import 'package:auto_route/auto_route.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
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
import 'package:zephyr/widgets/plugin_icon.dart';
import 'package:zephyr/widgets/toast.dart';

/// 插件通用 TabView 骨架（CalmUI 版）：
/// - 宽屏（>= 600px）：顶栏左侧插件切换胶囊 + 可横滑分类标签 + 工具按钮；
/// - 窄屏（< 600px）：顶栏释放给标题/分类标签，底部右下角（左手模式左下角）浮空轻胶囊
///   切源，支持下滑自动隐藏、上滑浮现以及左右轻滑快速切换上/下一个源。
///
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
  static const double _kCompactWidthBreakpoint = 600;

  late final PluginHomeCubit _cubit;
  final Map<String, ComicListCubit> _sceneCubits = {};
  TabController? _tabController;
  int _tabIndex = 0;
  bool _floatingPillVisible = true;
  double _scrollAccumulator = 0;

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

  void _restoreFloatingPill() {
    _scrollAccumulator = 0;
    if (!_floatingPillVisible && mounted) {
      setState(() => _floatingPillVisible = true);
    }
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) {
      return false;
    }
    if (notification is ScrollUpdateNotification) {
      final delta = notification.scrollDelta;
      if (delta == null || delta == 0) return false;

      if (notification.metrics.pixels <= 16) {
        _restoreFloatingPill();
        return false;
      }

      // 反向滚动时重置累计量，保证回滑灵敏浮现、下翻不误触。
      if ((delta > 0 && _scrollAccumulator < 0) ||
          (delta < 0 && _scrollAccumulator > 0)) {
        _scrollAccumulator = delta;
      } else {
        _scrollAccumulator += delta;
      }

      if (_scrollAccumulator > 14 && _floatingPillVisible) {
        _scrollAccumulator = 0;
        setState(() => _floatingPillVisible = false);
      } else if (_scrollAccumulator < -8 && !_floatingPillVisible) {
        _scrollAccumulator = 0;
        setState(() => _floatingPillVisible = true);
      }
    }
    return false;
  }

  void _syncSceneCubits(PluginHomeState state) {
    _restoreFloatingPill();
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
      _scrollAccumulator = 0;
      setState(() {
        _tabIndex = controller.index;
        _floatingPillVisible = true;
      });
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
          final pluginMeta = state.pluginId.isEmpty
              ? (name: '', iconUrl: '')
              : context.select<
                  PluginRegistryCubit,
                  ({String name, String iconUrl})
                >(
                  (cubit) => (
                    name: cubit.state.pluginName(state.pluginId),
                    iconUrl: cubit.state.pluginIconUrl(state.pluginId) ?? '',
                  ),
                );
          final leftHandMode = context.select<GlobalSettingCubit, bool>(
            (cubit) => cubit.state.leftHandModeEnabled,
          );
          final pluginLabel = pluginMeta.name.isNotEmpty
              ? pluginMeta.name
              : widget.pageTitle;

          return Scaffold(
            backgroundColor: c.bg,
            body: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final useFloatingSwitcher =
                      constraints.maxWidth < _kCompactWidthBreakpoint;
                  return Column(
                    children: [
                      _buildTopBar(
                        context,
                        state: state,
                        tabs: tabs,
                        activeTab: activeTab,
                        activeIndex: activeIndex,
                        hasTabBar: hasTabBar,
                        pluginLabel: pluginLabel,
                        pluginIconUrl: pluginMeta.iconUrl,
                        useFloatingSwitcher: useFloatingSwitcher,
                      ),
                      Expanded(
                        child: Stack(
                          children: [
                            NotificationListener<ScrollNotification>(
                              onNotification: _handleScrollNotification,
                              child: _buildBody(
                                context,
                                state,
                                tabs: tabs,
                                activeIndex: activeIndex,
                              ),
                            ),
                            if (useFloatingSwitcher &&
                                state.candidates.isNotEmpty)
                              Positioned(
                                bottom: 16,
                                left: leftHandMode ? 16 : null,
                                right: leftHandMode ? null : 16,
                                child: IgnorePointer(
                                  ignoring: !_floatingPillVisible,
                                  child: AnimatedSlide(
                                    duration: const Duration(milliseconds: 220),
                                    curve: Curves.easeOutCubic,
                                    offset: _floatingPillVisible
                                        ? Offset.zero
                                        : const Offset(0, 1.35),
                                    child: AnimatedOpacity(
                                      duration: const Duration(
                                        milliseconds: 180,
                                      ),
                                      curve: Curves.easeOut,
                                      opacity: _floatingPillVisible ? 1 : 0,
                                      child: _FloatingPluginSwitcherPill(
                                        pluginId: state.pluginId,
                                        label: pluginLabel,
                                        iconUrl: pluginMeta.iconUrl,
                                        tooltip: widget.selectorTitle,
                                        canQuickSwitch:
                                            state.candidates.length > 1,
                                        onTap: () =>
                                            _openSelector(context, state),
                                        onQuickSwitch: (delta) =>
                                            _quickSwitchPlugin(state, delta),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }

  /// 轻盈顶栏：
  /// - 宽屏：插件切换胶囊 + 分类标签 + 工具按钮；
  /// - 窄屏：移除左上角切换胶囊，把空间留给分类标签或页面标题。
  Widget _buildTopBar(
    BuildContext context, {
    required PluginHomeState state,
    required List<PluginHomeTab> tabs,
    required PluginHomeTab? activeTab,
    required int activeIndex,
    required bool hasTabBar,
    required String pluginLabel,
    required String pluginIconUrl,
    required bool useFloatingSwitcher,
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
          if (!useFloatingSwitcher)
            _PluginSwitcherPill(
              label: pluginLabel,
              iconUrl: pluginIconUrl,
              tooltip: widget.selectorTitle,
              maxWidth: 220,
              onTap: () => _openSelector(context, state),
            ),
          if (hasTabBar) ...[
            if (!useFloatingSwitcher) const SizedBox(width: 6),
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: _buildTabBar(context, tabs),
              ),
            ),
          ] else if (useFloatingSwitcher)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text(
                  widget.pageTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textHeightBehavior: kCalmTextHeightBehavior,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: c.text,
                    height: 1.25,
                    leadingDistribution: TextLeadingDistribution.even,
                  ),
                ),
              ),
            )
          else
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
    await _switchToPlugin(picked);
  }

  Future<void> _quickSwitchPlugin(PluginHomeState state, int delta) async {
    final candidates = state.candidates;
    if (candidates.length <= 1) {
      return;
    }
    final currentIndex = candidates.indexOf(state.pluginId);
    final base = currentIndex < 0 ? 0 : currentIndex;
    final nextIndex = (base + delta + candidates.length) % candidates.length;
    final nextId = candidates[nextIndex];
    if (nextId == state.pluginId) {
      return;
    }
    HapticFeedback.selectionClick();
    await _switchToPlugin(nextId);
  }

  Future<void> _switchToPlugin(String pluginId) async {
    _scrollAccumulator = 0;
    setState(() {
      _tabIndex = 0;
      _floatingPillVisible = true;
    });
    await _cubit.switchPlugin(pluginId);
    if (!mounted) {
      return;
    }
    if (_cubit.state.error.isNotEmpty) {
      showErrorToast(_cubit.state.error);
    }
  }
}

/// 插件迷你头像：真实插件图标 + 首字母柔和底色兜底，顶栏与浮空胶囊共用。
class _PluginMiniAvatar extends StatelessWidget {
  const _PluginMiniAvatar({
    required this.iconUrl,
    required this.label,
    required this.size,
    required this.radius,
  });

  final String iconUrl;
  final String label;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    final trimmed = label.trim();
    final initial = trimmed.isNotEmpty
        ? trimmed.characters.first.toUpperCase()
        : '';

    return Container(
      width: size,
      height: size,
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: c.border.withValues(alpha: c.border.a * 0.8),
          width: 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: PluginIcon(
          url: iconUrl,
          placeholder: ColoredBox(
            color: c.accentSoft,
            child: Center(
              child: initial.isNotEmpty
                  ? Text(
                      initial,
                      textHeightBehavior: kCalmTextHeightBehavior,
                      strutStyle: calmStrut(size * 0.46),
                      style: TextStyle(
                        fontSize: size * 0.46,
                        fontWeight: FontWeight.w700,
                        color: c.accent,
                        height: 1.2,
                        leadingDistribution: TextLeadingDistribution.even,
                      ),
                    )
                  : Icon(
                      Icons.extension_rounded,
                      size: size * 0.56,
                      color: c.accent,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 宽屏顶栏插件切换胶囊：真实插件小图标 + 插件名（超长省略）+ 下拉箭头。
class _PluginSwitcherPill extends StatefulWidget {
  const _PluginSwitcherPill({
    required this.label,
    required this.iconUrl,
    required this.onTap,
    this.tooltip,
    this.maxWidth = 220,
  });

  final String label;
  final String iconUrl;
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
        height: 32,
        constraints: BoxConstraints(maxWidth: widget.maxWidth),
        padding: const EdgeInsets.fromLTRB(6, 0, 9, 0),
        decoration: BoxDecoration(
          color: _hovered ? c.surfaceHover : c.surface2,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _PluginMiniAvatar(
              iconUrl: widget.iconUrl,
              label: widget.label,
              size: 20,
              radius: 10,
            ),
            const SizedBox(width: 6),
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

/// 窄屏/移动端底部浮空切换胶囊：
/// - 单手大拇指可轻松触达（自动适配左手模式）；
/// - 点按拉起源选择抽屉，左右轻滑直接切换上/下一个源。
class _FloatingPluginSwitcherPill extends StatefulWidget {
  const _FloatingPluginSwitcherPill({
    required this.pluginId,
    required this.label,
    required this.iconUrl,
    required this.canQuickSwitch,
    required this.onTap,
    required this.onQuickSwitch,
    this.tooltip,
  });

  final String pluginId;
  final String label;
  final String iconUrl;
  final bool canQuickSwitch;
  final VoidCallback onTap;
  final ValueChanged<int> onQuickSwitch;
  final String? tooltip;

  @override
  State<_FloatingPluginSwitcherPill> createState() =>
      _FloatingPluginSwitcherPillState();
}

class _FloatingPluginSwitcherPillState
    extends State<_FloatingPluginSwitcherPill> {
  bool _hovered = false;
  bool _pressed = false;
  double _dragDx = 0;

  void _handleDragUpdate(DragUpdateDetails details) {
    if (!widget.canQuickSwitch) return;
    setState(() {
      _dragDx = (_dragDx + details.delta.dx).clamp(-64.0, 64.0);
    });
  }

  void _handleDragEnd(DragEndDetails details) {
    if (!widget.canQuickSwitch) return;
    final velocity = details.primaryVelocity ?? 0;
    final dx = _dragDx;
    setState(() => _dragDx = 0);

    if (velocity.abs() > 160) {
      widget.onQuickSwitch(velocity < 0 ? 1 : -1);
    } else if (dx.abs() > 26) {
      widget.onQuickSwitch(dx < 0 ? 1 : -1);
    }
  }

  void _handleDragCancel() {
    if (_dragDx != 0) {
      setState(() => _dragDx = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    final visualShiftX = (_dragDx * 0.22).clamp(-12.0, 12.0);
    final bg = _hovered
        ? Color.alphaBlend(c.accent.withValues(alpha: 0.05), c.surface)
        : c.surface;

    final pill = AnimatedContainer(
      duration: _dragDx == 0
          ? const Duration(milliseconds: 180)
          : Duration.zero,
      curve: Curves.easeOutCubic,
      transform: Matrix4.translationValues(visualShiftX, 0, 0),
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          height: 40,
          constraints: const BoxConstraints(maxWidth: 210),
          padding: const EdgeInsets.fromLTRB(7, 0, 11, 0),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: _hovered ? c.accentBorder : c.border,
              width: 1,
            ),
            boxShadow: c.shadowMd,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _PluginMiniAvatar(
                iconUrl: widget.iconUrl,
                label: widget.label,
                size: 26,
                radius: 13,
              ),
              const SizedBox(width: 7),
              Flexible(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 160),
                  transitionBuilder: (child, anim) =>
                      FadeTransition(opacity: anim, child: child),
                  child: Text(
                    widget.label,
                    key: ValueKey('${widget.pluginId}_${widget.label}'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textHeightBehavior: kCalmTextHeightBehavior,
                    strutStyle: calmStrut(12.5),
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: c.text,
                      height: 1.2,
                      leadingDistribution: TextLeadingDistribution.even,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.unfold_more_rounded, size: 15, color: c.text3),
            ],
          ),
        ),
      ),
    );

    final interactive = MouseRegion(
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
        onHorizontalDragUpdate: widget.canQuickSwitch
            ? _handleDragUpdate
            : null,
        onHorizontalDragEnd: widget.canQuickSwitch ? _handleDragEnd : null,
        onHorizontalDragCancel: widget.canQuickSwitch
            ? _handleDragCancel
            : null,
        child: pill,
      ),
    );

    final tooltip = widget.tooltip;
    if (tooltip == null || tooltip.isEmpty) return interactive;
    return Tooltip(message: tooltip, child: interactive);
  }
}
