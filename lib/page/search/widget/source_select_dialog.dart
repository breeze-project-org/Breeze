import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/ui/ui.dart';

Future<Map<String, bool>?> showSourceSelectDialog(
  BuildContext context, {
  required Map<String, bool> initial,
  required List<({String pluginId, String title})> sourceOptions,
}) {
  final next = Map<String, bool>.from(initial);
  return showCalmDialog<Map<String, bool>>(
    context,
    title: t.search.selectSource,
    subtitle: t.search.selectSourceTooltip,
    icon: Icons.source_rounded,
    bodyBuilder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        final c = ctx.calm;
        final selectedCount = sourceOptions
            .where((source) => next[source.pluginId] ?? true)
            .length;
        final allSelected =
            sourceOptions.isNotEmpty && selectedCount == sourceOptions.length;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '$selectedCount / ${sourceOptions.length}',
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
                      for (final source in sourceOptions) {
                        next[source.pluginId] = !allSelected;
                      }
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.start,
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final source in sourceOptions)
                  CalmFilterChip(
                    label: source.title,
                    selected: next[source.pluginId] ?? true,
                    onSelected: (selected) {
                      setState(() {
                        next[source.pluginId] = selected;
                      });
                    },
                  ),
              ],
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
        label: t.common.apply,
        variant: CalmButtonVariant.primary,
        onPressed: () => Navigator.of(ctx).pop(next),
      ),
    ],
  );
}
