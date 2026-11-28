import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/object_box/model.dart';
import 'package:zephyr/page/bookshelf/method/shelf_load_isolate.dart';
import 'package:zephyr/util/async/worker_pool.dart';

import '../test_helper.dart';

Future<ShelfLoadResult> _load(
  String mode, {
  String currentPath = '',
  int offset = 0,
  int limit = 2000,
  List<String> sources = const <String>[],
}) {
  return loadShelfInIsolate(
    ShelfLoadTask(
      handle: database.db.handle,
      mode: mode,
      currentPath: currentPath,
      keyword: '',
      sort: 'dd',
      sources: sources,
      offset: offset,
      limit: limit,
    ),
  );
}

Future<void> _addLink(String comicUniqueKey, String type) async {
  final now = DateTime.now().toUtc();
  await database.links.put(
    ComicLink(
      uniqueKey: '$comicUniqueKey||$type',
      comicUniqueKey: comicUniqueKey,
      typeData: type,
      versionVector: {},
      createdAt: now.millisecondsSinceEpoch,
      updatedAt: now.millisecondsSinceEpoch,
    ),
  );
}

/// 写入一个收藏文件夹；[parentSyncId] 为空表示根目录。
Future<ComicFolder> _putFolder({
  required String syncId,
  required String name,
  String parentSyncId = '',
  bool deleted = false,
}) async {
  final now = DateTime.now().toUtc().millisecondsSinceEpoch;
  final type = ComicFolderType.favorite.name;
  final folder = ComicFolder(
    syncId: syncId,
    parentSyncId: parentSyncId.isEmpty ? null : parentSyncId,
    uniqueKey: '$parentSyncId|$name|$type',
    name: name,
    typeData: type,
    versionVector: {},
    createdAt: now,
    updatedAt: now,
  );
  if (deleted) folder.deletedAt = now;
  await database.folders.put(folder);
  return folder;
}

/// 在指定文件夹（null = 根目录）下写入 [count] 条收藏链接。
Future<void> _addComicsToFolder(
  String prefix,
  int count,
  String? folderSyncId, {
  String source = 'test',
  bool deleted = false,
}) async {
  final now = DateTime.now().toUtc().millisecondsSinceEpoch;
  for (var i = 0; i < count; i++) {
    final favorite = createTestFavorite(
      '$prefix:$i',
      source: source,
      deleted: deleted,
    );
    await database.favorites.put(favorite);
    await database.links.put(
      ComicLink(
        uniqueKey: '${favorite.uniqueKey}|${folderSyncId ?? ''}|favorite',
        comicUniqueKey: favorite.uniqueKey,
        folderSyncId: folderSyncId,
        typeData: ComicFolderType.favorite.name,
        versionVector: {},
        createdAt: now,
        updatedAt: now,
      ),
    );
  }
}

void main() {
  setUpAll(TestDatabaseHelper.setUpTestDatabase);
  tearDownAll(TestDatabaseHelper.tearDownTestDatabase);
  tearDown(TestDatabaseHelper.cleanComicFolderBoxes);

  test('收藏书架在 worker 内加载', () async {
    final favorite = createTestFavorite('test:fav');
    await database.favorites.put(favorite);
    await _addLink(favorite.uniqueKey, ComicFolderType.favorite.name);

    final result = await _load('favorite');
    expect(result.comics, hasLength(1));
    expect(result.comics.single.id, favorite.comicId);
    expect(result.searchTexts, isNotEmpty);
  });

  test('书架加载经 worker 池返回时可跨 isolate 传递', () async {
    final favorite = createTestFavorite('test:pool');
    await database.favorites.put(favorite);
    await _addLink(favorite.uniqueKey, ComicFolderType.favorite.name);

    // 生产路径：bloc 通过 runInIsolate 提交整个书架任务。
    final task = ShelfLoadTask(
      handle: database.db.handle,
      mode: 'favorite',
      currentPath: '',
      keyword: '',
      sort: 'dd',
      sources: const <String>[],
    );
    final result = await runInIsolate(loadShelfInIsolate, task);
    expect(result.comics, hasLength(1));
    expect(result.comics.single.id, favorite.comicId);
    expect(result.searchTexts, isNotEmpty);
  });

  test('历史书架在 worker 内加载', () async {
    final history = createTestHistory('test:hist');
    await database.histories.put(history);

    final result = await _load('history');
    expect(result.comics, hasLength(1));
    expect(result.comics.single.id, history.comicId);
  });

  test('下载书架在 worker 内加载', () async {
    final download = createTestDownload('test:dl');
    await database.downloads.put(download);
    await _addLink(download.uniqueKey, ComicFolderType.download.name);

    final result = await _load('download');
    expect(result.comics, hasLength(1));
    expect(result.comics.single.id, download.comicId);
  });

  test('同一漫画的多条链接去重，缺失与软删的漫画跳过', () async {
    final favorite = createTestFavorite('test:dup');
    final deleted = createTestFavorite('test:deleted', deleted: true);
    await database.favorites.putMany([favorite, deleted]);
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    ComicLink link(String uniqueKey, String comicUniqueKey) => ComicLink(
      uniqueKey: uniqueKey,
      comicUniqueKey: comicUniqueKey,
      typeData: ComicFolderType.favorite.name,
      versionVector: {},
      createdAt: now,
      updatedAt: now,
    );
    await database.links.putMany([
      link('dup|1', favorite.uniqueKey),
      link('dup|2', favorite.uniqueKey),
      link('missing|1', 'test:missing'),
      link('deleted|1', deleted.uniqueKey),
    ]);

    final result = await _load('favorite');
    expect(result.comics, hasLength(1));
    expect(result.comics.single.id, favorite.comicId);
    expect(result.searchTexts, hasLength(1));
  });

  test('分页按原始行推进并返回 hasMore/nextOffset', () async {
    for (var i = 0; i < 5; i++) {
      final favorite = createTestFavorite('test:page$i');
      await database.favorites.put(favorite);
      await _addLink(favorite.uniqueKey, ComicFolderType.favorite.name);
    }

    final first = await _load('favorite', limit: 2);
    expect(first.comics, hasLength(2));
    expect(first.hasMore, isTrue);
    expect(first.nextOffset, 2);

    final second = await _load('favorite', offset: first.nextOffset, limit: 2);
    expect(second.comics, hasLength(2));
    expect(second.hasMore, isTrue);
    expect(second.nextOffset, 4);

    final third = await _load('favorite', offset: second.nextOffset, limit: 2);
    expect(third.comics, hasLength(1));
    expect(third.hasMore, isFalse);
    expect(third.nextOffset, 5);
  });

  test('书架下载行不读取章节明细', () async {
    final download = createTestDownload('test:lean');
    download.chapters = '{"chapters":[{"images":["a.jpg","b.jpg"]}]}';
    download.detailJson = '{"big":"payload"}';
    await database.downloads.put(download);
    await _addLink(download.uniqueKey, ComicFolderType.download.name);

    final rows = await database.downloads.getShelfByKeys([download.uniqueKey]);
    expect(rows, hasLength(1));
    expect(rows.single.title, download.title);
    expect(rows.single.chapters, isEmpty);
    expect(rows.single.detailJson, isEmpty);

    final result = await _load('download');
    expect(result.comics, hasLength(1));
    expect(result.searchTexts, hasLength(1));
  });

  test('进入子文件夹后能看到其中的漫画与子文件夹', () async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await database.folders.putMany([
      ComicFolder(
        syncId: 'sync-a',
        parentSyncId: '',
        uniqueKey: '|A|favorite',
        name: 'A',
        typeData: ComicFolderType.favorite.name,
        versionVector: {},
        createdAt: now,
        updatedAt: now,
      ),
      ComicFolder(
        syncId: 'sync-b',
        parentSyncId: 'sync-a',
        uniqueKey: 'sync-a|B|favorite',
        name: 'B',
        typeData: ComicFolderType.favorite.name,
        versionVector: {},
        createdAt: now,
        updatedAt: now,
      ),
    ]);
    final favorite = createTestFavorite('test:inA');
    await database.favorites.put(favorite);
    await database.links.put(
      ComicLink(
        uniqueKey: '${favorite.uniqueKey}|sync-a|favorite',
        comicUniqueKey: favorite.uniqueKey,
        folderSyncId: 'sync-a',
        typeData: ComicFolderType.favorite.name,
        versionVector: {},
        createdAt: now,
        updatedAt: now,
      ),
    );

    final root = await _load('favorite');
    expect(root.folders.map((f) => f.name), contains('A'));
    expect(root.folderComicCounts['/A'], 1);

    final inside = await _load('favorite', currentPath: '/A');
    expect(inside.folders.map((f) => f.name), contains('B'));
    expect(inside.comics, hasLength(1));
    expect(inside.comics.single.id, favorite.comicId);
  });

  test('文件夹漫画数跟随来源筛选并跳过已软删漫画', () async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await database.folders.put(
      ComicFolder(
        syncId: 'sync-a',
        parentSyncId: '',
        uniqueKey: '|A|favorite',
        name: 'A',
        typeData: ComicFolderType.favorite.name,
        versionVector: {},
        createdAt: now,
        updatedAt: now,
      ),
    );
    final sourceA = createTestFavorite('src-a:1', source: 'src-a');
    final sourceB = createTestFavorite('src-b:1', source: 'src-b');
    final deleted = createTestFavorite(
      'src-a:2',
      source: 'src-a',
      deleted: true,
    );
    await database.favorites.putMany([sourceA, sourceB, deleted]);
    await database.links.putMany([
      for (final favorite in [sourceA, sourceB, deleted])
        ComicLink(
          uniqueKey: '${favorite.uniqueKey}|sync-a|favorite',
          comicUniqueKey: favorite.uniqueKey,
          folderSyncId: 'sync-a',
          typeData: ComicFolderType.favorite.name,
          versionVector: {},
          createdAt: now,
          updatedAt: now,
        ),
    ]);

    final all = await _load('favorite');
    expect(all.folderComicCounts['/A'], 2);

    final filtered = await _load('favorite', sources: ['src-a']);
    expect(filtered.folderComicCounts['/A'], 1);
  });

  test('文件夹数量递归包含所有子孙文件夹的漫画', () async {
    await _putFolder(syncId: 'sync-test', name: 'test');
    await _putFolder(
      syncId: 'sync-test1',
      name: 'test1',
      parentSyncId: 'sync-test',
    );
    await _putFolder(
      syncId: 'sync-test2',
      name: 'test2',
      parentSyncId: 'sync-test1',
    );
    await _addComicsToFolder('rec:test', 5, 'sync-test');
    await _addComicsToFolder('rec:test1', 3, 'sync-test1');
    await _addComicsToFolder('rec:test2', 2, 'sync-test2');

    final root = await _load('favorite');
    expect(root.folderComicCounts['/test'], 10);

    final insideTest = await _load('favorite', currentPath: '/test');
    expect(insideTest.folders.map((f) => f.name), contains('test1'));
    expect(insideTest.folderComicCounts['/test/test1'], 5);

    final insideTest1 = await _load('favorite', currentPath: '/test/test1');
    expect(insideTest1.folders.map((f) => f.name), contains('test2'));
    expect(insideTest1.folderComicCounts['/test/test1/test2'], 2);
  });

  test('空父文件夹显示子文件夹里的漫画数，空子树不显示', () async {
    await _putFolder(syncId: 'sync-empty', name: 'empty');
    await _putFolder(
      syncId: 'sync-empty-child',
      name: 'child',
      parentSyncId: 'sync-empty',
    );
    await _putFolder(syncId: 'sync-blank', name: 'blank');
    await _addComicsToFolder('empty:child', 3, 'sync-empty-child');

    final root = await _load('favorite');
    expect(root.folderComicCounts['/empty'], 3);
    expect(root.folderComicCounts.containsKey('/blank'), isFalse);

    final inside = await _load('favorite', currentPath: '/empty');
    expect(inside.folderComicCounts['/empty/child'], 3);
  });

  test('递归计数排除软删文件夹、软删漫画与来源筛选', () async {
    await _putFolder(syncId: 'sync-root', name: 'root');
    await _putFolder(
      syncId: 'sync-sub',
      name: 'sub',
      parentSyncId: 'sync-root',
    );
    await _putFolder(
      syncId: 'sync-gone',
      name: 'gone',
      parentSyncId: 'sync-root',
      deleted: true,
    );
    await _addComicsToFolder('keep:root', 1, 'sync-root', source: 'src-a');
    await _addComicsToFolder('keep:sub', 1, 'sync-sub', source: 'src-a');
    await _addComicsToFolder('other:root', 1, 'sync-root', source: 'src-b');
    await _addComicsToFolder(
      'deleted:root',
      2,
      'sync-root',
      source: 'src-a',
      deleted: true,
    );
    await _addComicsToFolder('gone:sub', 2, 'sync-gone', source: 'src-a');

    final all = await _load('favorite');
    expect(all.folderComicCounts['/root'], 3);

    final filtered = await _load('favorite', sources: ['src-a']);
    expect(filtered.folderComicCounts['/root'], 2);

    final inside = await _load(
      'favorite',
      currentPath: '/root',
      sources: ['src-a'],
    );
    expect(inside.folders.map((f) => f.name), isNot(contains('gone')));
    expect(inside.folderComicCounts['/root/sub'], 1);
  });

  test('文件夹封面自动取最新、指定优先、失效回退自动', () async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final folder = ComicFolder(
      syncId: 'sync-cover',
      parentSyncId: '',
      uniqueKey: '|Cover|favorite',
      name: 'Cover',
      typeData: ComicFolderType.favorite.name,
      versionVector: {},
      createdAt: now,
      updatedAt: now,
    );
    await database.folders.put(folder);
    final older = createTestFavorite('test:cover-old');
    final newer = createTestFavorite('test:cover-new');
    await database.favorites.putMany([older, newer]);
    await database.links.putMany([
      ComicLink(
        uniqueKey: '${older.uniqueKey}|sync-cover|favorite',
        comicUniqueKey: older.uniqueKey,
        folderSyncId: folder.syncId,
        typeData: ComicFolderType.favorite.name,
        versionVector: {},
        createdAt: 1000,
        updatedAt: 1000,
      ),
      ComicLink(
        uniqueKey: '${newer.uniqueKey}|sync-cover|favorite',
        comicUniqueKey: newer.uniqueKey,
        folderSyncId: folder.syncId,
        typeData: ComicFolderType.favorite.name,
        versionVector: {},
        createdAt: 2000,
        updatedAt: 2000,
      ),
    ]);

    final auto = await _load('favorite');
    expect(auto.folderCovers['/Cover']?.id, newer.comicId);

    folder.coverComicUniqueKey = older.uniqueKey;
    await database.folders.put(folder);
    final explicit = await _load('favorite');
    expect(explicit.folderCovers['/Cover']?.id, older.comicId);

    older.deleted = true;
    await database.favorites.put(older);
    final fallback = await _load('favorite');
    expect(fallback.folderCovers['/Cover']?.id, newer.comicId);
  });

  test('文件夹自动封面跟随来源筛选', () async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final folder = ComicFolder(
      syncId: 'sync-source',
      parentSyncId: '',
      uniqueKey: '|Source|favorite',
      name: 'Source',
      typeData: ComicFolderType.favorite.name,
      versionVector: {},
      createdAt: now,
      updatedAt: now,
    );
    await database.folders.put(folder);
    final sourceA = createTestFavorite('src-a:cover', source: 'src-a');
    final sourceB = createTestFavorite('src-b:cover', source: 'src-b');
    await database.favorites.putMany([sourceA, sourceB]);
    await database.links.putMany([
      ComicLink(
        uniqueKey: '${sourceA.uniqueKey}|sync-source|favorite',
        comicUniqueKey: sourceA.uniqueKey,
        folderSyncId: folder.syncId,
        typeData: ComicFolderType.favorite.name,
        versionVector: {},
        createdAt: 1000,
        updatedAt: 1000,
      ),
      ComicLink(
        uniqueKey: '${sourceB.uniqueKey}|sync-source|favorite',
        comicUniqueKey: sourceB.uniqueKey,
        folderSyncId: folder.syncId,
        typeData: ComicFolderType.favorite.name,
        versionVector: {},
        createdAt: 2000,
        updatedAt: 2000,
      ),
    ]);

    final filtered = await _load('favorite', sources: ['src-a']);
    expect(filtered.folderCovers['/Source']?.id, sourceA.comicId);
  });
}
