import 'package:auto_route/auto_route.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/router/router.gr.dart';
import 'package:zephyr/cubit/plugin_registry_cubit.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/comic_list/cubit/comic_list_cubit.dart';
import 'package:zephyr/page/discover/service/discover_router.dart';
import 'package:zephyr/page/plugin_home/cubit/plugin_home_cubit.dart';
import 'package:zephyr/page/plugin_home/plugin_home_bundle.dart';
import 'package:zephyr/page/plugin_home/view/plugin_home_tab_body.dart';
import 'package:zephyr/page/plugin_home/view/plugin_selector_dialog.dart';
import 'package:zephyr/page/search/cubit/search_cubit.dart';
import 'package:zephyr/ui/ui.dart';
import 'package:zephyr/widgets/error_view.dart';
import 'package:zephyr/widgets/toast.dart';

/// 插件通用 TabView 骨架（CalmUI 版）：轻盈顶栏 = 插件切换胶囊 + 可横滑分类标签 + 工具按钮。
///
/// [pageTitle] 为无 tab 时的标题；左侧胶囊既是切换入口，也显示当前插件名。
/// 内容每次重进重载，不保活；同插件内切 tab 由 [PluginHomeTabBody] 自行保活。
class PluginHomeScaffold extends StatefulWidget {
  const PluginHomeScaffold({
    super.key,
    required this.pageTitle,
    required this.selectorTitle,
    required this.createCubit,
  });

  final String pageTitle;
  final String selectorTitle;
  final PluginHomeCubit Function() createCubit;

  @override
  State<PluginHomeScaffold> createState() => _PluginHomeScaffoldState();
}

class _PluginHomeScaffoldState extends State<PluginHomeScaffold>
    with TickerProviderStateMixin {
  late final PluginHomeCubit _cubit;
  final Map<String, ComicListCubit> _sceneCubits = {};
  TabController? _tabController;
  int _tabIndex = 0;

  @override
  void initState() {
    super.initState();
    _cubit = widget.createCubit();
    // init 结束后直接加载，无延迟 hack。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _cubit.load();
      }
    });
  }

  @override
  void dispose() {
    _tabController?.dispose();
    for (final cubit in _sceneCubits.values) {
      cubit.close();
    }
    _cubit.close();
    super.dispose();
  }

  void _syncSceneCubits(PluginHomeState state) {
    final bundle = state.bundle;
    if (bundle == null) {
      _disposeSceneCubits();
      return;
    }
    final wanted = <String>{};
    for (var i = 0; i < bundle.tabs.length; i++) {
      final tab = bundle.tabs[i];
      if (tab.scene == null) {
        continue;
      }
      final key = '${tab.id}#$i';
      wanted.add(key);
      _sceneCubits.putIfAbsent(
        key,
        // 新两页内的 scene：登录错误不出全局弹窗，由 tab 错误体出登录/刷新。
        () => ComicListCubit(
          initialScene: tab.scene,
          suppressNeedLoginEvent: true,
        ),
      );
    }
    final stale = _sceneCubits.keys
        .where((key) => !wanted.contains(key))
        .toList();
    for (final key in stale) {
      _sceneCubits.remove(key)?.close();
    }
    _syncTabController(bundle.tabs.length);
  }

  void _disposeSceneCubits() {
    _tabController?.dispose();
    _tabController = null;
    _tabIndex = 0;
    for (final cubit in _sceneCubits.values) {
      cubit.close();
    }
    _sceneCubits.clear();
  }

  void _syncTabController(int tabCount) {
    if (tabCount <= 1) {
      _tabController?.dispose();
      _tabController = null;
      _tabIndex = 0;
      return;
    }
    if (_tabController == null || _tabController!.length != tabCount) {
      final previousIndex = _tabIndex.clamp(0, tabCount - 1);
      _tabController?.dispose();
      _tabController = TabController(
        length: tabCount,
        vsync: this,
        initialIndex: previousIndex,
      );
      _tabController!.addListener(_onTabChanged);
      _tabIndex = previousIndex;
    }
  }

  void _onTabChanged() {
    final controller = _tabController;
    if (controller == null || controller.indexIsChanging) {
      return;
    }
    if (_tabIndex != controller.index) {
      setState(() => _tabIndex = controller.index);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _cubit,
      child: BlocConsumer<PluginHomeCubit, PluginHomeState>(
        listenWhen: (previous, current) =>
            previous.pluginId != current.pluginId ||
            previous.bundle != current.bundle ||
            previous.reloadSignal != current.reloadSignal,
        listener: (context, state) => _syncSceneCubits(state),
        builder: (context, state) {
          final c = context.calm;
          final bundle = state.bundle;
          final tabs = bundle?.tabs ?? const <PluginHomeTab>[];
          final activeIndex = tabs.isEmpty
              ? 0
              : _tabIndex.clamp(0, tabs.length - 1);
          final activeTab = tabs.isEmpty ? null : tabs[activeIndex];
          final hasTabBar = tabs.length > 1 && _tabController != null;
          final pluginName = state.pluginId.isEmpty
              ? ''
              : context.select<PluginRegistryCubit, String>(
                  (cubit) => cubit.state.pluginName(state.pluginId),
                );

          return Scaffold(
            backgroundColor: c.bg,
            body: SafeArea(
              child: Column(
                children: [
                  _buildTopBar(
                    context,
                    state: state,
                    tabs: tabs,
                    activeTab: activeTab,
                    activeIndex: activeIndex,
                    hasTabBar: hasTabBar,
                    pluginName: pluginName,
                  ),
                  Expanded(
                    child: _buildBody(
                      context,
                      state,
                      tabs: tabs,
                      activeIndex: activeIndex,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// 轻盈顶栏：插件切换胶囊 + 分类标签（可横滑）+ 工具按钮，全程 c.bg / c.surface 分层。
  Widget _buildTopBar(
    BuildContext context, {
    required PluginHomeState state,
    required List<PluginHomeTab> tabs,
    required PluginHomeTab? activeTab,
    required int activeIndex,
    required bool hasTabBar,
    required String pluginName,
  }) {
    final c = context.calm;
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: c.bg,
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      child: Row(
        children: [
          _PluginSwitcherPill(
            label: pluginName.isNotEmpty ? pluginName : widget.pageTitle,
            tooltip: widget.selectorTitle,
            maxWidth: MediaQuery.sizeOf(context).width < 600 ? 148 : 220,
            onTap: () => _openSelector(context, state),
          ),
          if (hasTabBar) ...[
            const SizedBox(width: 6),
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: _buildTabBar(context, tabs),
              ),
            ),
          ] else
            const Spacer(),
          if (activeTab != null) ...[
            ..._buildActions(context, state, activeTab, activeIndex),
            if (activeTab.headerActions.isNotEmpty) const SizedBox(width: 2),
          ],
          CalmIconButton(
            icon: Icons.search_rounded,
            tooltip: t.discover.search,
            onPressed: () => _search(context, state),
          ),
          const SizedBox(width: 6),
          CalmIconButton(
            icon: Icons.refresh_rounded,
            tooltip: t.common.refresh,
            onPressed: () => _cubit.retry(),
          ),
        ],
      ),
    );
  }

  /// 轻盈横滑分类标签：主色下划线 + 文字色分层，保留 TabController 的手势与联动。
  Widget _buildTabBar(BuildContext context, List<PluginHomeTab> tabs) {
    final c = context.calm;
    final labelStyle = TextStyle(
      fontSize: 12.5,
      fontWeight: FontWeight.w600,
      color: c.text,
      height: 1.2,
      leadingDistribution: TextLeadingDistribution.even,
    );
    final unselectedStyle = TextStyle(
      fontSize: 12.5,
      fontWeight: FontWeight.w500,
      color: c.text3,
      height: 1.2,
      leadingDistribution: TextLeadingDistribution.even,
    );
    return SizedBox(
      height: 46,
      child: TabBar(
        controller: _tabController,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        dividerHeight: 0,
        indicatorSize: TabBarIndicatorSize.label,
        indicatorColor: c.accent,
        indicatorWeight: 2,
        splashFactory: NoSplash.splashFactory,
        overlayColor: WidgetStatePropertyAll(
          c.accentSoft.withValues(alpha: 0.35),
        ),
        labelColor: c.text,
        unselectedLabelColor: c.text3,
        labelStyle: labelStyle,
        unselectedLabelStyle: unselectedStyle,
        labelPadding: const EdgeInsets.symmetric(horizontal: 11),
        padding: EdgeInsets.zero,
        tabs: [
          for (final tab in tabs)
            Tab(
              height: 46,
              child: Text(
                tab.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textHeightBehavior: kCalmTextHeightBehavior,
                strutStyle: calmStrut(12.5),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _buildActions(
    BuildContext context,
    PluginHomeState state,
    PluginHomeTab activeTab,
    int activeIndex,
  ) {
    if (activeTab.scene != null) {
      final sceneCubit = _sceneCubits['${activeTab.id}#$activeIndex'];
      if (sceneCubit == null) {
        return const [];
      }
      return [
        BlocProvider.value(
          value: sceneCubit,
          child: BlocBuilder<ComicListCubit, ComicListState>(
            builder: (context, sceneState) {
              if (sceneState.scene?.filter == null) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: CalmIconButton(
                  icon: Icons.tune_rounded,
                  tooltip: t.comicList.filter,
                  onPressed: () =>
                      openPluginHomeFilterDialog(context, sceneCubit),
                ),
              );
            },
          ),
        ),
      ];
    }
    if (activeTab.headerActions.isEmpty) {
      return const [];
    }
    return [
      for (final action in activeTab.headerActions)
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: CalmIconButton(
            icon: _iconForAction(action),
            tooltip: action['title']?.toString() ?? t.oldHome.function,
            onPressed: () => DiscoverRouter.route(
              context,
              action: action,
              currentFrom: state.pluginId,
            ),
          ),
        ),
    ];
  }

  void _search(BuildContext context, PluginHomeState state) {
    final source = state.pluginId;
    if (source.isEmpty) {
      showErrorToast(t.discover.noPluginForSearch);
      return;
    }
    context.pushRoute(
      SearchRoute(
        searchState: SearchStates.initial().copyWith(from: source),
        aggregateMode: true,
      ),
    );
  }

  IconData _iconForAction(Map<String, dynamic> action) {
    final icon = action['icon']?.toString().trim() ?? '';
    if (icon.isNotEmpty) {
      return switch (icon) {
        'search' => Icons.search_rounded,
        'filter' => Icons.filter_alt_rounded,
        'settings' => Icons.settings_outlined,
        'refresh' => Icons.refresh_rounded,
        _ => Icons.play_arrow_rounded,
      };
    }
    return switch (action['type']?.toString().trim() ?? '') {
      'openSearch' => Icons.search_rounded,
      'openComicList' => Icons.view_list_outlined,
      'openPluginFunction' => Icons.extension_outlined,
      'openCloudFavorite' => Icons.cloud_outlined,
      'openWeb' => Icons.open_in_browser_rounded,
      'openComicInfo' => Icons.menu_book_outlined,
      _ => Icons.play_arrow_rounded,
    };
  }

  Widget _buildBody(
    BuildContext context,
    PluginHomeState state, {
    required List<PluginHomeTab> tabs,
    required int activeIndex,
  }) {
    if (state.loading) {
      return Center(child: CalmLoading(label: t.common.loading));
    }
    if (state.error.isNotEmpty) {
      return ErrorView(
        errorMessage: state.error,
        loginPluginId: state.loginPluginId,
        onRetry: () => _cubit.retry(),
      );
    }
    final bundle = state.bundle;
    if (bundle == null || bundle.tabs.isEmpty) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: CalmEmptyState(
            icon: Icons.extension_outlined,
            title: t.common.empty,
            subtitle: widget.selectorTitle,
            action: CalmButton(
              label: widget.selectorTitle,
              icon: Icons.extension_outlined,
              variant: CalmButtonVariant.primary,
              size: CalmButtonSize.sm,
              onPressed: () => _openSelector(context, state),
            ),
          ),
        ),
      );
    }
    if (tabs.length <= 1 || _tabController == null) {
      final index = _tabIndex.clamp(0, tabs.length - 1);
      final tab = tabs[index];
      return PluginHomeTabBody(
        key: ValueKey('${state.pluginId}_${tab.id}_$index'),
        pluginId: state.pluginId,
        tab: tab,
        sceneCubit: tab.scene == null ? null : _sceneCubits['${tab.id}#$index'],
      );
    }
    // 多 tab：TabBarView 支持左右滑动切换，controller 与 TabBar 共用。
    // page tab（scheme 渲染）是 ListView，scene tab 是分页列表，
    // TabBarView 的横向手势与纵向滚动不冲突。
    return TabBarView(
      controller: _tabController,
      children: [
        for (var i = 0; i < tabs.length; i++)
          PluginHomeTabBody(
            key: ValueKey('${state.pluginId}_${tabs[i].id}_$i'),
            pluginId: state.pluginId,
            tab: tabs[i],
            sceneCubit: tabs[i].scene == null
                ? null
                : _sceneCubits['${tabs[i].id}#$i'],
          ),
      ],
    );
  }

  Future<void> _openSelector(
    BuildContext context,
    PluginHomeState state,
  ) async {
    final picked = await showPluginHomeSelector(
      context,
      candidates: state.candidates,
      selectedId: state.pluginId,
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() => _tabIndex = 0);
    await _cubit.switchPlugin(picked);
    if (!mounted) {
      return;
    }
    if (_cubit.state.error.isNotEmpty) {
      showErrorToast(_cubit.state.error);
    }
  }
}

/// 顶栏插件切换胶囊：图标 + 插件名（超长省略）+ 下拉箭头，悬停/按压有轻微反馈。
class _PluginSwitcherPill extends StatefulWidget {
  const _PluginSwitcherPill({
    required this.label,
    required this.onTap,
    this.tooltip,
    this.maxWidth = 220,
  });

  final String label;
  final VoidCallback onTap;
  final String? tooltip;
  final double maxWidth;

  @override
  State<_PluginSwitcherPill> createState() => _PluginSwitcherPillState();
}

class _PluginSwitcherPillState extends State<_PluginSwitcherPill> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    final pill = AnimatedScale(
      scale: _pressed ? 0.97 : 1.0,
      duration: const Duration(milliseconds: 110),
      curve: Curves.easeOut,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        height: 30,
        constraints: BoxConstraints(maxWidth: widget.maxWidth),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: _hovered ? c.surfaceHover : c.surface2,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.extension_rounded, size: 14, color: c.accent),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textHeightBehavior: kCalmTextHeightBehavior,
                strutStyle: calmStrut(12),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: c.text,
                  height: 1.2,
                  leadingDistribution: TextLeadingDistribution.even,
                ),
              ),
            ),
            const SizedBox(width: 2),
            Icon(Icons.expand_more_rounded, size: 15, color: c.text3),
          ],
        ),
      ),
    );

    final content = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: pill,
      ),
    );

    final tooltip = widget.tooltip;
    if (tooltip == null || tooltip.isEmpty) return content;
    return Tooltip(message: tooltip, child: content);
  }
}
