import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/router/router.gr.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/comic_info/bloc/comic_preview_bloc.dart';
import 'package:zephyr/page/comic_info/models/unified_plugin_preview.dart';
import 'package:zephyr/type/enum.dart';
import 'package:zephyr/ui/ui.dart';
import 'package:zephyr/widgets/picture_bloc/bloc/picture_bloc.dart';
import 'package:zephyr/widgets/picture_bloc/models/picture_info.dart';

class ComicPreviewSliver extends StatelessWidget {
  const ComicPreviewSliver({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ComicPreviewBloc, ComicPreviewState>(
      builder: (context, state) {
        if (state.status == ComicPreviewStatus.failure && state.items.isEmpty) {
          return SliverMainAxisGroup(
            slivers: [
              _header(context),
              SliverToBoxAdapter(child: _initialFailure(context)),
            ],
          );
        }

        if (state.status == ComicPreviewStatus.success &&
            state.items.isEmpty &&
            state.hasReachedMax) {
          return const SliverToBoxAdapter(child: SizedBox.shrink());
        }

        return SliverMainAxisGroup(
          slivers: [
            _header(context),
            if (state.status == ComicPreviewStatus.initial &&
                state.items.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Center(child: CalmLoading()),
                ),
              )
            else ...[
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 180,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 0.72,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => _ComicPreviewTile(
                      key: ValueKey(_itemKey(state.items[index], index)),
                      item: state.items[index],
                      comicId: context.read<ComicPreviewBloc>().comicId,
                      from: context.read<ComicPreviewBloc>().from,
                    ),
                    childCount: state.items.length,
                  ),
                ),
              ),
              if (state.status == ComicPreviewStatus.loadingMore)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    child: Center(child: CalmLoading()),
                  ),
                ),
              _footer(context, state),
            ],
          ],
        );
      },
    );
  }

  SliverToBoxAdapter _header(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 12),
        child: CalmSectionHeader(title: t.comicInfo.preview),
      ),
    );
  }

  Widget _initialFailure(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Center(
        child: CalmButton(
          label: t.searchResult.retry,
          icon: Icons.refresh_rounded,
          variant: CalmButtonVariant.tonal,
          onPressed: () =>
              context.read<ComicPreviewBloc>().add(const LoadComicPreview()),
        ),
      ),
    );
  }

  Widget _footer(BuildContext context, ComicPreviewState state) {
    if (state.hasReachedMax) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    if (state.status == ComicPreviewStatus.getMoreFailure) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Center(
            child: CalmButton(
              label: t.oldHome.loadMoreFailed,
              icon: Icons.refresh_rounded,
              variant: CalmButtonVariant.tonal,
              size: CalmButtonSize.xs,
              onPressed: () => context.read<ComicPreviewBloc>().add(
                const LoadComicPreview(loadMore: true),
              ),
            ),
          ),
        ),
      );
    }
    if (state.status == ComicPreviewStatus.loadingMore) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 14),
        child: Center(
          child: CalmButton(
            label: t.oldHome.loadMore,
            trailingIcon: Icons.keyboard_arrow_down_rounded,
            variant: CalmButtonVariant.ghost,
            size: CalmButtonSize.xs,
            onPressed: () => context.read<ComicPreviewBloc>().add(
              const LoadComicPreview(loadMore: true),
            ),
          ),
        ),
      ),
    );
  }

  String _itemKey(UnifiedPluginPreviewItem item, int index) {
    if (item.id.trim().isNotEmpty) return item.id;
    return '${item.path}|${item.url}|$index';
  }
}

class _ComicPreviewTile extends StatelessWidget {
  const _ComicPreviewTile({
    super.key,
    required this.item,
    required this.comicId,
    required this.from,
  });

  final UnifiedPluginPreviewItem item;
  final String comicId;
  final String from;

  @override
  Widget build(BuildContext context) {
    final pictureInfo = PictureInfo(
      from: from,
      url: item.url,
      path: item.path,
      cartoonId: comicId,
      chapterId: 'preview',
      pictureType: PictureType.comic,
      extern: item.extern,
    );
    return BlocProvider(
      create: (_) => PictureBloc()..add(GetPicture(pictureInfo)),
      child: BlocBuilder<PictureBloc, PictureLoadState>(
        builder: (context, state) {
          switch (state.status) {
            case PictureLoadStatus.initial:
              // 静态占位：预览图数量多，持续动画在墨水屏上会拖出残影。
              return _tileBackground(
                context,
                Icon(
                  Icons.image_outlined,
                  size: 18,
                  color: context.calm.text3.withValues(alpha: 0.7),
                ),
              );
            case PictureLoadStatus.success:
              return MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => context.pushRoute(
                    FullRouteImageRoute(imagePath: state.imagePath!),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: _tileBackground(
                      context,
                      Image.file(
                        File(state.imagePath!),
                        fit: BoxFit.contain,
                        cacheWidth: 360,
                      ),
                    ),
                  ),
                ),
              );
            case PictureLoadStatus.failure:
              return MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () =>
                      context.read<PictureBloc>().add(GetPicture(pictureInfo)),
                  child: _tileBackground(
                    context,
                    Icon(
                      Icons.refresh_rounded,
                      size: 18,
                      color: context.calm.text2,
                    ),
                  ),
                ),
              );
          }
        },
      ),
    );
  }

  Widget _tileBackground(BuildContext context, Widget child) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.calm.surface2,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Center(child: child),
    );
  }
}
