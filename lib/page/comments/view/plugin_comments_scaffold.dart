import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/config/router/router.gr.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/comments/cubit/cubit.dart';
import 'package:zephyr/page/comments/model/model.dart';
import 'package:zephyr/type/enum.dart';
import 'package:zephyr/type/pipe.dart';
import 'package:zephyr/ui/ui.dart';
import 'package:zephyr/util/text/chinese_convert.dart';
import 'package:zephyr/widgets/error_view.dart';
import 'package:zephyr/widgets/picture_bloc/bloc/picture_bloc.dart';
import 'package:zephyr/widgets/picture_bloc/models/picture_info.dart';

@RoutePage(name: 'PluginCommentsScaffoldRoute')
class PluginCommentsScaffold extends StatefulWidget {
  const PluginCommentsScaffold({
    super.key,
    required this.from,
    required this.comicId,
    required this.comicTitle,
  });

  final String from;
  final String comicId;
  final String comicTitle;

  @override
  State<PluginCommentsScaffold> createState() => _PluginCommentsScaffoldState();
}

class _PluginCommentsScaffoldState extends State<PluginCommentsScaffold> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _composeController = TextEditingController();
  CommentsCubit? _commentsCubit;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _composeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) =>
          CommentsCubit(from: widget.from, comicId: widget.comicId)
            ..loadInitial(),
      child: BlocListener<CommentsCubit, CommentsViewState>(
        listenWhen: (previous, current) =>
            previous.noticeId != current.noticeId &&
            current.noticeMessage.trim().isNotEmpty,
        listener: (context, state) {
          CalmToast.show(
            context,
            title: state.noticeMessage,
            tone: state.noticeMessage == t.comments.postSuccess
                ? CalmTone.success
                : CalmTone.danger,
          );
        },
        child: BlocBuilder<CommentsCubit, CommentsViewState>(
          builder: (context, state) {
            final cubit = context.read<CommentsCubit>();
            _commentsCubit = cubit;
            final isLeftHand = context
                .watch<GlobalSettingCubit>()
                .state
                .leftHandModeEnabled;

            return CalmPageScaffold(
              title: widget.comicTitle,
              maxContentWidth: 768,
              actions: [
                CalmIconButton(
                  icon: Icons.refresh_rounded,
                  tooltip: t.comments.retry,
                  onPressed: state.loading ? null : cubit.loadInitial,
                ),
              ],
              body: Column(
                children: [
                  if (state.posting) const CalmProgressBar(height: 2),
                  Expanded(child: _buildBody(state, cubit)),
                  if (state.canCommentComic)
                    _buildComposer(state, cubit, isLeftHand: isLeftHand),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildBody(CommentsViewState state, CommentsCubit cubit) {
    if (state.loading) {
      return const Center(child: CalmLoading(size: 22));
    }
    if (state.error != null && state.topItems.isEmpty && state.items.isEmpty) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ErrorView(
              errorMessage: state.error!,
              onRetry: cubit.loadInitial,
            ),
          ),
        ),
      );
    }

    final merged = <CommentItem>[...state.topItems, ...state.items];
    // 屏蔽词可能把当前页全部过滤掉；只要还有下一页就保留“加载更多”。
    if (merged.isEmpty && state.hasReachedMax) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: CalmEmptyState(
              icon: Icons.forum_outlined,
              title: t.comments.noComments,
            ),
          ),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      itemCount: merged.length + 1,
      itemBuilder: (context, index) {
        if (index >= merged.length) {
          return _buildFooter(state, cubit);
        }
        final item = merged[index];
        return KeyedSubtree(
          key: ValueKey(
            'comment_${item.id}_${index}_${item.avatarUrl}_${item.avatarPath}',
          ),
          child: _buildCommentCell(
            item,
            cubit: cubit,
            state: state,
            isReply: false,
            keySeed: '$index',
          ),
        );
      },
    );
  }

  Widget _buildFooter(CommentsViewState state, CommentsCubit cubit) {
    if (state.loadingMore) {
      return const CalmBottomLoader(status: CalmBottomLoaderStatus.loading);
    }
    if (state.hasReachedMax) {
      return const CalmBottomLoader(status: CalmBottomLoaderStatus.noMore);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: CalmButton(
          label: t.comments.loadMore,
          icon: Icons.expand_more_rounded,
          variant: CalmButtonVariant.ghost,
          size: CalmButtonSize.sm,
          onPressed: cubit.loadMore,
        ),
      ),
    );
  }

  Widget _buildCommentCell(
    CommentItem item, {
    required CommentsCubit cubit,
    required CommentsViewState state,
    required bool isReply,
    required String keySeed,
  }) {
    final c = context.calm;
    final replies = state.replyItems[item.id] ?? const <CommentItem>[];
    final isExpanded = state.expandedIds.contains(item.id);
    final canExpand = item.replyCount > 0 || item.replies.isNotEmpty;
    final loadingReplies = state.replyLoading[item.id] == true;
    final hasReachedMaxReplies = state.replyHasReachedMax[item.id] == true;

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildAvatar(item, isReply: isReply),
            SizedBox(width: isReply ? 8 : 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.authorName.let(convertChineseForDisplay),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: isReply ? 12 : 12.5,
                      fontWeight: FontWeight.w600,
                      color: c.accent,
                      height: 1.2,
                    ),
                  ),
                  if (item.createdAt.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      item.createdAt,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: c.text3,
                        height: 1.2,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  SelectableText(
                    item.content.let(convertChineseForDisplay),
                    style: TextStyle(
                      fontSize: isReply ? 12 : 12.5,
                      color: c.text,
                      height: 1.55,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (!isReply && canExpand)
                        CalmButton(
                          label: isExpanded
                              ? t.comments.collapseReplies
                              : t.comments.replyCount(count: item.replyCount),
                          variant: CalmButtonVariant.ghost,
                          size: CalmButtonSize.xs,
                          trailingIcon: isExpanded
                              ? Icons.keyboard_arrow_up_rounded
                              : Icons.keyboard_arrow_down_rounded,
                          onPressed: () => cubit.toggleReplies(item),
                        ),
                      const Spacer(),
                      if (state.canCommentReply && !isReply)
                        CalmIconButton(
                          icon: Icons.reply_rounded,
                          size: 26,
                          iconSize: 14,
                          tooltip: t.comments.postReply,
                          onPressed: state.posting
                              ? null
                              : () => _postReply(cubit, item),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        if (!isReply && isExpanded) ...[
          const SizedBox(height: 6),
          if (loadingReplies)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6, horizontal: 4),
              child: CalmLoading(size: 16),
            ),
          for (var i = 0; i < replies.length; i++)
            KeyedSubtree(
              key: ValueKey(
                'reply_${item.id}_${replies[i].id}_${i}_${replies[i].avatarUrl}_${replies[i].avatarPath}',
              ),
              child: _buildCommentCell(
                replies[i],
                cubit: cubit,
                state: state,
                isReply: true,
                keySeed: '$keySeed-$i',
              ),
            ),
          if (replies.isEmpty && !loadingReplies)
            Padding(
              padding: const EdgeInsets.only(left: 34, top: 4),
              child: Text(
                t.comments.noReplies,
                style: TextStyle(fontSize: 11, color: c.text3),
              ),
            ),
          if (!hasReachedMaxReplies && !loadingReplies)
            Padding(
              padding: const EdgeInsets.only(left: 30, top: 2),
              child: Align(
                alignment: Alignment.centerLeft,
                child: CalmButton(
                  label: t.comments.loadMoreReplies,
                  variant: CalmButtonVariant.ghost,
                  size: CalmButtonSize.xs,
                  onPressed: () => cubit.loadMoreReplies(item),
                ),
              ),
            ),
        ],
      ],
    );

    if (isReply) {
      return Padding(
        padding: const EdgeInsets.only(left: 30, bottom: 6),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
          decoration: BoxDecoration(
            color: c.bg,
            borderRadius: BorderRadius.circular(14),
          ),
          child: body,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: CalmCard(
        padding: const EdgeInsets.fromLTRB(12, 11, 12, 8),
        child: body,
      ),
    );
  }

  Widget _buildAvatar(CommentItem item, {bool isReply = false}) {
    final size = isReply ? 26.0 : 36.0;
    final fallback = CalmAvatar(
      text: item.authorName.let(convertChineseForDisplay),
      size: size,
    );
    if (item.avatarUrl.trim().isEmpty && item.avatarPath.trim().isEmpty) {
      return fallback;
    }
    final pictureInfo = PictureInfo(
      from: widget.from,
      url: item.avatarUrl,
      path: item.avatarPath,
      cartoonId: item.id,
      pictureType: PictureType.user,
    );
    return SizedBox(
      width: size,
      height: size,
      child: BlocProvider(
        create: (_) => PictureBloc()..add(GetPicture(pictureInfo)),
        child: BlocBuilder<PictureBloc, PictureLoadState>(
          builder: (context, state) {
            switch (state.status) {
              case PictureLoadStatus.initial:
                return CalmAvatar(icon: Icons.person_rounded, size: size);
              case PictureLoadStatus.success:
                if (pictureInfo.url.contains('nopic-Male.gif')) {
                  return ClipOval(
                    child: Image.asset(
                      'asset/image/assets/default_cover.png',
                      width: size,
                      height: size,
                      fit: BoxFit.cover,
                    ),
                  );
                }
                return GestureDetector(
                  onTap: () => context.pushRoute(
                    FullRouteImageRoute(imagePath: state.imagePath!),
                  ),
                  child: ClipOval(
                    child: SizedBox(
                      width: size,
                      height: size,
                      child: Image.file(
                        File(state.imagePath!),
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                );
              case PictureLoadStatus.failure:
                if (state.result.toString().contains('404')) {
                  return ClipOval(
                    child: Image.asset(
                      'asset/image/assets/default_cover.png',
                      width: size,
                      height: size,
                      fit: BoxFit.cover,
                    ),
                  );
                }
                return Tooltip(
                  message: t.common.reload,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: () {
                        context.read<PictureBloc>().add(
                          GetPicture(pictureInfo),
                        );
                      },
                      child: CalmAvatar(
                        icon: Icons.refresh_rounded,
                        size: size,
                      ),
                    ),
                  ),
                );
            }
          },
        ),
      ),
    );
  }

  /// 底部常驻评论输入条：轻盈 surface 底 + 胶囊输入框 + 主按钮发送。
  Widget _buildComposer(
    CommentsViewState state,
    CommentsCubit cubit, {
    required bool isLeftHand,
  }) {
    final c = context.calm;
    final field = Expanded(
      child: CalmTextField(
        controller: _composeController,
        hintText: t.comments.postCommentHint,
        prefixIcon: Icons.chat_bubble_outline_rounded,
        clearable: true,
        onSubmitted: (_) => _submitComposer(state, cubit),
      ),
    );
    final send = CalmButton(
      label: t.comments.confirm,
      icon: Icons.send_rounded,
      variant: CalmButtonVariant.primary,
      size: CalmButtonSize.sm,
      loading: state.posting,
      onPressed: state.posting ? null : () => _submitComposer(state, cubit),
    );

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.border)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: isLeftHand
            ? [send, const SizedBox(width: 8), field]
            : [field, const SizedBox(width: 8), send],
      ),
    );
  }

  Future<void> _submitComposer(
    CommentsViewState state,
    CommentsCubit cubit,
  ) async {
    if (state.posting) {
      return;
    }
    final content = _composeController.text.trim();
    if (content.isEmpty) {
      return;
    }
    await cubit.postComicComment(content);
    if (!mounted) {
      return;
    }
    if (cubit.state.noticeMessage == t.comments.postSuccess) {
      _composeController.clear();
    }
  }

  Future<void> _postReply(CommentsCubit cubit, CommentItem item) async {
    final content = await _openInputDialog(
      title: t.comments.postReply,
      hint: t.comments.postReplyHint,
    );
    if (content.isEmpty || !mounted) {
      return;
    }
    await cubit.postReply(item, content);
  }

  Future<String> _openInputDialog({
    required String title,
    required String hint,
  }) async {
    final controller = TextEditingController();
    final result = await showCalmDialog<String>(
      context,
      title: title,
      icon: Icons.chat_bubble_outline_rounded,
      maxWidth: 440,
      bodyBuilder: (ctx) => CalmTextArea(
        controller: controller,
        hintText: hint,
        minLines: 3,
        maxLines: 6,
      ),
      actionsBuilder: (ctx) => [
        CalmButton(
          label: t.comments.cancel,
          variant: CalmButtonVariant.ghost,
          onPressed: () => Navigator.of(ctx).pop(''),
        ),
        CalmButton(
          label: t.comments.confirm,
          variant: CalmButtonVariant.primary,
          onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
        ),
      ],
    );
    controller.dispose();
    return (result ?? '').trim();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) {
      return;
    }
    final max = _scrollController.position.maxScrollExtent;
    final current = _scrollController.offset;
    if (current >= max * 0.9) {
      _commentsCubit?.loadMore();
    }
  }
}
