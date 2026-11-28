//! 通用 SQL 执行层（第一层）。
//!
//! 不感知业务实体、不建表、不做 schema 映射。Dart 第二层传入原始 SQL +
//! JSON 参数数组，这里只负责：
//! - 主连接上的同步 SQL 执行（查询返回 JSON 数组）；
//! - 显式事务连接（`BEGIN IMMEDIATE` / `BEGIN`），支持异步调用之间的事务隔离；
//! - `update_hook` 表级变更通知，主连接和所有事务连接共享同一个 ChangeBus。
//!
//! 为什么事务要独立连接：Dart 侧全部异步，`begin` 与 `commit` 之间可能插入
//! 其他调用。如果共用主连接，别的语句会意外加入当前事务。独立连接让事务
//! 拥有自己的 SQLite 连接和锁，其他业务继续走主连接。
//!
//! 事务连接会放进池里复用：`begin` 不再每次都重新 `open` 文件、
//! 跑一遍 PRAGMA 并丢掉准备语句缓存。池只在 `Main` 句柄关闭时整体丢弃。
//!
//! SQLite 使用 `rusqlite` 的 `bundled` 特性，源码随 crate 编译；不链接系统
//! 预装的 sqlite3 动态库。

use std::collections::{BTreeMap, HashMap, HashSet};
use std::sync::atomic::{AtomicBool, AtomicI64, Ordering};
use std::sync::{Arc, LazyLock, Mutex, MutexGuard};

use anyhow::{Context, Result, anyhow, bail};
use base64::Engine;
use base64::engine::general_purpose::{GeneralPurpose, STANDARD};
use rusqlite::hooks::Action;
use rusqlite::types::ValueRef;
use rusqlite::{Connection, Statement, params_from_iter};
use serde_json::Value;

pub type ChangeListener = Box<dyn Fn(Vec<String>) + Send + Sync>;

/// 主连接的准备语句缓存条数：业务 SQL 形态多，128 条足够覆盖一轮常用语句。
const MAIN_STMT_CACHE: usize = 128;
/// 事务连接缓存条数：一个事务里通常只有几条语句。
const TX_STMT_CACHE: usize = 64;
/// 写事务连接最多缓存 1 条：写事务本身就是串行的。
const MAX_IDLE_WRITE_CONNS: usize = 1;
/// 读事务连接最多缓存 2 条：并发读常见，再多收益有限。
const MAX_IDLE_READ_CONNS: usize = 2;

const BASE64_STANDARD: GeneralPurpose = STANDARD;

static NEXT_HANDLE: AtomicI64 = AtomicI64::new(1);
static REGISTRY: LazyLock<Mutex<HashMap<i64, Arc<DbHandle>>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));

/// 事务提交后把去重后的表名广播给所有观察者。
#[derive(Default)]
pub struct ChangeBus {
    listeners: Mutex<Vec<Arc<ChangeListener>>>,
}

impl ChangeBus {
    pub fn add_listener(&self, listener: ChangeListener) {
        if let Ok(mut listeners) = self.listeners.lock() {
            listeners.push(Arc::new(listener));
        }
    }

    fn publish(&self, tables: Vec<String>) {
        if tables.is_empty() {
            return;
        }
        // 锁内只复制一次监听者列表；回调在锁外执行，监听者回头访问数据库
        // 也不会和发布路径互相卡死。
        let listeners: Vec<Arc<ChangeListener>> = match self.listeners.lock() {
            Ok(listeners) => listeners.clone(),
            Err(_) => return,
        };
        let Some((last, rest)) = listeners.split_last() else {
            return;
        };
        for listener in rest {
            listener(tables.clone());
        }
        // 最后一个监听者直接接管 tables，省掉一次拷贝。
        last(tables);
    }
}

/// 复用的事务连接：连接本身 + 它注册的 `update_hook` 写入的缓冲。
struct PooledConn {
    conn: Connection,
    stmt_pending: Arc<Mutex<HashSet<String>>>,
}

/// 主句柄持有的事务连接池。
///
/// 写连接与读连接分开，因为读连接打开时设了 `PRAGMA query_only=ON`，
/// 不能被写事务复用。
struct TxPool {
    closed: AtomicBool,
    write_idle: Mutex<Vec<PooledConn>>,
    read_idle: Mutex<Vec<PooledConn>>,
}

impl TxPool {
    fn new() -> Self {
        Self {
            closed: AtomicBool::new(false),
            write_idle: Mutex::new(Vec::new()),
            read_idle: Mutex::new(Vec::new()),
        }
    }

    fn is_closed(&self) -> bool {
        self.closed.load(Ordering::SeqCst)
    }

    fn idle(&self, write: bool) -> &Mutex<Vec<PooledConn>> {
        if write {
            &self.write_idle
        } else {
            &self.read_idle
        }
    }

    fn take(&self, write: bool) -> Result<Option<PooledConn>> {
        // 快速路径：池已关时不必再摸空闲表。
        if self.is_closed() {
            return Ok(None);
        }
        // 池锁只保护 Vec，不做任何 IO；毒化时退化为「不复用」而不是报错。
        let Ok(mut idle) = self.idle(write).lock() else {
            return Ok(None);
        };
        // 持锁复查：`close()` 先置 closed 再清空空闲表，所以这里查到的
        // closed 一定排除了「连接已经被丢弃、却又被取出去用」的情况。
        if self.is_closed() {
            return Ok(None);
        }
        Ok(idle.pop())
    }

    fn release(&self, write: bool, conn: PooledConn) {
        // 快速路径：池已关时绝大多数归还都挡在锁外。
        if self.is_closed() {
            return;
        }
        let capacity = if write {
            MAX_IDLE_WRITE_CONNS
        } else {
            MAX_IDLE_READ_CONNS
        };
        let Ok(mut idle) = self.idle(write).lock() else {
            return;
        };
        // 持锁复查：`close()` 以 SeqCst 置 closed 之后才清空空闲表，因此
        // 这里看到的 closed 意味着 close 的清空动作要么已经发生、要么会在
        // 本锁释放后发生；两种情况下都不能再 push（否则这条连接会被漏掉，
        // 一直握着文件句柄）。
        if self.is_closed() || idle.len() >= capacity {
            return;
        }
        idle.push(conn);
    }

    /// 关闭池：先标记关闭，再丢弃所有空闲连接。
    ///
    /// 调用方必须在 WAL checkpoint 之前调用，否则空闲连接还握着的文件句柄
    /// 会让截断失败（Windows 上尤其明显）。
    fn close(&self) {
        self.closed.store(true, Ordering::SeqCst);
        if let Ok(mut idle) = self.write_idle.lock() {
            idle.clear();
        }
        if let Ok(mut idle) = self.read_idle.lock() {
            idle.clear();
        }
    }
}

enum HandleKind {
    /// 应用主连接：autocommit 下每条成功语句都会直接发布表变更。
    Main { pool: Arc<TxPool> },
    /// 显式事务：独立连接，`COMMIT` 成功后才发布。
    Tx {
        finished: AtomicBool,
        write: bool,
        pool: Arc<TxPool>,
    },
}

pub struct DbHandle {
    pub id: i64,
    pub path: String,
    pub bus: Arc<ChangeBus>,
    conn: Mutex<Option<Connection>>,
    /// 当前语句由 `update_hook` 写入的表名；语句失败或事务回滚时清空。
    stmt_pending: Arc<Mutex<HashSet<String>>>,
    /// 事务级累计表名：`Tx` 在 COMMIT 后发布；主连接用于显式 BEGIN 的脚本。
    tx_pending: Arc<Mutex<HashSet<String>>>,
    kind: HandleKind,
}

impl DbHandle {
    fn open_main(id: i64, path: &str) -> Result<Self> {
        let bus = Arc::new(ChangeBus::default());
        let (mut conn, stmt_pending) = open_connection(path, false, MAIN_STMT_CACHE)?;
        // auto_vacuum / journal_mode 是写进数据库头的库级设置，主连接
        // 打开时执行一次即可；事务连接不必每次建连都再检查一遍。
        conn.execute_batch(
            "PRAGMA auto_vacuum=INCREMENTAL;
             PRAGMA journal_mode=WAL;",
        )
        .context("configure SQLite database")?;
        let tx_pending = new_pending();
        attach_rollback_hook(&mut conn, [stmt_pending.clone(), tx_pending.clone()])
            .context("register SQLite rollback hook")?;
        Ok(Self {
            id,
            path: path.to_string(),
            bus,
            conn: Mutex::new(Some(conn)),
            stmt_pending,
            tx_pending,
            kind: HandleKind::Main {
                pool: Arc::new(TxPool::new()),
            },
        })
    }

    fn open_tx(id: i64, main: &DbHandle, write: bool) -> Result<Self> {
        let HandleKind::Main { pool } = &main.kind else {
            bail!("cannot begin a transaction from handle {}", main.id);
        };
        let pool = pool.clone();
        if pool.is_closed() {
            bail!("database handle {} is closed", main.id);
        }
        // 优先复用空闲连接：省掉 open + PRAGMA + 准备语句缓存重建。
        let (mut conn, stmt_pending) = match pool.take(write)? {
            Some(pooled) => (pooled.conn, pooled.stmt_pending),
            None => open_connection(&main.path, !write, TX_STMT_CACHE)?,
        };
        // 只读事务保持 DEFERRED：快照在第一条真实读语句时建立，
        // 不提前占住读锁、不阻塞 WAL checkpoint。
        if let Err(error) = conn
            .execute_batch(if write { "BEGIN IMMEDIATE" } else { "BEGIN" })
            .context("begin SQLite transaction")
        {
            // BEGIN 没成功：连接还干净、池也没关时退回池里，否则直接丢弃。
            if conn.is_autocommit() && !pool.is_closed() {
                pool.release(write, PooledConn { conn, stmt_pending });
            }
            return Err(error);
        }
        let tx_pending = new_pending();
        if write {
            // 只读连接设了 `query_only=ON`、也没注册 `update_hook`，不会攒下
            // 待发布的表名；给它们挂 rollback_hook 只是白留一份 Arc。
            attach_rollback_hook(&mut conn, [stmt_pending.clone(), tx_pending.clone()])
                .context("register SQLite rollback hook")?;
        }
        Ok(Self {
            id,
            path: main.path.clone(),
            bus: main.bus.clone(),
            conn: Mutex::new(Some(conn)),
            stmt_pending,
            tx_pending,
            kind: HandleKind::Tx {
                finished: AtomicBool::new(false),
                write,
                pool,
            },
        })
    }

    pub fn query_json(&self, sql: &str, params_json: &str) -> Result<String> {
        let params = parse_params(params_json)?;
        self.with_conn(|conn| query_json_streamed(conn, sql, &params))
    }

    /// 执行单条语句。返回 `{"changes": n, "lastInsertId": id}`。
    pub fn execute(&self, sql: &str, params_json: &str) -> Result<String> {
        let params = parse_params(params_json)?;
        let (changes, last_id) = self.with_conn(|conn| {
            let mut stmt = conn
                .prepare_cached(sql)
                .with_context(|| format!("prepare SQL: {sql}"))?;
            let changes = stmt
                .execute(params_from_iter(params.iter()))
                .with_context(|| format!("execute SQL: {sql}"))?;
            Ok((changes, conn.last_insert_rowid()))
        })?;
        // 直接拼字符串：这两个字段名固定，没必要建 serde_json map。
        Ok(format!(
            r#"{{"changes":{changes},"lastInsertId":{last_id}}}"#
        ))
    }

    /// 执行多条语句（DDL / 迁移脚本），不返回结果集。
    pub fn execute_script(&self, sql: &str) -> Result<()> {
        self.with_conn(|conn| {
            conn.execute_batch(sql)
                .with_context(|| format!("execute SQL script: {sql}"))
        })
    }

    /// 只读访问连接：给 `plugin_config` 之类的同 crate 调用方直接使用 `rusqlite`。
    ///
    /// 与 [`Self::query_json`] 一样负责语句残留清理与表变更发布。
    pub(crate) fn with_conn_read<F, T>(&self, f: F) -> Result<T>
    where
        F: FnOnce(&Connection) -> Result<T>,
    {
        self.with_conn(|conn| f(conn))
    }

    /// 可写访问连接：闭包内可以直接 `BEGIN` / `COMMIT` 做更细的原子操作。
    pub(crate) fn with_conn_write<F, T>(&self, f: F) -> Result<T>
    where
        F: FnOnce(&mut Connection) -> Result<T>,
    {
        self.with_conn(f)
    }

    /// 统一「加锁 → 执行 → 收尾」流程。
    ///
    /// 收尾必须在连接锁内完成：表名只在语句成功后才有资格进入发布路径，
    /// 否则并发的主库写入会把未提交 / 已失败的语句表名广播出去。
    fn with_conn<F, T>(&self, f: F) -> Result<T>
    where
        F: FnOnce(&mut Connection) -> Result<T>,
    {
        self.ensure_active()?;
        let (value, publish) = {
            let mut guard = self.lock_conn()?;
            let Some(conn) = guard.as_mut() else {
                bail!("database handle {} is closed", self.id);
            };
            // 上一条语句可能触发过 update_hook 之后才失败（约束冲突等），
            // 这里先清空残留，保证本次成功只广播本次的语句。
            clear_pending(&self.stmt_pending);
            let value = match f(conn) {
                Ok(value) => value,
                Err(error) => {
                    clear_pending(&self.stmt_pending);
                    return Err(error);
                }
            };
            let publish = self.collect_pending(conn);
            (value, publish)
        };
        if let Some(tables) = publish {
            // 连接锁已释放，监听者可以安全地再访问数据库。
            self.bus.publish(tables);
        }
        Ok(value)
    }

    /// 语句成功后处理表名：主连接 autocommit 下直接返回待发布列表，
    /// 事务连接（或主连接上的显式 BEGIN）先累计到 `tx_pending`。
    fn collect_pending(&self, conn: &Connection) -> Option<Vec<String>> {
        match &self.kind {
            HandleKind::Main { .. } => {
                if !conn.is_autocommit() {
                    // 迁移脚本里的显式 BEGIN：等提交语句执行完再一起发。
                    merge_pending(&self.stmt_pending, &self.tx_pending);
                    return None;
                }
                let mut tables = take_pending(&self.stmt_pending);
                tables.extend(take_pending(&self.tx_pending));
                tables.sort();
                tables.dedup();
                if tables.is_empty() {
                    None
                } else {
                    Some(tables)
                }
            }
            HandleKind::Tx { .. } => {
                merge_pending(&self.stmt_pending, &self.tx_pending);
                None
            }
        }
    }

    pub fn commit(&self) -> Result<()> {
        let HandleKind::Tx {
            finished,
            write,
            pool,
        } = &self.kind
        else {
            bail!("handle {} is not a transaction", self.id);
        };
        if finished.swap(true, Ordering::SeqCst) {
            bail!("transaction {} already finished", self.id);
        }
        let (result, connection) = {
            // COMMIT 与失败后的 ROLLBACK 必须在同一把锁里完成，
            // 否则别的线程可能在这个连接上插进新语句。
            let mut guard = self.lock_conn()?;
            let Some(conn) = guard.as_mut() else {
                clear_pending(&self.stmt_pending);
                clear_pending(&self.tx_pending);
                return Err(anyhow!("transaction {} is already closed", self.id));
            };
            let result = conn
                .execute_batch("COMMIT")
                .context("commit SQLite transaction");
            if result.is_err() && !conn.is_autocommit() {
                // COMMIT 失败时事务可能仍然开着；立刻回滚，避免连接和
                // WAL 快照泄漏。
                let _ = conn.execute_batch("ROLLBACK");
            }
            // 连接从槽里取出，锁外再决定复用还是丢弃。
            let connection = guard.take();
            (result, connection)
        };
        clear_pending(&self.stmt_pending);
        self.recycle_connection(*write, pool, connection);
        match result {
            Ok(()) => {
                let tables = take_pending(&self.tx_pending);
                if !tables.is_empty() {
                    self.bus.publish(tables);
                }
                Ok(())
            }
            Err(error) => {
                clear_pending(&self.tx_pending);
                Err(error)
            }
        }
    }

    pub fn rollback(&self) -> Result<()> {
        let HandleKind::Tx {
            finished,
            write,
            pool,
        } = &self.kind
        else {
            bail!("handle {} is not a transaction", self.id);
        };
        if finished.swap(true, Ordering::SeqCst) {
            return Ok(());
        }
        let connection = {
            let mut guard = self.lock_conn()?;
            if let Some(conn) = guard.as_mut()
                && !conn.is_autocommit()
            {
                let _ = conn.execute_batch("ROLLBACK");
            }
            guard.take()
        };
        clear_pending(&self.stmt_pending);
        clear_pending(&self.tx_pending);
        self.recycle_connection(*write, pool, connection);
        Ok(())
    }

    /// 事务连接收尾后归还池：只有回到 autocommit 且池未关闭才能复用，
    /// 否则直接 Drop（顺带释放文件句柄）。
    fn recycle_connection(&self, write: bool, pool: &TxPool, conn: Option<Connection>) {
        let Some(mut conn) = conn else {
            return;
        };
        if !conn.is_autocommit() || pool.is_closed() {
            return;
        }
        if write {
            // rollback_hook 捕获了本次事务的 `stmt_pending` / `tx_pending`；
            // 不摘掉的话，空闲在池里的连接会一直让这两个 HashSet 存活。
            // 下次 begin 会为当前事务重新注册。
            let _ = conn.rollback_hook(None::<fn()>);
        }
        pool.release(
            write,
            PooledConn {
                conn,
                stmt_pending: self.stmt_pending.clone(),
            },
        );
    }

    pub fn close(&self) -> Result<()> {
        match &self.kind {
            HandleKind::Tx { .. } => {
                self.rollback()?;
            }
            HandleKind::Main { pool } => {
                // 先关池再 checkpoint：空闲事务连接还握着 SQLite 数据库 /
                // WAL 文件的句柄，在 Windows 上会阻塞 WAL 截断，也让 close
                // 之后文件继续被占用。
                pool.close();
                let mut guard = self.lock_conn()?;
                if let Some(conn) = guard.as_mut() {
                    // 关闭前刷新查询规划器统计信息；analysis_limit 限制单表采样量，
                    // 避免大表拖慢退出。失败不影响关闭。
                    let _ = conn.execute_batch("PRAGMA analysis_limit=400; PRAGMA optimize;");
                    let _ = conn.execute_batch("PRAGMA wal_checkpoint(TRUNCATE);");
                }
                // 立即释放主连接的句柄。
                let _ = guard.take();
            }
        }
        Ok(())
    }

    /// 已结束的事务、已关闭的连接都不再接受语句。
    fn ensure_active(&self) -> Result<()> {
        match &self.kind {
            HandleKind::Main { .. } => Ok(()),
            HandleKind::Tx { finished, .. } => {
                if finished.load(Ordering::SeqCst) {
                    bail!("transaction {} already finished", self.id);
                }
                Ok(())
            }
        }
    }

    fn lock_conn(&self) -> Result<MutexGuard<'_, Option<Connection>>> {
        self.conn
            .lock()
            .map_err(|_| anyhow!("database handle {} lock poisoned", self.id))
    }
}

fn new_pending() -> Arc<Mutex<HashSet<String>>> {
    Arc::new(Mutex::new(HashSet::new()))
}

fn clear_pending(pending: &Arc<Mutex<HashSet<String>>>) {
    if let Ok(mut pending) = pending.lock() {
        pending.clear();
    }
}

/// 取出去重并排序后的表名；锁毒化时返回空列表（不阻塞后续流程）。
fn take_pending(pending: &Arc<Mutex<HashSet<String>>>) -> Vec<String> {
    let mut pending = match pending.lock() {
        Ok(pending) => pending,
        Err(_) => return Vec::new(),
    };
    let mut tables: Vec<String> = pending.drain().collect();
    tables.sort();
    tables
}

fn merge_pending(from: &Arc<Mutex<HashSet<String>>>, into: &Arc<Mutex<HashSet<String>>>) {
    let Ok(mut into) = into.lock() else {
        clear_pending(from);
        return;
    };
    if let Ok(mut from) = from.lock() {
        into.extend(from.drain());
    }
}

/// 事务被 SQLite 回滚时（含语句级 `ON CONFLICT ROLLBACK`、显式 `ROLLBACK`），
/// 丢弃尚未发布的表名，避免把没提交的变更广播出去。
fn attach_rollback_hook<const N: usize>(
    conn: &mut Connection,
    sets: [Arc<Mutex<HashSet<String>>>; N],
) -> Result<()> {
    conn.rollback_hook(Some(move || {
        for set in &sets {
            clear_pending(set);
        }
    }))
    .context("register SQLite rollback hook")
}

fn open_connection(
    path: &str,
    read_only: bool,
    stmt_cache: usize,
) -> Result<(Connection, Arc<Mutex<HashSet<String>>>)> {
    let mut conn = Connection::open(path).with_context(|| format!("open SQLite {path}"))?;
    conn.busy_timeout(std::time::Duration::from_secs(5))?;
    conn.execute_batch(
        "PRAGMA synchronous=NORMAL;
         PRAGMA foreign_keys=ON;
         PRAGMA temp_store=MEMORY;
         PRAGMA cache_size=-8000;",
    )
    .context("configure SQLite pragmas")?;
    if read_only {
        // 在引擎层禁止写入；只读事务不应存在锁升级路径。
        conn.execute_batch("PRAGMA query_only=ON;")
            .context("configure read-only SQLite pragmas")?;
    }
    // 配合 prepare_cached 避免高频语句每次重新解析。
    conn.set_prepared_statement_cache_capacity(stmt_cache);

    let pending = new_pending();
    if !read_only {
        // 只读连接不会有写操作，不需要注册 hook。
        let sink = pending.clone();
        conn.update_hook(Some(
            move |action: Action, _db: &str, table: &str, _rowid: i64| {
                if !matches!(
                    action,
                    Action::SQLITE_INSERT | Action::SQLITE_UPDATE | Action::SQLITE_DELETE
                ) {
                    return;
                }
                // hook 在 SQLite 执行线程内同步调用：只入队，绝不查询/等待。
                // 批量写入时同一张表会被回调上万次，先查后插避免重复分配。
                if let Ok(mut buf) = sink.lock()
                    && !buf.contains(table)
                {
                    buf.insert(table.to_owned());
                }
            },
        ))?;
    }
    Ok((conn, pending))
}

// ---------------------------------------------------------------------------
// 查询结果流式序列化
// ---------------------------------------------------------------------------

/// 一列的输出计划：结果集下标 + 预编码的 JSON key 前缀。
struct ColumnPlan {
    index: usize,
    /// 第一列是 `"name":`，其余是 `,"name":`。
    prefix: Vec<u8>,
}

/// 一次算好列顺序与前缀。
///
/// `serde_json::Map` 是 `BTreeMap`：重复列名保留最后出现的值，输出按列名排序。
/// 这里用同样的规则生成计划，保证字节级输出与旧实现一致。
fn plan_columns(stmt: &Statement<'_>) -> Result<Vec<ColumnPlan>> {
    let mut by_name: BTreeMap<String, usize> = BTreeMap::new();
    for index in 0..stmt.column_count() {
        let name = stmt
            .column_name(index)
            .map(str::to_owned)
            .unwrap_or_default();
        by_name.insert(name, index);
    }
    let mut plan = Vec::with_capacity(by_name.len());
    for (position, (name, index)) in by_name.into_iter().enumerate() {
        let mut prefix = Vec::with_capacity(name.len() + 8);
        if position > 0 {
            prefix.push(b',');
        }
        // 列名可能含引号/控制字符，交给 serde_json 转义。
        serde_json::to_writer(&mut prefix, name.as_str())?;
        prefix.push(b':');
        plan.push(ColumnPlan { index, prefix });
    }
    Ok(plan)
}

fn write_json_value(out: &mut Vec<u8>, value: ValueRef<'_>) -> Result<()> {
    match value {
        ValueRef::Null => out.extend_from_slice(b"null"),
        ValueRef::Integer(v) => serde_json::to_writer(out, &v)?,
        ValueRef::Real(v) => {
            if v.is_finite() {
                serde_json::to_writer(out, &v)?;
            } else {
                // JSON 没有 NaN / Infinity：与 `Number::from_f64` 返回 None 的旧行为一致。
                out.extend_from_slice(b"null");
            }
        }
        ValueRef::Text(v) => match std::str::from_utf8(v) {
            // 合法 UTF-8 直接序列化 `&str`，不复制。
            Ok(text) => serde_json::to_writer(out, text)?,
            Err(_) => serde_json::to_writer(out, String::from_utf8_lossy(v).as_ref())?,
        },
        ValueRef::Blob(v) => {
            // base64 只用 A-Za-z0-9+/=，不需要 JSON 转义，可以直接写进缓冲区。
            let encoded_len =
                base64::encoded_len(v.len(), true).context("blob too large to base64 encode")?;
            out.push(b'"');
            let start = out.len();
            out.resize(start + encoded_len, 0);
            BASE64_STANDARD
                .encode_slice(v, &mut out[start..])
                .map_err(|error| anyhow!("encode blob as base64: {error}"))?;
            out.push(b'"');
        }
    }
    Ok(())
}

/// 把结果集直接流进一个字节缓冲区，不构造中间 `Vec<Value>` / 每行 `Map`。
fn query_json_streamed(
    conn: &Connection,
    sql: &str,
    params: &[rusqlite::types::Value],
) -> Result<String> {
    let mut stmt = conn
        .prepare_cached(sql)
        .with_context(|| format!("prepare SQL: {sql}"))?;
    let mut rows = stmt
        .query(params_from_iter(params.iter()))
        .with_context(|| format!("execute query: {sql}"))?;
    // 0 行的查询不该白占缓冲：第一条结果到达时再申请容量。
    let mut out: Vec<u8> = Vec::new();
    // 缓存的语句在 schema 变化后由 SQLite 在第一次 step 时自动重编译；
    // 列名必须在这之后读取，否则 `SELECT *` 可能沿用旧列集合。
    let mut plan: Option<Vec<ColumnPlan>> = None;
    let mut rows_written = 0usize;
    while let Some(row) = rows.next()? {
        if plan.is_none() {
            out.reserve(1024);
            plan = Some(plan_columns(row.as_ref())?);
        }
        let plan = plan.as_ref().expect("column plan initialized");
        out.push(if rows_written == 0 { b'[' } else { b',' });
        out.push(b'{');
        for column in plan {
            out.extend_from_slice(&column.prefix);
            write_json_value(&mut out, row.get_ref(column.index)?)?;
        }
        out.push(b'}');
        rows_written += 1;
    }
    if rows_written == 0 {
        return Ok("[]".to_string());
    }
    out.push(b']');
    String::from_utf8(out).context("query result is not valid UTF-8")
}

// ---------------------------------------------------------------------------
// 参数解析
// ---------------------------------------------------------------------------

fn parse_params(params_json: &str) -> Result<Vec<rusqlite::types::Value>> {
    let text = params_json.trim();
    // `[]` 是无参语句最常见的写法：直接跳过 JSON 解析。
    if text.is_empty() || text == "null" || text == "[]" {
        return Ok(Vec::new());
    }
    let value: Value = serde_json::from_str(text).context("parse SQL params JSON")?;
    let Value::Array(values) = value else {
        bail!("SQL params must be a JSON array");
    };
    // 逐个取走所有权：字符串参数直接移动进 `SqlValue::Text`。
    values.into_iter().map(json_to_sql).collect()
}

fn json_to_sql(value: Value) -> Result<rusqlite::types::Value> {
    use rusqlite::types::Value as SqlValue;
    Ok(match value {
        Value::Null => SqlValue::Null,
        Value::Bool(v) => SqlValue::Integer(i64::from(v)),
        Value::Number(n) => {
            if let Some(v) = n.as_i64() {
                SqlValue::Integer(v)
            } else if let Some(v) = n.as_f64() {
                SqlValue::Real(v)
            } else {
                bail!("unsupported number in SQL params: {n}");
            }
        }
        // 字符串直接移动进 `SqlValue::Text`：插件脚本 / 漫画详情这类大 JSON
        // 不必再复制一份。
        Value::String(v) => SqlValue::Text(v),
        other @ (Value::Array(_) | Value::Object(_)) => {
            SqlValue::Text(serde_json::to_string(&other)?)
        }
    })
}

// ---------------------------------------------------------------------------
// handle registry
// ---------------------------------------------------------------------------

pub fn open(path: &str) -> Result<i64> {
    let id = NEXT_HANDLE.fetch_add(1, Ordering::SeqCst);
    let handle = Arc::new(DbHandle::open_main(id, path)?);
    lock_registry()?.insert(id, handle);
    Ok(id)
}

pub fn begin(handle: i64, write: bool) -> Result<i64> {
    let main = get(handle)?;
    if !matches!(&main.kind, HandleKind::Main { .. }) {
        bail!("cannot begin a transaction on transaction handle {handle}");
    }
    let id = NEXT_HANDLE.fetch_add(1, Ordering::SeqCst);
    let tx = Arc::new(DbHandle::open_tx(id, &main, write)?);
    lock_registry()?.insert(id, tx);
    Ok(id)
}

pub fn get(handle: i64) -> Result<Arc<DbHandle>> {
    lock_registry()?
        .get(&handle)
        .cloned()
        .with_context(|| format!("unknown DB handle {handle}"))
}

/// 当前打开的应用主库（非事务连接）句柄。
///
/// 应用运行期只有一个主连接；进程内测试可能同时打开多个临时库，
/// 这里取最早打开的主连接，保证在单库场景下稳定。
pub fn main_handle() -> Result<i64> {
    lock_registry()?
        .iter()
        .filter(|(_, handle)| matches!(handle.kind, HandleKind::Main { .. }))
        .map(|(id, _)| *id)
        .min()
        .context("no open SQLite main database")
}

pub fn commit(handle: i64) -> Result<()> {
    let tx = get(handle)?;
    // 主句柄不能提交：直接报错，且不要把它从 registry 里摘掉。
    if !matches!(&tx.kind, HandleKind::Tx { .. }) {
        bail!("handle {handle} is not a transaction");
    }
    // 收尾前先摘除句柄：并发调用者再也拿不到这个正在结束的事务。
    let removed = lock_registry()?.remove(&handle);
    removed.unwrap_or(tx).commit()
}

pub fn rollback(handle: i64) -> Result<()> {
    let tx = get(handle)?;
    if !matches!(&tx.kind, HandleKind::Tx { .. }) {
        bail!("handle {handle} is not a transaction");
    }
    let removed = lock_registry()?.remove(&handle);
    removed.unwrap_or(tx).rollback()
}

pub fn close(handle: i64) -> Result<()> {
    let handle = lock_registry()?.remove(&handle);
    if let Some(handle) = handle {
        handle.close()?;
    }
    Ok(())
}

fn lock_registry() -> Result<MutexGuard<'static, HashMap<i64, Arc<DbHandle>>>> {
    REGISTRY
        .lock()
        .map_err(|_| anyhow!("DB registry lock poisoned"))
}

// ---------------------------------------------------------------------------
// tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    fn temp_db(name: &str) -> String {
        let dir = std::env::temp_dir().join("breeze_sql_layer_tests");
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join(format!(
            "{name}_{}_{}.sqlite3",
            std::process::id(),
            NEXT_HANDLE.load(Ordering::SeqCst)
        ));
        let _ = std::fs::remove_file(&path);
        path.to_string_lossy().into_owned()
    }

    /// 收集 ChangeBus 广播事件。
    fn watch(db: &DbHandle) -> Arc<Mutex<Vec<Vec<String>>>> {
        let events = Arc::new(Mutex::new(Vec::<Vec<String>>::new()));
        let sink = events.clone();
        db.bus.add_listener(Box::new(move |tables| {
            sink.lock().unwrap().push(tables);
        }));
        events
    }

    fn pool_of(db: &DbHandle) -> Arc<TxPool> {
        match &db.kind {
            HandleKind::Main { pool } => pool.clone(),
            HandleKind::Tx { .. } => panic!("expected a main handle"),
        }
    }

    #[test]
    fn fresh_database_uses_incremental_auto_vacuum() {
        let path = temp_db("auto_vacuum");
        let handle = open(&path).unwrap();
        let db = get(handle).unwrap();
        let read = |db: &DbHandle| -> i64 {
            let rows: Value =
                serde_json::from_str(&db.query_json("PRAGMA auto_vacuum", "[]").unwrap()).unwrap();
            rows[0]["auto_vacuum"].as_i64().unwrap()
        };
        assert_eq!(read(&db), 2);
        db.execute_script("CREATE TABLE t(id INTEGER PRIMARY KEY, v TEXT)")
            .unwrap();
        assert_eq!(read(&db), 2, "建表后仍保持 INCREMENTAL");
        close(handle).unwrap();
        let _ = std::fs::remove_file(path);
    }

    #[test]
    fn binds_params_as_values() {
        let handle = open(&temp_db("params")).unwrap();
        let db = get(handle).unwrap();
        db.execute_script("CREATE TABLE t(id INTEGER PRIMARY KEY, v TEXT)")
            .unwrap();
        db.execute("INSERT INTO t(id, v) VALUES(1, ?1)", r#"["x' OR 1=1 --"]"#)
            .unwrap();
        let rows = db
            .query_json("SELECT v FROM t WHERE v = ?1", r#"["x' OR 1=1 --"]"#)
            .unwrap();
        assert_eq!(rows, r#"[{"v":"x' OR 1=1 --"}]"#);
        // 注入串作为值不会扩大结果集。
        let injected = db
            .query_json("SELECT v FROM t WHERE v = ?1", r#"["' OR 1=1 --"]"#)
            .unwrap();
        assert_eq!(injected, "[]");
        close(handle).unwrap();
    }

    #[test]
    fn empty_params_fast_path_accepts_all_empty_spellings() {
        // `[]` / `null` / 空串都表示「没有参数」，且不进入 JSON 解析。
        for text in ["", " ", "null", " null ", "[]", " [] "] {
            assert!(parse_params(text).unwrap().is_empty(), "{text:?}");
        }
        let params = parse_params(r#"[1, "two", null, true]"#).unwrap();
        assert_eq!(params.len(), 4);
        assert!(matches!(params[0], rusqlite::types::Value::Integer(1)));
        assert!(matches!(&params[1], rusqlite::types::Value::Text(t) if t == "two"));
        assert!(matches!(params[2], rusqlite::types::Value::Null));
        assert!(matches!(params[3], rusqlite::types::Value::Integer(1)));
        assert!(parse_params(r#"{"a":1}"#).is_err(), "只接受数组");
        assert!(parse_params("not json").is_err());
    }

    #[test]
    fn query_json_preserves_map_semantics() {
        let handle = open(&temp_db("map_semantics")).unwrap();
        let db = get(handle).unwrap();
        // 重复列名保留最后一个值，输出按列名排序（与 serde_json::Map 一致）。
        assert_eq!(
            db.query_json("SELECT 1 AS a, 2 AS a, 3 AS b", "[]")
                .unwrap(),
            r#"[{"a":2,"b":3}]"#
        );
        // 0 行直接返回 []，不构造任何缓冲。
        assert_eq!(db.query_json("SELECT 1 AS a WHERE 0", "[]").unwrap(), "[]");
        close(handle).unwrap();
    }

    #[test]
    fn query_json_streams_special_values() {
        let handle = open(&temp_db("special_values")).unwrap();
        let db = get(handle).unwrap();
        let expected = concat!(
            r#"[{"b":"AP8Q","bad":""#,
            "\u{FFFD}",
            r#"A","i":1,"n":null,"r":1.5,"t":"he\"llo"}]"#
        );
        assert_eq!(
            db.query_json(
                r#"SELECT 1 AS i, 1.5 AS r, x'00ff10' AS b, 'he"llo' AS t,
                          CAST(x'ff41' AS TEXT) AS bad, NULL AS n"#,
                "[]"
            )
            .unwrap(),
            expected
        );
        // 非有限浮点数在 JSON 里只能是 null（与旧实现的 Number::from_f64 一致）。
        assert_eq!(
            db.query_json("SELECT 1e999 AS pos, -1e999 AS neg", "[]")
                .unwrap(),
            r#"[{"neg":null,"pos":null}]"#
        );
        // 空 blob / 空字符串 / 0 值。
        assert_eq!(
            db.query_json("SELECT x'' AS b, '' AS t, 0 AS z", "[]")
                .unwrap(),
            r#"[{"b":"","t":"","z":0}]"#
        );
        close(handle).unwrap();
    }

    #[test]
    fn execute_returns_fixed_json_shape() {
        let handle = open(&temp_db("execute_shape")).unwrap();
        let db = get(handle).unwrap();
        db.execute_script("CREATE TABLE t(id INTEGER PRIMARY KEY AUTOINCREMENT, v TEXT)")
            .unwrap();
        assert_eq!(
            db.execute("INSERT INTO t(v) VALUES(?1)", r#"["a"]"#)
                .unwrap(),
            r#"{"changes":1,"lastInsertId":1}"#
        );
        assert_eq!(
            db.execute("UPDATE t SET v = ?1 WHERE 0", r#"["b"]"#)
                .unwrap(),
            r#"{"changes":0,"lastInsertId":1}"#
        );
        close(handle).unwrap();
    }

    #[test]
    fn change_bus_sees_main_and_tx_commits() {
        let path = temp_db("bus");
        let handle = open(&path).unwrap();
        let db = get(handle).unwrap();
        db.execute_script("CREATE TABLE t(id INTEGER PRIMARY KEY, v TEXT)")
            .unwrap();
        let events = watch(&db);

        db.execute("INSERT INTO t(id, v) VALUES(1, 'main')", "[]")
            .unwrap();
        assert_eq!(events.lock().unwrap().as_slice(), &[vec!["t".to_string()]]);

        let tx = begin(handle, true).unwrap();
        let tx_handle = get(tx).unwrap();
        tx_handle
            .execute("INSERT INTO t(id, v) VALUES(2, 'tx')", "[]")
            .unwrap();
        assert_eq!(events.lock().unwrap().len(), 1, "tx commit 前不应发布");
        commit(tx).unwrap();
        assert_eq!(events.lock().unwrap().len(), 2);

        let tx = begin(handle, true).unwrap();
        get(tx)
            .unwrap()
            .execute("INSERT INTO t(id, v) VALUES(3, 'rollback')", "[]")
            .unwrap();
        rollback(tx).unwrap();
        assert_eq!(events.lock().unwrap().len(), 2, "回滚不应发布");
        close(handle).unwrap();
        let _ = std::fs::remove_file(path);
    }

    #[test]
    fn failed_statement_does_not_publish_tables() {
        let path = temp_db("failed_stmt");
        let handle = open(&path).unwrap();
        let db = get(handle).unwrap();
        // 触发器先写 audit（触发 update_hook），再 ABORT 整条语句。
        db.execute_script(
            "CREATE TABLE t(id INTEGER PRIMARY KEY);
             CREATE TABLE audit(id INTEGER PRIMARY KEY);
             CREATE TRIGGER t_ins AFTER INSERT ON t BEGIN
                 INSERT INTO audit(id) VALUES(new.id);
                 SELECT RAISE(ABORT, 'boom');
             END;",
        )
        .unwrap();
        let events = watch(&db);

        let error = db.execute("INSERT INTO t(id) VALUES(1)", "[]").unwrap_err();
        assert!(format!("{error:#}").contains("boom"), "{error:#}");
        assert!(
            events.lock().unwrap().is_empty(),
            "失败的语句不能广播表名: {:?}",
            events.lock().unwrap()
        );

        // 之后成功的语句只广播自己的表，不带失败语句的残留。
        db.execute("INSERT INTO audit(id) VALUES(7)", "[]").unwrap();
        assert_eq!(
            events.lock().unwrap().as_slice(),
            &[vec!["audit".to_string()]]
        );

        close(handle).unwrap();
        let _ = std::fs::remove_file(path);
    }

    #[test]
    fn explicit_main_transaction_publishes_after_commit() {
        let path = temp_db("main_explicit_tx");
        let handle = open(&path).unwrap();
        let db = get(handle).unwrap();
        db.execute_script("CREATE TABLE t(id INTEGER PRIMARY KEY)")
            .unwrap();
        let events = watch(&db);

        db.execute_script("BEGIN; INSERT INTO t(id) VALUES(1)")
            .unwrap();
        assert!(events.lock().unwrap().is_empty(), "显式事务未提交前不广播");
        db.execute("INSERT INTO t(id) VALUES(2)", "[]").unwrap();
        assert!(events.lock().unwrap().is_empty(), "事务内语句继续攒着");
        db.execute_script("COMMIT").unwrap();
        assert_eq!(events.lock().unwrap().as_slice(), &[vec!["t".to_string()]]);

        // 回滚：rollback_hook 清掉累计的表名，什么都不发。
        db.execute_script("BEGIN; INSERT INTO t(id) VALUES(3)")
            .unwrap();
        db.execute_script("ROLLBACK").unwrap();
        assert_eq!(events.lock().unwrap().len(), 1, "回滚不应发布");

        close(handle).unwrap();
        let _ = std::fs::remove_file(path);
    }

    #[test]
    fn tx_publishes_merged_tables_once() {
        let path = temp_db("tx_merge");
        let handle = open(&path).unwrap();
        let db = get(handle).unwrap();
        db.execute_script(
            "CREATE TABLE a(id INTEGER PRIMARY KEY); CREATE TABLE b(id INTEGER PRIMARY KEY)",
        )
        .unwrap();
        let events = watch(&db);

        let tx = begin(handle, true).unwrap();
        let tx_handle = get(tx).unwrap();
        tx_handle
            .execute("INSERT INTO b(id) VALUES(1)", "[]")
            .unwrap();
        tx_handle
            .execute("INSERT INTO a(id) VALUES(1)", "[]")
            .unwrap();
        tx_handle
            .execute("INSERT INTO a(id) VALUES(2)", "[]")
            .unwrap();
        assert!(events.lock().unwrap().is_empty());
        commit(tx).unwrap();
        assert_eq!(
            events.lock().unwrap().as_slice(),
            &[vec!["a".to_string(), "b".to_string()]],
            "一个事务只发布一次，表名去重排序"
        );
        close(handle).unwrap();
        let _ = std::fs::remove_file(path);
    }

    #[test]
    fn read_only_transaction_rejects_writes() {
        let path = temp_db("read_only_tx");
        let handle = open(&path).unwrap();
        let db = get(handle).unwrap();
        db.execute_script("CREATE TABLE t(id INTEGER PRIMARY KEY, v TEXT)")
            .unwrap();
        db.execute("INSERT INTO t(id, v) VALUES(1, 'main')", "[]")
            .unwrap();

        let tx = begin(handle, false).unwrap();
        let tx_handle = get(tx).unwrap();
        let error = tx_handle
            .execute("INSERT INTO t(id, v) VALUES(2, 'tx')", "[]")
            .unwrap_err();
        assert!(
            format!("{error:#}").contains("readonly"),
            "只读事务必须由 query_only 拒绝写入: {error:#}"
        );
        assert!(watch_has_no_pending(&tx_handle));
        assert_eq!(
            tx_handle
                .query_json("SELECT COUNT(*) AS c FROM t", "[]")
                .unwrap(),
            r#"[{"c":1}]"#
        );
        rollback(tx).unwrap();
        close(handle).unwrap();
        let _ = std::fs::remove_file(path);
    }

    fn watch_has_no_pending(handle: &DbHandle) -> bool {
        handle.stmt_pending.lock().unwrap().is_empty()
    }

    #[test]
    fn read_only_transaction_keeps_a_stable_snapshot() {
        let path = temp_db("read_only_snapshot");
        let handle = open(&path).unwrap();
        let db = get(handle).unwrap();
        db.execute_script("CREATE TABLE t(id INTEGER PRIMARY KEY, v TEXT)")
            .unwrap();
        db.execute("INSERT INTO t(id, v) VALUES(1, 'before')", "[]")
            .unwrap();

        let tx = begin(handle, false).unwrap();
        let tx_handle = get(tx).unwrap();
        // 第一条真实读语句建立快照。
        assert_eq!(
            tx_handle
                .query_json("SELECT COUNT(*) AS c FROM t", "[]")
                .unwrap(),
            r#"[{"c":1}]"#
        );
        db.execute("INSERT INTO t(id, v) VALUES(2, 'after')", "[]")
            .unwrap();
        assert_eq!(
            tx_handle
                .query_json("SELECT COUNT(*) AS c FROM t", "[]")
                .unwrap(),
            r#"[{"c":1}]"#,
            "只读事务内的多次读取必须看到同一快照"
        );
        assert_eq!(
            db.query_json("SELECT COUNT(*) AS c FROM t", "[]").unwrap(),
            r#"[{"c":2}]"#
        );
        rollback(tx).unwrap();
        close(handle).unwrap();
        let _ = std::fs::remove_file(path);
    }

    #[test]
    fn read_transactions_do_not_publish_tables() {
        let path = temp_db("read_tx_no_publish");
        let handle = open(&path).unwrap();
        let db = get(handle).unwrap();
        db.execute_script("CREATE TABLE t(id INTEGER PRIMARY KEY)")
            .unwrap();
        db.execute("INSERT INTO t(id) VALUES(1)", "[]").unwrap();
        let events = watch(&db);

        let tx = begin(handle, false).unwrap();
        get(tx)
            .unwrap()
            .query_json("SELECT COUNT(*) AS c FROM t", "[]")
            .unwrap();
        commit(tx).unwrap();
        assert!(events.lock().unwrap().is_empty(), "只读事务不发布");
        close(handle).unwrap();
        let _ = std::fs::remove_file(path);
    }

    #[test]
    fn cached_statements_see_schema_changes() {
        let path = temp_db("cached_schema");
        let handle = open(&path).unwrap();
        let db = get(handle).unwrap();
        db.execute_script("CREATE TABLE t(id INTEGER PRIMARY KEY, v TEXT)")
            .unwrap();
        assert_eq!(db.query_json("SELECT * FROM t", "[]").unwrap(), "[]");
        db.execute_script("ALTER TABLE t ADD COLUMN extra TEXT")
            .unwrap();
        db.execute("INSERT INTO t(id, v, extra) VALUES(1, 'v', 'e')", "[]")
            .unwrap();
        assert_eq!(
            db.query_json("SELECT * FROM t", "[]").unwrap(),
            r#"[{"extra":"e","id":1,"v":"v"}]"#,
            "缓存的语句必须在 schema 变化后重新准备"
        );
        close(handle).unwrap();
        let _ = std::fs::remove_file(path);
    }

    #[test]
    fn query_execute_and_transaction() {
        let handle = open(&temp_db("crud")).unwrap();
        let db = get(handle).unwrap();
        db.execute_script("CREATE TABLE t(id INTEGER PRIMARY KEY AUTOINCREMENT, v TEXT)")
            .unwrap();
        let result = db
            .execute("INSERT INTO t(v) VALUES(?1)", r#"["a"]"#)
            .unwrap();
        let result: Value = serde_json::from_str(&result).unwrap();
        assert_eq!(result["changes"], 1);
        assert_eq!(result["lastInsertId"], 1);

        let rows = db.query_json("SELECT * FROM t ORDER BY id", "[]").unwrap();
        assert_eq!(rows, r#"[{"id":1,"v":"a"}]"#);

        let tx = begin(handle, true).unwrap();
        let tx_handle = get(tx).unwrap();
        tx_handle
            .execute("INSERT INTO t(v) VALUES(?1)", r#"["b"]"#)
            .unwrap();
        rollback(tx).unwrap();
        assert_eq!(
            db.query_json("SELECT COUNT(*) AS c FROM t", "[]").unwrap(),
            r#"[{"c":1}]"#
        );
        close(handle).unwrap();
    }

    #[test]
    fn transaction_isolation_with_async_style_calls() {
        let handle = open(&temp_db("iso")).unwrap();
        let db = get(handle).unwrap();
        db.execute_script("CREATE TABLE t(id INTEGER PRIMARY KEY, v TEXT)")
            .unwrap();
        let tx = begin(handle, true).unwrap();
        let tx_handle = get(tx).unwrap();
        tx_handle
            .execute("INSERT INTO t(id, v) VALUES(1, 'tx')", "[]")
            .unwrap();

        // 事务未提交时，主连接看不到未提交数据。
        assert_eq!(
            db.query_json("SELECT COUNT(*) AS c FROM t", "[]").unwrap(),
            r#"[{"c":0}]"#
        );
        commit(tx).unwrap();
        assert_eq!(
            db.query_json("SELECT COUNT(*) AS c FROM t", "[]").unwrap(),
            r#"[{"c":1}]"#
        );
        close(handle).unwrap();
    }

    #[test]
    fn tx_connections_are_pooled_and_reused() {
        let path = temp_db("pool_reuse");
        let handle = open(&path).unwrap();
        let db = get(handle).unwrap();
        db.execute_script("CREATE TABLE t(id INTEGER PRIMARY KEY)")
            .unwrap();
        let pool = pool_of(&db);
        assert!(pool.take(true).unwrap().is_none(), "池初为空");

        for id in 1..=3 {
            let tx = begin(handle, true).unwrap();
            get(tx)
                .unwrap()
                .execute(&format!("INSERT INTO t(id) VALUES({id})"), "[]")
                .unwrap();
            commit(tx).unwrap();
        }
        assert_eq!(
            pool.write_idle.lock().unwrap().len(),
            1,
            "写连接复用后只保留 1 条"
        );

        // 读连接最多缓存 2 条。
        let mut read_txs = Vec::new();
        for _ in 0..3 {
            read_txs.push(begin(handle, false).unwrap());
        }
        for tx in read_txs {
            rollback(tx).unwrap();
        }
        assert_eq!(pool.read_idle.lock().unwrap().len(), 2);

        // 复用的连接状态仍然是干净的：可以继续开事务读。
        let tx = begin(handle, false).unwrap();
        assert_eq!(
            get(tx)
                .unwrap()
                .query_json("SELECT COUNT(*) AS c FROM t", "[]")
                .unwrap(),
            r#"[{"c":3}]"#
        );
        rollback(tx).unwrap();

        close(handle).unwrap();
        let _ = std::fs::remove_file(path);
    }

    #[test]
    fn pooled_write_connection_is_really_reused() {
        let path = temp_db("pool_identity");
        let handle = open(&path).unwrap();
        let db = get(handle).unwrap();
        db.execute_script("CREATE TABLE t(id INTEGER PRIMARY KEY)")
            .unwrap();

        // 临时表只属于打开它的连接：提交后仍然留在这个连接上，
        // 用它就能证明第二次 begin 复用的是同一个连接。
        let tx = begin(handle, true).unwrap();
        get(tx)
            .unwrap()
            .execute_script("CREATE TEMP TABLE marker(x)")
            .unwrap();
        commit(tx).unwrap();

        let tx = begin(handle, true).unwrap();
        assert_eq!(
            get(tx)
                .unwrap()
                .query_json("SELECT COUNT(*) AS c FROM temp.marker", "[]")
                .unwrap(),
            r#"[{"c":0}]"#,
            "第二次 begin 必须复用池里的写连接"
        );
        rollback(tx).unwrap();

        // 读连接是另一条连接，看不到写连接的临时表。
        let read = begin(handle, false).unwrap();
        assert!(
            get(read)
                .unwrap()
                .query_json("SELECT COUNT(*) AS c FROM temp.marker", "[]")
                .is_err()
        );
        rollback(read).unwrap();

        close(handle).unwrap();
        let _ = std::fs::remove_file(path);
    }

    #[test]
    fn close_drops_pooled_connections_before_checkpoint() {
        let path = temp_db("pool_close");
        let handle = open(&path).unwrap();
        let db = get(handle).unwrap();
        db.execute_script("CREATE TABLE t(id INTEGER PRIMARY KEY)")
            .unwrap();
        let pool = pool_of(&db);

        let tx = begin(handle, true).unwrap();
        get(tx)
            .unwrap()
            .execute("INSERT INTO t(id) VALUES(1)", "[]")
            .unwrap();
        commit(tx).unwrap();
        let tx = begin(handle, false).unwrap();
        rollback(tx).unwrap();
        assert_eq!(pool.write_idle.lock().unwrap().len(), 1);
        assert_eq!(pool.read_idle.lock().unwrap().len(), 1);

        close(handle).unwrap();
        assert!(pool.is_closed(), "close 必须标记池为关闭");
        assert!(
            pool.write_idle.lock().unwrap().is_empty(),
            "空闲写连接必须丢弃"
        );
        assert!(
            pool.read_idle.lock().unwrap().is_empty(),
            "空闲读连接必须丢弃"
        );
        // 主连接也已释放：后续调用直接报错。
        assert!(db.query_json("SELECT 1 AS v", "[]").is_err());
        drop(db);

        // 文件句柄都释放了，可以立刻删除。
        std::fs::remove_file(&path).expect("close 之后不应再持有文件句柄");
    }

    #[test]
    fn release_after_close_does_not_retain_connections() {
        let path = temp_db("pool_late_release");
        let handle = open(&path).unwrap();
        let db = get(handle).unwrap();
        db.execute_script("CREATE TABLE t(id INTEGER PRIMARY KEY)")
            .unwrap();
        let pool = pool_of(&db);

        // 造两条归还后还在池里的连接。
        let tx = begin(handle, true).unwrap();
        commit(tx).unwrap();
        let tx = begin(handle, false).unwrap();
        rollback(tx).unwrap();
        assert_eq!(pool.write_idle.lock().unwrap().len(), 1);
        assert_eq!(pool.read_idle.lock().unwrap().len(), 1);

        // 模拟 close 已经执行完毕，此时才归还连接（release 与 close 的竞态窗口）。
        let late_write = pool.take(true).unwrap().expect("写连接在池里");
        let late_read = pool.take(false).unwrap().expect("读连接在池里");
        close(handle).unwrap();
        assert!(pool.is_closed());

        pool.release(true, late_write);
        pool.release(false, late_read);
        assert!(
            pool.write_idle.lock().unwrap().is_empty(),
            "关闭后归还的写连接必须直接丢弃"
        );
        assert!(
            pool.read_idle.lock().unwrap().is_empty(),
            "关闭后归还的读连接必须直接丢弃"
        );
        // 关闭的池不再交出连接。
        assert!(pool.take(true).unwrap().is_none());
        assert!(pool.take(false).unwrap().is_none());
        drop(db);

        // 连接已 Drop，文件句柄全部释放。
        std::fs::remove_file(&path).expect("关闭后不应再持有文件句柄");
    }

    #[test]
    fn recycled_write_connection_detaches_rollback_hook() {
        let path = temp_db("recycle_hook");
        let handle = open(&path).unwrap();
        let db = get(handle).unwrap();
        db.execute_script("CREATE TABLE t(id INTEGER PRIMARY KEY)")
            .unwrap();

        let tx = begin(handle, true).unwrap();
        let tx_handle = get(tx).unwrap();
        tx_handle
            .execute("INSERT INTO t(id) VALUES(1)", "[]")
            .unwrap();
        assert_eq!(
            Arc::strong_count(&tx_handle.tx_pending),
            2,
            "写事务期间 rollback_hook 会持有一份 tx_pending"
        );
        commit(tx).unwrap();
        assert_eq!(
            Arc::strong_count(&tx_handle.tx_pending),
            1,
            "归还写连接前必须摘掉 rollback_hook，否则 tx_pending 会被池长期留住"
        );
        drop(tx_handle);
        assert_eq!(
            pool_of(&db).write_idle.lock().unwrap().len(),
            1,
            "连接本身仍然回池复用"
        );

        // 只读事务本来就不注册 rollback_hook。
        let tx = begin(handle, false).unwrap();
        let tx_handle = get(tx).unwrap();
        assert_eq!(
            Arc::strong_count(&tx_handle.tx_pending),
            1,
            "只读事务不需要 rollback_hook"
        );
        rollback(tx).unwrap();

        close(handle).unwrap();
        let _ = std::fs::remove_file(path);
    }

    #[test]
    fn finished_tx_handle_rejects_further_calls() {
        let path = temp_db("finished_tx");
        let handle = open(&path).unwrap();
        let db = get(handle).unwrap();
        db.execute_script("CREATE TABLE t(id INTEGER PRIMARY KEY)")
            .unwrap();

        let tx = begin(handle, true).unwrap();
        let tx_handle = get(tx).unwrap();
        tx_handle
            .execute("INSERT INTO t(id) VALUES(1)", "[]")
            .unwrap();
        commit(tx).unwrap();

        assert!(tx_handle.query_json("SELECT 1 AS v", "[]").is_err());
        assert!(
            tx_handle
                .execute("INSERT INTO t(id) VALUES(2)", "[]")
                .is_err()
        );
        assert!(tx_handle.execute_script("SELECT 1").is_err());
        assert!(tx_handle.commit().is_err());
        assert!(tx_handle.rollback().is_ok(), "重复回滚是幂等的");
        // registry 里已经摘除，外部句柄号不可再用。
        assert!(get(tx).is_err());
        assert!(sql_commit_removed(tx));
        assert!(sql_rollback_removed(tx));

        close(handle).unwrap();
        let _ = std::fs::remove_file(path);
    }

    fn sql_commit_removed(handle: i64) -> bool {
        commit(handle).is_err() && get(handle).is_err()
    }

    fn sql_rollback_removed(handle: i64) -> bool {
        rollback(handle).is_err() && get(handle).is_err()
    }

    #[test]
    fn main_handle_rejects_commit_and_rollback_without_leaving_the_registry() {
        let path = temp_db("main_rejects_tx_ops");
        let handle = open(&path).unwrap();
        let db = get(handle).unwrap();
        db.execute_script("CREATE TABLE t(id INTEGER PRIMARY KEY)")
            .unwrap();

        let error = commit(handle).unwrap_err();
        assert!(
            format!("{error:#}").contains("not a transaction"),
            "{error:#}"
        );
        assert!(get(handle).is_ok(), "主句柄不能被摘除");
        assert!(rollback(handle).is_err());
        assert!(get(handle).is_ok());

        // 主句柄依旧可用。
        assert_eq!(
            db.query_json("SELECT COUNT(*) AS c FROM t", "[]").unwrap(),
            r#"[{"c":0}]"#
        );
        close(handle).unwrap();
        let _ = std::fs::remove_file(path);
    }

    #[test]
    fn begin_on_transaction_handle_is_rejected() {
        let path = temp_db("nested_begin");
        let handle = open(&path).unwrap();
        let db = get(handle).unwrap();
        db.execute_script("CREATE TABLE t(id INTEGER PRIMARY KEY)")
            .unwrap();
        let tx = begin(handle, true).unwrap();
        let error = begin(tx, true).unwrap_err();
        assert!(format!("{error:#}").contains("cannot begin"), "{error:#}");
        rollback(tx).unwrap();
        close(handle).unwrap();
        let _ = std::fs::remove_file(path);
    }

    #[test]
    fn close_rolls_back_open_transactions() {
        let path = temp_db("close_tx");
        let handle = open(&path).unwrap();
        let db = get(handle).unwrap();
        db.execute_script("CREATE TABLE t(id INTEGER PRIMARY KEY)")
            .unwrap();
        let tx = begin(handle, true).unwrap();
        get(tx)
            .unwrap()
            .execute("INSERT INTO t(id) VALUES(1)", "[]")
            .unwrap();
        let tx_handle = get(tx).unwrap();
        close(tx).unwrap();
        assert!(tx_handle.query_json("SELECT 1 AS v", "[]").is_err());
        assert_eq!(
            db.query_json("SELECT COUNT(*) AS c FROM t", "[]").unwrap(),
            r#"[{"c":0}]"#
        );
        close(handle).unwrap();
        let _ = std::fs::remove_file(path);
    }
}
