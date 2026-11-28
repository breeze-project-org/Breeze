import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/bookshelf/models/shelf_page_mode.dart';
import 'package:zephyr/ui/ui.dart';

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

/// 打开书架筛选弹窗（CalmUI 版）：手机底部抽屉、平板与桌面居中卡片。
/// 取消/关闭返回 null，应用返回用户确认的草稿。
///
/// 形态在打开瞬间由 [showCalmDialog] 决定并与宿主路由绑定：窗口跨过 600px
/// 断点缩放或折叠屏展开收起时，不会出现底抽屉里套 Dialog、或 Dialog 里冒出
/// 拖拽条。
Future<BookshelfFilterResult?> showBookshelfFilterSheet(
  BuildContext context, {
  required ShelfPageMode mode,
  required String initialSort,
  required Set<String> initialSources,
  required List<String> availableSources,
  required List<BookshelfFilterSourceOption> sourceOptions,
  required bool initialHideFolders,
}) {
  // availableSources 为空表示调用方不做限制，退回可勾选列表，
  // 保证计数分母与可勾选项数量始终一致。
  final availableSourceSet = availableSources.isEmpty
      ? sourceOptions.map((option) => option.pluginId).toSet()
      : availableSources.toSet();

  // 草稿放在 ValueNotifier 里：正文与底部「重置 / 应用」分处两棵子树，
  // 只有共享同一个可监听草稿，禁用态与计数才能随勾选即时刷新。
  final draft = ValueNotifier<_FilterDraft>(
    _FilterDraft(
      sort: initialSort,
      // 与有效源取交集：外部传入的已禁用/已卸载 ID 不能参与计数与返回值。
      sources: initialSources.where(availableSourceSet.contains).toSet(),
      hideFolders: initialHideFolders,
      availableSources: availableSourceSet,
      // 历史没有文件夹体系，也没有按观看时间排序。
      supportsFolders: mode != ShelfPageMode.history,
    ),
  );

  return showCalmDialog<BookshelfFilterResult>(
    context,
    title: t.bookshelf.filter,
    icon: Icons.tune_rounded,
    maxWidth: 460,
    bodyBuilder: (dialogContext) =>
        _BookshelfFilterBody(draft: draft, sourceOptions: sourceOptions),
    actionsBuilder: (dialogContext) => [
      ValueListenableBuilder<_FilterDraft>(
        valueListenable: draft,
        builder: (context, value, _) => CalmButton(
          label: t.common.reset,
          variant: CalmButtonVariant.ghost,
          onPressed: value.isDirtyFromDefault
              ? () {
                  HapticFeedback.selectionClick();
                  draft.value = value.resetToDefault();
                }
              : null,
        ),
      ),
      CalmButton(
        label: t.common.cancel,
        variant: CalmButtonVariant.ghost,
        onPressed: () => Navigator.of(dialogContext).pop(),
      ),
      ValueListenableBuilder<_FilterDraft>(
        valueListenable: draft,
        builder: (context, value, _) => CalmButton(
          label: t.common.apply,
          variant: CalmButtonVariant.primary,
          onPressed: value.canApply
              ? () => Navigator.of(dialogContext).pop(value.toResult())
              : null,
        ),
      ),
    ],
  ).whenComplete(draft.dispose);
}

/// 筛选草稿：不可变，任何改动都换成新实例，便于 ValueListenableBuilder 重建。
class _FilterDraft {
  _FilterDraft({
    required this.sort,
    required Set<String> sources,
    required this.hideFolders,
    required this.availableSources,
    required this.supportsFolders,
  }) : sources = Set<String>.from(sources);

  static const String defaultSort = 'dd';

  final String sort;
  final Set<String> sources;
  final bool hideFolders;
  final Set<String> availableSources;
  final bool supportsFolders;

  bool get canApply => availableSources.isEmpty || sources.isNotEmpty;

  bool get isAllSourcesSelected =>
      availableSources.isNotEmpty && _hasSameSources(sources, availableSources);

  bool get isDirtyFromDefault =>
      sort != defaultSort ||
      (supportsFolders && hideFolders) ||
      (availableSources.isNotEmpty &&
          !_hasSameSources(sources, availableSources));

  _FilterDraft copyWith({
    String? sort,
    Set<String>? sources,
    bool? hideFolders,
  }) {
    return _FilterDraft(
      sort: sort ?? this.sort,
      sources: sources ?? this.sources,
      hideFolders: hideFolders ?? this.hideFolders,
      availableSources: availableSources,
      supportsFolders: supportsFolders,
    );
  }

  _FilterDraft resetToDefault() => copyWith(
    sort: defaultSort,
    hideFolders: false,
    sources: availableSources,
  );

  BookshelfFilterResult toResult() => BookshelfFilterResult(
    sort: sort,
    sources: sources,
    hideFolders: hideFolders,
  );

  static bool _hasSameSources(Set<String> current, Set<String> target) {
    return current.length == target.length && current.containsAll(target);
  }
}

class _BookshelfFilterBody extends StatelessWidget {
  const _BookshelfFilterBody({
    required this.draft,
    required this.sourceOptions,
  });

  final ValueNotifier<_FilterDraft> draft;
  final List<BookshelfFilterSourceOption> sourceOptions;

  void _selectSort(String sort) {
    HapticFeedback.selectionClick();
    draft.value = draft.value.copyWith(sort: sort);
  }

  void _setHideFolders(bool value) {
    HapticFeedback.selectionClick();
    draft.value = draft.value.copyWith(hideFolders: value);
  }

  void _toggleAllSources() {
    HapticFeedback.selectionClick();
    final current = draft.value;
    draft.value = current.isAllSourcesSelected
        ? current.copyWith(sources: <String>{})
        : current.copyWith(sources: current.availableSources);
  }

  void _toggleSource(String pluginId, bool selected) {
    HapticFeedback.selectionClick();
    final current = draft.value;
    final next = Set<String>.from(current.sources);
    if (selected) {
      next.add(pluginId);
    } else {
      next.remove(pluginId);
    }
    draft.value = current.copyWith(sources: next);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<_FilterDraft>(
      valueListenable: draft,
      builder: (context, value, _) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CalmSectionHeader(title: t.bookshelf.sort),
            const SizedBox(height: 8),
            _buildSortOptions(context, value),
            if (value.supportsFolders) ...[
              const SizedBox(height: 18),
              CalmSectionHeader(title: t.bookshelf.display),
              const SizedBox(height: 8),
              _buildHideFolders(context, value),
            ],
            const SizedBox(height: 18),
            _buildSourceSection(context, value),
          ],
        );
      },
    );
  }

  Widget _buildSortOptions(BuildContext context, _FilterDraft value) {
    final options = <(String, String)>[
      ('dd', t.bookshelf.sortDesc),
      ('da', t.bookshelf.sortAsc),
      if (value.supportsFolders) ...[
        ('vd', t.bookshelf.viewSortDesc),
        ('va', t.bookshelf.viewSortAsc),
      ],
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (sort, label) in options)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: CalmRadioTile<String>(
              label: label,
              value: sort,
              groupValue: value.sort,
              onChanged: _selectSort,
            ),
          ),
      ],
    );
  }

  Widget _buildHideFolders(BuildContext context, _FilterDraft value) {
    final c = context.calm;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              t.bookshelf.hideFolders,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textHeightBehavior: kCalmTextHeightBehavior,
              strutStyle: calmStrut(12.5),
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: c.text,
                height: 1.2,
                leadingDistribution: TextLeadingDistribution.even,
              ),
            ),
          ),
          const SizedBox(width: 10),
          CalmSwitch(value: value.hideFolders, onChanged: _setHideFolders),
        ],
      ),
    );
  }

  Widget _buildSourceSection(BuildContext context, _FilterDraft value) {
    if (sourceOptions.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CalmSectionHeader(title: t.bookshelf.source),
          const SizedBox(height: 8),
          // 没有可筛选图源时用柔和提示条替代空列表，应用按钮仍然可用。
          CalmStatusBanner(title: t.bookshelf.noFilterSource),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CalmSectionHeader(
          title: t.bookshelf.source,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CalmBadge(
                label:
                    '${value.sources.length}/${value.availableSources.length}',
                tone: value.sources.isEmpty
                    ? CalmBadgeTone.danger
                    : CalmBadgeTone.tonal,
              ),
              const SizedBox(width: 6),
              CalmButton(
                label: value.isAllSourcesSelected
                    ? t.bookshelf.deselectAll
                    : t.common.selectAll,
                variant: CalmButtonVariant.ghost,
                size: CalmButtonSize.xs,
                onPressed: _toggleAllSources,
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final source in sourceOptions)
              CalmFilterChip(
                label: source.title,
                selected: value.sources.contains(source.pluginId),
                onSelected: (selected) =>
                    _toggleSource(source.pluginId, selected),
              ),
          ],
        ),
      ],
    );
  }
}
