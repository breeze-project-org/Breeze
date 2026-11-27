import 'package:zephyr/database/db.dart';
import 'package:zephyr/database/db_read.dart';
import 'package:zephyr/database/row_codec.dart';
import 'package:zephyr/object_box/model.dart';
import 'package:zephyr/object_box/model_json_codec.dart';
import 'package:zephyr/util/async/worker_pool.dart';
import 'package:zephyr/util/rust/rust_loader.dart';

const _favoriteInsert =
    'INSERT INTO "UnifiedComicFavorite" '
    '("uniqueKey","source","comicId","title","description","createdAt",'
    '"updatedAt","deleted","schemaVersion","cover","creator","titleMeta",'
    '"metadata") VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)';

const _favoriteUpsert =
    'INSERT INTO "UnifiedComicFavorite" '
    '("id","uniqueKey","source","comicId","title","description","createdAt",'
    '"updatedAt","deleted","schemaVersion","cover","creator","titleMeta",'
    '"metadata") VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?) '
    'ON CONFLICT("id") DO UPDATE SET '
    '"uniqueKey"=excluded."uniqueKey","source"=excluded."source",'
    '"comicId"=excluded."comicId","title"=excluded."title",'
    '"description"=excluded."description","createdAt"=excluded."createdAt",'
    '"updatedAt"=excluded."updatedAt","deleted"=excluded."deleted",'
    '"schemaVersion"=excluded."schemaVersion","cover"=excluded."cover",'
    '"creator"=excluded."creator","titleMeta"=excluded."titleMeta",'
    '"metadata"=excluded."metadata"';

/// 收藏软删除：同一份 SQL 供单条与批量使用，立墓碑并清空展示字段。
///
/// `%KEYS%` 替换成对应数量的 `?`。
const _favoriteMarkDeleted = r'''
UPDATE "UnifiedComicFavorite"
SET "deleted" = 1, "updatedAt" = ?,
    "description" = '', "cover" = '', "creator" = '',
    "titleMeta" = '', "metadata" = ''
WHERE "uniqueKey" IN (%KEYS%) AND "deleted" = 0
''';

class UnifiedComicFavoriteRepository {
  final BreezeDatabase db;

  const UnifiedComicFavoriteRepository(this.db);

  static const String table = 'UnifiedComicFavorite';

  Future<UnifiedComicFavorite?> getById(int id) => runDbRead(
    db,
    sql: 'SELECT * FROM "UnifiedComicFavorite" WHERE "id" = ? LIMIT 1',
    params: <Object?>[id],
    decode: _decodeFirst,
  );

  Future<UnifiedComicFavorite?> getByKey(String uniqueKey) => runDbRead(
    db,
    sql: 'SELECT * FROM "UnifiedComicFavorite" WHERE "uniqueKey" = ? LIMIT 1',
    params: <Object?>[uniqueKey],
    decode: _decodeFirst,
  );

  /// 批量按 uniqueKey 取行（`IN` 分块，避免 SQLite 变量上限）。
  Future<List<UnifiedComicFavorite>> getByKeys(List<String> uniqueKeys) async {
    if (uniqueKeys.isEmpty) return const <UnifiedComicFavorite>[];
    final rows = <UnifiedComicFavorite>[];
    for (final chunk in chunkParams(uniqueKeys)) {
      final marks = List.filled(chunk.length, '?').join(',');
      rows.addAll(
        await runDbRead(
          db,
          sql:
              'SELECT * FROM "UnifiedComicFavorite" '
              'WHERE "uniqueKey" IN ($marks)',
          params: chunk,
          decode: _decodeAll,
        ),
      );
    }
    return rows;
  }

  Future<List<UnifiedComicFavorite>> getAll() => runDbRead(
    db,
    sql: 'SELECT * FROM "UnifiedComicFavorite" ORDER BY "id"',
    decode: _decodeAll,
  );

  /// 按来源取 uniqueKey（删除插件清理用，只读键不解码整行）。
  Future<List<String>> listKeysBySource(String source) => runDbRead(
    db,
    sql: 'SELECT "uniqueKey" FROM "UnifiedComicFavorite" WHERE "source" = ?',
    params: <Object?>[source],
    decode: uniqueKeysFromRows,
  );

  Future<List<UnifiedComicFavorite>> listActive() => runDbRead(
    db,
    sql:
        'SELECT * FROM "UnifiedComicFavorite" WHERE "deleted" = 0 '
        'ORDER BY "id"',
    decode: _decodeAll,
  );

  Future<int> count() => runDbRead(
    db,
    sql: 'SELECT COUNT(*) AS c FROM "UnifiedComicFavorite"',
    decode: countFromRows,
  );

  Future<int> put(UnifiedComicFavorite value) async {
    if (value.id > 0) {
      await db.execute(_favoriteUpsert, _params(value, includeId: true));
      return value.id;
    }
    final result = await db.execute(
      _favoriteInsert,
      _params(value, includeId: false),
    );
    value.id = result.lastInsertId;
    return value.id;
  }

  Future<List<int>> putMany(List<UnifiedComicFavorite> values) async {
    if (values.isEmpty) return const <int>[];
    return db.transaction((tx) async {
      final ids = <int>[];
      for (final value in values) {
        ids.add(await _putInTx(tx, value));
      }
      return ids;
    });
  }

  /// 软删除（同步墓碑）：单条入口，复用 [markDeletedByKeys] 的同一份 SQL。
  Future<int> markDeletedByKey(String uniqueKey) =>
      markDeletedByKeys([uniqueKey]);

  /// 批量软删除收藏，按 SQLite 变量上限分块，整个批次在一个事务内完成。
  ///
  /// 删除统一刷新 updatedAt，并清空不再需要的展示字段；复活时会重新写入。
  Future<int> markDeletedByKeys(Iterable<String> uniqueKeys) async {
    final keys = uniqueKeys.toList(growable: false);
    if (keys.isEmpty) return 0;
    final ts = dateToDb(DateTime.now().toUtc());
    var changes = 0;
    await db.transaction((tx) async {
      for (final chunk in chunkParams(keys)) {
        final marks = List.filled(chunk.length, '?').join(',');
        final result = await tx.execute(
          _favoriteMarkDeleted.replaceFirst('%KEYS%', marks),
          <Object?>[ts, ...chunk],
        );
        changes += result.changes;
      }
    });
    return changes;
  }

  Future<int> removeById(int id) async {
    final result = await db.execute(
      'DELETE FROM "UnifiedComicFavorite" WHERE "id" = ?',
      <Object?>[id],
    );
    return result.changes;
  }

  Future<int> removeAll() async {
    final result = await db.execute('DELETE FROM "UnifiedComicFavorite"');
    return result.changes;
  }

  Stream<List<UnifiedComicFavorite>> watchActive() async* {
    yield await listActive();
    yield* db.changes
        .where((tables) => tables.contains(table))
        .asyncMap((_) => listActive());
  }

  Future<int> _putInTx(DbTransaction tx, UnifiedComicFavorite value) async {
    if (value.id > 0) {
      await tx.execute(_favoriteUpsert, _params(value, includeId: true));
      return value.id;
    }
    final result = await tx.execute(
      _favoriteInsert,
      _params(value, includeId: false),
    );
    value.id = result.lastInsertId;
    return value.id;
  }

  List<Object?> _params(UnifiedComicFavorite v, {required bool includeId}) {
    return <Object?>[
      if (includeId) v.id,
      v.uniqueKey,
      v.source,
      v.comicId,
      v.title,
      v.description,
      dateToDb(v.createdAt),
      dateToDb(v.updatedAt),
      boolToDb(v.deleted),
      v.schemaVersion,
      comicImageToField(v.cover),
      creatorToField(v.creator),
      comicTitleMetaToField(v.titleMeta),
      comicMetadataToField(v.metadata),
    ];
  }

  static UnifiedComicFavorite _decodeRow(Map<String, dynamic> row) {
    return UnifiedComicFavorite.fromJson(
      normalizeRow(
        withDefaultId(row),
        dates: const <String>{'createdAt', 'updatedAt'},
        bools: const <String>{'deleted'},
      ),
    );
  }

  static List<UnifiedComicFavorite> _decodeAll(
    List<Map<String, dynamic>> rows,
  ) => rows.map(_decodeRow).toList();

  static UnifiedComicFavorite? _decodeFirst(List<Map<String, dynamic>> rows) =>
      rows.isEmpty ? null : _decodeRow(rows.first);
}

const _historyInsert =
    'INSERT INTO "UnifiedComicHistory" '
    '("uniqueKey","source","comicId","title","description","chapterId",'
    '"chapterTitle","chapterOrder","pageIndex","lastReadAt","deleted",'
    '"schemaVersion","createdAt","updatedAt","cover","creator","titleMeta",'
    '"metadata") VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)';

const _historyUpsert =
    'INSERT INTO "UnifiedComicHistory" '
    '("id","uniqueKey","source","comicId","title","description","chapterId",'
    '"chapterTitle","chapterOrder","pageIndex","lastReadAt","deleted",'
    '"schemaVersion","createdAt","updatedAt","cover","creator","titleMeta",'
    '"metadata") VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?) '
    'ON CONFLICT("id") DO UPDATE SET '
    '"uniqueKey"=excluded."uniqueKey","source"=excluded."source",'
    '"comicId"=excluded."comicId","title"=excluded."title",'
    '"description"=excluded."description","chapterId"=excluded."chapterId",'
    '"chapterTitle"=excluded."chapterTitle","chapterOrder"=excluded."chapterOrder",'
    '"pageIndex"=excluded."pageIndex","lastReadAt"=excluded."lastReadAt",'
    '"deleted"=excluded."deleted","schemaVersion"=excluded."schemaVersion",'
    '"createdAt"=excluded."createdAt","updatedAt"=excluded."updatedAt",'
    '"cover"=excluded."cover","creator"=excluded."creator",'
    '"titleMeta"=excluded."titleMeta","metadata"=excluded."metadata"';

/// 历史软删除：同一份 SQL 供单条与批量使用。
///
/// `%KEYS%` 替换成对应数量的 `?`。删除即刷新 updatedAt 与 lastReadAt，
/// 不区分单条还是批量。
const _historyMarkDeleted = r'''
UPDATE "UnifiedComicHistory"
SET "deleted" = 1, "updatedAt" = ?, "lastReadAt" = ?,
    "description" = '', "cover" = '', "creator" = '',
    "titleMeta" = '', "metadata" = ''
WHERE "uniqueKey" IN (%KEYS%) AND "deleted" = 0
''';

class UnifiedComicHistoryRepository {
  final BreezeDatabase db;

  const UnifiedComicHistoryRepository(this.db);

  static const String table = 'UnifiedComicHistory';

  Future<UnifiedComicHistory?> getById(int id) => runDbRead(
    db,
    sql: 'SELECT * FROM "UnifiedComicHistory" WHERE "id" = ? LIMIT 1',
    params: <Object?>[id],
    decode: _decodeFirst,
  );

  Future<UnifiedComicHistory?> getByKey(String uniqueKey) => runDbRead(
    db,
    sql: 'SELECT * FROM "UnifiedComicHistory" WHERE "uniqueKey" = ? LIMIT 1',
    params: <Object?>[uniqueKey],
    decode: _decodeFirst,
  );

  /// 批量按 uniqueKey 取行（`IN` 分块，避免 SQLite 变量上限）。
  Future<List<UnifiedComicHistory>> getByKeys(List<String> uniqueKeys) async {
    if (uniqueKeys.isEmpty) return const <UnifiedComicHistory>[];
    final rows = <UnifiedComicHistory>[];
    for (final chunk in chunkParams(uniqueKeys)) {
      final marks = List.filled(chunk.length, '?').join(',');
      rows.addAll(
        await runDbRead(
          db,
          sql:
              'SELECT * FROM "UnifiedComicHistory" '
              'WHERE "uniqueKey" IN ($marks)',
          params: chunk,
          decode: _decodeAll,
        ),
      );
    }
    return rows;
  }

  Future<List<UnifiedComicHistory>> getAll() => runDbRead(
    db,
    sql: 'SELECT * FROM "UnifiedComicHistory" ORDER BY "id"',
    decode: _decodeAll,
  );

  /// 按来源取 uniqueKey（删除插件清理用，只读键不解码整行）。
  Future<List<String>> listKeysBySource(String source) => runDbRead(
    db,
    sql: 'SELECT "uniqueKey" FROM "UnifiedComicHistory" WHERE "source" = ?',
    params: <Object?>[source],
    decode: uniqueKeysFromRows,
  );

  static String listActiveSql({bool ascending = false}) {
    final direction = ascending ? 'ASC' : 'DESC';
    return 'SELECT * FROM "UnifiedComicHistory" WHERE "deleted" = 0 '
        'ORDER BY "updatedAt" $direction, "id" $direction';
  }

  Future<List<UnifiedComicHistory>> listActive({
    bool ascending = false,
    int? limit,
    int? offset,
  }) => runDbRead(
    db,
    sql: limit == null
        ? listActiveSql(ascending: ascending)
        : '${listActiveSql(ascending: ascending)} LIMIT ? OFFSET ?',
    params: limit == null ? const <Object?>[] : <Object?>[limit, offset ?? 0],
    decode: _decodeAll,
  );

  /// 追更页加载用：整表历史改在后台 isolate 查询并解码。
  ///
  /// 历史表可能有上千行、每行数 KB JSON；[listActive] 在调用方 isolate 解码，
  /// 进入追更页时会卡帧。SQL 与解码完全复用，只把执行位置移到后台。
  Future<List<UnifiedComicHistory>> listActiveInWorker() => runDbReadInWorker(
    db,
    sql: listActiveSql(),
    decode: _decodeAll,
  );

  Future<int> count() => runDbRead(
    db,
    sql: 'SELECT COUNT(*) AS c FROM "UnifiedComicHistory"',
    decode: countFromRows,
  );

  Future<int> put(UnifiedComicHistory value) async {
    if (value.id > 0) {
      await db.execute(_historyUpsert, _params(value, includeId: true));
      return value.id;
    }
    final result = await db.execute(
      _historyInsert,
      _params(value, includeId: false),
    );
    value.id = result.lastInsertId;
    return result.lastInsertId;
  }

  /// 阅读器周期保存专用：把单条 upsert 放进 worker 池执行。
  ///
  /// 参数里的 metadata/creator 等 JSON 文本在写入侧编码，阅读器每 500ms 触发
  /// 一次，放到池里后编码与执行都不占 UI isolate。结果只有自增 id，零拷贝
  /// 没有收益，保留常驻池避免每 500ms spawn。新行插入时 worker 内的
  /// id 回写不会传回调用方对象，因此把 id 返回给调用方自行赋值。
  Future<int> putInWorker(UnifiedComicHistory value) {
    final handle = db.activeHandle;
    return runInWorker(() => _putHistoryInWorker(handle, value));
  }

  Future<List<int>> putMany(List<UnifiedComicHistory> values) async {
    if (values.isEmpty) return const <int>[];
    return db.transaction((tx) async {
      final ids = <int>[];
      for (final value in values) {
        ids.add(await _putInTx(tx, value));
      }
      return ids;
    });
  }

  /// 软删除（同步墓碑）：单条入口，复用 [markDeletedByKeys] 的同一份 SQL。
  Future<int> markDeletedByKey(String uniqueKey) =>
      markDeletedByKeys([uniqueKey]);

  /// 批量软删除历史，按 SQLite 变量上限分块，整个批次在一个事务内完成。
  ///
  /// 删除统一刷新 updatedAt/lastReadAt。章节定位字段（chapterId/chapterOrder）
  /// 保留，避免删除后仍从旧入口打开阅读器时行为变化。
  Future<int> markDeletedByKeys(Iterable<String> uniqueKeys) async {
    final keys = uniqueKeys.toList(growable: false);
    if (keys.isEmpty) return 0;
    final ts = dateToDb(DateTime.now().toUtc());
    var changes = 0;
    await db.transaction((tx) async {
      for (final chunk in chunkParams(keys)) {
        final marks = List.filled(chunk.length, '?').join(',');
        final result = await tx.execute(
          _historyMarkDeleted.replaceFirst('%KEYS%', marks),
          <Object?>[ts, ts, ...chunk],
        );
        changes += result.changes;
      }
    });
    return changes;
  }

  Future<int> removeById(int id) async {
    final result = await db.execute(
      'DELETE FROM "UnifiedComicHistory" WHERE "id" = ?',
      <Object?>[id],
    );
    return result.changes;
  }

  Future<int> removeAll() async {
    final result = await db.execute('DELETE FROM "UnifiedComicHistory"');
    return result.changes;
  }

  Stream<List<UnifiedComicHistory>> watchActive({
    bool ascending = false,
  }) async* {
    yield await listActive(ascending: ascending);
    yield* db.changes
        .where((tables) => tables.contains(table))
        .asyncMap((_) => listActive(ascending: ascending));
  }

  Future<int> _putInTx(DbTransaction tx, UnifiedComicHistory value) async {
    if (value.id > 0) {
      await tx.execute(_historyUpsert, _params(value, includeId: true));
      return value.id;
    }
    final result = await tx.execute(
      _historyInsert,
      _params(value, includeId: false),
    );
    value.id = result.lastInsertId;
    return value.id;
  }

  List<Object?> _params(UnifiedComicHistory v, {required bool includeId}) {
    return <Object?>[
      if (includeId) v.id,
      v.uniqueKey,
      v.source,
      v.comicId,
      v.title,
      v.description,
      v.chapterId,
      v.chapterTitle,
      v.chapterOrder,
      v.pageIndex,
      dateToDb(v.lastReadAt),
      boolToDb(v.deleted),
      v.schemaVersion,
      dateToDb(v.createdAt),
      dateToDb(v.updatedAt),
      comicImageToField(v.cover),
      creatorToField(v.creator),
      comicTitleMetaToField(v.titleMeta),
      comicMetadataToField(v.metadata),
    ];
  }

  static UnifiedComicHistory _decodeRow(Map<String, dynamic> row) {
    return UnifiedComicHistory.fromJson(
      normalizeRow(
        withDefaultId(row),
        dates: const <String>{'createdAt', 'lastReadAt', 'updatedAt'},
        bools: const <String>{'deleted'},
      ),
    );
  }

  static List<UnifiedComicHistory> _decodeAll(
    List<Map<String, dynamic>> rows,
  ) => rows.map(_decodeRow).toList();

  static UnifiedComicHistory? _decodeFirst(List<Map<String, dynamic>> rows) =>
      rows.isEmpty ? null : _decodeRow(rows.first);
}

const _downloadInsert =
    'INSERT INTO "UnifiedComicDownload" '
    '("uniqueKey","source","comicId","title","description","storageRoot",'
    '"createdAt","updatedAt","downloadedAt","deleted","schemaVersion",'
    '"totalViews","totalLikes","totalComments","isFavourite","isLiked",'
    '"allowComment","allowLike","allowFavorite","allowDownload","cover",'
    '"creator","titleMeta","metadata","chapters","detailJson","titleOverride",'
    '"coverOverride") VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)';

const _downloadUpsert =
    'INSERT INTO "UnifiedComicDownload" '
    '("id","uniqueKey","source","comicId","title","description","storageRoot",'
    '"createdAt","updatedAt","downloadedAt","deleted","schemaVersion",'
    '"totalViews","totalLikes","totalComments","isFavourite","isLiked",'
    '"allowComment","allowLike","allowFavorite","allowDownload","cover",'
    '"creator","titleMeta","metadata","chapters","detailJson","titleOverride",'
    '"coverOverride") VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?) '
    'ON CONFLICT("id") DO UPDATE SET '
    '"uniqueKey"=excluded."uniqueKey","source"=excluded."source",'
    '"comicId"=excluded."comicId","title"=excluded."title",'
    '"description"=excluded."description","storageRoot"=excluded."storageRoot",'
    '"createdAt"=excluded."createdAt","updatedAt"=excluded."updatedAt",'
    '"downloadedAt"=excluded."downloadedAt","deleted"=excluded."deleted",'
    '"schemaVersion"=excluded."schemaVersion","totalViews"=excluded."totalViews",'
    '"totalLikes"=excluded."totalLikes","totalComments"=excluded."totalComments",'
    '"isFavourite"=excluded."isFavourite","isLiked"=excluded."isLiked",'
    '"allowComment"=excluded."allowComment","allowLike"=excluded."allowLike",'
    '"allowFavorite"=excluded."allowFavorite","allowDownload"=excluded."allowDownload",'
    '"cover"=excluded."cover","creator"=excluded."creator",'
    '"titleMeta"=excluded."titleMeta","metadata"=excluded."metadata",'
    '"chapters"=excluded."chapters","detailJson"=excluded."detailJson",'
    '"titleOverride"=excluded."titleOverride","coverOverride"=excluded."coverOverride"';

class UnifiedComicDownloadRepository {
  final BreezeDatabase db;

  const UnifiedComicDownloadRepository(this.db);

  static const String table = 'UnifiedComicDownload';

  Future<UnifiedComicDownload?> getById(int id) => runDbRead(
    db,
    sql: 'SELECT * FROM "UnifiedComicDownload" WHERE "id" = ? LIMIT 1',
    params: <Object?>[id],
    decode: _decodeFirst,
  );

  Future<UnifiedComicDownload?> getByKey(String uniqueKey) => runDbRead(
    db,
    sql: 'SELECT * FROM "UnifiedComicDownload" WHERE "uniqueKey" = ? LIMIT 1',
    params: <Object?>[uniqueKey],
    decode: _decodeFirst,
  );

  /// 批量按 uniqueKey 取行（`IN` 分块，避免 SQLite 变量上限）。
  Future<List<UnifiedComicDownload>> getByKeys(List<String> uniqueKeys) async {
    if (uniqueKeys.isEmpty) return const <UnifiedComicDownload>[];
    final rows = <UnifiedComicDownload>[];
    for (final chunk in chunkParams(uniqueKeys)) {
      final marks = List.filled(chunk.length, '?').join(',');
      rows.addAll(
        await runDbRead(
          db,
          sql:
              'SELECT * FROM "UnifiedComicDownload" '
              'WHERE "uniqueKey" IN ($marks)',
          params: chunk,
          decode: _decodeAll,
        ),
      );
    }
    return rows;
  }

  /// 只取 `chapters`（阅读器 worker 用；大字段分开取可少一半 JSON 往返）。
  Future<String?> getChaptersJson(String uniqueKey) => runDbRead(
    db,
    sql:
        'SELECT "chapters" FROM "UnifiedComicDownload" '
        'WHERE "uniqueKey" = ? LIMIT 1',
    params: <Object?>[uniqueKey],
    decode: _decodeFirstString('chapters'),
  );

  /// 只取 `detailJson`（chapters 无图片时兜底，或历史页解析 ComicInfo）。
  Future<String?> getDetailJson(String uniqueKey) => runDbRead(
    db,
    sql:
        'SELECT "detailJson" FROM "UnifiedComicDownload" '
        'WHERE "uniqueKey" = ? LIMIT 1',
    params: <Object?>[uniqueKey],
    decode: _decodeFirstString('detailJson'),
  );

  static String? Function(List<Map<String, dynamic>>) _decodeFirstString(
    String column,
  ) => (rows) {
    if (rows.isEmpty) return null;
    return rows.first[column] as String? ?? '';
  };

  /// 书架用轻量行：不读 `chapters`/`detailJson`（章节含全部图片信息，量很大）。
  Future<List<UnifiedComicDownload>> getShelfByKeys(
    List<String> uniqueKeys,
  ) async {
    if (uniqueKeys.isEmpty) return const <UnifiedComicDownload>[];
    final rows = <UnifiedComicDownload>[];
    for (final chunk in chunkParams(uniqueKeys)) {
      final marks = List.filled(chunk.length, '?').join(',');
      rows.addAll(
        await runDbRead(
          db,
          sql:
              'SELECT "id","uniqueKey","source","comicId","title",'
              '"description","cover","creator","titleMeta","metadata",'
              '"totalViews","totalLikes","totalComments","storageRoot",'
              '"createdAt","updatedAt","downloadedAt","deleted",'
              '"schemaVersion","titleOverride","coverOverride" '
              'FROM "UnifiedComicDownload" WHERE "uniqueKey" IN ($marks)',
          params: chunk,
          decode: _decodeAll,
        ),
      );
    }
    return rows;
  }

  /// 按 comicId 取第一条下载记录（用于来源不一致时的兜底查找）。
  Future<UnifiedComicDownload?> getFirstByComicId(String comicId) => runDbRead(
    db,
    sql:
        'SELECT * FROM "UnifiedComicDownload" WHERE "comicId" = ? '
        'ORDER BY "id" LIMIT 1',
    params: <Object?>[comicId],
    decode: _decodeFirst,
  );

  Future<List<UnifiedComicDownload>> getAll() => runDbRead(
    db,
    sql: 'SELECT * FROM "UnifiedComicDownload" ORDER BY "id"',
    decode: _decodeAll,
  );

  /// 按来源取 uniqueKey（删除插件清理用，只读键不解码整行）。
  Future<List<String>> listKeysBySource(String source) => runDbRead(
    db,
    sql: 'SELECT "uniqueKey" FROM "UnifiedComicDownload" WHERE "source" = ?',
    params: <Object?>[source],
    decode: uniqueKeysFromRows,
  );

  Future<List<UnifiedComicDownload>> listActive() => runDbRead(
    db,
    sql:
        'SELECT * FROM "UnifiedComicDownload" WHERE "deleted" = 0 '
        'ORDER BY "id"',
    decode: _decodeAll,
  );

  Future<int> count() => runDbRead(
    db,
    sql: 'SELECT COUNT(*) AS c FROM "UnifiedComicDownload"',
    decode: countFromRows,
  );

  Future<int> put(UnifiedComicDownload value) async {
    if (value.id > 0) {
      await db.execute(_downloadUpsert, _params(value, includeId: true));
      return value.id;
    }
    final result = await db.execute(
      _downloadInsert,
      _params(value, includeId: false),
    );
    value.id = result.lastInsertId;
    return value.id;
  }

  Future<List<int>> putMany(List<UnifiedComicDownload> values) async {
    if (values.isEmpty) return const <int>[];
    return db.transaction((tx) async {
      final ids = <int>[];
      for (final value in values) {
        ids.add(await _putInTx(tx, value));
      }
      return ids;
    });
  }

  Future<int> removeById(int id) async {
    final result = await db.execute(
      'DELETE FROM "UnifiedComicDownload" WHERE "id" = ?',
      <Object?>[id],
    );
    return result.changes;
  }

  Future<int> removeAll() async {
    final result = await db.execute('DELETE FROM "UnifiedComicDownload"');
    return result.changes;
  }

  Future<int> _putInTx(DbTransaction tx, UnifiedComicDownload value) async {
    if (value.id > 0) {
      await tx.execute(_downloadUpsert, _params(value, includeId: true));
      return value.id;
    }
    final result = await tx.execute(
      _downloadInsert,
      _params(value, includeId: false),
    );
    value.id = result.lastInsertId;
    return value.id;
  }

  List<Object?> _params(UnifiedComicDownload v, {required bool includeId}) {
    return <Object?>[
      if (includeId) v.id,
      v.uniqueKey,
      v.source,
      v.comicId,
      v.title,
      v.description,
      v.storageRoot,
      dateToDb(v.createdAt),
      dateToDb(v.updatedAt),
      dateToDb(v.downloadedAt),
      boolToDb(v.deleted),
      v.schemaVersion,
      v.totalViews,
      v.totalLikes,
      v.totalComments,
      boolToDb(v.isFavourite),
      boolToDb(v.isLiked),
      boolToDb(v.allowComment),
      boolToDb(v.allowLike),
      boolToDb(v.allowFavorite),
      boolToDb(v.allowDownload),
      comicImageToField(v.cover),
      creatorToField(v.creator),
      comicTitleMetaToField(v.titleMeta),
      comicMetadataToField(v.metadata),
      v.chapters,
      v.detailJson,
      v.titleOverride,
      comicImageOrNullToField(v.coverOverride),
    ];
  }

  static UnifiedComicDownload _decodeRow(Map<String, dynamic> row) {
    return UnifiedComicDownload.fromJson(
      normalizeRow(
        withDefaultId(row),
        dates: const <String>{'createdAt', 'updatedAt', 'downloadedAt'},
        bools: const <String>{
          'deleted',
          'isFavourite',
          'isLiked',
          'allowComment',
          'allowLike',
          'allowFavorite',
          'allowDownload',
        },
      ),
    );
  }

  static List<UnifiedComicDownload> _decodeAll(
    List<Map<String, dynamic>> rows,
  ) => rows.map(_decodeRow).toList();

  static UnifiedComicDownload? _decodeFirst(List<Map<String, dynamic>> rows) =>
      rows.isEmpty ? null : _decodeRow(rows.first);
}

/// worker 池内执行历史 upsert；新建行时返回自增 id。
Future<int> _putHistoryInWorker(int handle, UnifiedComicHistory value) async {
  await initRustLib();
  return UnifiedComicHistoryRepository(BreezeDatabase.fromHandle(handle))
      .put(value);
}
