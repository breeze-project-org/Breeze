import 'package:material_ui/material_ui.dart';
import 'package:zephyr/ui/ui.dart';

/// 轻盈分组头：左侧主色圆条 + 标题 + 可选右侧提示/箭头。
///
/// 保持旧签名不变（`title` / `subtitle` / `onTap` / `margin`），
/// 整行可点击的行为沿用旧实现，视觉交给 [CalmSectionHeader]。
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle = '',
    this.onTap,
    this.margin = const EdgeInsets.all(5),
  });

  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    final canNavigate = onTap != null;
    final trimmedSubtitle = subtitle.trim();

    return Padding(
      padding: margin,
      child: MouseRegion(
        cursor: canNavigate
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: CalmSectionHeader(
            title: title,
            countText: trimmedSubtitle.isEmpty ? null : trimmedSubtitle,
            trailing: canNavigate
                ? Icon(Icons.chevron_right_rounded, size: 16, color: c.text3)
                : null,
          ),
        ),
      ),
    );
  }
}
