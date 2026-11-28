import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/ui/components/calm_button.dart';
import 'package:zephyr/ui/theme/calm_theme.dart';

enum CalmTone { info, success, warning, danger }

/// 页面内语义横幅（低干扰柔和底色 + 左侧图标 + 可选右侧操作）。
class CalmStatusBanner extends StatelessWidget {
  const CalmStatusBanner({
    super.key,
    required this.title,
    this.tone = CalmTone.info,
    this.trailing,
  });

  final String title;
  final CalmTone tone;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    final (bg, fg, icon) = switch (tone) {
      CalmTone.info => (c.accentSoft, c.accent, Icons.info_outline_rounded),
      CalmTone.success => (
        c.successSoft,
        c.success,
        Icons.check_circle_outline_rounded,
      ),
      CalmTone.warning => (
        c.warningSoft,
        c.warning,
        Icons.warning_amber_rounded,
      ),
      CalmTone.danger => (c.dangerSoft, c.danger, Icons.error_outline_rounded),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: fg,
              ),
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      ),
    );
  }
}

/// 顶部通知 Toast 卡片：严格垂直居中 + 内收圆头 3px 左侧色条 + 标题与详细内容。
class CalmToastCard extends StatelessWidget {
  const CalmToastCard({
    super.key,
    required this.title,
    this.description,
    this.tone = CalmTone.info,
    this.actionLabel,
    this.onAction,
    this.onDismiss,
  });

  final String title;
  final String? description;
  final CalmTone tone;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    final (accent, soft, icon) = switch (tone) {
      CalmTone.info => (c.accent, c.accentSoft, Icons.info_outline_rounded),
      CalmTone.success => (
        c.success,
        c.successSoft,
        Icons.check_circle_outline_rounded,
      ),
      CalmTone.warning => (
        c.warning,
        c.warningSoft,
        Icons.warning_amber_rounded,
      ),
      CalmTone.danger => (c.danger, c.dangerSoft, Icons.highlight_off_rounded),
    };

    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.borderStrong),
          boxShadow: c.shadowMd,
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 严格内收且垂直对称的 3px 圆头色条，永远不会被圆角裁切
              Padding(
                padding: const EdgeInsets.only(left: 6, top: 12, bottom: 12),
                child: Container(
                  width: 3,
                  constraints: const BoxConstraints(minHeight: 24),
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 11, 10, 11),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: soft,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        alignment: Alignment.center,
                        child: Icon(icon, size: 17, color: accent),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: c.text,
                                height: 1.3,
                              ),
                            ),
                            if (description != null &&
                                description!.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                description!,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: c.text2,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (actionLabel != null && onAction != null) ...[
                        const SizedBox(width: 8),
                        CalmButton(
                          label: actionLabel!,
                          variant: CalmButtonVariant.tonal,
                          size: CalmButtonSize.xs,
                          onPressed: () {
                            onAction!();
                            onDismiss?.call();
                          },
                        ),
                      ],
                      if (onDismiss != null) ...[
                        const SizedBox(width: 4),
                        MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                            onTap: onDismiss,
                            child: Container(
                              width: 26,
                              height: 26,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                              ),
                              alignment: Alignment.center,
                              child: Icon(
                                Icons.close_rounded,
                                size: 15,
                                color: c.text3,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
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

/// 顶部悬浮 Toast 工具：桌面右上角 / 手机顶部居中平滑滑入与渐隐退出。
class CalmToast {
  CalmToast._();

  static OverlayEntry? _currentEntry;
  static GlobalKey<_ToastSlideInState>? _currentKey;
  static Timer? _timer;

  static void show(
    BuildContext context, {
    required String title,
    String? description,
    CalmTone tone = CalmTone.info,
    String? actionLabel,
    VoidCallback? onAction,
    Duration duration = const Duration(seconds: 4),
  }) {
    dismiss(immediate: true);
    final overlay = Overlay.of(context);
    final isWide = MediaQuery.sizeOf(context).width >= 600;
    final key = GlobalKey<_ToastSlideInState>();

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) {
        final topInset = MediaQuery.paddingOf(ctx).top;
        return Positioned(
          top: topInset + (isWide ? 56 : 12),
          right: isWide ? 16 : 12,
          left: isWide ? null : 12,
          child: Align(
            alignment: isWide ? Alignment.topRight : Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 368),
              child: _ToastSlideIn(
                key: key,
                slideFromRight: isWide,
                child: CalmToastCard(
                  title: title,
                  description: description,
                  tone: tone,
                  actionLabel: actionLabel,
                  onAction: onAction,
                  onDismiss: () => _dismissEntry(entry, key),
                ),
              ),
            ),
          ),
        );
      },
    );

    _currentEntry = entry;
    _currentKey = key;
    overlay.insert(entry);
    _timer = Timer(duration, () => _dismissEntry(entry, key));
  }

  static void dismiss({bool immediate = false}) {
    final entry = _currentEntry;
    final key = _currentKey;
    if (entry == null) return;
    _dismissEntry(entry, key, immediate: immediate);
  }

  static void _dismissEntry(
    OverlayEntry entry,
    GlobalKey<_ToastSlideInState>? key, {
    bool immediate = false,
  }) {
    if (_currentEntry == entry) {
      _timer?.cancel();
      _timer = null;
      _currentEntry = null;
      _currentKey = null;
    }

    if (immediate) {
      if (entry.mounted) entry.remove();
      return;
    }

    final state = key?.currentState;
    if (state == null || !state.mounted) {
      if (entry.mounted) entry.remove();
      return;
    }

    state.dismiss().whenComplete(() {
      if (entry.mounted) entry.remove();
    });
  }
}

class _ToastSlideIn extends StatefulWidget {
  const _ToastSlideIn({
    super.key,
    required this.child,
    required this.slideFromRight,
  });

  final Widget child;
  final bool slideFromRight;

  @override
  State<_ToastSlideIn> createState() => _ToastSlideInState();
}

class _ToastSlideInState extends State<_ToastSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
    reverseDuration: const Duration(milliseconds: 200),
  );
  bool _dismissing = false;

  @override
  void initState() {
    super.initState();
    _ctrl.forward();
  }

  Future<void> dismiss() async {
    if (_dismissing || !mounted) return;
    _dismissing = true;
    try {
      await _ctrl.reverse();
    } catch (_) {
      // 控制器在动画中途释放时安全忽略。
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curve = CurvedAnimation(
      parent: _ctrl,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    final beginOffset = widget.slideFromRight
        ? const Offset(0.28, 0)
        : const Offset(0, -0.55);
    return FadeTransition(
      opacity: curve,
      child: SlideTransition(
        position: Tween<Offset>(begin: beginOffset, end: Offset.zero).animate(
          curve,
        ),
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.94, end: 1.0).animate(curve),
          alignment: widget.slideFromRight
              ? Alignment.topRight
              : Alignment.topCenter,
          child: widget.child,
        ),
      ),
    );
  }
}

/// 基础弹窗容器（桌面居中圆角卡片 / 手机底部带抓手滑出，头部严格居中对齐）。
class CalmDialogSurface extends StatelessWidget {
  const CalmDialogSurface({
    super.key,
    required this.title,
    required this.body,
    this.subtitle,
    this.icon,
    this.badge,
    this.tone = CalmTone.info,
    this.actions = const [],
    this.onClose,
    this.isBottomSheet = false,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final String? badge;
  final CalmTone tone;
  final Widget body;
  final List<Widget> actions;
  final VoidCallback? onClose;
  final bool isBottomSheet;

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    final (iconBg, iconFg) = switch (tone) {
      CalmTone.danger => (c.dangerSoft, c.danger),
      CalmTone.warning => (c.warningSoft, c.warning),
      CalmTone.success => (c.successSoft, c.success),
      CalmTone.info => (c.accentSoft, c.accent),
    };

    final radius = isBottomSheet
        ? const BorderRadius.vertical(top: Radius.circular(24))
        : BorderRadius.circular(20);

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: radius,
        boxShadow: c.shadowMd,
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(color: c.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isBottomSheet)
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: c.borderStrong,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 14, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: iconBg,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    alignment: Alignment.center,
                    child: Icon(icon, size: 18, color: iconFg),
                  ),
                  const SizedBox(width: 11),
                ],
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Flexible(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600,
                                color: c.text,
                                height: 1.25,
                              ),
                            ),
                          ),
                          if (badge != null) ...[
                            const SizedBox(width: 8),
                            Container(
                              height: 18,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                              ),
                              decoration: BoxDecoration(
                                color: c.accentSoft,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                badge!,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: c.accent,
                                  height: 1.0,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: c.text3,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (onClose != null) ...[
                  const SizedBox(width: 6),
                  CalmIconButton(
                    icon: Icons.close_rounded,
                    size: 28,
                    iconSize: 15,
                    onPressed: onClose,
                  ),
                ],
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 16),
              child: body,
            ),
          ),
          if (actions.isNotEmpty)
            Container(
              width: double.infinity,
              color: c.bg.withValues(alpha: 0.65),
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              // Wrap 而非 Row：窄屏下多个长按钮文案会自动换行，不会横向溢出。
              child: Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: actions,
              ),
            ),
        ],
      ),
    );
  }
}

/// 统一自适应弹窗入口：窄屏手机底部弹出，平板与桌面端居中卡片弹出。
///
/// [barrierDismissible] 为 false 时不显示右上角关闭叉，点击遮罩也不关闭；
/// [preventPop] 为 true 时会拦截系统返回手势，适用于不可中断的加载弹窗。
///
/// 返回的 Future 在弹窗**完全退场**后才完成：路由的 `push` future 在 `pop()`
/// 瞬间就完成，此时退场动画（约 150~200ms）仍在跑、弹窗子树还在重建，
/// 调用方若在这里 `controller.dispose()` 就会撞上
/// `A TextEditingController was used after being disposed.`。
/// 这里改为 push 后再等 [TransitionRoute.completed]（在 overlayEntries 全部
/// unmount 之后才完成），让所有调用方 `await showCalmDialog(...)` 之后立刻
/// 释放 controller 都是安全的。
Future<T?> showCalmDialog<T>(
  BuildContext context, {
  required String title,
  required WidgetBuilder bodyBuilder,
  String? subtitle,
  IconData? icon,
  String? badge,
  CalmTone tone = CalmTone.info,
  List<Widget> Function(BuildContext dialogContext)? actionsBuilder,
  double maxWidth = 420,
  bool barrierDismissible = true,
  bool preventPop = false,
}) async {
  final isPhone = MediaQuery.sizeOf(context).width < 600;

  Widget surfaceOf(BuildContext ctx) {
    final surface = CalmDialogSurface(
      title: title,
      subtitle: subtitle,
      icon: icon,
      badge: badge,
      tone: tone,
      isBottomSheet: isPhone,
      onClose: barrierDismissible ? () => Navigator.of(ctx).pop() : null,
      body: bodyBuilder(ctx),
      actions: actionsBuilder?.call(ctx) ?? const [],
    );
    if (!preventPop) return surface;
    return PopScope(canPop: false, child: surface);
  }

  // 与 showCalmDialog 的旧实现保持同一 Navigator：
  // showDialog 默认 useRootNavigator: true，showModalBottomSheet 默认 false。
  final navigator = Navigator.of(context, rootNavigator: !isPhone);
  // 跨 Navigator 边界也要把主题与 CalmColors 一起带进弹窗子树。
  final themes = InheritedTheme.capture(from: context, to: navigator.context);
  final localizations = MaterialLocalizations.of(context);

  final TransitionRoute<T> route;
  if (isPhone) {
    route = ModalBottomSheetRoute<T>(
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: barrierDismissible,
      enableDrag: barrierDismissible,
      capturedThemes: themes,
      barrierLabel: localizations.scrimLabel,
      barrierOnTapHint: localizations.scrimOnTapHint(
        localizations.bottomSheetLabel,
      ),
      modalBarrierColor: Theme.of(context).bottomSheetTheme.modalBarrierColor,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: SafeArea(top: false, child: surfaceOf(ctx)),
      ),
    );
  } else {
    route = DialogRoute<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      barrierColor: context.calm.shadowColor.withValues(alpha: 0.28),
      themes: themes,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: surfaceOf(ctx),
        ),
      ),
    );
  }

  final result = await navigator.push<T>(route);
  // push 的 future 在 pop() 瞬间完成，completed 在路由 dispose（子树已
  // unmount）后才完成，这里必须等它，否则调用方的 controller.dispose() 会
  // 撞上退场动画期间的 CalmTextField 重建。
  await route.completed;
  return result;
}

/// 自适应抽屉：手机底部滑出 BottomSheet，平板与桌面右侧滑出 SideSheet。
Future<T?> showCalmSheet<T>(
  BuildContext context, {
  required String title,
  required WidgetBuilder builder,
  double desktopWidth = 340,
}) {
  final isPhone = MediaQuery.sizeOf(context).width < 600;
  if (isPhone) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SafeArea(
        top: false,
        child: CalmDialogSurface(
          title: title,
          isBottomSheet: true,
          onClose: () => Navigator.of(ctx).pop(),
          body: builder(ctx),
        ),
      ),
    );
  }

  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'close',
    barrierColor: context.calm.shadowColor.withValues(alpha: 0.26),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (ctx, _, _) => Align(
      alignment: Alignment.centerRight,
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: desktopWidth,
          height: double.infinity,
          decoration: BoxDecoration(
            color: ctx.calm.surface,
            boxShadow: ctx.calm.shadowMd,
          ),
          child: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 12, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                            color: ctx.calm.text,
                          ),
                        ),
                      ),
                      CalmIconButton(
                        icon: Icons.close_rounded,
                        size: 28,
                        iconSize: 15,
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: ctx.calm.border),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(18),
                    child: builder(ctx),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
    transitionBuilder: (_, anim, _, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      );
    },
  );
}

/// 轻盈空状态占位。
class CalmEmptyState extends StatelessWidget {
  const CalmEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: c.surface,
              shape: BoxShape.circle,
              boxShadow: c.shadowSm,
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 18, color: c.text3),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: c.text,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: c.text3),
            ),
          ],
          if (action != null) ...[const SizedBox(height: 12), action!],
        ],
      ),
    );
  }
}

/// 友好错误态组件：带一键复制错误详情 + 主次双按钮（如去登录 / 重试）。
class CalmErrorState extends StatelessWidget {
  const CalmErrorState({
    super.key,
    required this.title,
    required this.errorDetail,
    this.subtitle,
    this.primaryLabel,
    this.onPrimary,
    this.onRetry,
    this.onCopied,
    this.retryLabel = '刷新重试',
    this.errorDetailMaxLines = 1,
  });

  final String title;
  final String? subtitle;
  final String errorDetail;
  final String? primaryLabel;
  final VoidCallback? onPrimary;
  final VoidCallback? onRetry;
  final VoidCallback? onCopied;

  /// 重试按钮文案；调用方用自己的 i18n 词条覆盖。
  final String retryLabel;

  /// 错误详情单行截断行数（页内错误态给 1 行，整页错误态可给多行）。
  final int errorDetailMaxLines;

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: c.warningSoft,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(Icons.wifi_off_rounded, size: 15, color: c.warning),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: c.text,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: TextStyle(fontSize: 10.5, color: c.text3),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    errorDetail,
                    maxLines: errorDetailMaxLines,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: c.text2,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: errorDetail));
                      onCopied?.call();
                    },
                    child: Icon(Icons.copy_rounded, size: 13.5, color: c.text3),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              if (primaryLabel != null && onPrimary != null)
                CalmButton(
                  label: primaryLabel!,
                  variant: CalmButtonVariant.primary,
                  size: CalmButtonSize.xs,
                  onPressed: onPrimary,
                ),
              if (onRetry != null)
                CalmButton(
                  label: retryLabel,
                  icon: Icons.refresh_rounded,
                  variant: CalmButtonVariant.secondary,
                  size: CalmButtonSize.xs,
                  onPressed: onRetry,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 轻盈脉冲骨架占位块。
class CalmSkeletonBox extends StatefulWidget {
  const CalmSkeletonBox({
    super.key,
    this.width,
    required this.height,
    this.radius = 8,
  });

  final double? width;
  final double height;
  final double radius;

  @override
  State<CalmSkeletonBox> createState() => _CalmSkeletonBoxState();
}

class _CalmSkeletonBoxState extends State<CalmSkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: Color.lerp(c.surface2, c.surfaceHover, _ctrl.value),
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    );
  }
}

/// 轻盈环形加载指示器（可带右侧短提示文案）。
class CalmLoading extends StatelessWidget {
  const CalmLoading({super.key, this.label, this.size = 18});

  final String? label;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: size,
          height: size,
          child: CircularProgressIndicator(
            strokeWidth: 2.2,
            strokeCap: StrokeCap.round,
            color: c.accent,
            backgroundColor: c.accentSoft,
          ),
        ),
        if (label != null && label!.isNotEmpty) ...[
          const SizedBox(width: 9),
          Text(
            label!,
            textHeightBehavior: kCalmTextHeightBehavior,
            strutStyle: calmStrut(12),
            style: TextStyle(
              fontSize: 12,
              color: c.text2,
              height: 1.2,
              leadingDistribution: TextLeadingDistribution.even,
            ),
          ),
        ],
      ],
    );
  }
}

enum CalmBottomLoaderStatus { loading, error, noMore }

/// 分页列表通用底部状态条（加载中 / 加载失败点击重试 / 已全部加载）。
class CalmBottomLoader extends StatelessWidget {
  const CalmBottomLoader({
    super.key,
    required this.status,
    this.loadingText = '正在加载更多…',
    this.errorText = '加载失败',
    this.noMoreText = '已经到底啦',
    this.onRetry,
  });

  final CalmBottomLoaderStatus status;
  final String loadingText;
  final String errorText;
  final String noMoreText;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Center(
        child: switch (status) {
          CalmBottomLoaderStatus.loading => CalmLoading(
            label: loadingText,
            size: 16,
          ),
          CalmBottomLoaderStatus.error => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded, size: 15, color: c.danger),
              const SizedBox(width: 6),
              Text(errorText, style: TextStyle(fontSize: 12, color: c.text2)),
              if (onRetry != null) ...[
                const SizedBox(width: 8),
                CalmButton(
                  label: '重试',
                  size: CalmButtonSize.xs,
                  variant: CalmButtonVariant.tonal,
                  onPressed: onRetry,
                ),
              ],
            ],
          ),
          CalmBottomLoaderStatus.noMore => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 24, height: 1, color: c.borderStrong),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  noMoreText,
                  style: TextStyle(fontSize: 11, color: c.text3),
                ),
              ),
              Container(width: 24, height: 1, color: c.borderStrong),
            ],
          ),
        },
      ),
    );
  }
}
