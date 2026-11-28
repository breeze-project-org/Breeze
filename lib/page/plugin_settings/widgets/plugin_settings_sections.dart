import 'package:material_ui/material_ui.dart';
import 'package:zephyr/page/setting/common/setting_ui.dart';

/// 插件设置分组卡（CalmUI 版）：轻盈分组头 + 零内边距浮空卡片 + 柔和分割线。
///
/// 颜色全部由 `context.calm` 令牌决定（不再吃 Material ColorScheme），
/// 保证 6 套主题色与深浅色切换零割裂。
class PluginSettingsSectionCard extends StatelessWidget {
  const PluginSettingsSectionCard({
    super.key,
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final trimmed = title.trim();
    if (trimmed.isEmpty && children.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (trimmed.isNotEmpty) settingSectionTitle(context, trimmed),
        if (children.isNotEmpty) settingCardGroup(children),
      ],
    );
  }
}

/// 插件设置行（CalmUI 版）：左侧可选语义图标底 + 标题/副标题 + 尾部任意控件。
///
/// 旧签名 `(title, subtitle, trailing, onTap)` 仍然兼容：
/// [subtitle] 与 [trailing] 现在都可省略，[icon] 为新增可选语义。
class PluginSettingsFieldRow extends StatelessWidget {
  const PluginSettingsFieldRow({
    super.key,
    required this.title,
    this.subtitle = '',
    this.trailing,
    this.onTap,
    this.icon,
  });

  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    return CalmListTile(
      title: title,
      subtitle: subtitle.trim().isEmpty ? null : subtitle,
      onTap: onTap,
      leading: icon == null ? null : settingTileIcon(icon!),
      trailing:
          trailing ??
          (onTap == null
              ? null
              : Icon(Icons.chevron_right_rounded, size: 18, color: c.text3)),
    );
  }
}

class PluginSettingsOptionPair {
  const PluginSettingsOptionPair({required this.label, required this.value});

  final String label;
  final dynamic value;
}
