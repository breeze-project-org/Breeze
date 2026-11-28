import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/object_box/model.dart';
import 'package:zephyr/page/bookshelf/method/shelf_load_isolate.dart';
import 'package:zephyr/page/bookshelf/models/shelf_page_mode.dart';
import 'package:zephyr/util/async/worker_pool.dart';
import 'package:zephyr/widgets/comic_simplify_entry/comic_simplify_entry_info.dart';
import 'package:zephyr/page/bookshelf/service/comic_folder_service.dart';
import 'package:zephyr/page/bookshelf/service/comic_link_service.dart';
import 'package:zephyr/page/bookshelf/bloc/folder_shelf_event.dart';
import 'package:zephyr/page/bookshelf/bloc/folder_shelf_state.dart';
export 'package:zephyr/page/bookshelf/bloc/folder_shelf_event.dart';
export 'package:zephyr/page/bookshelf/bloc/folder_shelf_state.dart';

class FolderShelfBloc extends Bloc<FolderShelfEvent, FolderShelfState> {
  FolderShelfBloc({required ShelfPageMode mode})
    : super(FolderShelfState(mode: mode)) {
    // 刷新可能和旧 load 并发；restartable 让最新一次结果生效。
    on<FolderShelfLoadRequested>(_onLoadRequested, transformer: restartable());
    on<FolderShelfLoadMoreRequested>(
      _onLoadMoreRequested,
      transformer: droppable(),
    );
    on<FolderShelfEnterFolder>(_onEnterFolder);
    on<FolderShelfGoBack>(_onGoBack);
    on<FolderShelfGoHome>(_onGoHome);
    on<FolderShelfToggleSort>(_onToggleSort);
    on<FolderShelfCreateFolder>(_onCreateFolder);
    on<FolderShelfDeleteFolder>(_onDeleteFolder);
    on<FolderShelfRenameFolder>(_onRenameFolder);
    on<FolderShelfEnterSelectionMode>(_onEnterSelectionMode);
    on<FolderShelfExitSelectionMode>(_onExitSelectionMode);
    on<FolderShelfToggleFolderSelection>(_onToggleFolderSelection);
    on<FolderShelfToggleComicSelection>(_onToggleComicSelection);
    on<FolderShelfSelectAll>(_onSelectAll);
    on<FolderShelfMoveSelected>(_onMoveSelected);
    on<FolderShelfCopySelected>(_onCopySelected);
    on<FolderShelfDeleteSelected>(_onDeleteSelected);
  }

  ComicFolderType get _folderType => _toFolderType(state.mode);

  static ComicFolderType _toFolderType(ShelfPageMode mode) {
    return switch (mode) {
      ShelfPageMode.favorite => ComicFolderType.favorite,
      ShelfPageMode.history => ComicFolderType.history,
      ShelfPageMode.download => ComicFolderType.download,
    };
  }

  Future<void> _onLoadRequested(
    FolderShelfLoadRequested event,
    Emitter<FolderShelfState> emit,
  ) async {
    emit(state.copyWith(isLoading: true, error: null));
    try {
      final search = event.search ?? state.search;
      // 任务对象必须在 UI isolate 构造：worker 里没有全局 database。
      final task = ShelfLoadTask(
        handle: database.db.handle,
        mode: state.mode.name,
        currentPath: state.currentPath,
        keyword: search?.keyword ?? '',
        sort: search?.sort ?? 'dd',
        sources: search?.sources ?? const <String>[],
        limit: shelfPageSize(state.mode),
      );
      final result = await runInIsolate(loadShelfInIsolate, task);
      emit(
        state.copyWith(
          folders: result.folders,
          folderComicCounts: result.folderComicCounts,
          folderCovers: result.folderCovers,
          comics: result.comics,
          comicSearchTexts: result.searchTexts,
          search: search,
          sortAscending: search?.sort == 'da',
          isLoading: false,
          isLoadingMore: false,
          nextOffset: result.nextOffset,
          hasMore: result.hasMore,
          error: null,
        ),
      );
    } catch (e) {
      logger.e(e);
      emit(
        state.copyWith(
          isLoading: false,
          isLoadingMore: false,
          error: e.toString(),
        ),
      );
    }
  }

  Future<void> _onLoadMoreRequested(
    FolderShelfLoadMoreRequested event,
    Emitter<FolderShelfState> emit,
  ) async {
    if (isClosed || state.isLoading || state.isLoadingMore || !state.hasMore) {
      return;
    }
    final offset = state.nextOffset;
    final mode = state.mode;
    final currentPath = state.currentPath;
    final search = state.search;
    emit(state.copyWith(isLoadingMore: true, error: null));
    try {
      // 任务对象必须在 UI isolate 构造：worker 里没有全局 database。
      final task = ShelfLoadTask(
        handle: database.db.handle,
        mode: mode.name,
        currentPath: currentPath,
        keyword: search?.keyword ?? '',
        sort: search?.sort ?? 'dd',
        sources: search?.sources ?? const <String>[],
        offset: offset,
        limit: shelfPageSize(mode),
      );
      final result = await runInIsolate(loadShelfInIsolate, task);
      if (isClosed) return;
      // 加载期间发生了刷新/切目录/换排序：丢弃这一页。
      if (state.nextOffset != offset ||
          state.mode != mode ||
          state.currentPath != currentPath ||
          state.search != search) {
        return;
      }
      // 跨页去重（搜索时同一漫画可能出现在多条链接里）。
      final existing = <String>{
        for (final comic in state.comics) '${comic.from.trim()}:${comic.id}',
      };
      final added = <ComicSimplifyEntryInfo>[
        for (final comic in result.comics)
          if (existing.add('${comic.from.trim()}:${comic.id}')) comic,
      ];
      emit(
        state.copyWith(
          comics: <ComicSimplifyEntryInfo>[...state.comics, ...added],
          comicSearchTexts: <String, String>{
            ...state.comicSearchTexts,
            ...result.searchTexts,
          },
          nextOffset: result.nextOffset,
          hasMore: result.hasMore,
          isLoadingMore: false,
          error: null,
        ),
      );
    } catch (e) {
      logger.e(e);
      if (isClosed) return;
      emit(state.copyWith(isLoadingMore: false, error: e.toString()));
    }
  }

  /// 历史无文件夹：导航/文件夹变更事件直接忽略（历史恒为根目录）。
  bool get _isHistoryMode => state.mode == ShelfPageMode.history;

  Future<void> _onEnterFolder(
    FolderShelfEnterFolder event,
    Emitter<FolderShelfState> emit,
  ) async {
    if (_isHistoryMode) return;
    // 先置 loading 再换路径：否则从 path 变更到 load 事件之间会有一帧
    // isLoading=false + 旧文件夹 items 的中间态，UI 会误把它当成新列表。
    emit(state.copyWith(currentPath: event.path, isLoading: true, error: null));
    add(const FolderShelfLoadRequested());
  }

  Future<void> _onGoBack(
    FolderShelfGoBack event,
    Emitter<FolderShelfState> emit,
  ) async {
    if (state.isRoot) return;
    final lastIndex = state.currentPath.lastIndexOf('/');
    final parentPath = lastIndex <= 0
        ? kFolderShelfRootPath
        : state.currentPath.substring(0, lastIndex);
    emit(state.copyWith(currentPath: parentPath, isLoading: true, error: null));
    add(const FolderShelfLoadRequested());
  }

  Future<void> _onGoHome(
    FolderShelfGoHome event,
    Emitter<FolderShelfState> emit,
  ) async {
    if (state.isRoot) return;
    emit(
      state.copyWith(
        currentPath: kFolderShelfRootPath,
        isLoading: true,
        error: null,
      ),
    );
    add(const FolderShelfLoadRequested());
  }

  Future<void> _onToggleSort(
    FolderShelfToggleSort event,
    Emitter<FolderShelfState> emit,
  ) async {
    emit(state.copyWith(sortAscending: !state.sortAscending, error: null));
    add(const FolderShelfLoadRequested());
  }

  Future<void> _onCreateFolder(
    FolderShelfCreateFolder event,
    Emitter<FolderShelfState> emit,
  ) async {
    if (_isHistoryMode) return;
    try {
      await ComicFolderService.createFolder(
        state.currentPath,
        event.name,
        _folderType,
      );
      add(const FolderShelfLoadRequested());
    } catch (e) {
      logger.e(e);
      emit(state.copyWith(error: e.toString()));
    }
  }

  Future<void> _onDeleteFolder(
    FolderShelfDeleteFolder event,
    Emitter<FolderShelfState> emit,
  ) async {
    if (_isHistoryMode) return;
    try {
      await ComicFolderService.deleteFolder(event.path, _folderType);
      await ComicLinkService.removeLinksInFolderTree(event.path, _folderType);
      add(const FolderShelfLoadRequested());
    } catch (e) {
      logger.e(e);
      emit(state.copyWith(error: e.toString()));
    }
  }

  Future<void> _onRenameFolder(
    FolderShelfRenameFolder event,
    Emitter<FolderShelfState> emit,
  ) async {
    if (_isHistoryMode) return;
    try {
      await ComicFolderService.renameFolder(
        event.path,
        event.newName,
        _folderType,
      );
      add(const FolderShelfLoadRequested());
    } catch (e) {
      logger.e(e);
      emit(state.copyWith(error: e.toString()));
    }
  }

  Future<void> _onEnterSelectionMode(
    FolderShelfEnterSelectionMode event,
    Emitter<FolderShelfState> emit,
  ) async {
    emit(state.copyWith(selectionMode: true, error: null));
  }

  Future<void> _onExitSelectionMode(
    FolderShelfExitSelectionMode event,
    Emitter<FolderShelfState> emit,
  ) async {
    emit(
      state.copyWith(
        selectionMode: false,
        selectedFolderPaths: const <String>{},
        selectedComicKeys: const <String>{},
        error: null,
      ),
    );
  }

  Future<void> _onToggleFolderSelection(
    FolderShelfToggleFolderSelection event,
    Emitter<FolderShelfState> emit,
  ) async {
    if (_isHistoryMode) return;
    final selected = Set<String>.from(state.selectedFolderPaths);
    if (selected.contains(event.path)) {
      selected.remove(event.path);
    } else {
      selected.add(event.path);
    }
    emit(
      state.copyWith(
        selectionMode: true,
        selectedFolderPaths: selected,
        error: null,
      ),
    );
  }

  Future<void> _onToggleComicSelection(
    FolderShelfToggleComicSelection event,
    Emitter<FolderShelfState> emit,
  ) async {
    final selected = Set<String>.from(state.selectedComicKeys);
    if (selected.contains(event.comicUniqueKey)) {
      selected.remove(event.comicUniqueKey);
    } else {
      selected.add(event.comicUniqueKey);
    }
    emit(
      state.copyWith(
        selectionMode: true,
        selectedComicKeys: selected,
        error: null,
      ),
    );
  }

  Future<void> _onSelectAll(
    FolderShelfSelectAll event,
    Emitter<FolderShelfState> emit,
  ) async {
    final allComics = state.comics
        .map((c) => '${c.from.trim()}:${c.id}')
        .toSet();
    // 历史无文件夹，全选只选中漫画。
    final allFolders = _isHistoryMode
        ? <String>{}
        : await _folderPathsOfType(_folderType);
    emit(
      state.copyWith(
        selectionMode: true,
        selectedFolderPaths: allFolders,
        selectedComicKeys: allComics,
        error: null,
      ),
    );
  }

  Future<Set<String>> _folderPathsOfType(ComicFolderType type) async {
    final all = await ComicFolderService.listAllFolders(type);
    final syncIdMap = {for (final folder in all) folder.syncId: folder};
    return state.folders
        .map((f) => ComicFolderService.folderPath(f, syncIdMap: syncIdMap))
        .toSet();
  }

  Future<void> _onMoveSelected(
    FolderShelfMoveSelected event,
    Emitter<FolderShelfState> emit,
  ) async {
    if (_isHistoryMode) return;
    try {
      final targetPaths = event.targetPaths;
      final sourceFolderPaths =
          event.sourceFolderPaths ?? state.selectedFolderPaths;
      if (sourceFolderPaths.isNotEmpty && targetPaths.length > 1) {
        throw StateError(t.bookshelf.moveFoldersOnlyOneTarget);
      }
      for (final targetPath in targetPaths) {
        if (sourceFolderPaths.isNotEmpty) {
          await ComicFolderService.batchMoveFolders(
            sourceFolderPaths,
            targetPath,
            _folderType,
          );
        }
        await ComicLinkService.batchMoveComics(
          state.selectedComicKeys,
          state.currentPath.isEmpty ? null : state.currentPath,
          targetPath,
          _folderType,
        );
      }
      _exitSelectionAndRefresh();
    } catch (e) {
      logger.e(e);
      emit(state.copyWith(error: e.toString()));
    }
  }

  Future<void> _onCopySelected(
    FolderShelfCopySelected event,
    Emitter<FolderShelfState> emit,
  ) async {
    if (_isHistoryMode) return;
    try {
      for (final targetPath in event.targetPaths) {
        await ComicFolderService.batchCopyFolders(
          state.selectedFolderPaths,
          targetPath,
          _folderType,
        );
        await ComicLinkService.batchCopyComics(
          state.selectedComicKeys,
          targetPath,
          _folderType,
        );
      }
      _exitSelectionAndRefresh();
    } catch (e) {
      logger.e(e);
      emit(state.copyWith(error: e.toString()));
    }
  }

  Future<void> _onDeleteSelected(
    FolderShelfDeleteSelected event,
    Emitter<FolderShelfState> emit,
  ) async {
    try {
      // 历史无 ComicLink：直接软删除历史本体（与旧 LocalShelfPage 一致）。
      if (_isHistoryMode) {
        await _deleteHistoryComics(state.selectedComicKeys);
        _exitSelectionAndRefresh();
        return;
      }
      await ComicFolderService.batchDeleteFolders(
        state.selectedFolderPaths,
        _folderType,
      );
      for (final folderPath in state.selectedFolderPaths) {
        await ComicLinkService.removeLinksInFolderTree(folderPath, _folderType);
      }
      await ComicLinkService.batchRemoveComics(
        state.selectedComicKeys,
        state.currentPath.isEmpty ? null : state.currentPath,
        _folderType,
      );
      _exitSelectionAndRefresh();
    } catch (e) {
      logger.e(e);
      emit(state.copyWith(error: e.toString()));
    }
  }

  /// 批量软删除历史记录。调用方保证只传历史 uniqueKey。
  Future<void> _deleteHistoryComics(Set<String> comicUniqueKeys) async {
    if (comicUniqueKeys.isEmpty) return;
    await database.histories.markDeletedByKeys(comicUniqueKeys);
  }

  void _exitSelectionAndRefresh() {
    add(const FolderShelfExitSelectionMode());
    add(const FolderShelfLoadRequested());
  }
}

/// 历史无文件夹体系：查询、解码、映射与搜索文本全部在后台 isolate 任务中完成。
