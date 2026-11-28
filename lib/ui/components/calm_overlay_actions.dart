import 'dart:async';
import 'dart:math' as math;

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

/// 在任意全局坐标处弹出轻盈右键/上下文菜单（自动避让屏幕边缘，桌面端右键书架/文件夹/章节必备）。
Future<T?> showCalmContextMenu<T>(
  BuildContext context, {
  required Offset globalPosition,
  required List<CalmPopupMenuEntry<T>> entries,
  double menuWidth = 204,
}) {
  final overlay = Overlay.of(context);
  final media = MediaQuery.sizeOf(context);
  final padding = MediaQuery.paddingOf(context);
  final c = context.calm;

  // 估算菜单高度用于防出屏翻转
  double estimatedHeight = 14;
  for (final e in entries) {
    estimatedHeight += e.isDivider ? 9 : 34;
  }

  const margin = 10.0;
  final left = globalPosition.dx
      .clamp(
        padding.left + margin,
        math.max(
          padding.left + margin,
          media.width - padding.right - menuWidth - margin,
        ),
      )
      .toDouble();
  final fitsBelow =
      globalPosition.dy + estimatedHeight <=
      media.height - padding.bottom - margin;
  final rawTop = fitsBelow
      ? globalPosition.dy
      : globalPosition.dy - estimatedHeight;
  final top = rawTop
      .clamp(
        padding.top + margin,
        math.max(
          padding.top + margin,
          media.height - padding.bottom - estimatedHeight - margin,
        ),
      )
      .toDouble();

  final completer = Completer<T?>();
  late OverlayEntry overlayEntry;

  void finish([T? result]) {
    if (!completer.isCompleted) {
      overlayEntry.remove();
      completer.complete(result);
    }
  }

  overlayEntry = OverlayEntry(
    builder: (_) => Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => finish(),
            onSecondaryTap: () => finish(),
          ),
        ),
        Positioned(
          left: left,
          top: top,
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: menuWidth,
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
                  for (final entry in entries)
                    if (entry.isDivider)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Divider(height: 1, color: c.border),
                      )
                    else
                      _MenuActionRow(
                        label: entry.label!,
                        icon: entry.icon,
                        shortcut: entry.shortcut,
                        danger: entry.danger,
                        calm: c,
                        onTap: () => finish(entry.value as T),
                      ),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );

  overlay.insert(overlayEntry);
  return completer.future;
}

/// 轻盈动作弹出菜单（桌面右键 / 点击触发均适用）。
class CalmPopupMenuButton<T> extends StatefulWidget {
  const CalmPopupMenuButton({
    super.key,
    required this.entries,
    required this.onSelected,
    required this.child,
    this.menuWidth = 204,
  });

  final List<CalmPopupMenuEntry<T>> entries;
  final ValueChanged<T> onSelected;
  final Widget child;
  final double menuWidth;

  @override
  State<CalmPopupMenuButton<T>> createState() => _CalmPopupMenuButtonState<T>();
}

class _CalmPopupMenuButtonState<T> extends State<CalmPopupMenuButton<T>> {
  final LayerLink _link = LayerLink();
  OverlayEntry? _entry;
  bool _open = false;

  void _close() {
    _entry?.remove();
    _entry = null;
    if (mounted) setState(() => _open = false);
  }

  void _toggle() {
    if (_open) {
      _close();
      return;
    }
    final overlay = Overlay.of(context);
    final box = context.findRenderObject() as RenderBox?;
    final c = context.calm;

    _entry = OverlayEntry(
      builder: (_) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _close,
              onSecondaryTap: _close,
            ),
          ),
          CompositedTransformFollower(
            link: _link,
            showWhenUnlinked: false,
            offset: Offset(0, (box?.size.height ?? 34) + 6),
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: widget.menuWidth,
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
                    for (final entry in widget.entries)
                      if (entry.isDivider)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Divider(height: 1, color: c.border),
                        )
                      else
                        _MenuActionRow(
                          label: entry.label!,
                          icon: entry.icon,
                          shortcut: entry.shortcut,
                          danger: entry.danger,
                          calm: c,
                          onTap: () {
                            final v = entry.value as T;
                            _close();
                            widget.onSelected(v);
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
    return CompositedTransformTarget(
      link: _link,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggle,
        child: widget.child,
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
class CalmSpeedDial extends StatefulWidget {
  const CalmSpeedDial({
    super.key,
    required this.actions,
    this.label = '快捷操作',
    this.initiallyOpen = false,
  });

  final List<({String label, IconData icon, VoidCallback onTap})> actions;
  final String label;
  final bool initiallyOpen;

  @override
  State<CalmSpeedDial> createState() => _CalmSpeedDialState();
}

class _CalmSpeedDialState extends State<CalmSpeedDial> {
  late bool _open = widget.initiallyOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.94, end: 1.0).animate(anim),
              alignment: Alignment.bottomRight,
              child: child,
            ),
          ),
          child: _open
              ? Container(
                  key: const ValueKey('deck'),
                  width: 180,
                  margin: const EdgeInsets.only(bottom: 8),
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
    );
  }
}
