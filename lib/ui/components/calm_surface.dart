import 'package:material_ui/material_ui.dart';
import 'package:zephyr/ui/theme/calm_theme.dart';

/// 轻盈浮空卡片：大圆角 + 极轻弥散阴影，去厚重边框。
class CalmCard extends StatelessWidget {
  const CalmCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 18,
    this.color,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? c.surface,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: c.shadowSm,
      ),
      child: child,
    );
  }
}

/// 轻盈分组头：左侧 4×14 主色圆条 + 标题 + 计数 + 可选右侧「更多」胶囊。
class CalmSectionHeader extends StatelessWidget {
  const CalmSectionHeader({
    super.key,
    required this.title,
    this.countText,
    this.actionLabel,
    this.onActionTap,
    this.accentColor,
    this.trailing,
  });

  final String title;
  final String? countText;
  final String? actionLabel;
  final VoidCallback? onActionTap;
  final Color? accentColor;

  /// 右侧额外插槽（如点击进入的箭头）。
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 4,
          height: 15,
          decoration: BoxDecoration(
            color: accentColor ?? c.accent,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: c.text,
                  ),
                ),
              ),
              if (countText != null) ...[
                const SizedBox(width: 7),
                Text(
                  countText!,
                  style: TextStyle(
                    fontSize: 11,
                    color: c.text3,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ],
          ),
        ),
        if (actionLabel != null && onActionTap != null)
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: onActionTap,
              child: Container(
                height: 24,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: c.shadowSm,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      actionLabel!,
                      textHeightBehavior: kCalmTextHeightBehavior,
                      strutStyle: calmStrut(11),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: c.text2,
                        height: 1.2,
                        leadingDistribution: TextLeadingDistribution.even,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(Icons.chevron_right_rounded, size: 14, color: c.text3),
                  ],
                ),
              ),
            ),
          ),
        if (trailing != null) ...[const SizedBox(width: 6), trailing!],
      ],
    );
  }
}

/// 高密度通用列表行（支持全局紧凑/舒适密度自适应）。
class CalmListTile extends StatefulWidget {
  const CalmListTile({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.borderRadius = 12,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final double borderRadius;

  @override
  State<CalmListTile> createState() => _CalmListTileState();
}

class _CalmListTileState extends State<CalmListTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    final clickable = widget.onTap != null;
    return MouseRegion(
      cursor: clickable ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: EdgeInsets.symmetric(
            horizontal: 12,
            vertical: c.rowVPadding,
          ),
          decoration: BoxDecoration(
            color: _hovered && clickable
                ? c.surface2.withValues(alpha: 0.7)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(widget.borderRadius),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (widget.leading != null) ...[
                widget.leading!,
                const SizedBox(width: 11),
              ],
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: c.text,
                        height: 1.3,
                      ),
                    ),
                    if (widget.subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        widget.subtitle!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: c.text3,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (widget.trailing != null) ...[
                const SizedBox(width: 10),
                widget.trailing!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 轻盈可折叠面板（Accordion）。
class CalmExpansionTile extends StatefulWidget {
  const CalmExpansionTile({
    super.key,
    required this.title,
    required this.child,
    this.initiallyExpanded = false,
  });

  final String title;
  final Widget child;
  final bool initiallyExpanded;

  @override
  State<CalmExpansionTile> createState() => _CalmExpansionTileState();
}

class _CalmExpansionTileState extends State<CalmExpansionTile> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CalmListTile(
          title: widget.title,
          onTap: () => setState(() => _expanded = !_expanded),
          trailing: AnimatedRotation(
            turns: _expanded ? 0.5 : 0,
            duration: const Duration(milliseconds: 180),
            child: Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 18,
              color: c.text3,
            ),
          ),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox(width: double.infinity, height: 0),
          secondChild: Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: c.bg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: widget.child,
          ),
          crossFadeState: _expanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 180),
        ),
      ],
    );
  }
}
