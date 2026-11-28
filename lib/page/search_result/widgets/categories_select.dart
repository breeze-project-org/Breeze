import 'package:material_ui/material_ui.dart';
import 'package:zephyr/type/pipe.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/ui/ui.dart';
import 'package:zephyr/util/text/chinese_convert.dart';

/// 分类多选弹窗：高密度复选行 + 全选/全不选 + 已选计数。
Future<Map<String, bool>?> showCategoryDialog(
  BuildContext context,
  Map<String, bool> initialMap,
) {
  final Map<String, bool> tempMap = Map<String, bool>.from(initialMap);

  return showCalmDialog<Map<String, bool>>(
    context,
    title: t.search.selectCategory,
    icon: Icons.category_rounded,
    bodyBuilder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        final c = ctx.calm;
        final entries = tempMap.entries.toList();
        final selectedCount = tempMap.values.where((value) => value).length;
        final allSelected =
            tempMap.isNotEmpty && selectedCount == tempMap.length;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '$selectedCount / ${tempMap.length}',
                    textHeightBehavior: kCalmTextHeightBehavior,
                    strutStyle: calmStrut(11.5),
                    style: TextStyle(
                      fontSize: 11.5,
                      color: c.text3,
                      height: 1.2,
                      leadingDistribution: TextLeadingDistribution.even,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                CalmButton(
                  label: allSelected ? t.common.deselect : t.common.selectAll,
                  size: CalmButtonSize.xs,
                  variant: CalmButtonVariant.ghost,
                  onPressed: () {
                    setState(() {
                      for (final entry in entries) {
                        tempMap[entry.key] = !allSelected;
                      }
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 340),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: entries.length,
                separatorBuilder: (_, _) => const SizedBox(height: 2),
                itemBuilder: (_, index) {
                  final entry = entries[index];
                  return CalmCheckboxTile(
                    label: entry.key.let(convertChineseForDisplay),
                    value: tempMap[entry.key] ?? false,
                    onChanged: (next) {
                      setState(() {
                        tempMap[entry.key] = next;
                      });
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    ),
    actionsBuilder: (ctx) => [
      CalmButton(
        label: t.common.cancel,
        variant: CalmButtonVariant.ghost,
        onPressed: () => Navigator.of(ctx).pop(),
      ),
      CalmButton(
        label: t.common.ok,
        variant: CalmButtonVariant.primary,
        onPressed: () => Navigator.of(ctx).pop(tempMap),
      ),
    ],
  );
}
