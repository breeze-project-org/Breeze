import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/ui/ui.dart';

/// 跳页输入弹窗：胶囊输入框 + 数字过滤 + 页码范围校验（>= 1）。
///
/// 校验不通过时停留在弹窗内并给出错误提示，而不是静默关闭。
Future<int?> showNumberInputDialog({
  required BuildContext context,
  String? title,
  String? hintText,
  int? initialValue,
}) {
  final inputController = TextEditingController(
    text: initialValue?.toString() ?? '',
  );
  final error = ValueNotifier<String?>(null);

  void submit(BuildContext dialogContext, String raw) {
    final parsed = int.tryParse(raw.trim());
    if (parsed == null || parsed < 1) {
      error.value = t.searchResult.pleaseEnterNumber;
      return;
    }
    Navigator.of(dialogContext).pop(parsed);
  }

  return showCalmDialog<int>(
    context,
    title: title ?? t.searchResult.enterPageNumber,
    icon: Icons.pin_rounded,
    bodyBuilder: (ctx) => ValueListenableBuilder<String?>(
      valueListenable: error,
      builder: (ctx, errorText, _) => CalmTextField(
        controller: inputController,
        hintText: hintText ?? t.searchResult.pleaseEnterNumber,
        prefixIcon: Icons.numbers_rounded,
        errorText: errorText,
        keyboardType: TextInputType.number,
        onChanged: (value) {
          // 与旧的 FilteringTextInputFormatter.digitsOnly 等价：
          // 任何非数字（含粘贴）都不会留在输入框里。
          final digits = value.replaceAll(RegExp(r'\D'), '');
          if (digits != value) {
            inputController.value = TextEditingValue(
              text: digits,
              selection: TextSelection.collapsed(offset: digits.length),
            );
          }
          if (error.value != null) {
            error.value = null;
          }
        },
        onSubmitted: (value) => submit(ctx, value),
      ),
    ),
    actionsBuilder: (ctx) => [
      CalmButton(
        label: t.common.cancel,
        variant: CalmButtonVariant.ghost,
        onPressed: () => Navigator.of(ctx).pop(),
      ),
      CalmButton(
        label: t.common.next,
        variant: CalmButtonVariant.primary,
        onPressed: () => submit(ctx, inputController.text),
      ),
    ],
  );
}
