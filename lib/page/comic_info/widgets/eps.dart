import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/cubit/string_select.dart';
import 'package:zephyr/page/comic_info/json/normal/normal_comic_all_info.dart';
import 'package:zephyr/page/comic_read/type/chapter_extern.dart';
import 'package:zephyr/page/download/adapters/download_chapter_adapter.dart';
import 'package:zephyr/page/download/models/download_chapter.dart';
import 'package:zephyr/page/comic_info/cubit/episode_download_status_cubit.dart';
import 'package:zephyr/page/comic_info/cubit/episode_selection_cubit.dart';
import 'package:zephyr/page/comic_info/widgets/episode_download_controller.dart';
import 'package:zephyr/service/download/download_task_repository.dart';
import 'package:zephyr/type/enum.dart';
import 'package:zephyr/ui/ui.dart';
import 'package:zephyr/util/text/chinese_convert.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/config/router/router.gr.dart';
import 'package:zephyr/widgets/toast.dart';

class EpButtonWidget extends StatelessWidget {
  static const double fixedHeight = 56;

  final Ep doc;
  final DownloadChapter chapter;
  final EpisodeDownloadController controller;
  final dynamic allInfo;
  final int epsLength;

  /// 组内总数：分组显示时行号按组内 1..N 编排（null 时回退 [epsLength]，
  /// 即今天的扁平行为）。阅读器用的总章节数仍走 [epsLength]。
  final int? displayTotal;
  final ComicEntryType type;
  final String comicId;
  final String from;
  final int index;
  final bool isReversed;

  /// 是否已读过该章节；已读行整体置灰，保留可点击。
  final bool isRead;

  /// 下载是否被插件允许；为 false 时仍显示下载按钮，点击后由调用方弹出禁用原因。
  final bool downloadAllowed;
  final String downloadDisabledReason;
  final VoidCallback? onAction;
  final VoidCallback? onToggleSelect;
  final VoidCallback? onEnterSelect;

  const EpButtonWidget({
    super.key,
    required this.doc,
    required this.chapter,
    required this.controller,
    required this.allInfo,
    required this.epsLength,
    this.displayTotal,
    required this.type,
    required this.comicId,
    required this.from,
    required this.index,
    required this.isReversed,
    this.isRead = false,
    this.downloadAllowed = true,
    this.downloadDisabledReason = '',
    this.onAction,
    this.onToggleSelect,
    this.onEnterSelect,
  });

  @override
  Widget build(BuildContext context) {
    // 不依赖插件返回的 order，按当前显示位置自主计算序号：
    // 正序从上到下 1..N，倒序从下到上 N..1。分组时 N 为组内总数。
    // 标题只在外层 build 算一次（带 FFI 缓存），选中/进度变化只走内层监听，
    final numberTotal = displayTotal ?? epsLength;
    final displayNumber = isReversed ? numberTotal - index : index + 1;
    final rawTitle = doc.name.trim();
    final title = rawTitle.isEmpty
        ? t.comicInfo.episodeFallback(index: displayNumber)
        : convertChineseForDisplay(rawTitle);
    final episodeLabel = t.comicInfo.episodeLabel(index: displayNumber);

    // RepaintBoundary 把进度圈动画隔离在行内；选中态只听 selectionCubit，
    // 下载进度 tick 不会重建标题/背景整行。
    return RepaintBoundary(
      child: BlocBuilder<EpisodeSelectionCubit, int>(
        bloc: controller.selectionCubit,
        builder: (context, _) {
          final c = context.calm;
          final selectionMode = controller.selectionMode;
          final selected = controller.selectedIds.contains(chapter.id);
          // 已读行整体置灰（保留可点击），但保持不透明以外的次级色阶。
          final readColor = c.text3.withValues(alpha: 0.72);
          return MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: selectionMode ? onToggleSelect : () => _openRead(context),
              onLongPress: onEnterSelect,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                width: double.infinity,
                height: fixedHeight,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: selected
                      ? c.accentSoft
                      : isRead
                      ? c.surface2
                      : c.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selected ? c.accentBorder : c.border,
                    width: selected ? 1.2 : 1,
                  ),
                  boxShadow: selected ? const [] : c.shadowSm,
                ),
                child: Row(
                  children: [
                    if (selectionMode)
                      Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: Icon(
                          selected
                              ? Icons.check_circle_rounded
                              : Icons.radio_button_unchecked,
                          color: selected ? c.accent : c.text3,
                          size: 19,
                        ),
                      ),
                    Text(
                      episodeLabel,
                      textHeightBehavior: kCalmTextHeightBehavior,
                      strutStyle: calmStrut(12),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: isRead ? readColor : c.accent,
                        height: 1.2,
                        leadingDistribution: TextLeadingDistribution.even,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: isRead
                              ? FontWeight.w500
                              : FontWeight.w600,
                          fontSize: 15,
                          color: isRead ? readColor : c.text,
                        ),
                      ),
                    ),
                    _EpisodeTrailing(
                      controller: controller,
                      chapter: chapter,
                      downloadAllowed: downloadAllowed,
                      onAction: onAction,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _openRead(BuildContext context) async {
    final chapter = const DownloadChapterAdapter().fromEp(doc);
    final wantRecord =
        type == ComicEntryType.normal || type == ComicEntryType.history;
    // 一次 worker 调用：读下载记录 + 解析章节 + 匹配 + 章节总数。
    final lookup = await const DownloadTaskRepository().lookupDownloadedChapter(
      from: from,
      comicId: comicId,
      chapterKeys: <String>[chapter.id],
      includeRecord: wantRecord,
    );
    final local = lookup.chapter;
    if (local != null && local.images.isEmpty) {
      showErrorToast(t.comicEdit.emptyChapter);
      return;
    }
    // 在线入口统一查库：该章已下载则直接读本地，不再看来源 type。
    if (wantRecord) {
      final record = lookup.record;
      if (local != null && record != null) {
        if (!context.mounted) return;
        context.pushRoute(
          ComicReadRoute(
            comicInfo: record,
            comicId: record.comicId,
            type: type == ComicEntryType.history
                ? ComicEntryType.historyAndDownload
                : ComicEntryType.download,
            order: local.order,
            chapterId: local.id,
            requestId: local.effectiveRequestId,
            storageChapterId: local.storageId ?? '',
            logicalKey: local.id,
            chapterExtern: ChapterExtern.from(local.extern),
            epsNumber: lookup.chapterCount,
            from: from,
            stringSelectCubit: context.read<StringSelectCubit>(),
          ),
        );
        return;
      }
    }
    final resolvedType = type == ComicEntryType.history
        ? ComicEntryType.normal
        : type;
    final chapterExtern = Map<String, dynamic>.from(doc.extern);
    if (!context.mounted) return;
    context.pushRoute(
      ComicReadRoute(
        comicInfo: allInfo,
        comicId: comicId,
        type: resolvedType,
        order: chapter.order,
        chapterId: chapter.id,
        requestId: chapter.effectiveRequestId,
        storageChapterId: chapter.storageId ?? '',
        logicalKey: chapter.id,
        chapterExtern: enrichEpisodeChapterExtern(doc, chapterExtern),
        epsNumber: epsLength,
        from: from,
        stringSelectCubit: context.read<StringSelectCubit>(),
      ),
    );
  }

  ChapterExtern enrichEpisodeChapterExtern(
    Ep episode,
    ChapterExtern chapterExtern,
  ) {
    return chapterExtern;
  }
}

/// 章节行右侧下载角标：独立监听下载状态，进度 tick 时只重建
/// 这个 32x32 槽位，不重建整行标题/背景。
class _EpisodeTrailing extends StatelessWidget {
  const _EpisodeTrailing({
    required this.controller,
    required this.chapter,
    required this.downloadAllowed,
    this.onAction,
  });

  final EpisodeDownloadController controller;
  final DownloadChapter chapter;
  final bool downloadAllowed;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    if (!downloadAllowed) {
      // 不允许下载时显示静态按钮，无需订阅，点击后由 onAction 弹出禁用原因。
      return _slot(
        context,
        Icon(
          Icons.download_outlined,
          size: 19,
          color: c.text3.withValues(alpha: 0.75),
        ),
      );
    }
    // 只订阅自己这一章的 (status, progress)：别的章节进度变化时不重建。
    return BlocSelector<
      EpisodeDownloadStatusCubit,
      EpisodeDownloadStatusState,
      (ChapterDownloadStatus, double?)
    >(
      bloc: controller.statusCubit,
      selector: (state) => (state.statusOf(chapter), state.progressOf(chapter)),
      builder: (context, selected) {
        final status = selected.$1;
        switch (status) {
          case ChapterDownloadStatus.notDownloaded:
            return _slot(
              context,
              Icon(
                Icons.download_outlined,
                size: 19,
                color: c.text3.withValues(alpha: 0.75),
              ),
            );
          case ChapterDownloadStatus.queued:
            return _slot(
              context,
              Icon(
                Icons.hourglass_empty_rounded,
                size: 19,
                color: c.text3.withValues(alpha: 0.75),
              ),
            );
          case ChapterDownloadStatus.downloading:
            return _slot(
              context,
              SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  value: selected.$2,
                  color: c.accent,
                  backgroundColor: c.accentSoft,
                ),
              ),
            );
          case ChapterDownloadStatus.failed:
            return _slot(
              context,
              Icon(Icons.error_outline_rounded, size: 19, color: c.danger),
            );
          case ChapterDownloadStatus.downloaded:
            // 已下载：柔和成功色微标记，不用大面积色块抢标题。
            return _slot(
              context,
              Icon(Icons.check_circle_rounded, size: 19, color: c.success),
            );
        }
      },
    );
  }

  // 行内容高度只有 32（56-上下 padding），IconButton 默认最小 40 会被纵向
  // 挤压，里面的进度圈会被压成椭圆。这里统一用 32x32 正方形槽位，保证不变形。
  Widget _slot(BuildContext context, Widget child) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onAction,
        child: SizedBox.square(dimension: 32, child: Center(child: child)),
      ),
    );
  }
}
