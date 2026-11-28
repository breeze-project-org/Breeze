import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/comic_list/scene_filter/plugin_choice_dropdown.dart';
import 'package:zephyr/page/comic_list/scene_filter/plugin_list_filter_schema.dart';
import 'package:zephyr/ui/ui.dart';

/// 插件列表筛选面板（CalmUI）。
///
/// 保持公开构造签名不变，外部仍可直接 `showDialog(builder: (_) =>
/// PluginListFilterDialog(...))`。内部改为透明 [Dialog] + [CalmDialogSurface]：
/// 手机贴底滑出（带抓手）、平板与桌面居中卡片，与 [showCalmDialog] 视觉一致。
class PluginListFilterDialog extends StatefulWidget {
  const PluginListFilterDialog({
    super.key,
    required this.scheme,
    required this.initialSelections,
  });

  final PluginListFilterSchema scheme;
  final Map<String, String> initialSelections;

  @override
  State<PluginListFilterDialog> createState() => _PluginListFilterDialogState();
}

class _PluginListFilterDialogState extends State<PluginListFilterDialog> {
  late final Map<String, String> _selections;

  @override
  void initState() {
    super.initState();
    _selections = Map<String, String>.from(widget.initialSelections);
  }

  int get _activeCount =>
      _selections.values.where((value) => value.trim().isNotEmpty).length;

  @override
  Widget build(BuildContext context) {
    final isPhone = MediaQuery.sizeOf(context).width < 600;
    final title = widget.scheme.title.isNotEmpty
        ? widget.scheme.title
        : t.comicList.filter;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      alignment: isPhone ? Alignment.bottomCenter : Alignment.center,
      insetPadding: isPhone ? EdgeInsets.zero : const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: CalmDialogSurface(
          title: title,
          icon: Icons.tune_rounded,
          badge: _activeCount > 0 ? '$_activeCount' : null,
          isBottomSheet: isPhone,
          onClose: () => Navigator.of(context).pop(),
          body: _buildBody(context),
          actions: [
            CalmButton(
              label: t.common.cancel,
              variant: CalmButtonVariant.ghost,
              onPressed: () => Navigator.of(context).pop(),
            ),
            CalmButton(
              label: t.common.ok,
              variant: CalmButtonVariant.primary,
              onPressed: () =>
                  Navigator.of(context)
                      .pop(Map<String, String>.from(_selections)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (widget.scheme.fields.isEmpty) {
      return CalmEmptyState(
        icon: Icons.filter_alt_off_rounded,
        title: t.comicList.filter,
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final field in widget.scheme.fields) _buildField(context, field),
      ],
    );
  }

  Widget _buildField(BuildContext context, PluginChoiceField field) {
    final selectedPath =
        field.findPathByValue(_selections[field.key]) ?? const [];
    final visibleLevelOptionSets = field.buildVisibleLevels(
      _selections[field.key],
    );

    if (field.isDropdownField) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(
          // 不能 stretch：FluentDropdown 以自身宽度作为菜单最小宽度，
          // 被拉满整行时会让菜单宽度超过上限。
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (field.label.isNotEmpty) ...[
              _FieldLabel(label: field.label),
              const SizedBox(height: 6),
            ],
            PluginChoiceDropdown(
              field: field,
              selectedValue: _selections[field.key] ?? '',
              onSelected: (value) {
                setState(() {
                  _selections[field.key] = value;
                });
              },
            ),
          ],
        ),
      );
    }

    if (visibleLevelOptionSets.length == 1 &&
        visibleLevelOptionSets.first.options.length <= 1) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (field.label.isNotEmpty) ...[
            _FieldLabel(label: field.label),
            const SizedBox(height: 8),
          ],
          ...visibleLevelOptionSets.asMap().entries.map((entry) {
            final level = entry.key;
            final filterLevel = entry.value;
            final levelOptions = filterLevel.options;
            final selectedValue = selectedPath.length > filterLevel.pathIndex
                ? selectedPath[filterLevel.pathIndex].value
                : '';
            final levelLabel = level == 0
                ? null
                : level == 1
                ? t.comicList.subCategory
                : t.comicList.levelCategory(level: level + 1);

            return Padding(
              padding: EdgeInsets.only(
                bottom: level == visibleLevelOptionSets.length - 1 ? 0 : 12,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (levelLabel != null) ...[
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        levelLabel,
                        style: TextStyle(
                          fontSize: 10.5,
                          height: 1.2,
                          color: context.calm.text3,
                        ),
                      ),
                    ),
                  ],
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: levelOptions.map((option) {
                      final value = option.value;
                      final optionLabel = option.label.isNotEmpty
                          ? option.label
                          : value;
                      return CalmFilterChip(
                        label: optionLabel,
                        selected: selectedValue == value,
                        onSelected: (_) {
                          setState(() {
                            _selections[field.key] = value;
                          });
                        },
                      );
                    }).toList(),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

/// 分组小标题：左侧 3px 主色竖条 + 文案，和 CalmSectionHeader 同一套语汇。
class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 3,
          height: 12,
          decoration: BoxDecoration(
            color: c.accent,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textHeightBehavior: kCalmTextHeightBehavior,
            strutStyle: calmStrut(12),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: c.text2,
              height: 1.2,
              leadingDistribution: TextLeadingDistribution.even,
            ),
          ),
        ),
      ],
    );
  }
}
