import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/config/router/router.gr.dart';
import 'package:zephyr/ui/ui.dart';
import 'package:zephyr/widgets/picture_bloc/bloc/picture_bloc.dart';
import 'package:zephyr/widgets/picture_bloc/models/picture_info.dart';

/// 用户头像（CalmUI 版）：圆角描边环 + 柔和底色兜底，点击可看大图。
class UserAvatar extends StatelessWidget {
  final PictureInfo pictureInfo;

  const UserAvatar({super.key, required this.pictureInfo});

  static const double _size = 75;

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    return SizedBox(
      height: _size,
      width: _size,
      child: BlocProvider(
        create: (context) => PictureBloc()..add(GetPicture(pictureInfo)),
        child: BlocBuilder<PictureBloc, PictureLoadState>(
          builder: (context, state) {
            switch (state.status) {
              case PictureLoadStatus.initial:
                return _frame(child: const Center(child: CalmLoading()));
              case PictureLoadStatus.success:
                return GestureDetector(
                  onTap: () {
                    context.pushRoute(
                      FullRouteImageRoute(imagePath: state.imagePath!),
                    );
                  },
                  child: _frame(
                    child: pictureInfo.url.contains('nopic-Male.gif')
                        ? Image.asset(
                            'asset/image/assets/default_cover.png',
                            fit: BoxFit.cover,
                          )
                        : Image.file(
                            File(state.imagePath!),
                            fit: BoxFit.cover,
                          ),
                  ),
                );
              case PictureLoadStatus.failure:
                if (state.result.toString().contains('404')) {
                  return _frame(
                    child: Image.asset(
                      'asset/image/assets/default_cover.png',
                      fit: BoxFit.cover,
                    ),
                  );
                }
                return _frame(
                  child: Center(
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () {
                          context.read<PictureBloc>().add(
                            GetPicture(pictureInfo),
                          );
                        },
                        child: Icon(
                          Icons.refresh_rounded,
                          size: 20,
                          color: c.text3,
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

  Widget _frame({required Widget child}) {
    return Builder(
      builder: (context) {
        final c = context.calm;
        return Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: c.surface2,
            border: Border.all(color: c.accentBorder, width: 1.5),
          ),
          clipBehavior: Clip.antiAlias,
          child: child,
        );
      },
    );
  }
}
