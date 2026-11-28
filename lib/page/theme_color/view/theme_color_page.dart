import 'package:auto_route/annotations.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/config/global/color_theme_types.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/page/setting/common/setting_ui.dart';
import 'package:zephyr/page/theme_color/theme_color.dart';

@RoutePage()
class ThemeColorPage extends StatefulWidget {
  const ThemeColorPage({super.key});

  @override
  State<ThemeColorPage> createState() => _ThemeColorPageState();
}

class _ThemeColorPageState extends State<ThemeColorPage> {
  late Color _currentColor;

  @override
  void initState() {
    super.initState();
    _currentColor = globalSetting.seedColor;
  }

  /// 当前主色恰好命中某套内置 Seed 时，让「推荐预设」对应项高亮。
  CalmSeed? get _selectedSeed {
    for (final seed in CalmSeed.values) {
      if (seed.swatch.toARGB32() == _currentColor.toARGB32()) return seed;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return SettingPageShell(
      title: t.settings.themeColor,
      subtitle: t.settings.themeColorSubtitle,
      child: ListView(
        padding: kSettingPagePadding,
        children: [
          settingSectionTitle(
            context,
            t.settings.themeColor,
            icon: Icons.auto_awesome_outlined,
          ),
          CalmCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  t.settings.themeColorSubtitle,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: context.calm.text3,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                CalmColorGrid(
                  selected: _selectedSeed,
                  onSelected: (seed) {
                    setState(() => _currentColor = seed.swatch);
                    _setThemeColor(seed.swatch);
                  },
                ),
              ],
            ),
          ),
          settingSectionTitle(
            context,
            t.common.custom,
            icon: Icons.colorize_outlined,
          ),
          CalmCard(
            child: ColorPickerPage(
              currentColor: _currentColor,
              onColorChanged: (color) {
                // 更新本地 UI 状态
                setState(() => _currentColor = color);
                // 更新全局 Cubit 状态
                _setThemeColor(color);
              },
            ),
          ),
          settingSectionTitle(
            context,
            t.common.all,
            icon: Icons.palette_outlined,
          ),
          CalmCard(
            child: LayoutBuilder(
              builder: (context, constraints) {
                const spacing = 8.0;
                // 自适应列宽：窄屏 4 列，宽屏最多 8 列，永不出现内容溢出。
                final columns = (constraints.maxWidth / 76).floor().clamp(4, 9);
                final itemWidth =
                    (constraints.maxWidth - spacing * (columns - 1)) / columns;
                return Wrap(
                  spacing: spacing,
                  runSpacing: 12,
                  children: colorThemeList.map((colorInfo) {
                    return ColorThemeItem(
                      colorInfo: colorInfo,
                      currentColor: _currentColor,
                      itemWidth: itemWidth,
                      onColorSelected: (color) {
                        setState(() => _currentColor = color);
                        _setThemeColor(color);
                      },
                    );
                  }).toList(),
                );
              },
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  void _setThemeColor(Color color) {
    context.read<GlobalSettingCubit>().updateState(
      (current) => current.copyWith(seedColor: color),
    );
  }
}
