import 'package:material_ui/material_ui.dart';
import 'package:zephyr/ui/theme/calm_theme.dart';

enum CalmButtonVariant { primary, tonal, secondary, ghost, danger }

enum CalmButtonSize { xs, sm, md }

/// 轻盈胶囊按钮：5 种语义层级 × 3 种尺寸，带轻微按压回弹与加载态。
class CalmButton extends StatefulWidget {
  const CalmButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.trailingIcon,
    this.variant = CalmButtonVariant.secondary,
    this.size = CalmButtonSize.sm,
    this.loading = false,
    this.expand = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final IconData? trailingIcon;
  final CalmButtonVariant variant;
  final CalmButtonSize size;
  final bool loading;
  final bool expand;

  @override
  State<CalmButton> createState() => _CalmButtonState();
}

class _CalmButtonState extends State<CalmButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    final enabled = widget.onPressed != null && !widget.loading;

    final (height, hPad, fontSize, iconSize) = switch (widget.size) {
      CalmButtonSize.xs => (26.0, 10.0, 11.0, 13.0),
      CalmButtonSize.sm => (30.0, 13.0, 12.0, 14.5),
      CalmButtonSize.md => (35.0, 16.0, 12.5, 15.5),
    };

    final (bg, fg, shadow) = switch (widget.variant) {
      CalmButtonVariant.primary => (
        _hovered
            ? Color.alphaBlend(Colors.white.withValues(alpha: 0.08), c.accent)
            : c.accent,
        c.accentFg,
        [
          BoxShadow(
            color: c.accentBorder,
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      CalmButtonVariant.tonal => (
        _hovered
            ? Color.alphaBlend(c.accent.withValues(alpha: 0.06), c.accentSoft)
            : c.accentSoft,
        c.accent,
        const <BoxShadow>[],
      ),
      CalmButtonVariant.secondary => (
        _hovered ? c.surfaceHover : c.surface2,
        c.text,
        const <BoxShadow>[],
      ),
      CalmButtonVariant.ghost => (
        _hovered ? c.surface2 : Colors.transparent,
        _hovered ? c.text : c.text2,
        const <BoxShadow>[],
      ),
      CalmButtonVariant.danger => (
        _hovered ? c.danger.withValues(alpha: 0.18) : c.dangerSoft,
        c.danger,
        const <BoxShadow>[],
      ),
    };

    final child = AnimatedScale(
      scale: _pressed && enabled ? 0.97 : 1.0,
      duration: const Duration(milliseconds: 110),
      curve: Curves.easeOut,
      child: AnimatedOpacity(
        opacity: enabled ? 1.0 : 0.42,
        duration: const Duration(milliseconds: 140),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          height: height,
          padding: EdgeInsets.symmetric(horizontal: hPad),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(999),
            boxShadow: enabled ? shadow : const [],
          ),
          child: Row(
            mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.loading) ...[
                SizedBox(
                  width: iconSize,
                  height: iconSize,
                  child: CircularProgressIndicator(strokeWidth: 1.8, color: fg),
                ),
                const SizedBox(width: 6),
              ] else if (widget.icon != null) ...[
                Icon(widget.icon, size: iconSize, color: fg),
                const SizedBox(width: 5),
              ],
              Text(
                widget.label,
                textHeightBehavior: kCalmTextHeightBehavior,
                strutStyle: calmStrut(fontSize),
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: FontWeight.w500,
                  color: fg,
                  height: 1.2,
                  leadingDistribution: TextLeadingDistribution.even,
                ),
              ),
              if (widget.trailingIcon != null) ...[
                const SizedBox(width: 4),
                Icon(widget.trailingIcon, size: iconSize, color: fg),
              ],
            ],
          ),
        ),
      ),
    );

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: () => setState(() => _pressed = false),
        onTap: enabled ? widget.onPressed : null,
        child: child,
      ),
    );
  }
}

/// 轻盈圆形图标按钮（支持选中激活态，如收藏/置顶）。
class CalmIconButton extends StatefulWidget {
  const CalmIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.selected = false,
    this.tooltip,
    this.size = 32,
    this.iconSize = 16,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final bool selected;
  final String? tooltip;
  final double size;
  final double iconSize;

  @override
  State<CalmIconButton> createState() => _CalmIconButtonState();
}

class _CalmIconButtonState extends State<CalmIconButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    final enabled = widget.onPressed != null;

    final bg = widget.selected
        ? c.accentSoft
        : _hovered
        ? c.surfaceHover
        : c.surface2;
    final fg = widget.selected ? c.accent : (_hovered ? c.text : c.text2);

    final btn = MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onPressed,
        child: AnimatedScale(
          scale: _pressed && enabled ? 0.94 : 1.0,
          duration: const Duration(milliseconds: 110),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Icon(widget.icon, size: widget.iconSize, color: fg),
          ),
        ),
      ),
    );

    if (widget.tooltip != null) {
      return Tooltip(message: widget.tooltip!, child: btn);
    }
    return btn;
  }
}
