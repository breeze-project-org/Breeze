import 'package:zephyr/database/database.dart';
import 'package:zephyr/object_box/model.dart';
import 'package:zephyr/page/bookshelf/method/comic_search_text.dart';
import 'package:zephyr/page/bookshelf/method/comic_shelf_resolver.dart';
import 'package:zephyr/page/bookshelf/models/shelf_page_mode.dart';
import 'package:zephyr/page/bookshelf/service/comic_folder_service.dart';
import 'package:zephyr/util/rust/rust_loader.dart';
import 'package:zephyr/widgets/comic_entry/models/models.dart';
import 'package:zephyr/widgets/comic_simplify_entry/comic_simplify_entry_info.dart';

/// 书架分页大小：收藏/历史 2000，下载数据量大用 200。
int shelfPageSize(ShelfPageMode mode) =>
    mode == ShelfPageMode.download ? 200 : 2000;

/// 单页结果为空但仍有更多数据时，最多连续翻几页再返回（搜索/失效链接场景）。
const int _maxSparsePages = 5;

/// 书架加载任务：只携带可跨 isolate 传递的简单参数。
class ShelfLoadTask {
  const ShelfLoadTask({
    required this.handle,
    required this.mode,
    required this.currentPath,
    required this.keyword,
    required this.sort,
    required this.sources,
    this.offset = 0,
    this.limit = 2000,
  });

  final int handle;
  final String mode;
  final String currentPath;
  final String keyword;
  final String sort;
  final List<String> sources;

  /// 主列表（链接/历史）的起始行偏移。
  final int offset;

  /// 本次最多取多少行原始记录。
  final int limit;
}

/// 书架加载结果：全部为普通 Dart 对象，可由 `compute` 零拷贝交回 UI。
class ShelfLoadResult {
  const ShelfLoadResult({
    required this.folders,
    required this.folderComicCounts,
    required this.folderCovers,
    required this.comics,
    required this.searchTexts,
    required this.nextOffset,
    required this.hasMore,
  });

  final List<ComicFolder> folders;
  final Map<String, int> folderComicCounts;

  /// 当前路径下每个文件夹卡片要显示的封面，键为文件夹完整路径。
  final Map<String, ComicSimplifyEntryInfo> folderCovers;
  final List<ComicSimplifyEntryInfo> comics;
  final Map<String, String> searchTexts;

  /// 下一页应使用的偏移（已包含第一页的空页补偿）。
  final int nextOffset;

  /// 是否还有更多原始行可加载。
  final bool hasMore;
}

/// 在 compute isolate 内完成书架（收藏/历史/下载）的查询、解码与映射。
///
/// 分页按原始行（ComicLink / UnifiedComicHistory）计数；单页解不出漫画时
/// （链接失效、搜索不匹配）会在同一个 isolate 内最多续翻 5 页。
///
/// 注意：不能引用 UI 全局状态（`database`、`globalSetting`、`BuildContext`）；
/// RustLib 需要在本 isolate 内初始化。
Future<ShelfLoadResult> loadShelfInIsolate(ShelfLoadTask task) async {
  await initRustLib();
  final db = Database.fromHandle(task.handle);
  final mode = ShelfPageMode.values.byName(task.mode);
  final folderType = comicFolderTypeOf(mode);
  final keyword = task.keyword;
  final sort = task.sort;
  final sortAscending = sort == 'da';
  final sourceFilter = _sourceFilter(task.sources);
  final isSearching = keyword.trim().isNotEmpty;
  final normalizedKeyword = isSearching ? normalizeSearchText(keyword) : '';

  // 历史无文件夹体系：直读历史表分页。
  if (mode == ShelfPageMode.history) {
    return _loadHistoryShelf(
      db,
      sortAscending: sortAscending,
      keyword: keyword,
      sourceFilter: sourceFilter,
      offset: task.offset,
      pageSize: task.limit,
    );
  }

  // 文件夹与计数只在第一页计算；搜索时不展示文件夹。
  final isFirstPage = task.offset == 0;
  final folders = isFirstPage && !isSearching
      ? await ComicFolderService.listChildFolders(
          task.currentPath,
          folderType,
          sortAscending: sortAscending,
          db: db,
        )
      : const <ComicFolder>[];
  // 文件夹数量按「自身 + 所有未删除子孙文件夹」递归统计：根目录的 /test
  // 需要把 /test/test1 里的漫画也算进去，否则父文件夹看起来是空的。
  var folderComicCounts = const <String, int>{};
  if (isFirstPage && !isSearching && folders.isNotEmpty) {
    final directCounts = await db.links.countActiveByFolder(
      folderType.name,
      sources: task.sources,
    );
    final activeFolders = await db.folders.listActiveByType(folderType.name);
    final subtreeCounts = _computeFolderSubtreeCounts(
      folders: folders,
      activeFolders: activeFolders,
      directCounts: directCounts,
    );
    folderComicCounts = <String, int>{
      for (final folder in folders)
        if ((subtreeCounts[folder.syncId] ?? 0) > 0)
          (task.currentPath.isEmpty
                  ? '/${folder.name}'
                  : '${task.currentPath}/${folder.name}'):
              subtreeCounts[folder.syncId]!,
    };
  }

  var folderCovers = const <String, ComicSimplifyEntryInfo>{};
  if (isFirstPage && !isSearching && folders.isNotEmpty) {
    String pathOf(ComicFolder folder) => task.currentPath.isEmpty
        ? '/${folder.name}'
        : '${task.currentPath}/${folder.name}';
    final latestKeys = await db.links.latestComicKeyByFolder(
      folderType.name,
      sources: task.sources,
    );
    final autoKeys = <String, String>{
      for (final folder in folders)
        if ((latestKeys[folder.syncId] ?? '').isNotEmpty)
          folder.syncId: latestKeys[folder.syncId]!,
    };
    final explicitKeys = <String, String>{
      for (final folder in folders)
        if ((folder.coverComicUniqueKey ?? '').trim().isNotEmpty)
          folder.syncId: folder.coverComicUniqueKey!.trim(),
    };
    final keys = <String>{...autoKeys.values, ...explicitKeys.values};
    if (keys.isNotEmpty) {
      final resolved = await resolveShelfComicsByKeys(
        folderType,
        keys.toList(),
        db,
      );
      final covers = <String, ComicSimplifyEntryInfo>{};
      for (final folder in folders) {
        final explicit = explicitKeys[folder.syncId];
        final auto = autoKeys[folder.syncId];
        final info =
            (explicit == null ? null : resolved[explicit]) ??
            (auto == null ? null : resolved[auto]);
        if (info != null) {
          covers[pathOf(folder)] = info.info;
        }
      }
      folderCovers = covers;
    }
  }

  // ComicLink.folderSyncId 存的是文件夹 syncId，而 currentPath 是显示路径，
  // 进入子文件夹时必须先解析，否则一条链接都匹配不到。
  final folderSyncId = !isSearching && task.currentPath.isNotEmpty
      ? await ComicFolderService.folderSyncIdByPath(
          task.currentPath,
          folderType,
          db: db,
        )
      : null;

  final comics = <ComicSimplifyEntryInfo>[];
  final searchTexts = <String, String>{};
  final seenKeys = <String>{};
  var cursor = task.offset;
  var hasMore = false;
  for (var attempted = 0; attempted < _maxSparsePages; attempted++) {
    final rows = await db.links.listShelfLinks(
      typeData: folderType.name,
      folderSyncId: folderSyncId,
      allFolders: isSearching,
      sort: sort,
      offset: cursor,
      limit: task.limit + 1,
    );
    hasMore = rows.length > task.limit;
    final pageLinks = hasMore ? rows.sublist(0, task.limit) : rows;
    cursor += pageLinks.length;
    if (pageLinks.isEmpty) break;
    await _appendResolvedComics(
      folderType: folderType,
      links: pageLinks,
      db: db,
      sourceFilter: sourceFilter,
      normalizedKeyword: normalizedKeyword,
      comics: comics,
      searchTexts: searchTexts,
      seenKeys: seenKeys,
    );
    if (comics.isNotEmpty || !hasMore) break;
  }

  return ShelfLoadResult(
    folders: folders,
    folderComicCounts: folderComicCounts,
    folderCovers: folderCovers,
    comics: comics,
    searchTexts: searchTexts,
    nextOffset: cursor,
    hasMore: hasMore,
  );
}

/// 计算 [folders] 每个文件夹的递归漫画数（自身直属 + 全部未删除子孙文件夹）。
///
/// [directCounts] 为 `folderSyncId -> 直属未删除漫画数`；[activeFolders] 只含
/// 未软删除的文件夹，因此已删除文件夹里的链接不会被任何父文件夹计入。
/// 结果带记忆化，并用 [visiting] 兜住历史脏数据里可能出现的环。
Map<String, int> _computeFolderSubtreeCounts({
  required List<ComicFolder> folders,
  required List<ComicFolder> activeFolders,
  required Map<String, int> directCounts,
}) {
  final childrenOf = <String, List<String>>{};
  for (final folder in activeFolders) {
    final parentSyncId = folder.parentSyncId;
    if (parentSyncId == null || parentSyncId.isEmpty) continue;
    (childrenOf[parentSyncId] ??= <String>[]).add(folder.syncId);
  }

  final memo = <String, int>{};
  final visiting = <String>{};

  int countSubtree(String syncId) {
    final cached = memo[syncId];
    if (cached != null) return cached;
    // 环上重复展开的那一层直接返回 0，避免无限递归。
    if (!visiting.add(syncId)) return 0;
    var total = directCounts[syncId] ?? 0;
    for (final child in childrenOf[syncId] ?? const <String>[]) {
      total += countSubtree(child);
    }
    visiting.remove(syncId);
    memo[syncId] = total;
    return total;
  }

  return <String, int>{
    for (final folder in folders) folder.syncId: countSubtree(folder.syncId),
  };
}

Future<ShelfLoadResult> _loadHistoryShelf(
  Database db, {
  required bool sortAscending,
  required String keyword,
  required Set<String>? sourceFilter,
  required int offset,
  required int pageSize,
}) async {
  final isSearching = keyword.trim().isNotEmpty;
  final normalizedKeyword = isSearching ? normalizeSearchText(keyword) : '';
  final comics = <ComicSimplifyEntryInfo>[];
  final searchTexts = <String, String>{};
  final filterSources = sourceFilter != null && sourceFilter.isNotEmpty;
  var cursor = offset;
  var hasMore = false;
  for (var attempted = 0; attempted < _maxSparsePages; attempted++) {
    final rows = await db.histories.listActive(
      ascending: sortAscending,
      limit: pageSize + 1,
      offset: cursor,
    );
    hasMore = rows.length > pageSize;
    final pageRows = hasMore ? rows.sublist(0, pageSize) : rows;
    cursor += pageRows.length;
    if (pageRows.isEmpty) break;
    for (final history in pageRows) {
      if (filterSources && !sourceFilter.contains(history.source)) continue;
      final info = unifiedComicFromUnifiedHistory(history)
          .toSimplifyEntryInfo();
      final key = '${info.from.trim()}:${info.id}';
      final searchText = buildComicSearchText(history);
      if (isSearching && !searchText.contains(normalizedKeyword)) {
        continue;
      }
      comics.add(info);
      searchTexts[key] = searchText;
    }
    if (comics.isNotEmpty || !hasMore) break;
  }
  return ShelfLoadResult(
    folders: const <ComicFolder>[],
    folderComicCounts: const <String, int>{},
    folderCovers: const <String, ComicSimplifyEntryInfo>{},
    comics: comics,
    searchTexts: searchTexts,
    nextOffset: cursor,
    hasMore: hasMore,
  );
}

/// 解析一页链接并把命中的漫画追加到结果（去重、来源过滤、关键字过滤）。
Future<void> _appendResolvedComics({
  required ComicFolderType folderType,
  required List<ComicLink> links,
  required Database db,
  required Set<String>? sourceFilter,
  required String normalizedKeyword,
  required List<ComicSimplifyEntryInfo> comics,
  required Map<String, String> searchTexts,
  required Set<String> seenKeys,
}) async {
  final resolvedByKey = await resolveShelfComicsByKeys(
    folderType,
    {for (final link in links) link.comicUniqueKey}.toList(),
    db,
  );
  for (final link in links) {
    final resolved = resolvedByKey[link.comicUniqueKey];
    if (resolved == null) continue;
    if (sourceFilter != null && !sourceFilter.contains(resolved.info.source)) {
      continue;
    }
    final key = '${resolved.info.from.trim()}:${resolved.info.id}';
    if (!seenKeys.add(key)) continue;
    if (normalizedKeyword.isNotEmpty &&
        !resolved.searchText.contains(normalizedKeyword)) {
      continue;
    }
    comics.add(resolved.info);
    searchTexts[key] = resolved.searchText;
  }
}

Set<String>? _sourceFilter(List<String> sources) {
  final cleaned = sources
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toSet();
  return cleaned.isEmpty ? null : cleaned;
}
