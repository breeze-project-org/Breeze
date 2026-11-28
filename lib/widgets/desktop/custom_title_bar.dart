import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:window_manager/window_manager.dart';
import 'package:zephyr/platform/desktop/desktop_window.dart';
import 'package:zephyr/ui/ui.dart';

/// CalmUI 风格的自定义标题栏（仅桌面平台使用）。
///
/// 与正文同底色，仅用一条极淡的 1px 分隔线收口；窗口按钮悬停时给柔和底色，
/// 关闭按钮沿用「危险语义」的玫瑰色。
class CustomTitleBar extends StatefulWidget {
  const CustomTitleBar({super.key});

  @override
  State<CustomTitleBar> createState() => _CustomTitleBarState();
}

class _CustomTitleBarState extends State<CustomTitleBar> {
  bool _isMaximized = false;
  ListenerId? _windowListenerId;

  @override
  void initState() {
    super.initState();
    _windowListenerId = mainWindow?.addListener(_handleWindowEvent);
    _isMaximized = mainWindow?.isMaximized ?? false;
  }

  @override
  void dispose() {
    final listenerId = _windowListenerId;
    if (listenerId != null) {
      mainWindow?.removeListener(listenerId);
      _windowListenerId = null;
    }
    super.dispose();
  }

  void _handleWindowEvent(WindowEvent event) {
    switch (event) {
      // nativeapi 的「还原」同时覆盖取消最大化和从最小化恢复，
      // 因此统一回读窗口真实状态，而不是靠事件类型推断。
      case WindowMaximizedEvent():
      case WindowRestoredEvent():
        final maximized = mainWindow?.isMaximized ?? false;
        if (mounted && maximized != _isMaximized) {
          setState(() => _isMaximized = maximized);
        }
      case _:
        break;
    }
  }

  void _minimize() => mainWindow?.minimize();

  void _toggleMaximize() {
    final window = mainWindow;
    if (window == null) return;
    // 以窗口真实状态为准，避免本地 _isMaximized 与窗口脱节。
    if (window.isMaximized) {
      window.unmaximize();
    } else {
      window.maximize();
    }
  }

  void _handleClose() {
    // 必须走 window.close() 而不是直接发 WM_CLOSE：只有前者会先询问
    // 关闭监听（nativeapi 把裸 WM_CLOSE 当作不可取消的强制关闭）。
    mainWindow?.close();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    final isMacOS = Platform.isMacOS; // 检测是否为 macOS
    final titleColor = isMacOS ? c.text2 : c.text;

    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: c.bg,
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      child: Row(
        children: [
          // --- macOS 专属占位 ---
          if (isMacOS) const SizedBox(width: 80), // 为系统“红绿灯”按钮留出空间
          // 1. 左侧和中间区域：负责拖拽和双击
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanStart: (_) => mainWindow?.startDragging(),
              onDoubleTap: _toggleMaximize,
              child: Row(
                children: [
                  // 仅在非 macOS 平台（如 Windows）显示图标和标题
                  if (!isMacOS) ...[
                    const SizedBox(width: 12),
                    Image.asset(
                      'asset/image/app_icon.ico',
                      width: 18,
                      height: 18,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Breeze',
                      textHeightBehavior: kCalmTextHeightBehavior,
                      strutStyle: calmStrut(12.5),
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: titleColor,
                        height: 1.2,
                        leadingDistribution: TextLeadingDistribution.even,
                      ),
                    ),
                  ],

                  // 如果是 macOS，可以让标题居中（可选）
                  if (isMacOS) const Spacer(),
                  if (isMacOS)
                    Text(
                      'Breeze',
                      textHeightBehavior: kCalmTextHeightBehavior,
                      strutStyle: calmStrut(12.5),
                      style: TextStyle(
                        fontSize: 12.5, // macOS 标题通常更小更精致
                        fontWeight: FontWeight.w500,
                        color: titleColor,
                        height: 1.2,
                        leadingDistribution: TextLeadingDistribution.even,
                      ),
                    ),
                  if (isMacOS) const Spacer(),
                ],
              ),
            ),
          ),

          // 2. 右侧按钮区域（仅在非 macOS 平台显示）
          // macOS 的控制按钮在左边，所以右边的自定义按钮应该隐藏
          if (!isMacOS) ...[
            _TitleBarButton(
              icon: Icons.minimize_rounded,
              onPressed: _minimize,
              hoverColor: c.surfaceHover,
              iconColor: c.text2,
            ),
            _TitleBarButton(
              icon: _isMaximized
                  ? Icons.filter_none_rounded
                  : Icons.crop_square_rounded,
              onPressed: _toggleMaximize,
              hoverColor: c.surfaceHover,
              iconColor: c.text2,
            ),
            _TitleBarButton(
              icon: Icons.close_rounded,
              onPressed: _handleClose,
              hoverColor: c.danger,
              hoverIconColor: Colors.white,
              iconColor: c.text2,
            ),
          ],
        ],
      ),
    );
  }
}

/// 标题栏上的单个按钮
class _TitleBarButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final Color hoverColor;
  final Color iconColor;
  final Color? hoverIconColor;

  const _TitleBarButton({
    required this.icon,
    required this.onPressed,
    required this.hoverColor,
    required this.iconColor,
    this.hoverIconColor,
  });

  @override
  State<_TitleBarButton> createState() => _TitleBarButtonState();
}

class _TitleBarButtonState extends State<_TitleBarButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          width: 46,
          height: 40,
          color: _isHovered ? widget.hoverColor : Colors.transparent,
          alignment: Alignment.center,
          child: Icon(
            widget.icon,
            size: 18,
            color: _isHovered
                ? (widget.hoverIconColor ?? widget.iconColor)
                : widget.iconColor,
          ),
        ),
      ),
    );
  }
}
