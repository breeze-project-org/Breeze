import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/config/router/router.gr.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/setting/common/setting_ui.dart';
import 'package:zephyr/page/setting/global/widgets.dart';
import 'package:zephyr/util/network/network_policy.dart';
import 'package:zephyr/widgets/fluent_dropdown.dart';

@RoutePage()
class ContentNetworkSettingPage extends StatelessWidget {
  const ContentNetworkSettingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<GlobalSettingCubit>();
    final state = cubit.state;

    return SettingPageShell(
      title: t.settings.contentAndNetwork,
      child: ListView(
        padding: kSettingPagePadding,
        children: [
          settingSectionTitle(
            context,
            t.settings.content,
            icon: Icons.filter_alt_outlined,
          ),
          settingCardGroup([
            editMaskedKeywords(context),
            editMaskedCommentKeywords(context),
            if (state.showSearchBookmark)
              _searchBookmarkProbePages(state, cubit),
            _chineseConvertMode(state, cubit),
          ]),
          settingSectionTitle(
            context,
            t.settings.network,
            icon: Icons.wifi_outlined,
          ),
          settingCardGroup([
            proxyToggle(
              context,
              enabled: state.proxySetting.enabled,
              type: state.proxySetting.type,
              currentProxy: state.proxySetting.address,
            ),
            settingCategoryTile(
              icon: Icons.dns_outlined,
              title: t.settings.doh,
              subtitle: state.dohSetting.enabled
                  ? t.settings.dohProviderCount(
                      count: state.dohSetting.providers.length,
                    )
                  : t.common.disabled,
              onTap: () => context.pushRoute(const DohSettingRoute()),
            ),
            settingSwitchTile(
              icon: Icons.lan_outlined,
              title: t.settings.blockPrivateNetwork,
              subtitle: t.settings.blockPrivateNetworkSubtitle,
              value: state.blockPrivateNetwork,
              onChanged: (value) {
                cubit.updateState(
                  (current) => current.copyWith(blockPrivateNetwork: value),
                );
                // 立刻生效：配置变更会同步到已加载的插件。
                applyPrivateNetworkPolicy(blockPrivateNetwork: value);
              },
            ),
            settingSwitchTile(
              icon: Icons.download_outlined,
              title: t.settings.retryDownloadUntilSuccess,
              subtitle: t.settings.retryDownloadUntilSuccessSubtitle,
              value: state.retryDownloadUntilSuccess,
              onChanged: (value) {
                cubit.updateState(
                  (current) =>
                      current.copyWith(retryDownloadUntilSuccess: value),
                );
              },
            ),
          ]),
          // _updateAccelerate(state, cubit),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _searchBookmarkProbePages(
    GlobalSettingState state,
    GlobalSettingCubit cubit,
  ) {
    const options = [0, 1, 2, 3, 5];
    final current = options.contains(state.searchBookmarkProbePages)
        ? state.searchBookmarkProbePages
        : 3;
    return CalmListTile(
      leading: settingTileIcon(Icons.manage_search_outlined),
      title: t.searchBookmark.probePages,
      subtitle: t.searchBookmark.probePagesSubtitle,
      trailing: FluentDropdown<int>(
        value: current,
        displayValue: '$current',
        items: {for (final v in options) v: '$v'},
        onChanged: (int value) {
          cubit.updateState(
            (current) => current.copyWith(searchBookmarkProbePages: value),
          );
        },
      ),
    );
  }

  Widget _chineseConvertMode(
    GlobalSettingState state,
    GlobalSettingCubit cubit,
  ) {
    final chineseConvertItems = <ChineseConvertMode, String>{
      ChineseConvertMode.off: t.settings.chineseConvertOff,
      ChineseConvertMode.simplified: t.settings.chineseConvertSimplified,
      ChineseConvertMode.traditional: t.settings.chineseConvertTraditional,
    };

    return CalmListTile(
      leading: settingTileIcon(Icons.translate_outlined),
      title: t.settings.chineseConvert,
      subtitle: t.settings.chineseConvertSubtitle,
      trailing: FluentDropdown<ChineseConvertMode>(
        value: state.chineseConvertMode,
        displayValue: chineseConvertItems[state.chineseConvertMode]!,
        items: chineseConvertItems,
        onChanged: (ChineseConvertMode value) {
          if (value == state.chineseConvertMode) return;
          cubit.updateState(
            (current) => current.copyWith(chineseConvertMode: value),
          );
        },
      ),
    );
  }

  // Widget _updateAccelerate(GlobalSettingState state, GlobalSettingCubit cubit) {
  //   return settingSwitchTile(
  //     icon: Icons.rocket_launch_outlined,
  //     title: t.settings.updateAccelerate,
  //     subtitle: t.settings.updateAccelerateSubtitle,
  //     value: state.updateAccelerate,
  //     onChanged: (bool value) {
  //       cubit.updateState(
  //         (current) => current.copyWith(updateAccelerate: value),
  //       );
  //     },
  //   );
  // }
}
