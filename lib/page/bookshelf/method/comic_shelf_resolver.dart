import 'package:zephyr/database/database.dart';
import 'package:zephyr/object_box/model.dart';
import 'package:zephyr/page/bookshelf/method/comic_search_text.dart';
import 'package:zephyr/widgets/comic_entry/models/models.dart';
import 'package:zephyr/widgets/comic_simplify_entry/comic_simplify_entry_info.dart';

/// 书架漫画链接解析结果：列表项 + 本地搜索文本。
typedef ResolvedShelfComic = ({ComicSimplifyEntryInfo info, String searchText});

/// 把 `ComicLink.comicUniqueKey` 批量解析成列表项与搜索文本。
///
/// 逐条 `getByKey` 会形成 N+1 查询（300 条链接实测约 88ms），这里按类型
/// 批量 `WHERE "uniqueKey" IN (...)` 预取，只对命中的行做映射与搜索文本。
///
/// 纯数据库函数，不引用 UI 全局状态；书架 isolate 与封面选择弹窗共用。
Future<Map<String, ResolvedShelfComic>> resolveShelfComicsByKeys(
  ComicFolderType folderType,
  List<String> uniqueKeys,
  Database db,
) async {
  final keys = uniqueKeys.where((key) => key.isNotEmpty).toSet().toList();
  final resolved = <String, ResolvedShelfComic>{};
  if (keys.isEmpty) return resolved;

  switch (folderType) {
    case ComicFolderType.favorite:
      for (final comic in await db.favorites.getByKeys(keys)) {
        if (comic.deleted) continue;
        resolved[comic.uniqueKey] = (
          info: unifiedComicFromUnifiedFavorite(comic).toSimplifyEntryInfo(),
          searchText: buildComicSearchText(comic),
        );
      }
    case ComicFolderType.download:
      // 书架不返回章节明细：查询不取 chapters/detailJson，映射也不带 raw。
      for (final comic in await db.downloads.getShelfByKeys(keys)) {
        if (comic.deleted) continue;
        resolved[comic.uniqueKey] = (
          info: unifiedComicFromUnifiedDownload(
            comic,
            includeRaw: false,
          ).toSimplifyEntryInfo(),
          searchText: buildComicSearchText(comic),
        );
      }
    case ComicFolderType.history:
      for (final comic in await db.histories.getByKeys(keys)) {
        if (comic.deleted) continue;
        resolved[comic.uniqueKey] = (
          info: unifiedComicFromUnifiedHistory(comic).toSimplifyEntryInfo(),
          searchText: buildComicSearchText(comic),
        );
      }
  }
  return resolved;
}
