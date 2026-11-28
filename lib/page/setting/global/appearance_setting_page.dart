import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/config/router/router.gr.dart';
import 'package:zephyr/i18n/i18n_helper.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/i18n/system_locale_service.dart';
import 'package:zephyr/page/font_setting/view/font_setting_page.dart';
import 'package:zephyr/page/setting/common/setting_ui.dart';
import 'package:zephyr/page/setting/global/widgets.dart';
import 'package:zephyr/util/ohos/platform.dart';
import 'package:zephyr/widgets/fluent_dropdown.dart';
import 'package:zephyr/widgets/toast.dart';

@RoutePage()
class AppearanceSettingPage extends StatelessWidget {
  const AppearanceSettingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<GlobalSettingCubit>();
    final state = cubit.state;

    return SettingPageShell(
      title: t.settings.appearance,
      child: ListView(
        padding: kSettingPagePadding,
        children: [
          settingSectionTitle(
            context,
            t.settings.appearance,
            icon: Icons.palette_outlined,
          ),
          settingCardGroup([
            _languageTile(context, state, cubit),
            _systemTheme(state, cubit),
            if (!isOhos) _dynamicColor(state, cubit),
            if (isOhos || !state.dynamicColor) changeThemeColor(context),
            _fontSettings(context),
          ]),
          settingSectionTitle(
            context,
            t.settings.content,
            icon: Icons.view_list_outlined,
          ),
          settingCardGroup([
            _comicReadTopContainer(state, cubit),
            _isAMOLED(state, cubit),
            _detailLayout(state, cubit),
            _comicDetail(context),
            _showPluginHome(state, cubit),
            _showPluginCloudFavorite(state, cubit),
            _showSearchBookmark(state, cubit),
            // 滚动条两项不再单独分组：分组标题与条目标题同名会让同一屏
            // 连出现两次「显示滚动条」，并入同一张卡片更紧凑也不再重名。
            _showScrollbar(state, cubit),
            if (state.effectiveShowScrollbar)
              _alwaysShowScrollbar(state, cubit),
          ]),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _languageTile(
    BuildContext context,
    GlobalSettingState state,
    GlobalSettingCubit cubit,
  ) {
    final labels = {
      null: t.settings.followSystemLanguage,
      for (final appLocale in AppLocale.values)
        I18nHelper.toFlutterLocale(appLocale): I18nHelper.displayName(
          appLocale,
        ),
    };

    final currentValue = state.localeFollowsSystem ? null : state.locale;
    final currentLabel = labels[currentValue]!;

    return CalmListTile(
      leading: settingTileIcon(Icons.language_outlined),
      title: t.settings.language,
      subtitle: t.settings.languageSubtitle,
      trailing: FluentDropdown<Locale?>(
        value: currentValue,
        displayValue: currentLabel,
        items: labels,
        onChanged: (value) async {
          if (value == currentValue) return;
          if (value == null) {
            final systemInfo = await SystemLocaleService.getInfo();
            await cubit.setSystemLocale(systemInfo.locale);
          } else {
            await cubit.setLocale(value, followsSystem: false);
          }
          if (context.mounted) {
            showInfoToast(t.settings.languageChangedRestartHint);
          }
        },
      ),
    );
  }

  Widget _systemTheme(GlobalSettingState state, GlobalSettingCubit cubit) {
    final themeItems = <ThemeMode, String>{
      ThemeMode.system: t.common.followSystem,
      ThemeMode.light: t.common.lightMode,
      ThemeMode.dark: t.common.darkMode,
    };

    return CalmListTile(
      leading: settingTileIcon(Icons.dark_mode_outlined),
      title: t.settings.theme,
      subtitle: t.settings.themeSubtitle,
      trailing: FluentDropdown<ThemeMode>(
        value: state.themeMode,
        displayValue: themeItems[state.themeMode]!,
        items: themeItems,
        onChanged: (ThemeMode value) {
          cubit.updateState((current) => current.copyWith(themeMode: value));
        },
      ),
    );
  }

  Widget _dynamicColor(GlobalSettingState state, GlobalSettingCubit cubit) {
    return settingSwitchTile(
      icon: Icons.color_lens_outlined,
      title: t.settings.dynamicColor,
      subtitle: t.settings.dynamicColorSubtitle,
      value: state.dynamicColor,
      onChanged: (bool value) {
        cubit.updateState((current) => current.copyWith(dynamicColor: value));
      },
    );
  }

  Widget _fontSettings(BuildContext context) {
    return settingActionTile(
      icon: Icons.font_download_outlined,
      title: t.settings.fontSettings,
      subtitle: t.settings.fontSettingsSubtitle,
      onTap: () {
        Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const FontSettingPage()));
      },
    );
  }

  Widget _isAMOLED(GlobalSettingState state, GlobalSettingCubit cubit) {
    return settingSwitchTile(
      icon: Icons.contrast_outlined,
      title: t.settings.amoled,
      subtitle: t.settings.amoledSubtitle,
      value: state.isAMOLED,
      onChanged: (bool value) {
        cubit.updateState((current) => current.copyWith(isAMOLED: value));
      },
    );
  }

  Widget _comicReadTopContainer(
    GlobalSettingState state,
    GlobalSettingCubit cubit,
  ) {
    return settingSwitchTile(
      icon: Icons.smartphone_outlined,
      title: t.settings.notchAdaptation,
      subtitle: t.settings.notchAdaptationSubtitle,
      value: state.readSetting.comicReadTopContainer,
      onChanged: (bool value) {
        cubit.updateReadSetting(
          (current) => current.copyWith(comicReadTopContainer: value),
        );
      },
    );
  }

  Widget _detailLayout(GlobalSettingState state, GlobalSettingCubit cubit) {
    return settingSwitchTile(
      icon: Icons.view_list_outlined,
      title: t.settings.detailLayout,
      subtitle: t.settings.detailLayoutSubtitle,
      value: state.bookshelfSetting.detailLayout,
      onChanged: (bool value) {
        cubit.updateBookshelfSetting(
          (current) => current.copyWith(detailLayout: value),
        );
        showSuccessToast(t.common.settingSaved);
      },
    );
  }

  Widget _comicDetail(BuildContext context) {
    return settingCategoryTile(
      icon: Icons.article_outlined,
      title: t.settings.comicDetail,
      subtitle: t.settings.comicDetailSubtitle,
      onTap: () => context.pushRoute(const ComicDetailSettingRoute()),
    );
  }

  Widget _showPluginHome(GlobalSettingState state, GlobalSettingCubit cubit) {
    return settingSwitchTile(
      icon: Icons.home_outlined,
      title: t.settings.showPluginHome,
      subtitle: t.settings.showPluginHomeSubtitle,
      value: state.showPluginHome,
      onChanged: (bool value) {
        cubit.updateState((current) => current.copyWith(showPluginHome: value));
      },
    );
  }

  Widget _showPluginCloudFavorite(
    GlobalSettingState state,
    GlobalSettingCubit cubit,
  ) {
    return settingSwitchTile(
      icon: Icons.cloud_outlined,
      title: t.settings.showPluginCloudFavorite,
      subtitle: t.settings.showPluginCloudFavoriteSubtitle,
      value: state.showPluginCloudFavorite,
      onChanged: (bool value) {
        cubit.updateState(
          (current) => current.copyWith(showPluginCloudFavorite: value),
        );
      },
    );
  }

  Widget _showSearchBookmark(
    GlobalSettingState state,
    GlobalSettingCubit cubit,
  ) {
    return settingSwitchTile(
      icon: Icons.bookmark_outline,
      title: t.settings.showSearchBookmark,
      subtitle: t.settings.showSearchBookmarkSubtitle,
      value: state.showSearchBookmark,
      onChanged: (bool value) {
        cubit.updateState(
          (current) => current.copyWith(showSearchBookmark: value),
        );
      },
    );
  }

  Widget _showScrollbar(GlobalSettingState state, GlobalSettingCubit cubit) {
    return settingSwitchTile(
      icon: Icons.swap_vert,
      title: t.settings.showScrollbar,
      subtitle: t.settings.showScrollbarSubtitle,
      value: state.effectiveShowScrollbar,
      onChanged: (bool value) {
        cubit.updateState((current) => current.copyWith(showScrollbar: value));
      },
    );
  }

  Widget _alwaysShowScrollbar(
    GlobalSettingState state,
    GlobalSettingCubit cubit,
  ) {
    return settingSwitchTile(
      icon: Icons.push_pin_outlined,
      title: t.settings.alwaysShowScrollbar,
      subtitle: t.settings.alwaysShowScrollbarSubtitle,
      value: state.alwaysShowScrollbar,
      onChanged: (bool value) {
        cubit.updateState(
          (current) => current.copyWith(alwaysShowScrollbar: value),
        );
      },
    );
  }
}
