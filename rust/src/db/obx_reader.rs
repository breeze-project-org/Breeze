//! 直接读取 ObjectBox 的 LMDB 数据库，不依赖 `libobjectbox`。
//!
//! ObjectBox 在 LMDB 上定义了固定格式：
//! - object key：8/12 字节，prefix 编码 entity id，后跟 object id；
//! - object value：FlatBuffers 表，property id `p` 位于 vtable slot `p - 1`；
//! - meta key：前 4 字节为 0，key 低 4 字节为 entity id，value 是该 entity 的 schema。
//!
//! 这里只做「读取 + 解码」，不写 LMDB。格式细节与验证结论见
//! `objectbox-reader-src-0.1.0.zip` 内的参考实现（已在 ObjectBox core
//! 4.0.0/4.3.1/5.0.0/5.3.2 上对齐）。
//!
//! 解码输出使用数据库里的原始表示：date 为 Unix 毫秒整数，`List<String>`
//! 为 JSON 数组。迁移层再按目标 SQLite 列类型转换。
//!
//! 读取只开一个只读事务，schema 与对象共用它；对象扫描用 `SET_RANGE`
//! 定位到 `0x1800_0000` 开头的对象区间，`0x2000_0000` 起的索引键一个都不会碰。

use std::collections::{BTreeMap, HashMap};
use std::path::Path;

use anyhow::{Context, Result, bail};
use lmdb::{Cursor, Database, Environment, RoTransaction, Transaction};
use serde_json::{Map, Value};

const KIND_OBJECT_PREFIX: u32 = 0x1800_0000;

/// 对象区间的右边界（不含）：`0x1800_0000 .. 0x1C00_0000`。
const OBJECT_KEY_END: u32 = KIND_OBJECT_PREFIX | 0x0400_0000;

/// meta 行的 key 上界：所有 Meta key 都是 `[0, 0, 0, 0]` 开头，B+ 树里排在最前面。
const META_SCAN_END: [u8; 4] = [0, 0, 0, 1];
/// 对象区间的起点 / 终点（`0x1800_0000` / `0x1C00_0000` 的大端前缀）。
const OBJECT_SCAN_START: [u8; 4] = KIND_OBJECT_PREFIX.to_be_bytes();
const OBJECT_SCAN_END: [u8; 4] = OBJECT_KEY_END.to_be_bytes();

/// 只读映射的最小尺寸，避免小库映射过小。
const MIN_MAP_SIZE: u64 = 64 * 1024 * 1024;

const T_BOOL: u16 = 1;
const T_BYTE: u16 = 2;
const T_SHORT: u16 = 3;
const T_CHAR: u16 = 4;
const T_INT: u16 = 5;
const T_LONG: u16 = 6;
const T_FLOAT: u16 = 7;
const T_DOUBLE: u16 = 8;
const T_STRING: u16 = 9;
const T_DATE: u16 = 10;
const T_RELATION: u16 = 11;
const T_DATE_NANO: u16 = 12;
const T_FLEX: u16 = 13;
const T_BOOL_VECTOR: u16 = 22;
const T_BYTE_VECTOR: u16 = 23;
const T_SHORT_VECTOR: u16 = 24;
const T_CHAR_VECTOR: u16 = 25;
const T_INT_VECTOR: u16 = 26;
const T_LONG_VECTOR: u16 = 27;
const T_FLOAT_VECTOR: u16 = 28;
const T_DOUBLE_VECTOR: u16 = 29;
const T_STRING_VECTOR: u16 = 30;
const T_DATE_VECTOR: u16 = 31;
const T_DATE_NANO_VECTOR: u16 = 32;

#[derive(Debug, Clone)]
pub struct ObxProperty {
    pub id: u32,
    pub name: String,
    pub ty: u16,
}

#[derive(Debug, Clone)]
pub struct ObxEntity {
    pub id: u32,
    pub name: String,
    pub properties: Vec<ObxProperty>,
}

#[derive(Debug, Default)]
pub struct ObxSnapshot {
    pub entities: Vec<ObxEntity>,
    pub records: BTreeMap<String, Vec<Map<String, Value>>>,
    pub object_rows: u64,
    pub skipped_rows: u64,
}

fn parse_object_key(key: &[u8]) -> Option<(u32, u64)> {
    if key.len() != 8 && key.len() != 12 {
        return None;
    }
    let prefix = u32::from_be_bytes(key[0..4].try_into().ok()?);
    if prefix & 0xFC00_0000 != KIND_OBJECT_PREFIX {
        return None;
    }
    let entity_id = (prefix & 0x03FF_FFFC) >> 2;
    if entity_id == 0 {
        return None;
    }
    let object_id = match key.len() {
        8 => u32::from_be_bytes(key[4..8].try_into().ok()?) as u64,
        12 => u64::from_be_bytes(key[4..12].try_into().ok()?),
        _ => return None,
    };
    Some((entity_id, object_id))
}

fn parse_meta_entity_id(key: &[u8]) -> Option<u32> {
    if key.len() != 8 || key[0..4] != [0, 0, 0, 0] {
        return None;
    }
    Some(u32::from_be_bytes(key[4..8].try_into().ok()?))
}

/// 只读映射尺寸：按文件大小（至少 64 MiB）。
///
/// 不用 `saturating_mul(2)`：32 位虚拟地址空间本来就紧张，翻倍只会白白浪费
/// 甚至直接映射失败；文件本身已经够大时，按文件大小映射就足够。
fn map_size_for_file(file_len: u64) -> Result<usize> {
    usize::try_from(file_len.max(MIN_MAP_SIZE))
        .context("ObjectBox data file is too large to map on this platform")
}

fn open_env(db_dir: &Path) -> Result<Environment> {
    let data_path = db_dir.join("data.mdb");
    if !data_path.exists() {
        bail!(
            "ObjectBox database not found: {}",
            data_path.to_string_lossy()
        );
    }
    let file_len = std::fs::metadata(&data_path)
        .with_context(|| format!("stat {}", data_path.to_string_lossy()))?
        .len();
    let map_size = map_size_for_file(file_len)?;

    let mut builder = Environment::new();
    builder
        .set_flags(lmdb::EnvironmentFlags::READ_ONLY | lmdb::EnvironmentFlags::NO_LOCK)
        .set_map_size(map_size);
    builder
        .open(db_dir)
        .with_context(|| format!("open LMDB env {}", db_dir.to_string_lossy()))
}

// ---------------------------------------------------------------------------
// FlatBuffers 最小读取器
// ---------------------------------------------------------------------------

fn read_slice<'a>(buf: &'a [u8], off: usize, len: usize, what: &str) -> Result<&'a [u8]> {
    let end = off
        .checked_add(len)
        .with_context(|| format!("{what}: offset overflow"))?;
    if end > buf.len() {
        bail!(
            "{what}: range {off}..{end} outside {}-byte buffer",
            buf.len()
        );
    }
    Ok(&buf[off..end])
}

macro_rules! read_num {
    ($name:ident, $ty:ty, $len:expr) => {
        fn $name(buf: &[u8], off: usize) -> Result<$ty> {
            let s = read_slice(buf, off, $len, stringify!($name))?;
            let mut a = [0u8; $len];
            a.copy_from_slice(s);
            Ok(<$ty>::from_le_bytes(a))
        }
    };
}

read_num!(read_u16, u16, 2);
read_num!(read_i16, i16, 2);
read_num!(read_u32, u32, 4);
read_num!(read_i32, i32, 4);
read_num!(read_i64, i64, 8);
read_num!(read_f32, f32, 4);
read_num!(read_f64, f64, 8);

fn read_u8(buf: &[u8], off: usize) -> Result<u8> {
    Ok(read_slice(buf, off, 1, "u8")?[0])
}

#[derive(Debug, Clone, Copy)]
struct Table<'a> {
    buf: &'a [u8],
    pos: usize,
    vtable: usize,
    vtable_len: usize,
}

impl<'a> Table<'a> {
    fn root(buf: &'a [u8]) -> Result<Self> {
        if buf.len() < 4 {
            bail!("buffer too short for a FlatBuffers root");
        }
        Self::at(buf, read_u32(buf, 0)? as usize)
    }

    fn at(buf: &'a [u8], pos: usize) -> Result<Self> {
        let soffset = read_i32(buf, pos)? as i64;
        let vtable = pos as i64 - soffset;
        if vtable < 0 {
            bail!("invalid negative vtable offset");
        }
        let vtable = vtable as usize;
        let vtable_len = read_u16(buf, vtable)? as usize;
        if vtable_len < 4 || !vtable_len.is_multiple_of(2) {
            bail!("invalid vtable length {vtable_len}");
        }
        read_slice(buf, vtable, vtable_len, "vtable")?;
        Ok(Self {
            buf,
            pos,
            vtable,
            vtable_len,
        })
    }

    fn field(&self, slot: usize) -> Result<Option<usize>> {
        let vtoff = slot
            .checked_mul(2)
            .and_then(|v| v.checked_add(4))
            .context("vtable slot overflow")?;
        if vtoff + 2 > self.vtable_len {
            return Ok(None);
        }
        let rel = read_u16(self.buf, self.vtable + vtoff)? as usize;
        if rel == 0 {
            return Ok(None);
        }
        let field = self.pos.checked_add(rel).context("field offset overflow")?;
        if field >= self.buf.len() {
            bail!("field {slot} offset outside buffer");
        }
        Ok(Some(field))
    }
}

fn read_string(buf: &[u8], field: usize) -> Result<String> {
    let p = field
        .checked_add(read_u32(buf, field)? as usize)
        .context("string offset overflow")?;
    let len = read_u32(buf, p)? as usize;
    let bytes = read_slice(buf, p + 4, len, "string")?;
    Ok(String::from_utf8_lossy(bytes).into_owned())
}

fn read_vector(buf: &[u8], field: usize) -> Result<(usize, usize)> {
    let p = field
        .checked_add(read_u32(buf, field)? as usize)
        .context("vector offset overflow")?;
    let count = read_u32(buf, p)? as usize;
    if count > buf.len() {
        bail!("vector count {count} exceeds buffer size");
    }
    Ok((p + 4, count))
}

fn read_string_vector(buf: &[u8], field: usize) -> Result<Vec<Value>> {
    let (start, count) = read_vector(buf, field)?;
    read_slice(buf, start, count.saturating_mul(4), "string vector")?;
    let mut out = Vec::with_capacity(count);
    for i in 0..count {
        let elem = start + i * 4;
        let rel = read_u32(buf, elem)? as usize;
        if rel == 0 {
            out.push(Value::Null);
            continue;
        }
        let p = elem
            .checked_add(rel)
            .context("string vector element offset overflow")?;
        let len = read_u32(buf, p)? as usize;
        let bytes = read_slice(buf, p + 4, len, "string vector element")?;
        out.push(Value::String(String::from_utf8_lossy(bytes).into_owned()));
    }
    Ok(out)
}

// ---------------------------------------------------------------------------
// schema meta 行
// ---------------------------------------------------------------------------

fn parse_property(buf: &[u8], pos: usize) -> Result<ObxProperty> {
    let table = Table::at(buf, pos)?;
    let id = read_u32(
        buf,
        table
            .field(1)?
            .context("native schema: missing property ID")?,
    )?;
    let name = read_string(
        buf,
        table
            .field(6)?
            .context("native schema: missing property name")?,
    )?;
    let ty = read_u16(
        buf,
        table
            .field(7)?
            .context("native schema: missing property type")?,
    )?;
    // ID 字段的 flags 在 slot 9；只用来确认 schema 合法性。
    let _flags = table
        .field(9)?
        .map(|f| read_u32(buf, f))
        .transpose()?
        .unwrap_or(0);
    if name.is_empty() {
        bail!("native schema: property ID {id} has an empty name");
    }
    if ty == 0 || ty > T_DATE_NANO_VECTOR {
        bail!("native schema: property {name:?} has unknown type {ty}");
    }
    Ok(ObxProperty { id, name, ty })
}

fn parse_entity(buf: &[u8], expected_id: u32) -> Result<ObxEntity> {
    let root = Table::root(buf)?;
    let name = read_string(
        buf,
        root.field(3)?
            .context("native schema: missing entity name")?,
    )?;
    if name.is_empty() {
        bail!("native schema: entity has an empty name");
    }
    let props_field = root
        .field(4)?
        .context("native schema: missing entity properties")?;
    let (start, count) = read_vector(buf, props_field)?;
    // 先确认属性表数组完整落在缓冲区里，再按 count 预分配：损坏的 count
    // 不能变成一次巨量内存申请。
    let byte_len = count
        .checked_mul(4)
        .context("native schema: entity properties overflow")?;
    read_slice(buf, start, byte_len, "entity properties")?;
    let mut properties = Vec::with_capacity(count);
    for i in 0..count {
        let elem = start + i * 4;
        let target = elem
            .checked_add(read_u32(buf, elem)? as usize)
            .context("property table offset overflow")?;
        properties.push(parse_property(buf, target)?);
    }
    properties.sort_by_key(|p| p.id);
    properties.dedup_by_key(|p| p.id);
    Ok(ObxEntity {
        id: expected_id,
        name,
        properties,
    })
}

/// schema 表 + meta 区间之后的第一条真实 key（对象扫描的 seek 起点）。
type SchemaScan<'txn> = (HashMap<u32, ObxEntity>, Option<&'txn [u8]>);

/// 读取 schema。Meta key 全部以 `[0, 0, 0, 0]` 开头，越过 `[0, 0, 0, 1]` 就结束。
///
/// 同时返回 meta 区间之后的第一条真实 key：对象扫描用它做 `SET_RANGE`
/// 定位，既跳过索引键，又不会在空区间上 seek。
fn load_schema<'txn>(txn: &'txn RoTransaction<'_>, db: Database) -> Result<SchemaScan<'txn>> {
    let mut cursor = txn.open_ro_cursor(db)?;
    let mut entities = HashMap::new();
    let mut next_key = None;
    for (key, value) in cursor.iter() {
        if key >= META_SCAN_END.as_slice() {
            next_key = Some(key);
            break;
        }
        let Some(entity_id) = parse_meta_entity_id(key) else {
            continue;
        };
        // key 0 是 platform model 行，没有 entity schema。
        if entity_id == 0 {
            continue;
        }
        let entity = parse_entity(value, entity_id)
            .with_context(|| format!("parse schema meta for entity id {entity_id}"))?;
        if entities.insert(entity.id, entity).is_some() {
            bail!("native schema: duplicate entity ID {entity_id}");
        }
    }
    if entities.is_empty() {
        bail!("no entity schemas found in ObjectBox meta rows");
    }
    Ok((entities, next_key))
}

// ---------------------------------------------------------------------------
// object value 解码
// ---------------------------------------------------------------------------

fn decode_value(prop: &ObxProperty, buf: &[u8], field: usize) -> Result<Value> {
    Ok(match prop.ty {
        T_BOOL => Value::Bool(read_u8(buf, field)? != 0),
        T_BYTE => Value::Number((read_u8(buf, field)? as i8 as i64).into()),
        T_SHORT => Value::Number((read_i16(buf, field)? as i64).into()),
        T_CHAR => Value::Number((read_u16(buf, field)? as u64).into()),
        T_INT => Value::Number((read_i32(buf, field)? as i64).into()),
        T_LONG | T_RELATION => Value::Number(read_i64(buf, field)?.into()),
        T_FLOAT => float_value(read_f32(buf, field)? as f64),
        T_DOUBLE => float_value(read_f64(buf, field)?),
        T_STRING => Value::String(read_string(buf, field)?),
        T_DATE | T_DATE_NANO => Value::Number(read_i64(buf, field)?.into()),
        T_FLEX | T_BYTE_VECTOR => {
            let (start, count) = read_vector(buf, field)?;
            let raw = read_slice(buf, start, count, "byte vector")?;
            Value::Array(raw.iter().map(|b| Value::from(*b)).collect())
        }
        T_BOOL_VECTOR => {
            let (start, count) = read_vector(buf, field)?;
            let raw = read_slice(buf, start, count, "bool vector")?;
            Value::Array(raw.iter().map(|b| Value::Bool(*b != 0)).collect())
        }
        T_SHORT_VECTOR => {
            let (start, count) = read_vector(buf, field)?;
            let raw = read_slice(buf, start, count.saturating_mul(2), "short vector")?;
            Value::Array(
                raw.as_chunks::<2>()
                    .0
                    .iter()
                    .map(|c| Value::from(i16::from_le_bytes(*c) as i64))
                    .collect(),
            )
        }
        T_CHAR_VECTOR => {
            let (start, count) = read_vector(buf, field)?;
            let raw = read_slice(buf, start, count.saturating_mul(2), "char vector")?;
            Value::Array(
                raw.as_chunks::<2>()
                    .0
                    .iter()
                    .map(|c| Value::from(u16::from_le_bytes(*c) as u64))
                    .collect(),
            )
        }
        T_INT_VECTOR => {
            let (start, count) = read_vector(buf, field)?;
            let raw = read_slice(buf, start, count.saturating_mul(4), "int vector")?;
            Value::Array(
                raw.as_chunks::<4>()
                    .0
                    .iter()
                    .map(|c| Value::from(i32::from_le_bytes(*c) as i64))
                    .collect(),
            )
        }
        T_LONG_VECTOR => {
            let (start, count) = read_vector(buf, field)?;
            let raw = read_slice(buf, start, count.saturating_mul(8), "long vector")?;
            Value::Array(
                raw.as_chunks::<8>()
                    .0
                    .iter()
                    .map(|c| Value::from(i64::from_le_bytes(*c)))
                    .collect(),
            )
        }
        T_FLOAT_VECTOR => {
            let (start, count) = read_vector(buf, field)?;
            let raw = read_slice(buf, start, count.saturating_mul(4), "float vector")?;
            Value::Array(
                raw.as_chunks::<4>()
                    .0
                    .iter()
                    .map(|c| float_value(f32::from_le_bytes(*c) as f64))
                    .collect(),
            )
        }
        T_DOUBLE_VECTOR => {
            let (start, count) = read_vector(buf, field)?;
            let raw = read_slice(buf, start, count.saturating_mul(8), "double vector")?;
            Value::Array(
                raw.as_chunks::<8>()
                    .0
                    .iter()
                    .map(|c| float_value(f64::from_le_bytes(*c)))
                    .collect(),
            )
        }
        T_STRING_VECTOR => Value::Array(read_string_vector(buf, field)?),
        T_DATE_VECTOR | T_DATE_NANO_VECTOR => {
            let (start, count) = read_vector(buf, field)?;
            let raw = read_slice(buf, start, count.saturating_mul(8), "date vector")?;
            Value::Array(
                raw.as_chunks::<8>()
                    .0
                    .iter()
                    .map(|c| Value::from(i64::from_le_bytes(*c)))
                    .collect(),
            )
        }
        other => bail!("unsupported property type {other} ({})", prop.name),
    })
}

fn float_value(v: f64) -> Value {
    if v.is_finite() {
        serde_json::Number::from_f64(v)
            .map(Value::Number)
            .unwrap_or(Value::Null)
    } else if v.is_nan() {
        Value::String("NaN".into())
    } else if v.is_sign_positive() {
        Value::String("Infinity".into())
    } else {
        Value::String("-Infinity".into())
    }
}

fn decode_object(entity: &ObxEntity, buf: &[u8], object_id: u64) -> Result<Map<String, Value>> {
    let table = Table::root(buf)?;
    let mut out = Map::new();
    for prop in &entity.properties {
        // `id` 一律用 LMDB key 里的 object id 覆盖，value 里那份不用解码。
        if prop.name == "id" {
            continue;
        }
        // vtable slot = property ID - 1（ID 字段本身也写在 value 里，
        // 但 LMDB key 中的 object id 才是权威值）。
        let Some(slot) = prop.id.checked_sub(1).map(|id| id as usize) else {
            bail!("entity {} property {} has ID 0", entity.name, prop.name);
        };
        let Some(field) = table.field(slot)? else {
            continue;
        };
        out.insert(prop.name.clone(), decode_value(prop, buf, field)?);
    }
    out.insert("id".to_string(), Value::Number(object_id.into()));

    // 对少数 ID 字段不叫 `id` 的实体（目前没有）保留原值即可。
    Ok(out)
}

// ---------------------------------------------------------------------------
// public API
// ---------------------------------------------------------------------------

pub fn read_objectbox_database(db_dir: &Path) -> Result<ObxSnapshot> {
    let env = open_env(db_dir)?;
    // `open_db` 自己开一个短事务；schema 与对象扫描共用下面这一个只读事务。
    let db = env.open_db(None)?;
    let txn = env.begin_ro_txn()?;
    let (entities, first_after_meta) = load_schema(&txn, db)?;

    // 按 entity id 分桶：避免每行都 clone entity.name、查一次 BTreeMap。
    let mut buckets: HashMap<u32, Vec<Map<String, Value>>> = HashMap::new();
    let mut object_rows = 0u64;
    let mut skipped_rows = 0u64;

    // 只扫描对象区间 `0x1800_0000 .. 0x1C00_0000`：索引键从 `0x2000_0000`
    // 起，落在终点之后，所以一个都不会被遍历（旧实现要扫全部索引行）。
    //
    // 定位用 `iter_from`，起点取「meta 区间之后的第一条真实 key」：
    // - 这条 key 一定存在，不会踩到 lmdb 0.8 的坑（`iter_from` 内部对
    //   MDB_SET_RANGE 的结果 `unwrap()`，起点越界会 panic）；
    // - 起点已经越过全部 schema 行；若它已到索引区间就直接跳过扫描。
    if let Some(start) = first_after_meta
        && start < OBJECT_SCAN_END.as_slice()
    {
        let mut cursor = txn.open_ro_cursor(db)?;
        for (key, value) in cursor.iter_from(start) {
            // 少数其它 key 种类可能落在 meta 与对象区间之间。
            if key < OBJECT_SCAN_START.as_slice() {
                continue;
            }
            if key >= OBJECT_SCAN_END.as_slice() {
                break;
            }
            // 只解析一次 key：结果同时给出 entity id / object id。
            let Some((entity_id, object_id)) = parse_object_key(key) else {
                skipped_rows += 1;
                continue;
            };
            let Some(entity) = entities.get(&entity_id) else {
                skipped_rows += 1;
                continue;
            };
            let record = decode_object(entity, value, object_id).with_context(|| {
                format!(
                    "decode {} id={} ({} bytes)",
                    entity.name,
                    object_id,
                    value.len()
                )
            })?;
            buckets.entry(entity_id).or_default().push(record);
            object_rows += 1;
        }
    }

    let mut records: BTreeMap<String, Vec<Map<String, Value>>> = BTreeMap::new();
    for (entity_id, mut rows) in buckets {
        let Some(entity) = entities.get(&entity_id) else {
            continue;
        };
        rows.sort_by_key(|record| record.get("id").and_then(Value::as_u64).unwrap_or(0));
        records.insert(entity.name.clone(), rows);
    }

    let mut entities: Vec<ObxEntity> = entities.into_values().collect();
    entities.sort_by_key(|e| e.id);

    Ok(ObxSnapshot {
        entities,
        records,
        object_rows,
        skipped_rows,
    })
}

#[cfg(test)]
mod tests {
    use std::collections::BTreeMap;

    use super::*;

    /// 用真实 App 数据库验证。需要手动指定：
    /// `BREEZE_OBJECTBOX_TEST_DB=D:/.../breeze_db cargo test --offline -- --ignored`
    #[test]
    #[ignore]
    fn reads_real_objectbox_db() {
        let dir = std::env::var("BREEZE_OBJECTBOX_TEST_DB")
            .expect("set BREEZE_OBJECTBOX_TEST_DB to the ObjectBox db directory");
        let snapshot = read_objectbox_database(Path::new(&dir)).unwrap();
        println!(
            "entities={} object_rows={} skipped={}",
            snapshot.entities.len(),
            snapshot.object_rows,
            snapshot.skipped_rows
        );
        for entity in &snapshot.entities {
            let count = snapshot
                .records
                .get(&entity.name)
                .map(Vec::len)
                .unwrap_or(0);
            println!("{} (id={}): {count}", entity.name, entity.id);
        }
        if let Some(rows) = snapshot.records.get("UnifiedComicHistory")
            && let Some(row) = rows.first()
        {
            println!("history0 keys: {:?}", row.keys().collect::<Vec<_>>());
            for key in [
                "id",
                "uniqueKey",
                "chapterId",
                "chapterOrder",
                "pageIndex",
                "lastReadAt",
                "deleted",
                "createdAt",
                "updatedAt",
            ] {
                println!("history0 {key} = {:?}", row.get(key));
            }
        }
        assert!(!snapshot.records.is_empty());
    }

    #[test]
    fn parses_object_keys() {
        assert_eq!(
            parse_object_key(&[0x18, 0x00, 0x00, 0x20, 0x00, 0x00, 0x00, 0x01]),
            Some((8, 1))
        );
        assert_eq!(
            parse_object_key(&[
                0x18, 0x00, 0x00, 0x20, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x02
            ]),
            Some((8, 0x1_0000_0002))
        );
        // 索引键（0x2000_0000 起）不属于对象区间，不能被当成对象。
        assert_eq!(
            parse_object_key(&[0x20, 0x00, 0x00, 0x04, 0, 0, 0, 0]),
            None
        );
        assert_eq!(
            parse_meta_entity_id(&[0x20, 0x00, 0x00, 0x04, 0, 0, 0, 0]),
            None
        );
    }

    #[test]
    fn meta_and_object_ranges_are_disjoint_and_ordered() {
        // Meta key 全部落在扫描终点之前，对象 / 索引键落在之后。
        assert_eq!(META_SCAN_END, [0, 0, 0, 1]);
        assert_eq!(OBJECT_SCAN_START, [0x18, 0x00, 0x00, 0x00]);
        assert_eq!(OBJECT_SCAN_END, [0x1C, 0x00, 0x00, 0x00]);
        assert!(META_SCAN_END.as_slice() <= OBJECT_SCAN_START.as_slice());
        assert!(OBJECT_SCAN_END.as_slice() < [0x20, 0, 0, 0].as_slice());

        // 对象区间覆盖所有 entity id 的对象键。
        let key = [0x1B, 0xFF, 0xFF, 0xFF, 0, 0, 0, 1];
        assert!(key.as_slice() >= OBJECT_SCAN_START.as_slice());
        assert!(key.as_slice() < OBJECT_SCAN_END.as_slice());
        let index_key = [0x20, 0, 0, 0, 0, 0, 0, 0];
        assert!(index_key.as_slice() >= OBJECT_SCAN_END.as_slice());
    }

    #[test]
    fn map_size_never_shrinks_below_the_floor() {
        assert_eq!(map_size_for_file(0).unwrap(), MIN_MAP_SIZE as usize);
        assert_eq!(map_size_for_file(1024).unwrap(), MIN_MAP_SIZE as usize);
        assert_eq!(
            map_size_for_file(96 * 1024 * 1024).unwrap(),
            96 * 1024 * 1024
        );
        #[cfg(target_pointer_width = "32")]
        assert!(map_size_for_file(1 << 40).is_err());
        #[cfg(target_pointer_width = "64")]
        assert_eq!(map_size_for_file(1 << 40).unwrap(), 1usize << 40);
    }

    #[test]
    fn parse_entity_rejects_a_corrupt_property_count_without_allocating() {
        // root table 在 32，vtable 在 4，name 在 48，属性向量在 100，
        // count 声称有 99 项（396 字节），远超剩余缓冲区。
        let mut buf = vec![0u8; 200];
        buf[0..4].copy_from_slice(&32u32.to_le_bytes());
        let vtable_pos = 4usize;
        let table_pos = 32usize;
        let vtable_len = 14u16;
        buf[vtable_pos..vtable_pos + 2].copy_from_slice(&vtable_len.to_le_bytes());
        buf[vtable_pos + 2..vtable_pos + 4].copy_from_slice(&4u16.to_le_bytes());
        let soffset = (table_pos - vtable_pos) as u32;
        buf[table_pos..table_pos + 4].copy_from_slice(&soffset.to_le_bytes());
        // slot 3: name, slot 4: properties
        let name_field = table_pos + 4;
        let props_field = table_pos + 8;
        buf[vtable_pos + 4 + 6..vtable_pos + 4 + 8]
            .copy_from_slice(&((name_field - table_pos) as u16).to_le_bytes());
        buf[vtable_pos + 4 + 8..vtable_pos + 4 + 10]
            .copy_from_slice(&((props_field - table_pos) as u16).to_le_bytes());
        buf[name_field..name_field + 4].copy_from_slice(&((48 - name_field) as u32).to_le_bytes());
        buf[48..52].copy_from_slice(&1u32.to_le_bytes());
        buf[52] = b'E';
        buf[props_field..props_field + 4]
            .copy_from_slice(&((100 - props_field) as u32).to_le_bytes());
        buf[100..104].copy_from_slice(&99u32.to_le_bytes());

        let error = parse_entity(&buf, 8).unwrap_err();
        let message = format!("{error:#}");
        assert!(message.contains("entity properties"), "{message}");
    }

    // -- 测试用的极简 FlatBuffers 写入器 ------------------------------------

    /// 只支持本模块读取所需的字段类型；布局按「前向」写，不追求真实
    /// FlatBuffers builder 的全部约束（读者只按偏移取值）。
    #[derive(Default, Clone)]
    struct TestTable {
        fields: BTreeMap<usize, TestField>,
    }

    #[derive(Clone)]
    enum TestField {
        U16(u16),
        U32(u32),
        I64(i64),
        Str(&'static str),
        Tables(Vec<TestTable>),
        I64s(Vec<i64>),
        Strs(Vec<&'static str>),
    }

    impl TestTable {
        fn new() -> Self {
            Self::default()
        }

        fn with(mut self, slot: usize, field: TestField) -> Self {
            self.fields.insert(slot, field);
            self
        }
    }

    /// 写入一张表，返回它在缓冲区中的位置。
    fn write_table(out: &mut Vec<u8>, table: &TestTable) -> usize {
        let max_slot = table.fields.keys().next_back().copied().unwrap_or(0);
        let vtable_len = 4 + 2 * (max_slot + 1);
        let vtable_pos = out.len();
        out.resize(vtable_pos + vtable_len, 0);
        out[vtable_pos..vtable_pos + 2].copy_from_slice(&(vtable_len as u16).to_le_bytes());
        out[vtable_pos + 2..vtable_pos + 4].copy_from_slice(&4u16.to_le_bytes());
        let table_pos = out.len();
        out.extend_from_slice(&[0u8; 4]);
        let soffset = (table_pos - vtable_pos) as i32;
        out[table_pos..table_pos + 4].copy_from_slice(&soffset.to_le_bytes());

        let mut deferred = Vec::new();
        for (slot, field) in &table.fields {
            let field_pos = out.len();
            let rel = (field_pos - table_pos) as u16;
            let entry = vtable_pos + 4 + 2 * slot;
            out[entry..entry + 2].copy_from_slice(&rel.to_le_bytes());
            match field {
                TestField::U16(v) => out.extend_from_slice(&v.to_le_bytes()),
                TestField::U32(v) => out.extend_from_slice(&v.to_le_bytes()),
                TestField::I64(v) => out.extend_from_slice(&v.to_le_bytes()),
                TestField::Str(_)
                | TestField::Tables(_)
                | TestField::I64s(_)
                | TestField::Strs(_) => {
                    out.extend_from_slice(&[0u8; 4]);
                    deferred.push((field_pos, field));
                }
            }
        }
        for (field_pos, field) in deferred {
            let data_pos = out.len();
            match field {
                TestField::Str(text) => {
                    out.extend_from_slice(&(text.len() as u32).to_le_bytes());
                    out.extend_from_slice(text.as_bytes());
                }
                TestField::Tables(tables) => {
                    // 真实 FlatBuffers 的向量元素是连续排列的（子表数据在数组之后）。
                    out.extend_from_slice(&(tables.len() as u32).to_le_bytes());
                    let elems_pos = out.len();
                    out.resize(elems_pos + tables.len() * 4, 0);
                    for (index, child) in tables.iter().enumerate() {
                        let child_pos = write_table(out, child);
                        let elem_pos = elems_pos + index * 4;
                        out[elem_pos..elem_pos + 4]
                            .copy_from_slice(&((child_pos - elem_pos) as u32).to_le_bytes());
                    }
                }
                // 定长元素向量：count + 原始小端字节。
                TestField::I64s(values) => {
                    out.extend_from_slice(&(values.len() as u32).to_le_bytes());
                    for value in values {
                        out.extend_from_slice(&value.to_le_bytes());
                    }
                }
                // 字符串向量：count + 每个元素的相对偏移，元素数据在数组之后。
                TestField::Strs(values) => {
                    out.extend_from_slice(&(values.len() as u32).to_le_bytes());
                    let elems_pos = out.len();
                    out.resize(elems_pos + values.len() * 4, 0);
                    for (index, text) in values.iter().enumerate() {
                        let elem_pos = elems_pos + index * 4;
                        let text_pos = out.len();
                        out.extend_from_slice(&(text.len() as u32).to_le_bytes());
                        out.extend_from_slice(text.as_bytes());
                        out[elem_pos..elem_pos + 4]
                            .copy_from_slice(&((text_pos - elem_pos) as u32).to_le_bytes());
                    }
                }
                TestField::U16(_) | TestField::U32(_) | TestField::I64(_) => unreachable!(),
            }
            out[field_pos..field_pos + 4]
                .copy_from_slice(&((data_pos - field_pos) as u32).to_le_bytes());
        }
        table_pos
    }

    fn finish_table(table: &TestTable) -> Vec<u8> {
        let mut out = vec![0u8; 4];
        let root = write_table(&mut out, table);
        out[0..4].copy_from_slice(&(root as u32).to_le_bytes());
        out
    }

    fn property(id: u32, name: &'static str, ty: u16) -> TestTable {
        TestTable::new()
            .with(1, TestField::U32(id))
            .with(6, TestField::Str(name))
            .with(7, TestField::U16(ty))
    }

    fn object_key(entity_id: u32, object_id: u32) -> [u8; 8] {
        let prefix = KIND_OBJECT_PREFIX | (entity_id << 2);
        let mut key = [0u8; 8];
        key[0..4].copy_from_slice(&prefix.to_be_bytes());
        key[4..8].copy_from_slice(&object_id.to_be_bytes());
        key
    }

    fn meta_key(entity_id: u32) -> [u8; 8] {
        let mut key = [0u8; 8];
        key[4..8].copy_from_slice(&entity_id.to_be_bytes());
        key
    }

    fn seed_env(dir: &Path, entries: Vec<([u8; 8], Vec<u8>)>) {
        let mut builder = Environment::new();
        builder.set_map_size(8 * 1024 * 1024).set_max_readers(16);
        let env = builder.open(dir).unwrap();
        let db = env.open_db(None).unwrap();
        {
            let mut txn = env.begin_rw_txn().unwrap();
            for (key, value) in &entries {
                txn.put(db, key, value, lmdb::WriteFlags::empty()).unwrap();
            }
            txn.commit().unwrap();
        }
    }

    fn temp_dir(tag: &str) -> std::path::PathBuf {
        let stamp = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let dir = std::env::temp_dir().join(format!(
            "breeze_obx_reader_{tag}_{}_{stamp}",
            std::process::id()
        ));
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn reads_schemas_and_objects_and_skips_index_keys() {
        let dir = temp_dir("scan");
        let comic = TestTable::new().with(3, TestField::Str("Comic")).with(
            4,
            TestField::Tables(vec![
                property(1, "id", T_LONG),
                property(2, "title", T_STRING),
                property(3, "pages", T_LONG),
                property(4, "tags", T_STRING_VECTOR),
                property(5, "scores", T_LONG_VECTOR),
            ]),
        );
        // `id` 声明成 T_STRING，并在对象里放一个越界的 slot 0：
        // 只有「跳过 id 属性」的实现才能解码成功。
        let weird = TestTable::new()
            .with(3, TestField::Str("Weird"))
            .with(4, TestField::Tables(vec![property(1, "id", T_STRING)]));
        let empty = TestTable::new()
            .with(3, TestField::Str("Empty"))
            .with(4, TestField::Tables(vec![property(1, "id", T_LONG)]));

        let object = |title: &'static str, pages: i64| -> Vec<u8> {
            finish_table(
                &TestTable::new()
                    .with(0, TestField::U32(0))
                    .with(1, TestField::Str(title))
                    .with(2, TestField::I64(pages))
                    .with(3, TestField::Strs(vec!["tag-a", "tag-b"]))
                    .with(4, TestField::I64s(vec![7, -1, 0])),
            )
        };

        let mut entries = vec![
            (
                meta_key(0),
                finish_table(&TestTable::new().with(3, TestField::Str("platform"))),
            ),
            (meta_key(8), finish_table(&comic)),
            (meta_key(9), finish_table(&weird)),
            (meta_key(10), finish_table(&empty)),
            (object_key(8, 2), object("second", 20)),
            (object_key(8, 1), object("first", 10)),
            // 未知 entity：计入 skipped。
            (object_key(12, 1), finish_table(&TestTable::new())),
            // Index 键：内容故意不是 FlatBuffers，扫描不应碰它。
            (
                [0x20, 0x00, 0x00, 0x04, 0, 0, 0, 0],
                b"not a flatbuffer".to_vec(),
            ),
        ];
        // Weird 的 slot 0 指向越界位置。
        let weird_object = finish_table(&TestTable::new().with(0, TestField::U32(0xFFFF_FFFF)));
        entries.push((object_key(9, 1), weird_object));
        seed_env(&dir, entries);

        let snapshot = read_objectbox_database(&dir).unwrap();
        assert_eq!(snapshot.entities.len(), 3);
        assert_eq!(
            snapshot
                .entities
                .iter()
                .map(|e| e.name.as_str())
                .collect::<Vec<_>>(),
            vec!["Comic", "Weird", "Empty"]
        );
        assert_eq!(snapshot.object_rows, 3);
        assert_eq!(snapshot.skipped_rows, 1, "未知 entity 的对象计入 skipped");
        assert!(
            !snapshot.records.contains_key("Empty"),
            "没有对象的 entity 不出现在结果里"
        );

        let rows = &snapshot.records["Comic"];
        assert_eq!(rows.len(), 2);
        assert_eq!(rows[0]["id"], Value::from(1));
        assert_eq!(rows[0]["title"], Value::from("first"));
        assert_eq!(rows[0]["pages"], Value::from(10));
        // 向量类型：字符串向量 / 定长元素向量都要按原始表示还原。
        assert_eq!(rows[0]["tags"], serde_json::json!(["tag-a", "tag-b"]));
        assert_eq!(rows[0]["scores"], serde_json::json!([7, -1, 0]));
        assert_eq!(rows[1]["id"], Value::from(2));
        assert_eq!(rows[1]["title"], Value::from("second"));

        // id 来自 key，value 里那一位根本没有解码。
        assert_eq!(
            snapshot.records["Weird"],
            vec![{
                let mut map = Map::new();
                map.insert("id".to_string(), Value::from(1));
                map
            }]
        );

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn empty_object_range_is_handled_without_panicking() {
        let dir = temp_dir("empty");
        let comic = TestTable::new()
            .with(3, TestField::Str("Comic"))
            .with(4, TestField::Tables(vec![property(1, "id", T_LONG)]));
        // 只有 meta 行 + index 行，没有任何对象。
        seed_env(
            &dir,
            vec![
                (meta_key(8), finish_table(&comic)),
                ([0x20, 0, 0, 4, 0, 0, 0, 1], b"index".to_vec()),
            ],
        );
        let snapshot = read_objectbox_database(&dir).unwrap();
        assert_eq!(snapshot.entities.len(), 1);
        assert_eq!(snapshot.object_rows, 0);
        assert_eq!(snapshot.skipped_rows, 0);
        assert!(snapshot.records.is_empty());
        let _ = std::fs::remove_dir_all(&dir);

        // 只有 schema 行、连索引行都没有：不能去 seek 一个不存在的起点。
        let dir = temp_dir("only_meta");
        seed_env(&dir, vec![(meta_key(8), finish_table(&comic))]);
        let snapshot = read_objectbox_database(&dir).unwrap();
        assert_eq!(snapshot.entities.len(), 1);
        assert_eq!(snapshot.object_rows, 0);
        assert!(snapshot.records.is_empty());
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn missing_schema_is_an_error() {
        let dir = temp_dir("no_schema");
        seed_env(&dir, vec![(meta_key(0), finish_table(&TestTable::new()))]);
        let error = read_objectbox_database(&dir).unwrap_err();
        assert!(format!("{error:#}").contains("no entity schemas"));
        let _ = std::fs::remove_dir_all(&dir);
    }
}
