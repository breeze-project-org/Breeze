import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/ui/ui.dart';

/// 搜索语法速查弹窗：三张语气色标签卡 + 示例胶囊。
void showSearchHelp(BuildContext context) {
  showCalmDialog<void>(
    context,
    title: t.search.tipsTitle,
    icon: Icons.tips_and_updates_rounded,
    bodyBuilder: (_) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildTipCard(
          context,
          title: t.search.exactSearchTitle,
          example: t.search.exactSearchExample,
          desc: t.search.exactSearchDesc,
          icon: Icons.filter_alt_rounded,
          tone: CalmTone.info,
        ),
        const SizedBox(height: 8),
        _buildTipCard(
          context,
          title: t.search.excludeSearchTitle,
          example: t.search.excludeSearchExample,
          desc: t.search.excludeSearchDesc,
          icon: Icons.remove_circle_outline_rounded,
          tone: CalmTone.danger,
        ),
        const SizedBox(height: 8),
        _buildTipCard(
          context,
          title: t.search.fuzzySearchTitle,
          example: t.search.fuzzySearchExample,
          desc: t.search.fuzzySearchDesc,
          icon: Icons.blur_on_rounded,
          tone: CalmTone.success,
        ),
      ],
    ),
  );
}

Widget _buildTipCard(
  BuildContext context, {
  required String title,
  required String example,
  required String desc,
  required IconData icon,
  required CalmTone tone,
}) {
  final c = context.calm;
  final (bg, fg) = switch (tone) {
    CalmTone.info => (c.accentSoft, c.accent),
    CalmTone.success => (c.successSoft, c.success),
    CalmTone.warning => (c.warningSoft, c.warning),
    CalmTone.danger => (c.dangerSoft, c.danger),
  };

  return Container(
    padding: const EdgeInsets.all(11),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(13),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(icon, size: 15, color: fg),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: fg,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            example,
            textHeightBehavior: kCalmTextHeightBehavior,
            strutStyle: calmStrut(11.5),
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
              color: c.text,
              height: 1.2,
              leadingDistribution: TextLeadingDistribution.even,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          desc,
          style: TextStyle(fontSize: 11.5, color: c.text2, height: 1.45),
        ),
      ],
    ),
  );
}
