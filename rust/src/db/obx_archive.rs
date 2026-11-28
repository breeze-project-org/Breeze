//! 迁移完成后压缩旧 ObjectBox 的 LMDB 数据。
//!
//! LMDB 采用 copy-on-write，文件只增不减，删除/更新大字段后会在 `data.mdb`
//! 内留下大量空闲页。SQLite 迁移成功后这些页已经没有运行时价值，但原始文件
//! 仍应保留一份可恢复副本，因此这里把它压成 7z：
//!
//! 1. 边压缩边计算原文件 MD5 与字节数（一次读取）；
//! 2. 写入临时 7z 并 fsync；
//! 3. 完整解压临时归档、重新计算 MD5，并核对大小；
//! 4. 校验全部通过后才替换正式归档并删除原 `data.mdb`。
//!
//! 任何一步失败都会保留原文件并清理临时归档，下次启动可以安全重试。
//! 已存在的归档也会先做完整校验；通过时直接删除原文件，避免重复压缩。
//!
//! 压缩路径不再先整文件算一遍 MD5 再读第二遍：`data.mdb` 动辄几百 MB，
//! 多读一次在移动设备上很贵。

use std::fs::{self, File};
use std::io::{self, BufReader, Read};
use std::path::Path;

use anyhow::{Context, Result, bail};
use md5::Context as Md5Context;
use sevenz_rust::{Password, SevenZArchiveEntry, SevenZReader, SevenZWriter};

pub const DATA_FILE: &str = "data.mdb";
pub const ARCHIVE_FILE: &str = "data.mdb.7z";
const ENTRY_NAME: &str = "data.mdb";
/// 哈希 / 解压校验的读写缓冲：256 KiB 足够摊薄系统调用，又不会占太多内存。
const HASH_BUFFER_SIZE: usize = 256 * 1024;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ArchiveStatus {
    /// 本次新压缩并删除了 data.mdb。
    Archived,
    /// 已有归档通过校验，只删除了 data.mdb。
    Reused,
    /// data.mdb 已不存在且归档存在，无需处理。
    AlreadyArchived,
}

impl ArchiveStatus {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Archived => "archived",
            Self::Reused => "reused",
            Self::AlreadyArchived => "already_archived",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ArchiveOutcome {
    pub status: ArchiveStatus,
    pub original_bytes: u64,
    pub archive_bytes: u64,
}

/// 把 `db_dir/data.mdb` 压缩为 `db_dir/data.mdb.7z`，校验成功后删除原文件。
pub fn archive_objectbox_data(db_dir: &Path) -> Result<ArchiveOutcome> {
    let data_path = db_dir.join(DATA_FILE);
    let archive_path = db_dir.join(ARCHIVE_FILE);

    if !data_path.exists() {
        if archive_path.exists() {
            return Ok(ArchiveOutcome {
                status: ArchiveStatus::AlreadyArchived,
                original_bytes: 0,
                archive_bytes: archive_size(&archive_path)?,
            });
        }
        bail!(
            "ObjectBox data file not found: {}",
            data_path.to_string_lossy()
        );
    }

    // 上次可能在「归档已写完、原文件未删」之间退出；先校验已有归档。
    // 这条路径必须先知道原文件摘要（校验已有归档要用它），所以只能单独算一次；
    // 校验不通过时会重新压缩，届时摘要来自流式压缩那一次读取。
    if archive_path.exists() {
        let original_bytes = fs::metadata(&data_path)
            .with_context(|| format!("stat {}", data_path.to_string_lossy()))?
            .len();
        let original_md5 = file_md5(&data_path)?;
        if verify_archive(&archive_path, &original_md5, original_bytes).is_ok() {
            ensure_unchanged(&data_path, &original_md5, original_bytes)?;
            remove_data_file(&data_path)?;
            let archive_bytes = archive_size(&archive_path)?;
            return Ok(ArchiveOutcome {
                status: ArchiveStatus::Reused,
                original_bytes,
                archive_bytes,
            });
        }
        fs::remove_file(&archive_path).with_context(|| {
            format!("remove invalid archive {}", archive_path.to_string_lossy())
        })?;
    }

    let temp_path = archive_path.with_extension("7z.tmp");
    let _ = fs::remove_file(&temp_path);

    // 压缩 + 哈希一次读完：返回的 (字节数, MD5) 描述的就是归档里的内容。
    let (original_bytes, original_md5) = match write_archive(&data_path, &temp_path) {
        Ok(hashed) => hashed,
        Err(error) => {
            let _ = fs::remove_file(&temp_path);
            return Err(error);
        }
    };

    // 压缩期间原文件不应再被写入；删除前再核对一次，防止归档到混合内容。
    if let Err(error) = verify_archive(&temp_path, &original_md5, original_bytes) {
        let _ = fs::remove_file(&temp_path);
        return Err(error).with_context(|| {
            format!(
                "archive verification failed, keeping {}",
                data_path.to_string_lossy()
            )
        });
    }

    if archive_path.exists() {
        fs::remove_file(&archive_path)
            .with_context(|| format!("remove old archive {}", archive_path.to_string_lossy()))?;
    }
    fs::rename(&temp_path, &archive_path).with_context(|| {
        format!(
            "rename {} -> {}",
            temp_path.to_string_lossy(),
            archive_path.to_string_lossy()
        )
    })?;
    sync_parent_dir(&archive_path);

    ensure_unchanged(&data_path, &original_md5, original_bytes)?;
    let archive_bytes = archive_size(&archive_path)?;
    remove_data_file(&data_path)?;

    Ok(ArchiveOutcome {
        status: ArchiveStatus::Archived,
        original_bytes,
        archive_bytes,
    })
}

/// 边读边算 MD5 与字节数的读取包装：压缩与摘要共用一次磁盘读取。
struct HashingReader<R> {
    inner: R,
    md5: Md5Context,
    bytes: u64,
}

impl<R> HashingReader<R> {
    fn new(inner: R) -> Self {
        Self {
            inner,
            md5: Md5Context::new(),
            bytes: 0,
        }
    }

    /// 消费掉内部状态，返回 `(MD5, 字节数)`。
    fn finish(self) -> ([u8; 16], u64) {
        (self.md5.finalize().0, self.bytes)
    }
}

impl<R: Read> Read for HashingReader<R> {
    fn read(&mut self, buf: &mut [u8]) -> io::Result<usize> {
        let read = self.inner.read(buf)?;
        if read > 0 {
            self.md5.consume(&buf[..read]);
            self.bytes += read as u64;
        }
        Ok(read)
    }
}

/// 压缩 `data_path` 到 `temp_path`，同时返回原文件的字节数与 MD5。
fn write_archive(data_path: &Path, temp_path: &Path) -> Result<(u64, [u8; 16])> {
    let source =
        File::open(data_path).with_context(|| format!("open {}", data_path.to_string_lossy()))?;
    let mut source = HashingReader::new(BufReader::with_capacity(HASH_BUFFER_SIZE, source));
    let mut entry = SevenZArchiveEntry::new();
    entry.name = ENTRY_NAME.to_string();
    let mut writer = SevenZWriter::create(temp_path)
        .with_context(|| format!("create archive {}", temp_path.to_string_lossy()))?;
    writer
        .push_archive_entry(entry, Some(&mut source))
        .with_context(|| format!("compress {}", data_path.to_string_lossy()))?;
    let file = writer
        .finish()
        .with_context(|| format!("finish archive {}", temp_path.to_string_lossy()))?;
    file.sync_all()
        .with_context(|| format!("sync archive {}", temp_path.to_string_lossy()))?;
    // 压缩已经把 `source` 读到底；这里取出同一次读取得到的摘要。
    let (md5, bytes) = source.finish();
    Ok((bytes, md5))
}

/// 完整读取归档并校验唯一 entries、大小与 MD5。
fn verify_archive(path: &Path, expected_md5: &[u8; 16], expected_size: u64) -> Result<()> {
    let mut reader = SevenZReader::open(path, Password::empty())
        .with_context(|| format!("open 7z archive {}", path.to_string_lossy()))?;
    let mut ctx = Md5Context::new();
    let mut entry_count = 0usize;
    let mut size = 0u64;
    let mut buf = vec![0u8; HASH_BUFFER_SIZE];

    reader
        .for_each_entries(|entry, input| {
            entry_count += 1;
            if entry_count > 1 {
                return Err(sevenz_rust::Error::other("unexpected extra archive entry"));
            }
            if entry.is_directory() || !entry.has_stream() || entry.name() != ENTRY_NAME {
                return Err(sevenz_rust::Error::other(format!(
                    "unexpected archive entry: {}",
                    entry.name()
                )));
            }
            // 手工循环而不是 `io::copy`：后者的默认缓冲只有 8 KiB，
            // 对几百 MB 的归档太小。
            loop {
                let read = input.read(&mut buf).map_err(sevenz_rust::Error::io)?;
                if read == 0 {
                    break;
                }
                size += read as u64;
                ctx.consume(&buf[..read]);
            }
            Ok(true)
        })
        .with_context(|| format!("decompress 7z archive {}", path.to_string_lossy()))?;

    if entry_count != 1 {
        bail!(
            "archive {} contains {} entries, expected 1",
            path.to_string_lossy(),
            entry_count
        );
    }
    if size != expected_size {
        bail!(
            "archive {} size mismatch: {} != {}",
            path.to_string_lossy(),
            size,
            expected_size
        );
    }
    let actual_md5 = ctx.finalize().0;
    if actual_md5 != *expected_md5 {
        bail!(
            "archive {} MD5 mismatch: {:x} != {:x}",
            path.to_string_lossy(),
            md5::Digest(actual_md5),
            md5::Digest(*expected_md5)
        );
    }
    Ok(())
}

fn file_md5(path: &Path) -> Result<[u8; 16]> {
    let mut file = File::open(path).with_context(|| format!("open {}", path.to_string_lossy()))?;
    let mut ctx = Md5Context::new();
    let mut buf = vec![0u8; HASH_BUFFER_SIZE];
    loop {
        let read = file
            .read(&mut buf)
            .with_context(|| format!("read {}", path.to_string_lossy()))?;
        if read == 0 {
            break;
        }
        ctx.consume(&buf[..read]);
    }
    Ok(ctx.finalize().0)
}

/// 删除原文件前确认它没有被再次写入。
///
/// 先比大小：大小变了就没必要再读一遍整个文件算 MD5。
fn ensure_unchanged(path: &Path, expected_md5: &[u8; 16], expected_size: u64) -> Result<()> {
    let current = fs::metadata(path)
        .with_context(|| format!("stat {}", path.to_string_lossy()))?
        .len();
    if current != expected_size {
        bail!(
            "ObjectBox data changed while archiving, keeping {}",
            path.to_string_lossy()
        );
    }
    if file_md5(path)? != *expected_md5 {
        bail!(
            "ObjectBox data changed while archiving, keeping {}",
            path.to_string_lossy()
        );
    }
    Ok(())
}

fn remove_data_file(path: &Path) -> Result<()> {
    fs::remove_file(path)
        .with_context(|| format!("remove archived source {}", path.to_string_lossy()))?;
    sync_parent_dir(path);
    Ok(())
}

fn archive_size(path: &Path) -> Result<u64> {
    Ok(fs::metadata(path)
        .with_context(|| format!("stat {}", path.to_string_lossy()))?
        .len())
}

#[cfg(unix)]
fn sync_parent_dir(path: &Path) {
    if let Some(parent) = path.parent()
        && let Ok(dir) = File::open(parent)
    {
        let _ = dir.sync_all();
    }
}

#[cfg(not(unix))]
fn sync_parent_dir(_path: &Path) {}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::{SystemTime, UNIX_EPOCH};

    fn temp_dir(tag: &str) -> std::path::PathBuf {
        let stamp = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let dir = std::env::temp_dir().join(format!(
            "breeze_obx_archive_{tag}_{}_{stamp}",
            std::process::id()
        ));
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    fn sample_bytes() -> Vec<u8> {
        (0..(2 * 1024 * 1024))
            .map(|index| ((index * 31 + index / 97) % 251) as u8)
            .collect()
    }

    fn verify_file(path: &Path, bytes: &[u8]) {
        let digest = md5::compute(bytes);
        verify_archive(path, &digest.0, bytes.len() as u64).unwrap();
    }

    #[test]
    fn archives_verifies_and_removes_source() {
        let dir = temp_dir("roundtrip");
        let data_path = dir.join(DATA_FILE);
        let archive_path = dir.join(ARCHIVE_FILE);
        let bytes = sample_bytes();
        fs::write(&data_path, &bytes).unwrap();

        let outcome = archive_objectbox_data(&dir).unwrap();
        assert_eq!(outcome.status, ArchiveStatus::Archived);
        assert_eq!(outcome.original_bytes, bytes.len() as u64);
        assert!(!data_path.exists());
        assert!(archive_path.exists());
        assert!(outcome.archive_bytes > 0);
        assert!(outcome.archive_bytes < outcome.original_bytes);
        verify_file(&archive_path, &bytes);

        let again = archive_objectbox_data(&dir).unwrap();
        assert_eq!(again.status, ArchiveStatus::AlreadyArchived);
        assert_eq!(again.archive_bytes, outcome.archive_bytes);

        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn replaces_corrupt_existing_archive() {
        let dir = temp_dir("corrupt");
        let data_path = dir.join(DATA_FILE);
        let archive_path = dir.join(ARCHIVE_FILE);
        let bytes = sample_bytes();
        fs::write(&data_path, &bytes).unwrap();
        fs::write(&archive_path, b"not a 7z archive").unwrap();

        let outcome = archive_objectbox_data(&dir).unwrap();
        assert_eq!(outcome.status, ArchiveStatus::Archived);
        assert!(!data_path.exists());
        verify_file(&archive_path, &bytes);

        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn hashing_reader_tracks_digest_and_size_while_streaming() {
        let bytes = sample_bytes();
        let mut reader = HashingReader::new(BufReader::with_capacity(1024, bytes.as_slice()));
        // 故意用不规整的块大小读，模拟压缩器的读取节奏。
        let mut sink = Vec::new();
        let mut buf = [0u8; 777];
        loop {
            let read = reader.read(&mut buf).unwrap();
            if read == 0 {
                break;
            }
            sink.extend_from_slice(&buf[..read]);
        }
        let (digest, size) = reader.finish();
        assert_eq!(sink, bytes);
        assert_eq!(size, bytes.len() as u64);
        assert_eq!(digest, md5::compute(&bytes).0);
    }

    #[test]
    fn ensures_source_is_unchanged_before_removal() {
        let dir = temp_dir("unchanged");
        let data_path = dir.join(DATA_FILE);
        let bytes = b"history".to_vec();
        fs::write(&data_path, &bytes).unwrap();
        let digest = md5::compute(&bytes).0;

        ensure_unchanged(&data_path, &digest, bytes.len() as u64).unwrap();
        // 大小不同：不必再读文件就能判定已变化。
        let error = ensure_unchanged(&data_path, &digest, bytes.len() as u64 + 1).unwrap_err();
        assert!(format!("{error:#}").contains("changed"), "{error:#}");
        // 大小相同但内容不同。
        let error = ensure_unchanged(&data_path, &[0u8; 16], bytes.len() as u64).unwrap_err();
        assert!(format!("{error:#}").contains("changed"), "{error:#}");

        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn recompresses_when_source_changed_after_the_archive_was_written() {
        let dir = temp_dir("changed_source");
        let data_path = dir.join(DATA_FILE);
        let archive_path = dir.join(ARCHIVE_FILE);

        let first = sample_bytes();
        fs::write(&data_path, &first).unwrap();
        assert_eq!(
            archive_objectbox_data(&dir).unwrap().status,
            ArchiveStatus::Archived
        );
        verify_file(&archive_path, &first);

        // 上次写完归档但没删原文件、原文件又被改过：必须重新压缩新内容。
        let second: Vec<u8> = first.iter().rev().copied().collect();
        fs::write(&data_path, &second).unwrap();
        let outcome = archive_objectbox_data(&dir).unwrap();
        assert_eq!(outcome.status, ArchiveStatus::Archived);
        assert_eq!(outcome.original_bytes, second.len() as u64);
        assert!(!data_path.exists());
        verify_file(&archive_path, &second);

        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn keeps_source_when_archive_cannot_be_written() {
        let dir = temp_dir("failure");
        let data_path = dir.join(DATA_FILE);
        let archive_path = dir.join(ARCHIVE_FILE);
        fs::write(&data_path, b"history").unwrap();
        // 占住临时归档路径，让压缩写入失败。
        fs::create_dir(dir.join("data.mdb.7z.tmp")).unwrap();

        assert!(archive_objectbox_data(&dir).is_err());
        assert!(data_path.exists());
        assert!(!archive_path.exists());

        let _ = fs::remove_dir_all(&dir);
    }
}
