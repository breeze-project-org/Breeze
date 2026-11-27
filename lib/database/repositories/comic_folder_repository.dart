import 'package:zephyr/database/db.dart';
import 'package:zephyr/database/db_read.dart';
import 'package:zephyr/database/row_codec.dart';
import 'package:zephyr/object_box/model.dart';
import 'package:zephyr/object_box/model_json_codec.dart';

const _folderInsert =
    'INSERT INTO "ComicFolder" '
    '("uniqueKey","name","typeData","versionVectorJson","deletedAt",'
    '"createdAt","updatedAt","syncId","parentSyncId","coverComicUniqueKey") '
    'VALUES (?,?,?,?,?,?,?,?,?,?)';

const _folderUpsert =
    'INSERT INTO "ComicFolder" '
    '("id","uniqueKey","name","typeData","versionVectorJson","deletedAt",'
    '"createdAt","updatedAt","syncId","parentSyncId","coverComicUniqueKey") '
    'VALUES (?,?,?,?,?,?,?,?,?,?,?) '
    'ON CONFLICT("id") DO UPDATE SET '
    '"uniqueKey"=excluded."uniqueKey","name"=excluded."name",'
    '"typeData"=excluded."typeData",'
    '"versionVectorJson"=excluded."versionVectorJson",'
    '"deletedAt"=excluded."deletedAt","createdAt"=excluded."createdAt",'
    '"updatedAt"=excluded."updatedAt","syncId"=excluded."syncId",'
    '"parentSyncId"=excluded."parentSyncId",'
    '"coverComicUniqueKey"=excluded."coverComicUniqueKey"';

class ComicFolderRepository {
  final BreezeDatabase db;

  const ComicFolderRepository(this.db);

  static const String table = 'ComicFolder';

  Future<ComicFolder?> getById(int id) => runDbRead(
    db,
    sql: 'SELECT * FROM "ComicFolder" WHERE "id" = ? LIMIT 1',
    params: <Object?>[id],
    decode: _decodeFirst,
  );

  Future<ComicFolder?> getByUniqueKey(String uniqueKey) => runDbRead(
    db,
    sql: 'SELECT * FROM "ComicFolder" WHERE "uniqueKey" = ? LIMIT 1',
    params: <Object?>[uniqueKey],
    decode: _decodeFirst,
  );

  Future<ComicFolder?> getBySyncId(String syncId) => runDbRead(
    db,
    sql: 'SELECT * FROM "ComicFolder" WHERE "syncId" = ? LIMIT 1',
    params: <Object?>[syncId],
    decode: _decodeFirst,
  );

  Future<List<ComicFolder>> getAll() => runDbRead(
    db,
    sql: 'SELECT * FROM "ComicFolder" ORDER BY "id"',
    decode: _decodeAll,
  );

  Future<List<ComicFolder>> listByType(
    String typeData, {
    bool ascending = true,
  }) {
    final direction = ascending ? 'ASC' : 'DESC';
    return runDbRead(
      db,
      sql:
          'SELECT * FROM "ComicFolder" WHERE "typeData" = ? '
          'ORDER BY "name" $direction, "id" $direction',
      params: <Object?>[typeData],
      decode: _decodeAll,
    );
  }

  Future<List<ComicFolder>> listChildren(
    String? parentSyncId,
    String typeData, {
    bool ascending = true,
  }) {
    final direction = ascending ? 'ASC' : 'DESC';
    final sql = parentSyncId == null || parentSyncId.isEmpty
        ? 'SELECT * FROM "ComicFolder" WHERE "typeData" = ? '
              'AND ("parentSyncId" IS NULL OR "parentSyncId" = \'\') '
              'ORDER BY "name" $direction, "id" $direction'
        : 'SELECT * FROM "ComicFolder" WHERE "typeData" = ? '
              'AND "parentSyncId" = ? '
              'ORDER BY "name" $direction, "id" $direction';
    return runDbRead(
      db,
      sql: sql,
      params: parentSyncId == null || parentSyncId.isEmpty
          ? <Object?>[typeData]
          : <Object?>[typeData, parentSyncId],
      decode: _decodeAll,
    );
  }

  /// 某类型下所有未软删除的文件夹，按 createdAt 排序。
  Future<List<ComicFolder>> listActiveByType(
    String typeData, {
    bool ascending = false,
  }) {
    final direction = ascending ? 'ASC' : 'DESC';
    return runDbRead(
      db,
      sql:
          'SELECT * FROM "ComicFolder" WHERE "typeData" = ? '
          'AND "deletedAt" IS NULL '
          'ORDER BY "createdAt" $direction, "id" $direction',
      params: <Object?>[typeData],
      decode: _decodeAll,
    );
  }

  /// 某路径下未软删除的直接子文件夹，按 createdAt 排序。
  Future<List<ComicFolder>> listActiveChildren(
    String? parentSyncId,
    String typeData, {
    bool ascending = false,
  }) {
    final direction = ascending ? 'ASC' : 'DESC';
    final sql = parentSyncId == null || parentSyncId.isEmpty
        ? 'SELECT * FROM "ComicFolder" WHERE "typeData" = ? '
              'AND "deletedAt" IS NULL '
              'AND ("parentSyncId" IS NULL OR "parentSyncId" = \'\') '
              'ORDER BY "createdAt" $direction, "id" $direction'
        : 'SELECT * FROM "ComicFolder" WHERE "typeData" = ? '
              'AND "deletedAt" IS NULL AND "parentSyncId" = ? '
              'ORDER BY "createdAt" $direction, "id" $direction';
    return runDbRead(
      db,
      sql: sql,
      params: parentSyncId == null || parentSyncId.isEmpty
          ? <Object?>[typeData]
          : <Object?>[typeData, parentSyncId],
      decode: _decodeAll,
    );
  }

  Future<List<ComicFolder>> listBySyncIds(List<String> syncIds) async {
    if (syncIds.isEmpty) return const <ComicFolder>[];
    final marks = List.filled(syncIds.length, '?').join(',');
    return runDbRead(
      db,
      sql: 'SELECT * FROM "ComicFolder" WHERE "syncId" IN ($marks)',
      params: syncIds,
      decode: _decodeAll,
    );
  }

  Future<int> count() => runDbRead(
    db,
    sql: 'SELECT COUNT(*) AS c FROM "ComicFolder"',
    decode: countFromRows,
  );

  Future<int> put(ComicFolder value) async {
    if (value.id > 0) {
      await db.execute(_folderUpsert, _params(value, includeId: true));
      return value.id;
    }
    final result = await db.execute(
      _folderInsert,
      _params(value, includeId: false),
    );
    value.id = result.lastInsertId;
    return value.id;
  }

  Future<List<int>> putMany(List<ComicFolder> values) async {
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
      'DELETE FROM "ComicFolder" WHERE "id" = ?',
      <Object?>[id],
    );
    return result.changes;
  }

  Future<int> removeByType(String typeData) async {
    final result = await db.execute(
      'DELETE FROM "ComicFolder" WHERE "typeData" = ?',
      <Object?>[typeData],
    );
    return result.changes;
  }

  Future<int> removeAll() async {
    final result = await db.execute('DELETE FROM "ComicFolder"');
    return result.changes;
  }

  Future<int> _putInTx(DbTransaction tx, ComicFolder value) async {
    if (value.id > 0) {
      await tx.execute(_folderUpsert, _params(value, includeId: true));
      return value.id;
    }
    final result = await tx.execute(
      _folderInsert,
      _params(value, includeId: false),
    );
    value.id = result.lastInsertId;
    return value.id;
  }

  List<Object?> _params(ComicFolder v, {required bool includeId}) {
    return <Object?>[
      if (includeId) v.id,
      v.uniqueKey,
      v.name,
      v.typeData,
      versionVectorToField(v.versionVector),
      v.deletedAt,
      v.createdAt,
      v.updatedAt,
      v.syncId,
      v.parentSyncId,
      v.coverComicUniqueKey,
    ];
  }

  static ComicFolder _decodeRow(Map<String, dynamic> row) {
    return ComicFolder.fromJson(withDefaultId(row));
  }

  static List<ComicFolder> _decodeAll(List<Map<String, dynamic>> rows) =>
      rows.map(_decodeRow).toList();

  static ComicFolder? _decodeFirst(List<Map<String, dynamic>> rows) =>
      rows.isEmpty ? null : _decodeRow(rows.first);
}

const _linkInsert =
    'INSERT INTO "ComicLink" '
    '("uniqueKey","typeData","versionVectorJson","deletedAt","createdAt",'
    '"updatedAt","comicUniqueKey","folderSyncId") VALUES (?,?,?,?,?,?,?,?)';

const _linkUpsert =
    'INSERT INTO "ComicLink" '
    '("id","uniqueKey","typeData","versionVectorJson","deletedAt","createdAt",'
    '"updatedAt","comicUniqueKey","folderSyncId") VALUES (?,?,?,?,?,?,?,?,?) '
    'ON CONFLICT("id") DO UPDATE SET '
    '"uniqueKey"=excluded."uniqueKey","typeData"=excluded."typeData",'
    '"versionVectorJson"=excluded."versionVectorJson",'
    '"deletedAt"=excluded."deletedAt","createdAt"=excluded."createdAt",'
    '"updatedAt"=excluded."updatedAt",'
    '"comicUniqueKey"=excluded."comicUniqueKey",'
    '"folderSyncId"=excluded."folderSyncId"';

class ComicLinkRepository {
  final BreezeDatabase db;

  const ComicLinkRepository(this.db);

  static const String table = 'ComicLink';

  Future<ComicLink?> getById(int id) => runDbRead(
    db,
    sql: 'SELECT * FROM "ComicLink" WHERE "id" = ? LIMIT 1',
    params: <Object?>[id],
    decode: _decodeFirst,
  );

  Future<ComicLink?> getByUniqueKey(String uniqueKey) => runDbRead(
    db,
    sql: 'SELECT * FROM "ComicLink" WHERE "uniqueKey" = ? LIMIT 1',
    params: <Object?>[uniqueKey],
    decode: _decodeFirst,
  );

  Future<List<ComicLink>> getAll() => runDbRead(
    db,
    sql: 'SELECT * FROM "ComicLink" ORDER BY "id"',
    decode: _decodeAll,
  );

  Future<List<ComicLink>> listByType(String typeData, {bool ascending = true}) {
    final direction = ascending ? 'ASC' : 'DESC';
    return runDbRead(
      db,
      sql:
          'SELECT * FROM "ComicLink" WHERE "typeData" = ? '
          'ORDER BY "createdAt" $direction, "id" $direction',
      params: <Object?>[typeData],
      decode: _decodeAll,
    );
  }

  Future<List<ComicLink>> listByFolder(
    String? folderSyncId,
    String typeData, {
    bool ascending = true,
  }) {
    final direction = ascending ? 'ASC' : 'DESC';
    final sql = folderSyncId == null || folderSyncId.isEmpty
        ? 'SELECT * FROM "ComicLink" WHERE "typeData" = ? '
              'AND ("folderSyncId" IS NULL OR "folderSyncId" = \'\') '
              'ORDER BY "createdAt" $direction, "id" $direction'
        : 'SELECT * FROM "ComicLink" WHERE "typeData" = ? '
              'AND "folderSyncId" = ? '
              'ORDER BY "createdAt" $direction, "id" $direction';
    return runDbRead(
      db,
      sql: sql,
      params: folderSyncId == null || folderSyncId.isEmpty
          ? <Object?>[typeData]
          : <Object?>[typeData, folderSyncId],
      decode: _decodeAll,
    );
  }

  /// 某类型下全部未软删除的链接，按 createdAt 排序。
  Future<List<ComicLink>> listActiveByType(
    String typeData, {
    bool ascending = false,
  }) {
    final direction = ascending ? 'ASC' : 'DESC';
    return runDbRead(
      db,
      sql:
          'SELECT * FROM "ComicLink" WHERE "typeData" = ? '
          'AND "deletedAt" IS NULL '
          'ORDER BY "createdAt" $direction, "id" $direction',
      params: <Object?>[typeData],
      decode: _decodeAll,
    );
  }

  /// 某路径下未软删除的链接，按 createdAt 排序。
  Future<List<ComicLink>> listActiveByFolder(
    String? folderSyncId,
    String typeData, {
    bool ascending = false,
  }) {
    final direction = ascending ? 'ASC' : 'DESC';
    final sql = folderSyncId == null || folderSyncId.isEmpty
        ? 'SELECT * FROM "ComicLink" WHERE "typeData" = ? '
              'AND "deletedAt" IS NULL '
              'AND ("folderSyncId" IS NULL OR "folderSyncId" = \'\') '
              'ORDER BY "createdAt" $direction, "id" $direction'
        : 'SELECT * FROM "ComicLink" WHERE "typeData" = ? '
              'AND "deletedAt" IS NULL AND "folderSyncId" = ? '
              'ORDER BY "createdAt" $direction, "id" $direction';
    return runDbRead(
      db,
      sql: sql,
      params: folderSyncId == null || folderSyncId.isEmpty
          ? <Object?>[typeData]
          : <Object?>[typeData, folderSyncId],
      decode: _decodeAll,
    );
  }

  /// 书架分页查询：按目录与排序取一页未软删除的链接。
  ///
  /// [allFolders] 为 true 时不限制目录（搜索）；否则 [folderSyncId] 为空
  /// 表示根目录。`vd`/`va` 按观看时间排序（LEFT JOIN 历史表，未观看的
  /// 条目恒在已观看之后），其余按 createdAt。
  Future<List<ComicLink>> listShelfLinks({
    required String typeData,
    String? folderSyncId,
    bool allFolders = false,
    String sort = 'dd',
    int offset = 0,
    int limit = 200,
  }) {
    final direction = sort == 'da' || sort == 'va' ? 'ASC' : 'DESC';
    final byViewTime = sort == 'vd' || sort == 'va';
    final where = StringBuffer('l."typeData" = ? AND l."deletedAt" IS NULL');
    final params = <Object?>[typeData];
    if (!allFolders) {
      if (folderSyncId == null || folderSyncId.isEmpty) {
        where.write(
          ' AND (l."folderSyncId" IS NULL OR l."folderSyncId" = \'\')',
        );
      } else {
        where.write(' AND l."folderSyncId" = ?');
        params.add(folderSyncId);
      }
    }
    var joins = '';
    var order = 'l."createdAt" $direction, l."id" $direction';
    if (byViewTime) {
      joins =
          ' LEFT JOIN "UnifiedComicHistory" AS h '
          'ON h."uniqueKey" = l."comicUniqueKey" AND h."deleted" = 0';
      var itemTime = 'l."createdAt"';
      if (typeData == ComicFolderType.favorite.name) {
        joins +=
            ' LEFT JOIN "UnifiedComicFavorite" AS f '
            'ON f."uniqueKey" = l."comicUniqueKey"';
        itemTime = 'COALESCE(f."createdAt", l."createdAt")';
      } else if (typeData == ComicFolderType.download.name) {
        joins +=
            ' LEFT JOIN "UnifiedComicDownload" AS d '
            'ON d."uniqueKey" = l."comicUniqueKey"';
        itemTime = 'COALESCE(d."downloadedAt", l."createdAt")';
      }
      order =
          '(h."lastReadAt" IS NULL) ASC, h."lastReadAt" $direction, '
          '$itemTime $direction, l."id" $direction';
    }
    params
      ..add(limit)
      ..add(offset);
    return runDbRead(
      db,
      sql:
          'SELECT l.* FROM "ComicLink" AS l$joins '
          'WHERE $where '
          'ORDER BY $order LIMIT ? OFFSET ?',
      params: params,
      decode: _decodeAll,
    );
  }

  /// 各文件夹下未软删除链接数，键为文件夹 syncId（空串表示根目录）。
  ///
  /// [sources] 非空时只统计这些来源的漫画，与书架列表的来源筛选保持一致。
  /// 计数同时关联漫画本体表并跳过已软删除的记录，避免详情模式的「N 本」
  /// 把列表里看不到的条目也算进去。
  Future<Map<String, int>> countActiveByFolder(
    String typeData, {
    List<String> sources = const <String>[],
  }) {
    final comicTable = typeData == ComicFolderType.favorite.name
        ? '"UnifiedComicFavorite"'
        : typeData == ComicFolderType.download.name
        ? '"UnifiedComicDownload"'
        : null;
    if (comicTable == null) {
      return runDbRead(
        db,
        sql:
            'SELECT "folderSyncId", COUNT(*) AS c FROM "ComicLink" '
            'WHERE "typeData" = ? AND "deletedAt" IS NULL '
            'GROUP BY "folderSyncId"',
        params: <Object?>[typeData],
        decode: _decodeFolderCounts,
      );
    }
    final cleanedSources = <String>[
      for (final source in sources)
        if (source.trim().isNotEmpty) source.trim(),
    ];
    final sourceClause = cleanedSources.isEmpty
        ? ''
        : ' AND TRIM(m."source") IN (${List.filled(cleanedSources.length, '?').join(',')})';
    return runDbRead(
      db,
      sql:
          'SELECT l."folderSyncId", COUNT(*) AS c FROM "ComicLink" AS l '
          'JOIN $comicTable AS m ON m."uniqueKey" = l."comicUniqueKey" '
          'AND m."deleted" = 0 '
          'WHERE l."typeData" = ? AND l."deletedAt" IS NULL'
          '$sourceClause '
          'GROUP BY l."folderSyncId"',
      params: <Object?>[typeData, ...cleanedSources],
      decode: _decodeFolderCounts,
    );
  }

  static Map<String, int> _decodeFolderCounts(
    List<Map<String, dynamic>> rows,
  ) => <String, int>{
    for (final row in rows)
      (row['folderSyncId'] as String? ?? ''): (row['c'] as num).toInt(),
  };

  /// 每个文件夹下最新加入的未删除漫画链接，用于文件夹自动封面。
  ///
  /// 返回 `folderSyncId -> comicUniqueKey`。排序与书架默认排序一致：
  /// `createdAt DESC, id DESC`，保证同时间写入时结果稳定。
  Future<Map<String, String>> latestComicKeyByFolder(
    String typeData, {
    List<String> sources = const <String>[],
  }) {
    final comicTable = typeData == ComicFolderType.favorite.name
        ? '"UnifiedComicFavorite"'
        : typeData == ComicFolderType.download.name
        ? '"UnifiedComicDownload"'
        : null;
    if (comicTable == null) {
      return Future<Map<String, String>>.value(const <String, String>{});
    }
    final cleanedSources = <String>[
      for (final source in sources)
        if (source.trim().isNotEmpty) source.trim(),
    ];
    final sourceClause = cleanedSources.isEmpty
        ? ''
        : ' AND TRIM(m."source") IN (${List.filled(cleanedSources.length, '?').join(',')})';
    return runDbRead(
      db,
      sql:
          'SELECT "folderSyncId", "comicUniqueKey" FROM ('
          'SELECT l."folderSyncId" AS "folderSyncId", '
          'l."comicUniqueKey" AS "comicUniqueKey", '
          'ROW_NUMBER() OVER ('
          'PARTITION BY l."folderSyncId" '
          'ORDER BY l."createdAt" DESC, l."id" DESC'
          ') AS "rn" '
          'FROM "ComicLink" AS l '
          'JOIN $comicTable AS m ON m."uniqueKey" = l."comicUniqueKey" '
          'AND m."deleted" = 0 '
          'WHERE l."typeData" = ? AND l."deletedAt" IS NULL '
          'AND l."folderSyncId" IS NOT NULL AND l."folderSyncId" != \'\''
          '$sourceClause'
          ') WHERE "rn" = 1',
      params: <Object?>[typeData, ...cleanedSources],
      decode: _decodeLatestComicKeys,
    );
  }

  static Map<String, String> _decodeLatestComicKeys(
    List<Map<String, dynamic>> rows,
  ) {
    final result = <String, String>{};
    for (final row in rows) {
      final folderSyncId = row['folderSyncId'] as String? ?? '';
      final comicUniqueKey = row['comicUniqueKey'] as String? ?? '';
      if (folderSyncId.isNotEmpty && comicUniqueKey.isNotEmpty) {
        result[folderSyncId] = comicUniqueKey;
      }
    }
    return result;
  }

  /// 漫画在某类型下未软删除的全部链接（含根目录）。
  Future<List<ComicLink>> listActiveByComic(
    String comicUniqueKey,
    String typeData,
  ) => runDbRead(
    db,
    sql:
        'SELECT * FROM "ComicLink" WHERE "typeData" = ? '
        'AND "deletedAt" IS NULL AND "comicUniqueKey" = ? '
        'ORDER BY "createdAt" ASC, "id" ASC',
    params: <Object?>[typeData, comicUniqueKey],
    decode: _decodeAll,
  );

  Future<List<ComicLink>> listByComic(
    String comicUniqueKey, {
    String? typeData,
  }) {
    final sql = typeData == null
        ? 'SELECT * FROM "ComicLink" WHERE "comicUniqueKey" = ?'
        : 'SELECT * FROM "ComicLink" WHERE "comicUniqueKey" = ? '
              'AND "typeData" = ?';
    return runDbRead(
      db,
      sql: sql,
      params: typeData == null
          ? <Object?>[comicUniqueKey]
          : <Object?>[comicUniqueKey, typeData],
      decode: _decodeAll,
    );
  }

  Future<List<ComicLink>> listByFolderSyncIds(
    List<String> syncIds, {
    String? typeData,
  }) async {
    if (syncIds.isEmpty) return const <ComicLink>[];
    final marks = List.filled(syncIds.length, '?').join(',');
    final sql = typeData == null
        ? 'SELECT * FROM "ComicLink" WHERE "folderSyncId" IN ($marks)'
        : 'SELECT * FROM "ComicLink" WHERE "folderSyncId" IN ($marks) '
              'AND "typeData" = ?';
    return runDbRead(
      db,
      sql: sql,
      params: typeData == null ? syncIds : <Object?>[...syncIds, typeData],
      decode: _decodeAll,
    );
  }

  Future<int> count() => runDbRead(
    db,
    sql: 'SELECT COUNT(*) AS c FROM "ComicLink"',
    decode: countFromRows,
  );

  Future<int> put(ComicLink value) async {
    if (value.id > 0) {
      await db.execute(_linkUpsert, _params(value, includeId: true));
      return value.id;
    }
    final result = await db.execute(
      _linkInsert,
      _params(value, includeId: false),
    );
    value.id = result.lastInsertId;
    return value.id;
  }

  Future<List<int>> putMany(List<ComicLink> values) async {
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
      'DELETE FROM "ComicLink" WHERE "id" = ?',
      <Object?>[id],
    );
    return result.changes;
  }

  Future<int> removeByType(String typeData) async {
    final result = await db.execute(
      'DELETE FROM "ComicLink" WHERE "typeData" = ?',
      <Object?>[typeData],
    );
    return result.changes;
  }

  Future<int> removeAll() async {
    final result = await db.execute('DELETE FROM "ComicLink"');
    return result.changes;
  }

  Future<int> _putInTx(DbTransaction tx, ComicLink value) async {
    if (value.id > 0) {
      await tx.execute(_linkUpsert, _params(value, includeId: true));
      return value.id;
    }
    final result = await tx.execute(
      _linkInsert,
      _params(value, includeId: false),
    );
    value.id = result.lastInsertId;
    return value.id;
  }

  List<Object?> _params(ComicLink v, {required bool includeId}) {
    return <Object?>[
      if (includeId) v.id,
      v.uniqueKey,
      v.typeData,
      versionVectorToField(v.versionVector),
      v.deletedAt,
      v.createdAt,
      v.updatedAt,
      v.comicUniqueKey,
      v.folderSyncId,
    ];
  }

  static ComicLink _decodeRow(Map<String, dynamic> row) {
    return ComicLink.fromJson(withDefaultId(row));
  }

  static List<ComicLink> _decodeAll(List<Map<String, dynamic>> rows) =>
      rows.map(_decodeRow).toList();

  static ComicLink? _decodeFirst(List<Map<String, dynamic>> rows) =>
      rows.isEmpty ? null : _decodeRow(rows.first);
}
