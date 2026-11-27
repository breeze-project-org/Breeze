import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/cubit/plugin_registry_cubit.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/bookshelf/bookshelf.dart';
import 'package:zephyr/page/search/widget/search_input_dialog.dart';
import 'package:zephyr/plugin/plugin_registry_service.dart';
import 'package:zephyr/util/context/context_extensions.dart';
import 'package:zephyr/util/async/debouncer.dart';

@RoutePage()
class BookshelfPage extends StatelessWidget {
  const BookshelfPage({super.key});

  @override
  Widget build(BuildContext context) {
    final bookshelfSetting = context
        .read<GlobalSettingCubit>()
        .state
        .bookshelfSetting;
    return MultiBlocProvider(
      providers: [
        BlocProvider<BookshelfSearchCubit>(
          create: (context) => BookshelfSearchCubit(
            favorite: SearchStatusState(
              sort: bookshelfSetting.rememberFavoriteSort
                  ? bookshelfSetting.favoriteSort
                  : 'dd',
            ),
            history: SearchStatusState(
              sort: bookshelfSetting.rememberHistorySort
                  ? bookshelfSetting.historySort
                  : 'dd',
            ),
            download: SearchStatusState(
              sort: bookshelfSetting.rememberDownloadSort
                  ? bookshelfSetting.downloadSort
                  : 'dd',
            ),
          ),
        ),
      ],
      child: _BookshelfPageContent(
        initialIndex: bookshelfSetting.homePageIndex,
      ),
    );
  }
}

class _BookshelfPageContent extends StatefulWidget {
  const _BookshelfPageContent({required this.initialIndex});

  final int initialIndex;

  @override
  State<_BookshelfPageContent> createState() => _BookshelfPageContentState();
}

class _BookshelfPageContentState extends State<_BookshelfPageContent>
    with SingleTickerProviderStateMixin {
  late final List<String> _labels = [
    t.bookshelf.favorite,
    t.bookshelf.history,
    t.bookshelf.download,
  ];

  late int _currentIndex;
  late final TabController _tabController;
  final List<int> _refreshSignals = [0, 0, 0];
  final FocusNode _searchFocusNode = FocusNode();
  // 关键词防抖：短时间内连续输入只保留最后一次，停顿后才真正写入过滤；
  // 回车提交走 onSubmitted 立即生效，不经过这里。
  final _keywordDebouncer = Debouncer(milliseconds: 500);
  List<String> _lastAvailableSources = const <String>[];
  bool _isSearchExpanded = false;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, _labels.length - 1);
    _tabController = TabController(
      initialIndex: _currentIndex,
      length: _labels.length,
      vsync: this,
    )..addListener(_handleTabControllerChanged);
    _syncSourcesFromRegistry(context.read<PluginRegistryCubit>().state.plugins);
  }

  @override
  void dispose() {
    _tabController
      ..removeListener(_handleTabControllerChanged)
      ..dispose();
    _searchFocusNode.dispose();
    _keywordDebouncer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.sizeOf(context).width >= 600;

    return BlocListener<PluginRegistryCubit, PluginRegistryState>(
      listenWhen: (previous, current) =>
          _pluginAvailabilityRevision(previous.plugins) !=
          _pluginAvailabilityRevision(current.plugins),
      listener: (context, registry) {
        _syncSourcesFromRegistry(registry.plugins);
        _triggerRefreshAll();
      },
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: isDesktop ? 16 : 8,
          title: isDesktop ? _buildDesktopHeader() : _buildMobileHeader(),
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            FolderShelfPage(
              mode: ShelfPageMode.favorite,
              refreshSignal: _refreshSignals[0],
              isActive: _currentIndex == 0,
            ),
            FolderShelfPage(
              mode: ShelfPageMode.history,
              refreshSignal: _refreshSignals[1],
              isActive: _currentIndex == 1,
            ),
            FolderShelfPage(
              mode: ShelfPageMode.download,
              refreshSignal: _refreshSignals[2],
              isActive: _currentIndex == 2,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopHeader() {
    return Row(
      children: [
        _buildSleekTabs(),
        const SizedBox(width: 24),
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: _buildShelfSearchField(autoExpand: false),
                ),
              ),
              const SizedBox(width: 8),
              _buildFilterButton(onPressed: _openFilter),
            ],
          ),
        ),
      ],
    );
  }

  /// 筛选入口。当前 tab 存在非默认筛选条件时在图标上挂个小圆点，
  /// 让用户在收起弹窗后仍知道筛选是生效的。
  Widget _buildFilterButton({required VoidCallback onPressed}) {
    return BlocBuilder<BookshelfSearchCubit, BookshelfSearchState>(
      // 只关心当前 tab 的排序与源勾选：输入关键词、切换别 tab 的源都不必重建。
      buildWhen: (previous, current) {
        final mode = _currentMode();
        final before = previous.stateOf(mode);
        final after = current.stateOf(mode);
        return before.sort != after.sort ||
            !listEquals(before.sources, after.sources);
      },
      builder: (context, searchState) {
        return BlocBuilder<GlobalSettingCubit, GlobalSettingState>(
          // 只有「隐藏文件夹」会影响圆点，其余全局设置变化直接跳过。
          buildWhen: (previous, current) =>
              _hideFoldersOf(_currentMode(), previous) !=
              _hideFoldersOf(_currentMode(), current),
          builder: (context, settingState) {
            final colorScheme = context.theme.colorScheme;
            return IconButton(
              tooltip: t.bookshelf.filter,
              icon: _hasActiveFilter(searchState, settingState)
                  ? Badge(
                      smallSize: 8,
                      backgroundColor: colorScheme.primary,
                      child: Icon(Icons.tune, color: colorScheme.primary),
                    )
                  : const Icon(Icons.tune),
              onPressed: onPressed,
            );
          },
        );
      },
    );
  }

  /// 该 tab 实际生效的排序：历史模式下残留的 `vd`/`va` 或异常值一律归一化为
  /// 默认 `dd`。`_openFilter` 的初始值与「是否有筛选」的判定必须共用它，
  /// 否则会出现顶栏亮着圆点、点开却是默认值且重置禁用的矛盾。
  String _effectiveSort(ShelfPageMode mode, String rawSort) {
    return switch ((mode, rawSort)) {
      (ShelfPageMode.favorite || ShelfPageMode.download, 'vd' || 'va') =>
        rawSort,
      (_, 'da') => 'da',
      _ => 'dd',
    };
  }

  /// 各 tab 的「隐藏文件夹」开关；历史没有文件夹体系，恒为 false。
  bool _hideFoldersOf(ShelfPageMode mode, GlobalSettingState settingState) {
    return switch (mode) {
      ShelfPageMode.favorite =>
        settingState.bookshelfSetting.hideFavoriteFolders,
      ShelfPageMode.download =>
        settingState.bookshelfSetting.hideDownloadFolders,
      ShelfPageMode.history => false,
    };
  }

  /// 非默认筛选判定：自定义排序、隐藏文件夹，或只勾选了部分漫画源。
  bool _hasActiveFilter(
    BookshelfSearchState searchState,
    GlobalSettingState settingState,
  ) {
    final mode = _currentMode();
    final current = searchState.stateOf(mode);
    if (_effectiveSort(mode, current.sort) != 'dd') {
      return true;
    }
    if (_hideFoldersOf(mode, settingState)) {
      return true;
    }
    final availableSources = _lastAvailableSources;
    if (availableSources.isNotEmpty) {
      final selectedCount = current.sources
          .where(availableSources.contains)
          .toSet()
          .length;
      if (selectedCount > 0 && selectedCount < availableSources.length) {
        return true;
      }
    }
    return false;
  }

  /// 展开移动端搜索栏。挂载的 SearchQueryField 自带 autoExpand，
  /// 首帧后自动展开浮层并聚焦，键盘随之弹出。
  void _expandSearch() {
    if (_isSearchExpanded) {
      return;
    }
    setState(() => _isSearchExpanded = true);
  }

  /// 退出搜索：先收起键盘；若有关键词则清空并刷新列表，再收起搜索栏。
  /// 与浮层输入框内的 ×（清空但保持展开，方便继续输入）语义区分开。
  void _exitSearch() {
    _keywordDebouncer.cancel();
    _searchFocusNode.unfocus();
    if (_currentSearchState().keyword.isNotEmpty) {
      _setKeyword('');
      _triggerRefresh(goTop: true);
    }
    if (_isSearchExpanded) {
      setState(() => _isSearchExpanded = false);
    }
  }

  /// 展开态打开筛选：弹窗会抢走焦点，关闭后若还在搜索态则恢复聚焦，键盘回来接着输。
  Future<void> _openFilterFromSearch() async {
    await _openFilter();
    if (mounted && _isSearchExpanded) {
      _searchFocusNode.requestFocus();
    }
  }

  Widget _buildMobileHeader() {
    if (_isSearchExpanded) {
      return Row(
        children: [
          IconButton(
            tooltip: t.common.back,
            icon: const Icon(Icons.arrow_back),
            onPressed: _exitSearch,
          ),
          Expanded(child: _buildShelfSearchField(autoExpand: true)),
          _buildFilterButton(onPressed: _openFilterFromSearch),
        ],
      );
    }

    return Row(
      children: [
        _buildSleekTabs(),
        const Spacer(),
        IconButton(icon: const Icon(Icons.search), onPressed: _expandSearch),
        _buildFilterButton(onPressed: _openFilter),
      ],
    );
  }

  Widget _buildSleekTabs() {
    return Container(
      decoration: BoxDecoration(
        color: context.theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.5,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(_labels.length, (index) {
          final isSelected = _currentIndex == index;
          return GestureDetector(
            onTap: () => _onTabChanged(index),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected
                    ? context.theme.colorScheme.surface
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ]
                    : [],
              ),
              child: Text(
                _labels[index],
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                  fontSize: 14,
                  color: isSelected
                      ? context.textColor
                      : context.textColor.withValues(alpha: 0.6),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  /// 关键词防抖写入。mode 在调用时快照，避免防抖期间切 tab 把词写到别的 tab。
  void _setKeywordDebounced(ShelfPageMode mode, String keyword) {
    _keywordDebouncer.run(() {
      if (!mounted) {
        return;
      }
      final cubit = context.read<BookshelfSearchCubit>();
      if (cubit.state.stateOf(mode).keyword == keyword) {
        return;
      }
      cubit.setKeyword(mode, keyword);
    });
  }

  /// 书架搜索框：复用搜索页的 SearchQueryField（浮层展开、多行展示、回车即搜）。
  /// 非空输入经 500ms 防抖写入 cubit（列表按 keyword 做 BlocBuilder 实时过滤）；
  /// 清空（删到空/点 ×）是明确的单次操作，立即生效；
  /// 回车提交立即生效、保持浮层展开并回到顶部，方便继续改词。桌面端常驻显示（autoExpand 关），
  /// 移动端在展开时挂载（autoExpand 开，首帧自动聚焦弹键盘）。
  Widget _buildShelfSearchField({required bool autoExpand}) {
    return BlocBuilder<BookshelfSearchCubit, BookshelfSearchState>(
      buildWhen: (prev, curr) =>
          prev.stateOf(_currentMode()).keyword !=
          curr.stateOf(_currentMode()).keyword,
      builder: (context, state) {
        return SearchQueryField(
          // 按 tab 区分 element：切 tab 时重建，保证各 tab 关键词独立，
          // 且展开中的浮层不会串词。
          key: ValueKey('shelf_search_$_currentIndex'),
          query: state.stateOf(_currentMode()).keyword,
          autoExpand: autoExpand,
          focusNode: _searchFocusNode,
          closeOnSubmit: false,
          hintText: t.bookshelf.searchList,
          semanticLabel: t.bookshelf.searchList,
          onChanged: (keyword) {
            if (keyword.isEmpty) {
              // 清空是明确的单次操作，立即生效，不走防抖。
              _keywordDebouncer.cancel();
              if (_currentSearchState().keyword.isNotEmpty) {
                _setKeyword('');
                _triggerRefresh(goTop: true);
              }
              return;
            }
            _setKeywordDebounced(_currentMode(), keyword);
          },
          onSubmitted: (keyword) {
            _keywordDebouncer.cancel();
            _setKeyword(keyword.trim());
            _triggerRefresh(goTop: true);
          },
        );
      },
    );
  }

  void _onTabChanged(int index) {
    if (index == _currentIndex) return;
    _tabController.animateTo(index);
  }

  void _handleTabControllerChanged() {
    if (!mounted || _currentIndex == _tabController.index) {
      return;
    }
    setState(() {
      _currentIndex = _tabController.index;
    });
  }

  ShelfPageMode _currentMode() {
    return switch (_currentIndex) {
      0 => ShelfPageMode.favorite,
      1 => ShelfPageMode.history,
      2 => ShelfPageMode.download,
      _ => ShelfPageMode.favorite,
    };
  }

  void _maybePersistSort(ShelfPageMode mode, String sort) {
    final cubit = context.read<GlobalSettingCubit>();
    final setting = cubit.state.bookshelfSetting;
    final shouldPersist = switch (mode) {
      ShelfPageMode.favorite => setting.rememberFavoriteSort,
      ShelfPageMode.history => setting.rememberHistorySort,
      ShelfPageMode.download => setting.rememberDownloadSort,
    };
    if (!shouldPersist) return;
    cubit.updateBookshelfSetting(
      (current) => switch (mode) {
        ShelfPageMode.favorite => current.copyWith(favoriteSort: sort),
        ShelfPageMode.history => current.copyWith(historySort: sort),
        ShelfPageMode.download => current.copyWith(downloadSort: sort),
      },
    );
  }

  SearchStatusState _currentSearchState() {
    final cubit = context.read<BookshelfSearchCubit>();
    return cubit.state.stateOf(_currentMode());
  }

  void _setKeyword(String keyword) {
    context.read<BookshelfSearchCubit>().setKeyword(_currentMode(), keyword);
  }

  void _triggerRefresh({bool goTop = false}) {
    setState(() {
      _refreshSignals[_currentIndex] = _refreshSignals[_currentIndex] + 1;
    });
  }

  void _triggerRefreshAll() {
    if (!mounted) {
      return;
    }
    setState(() {
      for (var i = 0; i < _refreshSignals.length; i++) {
        _refreshSignals[i] = _refreshSignals[i] + 1;
      }
    });
  }

  Future<void> _openFilter() async {
    final searchCubit = context.read<BookshelfSearchCubit>();
    final currentMode = _currentMode();
    final current = searchCubit.state.stateOf(currentMode);
    final sourceOptions = _buildFilterSourceOptions();
    final availableSources = sourceOptions
        .map((source) => source.pluginId)
        .toList();

    if (availableSources.isEmpty && currentMode == ShelfPageMode.history) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(t.bookshelf.noFilterSource)));
      return;
    }

    final globalSettingState = context.read<GlobalSettingCubit>().state;
    final initialHideFolders = _hideFoldersOf(currentMode, globalSettingState);

    var selectedSources = current.sources
        .where(availableSources.contains)
        .toSet();
    if (selectedSources.isEmpty) {
      selectedSources = availableSources.toSet();
    }

    final result = await showBookshelfFilterSheet(
      context,
      mode: currentMode,
      initialSort: _effectiveSort(currentMode, current.sort),
      initialSources: selectedSources,
      availableSources: availableSources,
      sourceOptions: sourceOptions,
      initialHideFolders: initialHideFolders,
    );

    if (result == null || !mounted) return;

    context.read<GlobalSettingCubit>().updateBookshelfSetting(
      (setting) => switch (currentMode) {
        ShelfPageMode.favorite => setting.copyWith(
          hideFavoriteFolders: result.hideFolders,
        ),
        ShelfPageMode.download => setting.copyWith(
          hideDownloadFolders: result.hideFolders,
        ),
        ShelfPageMode.history => setting,
      },
    );
    searchCubit.setSort(currentMode, result.sort);
    _maybePersistSort(currentMode, result.sort);

    final nextSources = result.sources.toList();
    searchCubit.setSources(currentMode, nextSources);
    _triggerRefresh(goTop: true);
  }

  List<BookshelfFilterSourceOption> _buildFilterSourceOptions() {
    final registry = context.read<PluginRegistryCubit>().state;
    final sourceOptions = PluginRegistryService.I.sortPlugins(
      registry.plugins.values.where(
        (plugin) => plugin.isEnabled && !plugin.isDeleted,
      ),
    );
    return sourceOptions
        .map(
          (plugin) => BookshelfFilterSourceOption(
            pluginId: plugin.uuid,
            title: registry.pluginName(plugin.uuid),
          ),
        )
        .toList();
  }

  void _syncSourcesFromRegistry(Map<String, PluginRuntimeState> pluginStates) {
    final available =
        pluginStates.values
            .where((plugin) => plugin.isEnabled && !plugin.isDeleted)
            .map((plugin) => plugin.uuid)
            .toList()
          ..sort();

    if (listEquals(_lastAvailableSources, available)) {
      return;
    }
    final addedSources = available
        .where((item) => !_lastAvailableSources.contains(item))
        .toList();
    _lastAvailableSources = List<String>.from(available);

    context.read<BookshelfSearchCubit>().syncSources(
      available,
      autoSelect: addedSources,
    );
  }

  String _pluginAvailabilityRevision(
    Map<String, PluginRuntimeState> pluginStates,
  ) {
    final entries =
        pluginStates.entries
            .map(
              (entry) =>
                  '${entry.key}:${entry.value.isEnabled ? 1 : 0}:${entry.value.isDeleted ? 1 : 0}',
            )
            .toList()
          ..sort();
    return entries.join('|');
  }
}
