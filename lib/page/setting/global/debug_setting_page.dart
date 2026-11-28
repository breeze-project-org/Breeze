import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/config/router/router.gr.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/setting/common/setting_ui.dart';
import 'package:zephyr/src/rust/api/qjs.dart';
import 'package:zephyr/util/system/impeller_config.dart';
import 'package:zephyr/widgets/toast.dart';

@RoutePage()
class DebugSettingPage extends StatefulWidget {
  const DebugSettingPage({super.key});

  @override
  State<DebugSettingPage> createState() => _DebugSettingPageState();
}

class _DebugSettingPageState extends State<DebugSettingPage> {
  @override
  void initState() {
    super.initState();
    _loadImpellerConfig();
  }

  Future<void> _loadImpellerConfig() async {
    final supported = await ImpellerConfig.isForceEnableSupported();
    final forceEnableImpeller = supported
        ? await ImpellerConfig.getForceEnableImpeller()
        : false;

    if (!mounted) return;

    final cubit = context.read<GlobalSettingCubit>();
    if (cubit.state.forceEnableImpeller != forceEnableImpeller) {
      cubit.updateState(
        (current) => current.copyWith(forceEnableImpeller: forceEnableImpeller),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<GlobalSettingCubit>();
    final state = cubit.state;

    return SettingPageShell(
      title: t.settings.debug,
      child: ListView(
        padding: kSettingPagePadding,
        children: [
          settingSectionTitle(
            context,
            t.settings.debug,
            icon: Icons.bug_report_outlined,
          ),
          settingCardGroup([
            _logAddress(state, cubit),
            _enableMemoryDebug(state, cubit),
            _blockRustHttpRequests(state, cubit),
            if (defaultTargetPlatform == TargetPlatform.android)
              _forceEnableImpeller(state, cubit),
          ]),
          if (kDebugMode) ...[
            settingSectionTitle(
              context,
              t.settings.colorPreview,
              icon: Icons.colorize_outlined,
            ),
            settingCardGroup([
              settingCategoryTile(
                icon: Icons.colorize_outlined,
                title: t.settings.colorPreview,
                subtitle: t.settings.colorPreviewSubtitle,
                onTap: () => context.pushRoute(const ShowColorRoute()),
              ),
              settingCategoryTile(
                icon: Icons.developer_mode_outlined,
                title: t.settings.qjsRuntimeDebug,
                subtitle: t.settings.qjsRuntimeDebugSubtitle,
                onTap: () => context.pushRoute(const QjsRuntimeDebugRoute()),
              ),
              settingCategoryTile(
                icon: Icons.memory_outlined,
                title: t.settings.coremlDebug,
                subtitle: t.settings.coremlDebugSubtitle,
                onTap: () => context.pushRoute(const CoreMLUpscaleDebugRoute()),
              ),
            ]),
          ],
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _enableMemoryDebug(
    GlobalSettingState state,
    GlobalSettingCubit cubit,
  ) {
    return settingSwitchTile(
      icon: Icons.memory_outlined,
      title: t.settings.memoryDebug,
      subtitle: t.settings.memoryDebugSubtitle,
      value: state.enableMemoryDebug,
      onChanged: (bool value) {
        cubit.updateState(
          (current) => current.copyWith(enableMemoryDebug: value),
        );
      },
    );
  }

  Widget _logAddress(GlobalSettingState state, GlobalSettingCubit cubit) {
    final logAddress = state.logAddress.trim();
    return settingActionTile(
      icon: Icons.link_outlined,
      title: t.settings.logAddress,
      subtitle: logAddress.isEmpty ? t.settings.logAddressSubtitle : logAddress,
      onTap: () async {
        final controller = TextEditingController(text: logAddress);
        final result = await showCalmDialog<String>(
          context,
          title: t.settings.logAddress,
          subtitle: t.settings.logAddressSubtitle,
          icon: Icons.link_outlined,
          bodyBuilder: (dialogContext) => CalmTextField(
            controller: controller,
            hintText: 'https://example.com/log',
            prefixIcon: Icons.link_rounded,
            keyboardType: TextInputType.url,
            onSubmitted: (value) =>
                Navigator.of(dialogContext).pop(value.trim()),
          ),
          actionsBuilder: (dialogContext) => [
            CalmButton(
              label: t.common.cancel,
              variant: CalmButtonVariant.ghost,
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
            CalmButton(
              label: t.common.ok,
              variant: CalmButtonVariant.primary,
              onPressed: () =>
                  Navigator.of(dialogContext).pop(controller.text.trim()),
            ),
          ],
        );
        controller.dispose();

        if (result != null && result != logAddress) {
          cubit.updateState((current) => current.copyWith(logAddress: result));
          showSuccessToast(t.common.settingSaved);
        }
      },
    );
  }

  Widget _blockRustHttpRequests(
    GlobalSettingState state,
    GlobalSettingCubit cubit,
  ) {
    return settingSwitchTile(
      icon: Icons.cloud_off_outlined,
      title: t.settings.blockRustHttpRequests,
      subtitle: t.settings.blockRustHttpRequestsSubtitle,
      value: state.blockRustHttpRequests,
      onChanged: (bool value) {
        setHttpRequestsBlocked(blocked: value);
        cubit.updateState(
          (current) => current.copyWith(blockRustHttpRequests: value),
        );
      },
    );
  }

  Widget _forceEnableImpeller(
    GlobalSettingState state,
    GlobalSettingCubit cubit,
  ) {
    return settingSwitchTile(
      icon: Icons.auto_awesome_outlined,
      title: t.settings.forceEnableImpeller,
      subtitle: t.settings.forceEnableImpellerSubtitle,
      value: state.forceEnableImpeller,
      onChanged: (bool value) async {
        cubit.updateState(
          (current) => current.copyWith(forceEnableImpeller: value),
        );
        await ImpellerConfig.setForceEnableImpeller(value);
        showSuccessToast(t.common.restartToTakeEffect);
      },
    );
  }
}
