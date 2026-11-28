import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/color_theme_types.dart';
import 'package:zephyr/ui/ui.dart';

/// 单个预设色块：柔和圆角色卡 + 选中描边与勾选角标（全部走 context.calm）。
class ColorThemeItem extends StatelessWidget {
  const ColorThemeItem({
    super.key,
    required this.colorInfo,
    required this.currentColor,
    required this.onColorSelected,
    this.swatchSize = 46,
    this.itemWidth = 72,
  });

  final ColorThemeInfo colorInfo;
  final Color currentColor;
  final ValueChanged<Color> onColorSelected;
  final double swatchSize;

  /// 定宽而不是用 `screenWidth / 4 - 30`，窄屏与多列换行都不会溢出。
  final double itemWidth;

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    final selected = currentColor.toARGB32() == colorInfo.color.toARGB32();

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => onColorSelected(colorInfo.color),
        child: SizedBox(
          width: itemWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                width: swatchSize,
                height: swatchSize,
                decoration: BoxDecoration(
                  color: colorInfo.color,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: selected ? c.accent : c.border,
                    width: selected ? 2.4 : 1,
                  ),
                  boxShadow: selected ? c.shadowSm : null,
                ),
                child: selected
                    ? Align(
                        alignment: Alignment.bottomRight,
                        child: Container(
                          width: 17,
                          height: 17,
                          decoration: BoxDecoration(
                            color: c.accent,
                            shape: BoxShape.circle,
                            border: Border.all(color: c.surface, width: 1.6),
                          ),
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.check_rounded,
                            size: 10,
                            color: c.accentFg,
                          ),
                        ),
                      )
                    : null,
              ),
              const SizedBox(height: 6),
              Text(
                colorInfo.localizedLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                textHeightBehavior: kCalmTextHeightBehavior,
                strutStyle: calmStrut(11),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected ? c.accent : c.text2,
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
