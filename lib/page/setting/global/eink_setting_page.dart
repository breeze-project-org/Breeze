import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/setting/common/setting_ui.dart';
import 'package:zephyr/platform/eink/eink_device.dart';
import 'package:zephyr/platform/eink/eink_refresh.dart';
import 'package:zephyr/widgets/fluent_dropdown.dart';
import 'package:zephyr/widgets/toast.dart';

@RoutePage()
class EInkSettingPage extends StatefulWidget {
  const EInkSettingPage({super.key});

  @override
  State<EInkSettingPage> createState() => _EInkSettingPageState();
}

class _EInkSettingPageState extends State<EInkSettingPage> {
  late final Future<bool> _detected;

  @override
  void initState() {
    super.initState();
    _detected = EinkDevice.detect();
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<GlobalSettingCubit>();
    final eink = cubit.state.eInkSetting;
    final readSetting = cubit.state.readSetting;

    return SettingPageShell(
      title: t.settings.einkPageTitle,
      child: ListView(
        padding: kSettingPagePadding,
        children: [
          settingSectionTitle(
            context,
            t.settings.eink,
            icon: Icons.tablet_mac_outlined,
          ),
          settingCardGroup([
            FutureBuilder<bool>(
              future: _detected,
              builder: (context, snapshot) {
                final detected = snapshot.data ?? false;
                return CalmListTile(
                  leading: settingTileIcon(
                    detected
                        ? Icons.check_circle_outline_rounded
                        : Icons.help_outline_rounded,
                  ),
                  title: detected
                      ? t.settings.einkDetected
                      : t.settings.einkNotDetected,
                );
              },
            ),
            settingSwitchTile(
              icon: Icons.power_settings_new_outlined,
              title: t.settings.einkEnabled,
              subtitle: t.settings.einkEnabledSubtitle,
              value: eink.enabled,
              onChanged: (value) => cubit.updateState(
                (current) => current.copyWith(
                  eInkSetting: current.eInkSetting.copyWith(
                    enabled: value,
                    detectionHandled: true,
                  ),
                  // 开启时把阅读侧已有的「无动画」「墨水屏优化」一并打开；
                  // 这两项只在阅读设置里单独调整，本页不重复列出。
                  readSetting: value
                      ? current.readSetting.copyWith(
                          noAnimation: true,
                          einkOptimization: true,
                        )
                      : current.readSetting,
                ),
              ),
            ),
          ]),
          if (eink.enabled) ...[
            settingSectionTitle(
              context,
              t.settings.einkSectionAnimation,
              icon: Icons.animation_outlined,
            ),
            settingCardGroup([
              settingSwitchTile(
                icon: Icons.arrow_back_outlined,
                title: t.settings.einkNoRouteTransition,
                subtitle: t.settings.einkNoRouteTransitionSubtitle,
                value: eink.noRouteTransition,
                onChanged: (value) => cubit.updateEInkSetting(
                  (current) => current.copyWith(noRouteTransition: value),
                ),
              ),
              settingSwitchTile(
                icon: Icons.vertical_align_bottom_outlined,
                title: t.settings.einkNoScrollBounce,
                subtitle: t.settings.einkNoScrollBounceSubtitle,
                value: eink.noScrollBounce,
                onChanged: (value) => cubit.updateEInkSetting(
                  (current) => current.copyWith(noScrollBounce: value),
                ),
              ),
            ]),
            settingSectionTitle(
              context,
              t.settings.einkSectionLoading,
              icon: Icons.download_outlined,
            ),
            settingCardGroup([
              settingSwitchTile(
                icon: Icons.hourglass_empty_outlined,
                title: t.settings.einkNoSpinner,
                subtitle: t.settings.einkNoSpinnerSubtitle,
                value: eink.noLoadingSpinner,
                onChanged: (value) => cubit.updateEInkSetting(
                  (current) => current.copyWith(noLoadingSpinner: value),
                ),
              ),
            ]),
            settingSectionTitle(
              context,
              t.settings.einkSectionRefresh,
              icon: Icons.autorenew_outlined,
            ),
            settingCardGroup([
              _dropdownTile<EinkRefreshMode>(
                icon: Icons.refresh_outlined,
                title: t.settings.einkRefreshMode,
                subtitle: t.settings.einkRefreshHint,
                value: eink.refreshMode,
                values: EinkRefreshMode.values,
                label: (value) => value.label,
                onChanged: (value) => cubit.updateEInkSetting(
                  (current) => current.copyWith(refreshMode: value),
                ),
              ),
              _dropdownTile(
                icon: Icons.repeat_outlined,
                title: t.settings.einkAutoRefreshTurns,
                value: eink.autoRefreshEveryNTurns,
                values: _autoRefreshOptions,
                label: (value) =>
                    value == 0 ? t.settings.einkAutoRefreshOff : '$value',
                onChanged: (value) => cubit.updateEInkSetting(
                  (current) => current.copyWith(autoRefreshEveryNTurns: value),
                ),
              ),
              settingSwitchTile(
                icon: Icons.control_camera_outlined,
                title: t.settings.einkShowRefreshButton,
                subtitle: t.settings.einkShowRefreshButtonSubtitle,
                value: eink.showRefreshButton,
                onChanged: (value) => cubit.updateEInkSetting(
                  (current) => current.copyWith(showRefreshButton: value),
                ),
              ),
              if (eink.canFullRefresh)
                settingActionTile(
                  icon: Icons.flash_on_outlined,
                  title: t.settings.einkRefreshNow,
                  onTap: () async {
                    await EinkRefresh.run(
                      eink.refreshMode,
                      holdMs: readSetting.einkDelayMs.clamp(50, 500),
                    );
                    showSuccessToast(t.settings.einkRefreshDone);
                  },
                ),
            ]),
          ],
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  static const List<int> _autoRefreshOptions = <int>[0, 2, 3, 5, 8, 10, 15, 20];

  Widget _dropdownTile<T>({
    required IconData icon,
    required String title,
    String? subtitle,
    required T value,
    required List<T> values,
    required String Function(T value) label,
    required ValueChanged<T> onChanged,
  }) {
    final safeValue = values.contains(value) ? value : values.first;
    return CalmListTile(
      leading: settingTileIcon(icon),
      title: title,
      subtitle: subtitle,
      trailing: FluentDropdown<T>(
        value: safeValue,
        displayValue: label(safeValue),
        items: {for (final item in values) item: label(item)},
        onChanged: onChanged,
      ),
    );
  }
}
