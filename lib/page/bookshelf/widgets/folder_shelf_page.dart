import 'dart:async';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:zephyr/util/ohos/platform.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/object_box/model.dart';
import 'package:zephyr/page/bookshelf/bloc/folder_shelf_bloc.dart';
import 'package:zephyr/page/bookshelf/cubit/bookshelf_search_cubit.dart';
import 'package:zephyr/page/bookshelf/cubit/search_status.dart';
import 'package:zephyr/page/bookshelf/method/method.dart';
import 'package:zephyr/page/bookshelf/method/local_comic_import.dart';
import 'package:zephyr/page/bookshelf/method/local_comic_picker.dart';
import 'package:zephyr/page/bookshelf/models/models.dart';
import 'package:zephyr/page/bookshelf/service/comic_folder_service.dart';
import 'package:zephyr/page/bookshelf/service/comic_link_service.dart';
import 'package:zephyr/page/bookshelf/widgets/folder_cover_picker.dart';
import 'package:zephyr/page/bookshelf/widgets/folder_target_picker.dart';
import 'package:zephyr/page/bookshelf/widgets/bookshelf_empty_view.dart';
import 'package:zephyr/page/bookshelf/widgets/bookshelf_grid_shimmer.dart';
import 'package:zephyr/page/bookshelf/widgets/bookshelf_loading_view.dart';
import 'package:zephyr/page/bookshelf/widgets/folder_shelf_item.dart';
import 'package:zephyr/type/enum.dart';
import 'package:zephyr/ui/ui.dart';
import 'package:zephyr/util/text/chinese_convert.dart';
import 'package:zephyr/widgets/comic_simplify_entry/comic_simplify_entry.dart';
import 'package:zephyr/widgets/comic_simplify_entry/comic_simplify_entry_grid.dart';
import 'package:zephyr/widgets/comic_simplify_entry/detail_columns.dart';
import 'package:zephyr/widgets/comic_simplify_entry/comic_simplify_entry_info.dart';
import 'package:zephyr/widgets/toast.dart';

class FolderShelfPage extends StatelessWidget {
  const FolderShelfPage({
    super.key,
    required this.mode,
    this.refreshSignal = 0,
    this.isActive = true,
  });

  final ShelfPageMode mode;
  final int refreshSignal;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final search = context.read<BookshelfSearchCubit>().state.stateOf(mode);
    return BlocProvider(
      create: (_) =>
          FolderShelfBloc(mode: mode)
            ..add(FolderShelfLoadRequested(search: search)),
      child: _FolderShelfPageContent(
        refreshSignal: refreshSignal,
        search: search,
        isActive: isActive,
      ),
    );
  }
}

class _FolderShelfPageContent extends StatefulWidget {
  const _FolderShelfPageContent({
    required this.refreshSignal,
    required this.search,
    required this.isActive,
  });

  final int refreshSignal;
  final SearchStatusState search;
  final bool isActive;

  @override
  State<_FolderShelfPageContent> createState() =>
      _FolderShelfPageContentState();
}

class _FolderShelfPageContentState extends State<_FolderShelfPageContent>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  /// 书架 tab 内部路由上的返回拦截点：有待处理返回（退选择/退文件夹）时持有，
  /// 到根时清掉放行。见 shelf_back_action.dart 头部注释。
  ///
  /// 用 entry 而不是 PopScope：PersistentTabView 在非首页 tab 上按返回时，
  /// 内部 Navigator `canPop == false` 就直接切回首页，事件到不了 PopScope。
  LocalHistoryEntry? _backEntry;

  /// 程序化释放 entry 时置 true：entry.remove() 会同步触发 onRemove，
  /// 此时必须跳过 _handleShelfBack，否则切 tab/回根/dispose 都会误回退一级。
  /// 系统返回消费 entry 时为 false，才真正消费一次返回。
  bool _removingBackEntry = false;

  /// 上次的路径：listener 里与新 state 比较，只在路径变化时回顶+置显 bar。
  /// error/选择模式变化走同一 listener，不能顺手把用户藏起来的 bar 弹出来。
  String? _lastPath;

  /// 每个路径一个 ScrollController：列表 key 带路径，换路径会销毁旧 Scrollable，
  /// 返回上级时复用同一个控制器，再按保存的偏移 jumpTo 回去。
  final Map<String, ScrollController> _scrollControllers =
      <String, ScrollController>{};

  /// 各路径最后一次的纵向偏移，返回上级目录时用来恢复。
  final Map<String, double> _savedScrollOffsets = <String, double>{};

  /// 待恢复目标：路径 + 偏移。等该路径 load 完成、列表首帧布局后再跳。
  String? _pendingRestorePath;
  double? _pendingRestoreOffset;

  /// 帧后恢复回调是否已排：同一帧只排一次。
  bool _restoreScheduled = false;

  @override
  void initState() {
    super.initState();
    _lastPath = context.read<FolderShelfBloc>().state.currentPath;
    if (_isDesktop) {
      HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    }
  }

  @override
  void dispose() {
    if (_isDesktop) {
      HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    }
    _removeBackEntry();
    for (final controller in _scrollControllers.values) {
      controller.dispose();
    }
    _scrollControllers.clear();
    _savedScrollOffsets.clear();
    super.dispose();
  }

  static bool get _isDesktop =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;
  bool _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (event.logicalKey != LogicalKeyboardKey.escape) return false;
    if (!mounted || !widget.isActive) return false;
    final route = ModalRoute.of(context);
    if (route == null || !route.isCurrent) return false;

    return _handleShelfBack(context.read<FolderShelfBloc>().state);
  }

  /// 书架内返回：选择模式先退选，否则文件夹回退一级；根目录返回 false。
  /// 返回键（经 LocalHistoryEntry）与桌面 Escape 共用，保证行为一致。
  bool _handleShelfBack(FolderShelfState state) {
    switch (shelfBackActionFor(
      selectionMode: state.selectionMode,
      isRoot: state.isRoot,
    )) {
      case ShelfBackAction.exitSelection:
        context.read<FolderShelfBloc>().add(
          const FolderShelfExitSelectionMode(),
        );
        return true;
      case ShelfBackAction.goBack:
        context.read<FolderShelfBloc>().add(const FolderShelfGoBack());
        return true;
      case ShelfBackAction.none:
        return false;
    }
  }

  /// 与 bloc 状态同步 entry 的持有/释放。entry 的 onRemove 即一次返回事件，
  /// 直接消费状态机；entry 被消费后 onRemove 内按新状态重新同步（无残留时放行）。
  void _syncBackEntry(FolderShelfState state) {
    final want = wantShelfBackEntry(
      isActive: widget.isActive,
      selectionMode: state.selectionMode,
      isRoot: state.isRoot,
    );
    final has = _backEntry != null;
    if (want == has) return;
    if (!want) {
      _removeBackEntry();
      return;
    }
    final route = ModalRoute.of(context);
    if (route == null || !route.isCurrent) return;
    final entry = LocalHistoryEntry(
      // 书架 AppBar 自绘返回/关闭按钮，不需要框架按 entry 补 leading。
      impliesAppBarDismissal: false,
      onRemove: () {
        _backEntry = null;
        if (!mounted) return;
        // 程序化释放（切 tab/回根/dispose）：只清标记，不消费返回。
        if (_removingBackEntry) return;
        _handleShelfBack(context.read<FolderShelfBloc>().state);
        // 状态更新后按新状态重新同步：仍有可退层级则补回 entry，
        // 到根则保持放行。
        _syncBackEntry(context.read<FolderShelfBloc>().state);
      },
    );
    _backEntry = entry;
    route.addLocalHistoryEntry(entry);
  }

  void _removeBackEntry() {
    final entry = _backEntry;
    _backEntry = null;
    if (entry == null) return;
    // 同步触发 onRemove：置旗跳过其中的 _handleShelfBack。
    _removingBackEntry = true;
    try {
      entry.remove();
    } finally {
      _removingBackEntry = false;
    }
  }

  @override
  void didUpdateWidget(covariant _FolderShelfPageContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshSignal != widget.refreshSignal) {
      context.read<FolderShelfBloc>().add(
        FolderShelfLoadRequested(search: widget.search),
      );
    }
    if (oldWidget.isActive != widget.isActive && mounted) {
      // 切 tab 只同步返回拦截 entry，不自动重载列表：用户没要求刷新时
      // 列表不应因切 tab 而重排/换封面。
      // 切 tab 时按新可见性同步：后台 tab 释放 entry，避免抢返回；
      // 前台 tab 按当前 bloc 状态补回 entry。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _syncBackEntry(context.read<FolderShelfBloc>().state);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return BlocConsumer<FolderShelfBloc, FolderShelfState>(
      // 返回拦截 entry 与 error 提示共用 listener：error、选择模式、
      // 路径变化都要同步 entry 的持有/释放。
      listenWhen: (previous, current) =>
          (current.error != null && current.error != previous.error) ||
          current.selectionMode != previous.selectionMode ||
          current.currentPath != previous.currentPath ||
          current.isLoading != previous.isLoading ||
          current.isLoadingMore != previous.isLoadingMore,
      listener: (context, state) {
        final error = state.error;
        if (error != null && error.isNotEmpty) {
          showErrorToast(error);
        }
        if (state.currentPath != _lastPath) {
          _handleFolderPathChanged(state.currentPath);
        }
        _maybeScheduleScrollRestore(state);
        _syncBackEntry(state);
      },
      builder: (context, state) {
        return NotificationListener<ScrollNotification>(
          onNotification: _onGridScroll,
          child: Stack(
            children: [
              Positioned.fill(child: _buildBody(context)),
              // 顶部悬浮导航：选择模式下隐藏，由底部悬浮操作条接管。
              if (!state.selectionMode) ..._buildFloatingNav(context, state),
            ],
          ),
        );
      },
    );
  }

  /// 顶部悬浮物的显隐（滚动联动），变化时才 setState，避免逐帧重建。
  bool _navVisible = true;

  void _setNavVisible(bool visible) {
    if (_navVisible == visible || !mounted) {
      return;
    }
    setState(() => _navVisible = visible);
  }

  /// 列表滚动通知：保存当前路径的偏移，并联动悬浮物显隐。
  /// 只处理垂直主列表的通知，底部横向操作条不参与；不吞通知，RefreshIndicator 照常工作。
  bool _onGridScroll(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) {
      return false;
    }
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      // 手指接管滚动：放弃未完成的恢复，避免加载完成后列表又突然跳走。
      _pendingRestorePath = null;
      _pendingRestoreOffset = null;
    }
    // 恢复中的 jumpTo 不写入，否则会把半路位置当成用户位置。
    if ((notification is ScrollUpdateNotification ||
            notification is ScrollEndNotification) &&
        !context.read<FolderShelfBloc>().state.isLoading &&
        _pendingRestorePath == null &&
        _lastPath != null) {
      _savedScrollOffsets[_lastPath!] = notification.metrics.pixels;
    }
    if (notification.metrics.pixels <= notification.metrics.minScrollExtent) {
      _setNavVisible(true);
    } else if (notification is ScrollUpdateNotification &&
        notification.dragDetails != null) {
      // 手指拖动中按手指方向直接判定（比 UserScroll 更跟手）；
      // 惯性/程序滚动（dragDetails 为空）不参与，避免回顶动画中途闪烁。
      final dy = notification.dragDetails!.delta.dy;
      if (dy < 0) {
        _setNavVisible(false);
      } else if (dy > 0) {
        _setNavVisible(true);
      }
    } else if (notification is UserScrollNotification) {
      switch (notification.direction) {
        case ScrollDirection.reverse:
          _setNavVisible(false);
        case ScrollDirection.forward:
          _setNavVisible(true);
        case ScrollDirection.idle:
          break;
      }
    }
    return false;
  }

  ScrollController _scrollControllerFor(String path) {
    return _scrollControllers.putIfAbsent(path, ScrollController.new);
  }

  /// [candidateAncestor] 是否 [path] 的严格祖先（根路径 '' 是所有非空路径的祖先）。
  bool _isAncestorPath(String candidateAncestor, String path) {
    if (candidateAncestor == path) return false;
    if (candidateAncestor.isEmpty) return path.isNotEmpty;
    return path.startsWith('$candidateAncestor/');
  }

  /// 删除指定路径的控制器与偏移，控制器延后到帧结束再 dispose。
  /// 当前帧里即将卸载的列表还持有这些控制器，立即释放会触发已释放访问。
  void _dropScrollState(Iterable<String> paths) {
    final removed = <ScrollController>[];
    for (final path in paths.toList()) {
      _savedScrollOffsets.remove(path);
      final controller = _scrollControllers.remove(path);
      if (controller != null) removed.add(controller);
    }
    if (removed.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final controller in removed) {
        controller.dispose();
      }
    });
  }

  /// 路径变化：保存旧路径位置；返回上级时取出上级位置待恢复，
  /// 进入子目录时清掉目标路径残留，保证从 0 开始。
  void _handleFolderPathChanged(String newPath) {
    final oldPath = _lastPath;
    if (oldPath != null) {
      // 如果旧路径上有被打断的恢复目标，它才是用户最后看到的位置。
      final pendingOffset = _pendingRestorePath == oldPath
          ? _pendingRestoreOffset
          : null;
      if (pendingOffset != null) {
        _savedScrollOffsets[oldPath] = pendingOffset;
      } else {
        final controller = _scrollControllers[oldPath];
        if (controller != null && controller.hasClients) {
          _savedScrollOffsets[oldPath] = controller.offset;
        }
      }
    }

    _lastPath = newPath;
    // 换路径=全新列表：悬浮导航直接置显，不依赖滚动通知。
    // 靠 jumpTo 间接触发通知的链路不可靠（新列表替换/高度修正会吞掉
    // 那次通知），内容不够滑时 bar 会永远出不来。
    _setNavVisible(true);

    final knownPaths = <String>{
      ..._savedScrollOffsets.keys,
      ..._scrollControllers.keys,
    };

    if (oldPath != null && _isAncestorPath(newPath, oldPath)) {
      // 返回上级（返回键 / 面包屑 / 回根）：回收离开分支的缓存，
      // 只保留新路径自己的位置。
      _dropScrollState(
        knownPaths.where((path) => _isAncestorPath(newPath, path)),
      );
      final savedOffset = _savedScrollOffsets[newPath];
      if (savedOffset != null && savedOffset > 0) {
        _pendingRestorePath = newPath;
        _pendingRestoreOffset = savedOffset;
      } else {
        _pendingRestorePath = null;
        _pendingRestoreOffset = null;
      }
    } else {
      // 进入子目录 / 其它目录：目标是全新列表，清掉它的残留，从 0 开始。
      _pendingRestorePath = null;
      _pendingRestoreOffset = null;
      _dropScrollState(
        knownPaths.where(
          (path) => path == newPath || _isAncestorPath(newPath, path),
        ),
      );
    }
  }

  /// 待恢复目标就绪（load/loadMore 结束）时安排一次帧后恢复。
  void _maybeScheduleScrollRestore(FolderShelfState state) {
    if (_pendingRestorePath != state.currentPath ||
        _pendingRestoreOffset == null ||
        state.isLoading ||
        state.isLoadingMore) {
      return;
    }
    if (state.error != null) {
      _pendingRestorePath = null;
      _pendingRestoreOffset = null;
      return;
    }
    _scheduleScrollRestore();
  }

  /// 同一帧只排一次恢复回调：首帧布局结束才知道 maxScrollExtent。
  void _scheduleScrollRestore() {
    if (_restoreScheduled) return;
    _restoreScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restoreScheduled = false;
      _tryRestoreScrollOffset();
    });
  }

  /// 把待恢复偏移落到列表上；目标超出已加载内容时先翻页再继续。
  void _tryRestoreScrollOffset() {
    if (!mounted) return;
    final state = context.read<FolderShelfBloc>().state;
    final pendingPath = _pendingRestorePath;
    final targetOffset = _pendingRestoreOffset;
    if (state.isLoading ||
        state.isLoadingMore ||
        pendingPath == null ||
        targetOffset == null ||
        state.currentPath != pendingPath) {
      return;
    }
    final controller = _scrollControllers[state.currentPath];
    if (controller == null || !controller.hasClients) {
      // 空文件夹（或首帧列表还没挂上）：没有可恢复的位置。
      _pendingRestorePath = null;
      _pendingRestoreOffset = null;
      return;
    }
    final position = controller.position;
    final maxExtent = position.maxScrollExtent;
    final minExtent = position.minScrollExtent;
    if (targetOffset <= maxExtent || !state.hasMore) {
      final clamped = targetOffset.clamp(minExtent, maxExtent).toDouble();
      if ((position.pixels - clamped).abs() > 0.5) {
        controller.jumpTo(clamped);
      }
      _pendingRestorePath = null;
      _pendingRestoreOffset = null;
      return;
    }
    // 目标在已加载内容之外：先落到已加载末尾，再靠分页补足。
    if ((position.pixels - maxExtent).abs() > 0.5) {
      controller.jumpTo(maxExtent);
    }
    if (!state.isLoading && !state.isLoadingMore && state.hasMore) {
      context.read<FolderShelfBloc>().add(const FolderShelfLoadMoreRequested());
    }
  }

  /// 悬浮物拆成两个独立 Positioned：
  /// - 面包屑置顶（只在子文件夹出现，滑入淡出）；
  /// - 菜单为右下角 SpeedDial（与搜索结果页同款），跟随滚动显隐。
  List<Widget> _buildFloatingNav(BuildContext context, FolderShelfState state) {
    // 面包屑：子文件夹 + 未上滑隐藏时才出现；右下角菜单：只跟随滚动显隐。
    final pillHidden = state.isRoot || !_navVisible;
    final leftHandMode = context
        .watch<GlobalSettingCubit>()
        .state
        .leftHandModeEnabled;
    return [
      Positioned(
        bottom: 16,
        left: leftHandMode ? 16 : null,
        right: leftHandMode ? null : 16,
        child: IgnorePointer(
          ignoring: !_navVisible,
          child: AnimatedSlide(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            offset: _navVisible ? Offset.zero : const Offset(0, 1),
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 160),
              opacity: _navVisible ? 1 : 0,
              child: _buildNavMenuButton(context, state),
            ),
          ),
        ),
      ),
      Positioned(
        top: 8,
        left: 12,
        right: 12,
        child: IgnorePointer(
          ignoring: pillHidden,
          child: AnimatedSlide(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            offset: pillHidden ? const Offset(0, -1) : Offset.zero,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 160),
              opacity: pillHidden ? 0 : 1,
              child: _buildBreadcrumbPill(context, state),
            ),
          ),
        ),
      ),
    ];
  }

  /// 面包屑：返回 / 路径 / 回根。菜单由右端常驻按钮负责，这里不重复放。
  Widget _buildBreadcrumbPill(BuildContext context, FolderShelfState state) {
    final c = context.calm;
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.border),
        boxShadow: c.shadowMd,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          CalmIconButton(
            icon: Icons.arrow_back_rounded,
            tooltip: t.common.back,
            size: 30,
            iconSize: 16,
            onPressed: () =>
                context.read<FolderShelfBloc>().add(const FolderShelfGoBack()),
          ),
          const SizedBox(width: 2),
          Expanded(
            // 路径很长时横向滚动，不把 44px 高的浮条撑成多行。
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              // Center(widthFactor: 1) 让面包屑在 44px 高内垂直居中，
              // 同时保持自身宽度不撑满。
              child: Center(
                widthFactor: 1,
                child: CalmBreadcrumb(
                  segments: state.breadcrumbTitle.split(' > '),
                  onTapSegment: (index) => _jumpToBreadcrumb(state, index),
                ),
              ),
            ),
          ),
          const SizedBox(width: 2),
          CalmIconButton(
            icon: Icons.home_rounded,
            tooltip: t.common.root,
            size: 30,
            iconSize: 16,
            onPressed: () =>
                context.read<FolderShelfBloc>().add(const FolderShelfGoHome()),
          ),
        ],
      ),
    );
  }

  /// 点面包屑的祖先层级直接跳到该目录（末尾的当前目录不可点）。
  /// 段 0 是 tab 名，对应回根目录；其余段按层级拼回绝对路径。
  void _jumpToBreadcrumb(FolderShelfState state, int index) {
    final bloc = context.read<FolderShelfBloc>();
    if (index <= 0) {
      bloc.add(const FolderShelfGoHome());
      return;
    }
    final parts = state.currentPath
        .split('/')
        .where((part) => part.isNotEmpty)
        .toList();
    if (index >= parts.length) return;
    bloc.add(FolderShelfEnterFolder('/${parts.take(index).join('/')}'));
  }

  /// 右下角全局操作菜单：轻盈胶囊 SpeedDial（展开为紧凑操作卡）。
  /// 长按条目 → 多选已覆盖“管理”入口，这里不再重复放。
  /// 历史无文件夹体系：只有多选入口，直接给一颗主色胶囊按钮。
  Widget _buildNavMenuButton(BuildContext context, FolderShelfState state) {
    if (state.mode == ShelfPageMode.history) {
      return CalmButton(
        label: t.bookshelf.multiSelect,
        icon: Icons.checklist_rounded,
        variant: CalmButtonVariant.primary,
        size: CalmButtonSize.md,
        onPressed: () => context.read<FolderShelfBloc>().add(
          const FolderShelfEnterSelectionMode(),
        ),
      );
    }
    final leftHandMode = context
        .watch<GlobalSettingCubit>()
        .state
        .leftHandModeEnabled;
    return CalmSpeedDial(
      label: t.common.more,
      alignLeft: leftHandMode,
      actions: [
        (
          label: t.bookshelf.multiSelect,
          icon: Icons.checklist_rounded,
          onTap: () => context.read<FolderShelfBloc>().add(
            const FolderShelfEnterSelectionMode(),
          ),
        ),
        (
          label: t.bookshelf.newFolder,
          icon: Icons.create_new_folder_outlined,
          onTap: () => _showCreateFolderDialog(context),
        ),
        if (state.mode == ShelfPageMode.download) ...[
          (
            label: t.bookshelf.importExternalComic,
            icon: Icons.library_add_outlined,
            onTap: () => _importExternalComic(context),
          ),
          (
            label: t.bookshelf.importComic,
            icon: Icons.file_download_outlined,
            onTap: () => _importComic(context),
          ),
        ],
        (
          label: t.common.help,
          icon: Icons.help_outline_rounded,
          onTap: () => _showShelfHelpDialog(context),
        ),
      ],
    );
  }

  Future<void> _showShelfHelpDialog(BuildContext context) async {
    return showCalmDialog<void>(
      context,
      title: t.bookshelf.folderHint,
      icon: Icons.help_outline_rounded,
      bodyBuilder: (dialogContext) => Text(
        t.bookshelf.helpContent,
        style: TextStyle(
          fontSize: 12.5,
          color: dialogContext.calm.text2,
          height: 1.5,
        ),
      ),
      actionsBuilder: (dialogContext) => [
        CalmButton(
          label: t.common.gotIt,
          variant: CalmButtonVariant.primary,
          onPressed: () => Navigator.of(dialogContext).pop(),
        ),
      ],
    );
  }

  Widget _buildBody(BuildContext context) {
    return BlocBuilder<BookshelfSearchCubit, BookshelfSearchState>(
      builder: (context, searchState) {
        return BlocBuilder<FolderShelfBloc, FolderShelfState>(
          // 纯选中变化不重建整表：每行各自订阅自己的选中态（见 _ShelfComicEntry /
          // _ShelfFolderEntry）。否则每次点选都重建几百行，封面重新 resolve 会闪。
          buildWhen: (prev, curr) =>
              prev.folders != curr.folders ||
              prev.comics != curr.comics ||
              prev.comicSearchTexts != curr.comicSearchTexts ||
              prev.folderComicCounts != curr.folderComicCounts ||
              prev.folderCovers != curr.folderCovers ||
              prev.search != curr.search ||
              prev.isLoading != curr.isLoading ||
              prev.isLoadingMore != curr.isLoadingMore ||
              prev.hasMore != curr.hasMore ||
              prev.error != curr.error ||
              prev.sortAscending != curr.sortAscending ||
              prev.selectionMode != curr.selectionMode ||
              prev.currentPath != curr.currentPath,
          builder: (context, state) {
            final bookshelfSetting = context
                .watch<GlobalSettingCubit>()
                .state
                .bookshelfSetting;
            final detailed = bookshelfSetting.detailLayout;
            final hideFolders = switch (state.mode) {
              ShelfPageMode.favorite => bookshelfSetting.hideFavoriteFolders,
              ShelfPageMode.download => bookshelfSetting.hideDownloadFolders,
              ShelfPageMode.history => false,
            };
            final keyword = _normalizeSearchText(
              searchState.stateOf(state.mode).keyword,
            );
            // 搜索时只展示漫画；筛选里开了“不显示文件夹”也一起隐藏。
            final filteredFolders = keyword.isEmpty && !hideFolders
                ? state.folders
                : <ComicFolder>[];
            final filteredComics = keyword.isEmpty
                ? state.comics
                : state.comics.where((c) {
                    final key = '${c.from.trim()}:${c.id}';
                    final searchText = state.comicSearchTexts[key] ?? '';
                    return searchText.contains(keyword);
                  }).toList();

            final totalCount = filteredFolders.length + filteredComics.length;
            final isInitialLoading = state.isLoading && totalCount == 0;

            if (isInitialLoading) {
              return const Stack(
                children: [
                  BookshelfGridShimmer(),
                  Center(child: BookshelfLoadingView()),
                ],
              );
            }

            if (totalCount == 0) {
              return BookshelfEmptyView(
                onRefresh: () => context.read<FolderShelfBloc>().add(
                  const FolderShelfLoadRequested(),
                ),
              );
            }

            final comicType = _comicEntryTypeOf(state.mode);
            // 列表里的文件夹都是当前路径的直接子文件夹，路径可直接由当前路径拼出，
            // 避免在 build 里做异步查询。
            String folderPathOf(ComicFolder f) => state.currentPath.isEmpty
                ? '/${f.name}'
                : '${state.currentPath}/${f.name}';
            final listPadding = EdgeInsets.fromLTRB(
              10,
              state.selectionMode ? 10 : (state.isRoot ? 10 : 64),
              10,
              88,
            );
            Widget shelfItemBuilder(BuildContext context, int index) {
              if (index < filteredFolders.length) {
                final folder = filteredFolders[index];
                final folderPath = folderPathOf(folder);
                return _ShelfFolderEntry(
                  key: ValueKey('folder-${folder.uniqueKey}'),
                  folder: folder,
                  folderPath: folderPath,
                  detailed: detailed,
                  comicCount: state.folderComicCounts[folderPath],
                  coverInfo: state.folderCovers[folderPath],
                  onFolderAction: (position) =>
                      _showFolderActions(context, folder, folderPath, position),
                );
              }
              final comicIndex = index - filteredFolders.length;
              final comic = filteredComics[comicIndex];
              return _ShelfComicEntry(
                key: ValueKey('comic-${comic.from}:${comic.id}'),
                info: comic,
                type: comicType,
                detailed: detailed,
                onComicAction: (info, position) =>
                    _showComicActions(context, info, position),
              );
            }

            // 文件夹与漫画混排：详情模式多列懒加载（见 DetailColumnsSliver）。
            // 列数只与视口宽有关，build 期快照一次，不进 SliverLayoutBuilder。
            final columns = detailed
                ? detailColumnCount(
                    MediaQuery.sizeOf(context).width - listPadding.horizontal,
                  )
                : 1;
            // 路径 key：换路径时列表 element 销毁重建，原生 offset 就是 0，
            // 没有 jumpTo 的中间动效（旧列表先闪回顶再换内容，看着像里面滚了一段）。
            // 同路径刷新（如下拉）key 不变，offset 保留。
            final shelfList = detailed
                ? CustomScrollView(
                    key: ValueKey('shelf-${state.currentPath}'),
                    controller: _scrollControllerFor(state.currentPath),
                    // 内容不足一屏时也要能下拉，否则 RefreshIndicator 收不到手势。
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverPadding(
                        padding: listPadding,
                        sliver: DetailColumnsSliver(
                          columns: columns,
                          itemCount: totalCount,
                          itemBuilder: shelfItemBuilder,
                        ),
                      ),
                    ],
                  )
                : GridView.builder(
                    key: ValueKey('shelf-${state.currentPath}'),
                    controller: _scrollControllerFor(state.currentPath),
                    // 内容不足一屏时也要能下拉，否则 RefreshIndicator 收不到手势。
                    physics: const AlwaysScrollableScrollPhysics(),
                    // 悬浮物盖在列表上层：子文件夹有面包屑浮栏，留 64px 顶部滚动边距；
                    // 根目录无顶部悬浮物，选择模式无悬浮物，均保持 10。
                    // 右下角按钮 56px + bottom 16：底部留 88，避免挡住最后一行漫画。
                    padding: listPadding,
                    gridDelegate: buildComicSimplifyEntryGridDelegate(),
                    itemCount: totalCount,
                    itemBuilder: shelfItemBuilder,
                  );
            // 滚到底部附近时自动加载下一页；droppable 保证并发触发只跑一次。
            final scrollable = NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (!state.hasMore || state.isLoading || state.isLoadingMore) {
                  return false;
                }
                final metrics = notification.metrics;
                if (metrics.axis != Axis.vertical) return false;
                if (metrics.maxScrollExtent - metrics.pixels <= 600) {
                  context.read<FolderShelfBloc>().add(
                    const FolderShelfLoadMoreRequested(),
                  );
                }
                return false;
              },
              child: shelfList,
            );
            return RefreshIndicator(
              onRefresh: () async {
                context.read<FolderShelfBloc>().add(
                  const FolderShelfLoadRequested(),
                );
              },
              child: Stack(
                children: [
                  scrollable,
                  if (state.isLoading || state.isLoadingMore)
                    const Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      // 不定长胶囊进度条：颜色取 c.accent，与主题联动。
                      child: CalmProgressBar(height: 3),
                    ),
                  _buildSelectionBar(context),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSelectionBar(BuildContext context) {
    // 计数/按钮可用态自己订阅：顶层 buildWhen 已跳过纯选中变化，
    // 这里不订阅就会一直显示旧值。
    final selectionMode = context.select(
      (FolderShelfBloc bloc) => bloc.state.selectionMode,
    );
    final selectedCount = context.select(
      (FolderShelfBloc bloc) => bloc.state.selectedCount,
    );
    final hasSelection = context.select(
      (FolderShelfBloc bloc) => bloc.state.hasSelection,
    );
    final mode = context.select((FolderShelfBloc bloc) => bloc.state.mode);
    final bloc = context.read<FolderShelfBloc>();
    return Positioned(
      bottom: 8,
      left: 8,
      right: 8,
      child: IgnorePointer(
        ignoring: !selectionMode,
        child: AnimatedSlide(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          offset: selectionMode ? Offset.zero : const Offset(0, 1.0),
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 160),
            opacity: selectionMode ? 1 : 0,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                // 浮空胶囊条内部自带 Wrap，窄屏下操作按钮自动换行不溢出。
                child: CalmBatchActionBar(
                  selectedCount: selectedCount,
                  onClose: () => bloc.add(const FolderShelfExitSelectionMode()),
                  actions: [
                    CalmButton(
                      label: t.common.selectAll,
                      variant: CalmButtonVariant.ghost,
                      size: CalmButtonSize.xs,
                      onPressed: () => bloc.add(const FolderShelfSelectAll()),
                    ),
                    if (mode != ShelfPageMode.history)
                      CalmIconButton(
                        icon: Icons.drive_file_move_outline,
                        tooltip: t.bookshelf.moveTo,
                        size: 28,
                        iconSize: 15,
                        onPressed: hasSelection
                            ? () => _showTargetFolderDialog(
                                context,
                                onConfirmed: (targets) {
                                  bloc.add(FolderShelfMoveSelected(targets));
                                },
                              )
                            : null,
                      ),
                    if (mode != ShelfPageMode.history)
                      CalmIconButton(
                        icon: Icons.folder_copy_outlined,
                        tooltip: t.bookshelf.copyTo,
                        size: 28,
                        iconSize: 15,
                        onPressed: hasSelection
                            ? () => _showTargetFolderDialog(
                                context,
                                onConfirmed: (targets) {
                                  bloc.add(FolderShelfCopySelected(targets));
                                },
                              )
                            : null,
                      ),
                    if (mode == ShelfPageMode.download)
                      CalmIconButton(
                        icon: Icons.file_upload_outlined,
                        tooltip: t.bookshelf.batchExport,
                        size: 28,
                        iconSize: 15,
                        onPressed: hasSelection
                            ? () => _batchExportSelected(
                                context,
                                context.read<FolderShelfBloc>().state,
                              )
                            : null,
                      ),
                    CalmIconButton(
                      icon: Icons.delete_outline,
                      tooltip: t.common.delete,
                      size: 28,
                      iconSize: 15,
                      onPressed: hasSelection
                          ? () => _confirmDeleteSelected(context)
                          : null,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showCreateFolderDialog(BuildContext context) async {
    final controller = TextEditingController();
    final name = await showCalmDialog<String>(
      context,
      title: t.bookshelf.createFolder,
      icon: Icons.create_new_folder_outlined,
      bodyBuilder: (dialogContext) => CalmTextField(
        controller: controller,
        hintText: t.bookshelf.folderName,
        prefixIcon: Icons.folder_outlined,
        onSubmitted: (text) {
          final value = text.trim();
          if (value.isNotEmpty) Navigator.of(dialogContext).pop(value);
        },
      ),
      actionsBuilder: (dialogContext) => [
        CalmButton(
          label: t.common.cancel,
          variant: CalmButtonVariant.ghost,
          onPressed: () => Navigator.of(dialogContext).pop(),
        ),
        CalmButton(
          label: t.common.ok,
          variant: CalmButtonVariant.primary,
          onPressed: () {
            final text = controller.text.trim();
            if (text.isNotEmpty) Navigator.of(dialogContext).pop(text);
          },
        ),
      ],
    );
    controller.dispose();
    if (name != null && name.isNotEmpty && context.mounted) {
      context.read<FolderShelfBloc>().add(FolderShelfCreateFolder(name));
    }
  }

  void _showFolderActions(
    BuildContext context,
    ComicFolder folder,
    String folderPath,
    Offset position,
  ) {
    // 右键 / 长按统一走轻盈上下文菜单（自动避让屏幕边缘）。
    unawaited(
      showCalmContextMenu<String>(
        context,
        globalPosition: position,
        entries: [
          CalmPopupMenuEntry.item(
            value: 'rename',
            label: t.common.rename,
            icon: Icons.drive_file_rename_outline,
          ),
          CalmPopupMenuEntry.item(
            value: 'move',
            label: t.bookshelf.moveTo,
            icon: Icons.drive_file_move_outline,
          ),
          CalmPopupMenuEntry.item(
            value: 'cover',
            label: t.bookshelf.changeFolderCover,
            icon: Icons.image_outlined,
          ),
          const CalmPopupMenuEntry.divider(),
          CalmPopupMenuEntry.item(
            value: 'delete',
            label: t.common.delete,
            icon: Icons.delete_outline,
            danger: true,
          ),
        ],
      ).then((value) {
        if (!context.mounted) return;
        switch (value) {
          case 'rename':
            unawaited(_showRenameFolderDialog(context, folder, folderPath));
          case 'move':
            unawaited(
              _showTargetFolderDialog(
                context,
                selectedFolderPaths: {folderPath},
                onConfirmed: (targets) {
                  context.read<FolderShelfBloc>().add(
                    FolderShelfMoveSelected(
                      targets,
                      sourceFolderPaths: {folderPath},
                    ),
                  );
                },
              ),
            );
          case 'cover':
            unawaited(_chooseFolderCover(context, folder));
          case 'delete':
            unawaited(_confirmDeleteSingleFolder(context, folderPath));
        }
      }),
    );
  }

  /// 选择文件夹封面：从文件夹内漫画里挑一本，或恢复自动封面。
  Future<void> _chooseFolderCover(
    BuildContext context,
    ComicFolder folder,
  ) async {
    final choice = await showFolderCoverPicker(context, folder: folder);
    if (choice == null || !context.mounted) return;
    try {
      await ComicFolderService.setFolderCover(folder, choice.comicUniqueKey);
    } catch (e) {
      logger.e(e);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
      return;
    }
    if (!context.mounted) return;
    context.read<FolderShelfBloc>().add(const FolderShelfLoadRequested());
  }

  Future<void> _confirmDeleteSingleFolder(
    BuildContext context,
    String path,
  ) async {
    final confirmed = await showCalmDialog<bool>(
      context,
      title: t.bookshelf.confirmDeleteFolderTitle,
      icon: Icons.delete_outline,
      tone: CalmTone.danger,
      bodyBuilder: (dialogContext) => Text(
        t.bookshelf.confirmDeleteFolderContent,
        style: TextStyle(
          fontSize: 12.5,
          color: dialogContext.calm.text2,
          height: 1.5,
        ),
      ),
      actionsBuilder: (dialogContext) => [
        CalmButton(
          label: t.common.cancel,
          variant: CalmButtonVariant.ghost,
          onPressed: () => Navigator.of(dialogContext).pop(false),
        ),
        CalmButton(
          label: t.common.delete,
          variant: CalmButtonVariant.danger,
          onPressed: () => Navigator.of(dialogContext).pop(true),
        ),
      ],
    );
    if (confirmed == true && context.mounted) {
      context.read<FolderShelfBloc>().add(FolderShelfDeleteFolder(path));
    }
  }

  Future<void> _showRenameFolderDialog(
    BuildContext context,
    ComicFolder folder,
    String folderPath,
  ) async {
    final controller = TextEditingController(text: folder.name);
    final name = await showCalmDialog<String>(
      context,
      title: t.bookshelf.renameFolder,
      icon: Icons.drive_file_rename_outline,
      bodyBuilder: (dialogContext) => CalmTextField(
        controller: controller,
        hintText: t.common.rename,
        prefixIcon: Icons.folder_outlined,
        onSubmitted: (text) {
          final value = text.trim();
          if (value.isNotEmpty) Navigator.of(dialogContext).pop(value);
        },
      ),
      actionsBuilder: (dialogContext) => [
        CalmButton(
          label: t.common.cancel,
          variant: CalmButtonVariant.ghost,
          onPressed: () => Navigator.of(dialogContext).pop(),
        ),
        CalmButton(
          label: t.common.ok,
          variant: CalmButtonVariant.primary,
          onPressed: () {
            final text = controller.text.trim();
            if (text.isNotEmpty) Navigator.of(dialogContext).pop(text);
          },
        ),
      ],
    );
    controller.dispose();
    if (name != null && name.isNotEmpty && context.mounted) {
      context.read<FolderShelfBloc>().add(
        FolderShelfRenameFolder(folderPath, name),
      );
    }
  }

  static ComicEntryType _comicEntryTypeOf(ShelfPageMode mode) {
    return switch (mode) {
      ShelfPageMode.favorite => ComicEntryType.favorite,
      ShelfPageMode.history => ComicEntryType.history,
      ShelfPageMode.download => ComicEntryType.download,
    };
  }

  static String _normalizeSearchText(String text) {
    final lower = text.trim().toLowerCase();
    if (lower.isEmpty) return '';
    try {
      return t2s(lower);
    } catch (_) {
      return lower;
    }
  }

  void _showComicActions(
    BuildContext context,
    ComicSimplifyEntryInfo info,
    Offset position,
  ) {
    unawaited(
      showCalmContextMenu<String>(
        context,
        globalPosition: position,
        entries: [
          CalmPopupMenuEntry.item(
            value: 'multi_select',
            label: t.bookshelf.multiSelect,
            icon: Icons.checklist_rounded,
          ),
          const CalmPopupMenuEntry.divider(),
          CalmPopupMenuEntry.item(
            value: 'delete',
            label: t.common.delete,
            icon: Icons.delete_outline,
            danger: true,
          ),
        ],
      ).then((value) {
        if (!context.mounted) return;
        switch (value) {
          case 'multi_select':
            context.read<FolderShelfBloc>().add(
              FolderShelfToggleComicSelection('${info.from.trim()}:${info.id}'),
            );
          case 'delete':
            unawaited(_confirmRemoveComic(context, info));
        }
      }),
    );
  }

  Future<void> _confirmRemoveComic(
    BuildContext context,
    ComicSimplifyEntryInfo info,
  ) async {
    final confirmed = await showCalmDialog<bool>(
      context,
      title: t.bookshelf.confirmRemoveComicTitle,
      icon: Icons.delete_outline,
      tone: CalmTone.danger,
      bodyBuilder: (dialogContext) => Text(
        t.bookshelf.confirmRemoveComicContent(title: info.title),
        style: TextStyle(
          fontSize: 12.5,
          color: dialogContext.calm.text2,
          height: 1.5,
        ),
      ),
      actionsBuilder: (dialogContext) => [
        CalmButton(
          label: t.common.cancel,
          variant: CalmButtonVariant.ghost,
          onPressed: () => Navigator.of(dialogContext).pop(false),
        ),
        CalmButton(
          label: t.common.remove,
          variant: CalmButtonVariant.danger,
          onPressed: () => Navigator.of(dialogContext).pop(true),
        ),
      ],
    );
    if (confirmed == true && context.mounted) {
      final uniqueKey = '${info.from.trim()}:${info.id}';
      final state = context.read<FolderShelfBloc>().state;
      // 历史无 ComicLink：直接软删除历史本体（与旧 LocalShelfPage 一致）。
      if (state.mode == ShelfPageMode.history) {
        await database.histories.markDeletedByKey(uniqueKey);
        if (!context.mounted) return;
        context.read<FolderShelfBloc>().add(const FolderShelfLoadRequested());
        return;
      }
      final folderType = switch (state.mode) {
        ShelfPageMode.favorite => ComicFolderType.favorite,
        ShelfPageMode.download => ComicFolderType.download,
        ShelfPageMode.history => ComicFolderType.history,
      };
      await ComicLinkService.removeComic(
        uniqueKey,
        state.currentPath.isEmpty ? null : state.currentPath,
        folderType,
      );
      if (!context.mounted) return;
      context.read<FolderShelfBloc>().add(const FolderShelfLoadRequested());
    }
  }
}

Future<void> _showTargetFolderDialog(
  BuildContext context, {
  Set<String>? selectedFolderPaths,
  required ValueChanged<Set<String>> onConfirmed,
}) async {
  final state = context.read<FolderShelfBloc>().state;
  final mode = state.mode;
  final sourceFolderPaths = selectedFolderPaths ?? state.selectedFolderPaths;
  final type = _folderTypeOf(mode);
  final allFolders = await ComicFolderService.listAllFolders(type);
  if (!context.mounted) return;
  final syncIdMap = {for (final folder in allFolders) folder.syncId: folder};
  final pathMap = {
    for (final folder in allFolders)
      folder.syncId: ComicFolderService.folderPath(
        folder,
        syncIdMap: syncIdMap,
      ),
  };
  // 排除当前所在文件夹（仅自身）、被选中的文件夹及其子树
  final forbiddenSyncIds = <String>{};
  for (final path in sourceFolderPaths) {
    final folder = allFolders.firstWhereOrNull(
      (f) => pathMap[f.syncId] == path,
    );
    if (folder != null) {
      collectForbiddenSyncIds(folder.syncId, allFolders, forbiddenSyncIds);
    }
  }
  final currentPath = state.currentPath;
  final currentFolder = currentPath.isEmpty
      ? null
      : allFolders.firstWhereOrNull((f) => pathMap[f.syncId] == currentPath);

  // 根目录下移动/复制时禁用根目录目标（留在原地无意义）。
  final picked = await showFolderTargetPicker(
    context,
    type: type,
    allowCreateFolder: false,
    disabledSyncIds: forbiddenSyncIds,
    rootEnabled: currentPath.isNotEmpty,
    currentSyncId: currentFolder?.syncId,
  );
  if (picked == null || picked.isEmpty) return;
  onConfirmed(picked);
}

ComicFolderType _folderTypeOf(ShelfPageMode mode) {
  return switch (mode) {
    ShelfPageMode.favorite => ComicFolderType.favorite,
    ShelfPageMode.download => ComicFolderType.download,
    ShelfPageMode.history => ComicFolderType.history,
  };
}

Future<void> _importExternalComic(BuildContext context) async {
  final choice = await showCalmDialog<String>(
    context,
    title: t.bookshelf.importExternalComic,
    icon: Icons.library_add_outlined,
    bodyBuilder: (dialogContext) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!Platform.isIOS && !isOhos)
          CalmListTile(
            leading: Icon(
              Icons.folder_open_outlined,
              size: 17,
              color: dialogContext.calm.accent,
            ),
            title: t.bookshelf.importExternalFolder,
            subtitle: t.bookshelf.importExternalFolderHint,
            onTap: () => Navigator.of(dialogContext).pop('folder'),
          ),
        CalmListTile(
          leading: Icon(
            Icons.archive_outlined,
            size: 17,
            color: dialogContext.calm.accent,
          ),
          title: t.bookshelf.importExternalArchive,
          subtitle: t.bookshelf.importExternalArchiveHint,
          onTap: () => Navigator.of(dialogContext).pop('archive'),
        ),
      ],
    ),
    actionsBuilder: (dialogContext) => [
      CalmButton(
        label: t.common.cancel,
        variant: CalmButtonVariant.ghost,
        onPressed: () => Navigator.of(dialogContext).pop(),
      ),
    ],
  );
  if (choice == null) return;

  try {
    final picked = choice == 'folder'
        ? await pickLocalComicDirectory()
        : await pickLocalComicArchive();
    if (picked == null) return;
    if (!context.mounted) return;
    showSuccessToast(t.bookshelf.importExternalStarted);

    final result = await importLocalComic(
      sourcePath: picked.path,
      isDirectory: picked.isDirectory,
      cleanupRoot: picked.cleanupRoot,
      uncategorizedName: t.bookshelf.importUncategorized,
    );

    if (!context.mounted) return;
    showSuccessToast(
      t.bookshelf.importExternalCompleted(
        title: result.title,
        chapters: result.chapterCount,
        images: result.imageCount,
      ),
    );
    context.read<FolderShelfBloc>().add(const FolderShelfLoadRequested());
  } catch (e, st) {
    logger.e(e, stackTrace: st);
    if (!context.mounted) return;
    showErrorToast(t.error.importFailed(error: e.toString()));
  }
}

Future<void> _importComic(BuildContext context) async {
  String? importRoot;
  String? cleanupDir;
  try {
    if (Platform.isAndroid) {
      importRoot = await pickComicZipAndroid();
      if (importRoot != null) {
        cleanupDir = p.dirname(p.dirname(importRoot));
      }
    } else {
      final file = await openFile(
        acceptedTypeGroups: [
          const XTypeGroup(
            label: 'zip',
            extensions: ['zip'],
            uniformTypeIdentifiers: ['public.zip-archive'],
          ),
        ],
      );
      importRoot = file?.path;
    }
    if (importRoot == null || importRoot.trim().isEmpty) return;

    if (!context.mounted) return;
    showSuccessToast(t.bookshelf.importStarted);

    final result = await importComicFromZip(
      importRoot,
      cleanupDir: cleanupDir,
      onConfirmOverwrite: (title) =>
          _confirmComicImportOverwrite(context, title),
    );

    if (!context.mounted) return;
    showSuccessToast(t.bookshelf.importCompleted(title: result.title));
    context.read<FolderShelfBloc>().add(const FolderShelfLoadRequested());
  } on ComicImportCancelledException catch (e, st) {
    logger.e(e, stackTrace: st);
    if (!context.mounted) return;
    showErrorToast(t.common.cancelled);
  } catch (e) {
    logger.e(e);
    if (!context.mounted) return;
    showErrorToast(t.error.importFailed(error: e.toString()));
  }
}

Future<bool> _confirmComicImportOverwrite(
  BuildContext context,
  String title,
) async {
  final result = await showCalmDialog<bool>(
    context,
    title: t.bookshelf.comicExists,
    icon: Icons.file_download_outlined,
    tone: CalmTone.warning,
    bodyBuilder: (dialogContext) => Text(
      t.bookshelf.confirmOverwriteImport(title: title),
      style: TextStyle(
        fontSize: 12.5,
        color: dialogContext.calm.text2,
        height: 1.5,
      ),
    ),
    actionsBuilder: (dialogContext) => [
      CalmButton(
        label: t.common.cancel,
        variant: CalmButtonVariant.ghost,
        onPressed: () => Navigator.of(dialogContext).pop(false),
      ),
      CalmButton(
        label: t.common.overwrite,
        variant: CalmButtonVariant.primary,
        onPressed: () => Navigator.of(dialogContext).pop(true),
      ),
    ],
  );
  return result ?? false;
}

Future<void> _batchExportSelected(
  BuildContext context,
  FolderShelfState state,
) async {
  final selectedComics = state.comics
      .where(
        (c) => state.selectedComicKeys.contains('${c.from.trim()}:${c.id}'),
      )
      .toList();

  if (selectedComics.isEmpty) {
    showInfoToast(t.bookshelf.noExportableComics);
    return;
  }

  try {
    final success = await batchExportComics(
      context: context,
      comics: selectedComics,
    );
    if (!context.mounted) return;
    showSuccessToast(
      t.bookshelf.batchExportCompleted(
        success: success,
        total: selectedComics.length,
      ),
    );
    context.read<FolderShelfBloc>().add(const FolderShelfExitSelectionMode());
  } catch (e) {
    logger.e(e);
    if (!context.mounted) return;
    showErrorToast(t.bookshelf.batchExportFailed(error: e.toString()));
  }
}

Future<void> _confirmDeleteSelected(BuildContext context) async {
  final confirmed = await showCalmDialog<bool>(
    context,
    title: t.bookshelf.confirmDeleteSelectedTitle,
    icon: Icons.delete_outline,
    tone: CalmTone.danger,
    bodyBuilder: (dialogContext) => Text(
      t.bookshelf.confirmDeleteSelectedContent,
      style: TextStyle(
        fontSize: 12.5,
        color: dialogContext.calm.text2,
        height: 1.5,
      ),
    ),
    actionsBuilder: (dialogContext) => [
      CalmButton(
        label: t.common.cancel,
        variant: CalmButtonVariant.ghost,
        onPressed: () => Navigator.of(dialogContext).pop(false),
      ),
      CalmButton(
        label: t.common.delete,
        variant: CalmButtonVariant.danger,
        onPressed: () => Navigator.of(dialogContext).pop(true),
      ),
    ],
  );
  if (confirmed == true && context.mounted) {
    context.read<FolderShelfBloc>().add(const FolderShelfDeleteSelected());
  }
}

/// 文件夹行：只订阅自己的选中态 + 选择模式。
///
/// 顶层 buildWhen 已跳过纯选中变化，这里的 select 让点选时只有相关行重建，
/// 封面/整表不动（见 _buildBody 注释）。
/// 注意：select 只能出现在行 widget 内部，不能直接写在 sliver 的 itemBuilder 里
///（会触发 widget is! SliverWithKeepAliveWidget 断言）。
class _ShelfFolderEntry extends StatelessWidget {
  const _ShelfFolderEntry({
    super.key,
    required this.folder,
    required this.folderPath,
    required this.detailed,
    this.comicCount,
    this.coverInfo,
    required this.onFolderAction,
  });

  final ComicFolder folder;
  final String folderPath;
  final bool detailed;
  final int? comicCount;
  final ComicSimplifyEntryInfo? coverInfo;
  final void Function(Offset position) onFolderAction;

  @override
  Widget build(BuildContext context) {
    final selectionMode = context.select(
      (FolderShelfBloc bloc) => bloc.state.selectionMode,
    );
    final isSelected = context.select(
      (FolderShelfBloc bloc) =>
          bloc.state.selectedFolderPaths.contains(folderPath),
    );
    return FolderShelfItem(
      folder: folder,
      selectionMode: selectionMode,
      isSelected: isSelected,
      detailed: detailed,
      comicCount: comicCount,
      coverInfo: coverInfo,
      onTap: selectionMode
          ? () => context.read<FolderShelfBloc>().add(
              FolderShelfToggleFolderSelection(folderPath),
            )
          : () => context.read<FolderShelfBloc>().add(
              FolderShelfEnterFolder(folderPath),
            ),
      onLongPress: selectionMode
          ? (details) => context.read<FolderShelfBloc>().add(
              FolderShelfToggleFolderSelection(folderPath),
            )
          : (details) => onFolderAction(details.globalPosition),
      onSecondaryTapDown: selectionMode
          ? null
          : (details) => onFolderAction(details.globalPosition),
    );
  }
}

/// 漫画行：只订阅自己的选中态 + 选择模式，同上。
class _ShelfComicEntry extends StatelessWidget {
  const _ShelfComicEntry({
    super.key,
    required this.info,
    required this.type,
    required this.detailed,
    required this.onComicAction,
  });

  final ComicSimplifyEntryInfo info;
  final ComicEntryType type;
  final bool detailed;
  final void Function(ComicSimplifyEntryInfo info, Offset position)
  onComicAction;

  @override
  Widget build(BuildContext context) {
    final selectionMode = context.select(
      (FolderShelfBloc bloc) => bloc.state.selectionMode,
    );
    final comicKey = '${info.from.trim()}:${info.id}';
    final isSelected = context.select(
      (FolderShelfBloc bloc) => bloc.state.selectedComicKeys.contains(comicKey),
    );
    return ComicSimplifyEntry(
      info: info,
      type: type,
      selectionMode: selectionMode,
      isSelected: isSelected,
      detailed: detailed,
      refresh: () =>
          context.read<FolderShelfBloc>().add(const FolderShelfLoadRequested()),
      onTapOverride: selectionMode
          ? (info) => context.read<FolderShelfBloc>().add(
              FolderShelfToggleComicSelection(comicKey),
            )
          : null,
      onLongPressOverride: selectionMode
          ? (info, details) => context.read<FolderShelfBloc>().add(
              FolderShelfToggleComicSelection(comicKey),
            )
          : (info, details) => onComicAction(info, details.globalPosition),
      onSecondaryTapDown: selectionMode
          ? null
          : (info, details) => onComicAction(info, details.globalPosition),
    );
  }
}
