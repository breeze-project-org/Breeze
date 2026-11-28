import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/config/router/router.gr.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/setting/common/setting_ui.dart';
import 'package:zephyr/util/network/proxy_setting.dart';
import 'package:zephyr/widgets/fluent_dropdown.dart';
import 'package:zephyr/widgets/toast.dart';

Widget changeThemeColor(BuildContext context) {
  return settingActionTile(
    icon: Icons.palette_outlined,
    title: t.settings.themeColor,
    subtitle: t.settings.themeColorSubtitle,
    onTap: () {
      AutoRouter.of(context).push(const ThemeColorRoute());
    },
  );
}

Widget proxyToggle(
  BuildContext context, {
  required bool enabled,
  required ProxyType type,
  required String currentProxy,
}) {
  return Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      settingSwitchTile(
        icon: Icons.router_outlined,
        title: t.settings.proxy,
        subtitle: t.settings.proxyEnabledSubtitle,
        value: enabled,
        onChanged: (value) async {
          final globalSettingCubit = context.read<GlobalSettingCubit>();
          final next = globalSettingCubit.state.proxySetting.copyWith(
            enabled: value,
          );
          globalSettingCubit.updateState(
            (current) => current.copyWith(proxySetting: next),
          );
          // 立刻应用到 Rust HTTP 客户端和 Dart 侧 HttpClient，不需要重启。
          applyProxySetting(next);
          showSuccessToast(t.common.settingSaved);
        },
      ),
      if (enabled) proxyTypeEdit(context, type),
      if (enabled) proxyAddressEdit(context, currentProxy),
    ],
  );
}

Widget proxyTypeEdit(BuildContext context, ProxyType type) {
  final items = <ProxyType, String>{
    ProxyType.http: t.settings.proxyTypeHttp,
    ProxyType.socks5: t.settings.proxyTypeSocks5,
  };
  return CalmListTile(
    leading: settingTileIcon(Icons.lan_outlined),
    title: t.settings.proxyType,
    subtitle: t.settings.proxyTypeSubtitle,
    trailing: FluentDropdown<ProxyType>(
      value: type,
      displayValue: items[type]!,
      items: items,
      onChanged: (ProxyType value) {
        if (value == type) return;
        final globalSettingCubit = context.read<GlobalSettingCubit>();
        final next = globalSettingCubit.state.proxySetting.copyWith(
          type: value,
        );
        globalSettingCubit.updateState(
          (current) => current.copyWith(proxySetting: next),
        );
        applyProxySetting(next);
        showSuccessToast(t.common.settingSaved);
      },
    ),
  );
}

Widget proxyAddressEdit(BuildContext context, String currentProxy) {
  return settingActionTile(
    icon: Icons.link_outlined,
    title: t.settings.proxyAddress,
    subtitle: currentProxy.isEmpty
        ? t.settings.proxySubtitle
        : t.settings.proxyCurrent(currentProxy: currentProxy),
    onTap: () async {
      final globalSettingCubit = context.read<GlobalSettingCubit>();
      final controller = TextEditingController(text: currentProxy);

      final result = await showCalmDialog<String>(
        context,
        title: t.settings.proxyAddress,
        subtitle: t.settings.proxySubtitle,
        icon: Icons.link_outlined,
        bodyBuilder: (dialogContext) => CalmTextField(
          controller: controller,
          hintText: t.settings.proxyHint,
          prefixIcon: Icons.link_rounded,
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value.trim()),
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

      if (!context.mounted) {
        controller.dispose();
        return;
      }

      if (result != null && result != currentProxy) {
        final next = globalSettingCubit.state.proxySetting.copyWith(
          address: result,
        );
        globalSettingCubit.updateState(
          (current) => current.copyWith(proxySetting: next),
        );
        applyProxySetting(next);
        showSuccessToast(t.common.settingSaved);
      }
      controller.dispose();
    },
  );
}

Widget webdavSync(BuildContext context, SyncServiceType syncServiceType) {
  final title = switch (syncServiceType) {
    SyncServiceType.none => t.settings.syncConfig,
    _ => t.webdavSync.serviceTitle(
      service: switch (syncServiceType) {
        SyncServiceType.webdav => t.settings.syncServiceWebdav,
        SyncServiceType.s3 => t.settings.syncServiceS3,
        SyncServiceType.none => '',
      },
    ),
  };

  return settingActionTile(
    icon: Icons.cloud_outlined,
    title: title,
    subtitle: t.settings.syncConfigSubtitle,
    onTap: () {
      AutoRouter.of(context).push(const WebDavSyncRoute());
    },
  );
}

typedef _KeywordListSelector = List<String> Function(GlobalSettingState state);
typedef _KeywordListUpdater = GlobalSettingState Function(
  GlobalSettingState state,
  List<String> keywords,
);

Widget editMaskedKeywords(BuildContext context) {
  return _keywordManagementTile(
    context,
    icon: Icons.shield_outlined,
    title: t.settings.maskedKeywords,
    subtitle: t.settings.maskedKeywordsSubtitle,
    emptyText: t.settings.maskedKeywordsEmpty,
    inputHint: t.settings.maskedKeywordsInputHint,
    readKeywords: (state) => state.maskedKeywords,
    writeKeywords: (state, keywords) =>
        state.copyWith(maskedKeywords: keywords),
  );
}

Widget editMaskedCommentKeywords(BuildContext context) {
  return _keywordManagementTile(
    context,
    icon: Icons.comment_outlined,
    title: t.settings.maskedCommentKeywords,
    subtitle: t.settings.maskedCommentKeywordsSubtitle,
    emptyText: t.settings.maskedCommentKeywordsEmpty,
    inputHint: t.settings.maskedCommentKeywordsInputHint,
    readKeywords: (state) => state.maskedCommentKeywords,
    writeKeywords: (state, keywords) =>
        state.copyWith(maskedCommentKeywords: keywords),
  );
}

Widget _keywordManagementTile(
  BuildContext context, {
  required IconData icon,
  required String title,
  required String subtitle,
  required String emptyText,
  required String inputHint,
  required _KeywordListSelector readKeywords,
  required _KeywordListUpdater writeKeywords,
}) {
  return settingActionTile(
    icon: icon,
    title: title,
    subtitle: subtitle,
    onTap: () {
      showCalmDialog<void>(
        context,
        title: title,
        subtitle: subtitle,
        icon: icon,
        bodyBuilder: (dialogContext) => _KeywordManagementDialog(
          emptyText: emptyText,
          inputHint: inputHint,
          readKeywords: readKeywords,
          writeKeywords: writeKeywords,
        ),
      );
    },
  );
}

/// 关键词管理弹窗主体（CalmUI 胶囊标签 + 输入框 + 圆形加号按钮）。
class _KeywordManagementDialog extends StatefulWidget {
  const _KeywordManagementDialog({
    required this.emptyText,
    required this.inputHint,
    required this.readKeywords,
    required this.writeKeywords,
  });

  final String emptyText;
  final String inputHint;
  final _KeywordListSelector readKeywords;
  final _KeywordListUpdater writeKeywords;

  @override
  State<_KeywordManagementDialog> createState() =>
      _KeywordManagementDialogState();
}

class _KeywordManagementDialogState extends State<_KeywordManagementDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    // 只需要在这里获取 Cubit
    final globalSettingCubit = context.read<GlobalSettingCubit>();

    return BlocBuilder<GlobalSettingCubit, GlobalSettingState>(
      builder: (context, state) {
        final keywords = widget.readKeywords(state);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              constraints: const BoxConstraints(minHeight: 96, maxHeight: 240),
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: c.bg,
                borderRadius: BorderRadius.circular(14),
              ),
              child: SingleChildScrollView(
                child: keywords.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 28),
                          child: Text(
                            widget.emptyText,
                            style: TextStyle(fontSize: 12, color: c.text3),
                          ),
                        ),
                      )
                    : Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: List.generate(keywords.length, (index) {
                          return CalmInputChip(
                            label: keywords[index],
                            onDeleted: () {
                              globalSettingCubit.updateState((current) {
                                final newList = List<String>.from(
                                  widget.readKeywords(current),
                                )..removeAt(index);
                                return widget.writeKeywords(current, newList);
                              });
                            },
                          );
                        }),
                      ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: CalmTextField(
                    controller: _controller,
                    hintText: widget.inputHint,
                    prefixIcon: Icons.tag_rounded,
                    onSubmitted: (_) => _addKeyword(globalSettingCubit, state),
                  ),
                ),
                const SizedBox(width: 8),
                CalmIconButton(
                  icon: Icons.add_rounded,
                  tooltip: t.common.add,
                  selected: true,
                  size: 36,
                  iconSize: 18,
                  onPressed: () => _addKeyword(globalSettingCubit, state),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  void _addKeyword(GlobalSettingCubit cubit, GlobalSettingState state) {
    final text = _controller.text.trim();
    if (text.isEmpty || widget.readKeywords(state).contains(text)) {
      return;
    }
    cubit.updateState(
      (current) => widget.writeKeywords(current, [
        ...widget.readKeywords(current),
        text,
      ]),
    );
    _controller.clear();
  }
}
