import 'package:zephyr/database/db.dart';
import 'package:zephyr/database/migration/objectbox_import.dart';
import 'package:zephyr/database/schema.dart';

const int currentSchemaVersion = 3;

class DatabaseIncompatibleException implements Exception {
  const DatabaseIncompatibleException(this.message);

  final String message;

  @override
  String toString() => 'DatabaseIncompatibleException: $message';
}

/// 打开应用数据库：建表/索引 → 校验版本 → 一次性导入旧 ObjectBox 数据。
Future<BreezeDatabase> openAppDatabase({
  required String path,
  required String legacyObjectBoxDir,
  bool archiveLegacyData = false,
}) async {
  final db = await BreezeDatabase.open(path);
  try {
    await _ensureSchema(db);
    await ensureObjectBoxImport(
      db,
      legacyObjectBoxDir,
      archiveLegacyData: archiveLegacyData,
    );
    return db;
  } catch (_) {
    await db.close();
    rethrow;
  }
}

Future<void> _ensureSchema(BreezeDatabase db) async {
  final rows = await db.query('PRAGMA user_version');
  final version = rows.isEmpty
      ? 0
      : (rows.first['user_version'] as num?)?.toInt() ?? 0;
  if (version == 0) {
    await db.executeScript(databaseSchemaSql);
    return;
  }
  if (version > currentSchemaVersion) {
    throw DatabaseIncompatibleException(
      'SQLite schema v$version is newer than app v$currentSchemaVersion',
    );
  }
  // 按版本顺序执行 migration，每一步都自己推进 user_version。
  if (version < 2) {
    await db.executeScript('''
ALTER TABLE "PluginScript" ADD COLUMN "scriptUpdatedAt" INTEGER NOT NULL DEFAULT 0;
UPDATE "PluginScript" SET "scriptUpdatedAt" = COALESCE(
  (SELECT "updatedAt" FROM "PluginInfo" WHERE "PluginInfo"."uuid" = "PluginScript"."uuid"),
  0
) WHERE "scriptUpdatedAt" = 0;
PRAGMA user_version = 2;
''');
  }
  if (version < 3) {
    final columns = await db.query('PRAGMA table_info("ComicFolder")');
    final hasCoverColumn = columns.any(
      (row) => row['name'] == 'coverComicUniqueKey',
    );
    await db.executeScript('''
${hasCoverColumn ? '' : 'ALTER TABLE "ComicFolder" ADD COLUMN "coverComicUniqueKey" TEXT;'}
PRAGMA user_version = 3;
''');
  }
}
