import 'package:material_ui/material_ui.dart';
import 'package:zephyr/ui/components/calm_chips.dart';
import 'package:zephyr/ui/theme/calm_theme.dart';

/// 五端统一导航项模型（手机底栏 / 平板 Rail / 桌面侧栏共用）。
class CalmNavItem {
  const CalmNavItem({
    required this.label,
    required this.icon,
    this.activeIcon,
    this.badgeCount,
    this.shortcut,
  });

  final String label;
  final IconData icon;
  final IconData? activeIcon;
  final int? badgeCount;
  final String? shortcut;
}

/// 手机端轻盈底部导航栏（胶囊选中高亮 + 右上角微徽章）。
class CalmBottomNavBar extends StatelessWidget {
  const CalmBottomNavBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onChanged,
    this.borderRadius,
  });

  final List<CalmNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onChanged;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 8),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: borderRadius,
        border: borderRadius != null
            ? Border.all(color: c.border)
            : Border(top: BorderSide(color: c.border)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++)
            Expanded(
              child: _BottomNavCell(
                item: items[i],
                active: i == currentIndex,
                onTap: () => onChanged(i),
              ),
            ),
        ],
      ),
    );
  }
}

class _BottomNavCell extends StatelessWidget {
  const _BottomNavCell({
    required this.item,
    required this.active,
    required this.onTap,
  });

  final CalmNavItem item;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    final badge = item.badgeCount;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: 46,
                  height: 26,
                  decoration: BoxDecoration(
                    color: active ? c.accentSoft : Colors.transparent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    active ? (item.activeIcon ?? item.icon) : item.icon,
                    size: 18,
                    color: active ? c.accent : c.text3,
                  ),
                ),
                if (badge != null && badge > 0)
                  Positioned(
                    right: -2,
                    top: -3,
                    child: Container(
                      height: 15,
                      constraints: const BoxConstraints(minWidth: 15),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: c.accent,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        badge > 99 ? '99+' : '$badge',
                        textHeightBehavior: kCalmTextHeightBehavior,
                        strutStyle: calmStrut(9),
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: c.accentFg,
                          height: 1.2,
                          leadingDistribution: TextLeadingDistribution.even,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              item.label,
              textHeightBehavior: kCalmTextHeightBehavior,
              strutStyle: calmStrut(10),
              style: TextStyle(
                fontSize: 10,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                color: active ? c.accent : c.text3,
                height: 1.2,
                leadingDistribution: TextLeadingDistribution.even,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 平板端轻盈左侧导航轨（64px 宽）。
///
/// [fullHeight] 为 true 时铺满宿主管高、只留右侧 1px 分割线（应用侧边栏）；
/// 默认仍是浮空胶囊卡片，供独立预览与弹窗内嵌使用。
class CalmNavRail extends StatelessWidget {
  const CalmNavRail({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onChanged,
    this.fullHeight = false,
    this.footer,
    this.borderRadius,
  });

  final List<CalmNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onChanged;

  /// 铺满可用高度（占满左侧一列），而不是内容自适应的浮空卡片。
  final bool fullHeight;

  /// 固定在底部的内容（如搜索按钮）。
  final Widget? footer;

  /// 自定义圆角；为 null 时浮动模式为 16，铺满模式为直角。
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    final radius =
        borderRadius ?? (fullHeight ? null : BorderRadius.circular(16));
    final cells = <Widget>[
      for (var i = 0; i < items.length; i++) ...[
        if (i > 0) const SizedBox(height: 6),
        _BottomNavCell(
          item: items[i],
          active: i == currentIndex,
          onTap: () => onChanged(i),
        ),
      ],
    ];
    return Container(
      width: 64,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: radius,
        border: fullHeight && radius == null
            ? Border(right: BorderSide(color: c.border))
            : Border.all(color: c.border),
      ),
      child: Column(
        mainAxisSize: fullHeight ? MainAxisSize.max : MainAxisSize.min,
        children: [
          // 铺满模式：窗口很矮时导航项自身可滚动，底部的 footer 始终可见。
          if (fullHeight)
            Expanded(
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: cells),
              ),
            )
          else
            ...cells,
          if (footer != null) ...[const SizedBox(height: 6), footer!],
        ],
      ),
    );
  }
}

/// 桌面端侧边栏导航项（带徽章或快捷键提示）。
class CalmSidebarItem extends StatefulWidget {
  const CalmSidebarItem({
    super.key,
    required this.item,
    required this.active,
    required this.onTap,
  });

  final CalmNavItem item;
  final bool active;
  final VoidCallback onTap;

  @override
  State<CalmSidebarItem> createState() => _CalmSidebarItemState();
}

class _CalmSidebarItemState extends State<CalmSidebarItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    final badge = widget.item.badgeCount;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 11),
          decoration: BoxDecoration(
            color: widget.active
                ? c.accentSoft
                : _hovered
                ? c.surface2
                : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                widget.active
                    ? (widget.item.activeIcon ?? widget.item.icon)
                    : widget.item.icon,
                size: 16.5,
                color: widget.active ? c.accent : c.text2,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textHeightBehavior: kCalmTextHeightBehavior,
                  strutStyle: calmStrut(12.5),
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: widget.active
                        ? FontWeight.w600
                        : FontWeight.w400,
                    color: widget.active ? c.accent : c.text,
                    height: 1.2,
                    leadingDistribution: TextLeadingDistribution.even,
                  ),
                ),
              ),
              if (badge != null && badge > 0)
                CalmBadge(
                  label: badge > 99 ? '99+' : '$badge',
                  tone: widget.active
                      ? CalmBadgeTone.accent
                      : CalmBadgeTone.tonal,
                )
              else if (widget.item.shortcut != null)
                Text(
                  widget.item.shortcut!,
                  style: TextStyle(fontSize: 10.5, color: c.text3),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 下划线轻盈标签栏（用于浏览页「图源 / 扩展 / 迁移」等二级分栏）。
class CalmUnderlineTabs<T> extends StatelessWidget {
  const CalmUnderlineTabs({
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
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(width: 18),
            _UnderlineTabCell(
              label: items[i].label,
              count: items[i].count,
              active: items[i].value == value,
              onTap: () => onChanged(items[i].value),
            ),
          ],
        ],
      ),
    );
  }
}

class _UnderlineTabCell extends StatelessWidget {
  const _UnderlineTabCell({
    required this.label,
    required this.count,
    required this.active,
    required this.onTap,
  });

  final String label;
  final int? count;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 8),
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: label,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                        color: active ? c.accent : c.text2,
                        height: 1.2,
                        leadingDistribution: TextLeadingDistribution.even,
                      ),
                    ),
                    if (count != null)
                      TextSpan(
                        text: '  $count',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: (active ? c.accent : c.text3).withValues(
                            alpha: 0.85,
                          ),
                          height: 1.2,
                          leadingDistribution: TextLeadingDistribution.even,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                  ],
                ),
                textHeightBehavior: kCalmTextHeightBehavior,
                strutStyle: calmStrut(12.5),
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              height: 2.5,
              width: active ? 24 : 0,
              decoration: BoxDecoration(
                color: c.accent,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 轻盈面包屑路径（适用于文件夹层级、图源钻取）。
class CalmBreadcrumb extends StatelessWidget {
  const CalmBreadcrumb({super.key, required this.segments, this.onTapSegment});

  final List<String> segments;
  final ValueChanged<int>? onTapSegment;

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 4,
      runSpacing: 4,
      children: [
        for (var i = 0; i < segments.length; i++) ...[
          if (i > 0)
            Icon(Icons.chevron_right_rounded, size: 14, color: c.text3),
          MouseRegion(
            cursor: i < segments.length - 1 && onTapSegment != null
                ? SystemMouseCursors.click
                : SystemMouseCursors.basic,
            child: GestureDetector(
              onTap: i < segments.length - 1
                  ? () => onTapSegment?.call(i)
                  : null,
              child: Text(
                segments[i],
                textHeightBehavior: kCalmTextHeightBehavior,
                strutStyle: calmStrut(12),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: i == segments.length - 1
                      ? FontWeight.w600
                      : FontWeight.w400,
                  color: i == segments.length - 1 ? c.text : c.text3,
                  height: 1.2,
                  leadingDistribution: TextLeadingDistribution.even,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
