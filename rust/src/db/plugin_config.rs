//! 插件配置持久化。
//!
//! 表结构：`"PluginConfig"("id", "name", "config")`，`config` 是一个 JSON 对象。
//! 这里负责与旧 Dart 实现一致的合并/读取语义，QJS 宿主路由和 Dart UI 共用：
//! - save 把 `key` 合并进配置对象，值先按 JSON 解析，失败则按原始字符串保存；
//! - load 读取 `key`，缺失时返回 fallback（同样先按 JSON 解析）；
//! - 空 `key` 表示整个配置对象；
//! - 配置内容不是合法 JSON 对象时按空对象处理。
//!
//! 读写直接走 `rusqlite`（不再把参数/结果包成 JSON 文本），整个读-改-写由
//! 连接互斥锁 + `BEGIN IMMEDIATE` 保证原子，因此不需要进程级全局锁。

use anyhow::{Context, Result};
use rusqlite::{Connection, OptionalExtension, params};
use serde_json::{Map, Value, json};

use crate::db::sql;

const SELECT_CONFIG_BY_NAME: &str =
    r#"SELECT "id", "config" FROM "PluginConfig" WHERE "name" = ? LIMIT 1"#;
const UPDATE_CONFIG_BY_ID: &str = r#"UPDATE "PluginConfig" SET "config" = ? WHERE "id" = ?"#;
const INSERT_CONFIG: &str = r#"INSERT INTO "PluginConfig" ("name", "config") VALUES (?, ?)"#;

/// QJS 宿主路由使用的应用主库句柄（Rust 侧自动解析，无需 Flutter 注册）。
pub(crate) fn app_handle() -> Result<i64> {
    sql::main_handle()
}

fn decode_object_map(raw: &str) -> Map<String, Value> {
    let text = raw.trim();
    if text.is_empty() {
        return Map::new();
    }
    match serde_json::from_str::<Value>(text) {
        Ok(Value::Object(map)) => map,
        _ => Map::new(),
    }
}

fn decode_maybe_json(value: &str) -> Value {
    let text = value.trim();
    if text.is_empty() {
        return Value::String(value.to_string());
    }
    serde_json::from_str(text).unwrap_or_else(|_| Value::String(value.to_string()))
}

fn query_config_row(conn: &Connection, name: &str) -> Result<Option<(i64, String)>> {
    conn.prepare_cached(SELECT_CONFIG_BY_NAME)
        .context("prepare PluginConfig select")?
        .query_row([name], |row| Ok((row.get(0)?, row.get(1)?)))
        .optional()
        .context("query PluginConfig")
}

/// 合并写入配置。空 `key` 只确保行存在，配置内容不变。
pub fn save_value(handle: i64, name: &str, key: &str, value: &str) -> Result<()> {
    let db = sql::get(handle)?;
    db.with_conn_write(|conn| save_on_connection(conn, name, key, value))
}

/// 读-改-写整体放进一次 `BEGIN IMMEDIATE`。
///
/// 连接互斥锁已经保证同库写入串行，再加上写事务，既能防止并发 save 互相覆盖，
/// 又不会像全局锁那样阻塞其他数据库。
fn save_on_connection(conn: &mut Connection, name: &str, key: &str, value: &str) -> Result<()> {
    // 调用方已处在事务中（例如 Dart 的批量写入）：跟着外层事务走，
    // 由它决定提交还是回滚。
    if !conn.is_autocommit() {
        return merge_config(conn, name, key, value);
    }
    conn.execute_batch("BEGIN IMMEDIATE")
        .context("begin PluginConfig transaction")?;
    match merge_config(conn, name, key, value).and_then(|()| {
        conn.execute_batch("COMMIT")
            .context("commit PluginConfig transaction")
    }) {
        Ok(()) => Ok(()),
        Err(error) => {
            if !conn.is_autocommit() {
                let _ = conn.execute_batch("ROLLBACK");
            }
            Err(error)
        }
    }
}

fn merge_config(conn: &Connection, name: &str, key: &str, value: &str) -> Result<()> {
    match query_config_row(conn, name)? {
        None => {
            let mut data = Map::new();
            if !key.is_empty() {
                data.insert(key.to_string(), decode_maybe_json(value));
            }
            let config = Value::Object(data).to_string();
            conn.prepare_cached(INSERT_CONFIG)
                .context("prepare PluginConfig insert")?
                .execute(params![name, config])
                .context("insert PluginConfig")?;
            Ok(())
        }
        Some((id, raw)) => {
            // 空 key 只保证行存在：已有的配置内容不需要解码、重新序列化再写回。
            if key.is_empty() {
                return Ok(());
            }
            let mut data = decode_object_map(&raw);
            let new_value = decode_maybe_json(value);
            if data.get(key) == Some(&new_value) {
                // 值没变（`config` 是合法 JSON 对象才会命中）：跳过 UPDATE，
                // 不产生写入和表变更广播。
                return Ok(());
            }
            data.insert(key.to_string(), new_value);
            let config = Value::Object(data).to_string();
            conn.prepare_cached(UPDATE_CONFIG_BY_ID)
                .context("prepare PluginConfig update")?
                .execute(params![config, id])
                .context("update PluginConfig")?;
            Ok(())
        }
    }
}

/// 读取配置。空 `key` 返回整个配置对象；缺失 key 返回解析后的 fallback。
pub fn load_value(handle: i64, name: &str, key: &str, fallback: &str) -> Result<Value> {
    let db = sql::get(handle)?;
    let data = db.with_conn_read(|conn| {
        Ok(query_config_row(conn, name)?
            .map(|(_, config)| decode_object_map(&config))
            .unwrap_or_default())
    })?;
    if key.is_empty() {
        Ok(Value::Object(data))
    } else {
        Ok(data
            .get(key)
            .cloned()
            .unwrap_or_else(|| decode_maybe_json(fallback)))
    }
}

/// 与旧 Dart bridge 完全一致的保存响应字符串。
pub fn save_response_string() -> String {
    r#"{"ok":true}"#.to_string()
}

/// 与旧 Dart bridge 完全一致的读取响应字符串。
pub fn load_response_string(value: Value) -> String {
    json!({ "ok": true, "value": value }).to_string()
}

#[cfg(test)]
mod tests {
    use std::path::PathBuf;
    use std::sync::atomic::{AtomicU64, Ordering};
    use std::sync::{Arc, Mutex};

    use super::*;

    static TEST_SEQ: AtomicU64 = AtomicU64::new(0);

    fn temp_db(name: &str) -> (i64, PathBuf) {
        let dir = std::env::temp_dir().join("breeze_plugin_config_tests");
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join(format!(
            "{name}_{}_{}.sqlite3",
            std::process::id(),
            TEST_SEQ.fetch_add(1, Ordering::SeqCst)
        ));
        let _ = std::fs::remove_file(&path);
        let handle = sql::open(path.to_str().unwrap()).unwrap();
        sql::get(handle)
            .unwrap()
            .execute_script(
                r#"CREATE TABLE "PluginConfig" (
                    "id" INTEGER PRIMARY KEY AUTOINCREMENT,
                    "name" TEXT NOT NULL DEFAULT '',
                    "config" TEXT NOT NULL DEFAULT ''
                )"#,
            )
            .unwrap();
        (handle, path)
    }

    fn envelope(raw: &str) -> Value {
        let value: Value = serde_json::from_str(raw).unwrap();
        assert_eq!(value["ok"], true);
        value
    }

    /// 订阅表变更广播，用来确认「没有写」时不会触发变更。
    fn watch(handle: i64) -> Arc<Mutex<Vec<Vec<String>>>> {
        let events = Arc::new(Mutex::new(Vec::<Vec<String>>::new()));
        let sink = events.clone();
        sql::get(handle)
            .unwrap()
            .bus
            .add_listener(Box::new(move |tables| {
                sink.lock().unwrap().push(tables);
            }));
        events
    }

    fn raw_config(handle: i64, name: &str) -> Option<String> {
        sql::get(handle)
            .unwrap()
            .with_conn_read(|conn| {
                conn.prepare_cached(SELECT_CONFIG_BY_NAME)?
                    .query_row([name], |row| row.get::<_, String>(1))
                    .optional()
                    .context("query raw config")
            })
            .unwrap()
    }

    #[test]
    fn save_and_load_roundtrip_matches_dart_semantics() {
        let (handle, path) = temp_db("roundtrip");
        save_value(handle, "plugin", "theme", r#""dark""#).unwrap();
        save_value(handle, "plugin", "meta", r#"{"a":1,"b":[true,null]}"#).unwrap();
        save_value(handle, "plugin", "raw", "not-json").unwrap();
        save_value(handle, "plugin", "blank", "   ").unwrap();

        assert_eq!(
            load_value(handle, "plugin", "theme", "null").unwrap(),
            json!("dark")
        );
        assert_eq!(
            load_value(handle, "plugin", "meta", "null").unwrap(),
            json!({"a": 1, "b": [true, null]})
        );
        assert_eq!(
            load_value(handle, "plugin", "raw", "null").unwrap(),
            json!("not-json")
        );
        assert_eq!(
            load_value(handle, "plugin", "blank", "null").unwrap(),
            json!("   ")
        );
        assert_eq!(
            load_value(handle, "plugin", "missing", r#"{"x":2}"#).unwrap(),
            json!({"x": 2})
        );
        assert_eq!(
            load_value(handle, "plugin", "", "null").unwrap(),
            json!({"theme": "dark", "meta": {"a": 1, "b": [true, null]}, "raw": "not-json", "blank": "   "})
        );

        let response = envelope(&load_response_string(
            load_value(handle, "plugin", "missing", r#""fallback""#).unwrap(),
        ));
        assert_eq!(response["value"], json!("fallback"));
        assert_eq!(save_response_string(), r#"{"ok":true}"#);

        sql::close(handle).unwrap();
        let _ = std::fs::remove_file(path);
    }

    #[test]
    fn concurrent_saves_do_not_lose_keys() {
        let (handle, path) = temp_db("concurrent");
        let mut threads = Vec::new();
        for i in 0..16 {
            threads.push(std::thread::spawn(move || {
                save_value(handle, "plugin", &format!("k{i}"), &i.to_string()).unwrap();
            }));
        }
        for thread in threads {
            thread.join().unwrap();
        }

        let config = load_value(handle, "plugin", "", "null").unwrap();
        let object = config.as_object().expect("config object");
        assert_eq!(object.len(), 16);
        for i in 0..16 {
            assert_eq!(object[&format!("k{i}")], json!(i));
        }

        sql::close(handle).unwrap();
        let _ = std::fs::remove_file(path);
    }

    #[test]
    fn empty_key_creates_row_without_changing_config() {
        let (handle, path) = temp_db("empty_key");
        save_value(handle, "plugin", "", "123").unwrap();

        assert_eq!(load_value(handle, "plugin", "", "null").unwrap(), json!({}));
        let rows = sql::get(handle)
            .unwrap()
            .query_json(r#"SELECT COUNT(*) AS c FROM "PluginConfig""#, "[]")
            .unwrap();
        assert_eq!(rows, r#"[{"c":1}]"#);

        sql::close(handle).unwrap();
        let _ = std::fs::remove_file(path);
    }

    #[test]
    fn malformed_existing_config_is_treated_as_empty() {
        let (handle, path) = temp_db("malformed");
        sql::get(handle)
            .unwrap()
            .execute(
                "INSERT INTO \"PluginConfig\" (\"name\", \"config\") VALUES (?, ?)",
                r#"["plugin","not a json object"]"#,
            )
            .unwrap();

        assert_eq!(load_value(handle, "plugin", "", "null").unwrap(), json!({}));
        save_value(handle, "plugin", "k", "7").unwrap();
        assert_eq!(
            load_value(handle, "plugin", "", "null").unwrap(),
            json!({"k": 7})
        );

        sql::close(handle).unwrap();
        let _ = std::fs::remove_file(path);
    }

    #[test]
    fn repeated_save_of_the_same_value_skips_the_update() {
        let (handle, path) = temp_db("noop_save");
        let events = watch(handle);

        save_value(handle, "plugin", "k", "1").unwrap();
        assert_eq!(events.lock().unwrap().len(), 1, "第一次写入需要落库并广播");
        let stored = raw_config(handle, "plugin").expect("row exists");

        // 同样的值再存一次：不写库、不广播（含多余空白）。
        save_value(handle, "plugin", "k", "1").unwrap();
        save_value(handle, "plugin", "k", " 1 ").unwrap();
        assert_eq!(
            raw_config(handle, "plugin").as_deref(),
            Some(stored.as_str())
        );
        assert_eq!(events.lock().unwrap().len(), 1, "重复写入不应触发变更");

        // 值变了（数字 1 -> 字符串 "1"）就必须写。
        save_value(handle, "plugin", "k", r#""1""#).unwrap();
        assert_eq!(events.lock().unwrap().len(), 2);
        assert_eq!(
            raw_config(handle, "plugin").as_deref(),
            Some(r#"{"k":"1"}"#)
        );
        save_value(handle, "plugin", "k", "2").unwrap();
        assert_eq!(events.lock().unwrap().len(), 3);
        assert_eq!(load_value(handle, "plugin", "k", "null").unwrap(), json!(2));

        sql::close(handle).unwrap();
        let _ = std::fs::remove_file(path);
    }

    #[test]
    fn empty_key_on_existing_row_does_not_write() {
        let (handle, path) = temp_db("empty_key_existing");
        let events = watch(handle);
        save_value(handle, "plugin", "k", "1").unwrap();
        let stored = raw_config(handle, "plugin").expect("row exists");

        save_value(handle, "plugin", "", "999").unwrap();
        assert_eq!(
            raw_config(handle, "plugin").as_deref(),
            Some(stored.as_str())
        );
        assert_eq!(events.lock().unwrap().len(), 1, "空 key 只需确保行存在");
        assert_eq!(
            load_value(handle, "plugin", "", "null").unwrap(),
            json!({"k": 1})
        );

        sql::close(handle).unwrap();
        let _ = std::fs::remove_file(path);
    }

    #[test]
    fn save_inside_a_caller_transaction_follows_its_commit_or_rollback() {
        let (handle, path) = temp_db("caller_tx");
        let tx = sql::begin(handle, true).unwrap();
        save_value(tx, "plugin", "k", "1").unwrap();
        assert_eq!(load_value(tx, "plugin", "k", "null").unwrap(), json!(1));
        // 事务没提交前主连接看不到。
        assert_eq!(
            load_value(handle, "plugin", "k", "null").unwrap(),
            Value::Null
        );
        sql::rollback(tx).unwrap();
        assert_eq!(
            load_value(handle, "plugin", "k", "null").unwrap(),
            Value::Null
        );

        let tx = sql::begin(handle, true).unwrap();
        save_value(tx, "plugin", "k", "2").unwrap();
        sql::commit(tx).unwrap();
        assert_eq!(load_value(handle, "plugin", "k", "null").unwrap(), json!(2));

        sql::close(handle).unwrap();
        let _ = std::fs::remove_file(path);
    }

    #[test]
    fn failed_save_rolls_back_its_own_transaction() {
        let (handle, path) = temp_db("failed_save");
        save_value(handle, "plugin", "k", "1").unwrap();
        let db = sql::get(handle).unwrap();

        // 让 UPDATE 失败：丢掉 config 列的表现等价于真实错误路径。
        db.execute_script(r#"ALTER TABLE "PluginConfig" RENAME COLUMN "config" TO "config_bak""#)
            .unwrap();
        let error = save_value(handle, "plugin", "k", "2").unwrap_err();
        assert!(format!("{error:#}").contains("config"), "{error:#}");
        // 事务已经回滚，连接回到 autocommit，可以继续使用。
        assert!(db.with_conn_read(|conn| Ok(conn.is_autocommit())).unwrap());

        sql::close(handle).unwrap();
        let _ = std::fs::remove_file(path);
    }
}
