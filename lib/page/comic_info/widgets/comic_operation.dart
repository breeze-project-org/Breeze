import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/page/comic_info/models/favorite_workflow.dart';
import 'package:zephyr/page/comic_info/json/normal/normal_comic_all_info.dart';
import 'package:zephyr/page/comic_info/models/collect_comic.dart';
import 'package:zephyr/page/comic_follow/cubit/comic_follow_cubit.dart';
import 'package:zephyr/util/error/error_filter.dart';
import 'package:zephyr/config/router/router.gr.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/ui/ui.dart';

import 'package:zephyr/widgets/dialog.dart';
import 'package:zephyr/widgets/toast.dart';
import 'package:zephyr/object_box/model.dart';
import 'package:zephyr/page/bookshelf/widgets/folder_target_picker.dart';
import 'package:zephyr/main.dart';

class ComicOperationWidget extends StatefulWidget {
  final NormalComicAllInfo normalInfo;
  final String from;
  final String? collectionTargetId;
  final String? collectionTargetName;
  final dynamic comicInfo;

  /// 页面首帧的本地收藏状态，由详情 bloc 与详情一起读出；
  /// 不再由本组件异步查库，避免先显示「未收藏」再跳变。
  final bool initialCollected;

  const ComicOperationWidget({
    super.key,
    required this.normalInfo,
    required this.from,
    this.collectionTargetId,
    this.collectionTargetName,
    required this.comicInfo,
    required this.initialCollected,
  });

  @override
  State<ComicOperationWidget> createState() => _ComicOperationWidgetState();
}

class _ComicOperationWidgetState extends State<ComicOperationWidget> {
  dynamic get comicInfo => widget.comicInfo;
  NormalComicAllInfo get normalInfo => widget.normalInfo;
  ComicInfo get comicInfoView => normalInfo.comicInfo;
  late bool isCollected = widget.initialCollected;
  bool isLiked = false;
  bool isCloudCollected = false;

  @override
  void initState() {
    super.initState();
    isLiked = normalInfo.isLiked;
    isCloudCollected = normalInfo.isFavourite;
  }

  @override
  void didUpdateWidget(ComicOperationWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 刷新/重进后 bloc 会给出新的收藏快照；本组件未销毁时需要跟上。
    if (oldWidget.initialCollected != widget.initialCollected) {
      isCollected = widget.initialCollected;
    }
  }

  Future<void> _autoFollowIfEnabled() async {
    if (!context.read<GlobalSettingCubit>().state.autoFollowOnCollect) {
      return;
    }
    final followCubit = context.read<ComicFollowCubit>();
    final comicId = comicInfoView.id;
    if (followCubit.isFollowing(widget.from, comicId)) {
      return;
    }
    await followCubit.addOrUpdateFollow(
      source: widget.from,
      comicId: comicId,
      info: normalInfo,
      lastChapterCount: normalInfo.eps.length,
    );
  }

  /// 本地收藏成功后自动触发一次云收藏：仅开关开启、本地刚成功、云端未收藏时执行。
  /// 云端是否已收藏以页面初始快照 [isCloudCollected] 为准；执行失败只提示不抛错，
  /// 不影响本地收藏结果。插件不支持云收藏时静默跳过。
  Future<void> _autoCloudCollectIfEnabled() async {
    if (!context
        .read<GlobalSettingCubit>()
        .state
        .autoCloudCollectOnLocalFavorite) {
      return;
    }
    if (isCloudCollected) return;
    try {
      final next = await toggleCloudComicFavorite(
        context: context,
        from: widget.from,
        comicId: comicInfoView.id,
        currentStatus: false,
        legacyAllowCollected: normalInfo.allowCollected,
        legacyAllowCollectedReason: normalInfo.allowCollectedReason,
        collectionTargetId: widget.collectionTargetId,
        collectionTargetName: widget.collectionTargetName,
      );
      if (!mounted) return;
      setState(() {
        isCloudCollected = next;
      });
      if (next) {
        showSuccessToast(t.comicInfo.cloudCollectSuccess);
      }
    } on FavoriteWorkflowUnsupportedException catch (error) {
      logger.e(error);
    } on FavoriteWorkflowIncompleteException catch (error) {
      logger.e(error);
      if (mounted) {
        showInfoToast(
          error.result.message ?? t.comicInfo.cloudCollectIncomplete,
        );
      }
    } catch (error) {
      logger.e(error);
      if (!mounted) return;
      showErrorToast(
        normalizeSearchErrorMessage(error),
        duration: const Duration(seconds: 5),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    final detailSetting = context
        .watch<GlobalSettingCubit>()
        .state
        .comicDetailSetting;
    final localCollectItem = _OperationItemData(
      icon: isCollected ? Icons.star_rounded : Icons.star_border_rounded,
      text: isCollected ? t.comicInfo.collected : t.comicInfo.collect,
      highlighted: isCollected,
      accentColor: c.warning,
      enabled: true,
      onTap: _toggleLocalFavorite,
      onLongPress: _chooseLocalFavoriteFolders,
    );
    final cloudCollectItem = _OperationItemData(
      icon: isCloudCollected ? Icons.cloud_done_outlined : Icons.cloud_outlined,
      text: isCloudCollected
          ? t.comicInfo.cloudCollected
          : t.comicInfo.cloudCollect,
      highlighted: isCloudCollected,
      accentColor: c.accent,
      enabled: true,
      onTap: _toggleCloudFavorite,
    );
    final actions = <_OperationItemData>[
      if (detailSetting.showLikeAction)
        _OperationItemData(
          icon: isLiked
              ? Icons.favorite_rounded
              : Icons.favorite_border_rounded,
          text: t.comicInfo.likes(count: normalInfo.totalLikes),
          highlighted: isLiked,
          accentColor: c.danger,
          enabled: normalInfo.allowLike,
          onTap: _toggleCloudLike,
        ),
      if (detailSetting.showCommentAction)
        _OperationItemData(
          icon: Icons.mode_comment_outlined,
          text: t.comicInfo.comments(count: normalInfo.totalComments),
          enabled: normalInfo.allowComments,
          onTap: _openComments,
        ),
      if (detailSetting.showLocalCollectAction) localCollectItem,
      if (detailSetting.showCloudCollectAction) cloudCollectItem,
    ];
    if (actions.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      width: double.infinity,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isDesktop = constraints.maxWidth >= 900;
          const spacing = 10.0;
          // 按可见按钮数重排：窄屏最多 2 个一行、其余最多 4 个一行；
          // 单个按钮限宽避免被拉成整行。
          final maxPerRow = constraints.maxWidth < 420 ? 2 : 4;
          final perRow = actions.length < maxPerRow
              ? actions.length
              : maxPerRow;
          final itemWidth = isDesktop
              ? 136.0
              : ((constraints.maxWidth - spacing * (perRow - 1)) / perRow)
                    .clamp(0.0, 220.0)
                    .toDouble();

          return Center(
            child: Wrap(
              spacing: spacing,
              runSpacing: spacing,
              alignment: WrapAlignment.center,
              children: actions
                  .map(
                    (item) => SizedBox(
                      width: itemWidth,
                      child: _OperationCard(item: item, compact: isDesktop),
                    ),
                  )
                  .toList(),
            ),
          );
        },
      ),
    );
  }

  void _openComments() {
    if (!normalInfo.allowComments) {
      final reason = normalInfo.allowCommentsReason.trim();
      commonDialog(
        context,
        t.comicInfo.commentForbiddenTitle,
        reason.isNotEmpty ? reason : t.comicInfo.commentForbidden,
      );
      return;
    }

    context.pushRoute(
      PluginCommentsScaffoldRoute(
        from: widget.from,
        comicId: comicInfoView.id.toString(),
        comicTitle: comicInfoView.title,
      ),
    );
  }

  Future<void> _toggleLocalFavorite() async {
    try {
      // 取消收藏需要确认，因为会删除所有文件夹中的记录
      if (isCollected) {
        final confirmed = await _showUncollectConfirmDialog();
        if (!confirmed) {
          return;
        }
      }

      final next = await toggleLocalComicFavorite(
        from: widget.from,
        normalInfo: normalInfo,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        isCollected = next;
      });
      if (next) {
        await _autoFollowIfEnabled();
        await _autoCloudCollectIfEnabled();
        if (!mounted) return;
        showSuccessToast(t.comicInfo.addedToCollection);
      } else {
        showSuccessToast(t.comicInfo.removedFromCollection);
      }
    } catch (error) {
      logger.e(error);
      if (!mounted) {
        return;
      }
      showErrorToast(
        t.comicInfo.localCollectFailed(
          error: normalizeSearchErrorMessage(error),
        ),
        duration: const Duration(seconds: 5),
      );
    }
  }

  /// 本地收藏长按：选择归属文件夹（支持多选，可原地新建）。
  /// 未收藏时长按直接建收藏；已收藏时按所选重设链接。
  /// 空选确认（仅剩根目录不勾时）视为取消收藏，需二次确认。
  Future<void> _chooseLocalFavoriteFolders() async {
    try {
      final initialSelected = await localComicFavoriteFolderPaths(
        from: widget.from,
        comicId: comicInfoView.id,
      );
      if (!mounted) return;
      final picked = await showFolderTargetPicker(
        context,
        type: ComicFolderType.favorite,
        initialSelectedPaths: initialSelected,
        allowEmptyConfirm: true,
        title: t.comicInfo.chooseLocalFavoriteFolders,
      );
      if (picked == null || !mounted) return;

      if (picked.isEmpty) {
        if (!isCollected) return;
        final confirmed = await _showUncollectConfirmDialog();
        if (!confirmed || !mounted) return;
        final next = await toggleLocalComicFavorite(
          from: widget.from,
          normalInfo: normalInfo,
        );
        if (!mounted) return;
        setState(() {
          isCollected = next;
        });
        showSuccessToast(t.comicInfo.removedFromCollection);
        return;
      }

      if (picked.length == 1 &&
          initialSelected.length == 1 &&
          picked.single == initialSelected.single &&
          isCollected) {
        return;
      }
      final next = await setLocalComicFavoriteFolders(
        from: widget.from,
        normalInfo: normalInfo,
        targetPaths: picked,
      );
      final wasNewFavorite = !isCollected && next;
      if (!mounted) return;
      setState(() {
        isCollected = next;
      });
      if (wasNewFavorite) {
        await _autoFollowIfEnabled();
        await _autoCloudCollectIfEnabled();
        if (!mounted) return;
      }
      showSuccessToast(t.comicInfo.addedToCollection);
    } catch (error) {
      logger.e(error);
      if (!mounted) return;
      showErrorToast(
        t.comicInfo.localCollectFailed(
          error: normalizeSearchErrorMessage(error),
        ),
        duration: const Duration(seconds: 5),
      );
    }
  }

  Future<void> _toggleCloudFavorite() async {
    try {
      showInfoToast(
        isCloudCollected
            ? t.comicInfo.removingCloudCollection
            : t.comicInfo.collectingToCloud,
      );
      final next = await toggleCloudComicFavorite(
        context: context,
        from: widget.from,
        comicId: comicInfoView.id,
        currentStatus: isCloudCollected,
        legacyAllowCollected: normalInfo.allowCollected,
        legacyAllowCollectedReason: normalInfo.allowCollectedReason,
        collectionTargetId: widget.collectionTargetId,
        collectionTargetName: widget.collectionTargetName,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        isCloudCollected = next;
      });
      if (next) {
        await _autoFollowIfEnabled();
      }
      showSuccessToast(
        next
            ? t.comicInfo.cloudCollectSuccess
            : t.comicInfo.cloudUncollectSuccess,
      );
    } on FavoriteWorkflowUnsupportedException catch (error) {
      logger.e(error);
      if (mounted) {
        final reason = error.reason.trim();
        showInfoToast(
          reason.isNotEmpty ? reason : t.comicInfo.cloudCollectDisabled,
        );
      }
    } on FavoriteWorkflowIncompleteException catch (error) {
      logger.e(error);
      if (mounted) {
        showInfoToast(
          error.result.message ?? t.comicInfo.cloudCollectIncomplete,
        );
      }
    } catch (error) {
      logger.e(error);
      if (!mounted) {
        return;
      }
      showErrorToast(
        normalizeSearchErrorMessage(error),
        duration: const Duration(seconds: 5),
      );
    }
  }

  Future<bool> _showUncollectConfirmDialog() async {
    final confirmed = await showCalmDialog<bool>(
      context,
      title: t.comicInfo.confirmUncollectTitle,
      icon: Icons.star_border_rounded,
      tone: CalmTone.warning,
      bodyBuilder: (dialogContext) => Text(
        t.comicInfo.confirmUncollectContent,
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
          label: t.common.confirm,
          variant: CalmButtonVariant.danger,
          onPressed: () => Navigator.of(dialogContext).pop(true),
        ),
      ],
    );
    return confirmed == true;
  }

  Future<void> _toggleCloudLike() async {
    if (!normalInfo.allowLike) {
      final reason = normalInfo.allowLikeReason.trim();
      showInfoToast(reason.isNotEmpty ? reason : t.comicInfo.likeDisabled);
      return;
    }
    try {
      showInfoToast(isLiked ? t.comicInfo.unliking : t.comicInfo.liking);
      final next = await toggleCloudComicLike(
        from: widget.from,
        comicId: comicInfoView.id,
        currentStatus: isLiked,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        isLiked = next;
      });
      showSuccessToast(
        next ? t.comicInfo.likeSuccess : t.comicInfo.unlikeSuccess,
      );
    } catch (error) {
      logger.e(error);
      if (!mounted) {
        return;
      }
      showErrorToast(
        t.comicInfo.likeFailed(error: normalizeSearchErrorMessage(error)),
        duration: const Duration(seconds: 5),
      );
    }
  }
}

class _OperationItemData {
  const _OperationItemData({
    required this.icon,
    required this.text,
    this.onTap,
    this.onLongPress,
    this.enabled = true,
    this.highlighted = false,
    this.accentColor,
  });

  final IconData icon;
  final String text;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool enabled;
  final bool highlighted;
  final Color? accentColor;
}

class _OperationCard extends StatelessWidget {
  const _OperationCard({required this.item, this.compact = false});

  final _OperationItemData item;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    final accent = item.accentColor ?? c.accent;
    final background = item.highlighted
        ? accent.withValues(alpha: 0.12)
        : c.surface;
    final foreground = !item.enabled
        ? c.text3
        : item.highlighted
        ? accent
        : c.text;

    return MouseRegion(
      cursor: item.enabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: item.onTap,
        onLongPress: item.onLongPress,
        child: CalmCard(
          radius: 14,
          color: background,
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 8 : 10,
            vertical: compact ? 10 : 11,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(item.icon, size: compact ? 17 : 19, color: foreground),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  item.text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textHeightBehavior: kCalmTextHeightBehavior,
                  strutStyle: calmStrut(compact ? 12 : 12.5),
                  style: TextStyle(
                    fontSize: compact ? 12 : 12.5,
                    color: foreground,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                    leadingDistribution: TextLeadingDistribution.even,
                    fontFeatures: const [FontFeature.tabularFigures()],
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
