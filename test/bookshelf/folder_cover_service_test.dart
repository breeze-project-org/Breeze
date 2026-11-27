import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/object_box/model.dart';
import 'package:zephyr/page/bookshelf/service/comic_folder_service.dart';
import 'package:zephyr/page/bookshelf/service/folder_cover_service.dart';

import '../test_helper.dart';

void main() {
  setUpAll(TestDatabaseHelper.setUpTestDatabase);
  tearDownAll(TestDatabaseHelper.tearDownTestDatabase);
  tearDown(TestDatabaseHelper.cleanComicFolderBoxes);

  test('文件夹封面字段随 JSON 往返并兼容旧数据', () {
    final folder = ComicFolder(
      syncId: 'sync-json',
      uniqueKey: '|json|favorite',
      name: 'json',
      typeData: ComicFolderType.favorite.name,
      versionVector: const <String, int>{},
      createdAt: 1,
      updatedAt: 2,
      coverComicUniqueKey: 'test:cover',
    );
    expect(
      ComicFolder.fromJson(folder.toJson()).coverComicUniqueKey,
      'test:cover',
    );
    expect(
      ComicFolder.fromJson(const <String, dynamic>{
        'syncId': 'old',
        'uniqueKey': '|old|favorite',
        'name': 'old',
        'typeData': 'favorite',
      }).coverComicUniqueKey,
      isNull,
    );
  });

  test('设置与清除文件夹封面会写入 SQLite', () async {
    final folder = await ComicFolderService.createFolder(
      '',
      'cover',
      ComicFolderType.favorite,
    );
    final comic = createTestFavorite('test:cover');
    await database.favorites.put(comic);

    await ComicFolderService.setFolderCover(folder, comic.uniqueKey);
    final stored = await database.folders.getBySyncId(folder.syncId);
    expect(stored?.coverComicUniqueKey, comic.uniqueKey);

    await ComicFolderService.setFolderCover(stored!, null);
    final cleared = await database.folders.getBySyncId(folder.syncId);
    expect(cleared?.coverComicUniqueKey, isNull);
  });

  test('封面候选项按加入时间倒序并跳过已删漫画', () async {
    final folder = await ComicFolderService.createFolder(
      '',
      'candidates',
      ComicFolderType.favorite,
    );
    final older = createTestFavorite('test:older');
    final newer = createTestFavorite('test:newer');
    await database.favorites.putMany([older, newer]);
    await database.links.putMany([
      ComicLink(
        uniqueKey: '${older.uniqueKey}|${folder.syncId}|favorite',
        comicUniqueKey: older.uniqueKey,
        folderSyncId: folder.syncId,
        typeData: ComicFolderType.favorite.name,
        versionVector: {},
        createdAt: 1000,
        updatedAt: 1000,
      ),
      ComicLink(
        uniqueKey: '${newer.uniqueKey}|${folder.syncId}|favorite',
        comicUniqueKey: newer.uniqueKey,
        folderSyncId: folder.syncId,
        typeData: ComicFolderType.favorite.name,
        versionVector: {},
        createdAt: 2000,
        updatedAt: 2000,
      ),
    ]);

    final candidates = await FolderCoverService.listCandidates(folder);
    expect(candidates.map((item) => item.info.id), [
      newer.comicId,
      older.comicId,
    ]);

    older.deleted = true;
    await database.favorites.put(older);
    final afterDelete = await FolderCoverService.listCandidates(folder);
    expect(afterDelete.map((item) => item.info.id), [newer.comicId]);
  });
}
