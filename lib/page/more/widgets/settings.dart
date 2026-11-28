import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/config/router/router.gr.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/comic_follow/cubit/comic_follow_cubit.dart';
import 'package:zephyr/page/setting/common/setting_ui.dart';
import 'package:zephyr/service/update/check_update.dart';
import 'package:zephyr/service/update/json/github_release_json.dart';

class SettingsWidget extends StatelessWidget {
  const SettingsWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        settingSectionTitle(
          context,
          t.more.common,
          icon: Icons.widgets_outlined,
        ),
        settingCardGroup([
          settingActionTile(
            icon: Icons.download_outlined,
            title: t.more.downloadTasks,
            onTap: () => context.pushRoute(DownloadTaskRoute()),
          ),
          settingActionTile(
            icon: Icons.sync_outlined,
            title: t.more.sync,
            onTap: () => context.pushRoute(SyncSettingRoute()),
          ),
          BlocSelector<ComicFollowCubit, ComicFollowState, int>(
            selector: (state) => state.updateCount,
            builder: (context, updateCount) {
              return _ChevronTile(
                icon: Icons.notifications_active_outlined,
                title: t.more.comicFollow,
                badge: updateCount > 0
                    ? _NewBadge(count: updateCount)
                    : null,
                onTap: () => context.pushRoute(ComicFollowRoute()),
              );
            },
          ),
          BlocSelector<GlobalSettingCubit, GlobalSettingState, bool>(
            selector: (state) => state.showSearchBookmark,
            builder: (context, showSearchBookmark) {
              if (!showSearchBookmark) {
                return const SizedBox.shrink();
              }
              return settingActionTile(
                icon: Icons.bookmark_outline,
                title: t.searchBookmark.title,
                onTap: () => context.pushRoute(const SearchBookmarkRoute()),
              );
            },
          ),
          settingActionTile(
            icon: Icons.settings_outlined,
            title: t.settings.globalTitle,
            onTap: () => context.pushRoute(GlobalSettingRoute()),
          ),
        ]),
        settingSectionTitle(context, t.more.others, icon: Icons.more_horiz),
        settingCardGroup([
          // 检测到可用更新时在「更新日志」条目挂 NEW 徽标；只做提示，不额外发通知。
          ValueListenableBuilder<GithubReleaseJson?>(
            valueListenable: pendingAppUpdate,
            builder: (context, pendingUpdate, _) {
              return _ChevronTile(
                icon: Icons.history_rounded,
                title: t.more.changelog,
                badge: pendingUpdate != null ? const _NewBadge() : null,
                onTap: () => context.pushRoute(ChangelogRoute()),
              );
            },
          ),
          settingActionTile(
            icon: Icons.info_outline_rounded,
            title: t.about.title,
            onTap: () => context.pushRoute(AboutRoute()),
          ),
        ]),
      ],
    );
  }
}

/// 带尾部徽章与柔和右箭头的设置行。
class _ChevronTile extends StatelessWidget {
  const _ChevronTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.badge,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    return CalmListTile(
      leading: settingTileIcon(icon),
      title: title,
      onTap: onTap,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ?badge,
          Icon(
            Icons.chevron_right_rounded,
            size: 18,
            color: context.calm.text3,
          ),
        ],
      ),
    );
  }
}

/// 本地化的 NEW 徽标：追更未读数达到 99 时显示 99+。
class _NewBadge extends StatelessWidget {
  const _NewBadge({this.count});

  final int? count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: CalmBadge(
        label: (count ?? 0) >= 99 ? '99+' : t.more.newBadge,
        tone: CalmBadgeTone.danger,
      ),
    );
  }
}
