import 'package:material_ui/material_ui.dart';
import 'package:zephyr/ui/theme/calm_theme.dart';

/// 胶囊线性进度条（支持定长与不定长动画态、标签与等宽进度文本）。
class CalmProgressBar extends StatelessWidget {
  const CalmProgressBar({
    super.key,
    this.value,
    this.label,
    this.trailingText,
    this.height = 6,
    this.color,
  });

  /// null 表示不定长加载动画态；0.0 ~ 1.0 表示确定进度。
  final double? value;
  final String? label;
  final String? trailingText;
  final double height;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    final fill = color ?? c.accent;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (label != null || trailingText != null) ...[
          Row(
            children: [
              if (label != null)
                Expanded(
                  child: Text(
                    label!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: c.text2,
                    ),
                  ),
                ),
              if (trailingText != null)
                Text(
                  trailingText!,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: fill,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
        ],
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: SizedBox(
            height: height,
            child: value == null
                ? LinearProgressIndicator(
                    backgroundColor: c.surface2,
                    valueColor: AlwaysStoppedAnimation<Color>(fill),
                  )
                : LayoutBuilder(
                    builder: (_, constraints) {
                      final clamped = value!.clamp(0.0, 1.0);
                      return Stack(
                        children: [
                          Container(color: c.surface2),
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOutCubic,
                            width: constraints.maxWidth * clamped,
                            decoration: BoxDecoration(
                              color: fill,
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}

/// 轻盈圆形头像（支持首字/图标兜底、柔和描边环与右下角徽章）。
class CalmAvatar extends StatelessWidget {
  const CalmAvatar({
    super.key,
    this.text,
    this.icon,
    this.size = 40,
    this.badge,
    this.backgroundColor,
    this.foregroundColor,
  });

  final String? text;
  final IconData? icon;
  final double size;
  final String? badge;
  final Color? backgroundColor;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    final bg = backgroundColor ?? c.accentSoft;
    final fg = foregroundColor ?? c.accent;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: bg,
            shape: BoxShape.circle,
            border: Border.all(color: c.accentBorder, width: 1.5),
          ),
          alignment: Alignment.center,
          child: text != null && text!.isNotEmpty
              ? Text(
                  text!.characters.first,
                  textHeightBehavior: kCalmTextHeightBehavior,
                  strutStyle: calmStrut(size * 0.4),
                  style: TextStyle(
                    fontSize: size * 0.4,
                    fontWeight: FontWeight.w700,
                    color: fg,
                    height: 1.2,
                    leadingDistribution: TextLeadingDistribution.even,
                  ),
                )
              : Icon(
                  icon ?? Icons.person_rounded,
                  size: size * 0.48,
                  color: fg,
                ),
        ),
        if (badge != null && badge!.isNotEmpty)
          Positioned(
            right: -3,
            bottom: -2,
            child: Container(
              height: 16,
              padding: const EdgeInsets.symmetric(horizontal: 5),
              decoration: BoxDecoration(
                color: c.accent,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: c.surface, width: 1.5),
              ),
              alignment: Alignment.center,
              child: Text(
                badge!,
                textHeightBehavior: kCalmTextHeightBehavior,
                strutStyle: calmStrut(8.5),
                style: TextStyle(
                  fontSize: 8.5,
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
    );
  }
}

/// 柔和细分割线（支持居中提示文字）。
class CalmDivider extends StatelessWidget {
  const CalmDivider({super.key, this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    if (label == null || label!.isEmpty) {
      return Divider(height: 1, color: c.border);
    }
    return Row(
      children: [
        Expanded(child: Divider(height: 1, color: c.borderStrong)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(label!, style: TextStyle(fontSize: 11, color: c.text3)),
        ),
        Expanded(child: Divider(height: 1, color: c.borderStrong)),
      ],
    );
  }
}
