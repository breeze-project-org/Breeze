import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/ui/ui.dart';
import 'package:zephyr/widgets/picture_bloc/models/picture_info.dart';

import 'package:zephyr/config/router/router.gr.dart';
import 'package:zephyr/widgets/picture_bloc/bloc/picture_bloc.dart';

class Cover extends StatefulWidget {
  final PictureInfo pictureInfo;
  final double height;
  final double borderRadius;
  final VoidCallback? onTap;

  const Cover({
    super.key,
    required this.pictureInfo,
    this.height = 180,
    this.borderRadius = 16,
    this.onTap,
  });

  @override
  State<Cover> createState() => _CoverState();
}

class _CoverState extends State<Cover> {
  late final PictureBloc _bloc;

  @override
  void initState() {
    super.initState();
    _bloc = PictureBloc()..add(GetPicture(widget.pictureInfo));
  }

  @override
  void didUpdateWidget(covariant Cover oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldInfo = oldWidget.pictureInfo;
    final nextInfo = widget.pictureInfo;
    if (oldInfo.from != nextInfo.from ||
        oldInfo.cartoonId != nextInfo.cartoonId ||
        oldInfo.path != nextInfo.path ||
        oldInfo.url != nextInfo.url ||
        oldInfo.chapterId != nextInfo.chapterId ||
        oldInfo.pictureType != nextInfo.pictureType) {
      // 详情页编辑返回后封面路径会变；复用同一个 bloc，但必须发新请求。
      _bloc.add(GetPicture(nextInfo));
    }
  }

  @override
  void dispose() {
    _bloc.close();
    super.dispose();
  }

  /// 墨水屏模式：不驱动任何持续动画（骨架/转圈都会留下残影）。
  bool _removeLoadingAnimation() {
    try {
      return context.select<GlobalSettingCubit, bool>(
        (cubit) => cubit.state.eInkSetting.shouldRemoveLoadingSpinner,
      );
    } catch (_) {
      // 没有全局设置作用域时（预览/单测）按普通模式处理。
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    final width = widget.height / 4 * 3;
    final radius = BorderRadius.circular(widget.borderRadius);
    final staticPlaceholder = _removeLoadingAnimation();

    return SizedBox(
      height: widget.height,
      width: width,
      child: BlocProvider.value(
        value: _bloc,
        child: BlocBuilder<PictureBloc, PictureLoadState>(
          builder: (context, state) {
            switch (state.status) {
              case PictureLoadStatus.initial:
                return staticPlaceholder
                    ? Container(
                        decoration: BoxDecoration(
                          borderRadius: radius,
                          color: c.surface2,
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.auto_stories_outlined,
                          size: 26,
                          color: c.text3.withValues(alpha: 0.55),
                        ),
                      )
                    : CalmSkeletonBox(
                        width: width,
                        height: widget.height,
                        radius: widget.borderRadius,
                      );
              case PictureLoadStatus.success:
                return MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap:
                        widget.onTap ??
                        () {
                          context.pushRoute(
                            FullRouteImageRoute(imagePath: state.imagePath!),
                          );
                        },
                    child: ClipRRect(
                      borderRadius: radius,
                      child: Image.file(
                        File(state.imagePath!),
                        fit: BoxFit.cover,
                        width: width,
                        height: widget.height,
                      ),
                    ),
                  ),
                );
              case PictureLoadStatus.failure:
                if (state.result.toString().contains('404')) {
                  return ClipRRect(
                    borderRadius: radius,
                    child: Image.asset(
                      'asset/image/error_image/404.png',
                      fit: BoxFit.cover,
                    ),
                  );
                }
                return MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () {
                      context.read<PictureBloc>().add(
                        GetPicture(widget.pictureInfo),
                      );
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: radius,
                        color: c.surface2,
                      ),
                      alignment: Alignment.center,
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: c.surface,
                          shape: BoxShape.circle,
                          boxShadow: c.shadowSm,
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.refresh_rounded,
                          size: 17,
                          color: c.text2,
                        ),
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
}
