import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:window_manager/window_manager.dart';
import 'package:zephyr/platform/desktop/desktop_window.dart';
import 'package:zephyr/ui/ui.dart';

/// 轻量独立入口：跳过 Rust / 数据库 / 后台服务，秒启秒热重载，专用于打磨基础组件视觉。
/// 启动命令：flutter run -t lib/main_ui_demo.dart
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CalmUiDemoApp());
  // Breeze 的 Windows runner 创建的是隐藏窗口（无 WS_VISIBLE），
  // 需等首帧进入消息循环后再调 show()，避免冷启动双击 exe 时窗口句柄尚未就绪。
  if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealDesktopWindow());
  }
}

void _revealDesktopWindow([int attempt = 0]) {
  final window = mainWindow;
  if (window == null) {
    if (attempt < 5) {
      Future<void>.delayed(
        const Duration(milliseconds: 80),
        () => _revealDesktopWindow(attempt + 1),
      );
    }
    return;
  }
  window.isVisibleInTaskbar = true;
  window.setSize(const Size(1200, 820).toNative(), false);
  window.center();
  window.show();
  window.focus();
}

class CalmUiDemoApp extends StatefulWidget {
  const CalmUiDemoApp({super.key});

  @override
  State<CalmUiDemoApp> createState() => _CalmUiDemoAppState();
}

class _CalmUiDemoAppState extends State<CalmUiDemoApp> {
  Brightness _brightness = Brightness.light;
  CalmSeed _seed = CalmSeed.sky;
  CalmDensity _density = CalmDensity.compact;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CalmUI · 基础组件演示',
      debugShowCheckedModeBanner: false,
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: CalmTheme.build(
        brightness: _brightness,
        seed: _seed,
        density: _density,
      ),
      home: _DemoHomePage(
        brightness: _brightness,
        seed: _seed,
        density: _density,
        onBrightnessChanged: (v) => setState(() => _brightness = v),
        onSeedChanged: (v) => setState(() => _seed = v),
        onDensityChanged: (v) => setState(() => _density = v),
      ),
    );
  }
}

class _DemoHomePage extends StatefulWidget {
  const _DemoHomePage({
    required this.brightness,
    required this.seed,
    required this.density,
    required this.onBrightnessChanged,
    required this.onSeedChanged,
    required this.onDensityChanged,
  });

  final Brightness brightness;
  final CalmSeed seed;
  final CalmDensity density;
  final ValueChanged<Brightness> onBrightnessChanged;
  final ValueChanged<CalmSeed> onSeedChanged;
  final ValueChanged<CalmDensity> onDensityChanged;

  @override
  State<_DemoHomePage> createState() => _DemoHomePageState();
}

class _DemoHomePageState extends State<_DemoHomePage> {
  bool _loadingBtn = false;
  bool _bookmarked = true;
  bool _pinned = false;

  String _dropdownVal = 'recent_update';
  final Map<String, CalmTriState> _triFilters = {
    '奇幻': CalmTriState.include,
    '治愈': CalmTriState.none,
    '后宫': CalmTriState.exclude,
    '已完结': CalmTriState.include,
  };
  String _readDir = 'rtl';
  bool _swAutoCrop = true;
  bool _swDoubleCover = false;
  double _preloadPages = 4;

  String _segMode = 'grid';
  String _pillTab = 'all';
  String _underlineTab = 'sources';
  int _demoNavIndex = 0;
  final Set<String> _selectedChips = {'连载中', '已离线'};
  bool _cbReadSync = true;
  bool _cbWifiOnly = false;
  int _stepperCols = 5;
  int _stepperThreads = 3;
  Set<String> _multiSelected = {'追更', '日漫生肉'};
  double _dlProgress = 0.64;
  final List<String> _searchHistoryTags = ['葬送的芙莉莲', '迷宫饭', '白滨鸥', '奇幻治愈'];
  CalmBottomLoaderStatus _loaderStatus = CalmBottomLoaderStatus.loading;

  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _commentCtrl = TextEditingController(
    text: '这一话的分镜留白和跨页节奏太舒服了，双页模式配合晴空浅色观感很轻盈！',
  );
  final TextEditingController _renameCtrl = TextEditingController(
    text: '治愈奇幻合集',
  );

  @override
  void dispose() {
    _searchCtrl.dispose();
    _commentCtrl.dispose();
    _renameCtrl.dispose();
    super.dispose();
  }

  void _toast(
    String title, {
    String? desc,
    CalmTone tone = CalmTone.info,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    CalmToast.show(
      context,
      title: title,
      description: desc,
      tone: tone,
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    final width = MediaQuery.sizeOf(context).width;
    final bpLabel = width < 600
        ? 'Mobile'
        : width < 1024
        ? 'Tablet'
        : 'Desktop';

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(c, bpLabel, width.round()),
            Expanded(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 960),
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(
                      width < 600 ? 12 : 24,
                      16,
                      width < 600 ? 12 : 24,
                      48,
                    ),
                    children: [
                      _buildTokensSection(c),
                      const SizedBox(height: 22),
                      _buildButtonsSection(c),
                      const SizedBox(height: 22),
                      _buildControlsSection(c, width),
                      const SizedBox(height: 22),
                      _buildChipsAndNavSection(c),
                      const SizedBox(height: 22),
                      _buildListsSection(c),
                      const SizedBox(height: 22),
                      _buildToastSection(c, width),
                      const SizedBox(height: 22),
                      _buildDialogSection(c, width),
                      const SizedBox(height: 22),
                      _buildStatesSection(c, width),
                      const SizedBox(height: 22),
                      _buildSelectionSection(c, width),
                      const SizedBox(height: 22),
                      _buildDisplaySection(c, width),
                      const SizedBox(height: 22),
                      _buildNavigationSection(c, width),
                      const SizedBox(height: 22),
                      _buildOverlayActionsSection(c),
                      const SizedBox(height: 22),
                      _buildExtraFoundationsSection(c, width),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(CalmColors c, String bpLabel, int widthPx) {
    final isDark = widget.brightness == Brightness.dark;
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: c.accent,
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Text(
              '静',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: c.accentFg,
                height: 1.0,
              ),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    'CalmUI 基础组件',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: c.text,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                CalmBadge(
                  label: '$bpLabel · ${widthPx}px',
                  tone: CalmBadgeTone.neutral,
                ),
              ],
            ),
          ),
          // 6 套主题色圆点
          if (widthPx >= 640)
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: c.surface2,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final s in CalmSeed.values) ...[
                    if (s != CalmSeed.values.first) const SizedBox(width: 6),
                    _SeedDot(
                      seed: s,
                      active: s == widget.seed,
                      onTap: () => widget.onSeedChanged(s),
                    ),
                  ],
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: CalmButton(
                label: widget.seed.label,
                size: CalmButtonSize.xs,
                variant: CalmButtonVariant.tonal,
                onPressed: () {
                  final idx =
                      (CalmSeed.values.indexOf(widget.seed) + 1) %
                      CalmSeed.values.length;
                  widget.onSeedChanged(CalmSeed.values[idx]);
                },
              ),
            ),
          CalmButton(
            label: widget.density.label,
            size: CalmButtonSize.xs,
            variant: CalmButtonVariant.secondary,
            onPressed: () => widget.onDensityChanged(
              widget.density == CalmDensity.compact
                  ? CalmDensity.comfortable
                  : CalmDensity.compact,
            ),
          ),
          const SizedBox(width: 6),
          CalmIconButton(
            icon: isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
            tooltip: isDark ? '切换晴朗浅色' : '切换清透深色',
            size: 30,
            iconSize: 16,
            onPressed: () => widget.onBrightnessChanged(
              isDark ? Brightness.light : Brightness.dark,
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String title, String hint, Widget child) {
    final c = context.calm;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: c.text,
                  ),
                ),
              ),
              Text(
                hint,
                style: TextStyle(
                  fontSize: 10.5,
                  fontFamily: 'monospace',
                  color: c.text3,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        CalmCard(child: child),
      ],
    );
  }

  Widget _subLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: context.calm.text3,
        ),
      ),
    );
  }

  // 01. 色彩令牌与字阶
  Widget _buildTokensSection(CalmColors c) {
    final swatches = [
      ('画布底色', 'bg', c.bg),
      ('卡片表面', 'surface', c.surface),
      ('次级容器', 'surface2', c.surface2),
      ('主题主色', 'accent', c.accent),
      ('柔和主色', 'accentSoft', c.accentSoft),
      ('成功语义', 'success', c.success),
      ('告警语义', 'warning', c.warning),
      ('危险语义', 'danger', c.danger),
    ];

    return _section(
      '01 · 色彩令牌与字体层级',
      'CalmTheme / CalmColors',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _subLabel('动态主题色令牌（切换顶部 6 色圆点与深浅模式实时联动）'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (name, key, color) in swatches)
                Container(
                  width: 102,
                  decoration: BoxDecoration(
                    color: c.bg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  foregroundDecoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: c.border),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(height: 30, color: color),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 5,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: c.text,
                              ),
                            ),
                            Text(
                              key,
                              style: TextStyle(
                                fontSize: 9.5,
                                fontFamily: 'monospace',
                                color: c.text3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          _subLabel('高密度字阶与等宽数字 (tabularFigures)'),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: c.bg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '15px Semibold · 页面/弹窗主标题',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: c.text,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '12.5px Medium · 列表行与正文说明文字',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: c.text2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Ch.008 · 18/22 页 · 8.4 MB · 09:12  |  Ch.138 · 22/22 页 · 14.8 MB · 20:05',
                  style: TextStyle(
                    fontSize: 11,
                    color: c.text3,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 02. 按钮与操作控件
  Widget _buildButtonsSection(CalmColors c) {
    return _section(
      '02 · 按钮与图标操作',
      'CalmButton / CalmIconButton',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _subLabel('五种语义层级（带轻微按压缩放回弹）'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              CalmButton(
                label: '主按钮 Primary',
                icon: Icons.play_arrow_rounded,
                variant: CalmButtonVariant.primary,
                size: CalmButtonSize.md,
                onPressed: () => _toast('触发主按钮', desc: '用于页面唯一主要操作'),
              ),
              CalmButton(
                label: '柔和强调 Tonal',
                icon: Icons.download_rounded,
                variant: CalmButtonVariant.tonal,
                size: CalmButtonSize.md,
                onPressed: () {},
              ),
              CalmButton(
                label: '次按钮 Secondary',
                variant: CalmButtonVariant.secondary,
                size: CalmButtonSize.md,
                onPressed: () {},
              ),
              CalmButton(
                label: '文字按钮 Ghost',
                variant: CalmButtonVariant.ghost,
                size: CalmButtonSize.md,
                onPressed: () {},
              ),
              CalmButton(
                label: '危险操作',
                icon: Icons.delete_outline_rounded,
                variant: CalmButtonVariant.danger,
                size: CalmButtonSize.md,
                onPressed: () {},
              ),
            ],
          ),
          const SizedBox(height: 14),
          _subLabel('尺寸规格 (XS / SM / MD)、加载态、禁用态与圆形图标按钮'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              CalmButton(
                label: '超小 XS',
                size: CalmButtonSize.xs,
                variant: CalmButtonVariant.primary,
                onPressed: () {},
              ),
              CalmButton(
                label: '标准 SM',
                size: CalmButtonSize.sm,
                variant: CalmButtonVariant.primary,
                onPressed: () {},
              ),
              CalmButton(
                label: '中等 MD',
                size: CalmButtonSize.md,
                variant: CalmButtonVariant.primary,
                onPressed: () {},
              ),
              CalmButton(
                label: _loadingBtn ? '同步中…' : '点我试加载态',
                icon: Icons.refresh_rounded,
                loading: _loadingBtn,
                variant: CalmButtonVariant.secondary,
                onPressed: () {
                  setState(() => _loadingBtn = true);
                  Future<void>.delayed(const Duration(milliseconds: 1100), () {
                    if (mounted) setState(() => _loadingBtn = false);
                  });
                },
              ),
              const CalmButton(
                label: '禁用态',
                variant: CalmButtonVariant.secondary,
                onPressed: null,
              ),
              CalmIconButton(
                icon: _bookmarked
                    ? Icons.bookmark_rounded
                    : Icons.bookmark_border_rounded,
                selected: _bookmarked,
                tooltip: '收藏切换',
                onPressed: () => setState(() => _bookmarked = !_bookmarked),
              ),
              CalmIconButton(
                icon: Icons.push_pin_rounded,
                selected: _pinned,
                tooltip: '置顶切换',
                onPressed: () => setState(() => _pinned = !_pinned),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // 03. 表单、三态筛选与 Fluent 下拉
  Widget _buildControlsSection(CalmColors c, double width) {
    final isWide = width >= 720;
    final inputs = [
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _subLabel('搜索输入框（清空按钮 + 快捷键徽章）'),
          CalmTextField(
            controller: _searchCtrl,
            prefixIcon: Icons.search_rounded,
            hintText: '搜索书名、作者、标签…',
            shortcutHint: 'Ctrl K',
          ),
        ],
      ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _subLabel('Fluent 下拉选择器（左侧 3px 居中竖条）'),
          CalmDropdown<String>(
            value: _dropdownVal,
            items: const [
              (value: 'recent_update', label: '按最近更新排序', meta: '默认'),
              (value: 'recent_read', label: '按最近阅读排序', meta: '常用'),
              (value: 'unread_desc', label: '按未读话数排序', meta: '追更'),
              (value: 'title_az', label: '按名称拼音排序', meta: 'A-Z'),
            ],
            onChanged: (v) => setState(() => _dropdownVal = v),
          ),
        ],
      ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _subLabel('校验错误态输入框'),
          const CalmTextField(
            hintText: '输入仓库地址…',
            errorText: '仓库地址必须以 index.min.json 结尾',
          ),
        ],
      ),
    ];

    final selectors = [
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _subLabel('三态筛选框（点击循环：忽略 / 包含 / 排除）'),
          for (final entry in _triFilters.entries) ...[
            CalmTriCheckbox(
              label: entry.key,
              state: entry.value,
              onChanged: (next) =>
                  setState(() => _triFilters[entry.key] = next),
            ),
            const SizedBox(height: 6),
          ],
        ],
      ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _subLabel('单选组 (Radio)'),
          CalmRadioTile<String>(
            label: '日漫从右到左 (RTL)',
            value: 'rtl',
            groupValue: _readDir,
            onChanged: (v) => setState(() => _readDir = v),
          ),
          const SizedBox(height: 6),
          CalmRadioTile<String>(
            label: '常规从左到右 (LTR)',
            value: 'ltr',
            groupValue: _readDir,
            onChanged: (v) => setState(() => _readDir = v),
          ),
          const SizedBox(height: 6),
          CalmRadioTile<String>(
            label: '条漫纵向连续滚动',
            value: 'webtoon',
            groupValue: _readDir,
            onChanged: (v) => setState(() => _readDir = v),
          ),
        ],
      ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _subLabel('开关 (Switch) & 滑块 (Slider)'),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('自动裁剪白边', style: TextStyle(fontSize: 12.5, color: c.text)),
              CalmSwitch(
                value: _swAutoCrop,
                onChanged: (v) => setState(() => _swAutoCrop = v),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('双页首张单显', style: TextStyle(fontSize: 12.5, color: c.text)),
              CalmSwitch(
                value: _swDoubleCover,
                onChanged: (v) => setState(() => _swDoubleCover = v),
              ),
            ],
          ),
          const SizedBox(height: 14),
          CalmSlider(
            label: '图片预加载页数',
            value: _preloadPages,
            min: 1,
            max: 10,
            divisions: 9,
            valueText: '${_preloadPages.round()} 页',
            onChanged: (v) => setState(() => _preloadPages = v),
          ),
        ],
      ),
    ];

    return _section(
      '03 · 表单输入、Fluent 下拉、三态筛选与滑块',
      'CalmTextField / CalmDropdown / CalmTriCheckbox / CalmSwitch',
      Column(
        children: [
          if (isWide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < inputs.length; i++) ...[
                  if (i > 0) const SizedBox(width: 12),
                  Expanded(child: inputs[i]),
                ],
              ],
            )
          else
            Column(
              children: [
                for (var i = 0; i < inputs.length; i++) ...[
                  if (i > 0) const SizedBox(height: 12),
                  inputs[i],
                ],
              ],
            ),
          const SizedBox(height: 16),
          Divider(height: 1, color: c.border),
          const SizedBox(height: 14),
          if (isWide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < selectors.length; i++) ...[
                  if (i > 0) const SizedBox(width: 14),
                  Expanded(child: selectors[i]),
                ],
              ],
            )
          else
            Column(
              children: [
                for (var i = 0; i < selectors.length; i++) ...[
                  if (i > 0) const SizedBox(height: 14),
                  selectors[i],
                ],
              ],
            ),
        ],
      ),
    );
  }

  // 04. 标签、分段控件与徽章
  Widget _buildChipsAndNavSection(CalmColors c) {
    return _section(
      '04 · 分段控件、计数标签、筛选芯片与徽章',
      'CalmSegmentedControl / CalmPillTabs / CalmFilterChip / CalmBadge',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 16,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _subLabel('分段控件 (Segmented Control)'),
                  CalmSegmentedControl<String>(
                    value: _segMode,
                    options: const [
                      (
                        value: 'grid',
                        label: '网格',
                        icon: Icons.grid_view_rounded,
                      ),
                      (value: 'compact', label: '紧凑', icon: Icons.apps_rounded),
                      (
                        value: 'list',
                        label: '列表',
                        icon: Icons.view_list_rounded,
                      ),
                    ],
                    onChanged: (v) => setState(() => _segMode = v),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _subLabel('胶囊计数标签栏 (Pill Tabs)'),
                  CalmPillTabs<String>(
                    value: _pillTab,
                    items: const [
                      (value: 'all', label: '全部', count: 138),
                      (value: 'unread', label: '未读', count: 12),
                      (value: 'offline', label: '已离线', count: 6),
                    ],
                    onChanged: (v) => setState(() => _pillTab = v),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          _subLabel('可多选筛选芯片（点击切换）'),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final tag in ['连载中', '已完结', '已离线', '有未读', '已追踪', '中文图源'])
                CalmFilterChip(
                  label: tag,
                  selected: _selectedChips.contains(tag),
                  onSelected: (on) => setState(() {
                    if (on) {
                      _selectedChips.add(tag);
                    } else {
                      _selectedChips.remove(tag);
                    }
                  }),
                ),
            ],
          ),
          const SizedBox(height: 14),
          _subLabel('语义胶囊徽章（严格垂直居中）'),
          const Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              CalmBadge(label: '18', tone: CalmBadgeTone.accent),
              CalmBadge(
                label: '12',
                icon: Icons.storage_rounded,
                tone: CalmBadgeTone.neutral,
              ),
              CalmBadge(label: '连载中', dot: true, tone: CalmBadgeTone.success),
              CalmBadge(
                label: 'Cloudflare',
                icon: Icons.shield_outlined,
                tone: CalmBadgeTone.warning,
              ),
              CalmBadge(label: '连接超时', tone: CalmBadgeTone.danger),
              CalmBadge(label: '1.6.0 → 1.6.2', tone: CalmBadgeTone.tonal),
            ],
          ),
        ],
      ),
    );
  }

  // 05. 分组头、列表行与折叠面板
  Widget _buildListsSection(CalmColors c) {
    return _section(
      '05 · 分组头、高密度列表行与折叠面板',
      'CalmSectionHeader / CalmListTile / CalmExpansionTile',
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CalmSectionHeader(
            title: '本周热门连载',
            countText: '48 部',
            actionLabel: '更多',
            onActionTap: () => _toast('进入「本周热门连载」'),
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: c.bg,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                CalmListTile(
                  leading: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.notifications_none_rounded,
                      size: 16,
                      color: c.accent,
                    ),
                  ),
                  title: '定时检查书架更新',
                  subtitle: '每 12 小时静默检查一次 · 仅在 Wi-Fi 下执行',
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '12 小时',
                        style: TextStyle(fontSize: 11.5, color: c.text3),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 16,
                        color: c.text3,
                      ),
                    ],
                  ),
                  onTap: () => _toast('打开更新周期设置'),
                ),
                Divider(height: 1, indent: 12, endIndent: 12, color: c.border),
                CalmListTile(
                  title: '自动跳过重复汉化组章节',
                  subtitle: '读完同一话后自动同步标为已读',
                  trailing: CalmSwitch(
                    value: _swAutoCrop,
                    onChanged: (v) => setState(() => _swAutoCrop = v),
                  ),
                ),
                Divider(height: 1, indent: 12, endIndent: 12, color: c.border),
                CalmExpansionTile(
                  title: '可折叠高级网络选项 (ExpansionTile)',
                  initiallyExpanded: true,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'User-Agent: Mozilla/5.0 (Breeze/3.2 Multi-Platform)',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontFamily: 'monospace',
                            color: c.text2,
                          ),
                        ),
                      ),
                      CalmButton(
                        label: '复制',
                        size: CalmButtonSize.xs,
                        variant: CalmButtonVariant.ghost,
                        onPressed: () =>
                            _toast('已复制 User-Agent', tone: CalmTone.success),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 06. 顶部通知 Toast
  Widget _buildToastSection(CalmColors c, double width) {
    final samples = [
      (
        title: '发现插件更新',
        desc: '禁漫扩展插件可升级至 v1.6.2，修复偶发图裂。',
        tone: CalmTone.info,
        action: '去更新',
      ),
      (
        title: '五端进度同步完成',
        desc: '已通过 WebDAV 合并 14 条阅读记录与 2 个分类。',
        tone: CalmTone.success,
        action: null,
      ),
      (
        title: '图源触发 Cloudflare 验证',
        desc: '目标站点返回 403，请使用内置 WebView 刷新 Cookie。',
        tone: CalmTone.warning,
        action: '去验证',
      ),
      (
        title: '下载队列有 1 话失败',
        desc: '第 74 话连接超时，可一键重试或切换代理。',
        tone: CalmTone.danger,
        action: '重试',
      ),
    ];

    final isTwoCol = width >= 700;

    return _section(
      '06 · 顶部悬浮通知 Toast（标题 + 内容）',
      'CalmToast / CalmToastCard',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _subLabel('桌面端右上角 / 手机端顶部居中弹出 · 点击任意卡片可实时触发顶部弹出预览'),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: samples.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: isTwoCol ? 2 : 1,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              mainAxisExtent: 74,
            ),
            itemBuilder: (_, idx) {
              final s = samples[idx];
              return MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => _toast(
                    s.title,
                    desc: s.desc,
                    tone: s.tone,
                    actionLabel: s.action,
                    onAction: s.action != null
                        ? () =>
                              _toast('已触发「${s.action}」', tone: CalmTone.success)
                        : null,
                  ),
                  child: CalmToastCard(
                    title: s.title,
                    description: s.desc,
                    tone: s.tone,
                    actionLabel: s.action,
                    onAction: s.action != null
                        ? () =>
                              _toast('已触发「${s.action}」', tone: CalmTone.success)
                        : null,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // 07. 弹出窗口基本样式与自适应抽屉
  Widget _buildDialogSection(CalmColors c, double width) {
    final isTwoCol = width >= 720;

    final cards = [
      CalmDialogSurface(
        title: '标准确认弹窗',
        subtitle: '常规同步、批量标记、迁移确认',
        icon: Icons.info_outline_rounded,
        tone: CalmTone.info,
        body: Text(
          '确定将选中的 4 部漫画全部标为已读并同步到其他设备？',
          style: TextStyle(fontSize: 12, color: c.text2),
        ),
        actions: [
          CalmButton(
            label: '取消',
            size: CalmButtonSize.xs,
            variant: CalmButtonVariant.ghost,
            onPressed: _openConfirmDialog,
          ),
          CalmButton(
            label: '弹出体验',
            size: CalmButtonSize.xs,
            variant: CalmButtonVariant.primary,
            onPressed: _openConfirmDialog,
          ),
        ],
      ),
      CalmDialogSurface(
        title: '危险操作确认弹窗',
        subtitle: '删除缓存、清空历史、卸载插件',
        icon: Icons.warning_amber_rounded,
        tone: CalmTone.danger,
        body: Text(
          '将移除本地 142 MB 离线章节文件，书架收藏与阅读进度不受影响。',
          style: TextStyle(fontSize: 12, color: c.text2),
        ),
        actions: [
          CalmButton(
            label: '取消',
            size: CalmButtonSize.xs,
            variant: CalmButtonVariant.ghost,
            onPressed: _openDangerDialog,
          ),
          CalmButton(
            label: '弹出体验',
            size: CalmButtonSize.xs,
            variant: CalmButtonVariant.danger,
            onPressed: _openDangerDialog,
          ),
        ],
      ),
      CalmDialogSurface(
        title: '表单输入弹窗',
        subtitle: '重命名文件夹、添加仓库、跳页',
        body: const CalmTextField(hintText: '治愈奇幻合集'),
        actions: [
          CalmButton(
            label: '取消',
            size: CalmButtonSize.xs,
            variant: CalmButtonVariant.ghost,
            onPressed: _openInputDialog,
          ),
          CalmButton(
            label: '弹出体验',
            size: CalmButtonSize.xs,
            variant: CalmButtonVariant.tonal,
            onPressed: _openInputDialog,
          ),
        ],
      ),
      CalmDialogSurface(
        title: '更新说明 / 内容弹窗',
        badge: 'v3.2.0',
        subtitle: '全平台版本发布日志',
        body: Text(
          '· 新增 6 套轻盈主题色与动态染底\n· 优化桌面居中弹窗与手机底部滑出体验',
          style: TextStyle(fontSize: 12, color: c.text2, height: 1.5),
        ),
        actions: [
          CalmButton(
            label: '弹出体验',
            size: CalmButtonSize.xs,
            variant: CalmButtonVariant.secondary,
            onPressed: _openChangelogDialog,
          ),
        ],
      ),
    ];

    return _section(
      '07 · 弹窗基本样式体系与自适应抽屉',
      'showCalmDialog / CalmDialogSurface / showCalmSheet',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _subLabel('桌面居中卡片 / 手机底部带抓手弹出 · 4 种基础模板直接对比并可点击弹出'),
          if (isTwoCol)
            Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: cards[0]),
                    const SizedBox(width: 12),
                    Expanded(child: cards[1]),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: cards[2]),
                    const SizedBox(width: 12),
                    Expanded(child: cards[3]),
                  ],
                ),
              ],
            )
          else
            Column(
              children: [
                for (var i = 0; i < cards.length; i++) ...[
                  if (i > 0) const SizedBox(height: 12),
                  cards[i],
                ],
              ],
            ),
          const SizedBox(height: 14),
          CalmButton(
            label: '打开自适应抽屉（手机底部 / 平板与桌面右侧滑出）',
            icon: Icons.view_sidebar_outlined,
            variant: CalmButtonVariant.tonal,
            onPressed: _openAdaptiveSheet,
          ),
        ],
      ),
    );
  }

  // 08. 状态横幅、空态、错误态与骨架屏
  Widget _buildStatesSection(CalmColors c, double width) {
    final isWide = width >= 720;
    final stateCards = [
      CalmEmptyState(
        icon: Icons.menu_book_rounded,
        title: '当前分类暂无漫画',
        subtitle: '可从图源添加或导入 .tachibk 备份',
        action: CalmButton(
          label: '去逛图源',
          icon: Icons.add_rounded,
          size: CalmButtonSize.xs,
          variant: CalmButtonVariant.tonal,
          onPressed: () => _toast('跳转图源浏览'),
        ),
      ),
      CalmErrorState(
        title: '需要重新登录图源',
        subtitle: '登录后自动恢复当前页面',
        errorDetail: 'HTTP 401 · token_expired_for_plugin',
        primaryLabel: '去登录',
        onPrimary: () => _toast('跳转图源登录页'),
        onRetry: () => _toast('正在重新拉取数据…'),
        onCopied: () => _toast('已复制错误信息', tone: CalmTone.success),
      ),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: c.bg,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CalmSkeletonBox(width: 84, height: 11),
            SizedBox(height: 12),
            Row(
              children: [
                CalmSkeletonBox(width: 48, height: 64, radius: 10),
                SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CalmSkeletonBox(width: 140, height: 12),
                      SizedBox(height: 8),
                      CalmSkeletonBox(width: 90, height: 10),
                      SizedBox(height: 10),
                      CalmSkeletonBox(height: 10),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ];

    return _section(
      '08 · 状态横幅、空态、友好错误页与骨架屏',
      'CalmStatusBanner / CalmEmptyState / CalmErrorState / CalmSkeletonBox',
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const CalmStatusBanner(
            title: '发现 1 个扩展插件可更新（1.6.0 → 1.6.2）',
            tone: CalmTone.info,
          ),
          const SizedBox(height: 8),
          CalmStatusBanner(
            title: '目标图源触发 Cloudflare 保护，需要 WebView 验证',
            tone: CalmTone.warning,
            trailing: CalmButton(
              label: '去验证',
              size: CalmButtonSize.xs,
              variant: CalmButtonVariant.secondary,
              onPressed: () => _toast(
                '已拉起内置 WebView',
                desc: '通过人机验证后将自动刷新页面。',
                tone: CalmTone.warning,
              ),
            ),
          ),
          const SizedBox(height: 8),
          const CalmStatusBanner(
            title: 'WebDAV 五端书架与阅读进度同步完成 · 0 冲突',
            tone: CalmTone.success,
          ),
          const SizedBox(height: 14),
          if (isWide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < stateCards.length; i++) ...[
                  if (i > 0) const SizedBox(width: 12),
                  Expanded(child: stateCards[i]),
                ],
              ],
            )
          else
            Column(
              children: [
                for (var i = 0; i < stateCards.length; i++) ...[
                  if (i > 0) const SizedBox(height: 12),
                  stateCards[i],
                ],
              ],
            ),
        ],
      ),
    );
  }

  void _openConfirmDialog() {
    showCalmDialog<void>(
      context,
      title: '批量标为已读',
      subtitle: '同步服务将在下次联网时合并至其他设备',
      icon: Icons.info_outline_rounded,
      tone: CalmTone.info,
      bodyBuilder: (ctx) => Text(
        '确定将选中的 4 部漫画全部标为已读？操作后仍可通过撤销按钮恢复。',
        style: TextStyle(fontSize: 12.5, color: ctx.calm.text2, height: 1.5),
      ),
      actionsBuilder: (ctx) => [
        CalmButton(
          label: '取消',
          variant: CalmButtonVariant.ghost,
          onPressed: () => Navigator.of(ctx).pop(),
        ),
        CalmButton(
          label: '确认执行',
          variant: CalmButtonVariant.primary,
          onPressed: () {
            Navigator.of(ctx).pop();
            _toast(
              '已批量标为已读',
              desc: '选中的 4 部作品已更新至最新章节。',
              tone: CalmTone.success,
              actionLabel: '撤销',
              onAction: () => _toast('已撤销批量标记'),
            );
          },
        ),
      ],
    );
  }

  void _openDangerDialog() {
    showCalmDialog<void>(
      context,
      title: '确认删除离线章节？',
      subtitle: '高危操作使用柔和玫瑰色，不刺眼',
      icon: Icons.warning_amber_rounded,
      tone: CalmTone.danger,
      bodyBuilder: (ctx) => Text(
        '将移除本地已缓存的 12 个章节图片文件（约 142 MB），书架收藏与阅读进度会完整保留。',
        style: TextStyle(fontSize: 12.5, color: ctx.calm.text2, height: 1.5),
      ),
      actionsBuilder: (ctx) => [
        CalmButton(
          label: '取消',
          variant: CalmButtonVariant.ghost,
          onPressed: () => Navigator.of(ctx).pop(),
        ),
        CalmButton(
          label: '确认删除',
          variant: CalmButtonVariant.danger,
          onPressed: () {
            Navigator.of(ctx).pop();
            _toast(
              '已清理离线缓存',
              desc: '已释放 142 MB 本地存储空间。',
              tone: CalmTone.warning,
            );
          },
        ),
      ],
    );
  }

  void _openInputDialog() {
    showCalmDialog<void>(
      context,
      title: '重命名书架文件夹',
      subtitle: '同步后自动更新至五端设备',
      bodyBuilder: (ctx) =>
          CalmTextField(controller: _renameCtrl, hintText: '请输入新的文件夹名称…'),
      actionsBuilder: (ctx) => [
        CalmButton(
          label: '取消',
          variant: CalmButtonVariant.ghost,
          onPressed: () => Navigator.of(ctx).pop(),
        ),
        CalmButton(
          label: '保存',
          variant: CalmButtonVariant.primary,
          onPressed: () {
            Navigator.of(ctx).pop();
            _toast(
              '文件夹已重命名',
              desc: '新名称：${_renameCtrl.text.trim()}',
              tone: CalmTone.success,
            );
          },
        ),
      ],
    );
  }

  void _openChangelogDialog() {
    showCalmDialog<void>(
      context,
      title: '发现新版本',
      badge: 'v3.2.0',
      subtitle: '全平台通用更新',
      bodyBuilder: (ctx) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: ctx.calm.bg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          '· 全新轻盈主题色系统，支持 6 套活泼低攻击性配色\n'
          '· 顶部悬浮通知 Toast 支持标题与详细说明\n'
          '· 统一手机底部与桌面居中自适应弹窗体验',
          style: TextStyle(fontSize: 12, color: ctx.calm.text2, height: 1.6),
        ),
      ),
      actionsBuilder: (ctx) => [
        CalmButton(
          label: '稍后再说',
          variant: CalmButtonVariant.ghost,
          onPressed: () => Navigator.of(ctx).pop(),
        ),
        CalmButton(
          label: '立即更新',
          variant: CalmButtonVariant.primary,
          onPressed: () {
            Navigator.of(ctx).pop();
            _toast('正在后台下载更新包', desc: '下载完成后下次启动生效。');
          },
        ),
      ],
    );
  }

  // 09. 二态复选、数字步进器、分段 PIN 与多选弹窗
  Widget _buildSelectionSection(CalmColors c, double width) {
    final isWide = width >= 720;
    final cols = [
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _subLabel('二态复选框 (CalmCheckbox / Tile)'),
          CalmCheckboxTile(
            label: '仅在 Wi-Fi 下自动缓存章节',
            subtitle: '避免消耗蜂窝流量',
            value: _cbWifiOnly,
            onChanged: (v) => setState(() => _cbWifiOnly = v),
          ),
          const SizedBox(height: 4),
          CalmCheckboxTile(
            label: '阅读完成自动同步追踪进度',
            value: _cbReadSync,
            onChanged: (v) => setState(() => _cbReadSync = v),
          ),
          const SizedBox(height: 10),
          CalmButton(
            label: '打开多选列表弹窗（已选 ${_multiSelected.length}）',
            variant: CalmButtonVariant.tonal,
            size: CalmButtonSize.sm,
            onPressed: () async {
              final res = await showCalmMultiChoiceDialog<String>(
                context,
                title: '选择目标分类',
                subtitle: '支持多选与全选操作',
                initialSelected: _multiSelected,
                options: const [
                  (value: '追更', label: '追更', subtitle: '每周连载'),
                  (value: '日漫生肉', label: '日漫生肉', subtitle: '生肉图源'),
                  (value: '完结典藏', label: '完结典藏', subtitle: '离线归档'),
                  (value: '待补短篇', label: '待补短篇', subtitle: null),
                  (value: '画集图包', label: '画集图包', subtitle: '高分辨率'),
                ],
              );
              if (res != null && mounted) {
                setState(() => _multiSelected = res);
                _toast(
                  '已更新多选结果',
                  desc: '当前共选中 ${res.length} 个分类',
                  tone: CalmTone.success,
                );
              }
            },
          ),
        ],
      ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _subLabel('数字步进器 (CalmStepper)'),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('网格每行列数', style: TextStyle(fontSize: 12.5, color: c.text)),
              CalmStepper(
                value: _stepperCols,
                min: 2,
                max: 8,
                suffix: ' 列',
                onChanged: (v) => setState(() => _stepperCols = v),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('下载并发线程', style: TextStyle(fontSize: 12.5, color: c.text)),
              CalmStepper(
                value: _stepperThreads,
                min: 1,
                max: 8,
                suffix: ' 线程',
                onChanged: (v) => setState(() => _stepperThreads = v),
              ),
            ],
          ),
        ],
      ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _subLabel('分段 PIN 码输入（点击方块可键入数字）'),
          CalmPinField(
            length: 4,
            initialValue: '2026',
            onCompleted: (code) =>
                _toast('PIN 输入完成', desc: '输入内容：$code', tone: CalmTone.success),
          ),
          const SizedBox(height: 8),
          Text(
            '支持点击聚焦直接键盘输入与剪贴板粘贴，也支持 obscure 掩码模式。',
            style: TextStyle(fontSize: 11, color: c.text3),
          ),
        ],
      ),
    ];

    return _section(
      '09 · 二态复选框、步进器、分段 PIN 与多选弹窗',
      'CalmCheckbox / CalmStepper / CalmPinField / showCalmMultiChoiceDialog',
      isWide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: cols[0]),
                const SizedBox(width: 16),
                Expanded(child: cols[1]),
                const SizedBox(width: 16),
                Expanded(child: cols[2]),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                cols[0],
                const SizedBox(height: 14),
                cols[1],
                const SizedBox(height: 14),
                cols[2],
              ],
            ),
    );
  }

  // 10. 进度条、头像与分割线
  Widget _buildDisplaySection(CalmColors c, double width) {
    final isWide = width >= 700;
    final progressCol = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _subLabel('线性进度条（定长 + 不定长动画态）'),
        CalmProgressBar(
          value: _dlProgress,
          label: '葬送的芙莉莲 · 第 138 话下载中',
          trailingText: '${(_dlProgress * 100).round()}% · 2.8 MB/s',
        ),
        const SizedBox(height: 12),
        CalmProgressBar(
          value: 0.24,
          label: '本地离线缓存容量',
          trailingText: '4.8 GB / 20 GB',
          color: c.success,
        ),
        const SizedBox(height: 12),
        const CalmProgressBar(value: null, label: '正在拉取云端插件仓库索引…'),
        const SizedBox(height: 10),
        CalmButton(
          label: '推进下载进度 +12%',
          size: CalmButtonSize.xs,
          variant: CalmButtonVariant.secondary,
          onPressed: () => setState(() {
            _dlProgress = _dlProgress >= 0.99
                ? 0.16
                : (_dlProgress + 0.12).clamp(0.0, 1.0);
          }),
        ),
      ],
    );

    final avatarCol = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _subLabel('头像（首字/图标兜底 + 角标）& 分割线'),
        const Wrap(
          spacing: 14,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            CalmAvatar(text: '风', size: 44, badge: 'Lv12'),
            CalmAvatar(text: '静', size: 38),
            CalmAvatar(icon: Icons.extension_rounded, size: 36, badge: '3'),
            CalmAvatar(icon: Icons.person_outline_rounded, size: 32),
          ],
        ),
        const SizedBox(height: 16),
        const CalmDivider(),
        const SizedBox(height: 12),
        const CalmDivider(label: '以下是已停用项'),
      ],
    );

    return _section(
      '10 · 进度条、头像与分割线',
      'CalmProgressBar / CalmAvatar / CalmDivider',
      isWide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 6, child: progressCol),
                const SizedBox(width: 20),
                Expanded(flex: 5, child: avatarCol),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [progressCol, const SizedBox(height: 16), avatarCol],
            ),
    );
  }

  // 11. 五端自适应导航、下划线标签与面包屑
  Widget _buildNavigationSection(CalmColors c, double width) {
    const navItems = [
      CalmNavItem(
        label: '书架',
        icon: Icons.collections_bookmark_outlined,
        activeIcon: Icons.collections_bookmark_rounded,
      ),
      CalmNavItem(label: '更新', icon: Icons.schedule_rounded, badgeCount: 12),
      CalmNavItem(label: '历史', icon: Icons.history_rounded),
      CalmNavItem(
        label: '浏览',
        icon: Icons.explore_outlined,
        activeIcon: Icons.explore_rounded,
        badgeCount: 1,
      ),
      CalmNavItem(label: '更多', icon: Icons.more_horiz_rounded, shortcut: '⌘,'),
    ];

    final isWide = width >= 720;

    return _section(
      '11 · 五端导航基础件、下划线标签与面包屑',
      'CalmBottomNavBar / CalmNavRail / CalmSidebarItem / CalmUnderlineTabs / CalmBreadcrumb',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 24,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _subLabel('下划线标签栏 (CalmUnderlineTabs)'),
                  CalmUnderlineTabs<String>(
                    value: _underlineTab,
                    items: const [
                      (value: 'sources', label: '图源', count: 7),
                      (value: 'extensions', label: '扩展插件', count: 2),
                      (value: 'migrate', label: '迁移', count: null),
                    ],
                    onChanged: (v) => setState(() => _underlineTab = v),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _subLabel('面包屑路径 (CalmBreadcrumb)'),
                  CalmBreadcrumb(
                    segments: const ['书架', '治愈奇幻合集', '葬送的芙莉莲'],
                    onTapSegment: (idx) => _toast('返回第 ${idx + 1} 级路径'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          _subLabel('三端导航样本（点击可联动切换激活态）'),
          if (isWide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CalmNavRail(
                  items: navItems,
                  currentIndex: _demoNavIndex,
                  onChanged: (i) => setState(() => _demoNavIndex = i),
                ),
                const SizedBox(width: 14),
                SizedBox(
                  width: 210,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: c.bg,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        for (var i = 0; i < navItems.length; i++)
                          CalmSidebarItem(
                            item: navItems[i],
                            active: i == _demoNavIndex,
                            onTap: () => setState(() => _demoNavIndex = i),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: CalmBottomNavBar(
                    items: navItems,
                    currentIndex: _demoNavIndex,
                    borderRadius: BorderRadius.circular(16),
                    onChanged: (i) => setState(() => _demoNavIndex = i),
                  ),
                ),
              ],
            )
          else
            CalmBottomNavBar(
              items: navItems,
              currentIndex: _demoNavIndex,
              borderRadius: BorderRadius.circular(16),
              onChanged: (i) => setState(() => _demoNavIndex = i),
            ),
        ],
      ),
    );
  }

  // 12. 上下文菜单、悬浮批量操作条与速拨菜单
  Widget _buildOverlayActionsSection(CalmColors c) {
    return _section(
      '12 · 上下文动作菜单、批量操作条与速拨悬浮菜单',
      'CalmPopupMenuButton / CalmBatchActionBar / CalmSpeedDial',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              CalmPopupMenuButton<String>(
                entries: const [
                  CalmPopupMenuEntry.item(
                    value: 'read',
                    label: '标记以下为已读',
                    icon: Icons.done_all_rounded,
                    shortcut: 'R',
                  ),
                  CalmPopupMenuEntry.item(
                    value: 'migrate',
                    label: '迁移至其他图源',
                    icon: Icons.swap_horiz_rounded,
                    shortcut: 'M',
                  ),
                  CalmPopupMenuEntry.item(
                    value: 'category',
                    label: '修改所属分类',
                    icon: Icons.folder_open_rounded,
                    shortcut: 'C',
                  ),
                  CalmPopupMenuEntry.divider(),
                  CalmPopupMenuEntry.item(
                    value: 'remove',
                    label: '移出书架',
                    icon: Icons.delete_outline_rounded,
                    danger: true,
                  ),
                ],
                onSelected: (v) => _toast(
                  '触发菜单动作：$v',
                  tone: v == 'remove' ? CalmTone.warning : CalmTone.info,
                ),
                child: const CalmButton(
                  label: '打开上下文菜单 (PopupMenu)',
                  icon: Icons.more_vert_rounded,
                  variant: CalmButtonVariant.secondary,
                ),
              ),
              CalmBatchActionBar(
                selectedCount: 4,
                onClose: () => _toast('退出多选模式'),
                actions: [
                  CalmButton(
                    label: '分类',
                    icon: Icons.drive_file_move_outlined,
                    size: CalmButtonSize.xs,
                    variant: CalmButtonVariant.ghost,
                    onPressed: () => _toast('批量移动分类'),
                  ),
                  CalmButton(
                    label: '已读',
                    icon: Icons.check_rounded,
                    size: CalmButtonSize.xs,
                    variant: CalmButtonVariant.ghost,
                    onPressed: () => _toast('批量标为已读', tone: CalmTone.success),
                  ),
                  CalmButton(
                    label: '移出',
                    icon: Icons.delete_outline_rounded,
                    size: CalmButtonSize.xs,
                    variant: CalmButtonVariant.danger,
                    onPressed: () => _toast(
                      '已移出 4 部作品',
                      tone: CalmTone.warning,
                      actionLabel: '撤销',
                      onAction: () => _toast('已撤销移出'),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          _subLabel('可展开速拨悬浮菜单 (CalmSpeedDial)'),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: c.bg,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Text(
                    '展开为紧凑悬浮动作卡片，手机单手点击与桌面鼠标操作都清晰整齐。',
                    style: TextStyle(fontSize: 11.5, color: c.text3),
                  ),
                ),
                const SizedBox(width: 12),
                CalmSpeedDial(
                  initiallyOpen: true,
                  actions: [
                    (
                      label: '新建书架文件夹',
                      icon: Icons.create_new_folder_outlined,
                      onTap: () => _toast('新建书架文件夹'),
                    ),
                    (
                      label: '导入本地压缩包',
                      icon: Icons.upload_file_rounded,
                      onTap: () => _toast('选择本地 CBZ / ZIP 文件'),
                    ),
                    (
                      label: '批量管理书架',
                      icon: Icons.checklist_rounded,
                      onTap: () => _toast('进入多选批量模式'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 13. 统一页面顶栏、多行文本域、可删标签、右键坐标菜单、展开长文本、色板与分页底栏
  Widget _buildExtraFoundationsSection(CalmColors c, double width) {
    final isWide = width >= 720;

    final leftCol = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _subLabel('多行文本域 (CalmTextArea · 带字数计数)'),
        CalmTextArea(
          controller: _commentCtrl,
          hintText: '写一条评论、备注或屏蔽词列表…',
          maxLength: 200,
        ),
        const SizedBox(height: 14),
        _subLabel('可折叠长文本 (CalmExpandableText · 仅溢出时显示展开)'),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: c.bg,
            borderRadius: BorderRadius.circular(14),
          ),
          child: const CalmExpandableText(
            maxLines: 2,
            text: '打倒魔王后的十年旅途结束，长寿的精灵魔法使芙莉莲在昔日勇者离世后，决定踏上重新认识人类情感与时间意义的北方之旅。一路上她结识了新伙伴菲伦与休塔尔克，在平淡却温柔的日常中回望过去。',
          ),
        ),
      ],
    );

    final rightCol = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _subLabel('可移除标签 (CalmInputChip · 搜索历史 / 屏蔽词)'),
            if (_searchHistoryTags.length < 4)
              CalmButton(
                label: '恢复示例',
                size: CalmButtonSize.xs,
                variant: CalmButtonVariant.ghost,
                onPressed: () => setState(() {
                  _searchHistoryTags
                    ..clear()
                    ..addAll(['葬送的芙莉莲', '迷宫饭', '白滨鸥', '奇幻治愈']);
                }),
              ),
          ],
        ),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final tag in _searchHistoryTags)
              CalmInputChip(
                label: tag,
                icon: Icons.history_rounded,
                onTap: () => _toast('搜索历史：$tag'),
                onDeleted: () => setState(() => _searchHistoryTags.remove(tag)),
              ),
          ],
        ),
        const SizedBox(height: 14),
        _subLabel('桌面右键坐标菜单 (showCalmContextMenu · 右键或点击测试区域)'),
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onSecondaryTapDown: (d) => _openContextMenuAt(d.globalPosition),
            onTapDown: (d) => _openContextMenuAt(d.globalPosition),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
              decoration: BoxDecoration(
                color: c.bg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: c.borderStrong),
              ),
              child: Row(
                children: [
                  Icon(Icons.mouse_rounded, size: 16, color: c.accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '在此区域任意位置点击或鼠标右键，测试跟随光标弹出的上下文菜单（自动防出屏）',
                      style: TextStyle(fontSize: 11.5, color: c.text2),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        _subLabel('主题色选择网格 (CalmColorGrid · 与顶部实时联动)'),
        CalmColorGrid(selected: widget.seed, onSelected: widget.onSeedChanged),
      ],
    );

    return _section(
      '13 · 顶栏壳、多行输入、可删标签、右键菜单、长文本与分页底栏',
      'CalmAppBar / CalmTextArea / CalmInputChip / showCalmContextMenu / CalmBottomLoader',
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _subLabel('统一二级页顶栏 (CalmAppBar · 悬停图标可看轻盈 Tooltip)'),
          CalmAppBar(
            title: '外观与阅读设置',
            subtitle: '五端统一二级页壳 (CalmPageScaffold)',
            badge: '6 主题色',
            borderRadius: BorderRadius.circular(14),
            onBack: () => _toast('点击了顶栏返回'),
            actions: [
              CalmIconButton(
                icon: Icons.help_outline_rounded,
                tooltip: '轻盈圆角 Tooltip 已全局生效',
                size: 30,
                iconSize: 15,
                onPressed: () => _toast('打开帮助说明'),
              ),
              CalmButton(
                label: '保存',
                size: CalmButtonSize.xs,
                variant: CalmButtonVariant.primary,
                onPressed: () => _toast('已保存设置', tone: CalmTone.success),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (isWide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: leftCol),
                const SizedBox(width: 16),
                Expanded(child: rightCol),
              ],
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [leftCol, const SizedBox(height: 16), rightCol],
            ),
          const SizedBox(height: 16),
          Divider(height: 1, color: c.border),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _subLabel('分页列表底部加载条 (CalmBottomLoader · 三态切换)'),
              CalmSegmentedControl<CalmBottomLoaderStatus>(
                value: _loaderStatus,
                options: const [
                  (
                    value: CalmBottomLoaderStatus.loading,
                    label: '加载中',
                    icon: null,
                  ),
                  (
                    value: CalmBottomLoaderStatus.error,
                    label: '失败',
                    icon: null,
                  ),
                  (
                    value: CalmBottomLoaderStatus.noMore,
                    label: '到底了',
                    icon: null,
                  ),
                ],
                onChanged: (v) => setState(() => _loaderStatus = v),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: c.bg,
              borderRadius: BorderRadius.circular(14),
            ),
            child: CalmBottomLoader(
              status: _loaderStatus,
              onRetry: () {
                setState(() => _loaderStatus = CalmBottomLoaderStatus.loading);
                _toast('正在重试加载下一页…');
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openContextMenuAt(Offset pos) async {
    final result = await showCalmContextMenu<String>(
      context,
      globalPosition: pos,
      entries: const [
        CalmPopupMenuEntry.item(
          value: 'open',
          label: '直接继续阅读',
          icon: Icons.play_arrow_rounded,
          shortcut: 'Enter',
        ),
        CalmPopupMenuEntry.item(
          value: 'folder',
          label: '移动到文件夹',
          icon: Icons.drive_file_move_outlined,
          shortcut: 'M',
        ),
        CalmPopupMenuEntry.item(
          value: 'download',
          label: '缓存全部未读',
          icon: Icons.download_rounded,
          shortcut: 'D',
        ),
        CalmPopupMenuEntry.divider(),
        CalmPopupMenuEntry.item(
          value: 'delete',
          label: '从书架移除',
          icon: Icons.delete_outline_rounded,
          danger: true,
        ),
      ],
    );
    if (result != null && mounted) {
      _toast(
        '右键菜单选中：$result',
        tone: result == 'delete' ? CalmTone.warning : CalmTone.info,
      );
    }
  }

  void _openAdaptiveSheet() {
    showCalmSheet<void>(
      context,
      title: '自适应抽屉 (Sheet)',
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '手机端作为底部 BottomSheet 滑出，平板与桌面端自动切换为右侧 SideSheet，避免大屏底部弹窗过宽。',
              style: TextStyle(
                fontSize: 12.5,
                color: ctx.calm.text2,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            CalmListTile(
              title: '显示未读角标',
              trailing: CalmSwitch(
                value: _swAutoCrop,
                onChanged: (v) {
                  setState(() => _swAutoCrop = v);
                  setSheetState(() {});
                },
              ),
            ),
            CalmListTile(
              title: '双页模式首张单显',
              trailing: CalmSwitch(
                value: _swDoubleCover,
                onChanged: (v) {
                  setState(() => _swDoubleCover = v);
                  setSheetState(() {});
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SeedDot extends StatelessWidget {
  const _SeedDot({
    required this.seed,
    required this.active,
    required this.onTap,
  });

  final CalmSeed seed;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    return Tooltip(
      message: '主题色：${seed.label}',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            width: active ? 16 : 14,
            height: active ? 16 : 14,
            decoration: BoxDecoration(
              color: seed.swatch,
              shape: BoxShape.circle,
              border: active ? Border.all(color: c.surface, width: 2) : null,
              boxShadow: active
                  ? [
                      BoxShadow(
                        color: seed.swatch.withValues(alpha: 0.45),
                        blurRadius: 6,
                      ),
                    ]
                  : const [],
            ),
          ),
        ),
      ),
    );
  }
}
