import 'package:material_ui/material_ui.dart';
import 'package:zephyr/ui/theme/calm_theme.dart';

/// 精确垂直居中的轻量胶囊开关（38×22，内部 16×16 圆球）。
class CalmSwitch extends StatelessWidget {
  const CalmSwitch({super.key, required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

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
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            width: 38,
            height: 22,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: value ? c.accent : c.surfaceHover,
              borderRadius: BorderRadius.circular(999),
            ),
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.14),
                      blurRadius: 3,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 三态筛选状态：忽略 / 包含 / 排除（漫画标签筛选必备）。
enum CalmTriState { none, include, exclude }

class CalmTriCheckbox extends StatelessWidget {
  const CalmTriCheckbox({
    super.key,
    required this.label,
    required this.state,
    required this.onChanged,
  });

  final String label;
  final CalmTriState state;
  final ValueChanged<CalmTriState> onChanged;

  CalmTriState _next(CalmTriState cur) => switch (cur) {
    CalmTriState.none => CalmTriState.include,
    CalmTriState.include => CalmTriState.exclude,
    CalmTriState.exclude => CalmTriState.none,
  };

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    final (boxBg, boxBorder, icon, iconColor, stateLabel) = switch (state) {
      CalmTriState.include => (
        c.accent,
        c.accent,
        Icons.check_rounded,
        c.accentFg,
        '包含',
      ),
      CalmTriState.exclude => (
        c.dangerSoft,
        c.danger.withValues(alpha: 0.5),
        Icons.remove_rounded,
        c.danger,
        '排除',
      ),
      CalmTriState.none => (
        c.surface,
        c.borderStrong,
        null,
        Colors.transparent,
        '忽略',
      ),
    };

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => onChanged(_next(state)),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: c.bg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                width: 17,
                height: 17,
                decoration: BoxDecoration(
                  color: boxBg,
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: boxBorder, width: 1.2),
                ),
                alignment: Alignment.center,
                child: icon != null
                    ? Icon(icon, size: 12, color: iconColor)
                    : null,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(fontSize: 12, color: c.text),
                ),
              ),
              Text(
                stateLabel,
                style: TextStyle(
                  fontSize: 10.5,
                  color: state == CalmTriState.include
                      ? c.accent
                      : state == CalmTriState.exclude
                      ? c.danger
                      : c.text3,
                  fontWeight: state == CalmTriState.none
                      ? FontWeight.w400
                      : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 轻盈单选行。
class CalmRadioTile<T> extends StatelessWidget {
  const CalmRadioTile({
    super.key,
    required this.label,
    required this.value,
    required this.groupValue,
    required this.onChanged,
  });

  final String label;
  final T value;
  final T groupValue;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    final selected = value == groupValue;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => onChanged(value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? c.accentSoft : c.bg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? c.accent : c.borderStrong,
                    width: selected ? 1.8 : 1.3,
                  ),
                ),
                alignment: Alignment.center,
                child: AnimatedScale(
                  scale: selected ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 140),
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: c.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
                    color: selected ? c.accent : c.text,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 胶囊风格输入框 / 搜索框（带清空按钮、快捷键徽章、错误提示）。
class CalmTextField extends StatefulWidget {
  const CalmTextField({
    super.key,
    this.controller,
    this.hintText,
    this.prefixIcon,
    this.shortcutHint,
    this.errorText,
    this.obscureText = false,
    this.clearable = true,
    this.onChanged,
    this.onSubmitted,
    this.keyboardType,
  });

  final TextEditingController? controller;
  final String? hintText;
  final IconData? prefixIcon;
  final String? shortcutHint;
  final String? errorText;
  final bool obscureText;
  final bool clearable;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputType? keyboardType;

  @override
  State<CalmTextField> createState() => _CalmTextFieldState();
}

class _CalmTextFieldState extends State<CalmTextField> {
  late final TextEditingController _ctrl =
      widget.controller ?? TextEditingController();
  final FocusNode _focus = FocusNode();
  bool _focused = false;
  late bool _obscured = widget.obscureText;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (mounted) setState(() => _focused = _focus.hasFocus);
    });
    _ctrl.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onTextChanged);
    if (widget.controller == null) _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    final hasError = widget.errorText != null && widget.errorText!.isNotEmpty;
    final hasText = _ctrl.text.isNotEmpty;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: hasError ? c.dangerSoft : c.surface2,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: hasError
                  ? c.danger.withValues(alpha: 0.5)
                  : _focused
                  ? c.accentBorder
                  : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (widget.prefixIcon != null) ...[
                Icon(widget.prefixIcon, size: 15, color: c.text3),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  focusNode: _focus,
                  obscureText: _obscured,
                  keyboardType: widget.keyboardType,
                  onChanged: widget.onChanged,
                  onSubmitted: widget.onSubmitted,
                  style: TextStyle(fontSize: 12.5, color: c.text, height: 1.2),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                    hintText: widget.hintText,
                    hintStyle: TextStyle(fontSize: 12.5, color: c.text3),
                  ),
                ),
              ),
              if (widget.obscureText)
                GestureDetector(
                  onTap: () => setState(() => _obscured = !_obscured),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Icon(
                      _obscured
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded,
                      size: 15,
                      color: c.text3,
                    ),
                  ),
                )
              else if (widget.clearable && hasText)
                GestureDetector(
                  onTap: () {
                    _ctrl.clear();
                    widget.onChanged?.call('');
                  },
                  child: Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Icon(Icons.close_rounded, size: 15, color: c.text3),
                  ),
                )
              else if (widget.shortcutHint != null)
                Container(
                  height: 18,
                  padding: const EdgeInsets.symmetric(horizontal: 7),
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    widget.shortcutHint!,
                    style: TextStyle(
                      fontSize: 9.5,
                      color: c.text3,
                      height: 1.0,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (hasError)
          Padding(
            padding: const EdgeInsets.only(left: 12, top: 4),
            child: Text(
              widget.errorText!,
              style: TextStyle(fontSize: 10.5, color: c.danger),
            ),
          ),
      ],
    );
  }
}

/// 轻盈多行文本域（用于评论回复、漫画简介编辑、屏蔽词与多行配置）。
class CalmTextArea extends StatefulWidget {
  const CalmTextArea({
    super.key,
    this.controller,
    this.hintText,
    this.minLines = 3,
    this.maxLines = 6,
    this.maxLength,
    this.errorText,
    this.onChanged,
  });

  final TextEditingController? controller;
  final String? hintText;
  final int minLines;
  final int maxLines;
  final int? maxLength;
  final String? errorText;
  final ValueChanged<String>? onChanged;

  @override
  State<CalmTextArea> createState() => _CalmTextAreaState();
}

class _CalmTextAreaState extends State<CalmTextArea> {
  late final TextEditingController _ctrl =
      widget.controller ?? TextEditingController();
  final FocusNode _focus = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (mounted) setState(() => _focused = _focus.hasFocus);
    });
    _ctrl.addListener(_onChanged);
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onChanged);
    if (widget.controller == null) _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    final hasError = widget.errorText != null && widget.errorText!.isNotEmpty;
    final len = _ctrl.text.characters.length;
    final overLimit = widget.maxLength != null && len > widget.maxLength!;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.fromLTRB(13, 10, 13, 10),
          decoration: BoxDecoration(
            color: hasError || overLimit ? c.dangerSoft : c.surface2,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: hasError || overLimit
                  ? c.danger.withValues(alpha: 0.5)
                  : _focused
                  ? c.accentBorder
                  : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: TextField(
            controller: _ctrl,
            focusNode: _focus,
            minLines: widget.minLines,
            maxLines: widget.maxLines,
            onChanged: widget.onChanged,
            style: TextStyle(fontSize: 12.5, color: c.text, height: 1.5),
            decoration: InputDecoration(
              isDense: true,
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
              hintText: widget.hintText,
              hintStyle: TextStyle(fontSize: 12.5, color: c.text3),
            ),
          ),
        ),
        if (hasError || widget.maxLength != null)
          Padding(
            padding: const EdgeInsets.only(left: 10, right: 6, top: 4),
            child: Row(
              children: [
                Expanded(
                  child: hasError
                      ? Text(
                          widget.errorText!,
                          style: TextStyle(fontSize: 10.5, color: c.danger),
                        )
                      : const SizedBox.shrink(),
                ),
                if (widget.maxLength != null)
                  Text(
                    '$len / ${widget.maxLength}',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: overLimit ? c.danger : c.text3,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// 轻盈滑块控件（带标签与右侧等宽数值）。
class CalmSlider extends StatelessWidget {
  const CalmSlider({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.divisions,
    this.label,
    this.valueText,
  });

  final double value;
  final double min;
  final double max;
  final int? divisions;
  final ValueChanged<double> onChanged;
  final String? label;
  final String? valueText;

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null || valueText != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (label != null)
                  Text(
                    label!,
                    style: TextStyle(fontSize: 11.5, color: c.text2),
                  ),
                if (valueText != null)
                  Text(
                    valueText!,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: c.text,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
              ],
            ),
          ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            activeTrackColor: c.accent,
            inactiveTrackColor: c.surfaceHover,
            thumbColor: c.accent,
            overlayColor: c.accentSoft,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 15),
          ),
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

/// WinUI / Fluent 风格轻盈下拉选择器（选中项左侧 3px 垂直居中主色竖条，无对勾）。
class CalmDropdown<T> extends StatefulWidget {
  const CalmDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final T value;
  final List<({T value, String label, String? meta})> items;
  final ValueChanged<T> onChanged;

  @override
  State<CalmDropdown<T>> createState() => _CalmDropdownState<T>();
}

class _CalmDropdownState<T> extends State<CalmDropdown<T>> {
  final LayerLink _link = LayerLink();
  OverlayEntry? _entry;
  bool _open = false;

  void _toggle() {
    if (_open) {
      _close();
    } else {
      _show();
    }
  }

  void _close() {
    _entry?.remove();
    _entry = null;
    if (mounted) setState(() => _open = false);
  }

  void _show() {
    final overlay = Overlay.of(context);
    final box = context.findRenderObject() as RenderBox?;
    final width = box?.size.width ?? 220;
    final c = context.calm;

    _entry = OverlayEntry(
      builder: (ctx) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _close,
            ),
          ),
          CompositedTransformFollower(
            link: _link,
            showWhenUnlinked: false,
            offset: Offset(0, (box?.size.height ?? 36) + 6),
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: width.clamp(180, 320),
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: c.border),
                  boxShadow: c.shadowMd,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final item in widget.items)
                      _FluentOptionRow(
                        label: item.label,
                        meta: item.meta,
                        selected: item.value == widget.value,
                        calm: c,
                        onTap: () {
                          widget.onChanged(item.value);
                          _close();
                        },
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
    overlay.insert(_entry!);
    setState(() => _open = true);
  }

  @override
  void dispose() {
    _entry?.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    final current = widget.items.firstWhere(
      (e) => e.value == widget.value,
      orElse: () => widget.items.first,
    );

    return CompositedTransformTarget(
      link: _link,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: _toggle,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: _open ? c.surfaceHover : c.surface2,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    current.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: c.text,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedRotation(
                  turns: _open ? 0.5 : 0,
                  duration: const Duration(milliseconds: 160),
                  child: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 16,
                    color: c.text3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FluentOptionRow extends StatefulWidget {
  const _FluentOptionRow({
    required this.label,
    required this.selected,
    required this.calm,
    required this.onTap,
    this.meta,
  });

  final String label;
  final String? meta;
  final bool selected;
  final CalmColors calm;
  final VoidCallback onTap;

  @override
  State<_FluentOptionRow> createState() => _FluentOptionRowState();
}

class _FluentOptionRowState extends State<_FluentOptionRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.calm;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          height: 36,
          decoration: BoxDecoration(
            color: widget.selected
                ? c.accentSoft
                : _hovered
                ? c.surface2
                : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              if (widget.selected)
                Positioned(
                  left: 5,
                  child: Container(
                    width: 3,
                    height: 16,
                    decoration: BoxDecoration(
                      color: c.accent,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: widget.selected
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: widget.selected ? c.accent : c.text,
                        ),
                      ),
                    ),
                    if (widget.meta != null)
                      Text(
                        widget.meta!,
                        style: TextStyle(fontSize: 10.5, color: c.text3),
                      ),
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
