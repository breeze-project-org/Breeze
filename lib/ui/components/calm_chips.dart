import 'package:material_ui/material_ui.dart';
import 'package:zephyr/ui/theme/calm_theme.dart';

enum CalmBadgeTone { accent, tonal, neutral, success, warning, danger }

/// 严格垂直居中的胶囊徽章（支持等宽数字与可选前缀图标）。
class CalmBadge extends StatelessWidget {
  const CalmBadge({
    super.key,
    required this.label,
    this.tone = CalmBadgeTone.tonal,
    this.icon,
    this.dot = false,
  });

  final String label;
  final CalmBadgeTone tone;
  final IconData? icon;
  final bool dot;

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    final (bg, fg) = switch (tone) {
      CalmBadgeTone.accent => (c.accent, c.accentFg),
      CalmBadgeTone.tonal => (c.accentSoft, c.accent),
      CalmBadgeTone.neutral => (c.surface2, c.text2),
      CalmBadgeTone.success => (c.successSoft, c.success),
      CalmBadgeTone.warning => (c.warningSoft, c.warning),
      CalmBadgeTone.danger => (c.dangerSoft, c.danger),
    };

    return Container(
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (dot) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
          ],
          if (icon != null) ...[
            Icon(icon, size: 11.5, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            textHeightBehavior: kCalmTextHeightBehavior,
            strutStyle: calmStrut(10.5),
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: fg,
              height: 1.2,
              leadingDistribution: TextLeadingDistribution.even,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// 可多选胶囊筛选芯片。
class CalmFilterChip extends StatelessWidget {
  const CalmFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final ValueChanged<bool> onSelected;

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => onSelected(!selected),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 11),
          decoration: BoxDecoration(
            color: selected ? c.accentSoft : c.surface2,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (selected) ...[
                Icon(Icons.check_rounded, size: 13, color: c.accent),
                const SizedBox(width: 4),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textHeightBehavior: kCalmTextHeightBehavior,
                  strutStyle: calmStrut(11.5),
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: selected ? c.accent : c.text2,
                    height: 1.2,
                    leadingDistribution: TextLeadingDistribution.even,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 可移除标签芯片（用于搜索历史、屏蔽词、已激活条件展示）。
class CalmInputChip extends StatelessWidget {
  const CalmInputChip({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.onDeleted,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final VoidCallback? onDeleted;

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    return MouseRegion(
      cursor: onTap != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 28,
          padding: EdgeInsets.only(left: 10, right: onDeleted != null ? 6 : 10),
          decoration: BoxDecoration(
            color: c.surface2,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 12.5, color: c.text3),
                const SizedBox(width: 5),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textHeightBehavior: kCalmTextHeightBehavior,
                  strutStyle: calmStrut(11.5),
                  style: TextStyle(
                    fontSize: 11.5,
                    color: c.text,
                    height: 1.2,
                    leadingDistribution: TextLeadingDistribution.even,
                  ),
                ),
              ),
              if (onDeleted != null) ...[
                const SizedBox(width: 4),
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: onDeleted,
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: c.surface.withValues(alpha: 0.75),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.close_rounded,
                        size: 11,
                        color: c.text2,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 轻盈胶囊分段控件（Segmented Control）。
class CalmSegmentedControl<T> extends StatelessWidget {
  const CalmSegmentedControl({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  final List<({T value, String label, IconData? icon})> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final opt in options)
            _SegmentItem(
              label: opt.label,
              icon: opt.icon,
              active: opt.value == value,
              onTap: () => onChanged(opt.value),
            ),
        ],
      ),
    );
  }
}

class _SegmentItem extends StatelessWidget {
  const _SegmentItem({
    required this.label,
    required this.active,
    required this.onTap,
    this.icon,
  });

  final String label;
  final IconData? icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: active ? c.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            boxShadow: active ? c.shadowSm : const [],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 13.5, color: active ? c.accent : c.text2),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                textHeightBehavior: kCalmTextHeightBehavior,
                strutStyle: calmStrut(11.5),
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                  color: active ? c.text : c.text2,
                  height: 1.2,
                  leadingDistribution: TextLeadingDistribution.even,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 计数胶囊标签栏（Pill Tabs）。
class CalmPillTabs<T> extends StatelessWidget {
  const CalmPillTabs({
    super.key,
    required this.items,
    required this.value,
    required this.onChanged,
  });

  final List<({T value, String label, int? count})> items;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            _PillTabItem(
              label: items[i].label,
              count: items[i].count,
              active: items[i].value == value,
              onTap: () => onChanged(items[i].value),
              calm: c,
            ),
          ],
        ],
      ),
    );
  }
}

class _PillTabItem extends StatelessWidget {
  const _PillTabItem({
    required this.label,
    required this.count,
    required this.active,
    required this.onTap,
    required this.calm,
  });

  final String label;
  final int? count;
  final bool active;
  final VoidCallback onTap;
  final CalmColors calm;

  @override
  Widget build(BuildContext context) {
    final labelColor = active ? calm.accent : calm.text2;
    final countColor = (active ? calm.accent : calm.text3).withValues(
      alpha: 0.85,
    );
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? calm.accentSoft : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                    color: labelColor,
                    height: 1.2,
                    leadingDistribution: TextLeadingDistribution.even,
                  ),
                ),
                if (count != null)
                  TextSpan(
                    text: '  $count',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w500,
                      color: countColor,
                      height: 1.2,
                      leadingDistribution: TextLeadingDistribution.even,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
              ],
            ),
            textHeightBehavior: kCalmTextHeightBehavior,
            strutStyle: calmStrut(12),
          ),
        ),
      ),
    );
  }
}
