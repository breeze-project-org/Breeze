import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/setting/common/setting_ui.dart';

@RoutePage()
class ComicDetailSettingPage extends StatelessWidget {
  const ComicDetailSettingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<GlobalSettingCubit>();
    final state = cubit.state.comicDetailSetting;

    return SettingPageShell(
      title: t.settings.comicDetail,
      child: ListView(
        padding: kSettingPagePadding,
        children: [
          settingSectionTitle(
            context,
            t.settings.comicDetailActions,
            icon: Icons.widgets_outlined,
          ),
          settingCardGroup([
            _actionTile(
              icon: Icons.favorite_border,
              title: t.settings.comicDetailShowLike,
              subtitle: t.settings.comicDetailShowLikeSubtitle,
              value: state.showLikeAction,
              onChanged: (value) => cubit.updateComicDetailSetting(
                (current) => current.copyWith(showLikeAction: value),
              ),
            ),
            _actionTile(
              icon: Icons.mode_comment_outlined,
              title: t.settings.comicDetailShowComment,
              subtitle: t.settings.comicDetailShowCommentSubtitle,
              value: state.showCommentAction,
              onChanged: (value) => cubit.updateComicDetailSetting(
                (current) => current.copyWith(showCommentAction: value),
              ),
            ),
            _actionTile(
              icon: Icons.star_border,
              title: t.settings.comicDetailShowLocalCollect,
              subtitle: t.settings.comicDetailShowLocalCollectSubtitle,
              value: state.showLocalCollectAction,
              onChanged: (value) => cubit.updateComicDetailSetting(
                (current) => current.copyWith(showLocalCollectAction: value),
              ),
            ),
            _actionTile(
              icon: Icons.cloud_outlined,
              title: t.settings.comicDetailShowCloudCollect,
              subtitle: t.settings.comicDetailShowCloudCollectSubtitle,
              value: state.showCloudCollectAction,
              onChanged: (value) => cubit.updateComicDetailSetting(
                (current) => current.copyWith(showCloudCollectAction: value),
              ),
            ),
          ]),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _actionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return settingSwitchTile(
      icon: icon,
      title: title,
      subtitle: subtitle,
      value: value,
      onChanged: onChanged,
    );
  }
}
