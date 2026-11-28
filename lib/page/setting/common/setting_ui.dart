import 'package:material_ui/material_ui.dart';
import 'package:zephyr/ui/ui.dart';

// 设置页普遍复用 CalmUI 组件，统一从这里连带导出，避免每个子页重复 import。
export 'package:zephyr/ui/ui.dart';

const EdgeInsets kSettingPagePadding = EdgeInsets.fromLTRB(16, 12, 16, 24);

/// 保留旧常量名以免影响调用方；CalmUI 的 [CalmSwitch] 不再使用系统 thumb 图标。
const WidgetStateProperty<Icon> kSettingSwitchThumbIcon =
    WidgetStateProperty<Icon>.fromMap(<WidgetStatesConstraint, Icon>{
      WidgetState.selected: Icon(Icons.check),
      WidgetState.any: Icon(Icons.close),
    });

/// 设置页统一外壳：轻盈 [CalmAppBar] + 居中限宽内容区。
///
/// 保持 `(title, child)` 旧调用 100% 兼容，另外新增可选 [subtitle]、[actions] 与 [badge]。
class SettingPageShell extends StatelessWidget {
  const SettingPageShell({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.actions = const [],
    this.badge,
    this.maxContentWidth = 768,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final String? badge;
  final double maxContentWidth;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CalmPageScaffold(
      title: title,
      subtitle: subtitle,
      badge: badge,
      actions: actions,
      maxContentWidth: maxContentWidth,
      body: child,
    );
  }
}

/// 设置行左侧 30×30 圆角图标底（accentSoft + accent），供各设置页直接复用。
Widget settingTileIcon(IconData icon) {
  return Builder(
    builder: (context) {
      final c = context.calm;
      return Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: c.accentSoft,
          borderRadius: BorderRadius.circular(9),
        ),
        alignment: Alignment.center,
        child: Icon(icon, size: 16, color: c.accent),
      );
    },
  );
}

/// 设置分组标题（轻盈分组头，替代旧的主色小标题）。
///
/// [icon] 仅为兼容旧调用保留：[CalmSectionHeader] 自带主色圆条标记，
/// 再额外画一个图标会让分组头变重，因此这里统一以圆条为准。
Widget settingSectionTitle(
  BuildContext context,
  String title, {
  IconData? icon,
}) {
  return Padding(
    padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
    child: CalmSectionHeader(title: title),
  );
}

/// 设置分类入口行（图标 + 标题 + 副标题 + 柔和右箭头）。
Widget settingCategoryTile({
  required IconData icon,
  required String title,
  required String subtitle,
  required VoidCallback onTap,
  Widget? trailing,
}) {
  return Builder(
    builder: (context) {
      final c = context.calm;
      return CalmListTile(
        title: title,
        subtitle: subtitle,
        onTap: onTap,
        leading: settingTileIcon(icon),
        trailing:
            trailing ??
            Icon(Icons.chevron_right_rounded, size: 18, color: c.text3),
      );
    },
  );
}

/// 把若干设置行包进一张零内边距 [CalmCard]，行间用柔和细分割线。
///
/// 用于替代旧代码里零散的裸 `ListTile` + 全宽硬 `Divider`，避免卡片盒子套盒子。
Widget settingCardGroup(
  List<Widget> children, {
  double dividerIndent = 12,
  EdgeInsetsGeometry padding = EdgeInsets.zero,
}) {
  final rows = <Widget>[];
  for (var i = 0; i < children.length; i++) {
    rows.add(children[i]);
    if (i != children.length - 1) {
      rows.add(
        Padding(
          padding: EdgeInsets.symmetric(horizontal: dividerIndent),
          child: const CalmDivider(),
        ),
      );
    }
  }
  return CalmCard(
    padding: padding,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: rows,
    ),
  );
}

/// 设置分组卡片：分组头 + 零内边距 [CalmCard] + [CalmDivider] 分隔的条目。
class SettingSectionCard extends StatelessWidget {
  const SettingSectionCard({
    super.key,
    required this.title,
    required this.icon,
    required this.children,
    this.subtitle,
    this.dividerIndent = 12,
  });

  final String title;
  final IconData icon;
  final String? subtitle;
  final double dividerIndent;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        settingSectionTitle(context, title, icon: icon),
        settingCardGroup(children, dividerIndent: dividerIndent),
        if (subtitle != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
            child: Text(
              subtitle!,
              style: TextStyle(fontSize: 11, color: context.calm.text3),
            ),
          ),
      ],
    );
  }
}

/// 设置页开关行：整行可点即切换，右侧统一 [CalmSwitch]。
Widget settingSwitchTile({
  required String title,
  required bool value,
  required ValueChanged<bool>? onChanged,
  String? subtitle,
  IconData? icon,
}) {
  return CalmListTile(
    title: title,
    subtitle: subtitle,
    onTap: onChanged == null ? null : () => onChanged(!value),
    leading: icon == null ? null : settingTileIcon(icon),
    trailing: CalmSwitch(value: value, onChanged: onChanged),
  );
}

/// 设置页通用动作行（可选尾部任意控件，默认右箭头）。
Widget settingActionTile({
  required String title,
  VoidCallback? onTap,
  String? subtitle,
  IconData? icon,
  Widget? trailing,
}) {
  return Builder(
    builder: (context) {
      final c = context.calm;
      return CalmListTile(
        title: title,
        subtitle: subtitle,
        onTap: onTap,
        leading: icon == null ? null : settingTileIcon(icon),
        trailing:
            trailing ??
            (onTap == null
                ? null
                : Icon(Icons.chevron_right_rounded, size: 18, color: c.text3)),
      );
    },
  );
}

/// 危险操作按钮样式（向后兼容旧调用）：内部读 CalmUI 的 danger 语义色。
ButtonStyle settingDangerButtonStyle(BuildContext context) {
  final c = context.calm;
  return FilledButton.styleFrom(
    minimumSize: const Size.fromHeight(44),
    backgroundColor: c.dangerSoft,
    foregroundColor: c.danger,
  );
}
