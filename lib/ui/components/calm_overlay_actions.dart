import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/ui/components/calm_button.dart';
import 'package:zephyr/ui/theme/calm_theme.dart';

/// 上下文弹出菜单项（支持图标、快捷键、分割线与危险态）。
class CalmPopupMenuEntry<T> {
  const CalmPopupMenuEntry.item({
    required T this.value,
    required String this.label,
    this.icon,
    this.shortcut,
    this.danger = false,
  }) : isDivider = false;

  const CalmPopupMenuEntry.divider()
    : value = null,
      label = null,
      icon = null,
      shortcut = null,
      danger = false,
      isDivider = true;

  final T? value;
  final String? label;
  final IconData? icon;
  final String? shortcut;
  final bool danger;
  final bool isDivider;
}

double _estimateMenuHeight<T>(List<CalmPopupMenuEntry<T>> entries) {
  double height = 14;
  for (final e in entries) {
    height += e.isDivider ? 9 : 34;
  }
  return height;
}

/// 按菜单项内容动态测量合适宽度（图标 + 文案 + 快捷键 + 呼吸余量），避免固定宽导致大面积留白。
double _measureMenuWidth<T>(
  BuildContext context,
  List<CalmPopupMenuEntry<T>> entries, {
  double minWidth = 132,
  double maxWidth = 260,
}) {
  final textDirection = Directionality.of(context);
  final textScaler = MediaQuery.textScalerOf(context);
  final baseStyle = DefaultTextStyle.of(context).style;

  double maxRowWidth = 0;
  for (final entry in entries) {
    if (entry.isDivider) continue;

    final labelPainter = TextPainter(
      text: TextSpan(
        text: entry.label ?? '',
        style: baseStyle.copyWith(
          fontSize: 12,
          fontWeight: entry.danger ? FontWeight.w500 : FontWeight.w400,
        ),
      ),
      maxLines: 1,
      textDirection: textDirection,
      textScaler: textScaler,
    )..layout();

    // 行内边距(20) + 面板内边距(12) + 面板边框(2) + 右侧呼吸留白(14)
    double rowWidth = 48 + labelPainter.width;
    if (entry.icon != null) {
      rowWidth += 15 + 9;
    }
    if (entry.shortcut != null && entry.shortcut!.isNotEmpty) {
      final shortcutPainter = TextPainter(
        text: TextSpan(
          text: entry.shortcut!,
          style: baseStyle.copyWith(fontSize: 10),
        ),
        maxLines: 1,
        textDirection: textDirection,
        textScaler: textScaler,
      )..layout();
      rowWidth += 12 + shortcutPainter.width;
    }
    if (rowWidth > maxRowWidth) {
      maxRowWidth = rowWidth;
    }
  }

  return maxRowWidth.ceilToDouble().clamp(minWidth, maxWidth).toDouble();
}

/// 统一计算弹出菜单坐标，确保在任意屏幕边缘自动贴边避让与上下翻转。
({
  double left,
  double top,
  double width,
  double maxHeight,
  bool alignRight,
  bool openUp,
})
_computeMenuGeometry({
  required Size overlaySize,
  required EdgeInsets safePadding,
  required Rect anchorRect,
  required double desiredWidth,
  required double estimatedHeight,
  double gap = 6,
  double margin = 10,
}) {
  final minLeft = safePadding.left + margin;
  final maxRight = overlaySize.width - safePadding.right - margin;
  final availableWidth = math.max(120.0, maxRight - minLeft);
  final width = math.min(desiredWidth, availableWidth);

  final fitsLeftAligned = anchorRect.left + width <= maxRight;
  final alignRight = !fitsLeftAligned;
  final rawLeft = alignRight ? anchorRect.right - width : anchorRect.left;
  final left = rawLeft
      .clamp(minLeft, math.max(minLeft, maxRight - width))
      .toDouble();

  final minTop = safePadding.top + margin;
  final maxBottom = overlaySize.height - safePadding.bottom - margin;
  final belowStart = anchorRect.bottom + gap;
  final spaceBelow = math.max(0.0, maxBottom - belowStart);
  final spaceAbove = math.max(0.0, anchorRect.top - gap - minTop);

  final openUp = estimatedHeight > spaceBelow && spaceAbove > spaceBelow;
  final maxHeight = math.max(80.0, openUp ? spaceAbove : spaceBelow);
  final effectiveHeight = math.min(estimatedHeight, maxHeight);
  final rawTop = openUp ? anchorRect.top - gap - effectiveHeight : belowStart;
  final top = rawTop
      .clamp(minTop, math.max(minTop, maxBottom - effectiveHeight))
      .toDouble();

  return (
    left: left,
    top: top,
    width: width,
    maxHeight: maxHeight,
    alignRight: alignRight,
    openUp: openUp,
  );
}

/// 在任意全局坐标处弹出轻盈右键/上下文菜单（自动避让屏幕边缘，桌面端右键书架/文件夹/章节必备）。
Future<T?> showCalmContextMenu<T>(
  BuildContext context, {
  required Offset globalPosition,
  required List<CalmPopupMenuEntry<T>> entries,
  double? menuWidth,
}) {
  final overlay = Overlay.of(context, rootOverlay: true);
  final overlayBox = overlay.context.findRenderObject() as RenderBox?;
  final overlaySize = overlayBox?.size ?? MediaQuery.sizeOf(context);
  final localPos = overlayBox != null
      ? overlayBox.globalToLocal(globalPosition)
      : globalPosition;
  final padding = MediaQuery.paddingOf(context);
  final c = context.calm;
  final desiredWidth = menuWidth ?? _measureMenuWidth(context, entries);

  final geo = _computeMenuGeometry(
    overlaySize: overlaySize,
    safePadding: padding,
    anchorRect: Rect.fromLTWH(localPos.dx, localPos.dy, 0, 0),
    desiredWidth: desiredWidth,
    estimatedHeight: _estimateMenuHeight(entries),
    gap: 0,
  );

  final completer = Completer<T?>();
  late OverlayEntry overlayEntry;

  void finish([T? result]) {
    if (!completer.isCompleted) {
      completer.complete(result);
    }
  }

  overlayEntry = OverlayEntry(
    builder: (_) => _CalmMenuPopupOverlay<T>(
      left: geo.left,
      top: geo.top,
      width: geo.width,
      maxHeight: geo.maxHeight,
      scaleAlignment: Alignment(
        geo.alignRight ? 1.0 : -1.0,
        geo.openUp ? 1.0 : -1.0,
      ),
      calm: c,
      entries: entries,
      onSelected: (value) => finish(value),
      onDismissed: () {
        finish();
        if (overlayEntry.mounted) {
          overlayEntry.remove();
        }
      },
    ),
  );

  overlay.insert(overlayEntry);
  return completer.future;
}

/// 轻盈动作弹出菜单（锚定触发按钮，自动按内容测宽并避让屏幕左右与上下边缘）。
class CalmPopupMenuButton<T> extends StatefulWidget {
  const CalmPopupMenuButton({
    super.key,
    required this.entries,
    required this.onSelected,
    required this.child,
    this.menuWidth,
  });

  final List<CalmPopupMenuEntry<T>> entries;
  final ValueChanged<T> onSelected;
  final Widget child;
  final double? menuWidth;

  @override
  State<CalmPopupMenuButton<T>> createState() => _CalmPopupMenuButtonState<T>();
}

class _CalmPopupMenuButtonState<T> extends State<CalmPopupMenuButton<T>> {
  final GlobalKey<_CalmMenuPopupOverlayState<T>> _overlayKey = GlobalKey();
  OverlayEntry? _entry;
  bool _open = false;

  void _removeEntryImmediately() {
    final entry = _entry;
    _entry = null;
    if (entry != null && entry.mounted) {
      entry.remove();
    }
    if (mounted && _open) {
      setState(() => _open = false);
    }
  }

  void _close() {
    final overlayState = _overlayKey.currentState;
    if (overlayState != null) {
      overlayState.dismiss();
    } else {
      _removeEntryImmediately();
    }
  }

  void _toggle() {
    if (_open) {
      _close();
      return;
    }
    final overlay = Overlay.of(context, rootOverlay: true);
    final overlayBox = overlay.context.findRenderObject() as RenderBox?;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;

    final overlaySize = overlayBox?.size ?? MediaQuery.sizeOf(context);
    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlayBox);
    final anchorRect = topLeft & box.size;
    final padding = MediaQuery.paddingOf(context);
    final c = context.calm;

    final desiredWidth =
        widget.menuWidth ?? _measureMenuWidth(context, widget.entries);
    final geo = _computeMenuGeometry(
      overlaySize: overlaySize,
      safePadding: padding,
      anchorRect: anchorRect,
      desiredWidth: desiredWidth,
      estimatedHeight: _estimateMenuHeight(widget.entries),
      gap: 6,
    );

    _entry = OverlayEntry(
      builder: (_) => _CalmMenuPopupOverlay<T>(
        key: _overlayKey,
        left: geo.left,
        top: geo.top,
        width: geo.width,
        maxHeight: geo.maxHeight,
        scaleAlignment: Alignment(
          geo.alignRight ? 1.0 : -1.0,
          geo.openUp ? 1.0 : -1.0,
        ),
        calm: c,
        entries: widget.entries,
        onSelected: (value) {
          widget.onSelected(value);
        },
        onDismissed: _removeEntryImmediately,
      ),
    );
    overlay.insert(_entry!);
    setState(() => _open = true);
  }

  @override
  void dispose() {
    final entry = _entry;
    _entry = null;
    if (entry != null && entry.mounted) {
      entry.remove();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggle,
        child: widget.child,
      ),
    );
  }
}

class _CalmMenuPopupOverlay<T> extends StatefulWidget {
  const _CalmMenuPopupOverlay({
    super.key,
    required this.left,
    required this.top,
    required this.width,
    required this.maxHeight,
    required this.scaleAlignment,
    required this.calm,
    required this.entries,
    required this.onSelected,
    required this.onDismissed,
  });

  final double left;
  final double top;
  final double width;
  final double maxHeight;
  final Alignment scaleAlignment;
  final CalmColors calm;
  final List<CalmPopupMenuEntry<T>> entries;
  final ValueChanged<T> onSelected;
  final VoidCallback onDismissed;

  @override
  State<_CalmMenuPopupOverlay<T>> createState() =>
      _CalmMenuPopupOverlayState<T>();
}

class _CalmMenuPopupOverlayState<T> extends State<_CalmMenuPopupOverlay<T>>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 160),
    reverseDuration: const Duration(milliseconds: 110),
  );
  late final Animation<double> _opacity = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeIn,
  );
  late final Animation<double> _scale = Tween<double>(begin: 0.94, end: 1.0)
      .animate(
        CurvedAnimation(
          parent: _controller,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeIn,
        ),
      );

  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _controller.forward();
  }

  Future<void> dismiss() async {
    if (_closing) return;
    _closing = true;
    try {
      await _controller.reverse();
    } catch (_) {
      // 已被 dispose 时忽略。
    }
    if (mounted) {
      widget.onDismissed();
    }
  }

  void _handleSelect(T value) {
    if (_closing) return;
    widget.onSelected(value);
    unawaited(dismiss());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.calm;
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): dismiss},
      child: Focus(
        autofocus: true,
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: dismiss,
                onSecondaryTap: dismiss,
              ),
            ),
            Positioned(
              left: widget.left,
              top: widget.top,
              child: FadeTransition(
                opacity: _opacity,
                child: ScaleTransition(
                  scale: _scale,
                  alignment: widget.scaleAlignment,
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      width: widget.width,
                      constraints: BoxConstraints(maxHeight: widget.maxHeight),
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: c.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: c.border),
                        boxShadow: c.shadowMd,
                      ),
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final entry in widget.entries)
                              if (entry.isDivider)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 4,
                                  ),
                                  child: Divider(height: 1, color: c.border),
                                )
                              else
                                _MenuActionRow(
                                  label: entry.label!,
                                  icon: entry.icon,
                                  shortcut: entry.shortcut,
                                  danger: entry.danger,
                                  calm: c,
                                  onTap: () => _handleSelect(entry.value as T),
                                ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuActionRow extends StatefulWidget {
  const _MenuActionRow({
    required this.label,
    required this.danger,
    required this.calm,
    required this.onTap,
    this.icon,
    this.shortcut,
  });

  final String label;
  final IconData? icon;
  final String? shortcut;
  final bool danger;
  final CalmColors calm;
  final VoidCallback onTap;

  @override
  State<_MenuActionRow> createState() => _MenuActionRowState();
}

class _MenuActionRowState extends State<_MenuActionRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.calm;
    final fg = widget.danger ? c.danger : c.text;
    final bg = _hovered
        ? (widget.danger ? c.dangerSoft : c.surface2)
        : Colors.transparent;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (widget.icon != null) ...[
                Icon(
                  widget.icon,
                  size: 15,
                  color: widget.danger ? c.danger : c.text2,
                ),
                const SizedBox(width: 9),
              ],
              Expanded(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textHeightBehavior: kCalmTextHeightBehavior,
                  strutStyle: calmStrut(12),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: widget.danger
                        ? FontWeight.w500
                        : FontWeight.w400,
                    color: fg,
                    height: 1.2,
                    leadingDistribution: TextLeadingDistribution.even,
                  ),
                ),
              ),
              if (widget.shortcut != null) ...[
                const SizedBox(width: 8),
                Text(
                  widget.shortcut!,
                  style: TextStyle(fontSize: 10, color: c.text3),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 多选态底部悬浮批量操作胶囊栏。
class CalmBatchActionBar extends StatelessWidget {
  const CalmBatchActionBar({
    super.key,
    required this.selectedCount,
    required this.actions,
    this.onClose,
  });

  final int selectedCount;
  final List<Widget> actions;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.borderStrong),
        boxShadow: c.shadowMd,
      ),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              '已选 $selectedCount 项',
              textHeightBehavior: kCalmTextHeightBehavior,
              strutStyle: calmStrut(12),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: c.accent,
                height: 1.2,
                leadingDistribution: TextLeadingDistribution.even,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          Container(width: 1, height: 16, color: c.borderStrong),
          ...actions,
          if (onClose != null)
            CalmIconButton(
              icon: Icons.close_rounded,
              size: 26,
              iconSize: 14,
              onPressed: onClose,
            ),
        ],
      ),
    );
  }
}

/// 轻盈胶囊悬浮按钮 & 可展开紧凑菜单卡（替代零散飘浮的小圆球 SpeedDial）。
///
/// 展开后点击外部空白处或按 Esc 均可自动收起，并阻止误触下方列表项。
class CalmSpeedDial extends StatefulWidget {
  const CalmSpeedDial({
    super.key,
    required this.actions,
    this.label = '快捷操作',
    this.initiallyOpen = false,
    this.alignLeft = false,
  });

  final List<({String label, IconData icon, VoidCallback onTap})> actions;
  final String label;
  final bool initiallyOpen;
  final bool alignLeft;

  @override
  State<CalmSpeedDial> createState() => _CalmSpeedDialState();
}

class _CalmSpeedDialState extends State<CalmSpeedDial> {
  late bool _open = widget.initiallyOpen;

  void _close() {
    if (_open && mounted) {
      setState(() => _open = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    final availableMax = math.max(120.0, MediaQuery.sizeOf(context).width - 32);
    final deckWidth = _measureMenuWidth<int>(
      context,
      [
        for (var i = 0; i < widget.actions.length; i++)
          CalmPopupMenuEntry<int>.item(
            value: i,
            label: widget.actions[i].label,
            icon: widget.actions[i].icon,
          ),
      ],
      minWidth: 120,
      maxWidth: math.min(240.0, availableMax),
    );
    return TapRegion(
      consumeOutsideTaps: _open,
      onTapOutside: (_) => _close(),
      child: CallbackShortcuts(
        bindings: _open
            ? {const SingleActivator(LogicalKeyboardKey.escape): _close}
            : const {},
        child: Focus(
          autofocus: _open,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: widget.alignLeft
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.end,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 0.94, end: 1.0).animate(anim),
                    alignment: widget.alignLeft
                        ? Alignment.bottomLeft
                        : Alignment.bottomRight,
                    child: child,
                  ),
                ),
                child: _open
                    ? Container(
                        key: const ValueKey('deck'),
                        width: deckWidth,
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: c.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: c.border),
                          boxShadow: c.shadowMd,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final a in widget.actions)
                              _MenuActionRow(
                                label: a.label,
                                icon: a.icon,
                                danger: false,
                                calm: c,
                                onTap: () {
                                  setState(() => _open = false);
                                  a.onTap();
                                },
                              ),
                          ],
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              CalmButton(
                label: _open ? '收起' : widget.label,
                icon: _open ? Icons.close_rounded : Icons.add_rounded,
                variant: CalmButtonVariant.primary,
                size: CalmButtonSize.md,
                onPressed: () => setState(() => _open = !_open),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
