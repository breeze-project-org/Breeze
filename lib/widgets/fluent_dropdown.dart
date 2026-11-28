import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/ui/ui.dart';

// 视觉规格参考 WinUI 3 / Fluent UI 2 的 ComboBox：
// - 菜单面板 8px 内边距 + 圆角，选项行高由内容决定（单行 40）；
// - 选中项只用左侧 3px 主色竖条 + 浅色底，不用 Material 的对勾；
// - 菜单按锚点矩形定位，上下空间不足时自动翻转并压缩高度；
// - 键盘 ↑↓/Home/End 移动高亮，Enter/Space 选中，Esc 关闭。

const double _kMenuGap = 6;
const double _kScreenMargin = 8;
const double _kPanelPadding = 8;
const double _kPanelBorderWidth = 1;
const double _kItemHPadding = 12;
const double _kItemVPadding = 10;
const double _kItemGap = 12;
const double _kIndicatorWidth = 3;
const double _kLeadingSize = 24;
const double _kTrailingSize = 24;
const double _kMinTextHeight = 20;
const double _kMaxMenuWidth = 340;
const double _kMaxMenuHeight = 320;
const Duration _kMenuAnimationDuration = Duration(milliseconds: 220);
const Duration _kItemAnimationDuration = Duration(milliseconds: 120);

/// A single entry in a fluent popup menu.
class FluentPopupMenuItem<T> {
  const FluentPopupMenuItem({
    required this.value,
    this.leading,
    required this.title,
    this.trailing,
    this.enabled = true,
  });

  /// The value returned when this item is selected.
  final T value;

  /// Optional widget displayed at the start of the item (typically an icon).
  final Widget? leading;

  /// The main label of the item.
  final Widget title;

  /// Optional widget displayed at the end of the item.
  final Widget? trailing;

  /// Whether the item can be selected.
  final bool enabled;
}

/// Internal representation of a menu entry, used by the shared overlay.
class _MenuEntry<T> {
  const _MenuEntry({
    required this.value,
    this.leading,
    required this.title,
    this.trailing,
    this.enabled = true,
    this.isSelected = false,
  });

  final T value;
  final Widget? leading;
  final Widget title;
  final Widget? trailing;
  final bool enabled;
  final bool isSelected;
}

/// Measured geometry of a menu: panel width, per-item heights and their
/// offsets. Computed once when the menu opens so that layout, scrolling and
/// hit areas all agree on the same numbers.
class _MenuMetrics {
  _MenuMetrics({
    required this.width,
    required this.itemHeights,
    required this.selectedIndex,
  }) : itemOffsets = _prefixSums(itemHeights),
       contentHeight = itemHeights.fold(0.0, (sum, height) => sum + height);

  final double width;
  final List<double> itemHeights;

  /// Top offset of every item, relative to the first item.
  final List<double> itemOffsets;
  final double contentHeight;
  final int? selectedIndex;

  /// Panel height for the given height budget: content-sized, capped.
  /// The panel border sits outside the list, so it must be added as well.
  double panelHeight(double maxHeight) => math.min(
    maxHeight,
    contentHeight + (_kPanelPadding + _kPanelBorderWidth) * 2,
  );
}

List<double> _prefixSums(List<double> values) {
  final result = <double>[];
  var sum = 0.0;
  for (final value in values) {
    result.add(sum);
    sum += value;
  }
  return result;
}

/// Where the menu is placed relative to its anchor, in global coordinates.
class _MenuPlacement {
  const _MenuPlacement({
    required this.anchor,
    required this.bounds,
    required this.maxHeight,
    required this.openUp,
    required this.alignRight,
  });

  final Rect anchor;

  /// Usable screen area (safe padding + margin) the menu must stay inside.
  final Rect bounds;
  final double maxHeight;
  final bool openUp;
  final bool alignRight;

  @override
  bool operator ==(Object other) =>
      other is _MenuPlacement &&
      other.anchor == anchor &&
      other.bounds == bounds &&
      other.maxHeight == maxHeight &&
      other.openUp == openUp &&
      other.alignRight == alignRight;

  @override
  int get hashCode =>
      Object.hash(anchor, bounds, maxHeight, openUp, alignRight);
}

/// Converts a widget box into the coordinate space of [overlayBox].
///
/// Overlay children are positioned relative to the overlay, which is not
/// necessarily at the screen origin: on desktop `MaterialApp.builder` puts the
/// custom title bar above the Navigator, so the overlay starts below it.
/// Global coordinates would shift every menu down by that offset.
Rect _anchorInOverlay(RenderBox box, RenderBox overlayBox) =>
    box.localToGlobal(Offset.zero, ancestor: overlayBox) & box.size;

/// Resolves the menu placement for [anchor] (already in overlay coordinates),
/// preferring the side with more room and never exceeding the screen bounds.
_MenuPlacement _resolvePlacement(
  BuildContext context,
  Rect anchor,
  double menuWidth,
  RenderBox overlayBox,
) {
  final media = MediaQuery.of(context);
  final padding = media.padding;
  // 安全区是全局坐标，先换算到浮层坐标再和锚点比较。
  final bounds = Rect.fromLTRB(
    padding.left + _kScreenMargin,
    padding.top + _kScreenMargin,
    media.size.width - padding.right - _kScreenMargin,
    media.size.height - padding.bottom - _kScreenMargin,
  ).shift(-overlayBox.localToGlobal(Offset.zero));

  final spaceBelow = bounds.bottom - anchor.bottom - _kMenuGap;
  final spaceAbove = anchor.top - bounds.top - _kMenuGap;
  final openUp = spaceBelow < _kMaxMenuHeight && spaceAbove > spaceBelow;
  final available = openUp ? spaceAbove : spaceBelow;

  return _MenuPlacement(
    anchor: anchor,
    bounds: bounds,
    maxHeight: math.max(1.0, math.min(_kMaxMenuHeight, available)),
    openUp: openUp,
    alignRight: anchor.left + menuWidth > bounds.right,
  );
}

/// Measures label widths/heights so the panel can be laid out without
/// shrink-wrapping (a 265-entry list must not build every row on open).
_MenuMetrics _measureMenu<T>(
  BuildContext context,
  List<_MenuEntry<T>> entries, {
  required double minWidth,
}) {
  final theme = Theme.of(context);
  final textStyle =
      theme.textTheme.bodyMedium ?? DefaultTextStyle.of(context).style;
  final textScaler = MediaQuery.textScalerOf(context);
  final textDirection = Directionality.of(context);

  final leadingWidth = entries.any((entry) => entry.leading != null)
      ? _kLeadingSize + _kItemGap
      : 0.0;
  final trailingWidth = entries.any((entry) => entry.trailing != null)
      ? _kItemGap + _kTrailingSize
      : 0.0;
  // 面板内边距 + 边框 + 选项左右内边距 + 前后插槽。
  final chrome =
      (_kPanelPadding + _kPanelBorderWidth) * 2 +
      _kItemHPadding * 2 +
      leadingWidth +
      trailingWidth;

  final labels = <String>[];
  final naturalHeights = <double>[];
  var maxTextWidth = 0.0;
  for (final entry in entries) {
    final label = _extractText(entry.title) ?? '';
    labels.add(label);
    final painter = TextPainter(
      text: TextSpan(text: label, style: textStyle),
      textDirection: textDirection,
      textScaler: textScaler,
    )..layout();
    maxTextWidth = math.max(maxTextWidth, painter.width);
    naturalHeights.add(painter.height);
  }

  final screenWidth = math.max(
    1.0,
    MediaQuery.sizeOf(context).width - _kScreenMargin * 2,
  );
  // +2 是文本测量与真实渲染之间的缓冲，避免刚好卡在折行边界。
  final width = math.min(
    screenWidth,
    (maxTextWidth + chrome + 2)
        .clamp(math.min(minWidth, screenWidth), _kMaxMenuWidth)
        .toDouble(),
  );
  final textWidth = math.max(1.0, width - chrome);

  final needsWrap = maxTextWidth > textWidth + 0.5;
  final itemHeights = <double>[];
  for (var i = 0; i < entries.length; i++) {
    var textHeight = naturalHeights[i];
    if (needsWrap && labels[i].isNotEmpty) {
      final painter = TextPainter(
        text: TextSpan(text: labels[i], style: textStyle),
        textDirection: textDirection,
        textScaler: textScaler,
      )..layout(maxWidth: textWidth);
      textHeight = painter.height;
    }
    itemHeights.add(math.max(_kMinTextHeight, textHeight) + _kItemVPadding * 2);
  }

  var selectedIndex = -1;
  for (var i = 0; i < entries.length; i++) {
    if (entries[i].isSelected) {
      selectedIndex = i;
      break;
    }
  }

  return _MenuMetrics(
    width: width,
    itemHeights: itemHeights,
    selectedIndex: selectedIndex < 0 ? null : selectedIndex,
  );
}

String? _extractText(Widget widget) {
  if (widget is Text) {
    return widget.data ?? widget.textSpan?.toPlainText();
  }
  if (widget is RichText) {
    return widget.text.toPlainText();
  }
  return null;
}

/// Positions the panel against the anchor inside the screen bounds.
class _MenuLayout extends SingleChildLayoutDelegate {
  const _MenuLayout({required this.placement, required this.width});

  final _MenuPlacement placement;
  final double width;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return BoxConstraints(
      minWidth: width,
      maxWidth: width,
      maxHeight: placement.maxHeight,
    ).enforce(constraints);
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final bounds = placement.bounds;
    final dx = placement.alignRight
        ? placement.anchor.right - childSize.width
        : placement.anchor.left;
    final dy = placement.openUp
        ? placement.anchor.top - _kMenuGap - childSize.height
        : placement.anchor.bottom + _kMenuGap;
    return Offset(
      dx
          .clamp(
            bounds.left,
            math.max(bounds.left, bounds.right - childSize.width),
          )
          .toDouble(),
      dy
          .clamp(
            bounds.top,
            math.max(bounds.top, bounds.bottom - childSize.height),
          )
          .toDouble(),
    );
  }

  @override
  bool shouldRelayout(_MenuLayout oldDelegate) =>
      oldDelegate.placement != placement || oldDelegate.width != width;
}

/// Menu scrolling should feel native: no glow, no scrollbar, no bounce.
class _MenuScrollBehavior extends ScrollBehavior {
  const _MenuScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
    ...super.dragDevices,
    PointerDeviceKind.mouse,
  };

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const ClampingScrollPhysics();
}

/// The menu surface: rows, selection bar, hover/keyboard highlight and
/// keyboard navigation.
class _MenuPanel<T> extends StatefulWidget {
  const _MenuPanel({
    required this.metrics,
    required this.entries,
    required this.maxHeight,
    required this.selectionIndicator,
    required this.onSelected,
    required this.onDismiss,
    this.panelColor,
    this.selectedColor,
    this.hoverColor,
    this.panelBorderRadius = 16,
    this.itemBorderRadius = 10,
  });

  final _MenuMetrics metrics;
  final List<_MenuEntry<T>> entries;
  final double maxHeight;

  /// Whether the selected row shows the fluent accent bar. Popup menus
  /// (context menus) have no selection, so they pass `false`.
  final bool selectionIndicator;
  final ValueChanged<T> onSelected;
  final VoidCallback onDismiss;
  final Color? panelColor;
  final Color? selectedColor;
  final Color? hoverColor;
  final double panelBorderRadius;
  final double itemBorderRadius;

  @override
  State<_MenuPanel<T>> createState() => _MenuPanelState<T>();
}

class _MenuPanelState<T> extends State<_MenuPanel<T>> {
  late final ScrollController _scrollController;
  final FocusNode _focusNode = FocusNode(debugLabel: 'FluentMenuPanel');
  int? _activeIndex;

  @override
  void initState() {
    super.initState();
    _activeIndex = widget.metrics.selectedIndex;
    _scrollController = ScrollController(initialScrollOffset: _initialOffset());
    // 菜单挂在 OverlayEntry 里，是路由 FocusScope 的兄弟节点而不是子节点，
    // 所以 autofocus 会被 FocusManager 丢弃（scope.focusedChild 非空）。
    // 必须等首帧挂载完成后显式请求焦点，键盘导航才可用。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// Centers the selected row in the viewport, clamped to the scroll range.
  double _initialOffset() {
    final metrics = widget.metrics;
    final index = metrics.selectedIndex;
    if (index == null) return 0;
    final viewport = math.max(
      1.0,
      metrics.panelHeight(widget.maxHeight) -
          (_kPanelPadding + _kPanelBorderWidth) * 2,
    );
    final maxOffset = math.max(0.0, metrics.contentHeight - viewport);
    final target =
        metrics.itemOffsets[index] +
        metrics.itemHeights[index] / 2 -
        viewport / 2;
    return target.clamp(0.0, maxOffset);
  }

  void _setActive(int index) {
    if (_activeIndex == index) return;
    setState(() => _activeIndex = index);
    _ensureVisible(index);
  }

  void _moveActive(int delta) {
    final count = widget.entries.length;
    if (count == 0) return;
    var index = _activeIndex ?? (delta > 0 ? -1 : 0);
    for (var step = 0; step < count; step++) {
      index = (index + delta) % count;
      if (index < 0) index += count;
      if (widget.entries[index].enabled) {
        _setActive(index);
        return;
      }
    }
  }

  void _activateEdge({required bool fromStart}) {
    final count = widget.entries.length;
    for (var step = 0; step < count; step++) {
      final index = fromStart ? step : count - 1 - step;
      if (widget.entries[index].enabled) {
        _setActive(index);
        return;
      }
    }
  }

  void _ensureVisible(int index) {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final top = _kPanelPadding + widget.metrics.itemOffsets[index];
    final bottom = top + widget.metrics.itemHeights[index];
    final viewportTop = position.pixels;
    final viewportBottom = viewportTop + position.viewportDimension;
    if (top < viewportTop) {
      _scrollController.jumpTo(
        math.max(position.minScrollExtent, top - _kPanelPadding),
      );
    } else if (bottom > viewportBottom) {
      _scrollController.jumpTo(
        math.min(
          position.maxScrollExtent,
          bottom - position.viewportDimension + _kPanelPadding,
        ),
      );
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      widget.onDismiss();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _moveActive(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _moveActive(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.home) {
      _activateEdge(fromStart: true);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.end) {
      _activateEdge(fromStart: false);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.space) {
      final index = _activeIndex;
      if (index == null) return KeyEventResult.ignored;
      final entry = widget.entries[index];
      if (!entry.enabled) return KeyEventResult.ignored;
      widget.onSelected(entry.value);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    // 浮层比页面亮一档（深色）/ 纯白（浅色），与 CalmUI 的浮空卡片一致，
    // 避免面板和背景糊成一片。
    final panelColor = widget.panelColor ?? c.surface;
    final selectedColor = widget.selectedColor ?? c.accentSoft;
    final hoverColor = widget.hoverColor ?? c.surface2;

    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _handleKeyEvent,
      child: Material(
        type: MaterialType.transparency,
        borderRadius: BorderRadius.circular(widget.panelBorderRadius),
        child: Container(
          width: widget.metrics.width,
          height: widget.metrics.panelHeight(widget.maxHeight),
          decoration: BoxDecoration(
            color: panelColor,
            borderRadius: BorderRadius.circular(widget.panelBorderRadius),
            border: Border.all(color: c.border, width: _kPanelBorderWidth),
            boxShadow: c.shadowMd,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(widget.panelBorderRadius),
            child: ScrollConfiguration(
              behavior: const _MenuScrollBehavior(),
              child: ListView.builder(
                controller: _scrollController,
                primary: false,
                padding: const EdgeInsets.all(_kPanelPadding),
                itemCount: widget.entries.length,
                itemExtentBuilder: (index, dimensions) =>
                    widget.metrics.itemHeights[index],
                itemBuilder: (context, index) =>
                    _buildItem(context, index, c, selectedColor, hoverColor),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildItem(
    BuildContext context,
    int index,
    CalmColors c,
    Color selectedColor,
    Color hoverColor,
  ) {
    final entry = widget.entries[index];
    final isActive = _activeIndex == index;
    final isSelected = entry.isSelected;
    final background = isSelected
        ? selectedColor
        : isActive
        ? hoverColor
        : Colors.transparent;
    final disabledColor = c.text3;
    final iconColor = entry.enabled ? c.text2 : disabledColor;

    return Semantics(
      button: true,
      enabled: entry.enabled,
      selected: isSelected,
      child: MouseRegion(
        cursor: entry.enabled ? SystemMouseCursors.click : MouseCursor.defer,
        onEnter: entry.enabled ? (_) => _setActive(index) : null,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: entry.enabled ? () => widget.onSelected(entry.value) : null,
          child: Stack(
            fit: StackFit.passthrough,
            children: [
              AnimatedContainer(
                duration: _kItemAnimationDuration,
                curve: Curves.easeOut,
                padding: const EdgeInsets.symmetric(
                  horizontal: _kItemHPadding,
                  vertical: _kItemVPadding,
                ),
                decoration: BoxDecoration(
                  color: entry.enabled ? background : Colors.transparent,
                  borderRadius: BorderRadius.circular(widget.itemBorderRadius),
                ),
                child: Row(
                  children: [
                    if (entry.leading != null) ...[
                      IconTheme.merge(
                        data: IconThemeData(color: iconColor),
                        child: entry.leading!,
                      ),
                      const SizedBox(width: _kItemGap),
                    ],
                    Flexible(
                      child: DefaultTextStyle.merge(
                        style: TextStyle(
                          color: entry.enabled ? c.text : disabledColor,
                        ),
                        child: entry.title,
                      ),
                    ),
                    if (entry.trailing != null) ...[
                      const SizedBox(width: _kItemGap),
                      IconTheme.merge(
                        data: IconThemeData(color: iconColor),
                        child: entry.trailing!,
                      ),
                    ],
                  ],
                ),
              ),
              if (widget.selectionIndicator)
                PositionedDirectional(
                  start: 0,
                  top: 8,
                  bottom: 8,
                  child: AnimatedContainer(
                    duration: _kItemAnimationDuration,
                    curve: Curves.easeOut,
                    width: _kIndicatorWidth,
                    decoration: BoxDecoration(
                      color: isSelected ? c.accent : Colors.transparent,
                      borderRadius: BorderRadius.circular(_kIndicatorWidth),
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

/// Shared overlay: modal barrier + anchored, animated menu panel.
class _MenuOverlay<T> extends StatelessWidget {
  const _MenuOverlay({
    required this.placement,
    required this.metrics,
    required this.entries,
    required this.selectionIndicator,
    required this.onSelected,
    required this.onDismiss,
    required this.scaleAnimation,
    required this.opacityAnimation,
    this.panelColor,
    this.selectedColor,
    this.hoverColor,
    this.panelBorderRadius = 16,
    this.itemBorderRadius = 10,
  });

  final _MenuPlacement placement;
  final _MenuMetrics metrics;
  final List<_MenuEntry<T>> entries;
  final bool selectionIndicator;
  final ValueChanged<T> onSelected;
  final VoidCallback onDismiss;
  final Animation<double> scaleAnimation;
  final Animation<double> opacityAnimation;
  final Color? panelColor;
  final Color? selectedColor;
  final Color? hoverColor;
  final double panelBorderRadius;
  final double itemBorderRadius;

  @override
  Widget build(BuildContext context) {
    final alignment = placement.openUp
        ? (placement.alignRight ? Alignment.bottomRight : Alignment.bottomLeft)
        : (placement.alignRight ? Alignment.topRight : Alignment.topLeft);

    return Stack(
      children: [
        // 全屏遮罩：吞掉点击与拖动，避免菜单打开时滚动/点击到下层页面。
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onDismiss,
            onLongPress: onDismiss,
            onSecondaryTapDown: (_) => onDismiss(),
            onPanStart: (_) {},
          ),
        ),
        CustomSingleChildLayout(
          delegate: _MenuLayout(placement: placement, width: metrics.width),
          child: FadeTransition(
            opacity: opacityAnimation,
            child: ScaleTransition(
              alignment: alignment,
              scale: scaleAnimation,
              child: _MenuPanel<T>(
                metrics: metrics,
                entries: entries,
                maxHeight: placement.maxHeight,
                selectionIndicator: selectionIndicator,
                onSelected: onSelected,
                onDismiss: onDismiss,
                panelColor: panelColor,
                selectedColor: selectedColor,
                hoverColor: hoverColor,
                panelBorderRadius: panelBorderRadius,
                itemBorderRadius: itemBorderRadius,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A button that displays a fluent-styled popup menu when tapped.
///
/// This is intended as a drop-in replacement for [PopupMenuButton] with the
/// same visual style as [FluentDropdown], but without any selected-value
/// highlighting inside the menu.
class FluentPopupMenuButton<T> extends StatefulWidget {
  const FluentPopupMenuButton({
    super.key,
    required this.itemBuilder,
    this.onSelected,
    this.child,
    this.icon,
    this.tooltip,
    this.enabled = true,
  });

  /// Called to build the list of menu items when the menu is opened.
  final List<FluentPopupMenuItem<T>> Function(BuildContext context) itemBuilder;

  /// Called when the user selects an item.
  final ValueChanged<T>? onSelected;

  /// The widget used as the tappable trigger. Either [child] or [icon] must
  /// be provided.
  final Widget? child;

  /// Convenience property to use an icon as the trigger. Either [child] or
  /// [icon] must be provided.
  final Widget? icon;

  /// Tooltip shown on long press / hover.
  final String? tooltip;

  /// Whether the button can be pressed.
  final bool enabled;

  @override
  State<FluentPopupMenuButton<T>> createState() =>
      _FluentPopupMenuButtonState<T>();
}

class _FluentPopupMenuButtonState<T> extends State<FluentPopupMenuButton<T>>
    with SingleTickerProviderStateMixin {
  OverlayEntry? _overlayEntry;
  bool _isOpen = false;
  FocusNode? _previousFocus;

  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: _kMenuAnimationDuration,
      vsync: this,
    );
    _scaleAnimation = Tween<double>(
      begin: 0.92,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _opacityAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    _controller.stop();
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    if (!mounted) return;
    if (_isOpen) {
      _close();
    } else {
      _open();
    }
  }

  void _open() {
    final items = widget.itemBuilder(context);
    if (items.isEmpty) return;
    final entries = items
        .map(
          (item) => _MenuEntry<T>(
            value: item.value,
            leading: item.leading,
            title: item.title,
            trailing: item.trailing,
            enabled: item.enabled,
          ),
        )
        .toList();

    final renderBox = context.findRenderObject() as RenderBox;
    final overlay = Overlay.of(context);
    final overlayBox = overlay.context.findRenderObject() as RenderBox;
    final anchor = _anchorInOverlay(renderBox, overlayBox);
    final metrics = _measureMenu(
      context,
      entries,
      minWidth: renderBox.size.width,
    );
    _previousFocus = FocusManager.instance.primaryFocus;

    _overlayEntry = OverlayEntry(
      builder: (context) => _MenuOverlay<T>(
        placement: _resolvePlacement(
          context,
          anchor,
          metrics.width,
          overlayBox,
        ),
        metrics: metrics,
        entries: entries,
        selectionIndicator: false,
        onSelected: (value) {
          _close(onComplete: () => widget.onSelected?.call(value));
        },
        onDismiss: _close,
        scaleAnimation: _scaleAnimation,
        opacityAnimation: _opacityAnimation,
      ),
    );

    overlay.insert(_overlayEntry!);
    _controller.forward(from: 0);
    setState(() => _isOpen = true);
  }

  void _close({VoidCallback? onComplete}) {
    if (!_isOpen || !mounted) return;
    setState(() => _isOpen = false);
    _controller.reverse().then((_) {
      if (!mounted) {
        onComplete?.call();
        return;
      }
      _overlayEntry?.remove();
      _overlayEntry = null;
      setState(() {});
      // 先还原焦点再回调 onComplete：onChanged 可能触发重建并销毁触发器，
      // 那时再去 requestFocus 会作用在已释放的节点上。
      final previousFocus = _previousFocus;
      _previousFocus = null;
      if (previousFocus != null && previousFocus.canRequestFocus) {
        previousFocus.requestFocus();
      }
      onComplete?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    Widget trigger;
    if (widget.child != null) {
      trigger = InkWell(
        onTap: widget.enabled ? _toggle : null,
        borderRadius: BorderRadius.circular(8),
        child: widget.child,
      );
    } else {
      trigger = IconButton(
        icon: widget.icon ?? const Icon(Icons.more_vert),
        tooltip: widget.tooltip,
        onPressed: widget.enabled ? _toggle : null,
      );
    }

    return trigger;
  }
}

/// A Fluent UI-style dropdown button.
///
/// The trigger looks like a bordered input box with hover/pressed/focus
/// states. Tapping it opens an overlay menu with rounded corners, a border,
/// and a scale + fade animation. The selected row is marked by a 3px accent
/// bar on the left (no Material checkmark). The menu flips above the trigger
/// and shrinks when there is not enough room, and supports keyboard
/// navigation (arrows, Home/End, Enter/Space, Esc).
class FluentDropdown<T> extends StatefulWidget {
  const FluentDropdown({
    super.key,
    required this.value,
    required this.displayValue,
    required this.items,
    required this.onChanged,
    this.panelColor,
    this.selectedColor,
    this.hoverColor,
    this.panelBorderRadius = 16,
    this.itemBorderRadius = 10,
  });

  /// Currently selected value.
  final T value;

  /// Text displayed in the trigger button.
  final String displayValue;

  /// Map of selectable values to their display labels.
  final Map<T, String> items;

  /// Called when the user selects a different value. `null` disables the
  /// dropdown.
  final ValueChanged<T>? onChanged;

  /// Menu panel background. Defaults to the theme surface color.
  final Color? panelColor;

  /// Selected item background. Defaults to a translucent primary container.
  final Color? selectedColor;

  /// Hovered item background. Defaults to a lighter translucent primary container.
  final Color? hoverColor;

  /// Menu panel corner radius.
  final double panelBorderRadius;

  /// Menu item corner radius.
  final double itemBorderRadius;

  @override
  State<FluentDropdown<T>> createState() => _FluentDropdownState<T>();
}

class _FluentDropdownState<T> extends State<FluentDropdown<T>>
    with SingleTickerProviderStateMixin {
  OverlayEntry? _overlayEntry;
  bool _isOpen = false;
  bool _isHovered = false;
  bool _isPressed = false;
  bool _isFocused = false;
  FocusNode? _previousFocus;

  final FocusNode _triggerFocus = FocusNode(debugLabel: 'FluentDropdown');

  // 坑：AnimationController 必须在 initState() 里立刻创建，不能懒加载。
  // 因为 OverlayEntry 的回调可能在 widget 已经被 deactivated 之后触发，
  // 如果这时第一次访问 _controller 才去创建，会尝试读取 TickerMode / MediaQuery
  // 等 InheritedWidget 祖先，触发 "Looking up a deactivated widget's ancestor is unsafe"。
  // 另外 _close 里要先判断 mounted，避免 deactivated 后操作 overlay。
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: _kMenuAnimationDuration,
      vsync: this,
    );
    _scaleAnimation = Tween<double>(
      begin: 0.92,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _opacityAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    _controller.stop();
    _controller.dispose();
    _triggerFocus.dispose();
    super.dispose();
  }

  bool get _enabled => widget.onChanged != null;

  void _toggle() {
    if (!mounted || !_enabled) return;
    if (_isOpen) {
      _close();
    } else {
      _open();
    }
  }

  void _open() {
    if (widget.items.isEmpty) return;
    final entries = widget.items.entries
        .map(
          (entry) => _MenuEntry<T>(
            value: entry.key,
            title: Text(entry.value),
            isSelected: entry.key == widget.value,
          ),
        )
        .toList();

    final renderBox = context.findRenderObject() as RenderBox;
    final overlay = Overlay.of(context);
    final overlayBox = overlay.context.findRenderObject() as RenderBox;
    final anchor = _anchorInOverlay(renderBox, overlayBox);
    final metrics = _measureMenu(
      context,
      entries,
      minWidth: renderBox.size.width,
    );

    // 记录打开前的焦点，关闭后还原：键盘用户回到触发器，鼠标用户回到
    // 原来的路由 scope（否则全局快捷键会随焦点一起丢失）。
    _previousFocus = FocusManager.instance.primaryFocus;

    _overlayEntry = OverlayEntry(
      builder: (context) => _MenuOverlay<T>(
        placement: _resolvePlacement(
          context,
          anchor,
          metrics.width,
          overlayBox,
        ),
        metrics: metrics,
        entries: entries,
        selectionIndicator: true,
        onSelected: (value) {
          _close(onComplete: () => widget.onChanged?.call(value));
        },
        onDismiss: _close,
        scaleAnimation: _scaleAnimation,
        opacityAnimation: _opacityAnimation,
        panelColor: widget.panelColor,
        selectedColor: widget.selectedColor,
        hoverColor: widget.hoverColor,
        panelBorderRadius: widget.panelBorderRadius,
        itemBorderRadius: widget.itemBorderRadius,
      ),
    );

    overlay.insert(_overlayEntry!);
    _controller.forward(from: 0);
    setState(() => _isOpen = true);
  }

  void _close({VoidCallback? onComplete}) {
    if (!_isOpen || !mounted) return;
    // 立即把状态置为关闭，避免关闭过程中重复触发 _toggle/_close。
    setState(() => _isOpen = false);
    _controller.reverse().then((_) {
      // 动画期间 widget 可能被 deactivate/dispose，所以这里必须判断 mounted。
      // onComplete（即 onChanged）仍要调用：用户已经做出了选择，
      // 即使本 widget 被移除，通知父级更新状态也是安全的（不访问 context）。
      if (!mounted) {
        onComplete?.call();
        return;
      }
      _overlayEntry?.remove();
      _overlayEntry = null;
      setState(() {});
      // 先还原焦点再回调 onComplete：onChanged 可能触发重建并销毁触发器，
      // 那时再去 requestFocus 会作用在已释放的节点上。
      final previousFocus = _previousFocus;
      _previousFocus = null;
      if (previousFocus != null && previousFocus.canRequestFocus) {
        previousFocus.requestFocus();
      }
      onComplete?.call();
    });
  }

  // CalmUI 触发器：与 CalmDropdown 一致的胶囊底，靠 surface2 / surfaceHover
  // 区分静息与交互态，焦点/展开时用主色描边。
  Color _triggerFill(CalmColors c) {
    if (!_enabled) return Colors.transparent;
    if (_isPressed || _isHovered || _isOpen) return c.surfaceHover;
    return c.surface2;
  }

  Color _triggerBorder(CalmColors c) {
    if (!_enabled) return c.border;
    if (_isFocused || _isOpen) return c.accent;
    if (_isHovered) return c.borderStrong;
    return c.border;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    final textStyle = Theme.of(context).textTheme.bodyMedium;

    return PopScope(
      canPop: !_isOpen,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          return;
        }
        _close();
      },
      child: Semantics(
        button: true,
        enabled: _enabled,
        expanded: _isOpen,
        child: FocusableActionDetector(
          enabled: _enabled,
          focusNode: _triggerFocus,
          mouseCursor: _enabled
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          onShowHoverHighlight: (value) => setState(() => _isHovered = value),
          onShowFocusHighlight: (value) => setState(() => _isFocused = value),
          actions: {
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (intent) {
                _toggle();
                return null;
              },
            ),
          },
          child: GestureDetector(
            onTap: _enabled ? _toggle : null,
            onTapDown: _enabled
                ? (_) => setState(() => _isPressed = true)
                : null,
            onTapUp: _enabled
                ? (_) => setState(() => _isPressed = false)
                : null,
            onTapCancel: _enabled
                ? () => setState(() => _isPressed = false)
                : null,
            child: AnimatedContainer(
              duration: _kItemAnimationDuration,
              curve: Curves.easeOut,
              constraints: const BoxConstraints(maxWidth: 180, minHeight: 36),
              padding: const EdgeInsetsDirectional.fromSTEB(14, 8, 12, 8),
              decoration: BoxDecoration(
                color: _triggerFill(c),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: _triggerBorder(c)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      widget.displayValue,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textHeightBehavior: kCalmTextHeightBehavior,
                      strutStyle: calmStrut(12.5),
                      style: textStyle?.copyWith(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: _enabled ? c.text : c.text3,
                        height: 1.2,
                        leadingDistribution: TextLeadingDistribution.even,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  AnimatedRotation(
                    turns: _isOpen ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 16,
                      color: _enabled
                          ? c.text3
                          : c.text3.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Static helper for showing a fluent popup menu at an arbitrary screen
/// rectangle (e.g. the widget that was long-pressed).
class FluentPopupMenu {
  const FluentPopupMenu._();

  static VoidCallback? _disposeCurrent;

  /// Shows a fluent-styled popup menu anchored to [anchor].
  ///
  /// Returns the selected value, or `null` if the menu is dismissed without
  /// a selection.
  static Future<T?> show<T>({
    required BuildContext context,
    required List<FluentPopupMenuItem<T>> items,
    required Rect anchor,
    ValueChanged<T>? onSelected,
  }) async {
    // 先关闭上一个弹出的菜单，保证右键/长按另一个项目时只会显示最新菜单。
    _disposeCurrent?.call();
    _disposeCurrent = null;

    final overlayState = Overlay.of(context);
    final completer = Completer<T?>();
    final closedCompleter = Completer<void>();

    final entries = items
        .map(
          (item) => _MenuEntry<T>(
            value: item.value,
            leading: item.leading,
            title: item.title,
            trailing: item.trailing,
            enabled: item.enabled,
          ),
        )
        .toList();

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (overlayContext) => _PositionedMenuOverlay<T>(
        entries: entries,
        anchor: anchor,
        onSelected: (value) {
          if (!completer.isCompleted) completer.complete(value);
          onSelected?.call(value);
        },
        onDismiss: () {
          if (!completer.isCompleted) completer.complete(null);
        },
        onClosed: () {
          if (!closedCompleter.isCompleted) closedCompleter.complete();
        },
      ),
    );

    var removed = false;
    late final VoidCallback disposeCurrent;
    disposeCurrent = () {
      if (!completer.isCompleted) completer.complete(null);
      if (!closedCompleter.isCompleted) closedCompleter.complete();
      if (!removed) {
        removed = true;
        entry.remove();
      }
    };
    _disposeCurrent = disposeCurrent;

    overlayState.insert(entry);
    final result = await completer.future;
    await closedCompleter.future;
    if (_disposeCurrent == disposeCurrent) {
      _disposeCurrent = null;
    }
    if (!removed) {
      removed = true;
      entry.remove();
    }
    return result;
  }
}

class _PositionedMenuOverlay<T> extends StatefulWidget {
  const _PositionedMenuOverlay({
    required this.entries,
    required this.anchor,
    required this.onSelected,
    required this.onDismiss,
    required this.onClosed,
  });

  final List<_MenuEntry<T>> entries;
  final Rect anchor;
  final ValueChanged<T> onSelected;
  final VoidCallback onDismiss;
  final VoidCallback onClosed;

  @override
  State<_PositionedMenuOverlay<T>> createState() =>
      _PositionedMenuOverlayState<T>();
}

class _PositionedMenuOverlayState<T> extends State<_PositionedMenuOverlay<T>>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _opacityAnimation;
  _MenuMetrics? _metrics;
  _MenuPlacement? _placement;
  bool _closedReported = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: _kMenuAnimationDuration,
      vsync: this,
    );
    _scaleAnimation = Tween<double>(
      begin: 0.92,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _opacityAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _controller.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final overlayBox =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final metrics = _metrics ??= _measureMenu(
      context,
      widget.entries,
      minWidth: widget.anchor.width,
    );
    _placement ??= _resolvePlacement(
      context,
      widget.anchor.shift(-overlayBox.localToGlobal(Offset.zero)),
      metrics.width,
      overlayBox,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _close({VoidCallback? onComplete}) {
    _controller
        .reverse()
        .then((_) {
          if (mounted) setState(() {});
          onComplete?.call();
          if (!_closedReported) {
            _closedReported = true;
            widget.onClosed();
          }
        })
        .catchError((_) {
          // 动画被中断（例如新菜单直接替换了当前菜单）。
          if (!_closedReported) {
            _closedReported = true;
            widget.onClosed();
          }
        });
  }

  @override
  Widget build(BuildContext context) {
    return _MenuOverlay<T>(
      placement: _placement!,
      metrics: _metrics!,
      entries: widget.entries,
      selectionIndicator: false,
      onSelected: (value) {
        _close(onComplete: () => widget.onSelected(value));
      },
      onDismiss: () => _close(onComplete: widget.onDismiss),
      scaleAnimation: _scaleAnimation,
      opacityAnimation: _opacityAnimation,
    );
  }
}
