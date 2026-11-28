import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/setting/common/setting_ui.dart';
import 'package:zephyr/platform/desktop/window_logic.dart';
import 'package:zephyr/service/lifecycle/foreground_task/foreground_task_service.dart';
import 'package:zephyr/widgets/fluent_dropdown.dart';
import 'package:zephyr/widgets/gesture_lock.dart';
import 'package:zephyr/widgets/toast.dart';
import 'package:zephyr/main.dart';

@RoutePage()
class AppBehaviorSettingPage extends StatefulWidget {
  const AppBehaviorSettingPage({super.key});

  @override
  State<AppBehaviorSettingPage> createState() => _AppBehaviorSettingPageState();
}

class _AppBehaviorSettingPageState extends State<AppBehaviorSettingPage> {
  DesktopCloseBehavior _desktopCloseBehavior = DesktopCloseBehavior.ask;

  List<String> _splashPageList(GlobalSettingState state) {
    return [
      if (state.showPluginHome) t.navigation.home,
      if (state.showPluginCloudFavorite) t.oldHome.cloudFavorite,
      t.navigation.bookshelf,
      t.navigation.discover,
      t.navigation.more,
    ];
  }

  Map<String, int> _splashPageMap(GlobalSettingState state) {
    final labels = _splashPageList(state);
    final visibleBaseIndexes = [
      if (state.showPluginHome) 0,
      if (state.showPluginCloudFavorite) 1,
      2,
      3,
      4,
    ];
    assert(labels.length == visibleBaseIndexes.length);
    return {
      for (var i = 0; i < labels.length; i++) labels[i]: visibleBaseIndexes[i],
    };
  }

  @override
  void initState() {
    super.initState();
    _loadDesktopCloseBehavior();
  }

  Future<void> _loadDesktopCloseBehavior() async {
    if (!isDesktop) return;
    final value = await WindowLogic.loadCloseBehavior();
    if (!mounted) return;
    setState(() => _desktopCloseBehavior = value);
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<GlobalSettingCubit>();
    final state = cubit.state;

    return SettingPageShell(
      title: t.settings.appBehavior,
      child: ListView(
        padding: kSettingPagePadding,
        children: [
          settingSectionTitle(
            context,
            t.settings.appBehavior,
            icon: Icons.settings_outlined,
          ),
          settingCardGroup([
            _splashPage(state, cubit),
            if (isDesktop) _desktopCloseBehaviorTile(),
            if (Platform.isAndroid) _androidKeepAlive(state, cubit),
            if (Platform.isAndroid) _backPressExit(state, cubit),
            _autoFollowOnCollect(state, cubit),
            _autoCloudCollectOnLocalFavorite(state, cubit),
            _leftHandMode(state, cubit),
            _clickCoverToStartReading(state, cubit),
          ]),
          settingSectionTitle(
            context,
            t.settings.appLock,
            icon: Icons.lock_outline,
          ),
          settingCardGroup(_appLockTiles(state, cubit)),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _splashPage(GlobalSettingState state, GlobalSettingCubit cubit) {
    final splashPageList = _splashPageList(state);
    final splashPage = _splashPageMap(state);
    // welcomePageNum 存的是规范序号；隐藏中的序号回退到第一个可见页。
    final selectedBaseIndex = splashPage.containsValue(state.welcomePageNum)
        ? state.welcomePageNum
        : splashPage.values.first;
    final selectedLabel =
        splashPageList[splashPage.values.toList().indexOf(selectedBaseIndex)];

    final splashPageItems = {for (final page in splashPageList) page: page};

    return CalmListTile(
      leading: settingTileIcon(Icons.rocket_launch_outlined),
      title: t.settings.splashPage,
      subtitle: t.settings.splashPageSubtitle,
      trailing: FluentDropdown<String>(
        value: selectedLabel,
        displayValue: selectedLabel,
        items: splashPageItems,
        onChanged: (String value) {
          if (value == selectedLabel) return;
          showSuccessToast(t.common.restartToTakeEffect);
          cubit.updateState(
            (current) => current.copyWith(welcomePageNum: splashPage[value]!),
          );
        },
      ),
    );
  }

  Widget _autoFollowOnCollect(
    GlobalSettingState state,
    GlobalSettingCubit cubit,
  ) {
    return settingSwitchTile(
      icon: Icons.notifications_active_outlined,
      title: t.settings.autoFollowOnCollect,
      subtitle: t.settings.autoFollowOnCollectSubtitle,
      value: state.autoFollowOnCollect,
      onChanged: (bool value) {
        cubit.updateState(
          (current) => current.copyWith(autoFollowOnCollect: value),
        );
        showSuccessToast(t.common.settingSaved);
      },
    );
  }

  Widget _autoCloudCollectOnLocalFavorite(
    GlobalSettingState state,
    GlobalSettingCubit cubit,
  ) {
    return settingSwitchTile(
      icon: Icons.cloud_sync_outlined,
      title: t.settings.autoCloudCollectOnLocalFavorite,
      subtitle: t.settings.autoCloudCollectOnLocalFavoriteSubtitle,
      value: state.autoCloudCollectOnLocalFavorite,
      onChanged: (bool value) {
        cubit.updateState(
          (current) => current.copyWith(autoCloudCollectOnLocalFavorite: value),
        );
        showSuccessToast(t.common.settingSaved);
      },
    );
  }

  Widget _leftHandMode(GlobalSettingState state, GlobalSettingCubit cubit) {
    return settingSwitchTile(
      icon: Icons.back_hand_outlined,
      title: t.settings.leftHandMode,
      subtitle: t.settings.leftHandModeSubtitle,
      value: state.leftHandModeEnabled,
      onChanged: (bool value) {
        cubit.updateState(
          (current) => current.copyWith(leftHandModeEnabled: value),
        );
        showSuccessToast(t.common.settingSaved);
      },
    );
  }

  Widget _clickCoverToStartReading(
    GlobalSettingState state,
    GlobalSettingCubit cubit,
  ) {
    return settingSwitchTile(
      icon: Icons.touch_app_outlined,
      title: t.settings.clickCoverToStartReading,
      subtitle: t.settings.clickCoverToStartReadingSubtitle,
      value: state.clickCoverToStartReading,
      onChanged: (bool value) {
        cubit.updateState(
          (current) => current.copyWith(clickCoverToStartReading: value),
        );
        showSuccessToast(t.common.settingSaved);
      },
    );
  }

  Widget _androidKeepAlive(GlobalSettingState state, GlobalSettingCubit cubit) {
    return settingSwitchTile(
      icon: Icons.battery_charging_full_outlined,
      title: t.settings.androidKeepAlive,
      subtitle: t.settings.androidKeepAliveSubtitle,
      value: state.androidKeepAliveEnabled,
      onChanged: (bool value) async {
        cubit.updateState(
          (current) => current.copyWith(androidKeepAliveEnabled: value),
        );
        try {
          if (value) {
            await ForegroundTaskService.instance.enableKeepAlive();
          } else {
            await ForegroundTaskService.instance.disableKeepAlive();
          }
          showSuccessToast(t.common.settingSaved);
        } catch (e) {
          logger.e(e);
          cubit.updateState(
            (current) => current.copyWith(androidKeepAliveEnabled: !value),
          );
          showErrorToast(e.toString());
        }
      },
    );
  }

  Widget _backPressExit(GlobalSettingState state, GlobalSettingCubit cubit) {
    return settingSwitchTile(
      icon: Icons.exit_to_app_outlined,
      title: t.settings.backPressExit,
      subtitle: t.settings.backPressExitSubtitle,
      value: state.backPressExitEnabled,
      onChanged: (bool value) {
        cubit.updateState(
          (current) => current.copyWith(backPressExitEnabled: value),
        );
        showSuccessToast(t.common.settingSaved);
      },
    );
  }

  Widget _desktopCloseBehaviorTile() {
    final closeBehaviorItems = <DesktopCloseBehavior, String>{
      DesktopCloseBehavior.ask: t.settings.desktopCloseAsk,
      DesktopCloseBehavior.hide: t.settings.desktopCloseHide,
      DesktopCloseBehavior.close: t.settings.desktopCloseClose,
    };

    return CalmListTile(
      leading: settingTileIcon(Icons.close_fullscreen_outlined),
      title: t.settings.desktopCloseBehavior,
      subtitle: t.settings.desktopCloseBehaviorSubtitle,
      trailing: FluentDropdown<DesktopCloseBehavior>(
        value: _desktopCloseBehavior,
        displayValue: closeBehaviorItems[_desktopCloseBehavior]!,
        items: closeBehaviorItems,
        onChanged: (DesktopCloseBehavior value) async {
          if (value == _desktopCloseBehavior) return;
          await WindowLogic.saveCloseBehavior(value);
          if (!mounted) return;
          setState(() => _desktopCloseBehavior = value);
          showSuccessToast(t.common.settingSaved);
        },
      ),
    );
  }

  /// 应用锁分组：启用开关 + 手势重设 + 重置 PIN + 删除锁定。
  List<Widget> _appLockTiles(
    GlobalSettingState state,
    GlobalSettingCubit cubit,
  ) {
    final lockSetting = state.appLockSetting;
    final isReady = lockSetting.isReady;

    return [
      settingSwitchTile(
        icon: Icons.lock_outline,
        title: t.settings.appLock,
        subtitle: t.settings.appLockSubtitle,
        value: lockSetting.enabled,
        onChanged: (bool value) async {
          if (value && !isReady) {
            final nextSetting = await _configureAppLock();
            if (nextSetting == null) {
              return;
            }
            cubit.updateState(
              (current) => current.copyWith(appLockSetting: nextSetting),
            );
            showSuccessToast(t.common.settingSaved);
            return;
          }

          cubit.updateState(
            (current) => current.copyWith(
              appLockSetting: current.appLockSetting.copyWith(enabled: value),
            ),
          );
          showSuccessToast(t.common.settingSaved);
        },
      ),
      settingActionTile(
        icon: Icons.gesture_outlined,
        title: t.settings.appLock,
        subtitle: t.settings.appLockSubtitle,
        onTap: () async {
          final nextSetting = await _configureAppLock();
          if (nextSetting == null) {
            return;
          }
          cubit.updateState(
            (current) => current.copyWith(appLockSetting: nextSetting),
          );
          showSuccessToast(t.common.settingSaved);
        },
      ),
      if (isReady)
        settingActionTile(
          icon: Icons.pin_outlined,
          title: t.gestureLock.pinTitle,
          subtitle: t.gestureLock.pinHint,
          onTap: () async {
            final pin = await showPinCodeSetupDialog(
              context,
              title: t.gestureLock.pinTitle,
              confirmTitle: t.gestureLock.pinHint,
            );
            if (pin == null) {
              return;
            }
            cubit.updateState(
              (current) => current.copyWith(
                appLockSetting: current.appLockSetting.copyWith(
                  resetPinHash: hashPinCode(pin),
                ),
              ),
            );
            showSuccessToast(t.common.settingSaved);
          },
        ),
      if (isReady)
        settingActionTile(
          icon: Icons.delete_outline,
          title: t.common.delete,
          subtitle: t.settings.appLock,
          onTap: () async {
            final shouldDelete = await showCalmDialog<bool>(
              context,
              title: t.common.delete,
              icon: Icons.lock_open_rounded,
              tone: CalmTone.danger,
              bodyBuilder: (dialogContext) => Text(
                t.settings.appLockSubtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: dialogContext.calm.text2,
                ),
              ),
              actionsBuilder: (dialogContext) => [
                CalmButton(
                  label: t.common.cancel,
                  variant: CalmButtonVariant.ghost,
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                ),
                CalmButton(
                  label: t.common.delete,
                  variant: CalmButtonVariant.danger,
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                ),
              ],
            );
            if (shouldDelete != true) {
              return;
            }
            cubit.updateState(
              (current) => current.copyWith(
                appLockSetting: const AppLockSettingState(),
              ),
            );
            showSuccessToast(t.common.settingSaved);
          },
        ),
    ];
  }

  Future<AppLockSettingState?> _configureAppLock() async {
    final pattern = await showGesturePasswordSetupDialog(
      context,
      title: t.gestureLock.gestureTitle,
      confirmTitle: t.gestureLock.confirmGesture,
    );
    if (pattern == null) {
      return null;
    }

    if (!mounted) {
      return null;
    }

    final pin = await showPinCodeSetupDialog(
      context,
      title: '设置重置 PIN',
      confirmTitle: '确认重置 PIN',
    );
    if (pin == null) {
      return null;
    }

    return AppLockSettingState(
      enabled: true,
      gesturePasswordHash: hashGesturePattern(pattern),
      resetPinHash: hashPinCode(pin),
    );
  }
}
