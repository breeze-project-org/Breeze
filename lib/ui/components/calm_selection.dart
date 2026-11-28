import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/ui/components/calm_button.dart';
import 'package:zephyr/ui/components/calm_feedback.dart';
import 'package:zephyr/ui/theme/calm_theme.dart';

/// 常规二态复选框（柔和圆角方框 + 缩放对勾）。
class CalmCheckbox extends StatelessWidget {
  const CalmCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    this.size = 18,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    final enabled = onChanged != null;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: enabled ? () => onChanged!(!value) : null,
        child: AnimatedOpacity(
          opacity: enabled ? 1.0 : 0.45,
          duration: const Duration(milliseconds: 140),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOutCubic,
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: value ? c.accent : c.surface,
              borderRadius: BorderRadius.circular(5.5),
              border: Border.all(
                color: value ? c.accent : c.borderStrong,
                width: 1.4,
              ),
            ),
            alignment: Alignment.center,
            child: AnimatedScale(
              scale: value ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOutBack,
              child: Icon(
                Icons.check_rounded,
                size: size * 0.72,
                color: c.accentFg,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 高密度复选框列表行（选中时带柔和主色底）。
class CalmCheckboxTile extends StatelessWidget {
  const CalmCheckboxTile({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(!value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: EdgeInsets.symmetric(
            horizontal: 11,
            vertical: c.rowVPadding,
          ),
          decoration: BoxDecoration(
            color: value ? c.accentSoft : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              CalmCheckbox(value: value, onChanged: onChanged),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: value ? FontWeight.w600 : FontWeight.w400,
                        color: value ? c.accent : c.text,
                        height: 1.25,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: TextStyle(fontSize: 11, color: c.text3),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 紧凑胶囊数字步进器（用于列数、并发数、页码、间隔调节）。
class CalmStepper extends StatelessWidget {
  const CalmStepper({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.step = 1,
    this.suffix = '',
  });

  final int value;
  final int min;
  final int max;
  final int step;
  final String suffix;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    final canDec = value - step >= min;
    final canInc = value + step <= max;

    return Container(
      height: 30,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StepperBtn(
            icon: Icons.remove_rounded,
            enabled: canDec,
            onTap: () => onChanged((value - step).clamp(min, max)),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                '$value$suffix',
                textAlign: TextAlign.center,
                textHeightBehavior: kCalmTextHeightBehavior,
                strutStyle: calmStrut(12),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: c.text,
                  height: 1.2,
                  leadingDistribution: TextLeadingDistribution.even,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
          _StepperBtn(
            icon: Icons.add_rounded,
            enabled: canInc,
            onTap: () => onChanged((value + step).clamp(min, max)),
          ),
        ],
      ),
    );
  }
}

class _StepperBtn extends StatelessWidget {
  const _StepperBtn({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: AnimatedOpacity(
          opacity: enabled ? 1.0 : 0.35,
          duration: const Duration(milliseconds: 120),
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: c.surface,
              shape: BoxShape.circle,
              boxShadow: c.shadowSm,
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 14, color: c.text),
          ),
        ),
      ),
    );
  }
}

/// 分段式数字 PIN 码输入框（4 位或 6 位，隐私锁与验证弹窗通用）。
class CalmPinField extends StatefulWidget {
  const CalmPinField({
    super.key,
    this.length = 4,
    this.obscure = false,
    this.initialValue = '',
    this.onChanged,
    this.onCompleted,
  });

  final int length;
  final bool obscure;
  final String initialValue;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onCompleted;

  @override
  State<CalmPinField> createState() => _CalmPinFieldState();
}

class _CalmPinFieldState extends State<CalmPinField> {
  late final TextEditingController _ctrl = TextEditingController(
    text: widget.initialValue,
  );
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    final text = _ctrl.text;
    final activeIdx = text.length.clamp(0, widget.length - 1);

    return GestureDetector(
      onTap: () => _focus.requestFocus(),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 隐藏真实输入承接键盘与粘贴
          Opacity(
            opacity: 0,
            child: SizedBox(
              width: 1,
              height: 1,
              child: TextField(
                controller: _ctrl,
                focusNode: _focus,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(widget.length),
                ],
                onChanged: (v) {
                  setState(() {});
                  widget.onChanged?.call(v);
                  if (v.length == widget.length) {
                    widget.onCompleted?.call(v);
                  }
                },
              ),
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < widget.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  width: 40,
                  height: 44,
                  decoration: BoxDecoration(
                    color: c.surface2,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _focus.hasFocus && i == activeIdx
                          ? c.accent
                          : i < text.length
                          ? c.accentBorder
                          : Colors.transparent,
                      width: 1.6,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: i < text.length
                      ? widget.obscure
                            ? Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: c.text,
                                  shape: BoxShape.circle,
                                ),
                              )
                            : Text(
                                text[i],
                                textHeightBehavior: kCalmTextHeightBehavior,
                                strutStyle: calmStrut(16),
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: c.text,
                                  height: 1.2,
                                  leadingDistribution:
                                      TextLeadingDistribution.even,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              )
                      : null,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// 封装好的滚动多选列表弹窗（支持全选/清空、实时已选数量）。
Future<Set<T>?> showCalmMultiChoiceDialog<T>(
  BuildContext context, {
  required String title,
  String? subtitle,
  required List<({T value, String label, String? subtitle})> options,
  Set<T> initialSelected = const {},
  String confirmLabel = '确定',
}) {
  final selected = Set<T>.from(initialSelected);
  return showCalmDialog<Set<T>>(
    context,
    title: title,
    subtitle: subtitle,
    bodyBuilder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        final allSelected =
            options.isNotEmpty && selected.length == options.length;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '已选 ${selected.length} / ${options.length} 项',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: ctx.calm.text3,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                CalmButton(
                  label: allSelected ? '全不选' : '全选',
                  size: CalmButtonSize.xs,
                  variant: CalmButtonVariant.ghost,
                  onPressed: () {
                    setState(() {
                      if (allSelected) {
                        selected.clear();
                      } else {
                        selected.addAll(options.map((e) => e.value));
                      }
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: options.length,
                separatorBuilder: (_, _) => const SizedBox(height: 2),
                itemBuilder: (_, idx) {
                  final opt = options[idx];
                  final checked = selected.contains(opt.value);
                  return CalmCheckboxTile(
                    label: opt.label,
                    subtitle: opt.subtitle,
                    value: checked,
                    onChanged: (v) {
                      setState(() {
                        if (v) {
                          selected.add(opt.value);
                        } else {
                          selected.remove(opt.value);
                        }
                      });
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    ),
    actionsBuilder: (ctx) => [
      CalmButton(
        label: '取消',
        variant: CalmButtonVariant.ghost,
        onPressed: () => Navigator.of(ctx).pop(),
      ),
      CalmButton(
        label: confirmLabel,
        variant: CalmButtonVariant.primary,
        onPressed: () => Navigator.of(ctx).pop(selected),
      ),
    ],
  );
}
