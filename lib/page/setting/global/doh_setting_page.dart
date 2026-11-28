import 'package:auto_route/auto_route.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/setting/common/setting_ui.dart';
import 'package:zephyr/util/network/doh_setting.dart';
import 'package:zephyr/widgets/toast.dart';

/// DoH（DNS over HTTPS）开关与端点管理。
///
/// 开启且有端点时，Rust 侧所有 HTTP 请求（含 ECH 引导）都会优先走 DoH，
/// 与是否开启代理无关。每个端点优先用 JSON API，失败时回退 RFC 8484。
@RoutePage()
class DohSettingPage extends StatelessWidget {
  const DohSettingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<GlobalSettingCubit>();
    final setting = cubit.state.dohSetting;

    return SettingPageShell(
      title: t.settings.doh,
      child: ListView(
        padding: kSettingPagePadding,
        children: [
          settingCardGroup([
            settingSwitchTile(
              icon: Icons.shield_outlined,
              title: t.settings.doh,
              subtitle: t.settings.dohEnabledSubtitle,
              value: setting.enabled,
              onChanged: (value) =>
                  _update(cubit, setting.copyWith(enabled: value)),
            ),
          ]),
          settingSectionTitle(
            context,
            t.settings.dohProviders,
            icon: Icons.dns_outlined,
          ),
          settingCardGroup([
            if (setting.providers.isEmpty)
              CalmListTile(
                leading: settingTileIcon(Icons.info_outline_rounded),
                title: t.settings.dohEmpty,
              ),
            for (final provider in setting.providers)
              CalmListTile(
                leading: settingTileIcon(Icons.language_outlined),
                title: _hostOf(provider),
                subtitle: provider,
                trailing: CalmIconButton(
                  icon: Icons.delete_outline_rounded,
                  tooltip: t.common.delete,
                  onPressed: () => _remove(cubit, setting, provider),
                ),
              ),
            settingActionTile(
              icon: Icons.add_rounded,
              title: t.settings.dohAdd,
              subtitle: t.settings.dohAddHint,
              onTap: () => _add(context, cubit, setting),
            ),
            settingActionTile(
              icon: Icons.restart_alt_rounded,
              title: t.settings.dohReset,
              onTap: () => _update(
                cubit,
                setting.copyWith(providers: defaultDohProviders),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          CalmStatusBanner(title: t.settings.dohIpHint),
          const SizedBox(height: 8),
          CalmStatusBanner(title: t.settings.dohNote, tone: CalmTone.info),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  static void _update(GlobalSettingCubit cubit, DohSettingState next) {
    cubit.updateState((current) => current.copyWith(dohSetting: next));
    // 立刻应用到 Rust HTTP 客户端，不需要重启。
    applyDohSetting(next);
    showSuccessToast(t.common.settingSaved);
  }

  static void _remove(
    GlobalSettingCubit cubit,
    DohSettingState setting,
    String provider,
  ) {
    final providers = setting.providers
        .where((item) => item != provider)
        .toList(growable: false);
    _update(cubit, setting.copyWith(providers: providers));
  }

  static Future<void> _add(
    BuildContext context,
    GlobalSettingCubit cubit,
    DohSettingState setting,
  ) async {
    final controller = TextEditingController();
    // 用 ValueNotifier 承载校验错误：底部按钮无法直接重建 body，
    // 由 ValueListenableBuilder 在弹窗内部自动刷新错误提示。
    final error = ValueNotifier<String?>(null);

    final result = await showCalmDialog<String>(
      context,
      title: t.settings.dohAdd,
      subtitle: t.settings.dohAddHint,
      icon: Icons.dns_outlined,
      bodyBuilder: (dialogContext) => ValueListenableBuilder<String?>(
        valueListenable: error,
        builder: (context, errorText, _) => CalmTextField(
          controller: controller,
          hintText: t.settings.dohAddHint,
          prefixIcon: Icons.link_rounded,
          errorText: errorText,
          keyboardType: TextInputType.url,
          onChanged: (_) {
            if (error.value != null) error.value = null;
          },
        ),
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
          onPressed: () {
            final value = controller.text.trim();
            final uri = Uri.tryParse(value);
            if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
              // 校验失败时留在弹窗内，靠 errorText 提示，不关闭路由。
              error.value = t.settings.dohInvalidUrl;
              return;
            }
            Navigator.of(dialogContext).pop(value);
          },
        ),
      ],
    );
    controller.dispose();
    error.dispose();

    if (result == null) return;
    final providers = [...setting.providers];
    if (!providers.contains(result)) {
      providers.add(result);
    }
    _update(cubit, setting.copyWith(providers: providers));
  }

  static String _hostOf(String url) {
    final uri = Uri.tryParse(url);
    return uri != null && uri.host.isNotEmpty ? uri.host : url;
  }
}
