import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/ui/ui.dart';

Future<void> nothingDialog(BuildContext context) async {
  return showCalmDialog<void>(
    context,
    title: t.common.underConstruction,
    icon: Icons.construction_rounded,
    tone: CalmTone.warning,
    barrierDismissible: false, // user must tap button!
    bodyBuilder: (ctx) => Text(
      t.common.comingSoon,
      style: TextStyle(fontSize: 12.5, color: ctx.calm.text2, height: 1.45),
    ),
    actionsBuilder: (ctx) => [
      CalmButton(
        label: t.common.gotIt,
        variant: CalmButtonVariant.primary,
        onPressed: () => Navigator.of(ctx).pop(),
      ),
    ],
  );
}

// 通用对话框
// 只用来提示信息
Future<void> commonDialog(
  BuildContext context,
  String title,
  String content,
) async {
  return showCalmDialog<void>(
    context,
    title: title,
    barrierDismissible: false, // user must tap button!
    bodyBuilder: (ctx) => SelectableText(
      content,
      style: TextStyle(fontSize: 12.5, color: ctx.calm.text2, height: 1.45),
    ),
    actionsBuilder: (ctx) => [
      CalmButton(
        label: t.common.cancel,
        variant: CalmButtonVariant.ghost,
        onPressed: () => Navigator.of(ctx).pop(),
      ),
      CalmButton(
        label: t.common.ok,
        variant: CalmButtonVariant.primary,
        onPressed: () => Navigator.of(ctx).pop(),
      ),
    ],
  );
}
