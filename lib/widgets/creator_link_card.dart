import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:zephyr/config/router/router.gr.dart';
import 'package:zephyr/ui/ui.dart';
import 'package:zephyr/widgets/picture_bloc/bloc/picture_bloc.dart';
import 'package:zephyr/widgets/picture_bloc/models/picture_info.dart';
import 'package:zephyr/type/enum.dart';

/// 作者（创作者）信息卡片：头像 + 昵称 + 附加信息行 + 可点击进入详情。
///
/// 公开构造参数与旧版完全一致，仅外观迁移到 CalmUI 令牌。
class CreatorLinkCard extends StatefulWidget {
  const CreatorLinkCard({
    super.key,
    required this.creatorName,
    required this.avatarUrl,
    required this.avatarPath,
    required this.infoChildren,
    this.onTap,
    this.from = '',
    this.pictureType = PictureType.creator,
    this.imageKey = '',
    this.errorAssetPath = 'asset/image/assets/default_cover.png',
    this.padding = const EdgeInsets.symmetric(horizontal: 5.0),
  });

  final String creatorName;
  final String avatarUrl;
  final String avatarPath;
  final List<Widget> infoChildren;
  final VoidCallback? onTap;
  final String from;
  final PictureType pictureType;
  final String imageKey;
  final String errorAssetPath;
  final EdgeInsetsGeometry padding;

  @override
  State<CreatorLinkCard> createState() => _CreatorLinkCardState();
}

class _CreatorLinkCardState extends State<CreatorLinkCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    final pictureInfo = PictureInfo(
      from: widget.from,
      url: widget.avatarUrl,
      path: widget.avatarPath,
      cartoonId: widget.imageKey,
      chapterId: widget.imageKey,
      pictureType: widget.pictureType,
    );
    final tappable = widget.onTap != null;

    return Padding(
      padding: widget.padding,
      child: MouseRegion(
        cursor: tappable ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: CalmCard(
            padding: EdgeInsets.zero,
            radius: 16,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOut,
              padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
              decoration: BoxDecoration(
                color: _hovered ? c.surfaceHover : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _hovered ? c.accentBorder : c.border),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  _CreatorAvatarImage(
                    pictureInfo: pictureInfo,
                    errorAssetPath: widget.errorAssetPath,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          widget.creatorName,
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
                        ),
                        if (widget.infoChildren.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          ...widget.infoChildren,
                        ],
                      ],
                    ),
                  ),
                  if (tappable) ...[
                    const SizedBox(width: 8),
                    Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: _hovered ? c.accentSoft : c.surface2,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.chevron_right_rounded,
                        size: 15,
                        color: _hovered ? c.accent : c.text3,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CreatorAvatarImage extends StatelessWidget {
  const _CreatorAvatarImage({
    required this.pictureInfo,
    required this.errorAssetPath,
  });

  final PictureInfo pictureInfo;
  final String errorAssetPath;

  static const double _size = 46;

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    final hasRemoteOrLocalSource =
        pictureInfo.url.trim().isNotEmpty || pictureInfo.path.trim().isNotEmpty;

    Widget fallbackAsset() {
      return ClipOval(
        child: SizedBox(
          width: _size,
          height: _size,
          child: Image.asset(errorAssetPath, fit: BoxFit.cover),
        ),
      );
    }

    final avatar = !hasRemoteOrLocalSource
        ? fallbackAsset()
        : BlocProvider(
            create: (context) => PictureBloc()..add(GetPicture(pictureInfo)),
            child: BlocBuilder<PictureBloc, PictureLoadState>(
              builder: (context, state) {
                switch (state.status) {
                  case PictureLoadStatus.initial:
                    return Center(
                      child: LoadingAnimationWidget.waveDots(
                        color: c.accent,
                        size: 22,
                      ),
                    );
                  case PictureLoadStatus.success:
                    return MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () {
                          context.pushRoute(
                            FullRouteImageRoute(imagePath: state.imagePath!),
                          );
                        },
                        child: ClipOval(
                          child: SizedBox(
                            width: _size,
                            height: _size,
                            child: Image.file(
                              File(state.imagePath!),
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      ),
                    );
                  case PictureLoadStatus.failure:
                    if (state.result.toString().contains('404')) {
                      return fallbackAsset();
                    }
                    return MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () {
                          context.read<PictureBloc>().add(
                            GetPicture(pictureInfo),
                          );
                        },
                        child: Container(
                          width: _size,
                          height: _size,
                          decoration: BoxDecoration(
                            color: c.dangerSoft,
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.refresh_rounded,
                            size: 18,
                            color: c.danger,
                          ),
                        ),
                      ),
                    );
                }
              },
            ),
          );

    return SizedBox(
      width: _size + 4,
      height: _size + 4,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: c.accentBorder),
        ),
        child: Padding(padding: const EdgeInsets.all(2), child: avatar),
      ),
    );
  }
}
