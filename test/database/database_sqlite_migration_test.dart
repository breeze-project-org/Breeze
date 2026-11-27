import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:zephyr/database/app_database.dart';
import 'package:zephyr/database/migration/objectbox_import.dart';
import 'package:zephyr/util/rust/rust_loader.dart';

void main() {
  setUpAll(() async {
    await initRustLib();
  });

  test('SQLite schema, CRUD, rollback and table watcher', () async {
    final temp = await Directory.systemTemp.createTemp('breeze_sqlite_');
    final path = p.join(temp.path, 'breeze.sqlite3');
    final db = await openAppDatabase(
      path: path,
      legacyObjectBoxDir: p.join(temp.path, 'missing_objectbox'),
    );
    try {
      final version = await db.query('PRAGMA user_version');
      expect(version.single['user_version'], currentSchemaVersion);

      final write = await db.execute(
        'INSERT INTO "PluginConfig" ("name", "config") VALUES (?, ?)',
        <Object?>['demo', '{}'],
      );
      expect(write.lastInsertId, 1);

      final rows = await db.query(
        'SELECT * FROM "PluginConfig" WHERE "name" = ?',
        <Object?>['demo'],
      );
      expect(rows, hasLength(1));
      expect(rows.single['config'], '{}');

      await expectLater(
        db.transaction((tx) async {
          await tx.execute(
            'INSERT INTO "PluginConfig" ("name", "config") VALUES (?, ?)',
            <Object?>['rolled-back', '{}'],
          );
          throw StateError('rollback');
        }),
        throwsStateError,
      );
      final count = await db.query('SELECT COUNT(*) AS c FROM "PluginConfig"');
      expect(count.single['c'], 1);

      final change = db.changes.firstWhere(
        (tables) => tables.contains('PluginConfig'),
      );
      await db.execute(
        'INSERT INTO "PluginConfig" ("name", "config") VALUES (?, ?)',
        <Object?>['watched', '{}'],
      );
      expect(
        await change.timeout(const Duration(seconds: 5)),
        contains('PluginConfig'),
      );
    } finally {
      await db.close();
      await temp.delete(recursive: true);
    }
  });

  test('v1 PluginScript rows migrate to scriptUpdatedAt', () async {
    final temp = await Directory.systemTemp.createTemp('breeze_migrate_');
    final path = p.join(temp.path, 'breeze.sqlite3');
    final legacyDir = p.join(temp.path, 'missing_objectbox');
    var db = await openAppDatabase(path: path, legacyObjectBoxDir: legacyDir);
    try {
      // 造一个 v1 库：去掉新列，写入没有 scriptUpdatedAt 的旧数据。
      await db.executeScript(
        'ALTER TABLE "PluginScript" DROP COLUMN "scriptUpdatedAt";',
      );
      await db.execute(
        'INSERT INTO "PluginInfo" ("uuid","version","insertedAt","updatedAt") '
        'VALUES (?,?,?,?)',
        <Object?>['migrate:1', '1.0.0', 1000, 2000],
      );
      await db.execute(
        'INSERT INTO "PluginScript" ("uuid","originScript","revision") '
        'VALUES (?,?,?)',
        <Object?>['migrate:1', 'console.log("legacy");', 'rev-1'],
      );
      await db.executeScript('PRAGMA user_version = 1;');
    } finally {
      await db.close();
    }

    db = await openAppDatabase(path: path, legacyObjectBoxDir: legacyDir);
    try {
      final version = await db.query('PRAGMA user_version');
      expect(version.single['user_version'], currentSchemaVersion);
      final rows = await db.query(
        'SELECT "scriptUpdatedAt" FROM "PluginScript" WHERE "uuid" = ?',
        <Object?>['migrate:1'],
      );
      expect(rows.single['scriptUpdatedAt'], 2000);
    } finally {
      await db.close();
      await temp.delete(recursive: true);
    }
  });

  test('v2 ComicFolder rows migrate to coverComicUniqueKey', () async {
    final temp = await Directory.systemTemp.createTemp('breeze_migrate_');
    final path = p.join(temp.path, 'breeze.sqlite3');
    final legacyDir = p.join(temp.path, 'missing_objectbox');
    var db = await openAppDatabase(path: path, legacyObjectBoxDir: legacyDir);
    try {
      // 造一个 v2 库：去掉新列，写入没有封面的旧文件夹。
      await db.executeScript('''
ALTER TABLE "ComicFolder" DROP COLUMN "coverComicUniqueKey";
PRAGMA user_version = 2;
''');
      await db.execute(
        'INSERT INTO "ComicFolder" '
        '("uniqueKey","name","typeData","versionVectorJson","deletedAt",'
        '"createdAt","updatedAt","syncId","parentSyncId") '
        'VALUES (?,?,?,?,?,?,?,?,?)',
        <Object?>[
          '|migrate|favorite',
          'migrate',
          'favorite',
          '{"test":1}',
          null,
          1000,
          1000,
          'migrate-sync',
          '',
        ],
      );
    } finally {
      await db.close();
    }

    db = await openAppDatabase(path: path, legacyObjectBoxDir: legacyDir);
    try {
      final version = await db.query('PRAGMA user_version');
      expect(version.single['user_version'], currentSchemaVersion);
      final columns = await db.query('PRAGMA table_info("ComicFolder")');
      expect(
        columns.map((row) => row['name']),
        contains('coverComicUniqueKey'),
      );
      final rows = await db.query(
        'SELECT "name", "coverComicUniqueKey" FROM "ComicFolder" '
        'WHERE "syncId" = ?',
        <Object?>['migrate-sync'],
      );
      expect(rows.single['name'], 'migrate');
      expect(rows.single['coverComicUniqueKey'], isNull);
    } finally {
      await db.close();
      await temp.delete(recursive: true);
    }
  });

  test('archives and verifies legacy ObjectBox data.mdb', () async {
    final temp = await Directory.systemTemp.createTemp('breeze_archive_');
    final dataFile = File(p.join(temp.path, 'data.mdb'));
    final archiveFile = File(p.join(temp.path, 'data.mdb.7z'));
    final bytes = List<int>.generate(
      2 * 1024 * 1024,
      (index) => (index * 31 + index ~/ 97) % 251,
    );
    await dataFile.writeAsBytes(bytes, flush: true);
    try {
      final first = jsonDecode(
        await archiveLegacyObjectBoxData(temp.path),
      ) as Map<String, dynamic>;
      expect(first['status'], 'archived');
      expect(await dataFile.exists(), isFalse);
      expect(await archiveFile.exists(), isTrue);
      expect(await archiveFile.length(), lessThan(bytes.length));

      final second = jsonDecode(
        await archiveLegacyObjectBoxData(temp.path),
      ) as Map<String, dynamic>;
      expect(second['status'], 'already_archived');
      expect(second['archiveBytes'], first['archiveBytes']);
    } finally {
      await temp.delete(recursive: true);
    }
  });

  test('schedules archive after migration is already done', () async {
    final temp = await Directory.systemTemp.createTemp('breeze_archive_');
    final oldDir = Directory(p.join(temp.path, 'breeze_db'));
    final dataFile = File(p.join(oldDir.path, 'data.mdb'));
    final archiveFile = File(p.join(oldDir.path, 'data.mdb.7z'));
    final db = await openAppDatabase(
      path: p.join(temp.path, 'breeze.sqlite3'),
      legacyObjectBoxDir: p.join(temp.path, 'missing_objectbox'),
    );
    try {
      await oldDir.create();
      await dataFile.writeAsBytes(
        List<int>.filled(1024 * 1024, 7),
        flush: true,
      );
      await db.execute(
        'INSERT INTO app_meta(key, value) VALUES(?, ?) '
        'ON CONFLICT(key) DO UPDATE SET value = excluded.value',
        <Object?>['objectbox_import_state', 'done'],
      );

      await ensureObjectBoxImport(db, oldDir.path, archiveLegacyData: true);

      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (DateTime.now().isBefore(deadline) &&
          (await dataFile.exists() || !await archiveFile.exists())) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      expect(await archiveFile.exists(), isTrue);
      expect(await dataFile.exists(), isFalse);
    } finally {
      await db.close();
      await temp.delete(recursive: true);
    }
  });

  final oldDb = Platform.environment['BREEZE_OBJECTBOX_TEST_DB'];
  test(
    'imports a real ObjectBox LMDB database',
    () async {
      final temp = await Directory.systemTemp.createTemp('breeze_import_');
      final db = await openAppDatabase(
        path: p.join(temp.path, 'breeze.sqlite3'),
        legacyObjectBoxDir: oldDb!,
      );
      try {
        Future<int> count(String table) async {
          final rows = await db.query('SELECT COUNT(*) AS c FROM "$table"');
          return (rows.single['c'] as num).toInt();
        }

        expect(await count('UserSetting'), 1);
        expect(await count('PluginConfig'), 4);
        expect(await count('PluginInfo'), 6);
        expect(await count('UnifiedComicDownload'), 3);
        expect(await count('UnifiedComicFavorite'), 3);
        expect(await count('UnifiedComicHistory'), 10);
        expect(await count('ComicLink'), 6);
        expect(await count('ComicFollow'), 5);
        expect(await count('ComicReadChapter'), 17);

        // 导入的脚本必须带 revision，否则字节码缓存永远无法命中。
        final emptyRevision = await db.query(
          'SELECT COUNT(*) AS c FROM "PluginScript" '
          'WHERE "revision" = \'\'',
        );
        expect((emptyRevision.single['c'] as num).toInt(), 0);

        final setting = await db.query(
          'SELECT "globalSettingData" FROM "UserSetting" WHERE "id" = 1',
        );
        expect(
          setting.single['globalSettingData'] as String,
          contains('compatibleVersion'),
        );
      } finally {
        await db.close();
        await temp.delete(recursive: true);
      }
    },
    skip: oldDb == null
        ? 'set BREEZE_OBJECTBOX_TEST_DB to an ObjectBox db directory'
        : false,
  );
}
