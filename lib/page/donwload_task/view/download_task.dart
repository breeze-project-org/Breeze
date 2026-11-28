import 'package:auto_route/annotations.dart';
import 'package:material_ui/material_ui.dart' hide Page;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/object_box/model.dart';
import 'package:zephyr/page/donwload_task/bloc/dowload_task_bloc.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/service/download/download_queue_manager.dart';
import 'package:zephyr/service/download/download_task_progress.dart';
import 'package:zephyr/ui/ui.dart';
import 'package:zephyr/widgets/toast.dart';
import 'package:zephyr/main.dart';

@RoutePage()
class DownloadTaskPage extends StatelessWidget {
  const DownloadTaskPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => DowloadTaskBloc()..add(DowloadTaskEvent.started()),
      child: const _DownloadTaskView(),
    );
  }
}

class _DownloadTaskView extends StatelessWidget {
  const _DownloadTaskView();

  @override
  Widget build(BuildContext context) {
    return CalmPageScaffold(
      title: t.download.title,
      maxContentWidth: 768,
      body: BlocBuilder<DowloadTaskBloc, DowloadTaskState>(
        builder: (context, state) {
          return state.when(
            initial: () => const Center(child: CalmLoading()),
            loaded: (tasks, pendingCount) {
              if (tasks.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: CalmEmptyState(
                        icon: Icons.download_outlined,
                        title: t.download.noTasks,
                      ),
                    ),
                  ),
                );
              }

              final downloadingTasks = tasks
                  .where((t) => t.isDownloading)
                  .toList();
              final pendingTasks = tasks
                  .where((t) => !t.isDownloading)
                  .toList();

              return CustomScrollView(
                slivers: [
                  if (downloadingTasks.isNotEmpty) ...[
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                        child: CalmSectionHeader(
                          title: t.download.downloading,
                          countText: '${downloadingTasks.length}',
                        ),
                      ),
                    ),
                    SliverList(
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final task = downloadingTasks[index];
                        return _DownloadingTaskTile(
                          key: ValueKey(task.id),
                          task: task,
                        );
                      }, childCount: downloadingTasks.length),
                    ),
                  ],
                  if (pendingTasks.isNotEmpty) ...[
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
                        child: CalmSectionHeader(
                          title: t.download.pending(count: pendingTasks.length),
                          accentColor: context.calm.text3,
                        ),
                      ),
                    ),
                    SliverList(
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final task = pendingTasks[index];
                        return _PendingTaskTile(
                          key: ValueKey(task.id),
                          task: task,
                          onRetry: task.taskInfo?.stateCode == 'failed'
                              ? () async {
                                  await DownloadQueueManager.instance.retryTask(
                                    task.id,
                                  );
                                }
                              : null,
                          onDelete: () {
                            context.read<DowloadTaskBloc>().add(
                              DowloadTaskEvent.taskDeleted(task.id),
                            );
                            showInfoToast(t.download.taskDeleted);
                          },
                        );
                      }, childCount: pendingTasks.length),
                    ),
                  ],
                  const SliverToBoxAdapter(child: SizedBox(height: 24)),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _DownloadingTaskTile extends StatelessWidget {
  final DownloadTask task;

  const _DownloadingTaskTile({required super.key, required this.task});

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    final payload = task.taskInfo;
    final progress = payload == null
        ? null
        : downloadTaskPayloadProgressFraction(payload);
    final progressMessage = payload == null
        ? ''
        : downloadTaskPayloadProgressMessage(payload);
    // 任务状态和 checkpoint 进度是分开写入的。下载中只显示结构化进度，
    // 避免两次数据库更新之间蓝色状态文字短暂出现造成闪烁。
    final statusMessage = progressMessage.isEmpty ? task.status : '';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 5, 16, 5),
      child: CalmCard(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: c.accentSoft,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: SizedBox(
                width: 15,
                height: 15,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  strokeCap: StrokeCap.round,
                  value: progress,
                  valueColor: AlwaysStoppedAnimation<Color>(c.accent),
                  backgroundColor: c.accent.withValues(alpha: 0.18),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _taskTitle(context, task),
                  if (statusMessage.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      statusMessage,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textHeightBehavior: kCalmTextHeightBehavior,
                      strutStyle: calmStrut(11),
                      style: TextStyle(
                        fontSize: 11,
                        color: c.accent,
                        height: 1.2,
                        leadingDistribution: TextLeadingDistribution.even,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                  if (progressMessage.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      progressMessage,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textHeightBehavior: kCalmTextHeightBehavior,
                      strutStyle: calmStrut(11),
                      style: TextStyle(
                        fontSize: 11,
                        color: c.text2,
                        height: 1.2,
                        leadingDistribution: TextLeadingDistribution.even,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                  if (progress != null) ...[
                    const SizedBox(height: 7),
                    CalmProgressBar(value: progress, height: 4),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 6),
            CalmIconButton(
              icon: Icons.close_rounded,
              tooltip: t.download.cancelTask,
              size: 28,
              iconSize: 15,
              onPressed: () => _confirmCancel(context),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmCancel(BuildContext context) async {
    final bloc = context.read<DowloadTaskBloc>();
    final confirmed = await showCalmDialog<bool>(
      context,
      title: t.download.cancelTask,
      icon: Icons.cancel_outlined,
      tone: CalmTone.danger,
      bodyBuilder: (dialogContext) => Text(
        t.download.cancelTaskConfirm(comicName: task.comicName),
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
    if (confirmed == true) {
      bloc.add(const DowloadTaskEvent.cancelCurrentTask());
    }
  }
}

class _PendingTaskTile extends StatelessWidget {
  final DownloadTask task;
  final VoidCallback? onRetry;
  final VoidCallback onDelete;

  const _PendingTaskTile({
    required super.key,
    required this.task,
    this.onRetry,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    final payload = task.taskInfo;
    final progressMessage = payload == null
        ? ''
        : downloadTaskPayloadProgressMessage(payload);
    final statusMessage = task.status == progressMessage ? '' : task.status;
    final failed = payload?.stateCode == 'failed';
    final failureMessage = failed ? payload?.lastErrorMessage.trim() ?? '' : '';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 5, 16, 5),
      child: CalmCard(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: failed ? c.dangerSoft : c.warningSoft,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(
                failed
                    ? Icons.error_outline_rounded
                    : Icons.hourglass_empty_rounded,
                size: 16,
                color: failed ? c.danger : c.warning,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _taskTitle(context, task),
                  if (statusMessage.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      statusMessage,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textHeightBehavior: kCalmTextHeightBehavior,
                      strutStyle: calmStrut(11),
                      style: TextStyle(
                        fontSize: 11,
                        color: c.text3,
                        height: 1.2,
                        leadingDistribution: TextLeadingDistribution.even,
                      ),
                    ),
                  ],
                  if (progressMessage.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      progressMessage,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textHeightBehavior: kCalmTextHeightBehavior,
                      strutStyle: calmStrut(11),
                      style: TextStyle(
                        fontSize: 11,
                        color: c.text2,
                        height: 1.2,
                        leadingDistribution: TextLeadingDistribution.even,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                  if (failureMessage.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _showDownloadFailureDetails(
                          context,
                          failureMessage,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CalmBadge(
                              label: t.common.detail,
                              tone: CalmBadgeTone.danger,
                              icon: Icons.info_outline_rounded,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                failureMessage,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: c.danger,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 6),
            if (onRetry != null)
              CalmIconButton(
                icon: Icons.refresh_rounded,
                tooltip: t.common.retry,
                size: 28,
                iconSize: 15,
                onPressed: onRetry,
              ),
            const SizedBox(width: 4),
            CalmIconButton(
              icon: Icons.delete_outline_rounded,
              tooltip: t.common.delete,
              size: 28,
              iconSize: 15,
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

/// 单行任务标题：漫画名 + 章节名（宽度不足时省略，不再撑高整张卡片）。
Widget _taskTitle(BuildContext context, DownloadTask task) {
  final c = context.calm;
  return Text(
    _chapterTaskTitle(task),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    textHeightBehavior: kCalmTextHeightBehavior,
    strutStyle: calmStrut(12.5),
    style: TextStyle(
      fontSize: 12.5,
      fontWeight: FontWeight.w600,
      color: c.text,
      height: 1.25,
      leadingDistribution: TextLeadingDistribution.even,
    ),
  );
}

/// 单章节任务标题：漫画名 + 章节名（老任务无章节名时只显示漫画名）。
String _chapterTaskTitle(DownloadTask task) {
  String? chapterTitle;
  try {
    chapterTitle = task.taskInfo?.chapterRef.title.trim();
  } catch (e, st) {
    logger.e(e, stackTrace: st);
    chapterTitle = null;
  }
  if (chapterTitle == null || chapterTitle.isEmpty) return task.comicName;
  return '${task.comicName} $chapterTitle';
}

void _showDownloadFailureDetails(BuildContext context, String message) {
  showCalmDialog<void>(
    context,
    title: t.download.notificationFailedTitle,
    icon: Icons.error_outline_rounded,
    tone: CalmTone.danger,
    maxWidth: 720,
    bodyBuilder: (dialogContext) => SelectableText(
      message,
      style: TextStyle(
        fontSize: 12,
        color: dialogContext.calm.text2,
        height: 1.5,
      ),
    ),
    actionsBuilder: (dialogContext) => [
      CalmButton(
        label: t.common.ok,
        variant: CalmButtonVariant.primary,
        onPressed: () => Navigator.of(dialogContext).pop(),
      ),
    ],
  );
}
