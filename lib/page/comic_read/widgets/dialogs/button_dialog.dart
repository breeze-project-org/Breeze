import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/ui/ui.dart';

/// 阅读器通用二选一确认弹窗：手机底部带抓手滑出，平板/桌面居中卡片。
///
/// 返回 `true` 表示确认，取消或点外部关闭返回 `false`。
Future<bool> buttonDialog(
  BuildContext context,
  String title,
  String content,
) async {
  return await showCalmDialog<bool>(
        context,
        title: title,
        icon: Icons.help_outline_rounded,
        barrierDismissible: false, // 不允许点击外部区域关闭对话框
        bodyBuilder: (ctx) => Text(
          content,
          style: TextStyle(fontSize: 12.5, height: 1.5, color: ctx.calm.text2),
        ),
        actionsBuilder: (ctx) => [
          CalmButton(
            label: t.common.cancel,
            variant: CalmButtonVariant.ghost,
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
          CalmButton(
            label: t.common.ok,
            variant: CalmButtonVariant.primary,
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ) ??
      false; // 处理返回值为空的情况
}
