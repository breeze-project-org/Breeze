import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/comic_read/model/seamless_transition_state.dart';
import 'package:zephyr/ui/ui.dart';

/// 章节衔接卡片：上一话 → 加载状态 → 下一话。
///
/// 底色/字色全部取自 [context.calm]，并以 [backgroundColor]（阅读器当前底色）
/// 作为环境判断依据——卡片自身是一张轻盈浮空面板，所以深色与浅色阅读器背景
/// 上都能读得清；[CalmColors.shadowMd] 保证浅底 + 白卡时依然有明确边界。
class ChapterTransitionCard extends StatelessWidget {
  const ChapterTransitionCard({
    super.key,
    required this.previousChapterOrder,
    required this.previousChapterTitle,
    required this.nextChapterOrder,
    required this.nextChapterTitle,
    required this.transitionStatus,
    required this.onTap,
    required this.backgroundColor,
    this.minHeight = 320,
    this.padding = const EdgeInsets.symmetric(horizontal: 24, vertical: 26),
    this.titleMaxLines = 2,
    this.lineSpacing = 34,
  });

  final int? previousChapterOrder;
  final String? previousChapterTitle;
  final int nextChapterOrder;
  final String nextChapterTitle;
  final SeamlessTransitionStatus transitionStatus;
  final VoidCallback onTap;
  final Color backgroundColor;
  final double minHeight;
  final EdgeInsetsGeometry padding;
  final int titleMaxLines;
  final double lineSpacing;

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    final previousTitle = (previousChapterTitle ?? '').trim().isEmpty
        ? t.reader.chapterOrder(order: previousChapterOrder ?? '--')
        : previousChapterTitle!;
    final currentTitle = nextChapterTitle.trim().isEmpty
        ? t.reader.chapterOrder(order: nextChapterOrder)
        : nextChapterTitle;
    final statusMeta = _resolveStatusMeta(transitionStatus, c);
    // 卡片与阅读器底色接近时（浅色主题 + 纯白阅读器背景 / 深色主题 + 纯黑），
    // 阴影不够用，换成更实一档的描边把边界拉回来。
    final surfaceDelta =
        (c.surface.computeLuminance() - backgroundColor.computeLuminance())
            .abs();
    final borderColor = surfaceDelta < 0.1 ? c.borderStrong : c.border;
    // 行模式只给了水平内边距（旧版卡片没有底/边），换成浮空卡后必须补一点
    // 纵向留白，否则文字会贴到描边上。
    final resolvedPadding = padding.resolve(Directionality.of(context));
    final cardPadding = resolvedPadding.copyWith(
      top: resolvedPadding.top < 12 ? 12 : resolvedPadding.top,
      bottom: resolvedPadding.bottom < 12 ? 12 : resolvedPadding.bottom,
    );

    final card = Container(
      width: double.infinity,
      padding: cardPadding,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
        boxShadow: c.shadowMd,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            previousTitle,
            textAlign: TextAlign.center,
            maxLines: titleMaxLines,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: c.text3,
              height: 1.3,
            ),
          ),
          SizedBox(height: lineSpacing),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (statusMeta.leading != null) ...[
                statusMeta.leading!,
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  statusMeta.message,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: c.text2,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: lineSpacing),
          CalmBadge(
            label: t.reader.nextChapter,
            tone: CalmBadgeTone.tonal,
            icon: Icons.arrow_downward_rounded,
          ),
          const SizedBox(height: 7),
          Text(
            currentTitle,
            textAlign: TextAlign.center,
            maxLines: titleMaxLines,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: c.text,
              height: 1.25,
            ),
          ),
        ],
      ),
    );

    return GestureDetector(
      onTap: statusMeta.canTap ? onTap : null,
      child: MouseRegion(
        cursor: statusMeta.canTap
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: minHeight),
          child: Center(child: card),
        ),
      ),
    );
  }

  _TransitionStatusMeta _resolveStatusMeta(
    SeamlessTransitionStatus status,
    CalmColors c,
  ) {
    switch (status) {
      case SeamlessTransitionStatus.hidden:
        return _TransitionStatusMeta(
          message: t.reader.transitionSwipeToLoad,
          canTap: true,
          leading: Icon(Icons.arrow_forward_rounded, size: 15, color: c.accent),
        );
      case SeamlessTransitionStatus.loading:
        return _TransitionStatusMeta(
          message: t.common.loading,
          canTap: false,
          leading: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(c.accent),
            ),
          ),
        );
      case SeamlessTransitionStatus.ready:
        return _TransitionStatusMeta(
          message: t.reader.transitionLoaded,
          canTap: false,
          leading: Icon(
            Icons.check_circle_outline_rounded,
            size: 15,
            color: c.success,
          ),
        );
      case SeamlessTransitionStatus.error:
        return _TransitionStatusMeta(
          message: t.reader.transitionLoadFailedRetry,
          canTap: true,
          leading: Icon(Icons.refresh_rounded, size: 15, color: c.warning),
        );
    }
  }
}

class _TransitionStatusMeta {
  const _TransitionStatusMeta({
    required this.message,
    required this.canTap,
    required this.leading,
  });

  final String message;
  final bool canTap;
  final Widget? leading;
}
