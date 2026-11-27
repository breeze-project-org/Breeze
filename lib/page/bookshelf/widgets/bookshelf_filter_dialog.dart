import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/bookshelf/models/shelf_page_mode.dart';

/// 书架筛选弹窗的返回值。
class BookshelfFilterResult {
  BookshelfFilterResult({
    required this.sort,
    required Set<String> sources,
    required this.hideFolders,
  }) : sources = Set<String>.from(sources);

  final String sort;
  final Set<String> sources;
  final bool hideFolders;
}

/// 书架筛选弹窗里可勾选的漫画源。
class BookshelfFilterSourceOption {
  const BookshelfFilterSourceOption({
    required this.pluginId,
    required this.title,
  });

  final String pluginId;
  final String title;
}

/// 打开书架筛选弹窗：窄屏走底部弹层，宽屏走居中弹窗。
/// 取消/关闭返回 null，应用返回用户确认的草稿。
Future<BookshelfFilterResult?> showBookshelfFilterSheet(
  BuildContext context, {
  required ShelfPageMode mode,
  required String initialSort,
  required Set<String> initialSources,
  required List<String> availableSources,
  required List<BookshelfFilterSourceOption> sourceOptions,
  required bool initialHideFolders,
}) {
  final isCompact = MediaQuery.sizeOf(context).width < 600;
  // 容器形态在打开的那一刻定死并与宿主路由保持一致：窗口跨过 600px 断点缩放
  // 或折叠屏展开收起时，不会出现底部弹层里套 Dialog、或 Dialog 里冒出拖拽条。
  final sheet = _BookshelfFilterSheet(
    isCompact: isCompact,
    mode: mode,
    initialSort: initialSort,
    initialSources: initialSources,
    availableSources: availableSources,
    sourceOptions: sourceOptions,
    initialHideFolders: initialHideFolders,
  );

  if (isCompact) {
    return showModalBottomSheet<BookshelfFilterResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      isDismissible: true,
      enableDrag: true,
      builder: (_) => sheet,
    );
  }

  return showDialog<BookshelfFilterResult>(
    context: context,
    builder: (_) => sheet,
  );
}

class _BookshelfFilterSheet extends StatefulWidget {
  const _BookshelfFilterSheet({
    required this.isCompact,
    required this.mode,
    required this.initialSort,
    required this.initialSources,
    required this.availableSources,
    required this.sourceOptions,
    required this.initialHideFolders,
  });

  /// 与宿主路由一一对应：true 为底部弹层，false 为居中 Dialog。
  final bool isCompact;
  final ShelfPageMode mode;
  final String initialSort;
  final Set<String> initialSources;
  final List<String> availableSources;
  final List<BookshelfFilterSourceOption> sourceOptions;
  final bool initialHideFolders;

  @override
  State<_BookshelfFilterSheet> createState() => _BookshelfFilterSheetState();
}

class _BookshelfFilterSheetState extends State<_BookshelfFilterSheet> {
  static const String _defaultSort = 'dd';

  /// 真正有效的漫画源集合：计数、全选判定与脏数据过滤都以它为准，
  /// 只在初次读取时构建一次，避免每次 build 重新分配。
  late final Set<String> _availableSourceSet = _resolveAvailableSources();

  late String _selectedSort;
  late Set<String> _selectedSources;
  late bool _hideFolders;

  /// availableSources 为空表示调用方不做限制，退回可勾选列表，
  /// 保证计数分母与 chip 数量始终一致。
  Set<String> _resolveAvailableSources() {
    if (widget.availableSources.isEmpty) {
      return widget.sourceOptions.map((option) => option.pluginId).toSet();
    }
    return widget.availableSources.toSet();
  }

  @override
  void initState() {
    super.initState();
    _selectedSort = widget.initialSort;
    // 与有效源取交集：外部传入的已禁用/已卸载 ID 不能参与计数与返回值。
    _selectedSources = widget.initialSources
        .where(_availableSourceSet.contains)
        .toSet();
    _hideFolders = widget.initialHideFolders;
  }

  /// 历史没有文件夹体系，也没有按观看时间排序。
  bool get _supportsFolders => widget.mode != ShelfPageMode.history;

  bool get _canApply =>
      _availableSourceSet.isEmpty || _selectedSources.isNotEmpty;

  bool get _isAllSourcesSelected =>
      _availableSourceSet.isNotEmpty &&
      _hasSameSources(_selectedSources, _availableSourceSet);

  bool get _isDirtyFromDefault =>
      _selectedSort != _defaultSort ||
      (_supportsFolders && _hideFolders) ||
      (_availableSourceSet.isNotEmpty &&
          !_hasSameSources(_selectedSources, _availableSourceSet));

  bool _hasSameSources(Set<String> current, Set<String> target) {
    return current.length == target.length && current.containsAll(target);
  }

  void _resetToDefault() {
    HapticFeedback.selectionClick();
    setState(() {
      _selectedSort = _defaultSort;
      _hideFolders = false;
      _selectedSources = Set<String>.from(_availableSourceSet);
    });
  }

  void _toggleSelectAll() {
    HapticFeedback.selectionClick();
    setState(() {
      if (_isAllSourcesSelected) {
        _selectedSources.clear();
      } else {
        _selectedSources = Set<String>.from(_availableSourceSet);
      }
    });
  }

  void _selectSort(String sort) {
    HapticFeedback.selectionClick();
    setState(() => _selectedSort = sort);
  }

  void _toggleSource(String pluginId, bool selected) {
    HapticFeedback.selectionClick();
    setState(() {
      if (selected) {
        _selectedSources.add(pluginId);
      } else {
        _selectedSources.remove(pluginId);
      }
    });
  }

  void _apply() {
    Navigator.of(context).pop(
      BookshelfFilterResult(
        sort: _selectedSort,
        sources: _selectedSources,
        hideFolders: _hideFolders,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // 形态由宿主路由下发，只有高度上限跟随当前窗口实时变化。
    final isCompact = widget.isCompact;
    final maxHeight = MediaQuery.sizeOf(context).height;

    if (isCompact) {
      return ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight * 0.82),
        child: Material(
          color: colorScheme.surfaceContainerHigh,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDragHandle(colorScheme),
              _buildHeader(context, isCompact: true),
              _buildBody(context, isCompact: true),
              _buildFooter(context, isCompact: true),
            ],
          ),
        ),
      );
    }

    return Dialog(
      backgroundColor: colorScheme.surfaceContainerHigh,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.45),
          width: 1,
        ),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 460, maxHeight: maxHeight * 0.8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(context, isCompact: false),
            _buildBody(context, isCompact: false),
            _buildFooter(context, isCompact: false),
          ],
        ),
      ),
    );
  }

  Widget _buildDragHandle(ColorScheme colorScheme) {
    return Center(
      child: Container(
        width: 36,
        height: 4,
        margin: const EdgeInsets.only(top: 10, bottom: 4),
        decoration: BoxDecoration(
          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, {required bool isCompact}) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      children: [
        Padding(
          padding: isCompact
              ? const EdgeInsets.fromLTRB(20, 8, 12, 12)
              : const EdgeInsets.fromLTRB(24, 20, 16, 12),
          child: Row(
            children: [
              Icon(Icons.tune_rounded, size: 20, color: colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  t.bookshelf.filter,
                  style: textTheme.titleMedium?.copyWith(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
              TextButton(
                onPressed: _isDirtyFromDefault ? _resetToDefault : null,
                style: TextButton.styleFrom(
                  foregroundColor: colorScheme.primary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: Text(t.common.reset),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                iconSize: 20,
                tooltip: t.common.close,
                visualDensity: VisualDensity.compact,
                color: colorScheme.onSurfaceVariant,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        Divider(
          height: 1,
          thickness: 1,
          color: colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ],
    );
  }

  Widget _buildBody(BuildContext context, {required bool isCompact}) {
    return Flexible(
      child: SingleChildScrollView(
        padding: isCompact
            ? const EdgeInsets.fromLTRB(20, 16, 20, 16)
            : const EdgeInsets.fromLTRB(24, 16, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSortSection(context),
            const SizedBox(height: 20),
            if (_supportsFolders) ...[
              _buildDisplaySection(context),
              const SizedBox(height: 20),
            ],
            _buildSourceSection(context),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Text(
      title,
      style: textTheme.titleSmall?.copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: colorScheme.onSurfaceVariant,
        letterSpacing: 0.2,
      ),
    );
  }

  Widget _buildSortSection(BuildContext context) {
    final options = <(String, String)>[
      ('dd', t.bookshelf.sortDesc),
      ('da', t.bookshelf.sortAsc),
      if (_supportsFolders) ...[
        ('vd', t.bookshelf.viewSortDesc),
        ('va', t.bookshelf.viewSortAsc),
      ],
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(context, t.bookshelf.sort),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (value, label) in options)
              _buildSortChip(
                context,
                label: label,
                selected: _selectedSort == value,
                onSelected: () => _selectSort(value),
              ),
          ],
        ),
      ],
    );
  }

  /// 排序 chip 与漫画源 chip 共用的外观：圆角、紧凑密度与选中态配色。
  /// 样式统一走 [ChipTheme]，两种 chip 只声明各自独有的部分。
  Widget _buildStyledChip(
    BuildContext context, {
    required bool selected,
    required Widget chip,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return ChipTheme(
      data: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        labelPadding: const EdgeInsets.symmetric(horizontal: 4),
        backgroundColor: colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.45,
        ),
        selectedColor: colorScheme.primaryContainer.withValues(alpha: 0.92),
        side: BorderSide(
          color: selected
              ? colorScheme.primary
              : colorScheme.outlineVariant.withValues(alpha: 0.7),
          width: selected ? 1.4 : 1,
        ),
        labelStyle: textTheme.bodyMedium?.copyWith(
          fontSize: 13,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          color: selected
              ? colorScheme.onPrimaryContainer
              : colorScheme.onSurface,
        ),
        checkmarkColor: colorScheme.onPrimaryContainer,
      ),
      child: chip,
    );
  }

  Widget _buildSortChip(
    BuildContext context, {
    required String label,
    required bool selected,
    required VoidCallback onSelected,
  }) {
    return _buildStyledChip(
      context,
      selected: selected,
      chip: ChoiceChip(
        showCheckmark: false,
        label: Text(label),
        selected: selected,
        onSelected: (_) => onSelected(),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  Widget _buildDisplaySection(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(context, t.bookshelf.display),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.65),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            // 透明 Material 只为让 SwitchListTile 的水波纹有落点：
            // 外层 Container 带背景色，直接贴 ListTile 会触发 debug 断言。
            child: Material(
              type: MaterialType.transparency,
              child: SwitchListTile.adaptive(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 2,
                ),
                value: _hideFolders,
                onChanged: (value) {
                  HapticFeedback.selectionClick();
                  setState(() => _hideFolders = value);
                },
                title: Text(
                  t.bookshelf.hideFolders,
                  style: textTheme.bodyMedium?.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSourceSection(BuildContext context) {
    if (widget.sourceOptions.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle(context, t.bookshelf.source),
          const SizedBox(height: 10),
          _buildNoSourceHint(context),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _buildSectionTitle(context, t.bookshelf.source),
            const SizedBox(width: 8),
            _buildSourceCountCapsule(context),
            const Spacer(),
            _buildSelectAllButton(context),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final source in widget.sourceOptions)
              _buildSourceChip(
                context,
                source: source,
                selected: _selectedSources.contains(source.pluginId),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildNoSourceHint(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        t.bookshelf.noFilterSource,
        style: textTheme.bodySmall?.copyWith(
          fontSize: 13,
          color: colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _buildSourceCountCapsule(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isEmpty = _selectedSources.isEmpty;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isEmpty
            ? colorScheme.errorContainer
            : colorScheme.secondaryContainer.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '${_selectedSources.length}/${_availableSourceSet.length}',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: isEmpty
              ? colorScheme.onErrorContainer
              : colorScheme.onSecondaryContainer,
        ),
      ),
    );
  }

  Widget _buildSelectAllButton(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return TextButton(
      onPressed: _toggleSelectAll,
      style: TextButton.styleFrom(
        foregroundColor: colorScheme.primary,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      child: Text(
        _isAllSourcesSelected ? t.bookshelf.deselectAll : t.common.selectAll,
      ),
    );
  }

  Widget _buildSourceChip(
    BuildContext context, {
    required BookshelfFilterSourceOption source,
    required bool selected,
  }) {
    return _buildStyledChip(
      context,
      selected: selected,
      chip: FilterChip(
        showCheckmark: true,
        // 320px 窄屏下超长源名保持单行省略，不把芯片撑成畸形多行块。
        label: Text(source.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        selected: selected,
        onSelected: (value) => _toggleSource(source.pluginId, value),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  Widget _buildFooter(BuildContext context, {required bool isCompact}) {
    final colorScheme = Theme.of(context).colorScheme;
    final divider = Divider(
      height: 1,
      thickness: 1,
      color: colorScheme.outlineVariant.withValues(alpha: 0.4),
    );

    if (isCompact) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          divider,
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 44),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(t.common.cancel),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _canApply ? _apply : null,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 44),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(t.common.apply),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        divider,
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 18),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                style: TextButton.styleFrom(
                  minimumSize: const Size(88, 40),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(t.common.cancel),
              ),
              const SizedBox(width: 10),
              FilledButton(
                onPressed: _canApply ? _apply : null,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(88, 40),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(t.common.apply),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
