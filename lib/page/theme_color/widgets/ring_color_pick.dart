import 'package:material_ui/material_ui.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

/// 自定义取色器（色环），外层放在 CalmCard 里即可与设置页风格统一。
class ColorPickerPage extends StatelessWidget {
  const ColorPickerPage({
    super.key,
    required this.currentColor,
    required this.onColorChanged,
  });

  final Color currentColor;
  final ValueChanged<Color> onColorChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 手机窄屏下色环收敛尺寸，避免撑破卡片；桌面端上限 240。
        final ringSize = constraints.maxWidth.clamp(150.0, 240.0);
        return Center(
          child: HueRingPicker(
            pickerColor: currentColor,
            onColorChanged: onColorChanged,
            displayThumbColor: true,
            enableAlpha: false,
            portraitOnly: true,
            colorPickerHeight: ringSize,
            hueRingStrokeWidth: 18,
            pickerAreaBorderRadius: BorderRadius.circular(999),
          ),
        );
      },
    );
  }
}
