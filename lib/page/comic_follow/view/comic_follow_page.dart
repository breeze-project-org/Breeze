import 'package:auto_route/auto_route.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/router/router.gr.dart';
import 'package:zephyr/cubit/plugin_registry_cubit.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/object_box/model.dart';
import 'package:zephyr/page/comic_follow/cubit/comic_follow_cubit.dart';
import 'package:zephyr/page/comic_follow/view/follow_display.dart';
import 'package:zephyr/type/enum.dart';
import 'package:zephyr/ui/ui.dart';
import 'package:zephyr/widgets/comic_entry/models/models.dart';
import 'package:zephyr/widgets/comic_simplify_entry/cover.dart';
import 'package:zephyr/widgets/error_view.dart';
import 'package:zephyr/widgets/toast.dart';

@RoutePage()
class ComicFollowPage extends StatefulWidget {
  const ComicFollowPage({super.key});

  @override
  State<ComicFollowPage> createState() => _ComicFollowPageState();
}

class _ComicFollowPageState extends State<ComicFollowPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<ComicFollowCubit>().refreshHistories();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return const _ComicFollowPageContent();
  }
}

/// 追更列表页：顶部摘要条（更新数 + 检测 + 全部已读）+ 筛选行 + 单列列表。
class _ComicFollowPageContent extends StatelessWidget {
  const _ComicFollowPageContent();

  @override
  Widget build(BuildContext context) {
    return CalmPageScaffold(
      title: t.comicFollow.title,
      maxContentWidth: 768,
      body: BlocBuilder<ComicFollowCubit, ComicFollowState>(
        builder: (context, state) {
          switch (state.status) {
            case ComicFollowStatus.initial:
            case ComicFollowStatus.loading:
              return const Center(child: CalmLoading());
            case ComicFollowStatus.failure:
              return ErrorView(
                errorMessage: t.comicFollow.loadFailed(result: state.result),
                onRetry: () =>
                    context.read<ComicFollowCubit>().loadFromDatabase(),
              );
            case ComicFollowStatus.success:
              if (state.items.isEmpty) {
                return _buildEmptyView(context);
              }
              return _buildContent(context, state);
          }
        },
      ),
    );
  }

  Widget _buildEmptyView(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: CalmEmptyState(
            icon: Icons.notifications_none_outlined,
            title: t.comicFollow.empty,
            subtitle: t.comicFollow.emptyHint,
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, ComicFollowState state) {
    final visibleItems = state.visibleItems;
    // 页面外壳已按 768 限宽居中，这里只做纵向三段式布局。
    return Column(
      children: [
        _SummaryBar(state: state),
        _FilterRow(state: state),
        Expanded(
          child:
              visibleItems.isEmpty && state.filter == ComicFollowFilter.unread
              ? _buildFilteredEmptyView(context)
              : _FollowList(items: visibleItems),
        ),
      ],
    );
  }

  Widget _buildFilteredEmptyView(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: CalmEmptyState(
            icon: Icons.check_circle_outline_rounded,
            title: t.comicFollow.noUnread,
            action: CalmButton(
              label: t.comicFollow.showAll,
              icon: Icons.done_all_rounded,
              variant: CalmButtonVariant.tonal,
              onPressed: () => context.read<ComicFollowCubit>().setFilter(
                ComicFollowFilter.all,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 顶部摘要条：更新计数 + 检测按钮 + 全部已读。
class _SummaryBar extends StatelessWidget {
  const _SummaryBar({required this.state});

  final ComicFollowState state;

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    final unread = state.updateCount;
    final title = unread == 1
        ? t.comicFollow.updatedComicsSingle
        : unread > 1
        ? t.comicFollow.updatedComicsMultiple(count: unread)
        : t.comicFollow.noUnread;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
      child: CalmCard(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: unread > 0 ? c.accentSoft : c.surface2,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(
                unread > 0
                    ? Icons.notifications_active_outlined
                    : Icons.notifications_none_outlined,
                size: 17,
                color: unread > 0 ? c.accent : c.text3,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textHeightBehavior: kCalmTextHeightBehavior,
                    strutStyle: calmStrut(12.5),
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: c.text,
                      height: 1.2,
                      leadingDistribution: TextLeadingDistribution.even,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    state.isCheckingUpdates
                        ? t.common.loading
                        : t.comicFollow.checkTime(
                            time: formatFollowCheckTime(_latestCheck(state)),
                          ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textHeightBehavior: kCalmTextHeightBehavior,
                    strutStyle: calmStrut(10.5),
                    style: TextStyle(
                      fontSize: 10.5,
                      color: c.text3,
                      height: 1.2,
                      leadingDistribution: TextLeadingDistribution.even,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
            if (!state.isCheckingUpdates && unread > 0) ...[
              const SizedBox(width: 4),
              CalmIconButton(
                icon: Icons.done_all_rounded,
                tooltip: t.comicFollow.markAllReadHint,
                size: 30,
                iconSize: 16,
                onPressed: () => _markAllAsRead(context),
              ),
            ],
            const SizedBox(width: 2),
            CalmIconButton(
              icon: Icons.refresh_rounded,
              tooltip: t.common.refresh,
              size: 30,
              iconSize: 16,
              onPressed: state.isCheckingUpdates
                  ? null
                  : () => context.read<ComicFollowCubit>().checkUpdates(),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _markAllAsRead(BuildContext context) async {
    await context.read<ComicFollowCubit>().markAllAsRead();
    if (context.mounted) {
      showSuccessToast(t.comicFollow.markAllReadDone);
    }
  }

  DateTime _latestCheck(ComicFollowState state) {
    var latest = state.items.first.updateTime;
    for (final item in state.items) {
      if (item.updateTime.isAfter(latest)) {
        latest = item.updateTime;
      }
    }
    return latest;
  }
}

/// 筛选行：全部 / 未读 胶囊分段控件 + 排序菜单。
class _FilterRow extends StatelessWidget {
  const _FilterRow({required this.state});

  final ComicFollowState state;

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    final cubit = context.read<ComicFollowCubit>();
    final sortLabel = state.sort == ComicFollowSort.lastRead
        ? t.comicFollow.lastRead
        : t.comicFollow.lastUpdate;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
      child: Row(
        children: [
          CalmSegmentedControl<ComicFollowFilter>(
            value: state.filter,
            options: [
              (
                value: ComicFollowFilter.all,
                label: t.comicFollow.all,
                icon: Icons.list_alt_rounded,
              ),
              (
                value: ComicFollowFilter.unread,
                label: t.comicFollow.unread,
                icon: Icons.fiber_new_outlined,
              ),
            ],
            onChanged: cubit.setFilter,
          ),
          const Spacer(),
          CalmPopupMenuButton<ComicFollowSort>(
            entries: [
              CalmPopupMenuEntry.item(
                value: ComicFollowSort.lastRead,
                label: t.comicFollow.lastRead,
                icon: Icons.history_rounded,
              ),
              CalmPopupMenuEntry.item(
                value: ComicFollowSort.update,
                label: t.comicFollow.lastUpdate,
                icon: Icons.update_rounded,
              ),
            ],
            onSelected: cubit.setSort,
            child: Container(
              height: 28,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: c.surface2,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(Icons.sort_rounded, size: 13, color: c.text3),
                  const SizedBox(width: 5),
                  Text(
                    sortLabel,
                    textHeightBehavior: kCalmTextHeightBehavior,
                    strutStyle: calmStrut(11),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: c.text2,
                      height: 1.2,
                      leadingDistribution: TextLeadingDistribution.even,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 单列列表：下拉刷新。
class _FollowList extends StatelessWidget {
  const _FollowList({required this.items});

  final List<ComicFollow> items;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () => context.read<ComicFollowCubit>().checkUpdates(),
      child: BlocBuilder<ComicFollowCubit, ComicFollowState>(
        builder: (context, state) {
          return ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 88),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final follow = items[index];
              return _FollowCard(
                key: ValueKey(follow.uniqueKey),
                follow: follow,
                history: state.historyFor(follow),
                hasUnreadUpdate: state.hasUnreadUpdate(follow),
                unreadChapterCount: state.unreadChapterCount(follow),
              );
            },
          );
        },
      ),
    );
  }
}

/// 新版列表卡片：封面 + 标题 + 来源/作者 + 进度条 + 最新/在读 + 底行时间。
class _FollowCard extends StatelessWidget {
  const _FollowCard({
    super.key,
    required this.follow,
    required this.history,
    required this.hasUnreadUpdate,
    required this.unreadChapterCount,
  });

  final ComicFollow follow;
  final UnifiedComicHistory? history;
  final bool hasUnreadUpdate;
  final int unreadChapterCount;

  static const _coverWidth = 84.0;
  static const _coverHeight = 112.0;

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    final cover = resolveFollowCover(follow);

    return Dismissible(
      key: ValueKey('dismiss-${follow.uniqueKey}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 22),
        decoration: BoxDecoration(
          color: c.dangerSoft,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Icon(Icons.delete_outline_rounded, color: c.danger),
      ),
      confirmDismiss: (_) => _askUnfollow(context),
      onDismissed: (_) => _removeFollow(context),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _openDetail(context),
          onLongPress: () => _onLongPress(context),
          child: CalmCard(
            padding: EdgeInsets.zero,
            color: hasUnreadUpdate
                ? Color.alphaBlend(c.accent.withValues(alpha: 0.05), c.surface)
                : c.surface,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Stack(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildCover(cover),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildTitleRow(context),
                              const SizedBox(height: 4),
                              _buildSourceLine(context),
                              const SizedBox(height: 8),
                              _buildProgress(context),
                              const SizedBox(height: 8),
                              _buildLatestLine(context),
                              const SizedBox(height: 2),
                              _buildReadingLine(context),
                              const SizedBox(height: 6),
                              _buildBottomRow(context),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  // 未读更新：左侧 3px 柔和主色竖条，替代厚重描边。
                  if (hasUnreadUpdate)
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      width: 3,
                      child: ColoredBox(color: c.accent),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 长按走“菜单式”二次确认：先弹取消追更确认框，确认后真正移除并 toast。
  Future<void> _onLongPress(BuildContext context) async {
    final confirmed = await _askUnfollow(context);
    if (confirmed == true && context.mounted) {
      await _removeFollow(context);
    }
  }

  Widget _buildCover(UnifiedComicCover cover) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: CoverWidget(
          fileServer: cover.url,
          path: cover.cachePath,
          id: follow.comicId,
          pictureType: PictureType.cover,
          from: follow.source,
          roundedCorner: false,
          width: _coverWidth,
          height: _coverHeight,
        ),
      ),
    );
  }

  Widget _buildTitleRow(BuildContext context) {
    final c = context.calm;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            follow.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textHeightBehavior: kCalmTextHeightBehavior,
            strutStyle: calmStrut(13),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: c.text,
              height: 1.25,
              leadingDistribution: TextLeadingDistribution.even,
            ),
          ),
        ),
        if (hasUnreadUpdate) ...[
          const SizedBox(width: 8),
          CalmBadge(
            label: t.comicFollow.newChaptersShort(diff: unreadChapterCount),
            tone: CalmBadgeTone.accent,
            dot: true,
          ),
        ],
      ],
    );
  }

  /// 来源插件名 + 作者，插件名走全局 cubit 的 infos，热切换。
  Widget _buildSourceLine(BuildContext context) {
    final c = context.calm;
    return BlocSelector<PluginRegistryCubit, PluginRegistryState, String>(
      selector: (registry) => registry.pluginName(follow.source),
      builder: (context, pluginLabel) {
        final parts = [
          if (pluginLabel.isNotEmpty) pluginLabel,
          ?parseFollowCreatorName(follow.creator),
        ];
        if (parts.isEmpty) {
          return const SizedBox.shrink();
        }
        return Row(
          children: [
            Icon(Icons.source_outlined, size: 12, color: c.text3),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                parts.join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textHeightBehavior: kCalmTextHeightBehavior,
                strutStyle: calmStrut(11),
                style: TextStyle(
                  fontSize: 11,
                  color: c.text2,
                  height: 1.2,
                  leadingDistribution: TextLeadingDistribution.even,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 阅读进度条：读到 order / 最新总数。
  Widget _buildProgress(BuildContext context) {
    final c = context.calm;
    final readOrder = history?.chapterOrder ?? 0;
    final total = follow.detectedChapterCount;
    final progress = followReadProgress(
      readOrder: readOrder,
      detectedTotal: total,
    );
    final label = readOrder > 0
        ? t.comicFollow.readProgress(read: readOrder, total: total)
        : t.comicFollow.readProgressUnknown(total: total);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CalmProgressBar(
          value: total > 0 ? progress : null,
          height: 4,
          color: hasUnreadUpdate ? c.accent : c.borderStrong,
        ),
        const SizedBox(height: 4),
        Text(
          label,
          textHeightBehavior: kCalmTextHeightBehavior,
          strutStyle: calmStrut(10.5),
          style: TextStyle(
            fontSize: 10.5,
            color: c.text3,
            height: 1.2,
            leadingDistribution: TextLeadingDistribution.even,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }

  Widget _buildLatestLine(BuildContext context) {
    final c = context.calm;
    if (follow.lastCheckFailed) {
      return GestureDetector(
        onTap: () => _retry(context),
        child: Row(
          children: [
            Icon(Icons.error_outline_rounded, size: 13, color: c.danger),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                t.comicFollow.checkFailedTapRetry,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textHeightBehavior: kCalmTextHeightBehavior,
                strutStyle: calmStrut(11),
                style: TextStyle(
                  fontSize: 11,
                  color: c.danger,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                  leadingDistribution: TextLeadingDistribution.even,
                ),
              ),
            ),
          ],
        ),
      );
    }
    final title = follow.detectedChapterTitle.trim();
    final latest = title.isEmpty
        ? t.comicFollow.latestCount(count: follow.detectedChapterCount)
        : t.comicFollow.latestChapter(
            count: follow.detectedChapterCount,
            chapter: title,
          );
    return Row(
      children: [
        Icon(
          hasUnreadUpdate
              ? Icons.fiber_new_outlined
              : Icons.check_circle_outline_rounded,
          size: 13,
          color: hasUnreadUpdate ? c.accent : c.text3,
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            latest,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textHeightBehavior: kCalmTextHeightBehavior,
            strutStyle: calmStrut(11),
            style: TextStyle(
              fontSize: 11,
              color: hasUnreadUpdate ? c.text : c.text2,
              fontWeight: hasUnreadUpdate ? FontWeight.w600 : FontWeight.normal,
              height: 1.2,
              leadingDistribution: TextLeadingDistribution.even,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReadingLine(BuildContext context) {
    final c = context.calm;
    final chapter = history?.chapterTitle.trim() ?? '';
    final label = chapter.isEmpty
        ? t.comicFollow.notRead
        : t.comicFollow.lastReadChapter(chapter: chapter);
    return Row(
      children: [
        Icon(Icons.history_rounded, size: 13, color: c.text3),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textHeightBehavior: kCalmTextHeightBehavior,
            strutStyle: calmStrut(11),
            style: TextStyle(
              fontSize: 11,
              color: c.text2,
              height: 1.2,
              leadingDistribution: TextLeadingDistribution.even,
            ),
          ),
        ),
      ],
    );
  }

  /// 底行：相对更新时间 + 相对上次阅读；失败时重试按钮。
  /// 需要 context 触发 cubit 单项检测：旧 _retry 是无 context 的空实现。
  Widget _buildBottomRow(BuildContext context) {
    final c = context.calm;
    return Row(
      children: [
        Expanded(
          child: Text(
            _relativeUpdate(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textHeightBehavior: kCalmTextHeightBehavior,
            strutStyle: calmStrut(10.5),
            style: TextStyle(
              fontSize: 10.5,
              color: c.text3,
              height: 1.2,
              leadingDistribution: TextLeadingDistribution.even,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        if (history?.chapterTitle.trim().isNotEmpty == true)
          Text(
            _relativeRead(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textHeightBehavior: kCalmTextHeightBehavior,
            strutStyle: calmStrut(10.5),
            style: TextStyle(
              fontSize: 10.5,
              color: c.text3,
              height: 1.2,
              leadingDistribution: TextLeadingDistribution.even,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        if (follow.lastCheckFailed) ...[
          const SizedBox(width: 6),
          CalmButton(
            label: t.comicFollow.retry,
            icon: Icons.refresh_rounded,
            size: CalmButtonSize.xs,
            variant: CalmButtonVariant.tonal,
            onPressed: () => _retry(context),
          ),
        ],
      ],
    );
  }

  String _relativeUpdate() {
    final diff = DateTime.now().toLocal().difference(
      follow.updateTime.toLocal(),
    );
    if (diff.inMinutes < 1) {
      return t.comicFollow.updatedJustNow;
    }
    if (diff.inHours < 1) {
      return t.comicFollow.updatedMinutesAgo(minutes: diff.inMinutes);
    }
    if (diff.inDays < 1) {
      return t.comicFollow.updatedHoursAgo(hours: diff.inHours);
    }
    return t.comicFollow.updatedDaysAgo(days: diff.inDays);
  }

  String _relativeRead() {
    final lastRead = history?.lastReadAt;
    if (lastRead == null) {
      return '';
    }
    final diff = DateTime.now().toLocal().difference(lastRead.toLocal());
    if (diff.inMinutes < 1) {
      return t.comicFollow.lastReadJustNow;
    }
    if (diff.inHours < 1) {
      return t.comicFollow.lastReadMinutesAgo(minutes: diff.inMinutes);
    }
    if (diff.inDays < 1) {
      return t.comicFollow.lastReadHoursAgo(hours: diff.inHours);
    }
    return t.comicFollow.lastReadDaysAgo(days: diff.inDays);
  }

  Future<void> _openDetail(BuildContext context) async {
    await context.pushRoute(
      ComicInfoRoute(
        comicId: follow.comicId,
        from: follow.source,
        type: ComicEntryType.normal,
      ),
    );
    if (context.mounted) {
      await context.read<ComicFollowCubit>().refreshHistories();
    }
  }

  /// 单项重试：需要 context 拿 cubit；失败由 cubit 写回 lastCheckFailed。
  Future<void> _retry(BuildContext context) {
    return context.read<ComicFollowCubit>().checkUpdateForItem(follow);
  }

  Future<bool?> _askUnfollow(BuildContext context) {
    return showCalmDialog<bool>(
      context,
      title: t.comicFollow.unfollow,
      icon: Icons.delete_outline_rounded,
      tone: CalmTone.danger,
      bodyBuilder: (dialogContext) => Text(
        t.comicFollow.unfollowConfirm(title: follow.title),
        style: TextStyle(
          fontSize: 12.5,
          color: dialogContext.calm.text2,
          height: 1.5,
        ),
      ),
      actionsBuilder: (dialogContext) => [
        CalmButton(
          label: t.common.cancel,
          variant: CalmButtonVariant.ghost,
          onPressed: () => Navigator.of(dialogContext).pop(false),
        ),
        CalmButton(
          label: t.common.ok,
          variant: CalmButtonVariant.danger,
          onPressed: () => Navigator.of(dialogContext).pop(true),
        ),
      ],
    );
  }

  Future<void> _removeFollow(BuildContext context) async {
    await context.read<ComicFollowCubit>().removeFollow(
      follow.source,
      follow.comicId,
    );
    showSuccessToast(t.comicFollow.unfollowed);
  }
}
