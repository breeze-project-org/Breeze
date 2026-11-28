import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/type/pipe.dart';
import 'package:zephyr/ui/ui.dart';
import 'package:zephyr/util/text/chinese_convert.dart';

class MultiChoiceDialogOption {
  const MultiChoiceDialogOption({required this.label, required this.value});

  final String label;
  final String value;
}

/// 多选列表弹窗（CalmUI 版）。
///
/// 对外签名、默认值与返回值 `Future<Set<String>?>` 全部保持不变，
/// 内部改为自适应 [showCalmDialog] + [CalmCheckboxTile]，
/// 因此原先「Scrollbar 与 ListView 必须共用 controller」的约束随 Scrollbar 一并消失。
Future<Set<String>?> showMultiChoiceListDialog(
  BuildContext context, {
  required String title,
  required List<MultiChoiceDialogOption> options,
  Iterable<String> initialSelected = const <String>[],
  String? cancelText,
  String? confirmText,
  bool useFilledConfirmButton = false,
  double width = 520,
  double height = 420,
}) {
  final selected = Set<String>.from(initialSelected);
  return showCalmDialog<Set<String>>(
    context,
    title: title,
    maxWidth: width,
    bodyBuilder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) {
        // 桌面端宽度由 showCalmDialog 的 maxWidth 控制；手机端改为铺满底抽屉宽度，
        // 高度在矮屏上收敛到 55% 屏高，避免窄屏 / 矮屏溢出与挤压。
        return SizedBox(
          width: double.infinity,
          height: math.min(height, MediaQuery.sizeOf(context).height * 0.55),
          child: ListView.builder(
            padding: EdgeInsets.zero,
            itemCount: options.length,
            itemBuilder: (context, index) {
              final option = options[index];
              final isSelected = selected.contains(option.value);
              return CalmCheckboxTile(
                key: ValueKey(option.value),
                label: option.label.let(convertChineseForDisplay),
                value: isSelected,
                onChanged: (checked) {
                  setState(() {
                    if (checked) {
                      selected.add(option.value);
                    } else {
                      selected.remove(option.value);
                    }
                  });
                },
              );
            },
          ),
        );
      },
    ),
    actionsBuilder: (dialogContext) => [
      CalmButton(
        label: cancelText ?? t.common.cancel,
        variant: CalmButtonVariant.ghost,
        onPressed: () => Navigator.of(dialogContext).pop(),
      ),
      CalmButton(
        label: confirmText ?? t.common.ok,
        variant: useFilledConfirmButton
            ? CalmButtonVariant.primary
            : CalmButtonVariant.secondary,
        onPressed: () => Navigator.of(dialogContext).pop(selected),
      ),
    ],
  );
}
