import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/plugin_settings/cubit/plugin_settings_cubit.dart';
import 'package:zephyr/page/plugin_settings/widgets/plugin_settings_sections.dart';
import 'package:zephyr/page/setting/common/plugin_user_info_card.dart';
import 'package:zephyr/page/setting/common/setting_ui.dart';
import 'package:zephyr/util/json/json_value.dart';
import 'package:zephyr/widgets/multi_choice_list_dialog.dart';

/// 插件设置内容区（CalmUI 版）。
///
/// 结构：插件自身设置优先（账号 / 配置项 / 操作），宿主管理项沉底；
/// 全部颜色取自 `context.calm`，分组头用 [CalmSectionHeader]，
/// 行统一走 [CalmListTile]，开关走 [CalmSwitch]，登录等主操作走 [CalmButton]。
class PluginSettingsContent extends StatelessWidget {
  const PluginSettingsContent({
    super.key,
    required this.from,
    required this.pluginRuntimeName,
    required this.state,
    required this.debugEnabled,
    required this.debugUrl,
    required this.deleted,
    required this.pluginVersion,
    required this.onUpdateDebugConfig,
    required this.onConfirmDeletePlugin,
    required this.onUpdatePlugin,
    required this.onOpenLoginPage,
    required this.onOpenDetailPage,
    required this.onCommitField,
    required this.onRunAction,
  });

  final String from;
  final String pluginRuntimeName;
  final PluginSettingsState state;
  final bool debugEnabled;
  final String debugUrl;
  final bool deleted;
  final String pluginVersion;
  final Future<void> Function({required bool enabled, required String url})
  onUpdateDebugConfig;
  final Future<void> Function() onConfirmDeletePlugin;
  final Future<void> Function() onUpdatePlugin;
  final Future<void> Function() onOpenLoginPage;
  final Future<void> Function() onOpenDetailPage;
  final Future<void> Function(Map<String, dynamic> field, dynamic value)
  onCommitField;
  final Future<void> Function(Map<String, dynamic> action) onRunAction;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
      children: _stack([
        ..._buildBodySections(context),
        if (state.detailSupported) _buildDetailSection(context),
        _buildManagementSection(context),
        _buildDangerSection(context),
      ]),
    );
  }

  /// 用轻量间距串起各分组（分组头本身已带上下留白）。
  List<Widget> _stack(List<Widget?> sections) {
    final children = <Widget>[];
    for (final section in sections) {
      if (section == null) continue;
      if (children.isNotEmpty) children.add(const SizedBox(height: 2));
      children.add(section);
    }
    return children;
  }

  // ---------------------------------------------------------------- 账号区

  /// 账号 / 用户信息区：用户信息卡 + 登录主按钮。
  ///
  /// 无用户信息时只保留登录入口；两者都不支持时整块不渲染。
  Widget? _buildUserSection(BuildContext context) {
    final c = context.calm;
    final canShowUserInfo = state.canShowUserInfo;
    if (!canShowUserInfo && !state.loginSupported) {
      return null;
    }

    final rows = <Widget>[];
    if (canShowUserInfo) {
      if (state.loadingUserInfo) {
        rows.add(
          CalmCard(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Center(child: CalmLoading(label: t.common.loading)),
          ),
        );
      } else if (state.userInfoError.isNotEmpty) {
        rows.add(
          CalmCard(
            padding: const EdgeInsets.all(10),
            child: CalmErrorState(
              title: t.plugin.userInfoLoadFailed,
              errorDetail: state.userInfoError,
              errorDetailMaxLines: 2,
              retryLabel: t.common.retry,
              onRetry: () =>
                  context.read<PluginSettingsCubit>().loadUserInfo(from),
            ),
          ),
        );
      } else if (state.userInfo.isNotEmpty) {
        rows.add(_buildUserInfoCard());
      } else {
        rows.add(
          Text(
            t.plugin.noUserInfo,
            style: TextStyle(fontSize: 11.5, color: c.text3),
          ),
        );
      }
    }

    if (state.loginSupported) {
      if (rows.isNotEmpty) rows.add(const SizedBox(height: 8));
      rows.add(_buildLoginButton(context));
    }

    final userTitle = canShowUserInfo
        ? state.userInfo['title']?.toString().trim() ?? ''
        : '';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        settingSectionTitle(
          context,
          userTitle.isEmpty ? t.plugin.userInfoTitle : userTitle,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: rows,
          ),
        ),
      ],
    );
  }

  Widget _buildUserInfoCard() {
    return PluginUserInfoCard(
      from: from,
      avatarUrl: asJsonMap(state.userInfo['avatar'])['url']?.toString() ?? '',
      avatarPath: asJsonMap(state.userInfo['avatar'])['path']?.toString() ?? '',
      lines: asJsonList(state.userInfo['lines'])
          .map((item) => item?.toString() ?? '')
          .toList(),
    );
  }

  Widget _buildLoginButton(BuildContext context) {
    final title = state.loginTitle.trim().isEmpty
        ? t.plugin.accountLogin
        : state.loginTitle.trim();
    final subtitle = state.loginSubtitle.trim().isEmpty
        ? null
        : state.loginSubtitle.trim();
    final c = context.calm;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CalmButton(
          label: title,
          icon: Icons.login_rounded,
          variant: CalmButtonVariant.primary,
          size: CalmButtonSize.md,
          expand: true,
          onPressed: deleted ? null : () => onOpenLoginPage(),
        ),
        if (subtitle != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
            child: Text(
              subtitle,
              style: TextStyle(fontSize: 11, color: c.text3),
            ),
          ),
      ],
    );
  }

  // ------------------------------------------------------------ 插件配置项

  Widget _buildLoadingSection() {
    return CalmCard(
      padding: const EdgeInsets.symmetric(vertical: 22),
      child: Center(child: CalmLoading(label: t.plugin.pluginSettingsLoading)),
    );
  }

  Widget _buildErrorSection(BuildContext context) {
    return CalmCard(
      padding: const EdgeInsets.all(10),
      child: CalmErrorState(
        title: t.plugin.pluginSettingsLoadFailed,
        errorDetail: state.error,
        errorDetailMaxLines: 3,
        retryLabel: t.common.retry,
        onRetry: () => context.read<PluginSettingsCubit>().load(from),
      ),
    );
  }

  List<Widget?> _buildBodySections(BuildContext context) {
    if (state.loading) {
      return [_buildLoadingSection()];
    }
    if (state.error.isNotEmpty) {
      return [_buildErrorSection(context)];
    }
    return [
      _buildUserSection(context),
      ..._buildSettingSections(context),
      _buildActionsSection(context),
    ];
  }

  List<Widget> _buildSettingSections(BuildContext context) {
    return state.sections.map((section) {
      return PluginSettingsSectionCard(
        title: section['title']?.toString() ?? '',
        children: asJsonList(section['fields'])
            .map((item) => asJsonMap(item))
            .map((field) => _buildField(context, field))
            .toList(),
      );
    }).toList();
  }

  Widget? _buildActionsSection(BuildContext context) {
    if (state.actions.isEmpty) {
      return null;
    }
    return PluginSettingsSectionCard(
      title: t.plugin.operations,
      children: state.actions
          .map((action) => _buildAction(context, action))
          .toList(),
    );
  }

  Widget _buildField(BuildContext context, Map<String, dynamic> field) {
    final key = field['key']?.toString() ?? '';
    final kind = field['kind']?.toString() ?? 'text';
    final label = field['label']?.toString() ?? key;
    final value = state.values[key];

    if (kind == 'switch') {
      return _buildSwitchField(field, label, value);
    }
    if (kind == 'select' || kind == 'choice') {
      return _buildSelectField(context, field, label, value);
    }
    if (kind == 'multiChoice') {
      return _buildMultiChoiceField(context, field, label, value);
    }
    return _buildTextField(context, field, label, value, kind);
  }

  Widget _buildSwitchField(
    Map<String, dynamic> field,
    String label,
    dynamic value,
  ) {
    final current = value == true;
    return settingSwitchTile(
      title: label,
      subtitle: current ? t.common.enabled : t.common.disabled,
      value: current,
      onChanged: (next) => onCommitField(field, next),
    );
  }

  Widget _buildSelectField(
    BuildContext context,
    Map<String, dynamic> field,
    String label,
    dynamic value,
  ) {
    final options = _normalizeOptions(field['options']);
    final selectedLabel = options
        .firstWhere(
          (item) => item.value.toString() == value?.toString(),
          orElse: () => PluginSettingsOptionPair(
            label: value?.toString() ?? '',
            value: value,
          ),
        )
        .label;

    return PluginSettingsFieldRow(
      title: label,
      subtitle: selectedLabel.trim().isEmpty
          ? t.search.notSelected
          : selectedLabel,
      icon: Icons.tune_rounded,
      onTap: deleted
          ? null
          : () async {
              final picked = await _showSingleChoiceDialog(
                context,
                title: label,
                options: options,
                current: value,
              );
              if (picked == null ||
                  picked.value.toString() == value?.toString()) {
                return;
              }
              await onCommitField(field, picked.value);
            },
    );
  }

  Widget _buildMultiChoiceField(
    BuildContext context,
    Map<String, dynamic> field,
    String label,
    dynamic value,
  ) {
    final options = _normalizeOptions(field['options']);
    final current = _asStringList(value);
    return PluginSettingsFieldRow(
      title: label,
      subtitle: current.isEmpty
          ? t.search.notSelected
          : t.search.selectedCount(count: current.length),
      icon: Icons.checklist_rounded,
      onTap: () async {
        final picked = await showMultiChoiceListDialog(
          context,
          title: label,
          options: options
              .map(
                (item) => MultiChoiceDialogOption(
                  label: item.label,
                  value: item.value.toString(),
                ),
              )
              .toList(),
          initialSelected: current,
          confirmText: t.common.save,
        );
        if (picked == null) return;
        await onCommitField(field, picked.toList());
      },
    );
  }

  Widget _buildTextField(
    BuildContext context,
    Map<String, dynamic> field,
    String label,
    dynamic value,
    String kind,
  ) {
    final text = value?.toString() ?? '';
    final password = kind == 'password';
    return PluginSettingsFieldRow(
      title: label,
      subtitle: _buildTextFieldDisplay(kind, text),
      icon: password ? Icons.lock_outline_rounded : Icons.edit_outlined,
      onTap: () async {
        final next = await _showInputDialog(
          context,
          title: label,
          initialValue: text,
          obscure: password,
        );
        if (next == null) return;
        await onCommitField(field, next);
      },
    );
  }

  String _buildTextFieldDisplay(String kind, String text) {
    if (kind == 'password' && text.isNotEmpty) {
      return '*' * text.length.clamp(6, 24);
    }
    return text;
  }

  Widget _buildAction(BuildContext context, Map<String, dynamic> action) {
    final title = action['title']?.toString() ?? t.plugin.unnamedAction;
    final fnPath = action['fnPath']?.toString() ?? '';
    return PluginSettingsFieldRow(
      title: title,
      subtitle: fnPath,
      icon: Icons.play_arrow_rounded,
      onTap: fnPath.isEmpty ? null : () => onRunAction(action),
    );
  }

  // -------------------------------------------------------------- 详情/管理

  Widget _buildDetailSection(BuildContext context) {
    return PluginSettingsSectionCard(
      title: t.plugin.pluginDetail,
      children: [
        PluginSettingsFieldRow(
          title: t.plugin.pluginDetailSubtitle,
          icon: Icons.info_outline_rounded,
          onTap: deleted ? null : () => onOpenDetailPage(),
        ),
      ],
    );
  }

  Widget _buildManagementSection(BuildContext context) {
    final version = pluginVersion.trim().isEmpty ? '-' : pluginVersion.trim();
    return PluginSettingsSectionCard(
      title: t.plugin.management,
      children: [
        PluginSettingsFieldRow(
          title: t.plugin.version,
          subtitle: t.plugin.currentVersion(version: version),
          icon: Icons.sell_outlined,
        ),
        PluginSettingsFieldRow(
          title: t.plugin.update,
          subtitle: t.plugin.updateSubtitle,
          icon: Icons.system_update_alt_rounded,
          onTap: deleted ? null : () => onUpdatePlugin(),
        ),
        settingSwitchTile(
          icon: Icons.bug_report_outlined,
          title: t.plugin.debugMode,
          subtitle: debugEnabled ? t.common.enabled : t.common.disabled,
          value: debugEnabled,
          onChanged: deleted
              ? null
              : (next) => onUpdateDebugConfig(enabled: next, url: debugUrl),
        ),
        if (debugEnabled) _buildDebugUrlRow(context),
      ],
    );
  }

  /// 危险操作区：不可逆删除单独成卡，用 danger 语义按钮与其它动作清晰分层。
  Widget _buildDangerSection(BuildContext context) {
    final c = context.calm;
    return CalmCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CalmButton(
            label: t.plugin.deletePlugin,
            icon: Icons.delete_outline_rounded,
            variant: CalmButtonVariant.danger,
            size: CalmButtonSize.md,
            expand: true,
            onPressed: deleted ? null : () => onConfirmDeletePlugin(),
          ),
          const SizedBox(height: 7),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              t.plugin.deletePluginSubtitle,
              style: TextStyle(fontSize: 11, color: c.text3, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDebugUrlRow(BuildContext context) {
    return PluginSettingsFieldRow(
      title: t.plugin.debugAddress,
      subtitle: debugUrl.isNotEmpty ? debugUrl : t.settings.notSet,
      icon: Icons.link_rounded,
      onTap: deleted
          ? null
          : () async {
              final next = await _showInputDialog(
                context,
                title: t.plugin.debugAddress,
                initialValue: debugUrl,
                obscure: false,
              );
              if (next == null) return;
              await onUpdateDebugConfig(
                enabled: debugEnabled,
                url: next.trim(),
              );
            },
    );
  }

  // ----------------------------------------------------------------- 工具

  List<PluginSettingsOptionPair> _normalizeOptions(dynamic raw) {
    return asJsonList(raw).map((item) {
      if (item is Map) {
        final map = asJsonMap(item);
        return PluginSettingsOptionPair(
          label: map['label']?.toString() ?? map['value']?.toString() ?? '',
          value: map['value'],
        );
      }
      return PluginSettingsOptionPair(label: item.toString(), value: item);
    }).toList();
  }

  List<String> _asStringList(dynamic value) {
    if (value is List) {
      return value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList();
    }
    if (value is Map) {
      return value.entries
          .where((entry) => entry.value == true)
          .map((entry) => entry.key.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList();
    }
    return const [];
  }

  /// 单选弹窗（CalmUI）：选中项用 accentSoft 底 + 主色对勾，点行即确认。
  Future<PluginSettingsOptionPair?> _showSingleChoiceDialog(
    BuildContext context, {
    required String title,
    required List<PluginSettingsOptionPair> options,
    required dynamic current,
  }) {
    return showCalmDialog<PluginSettingsOptionPair>(
      context,
      title: title,
      icon: Icons.tune_rounded,
      bodyBuilder: (dialogContext) {
        final c = dialogContext.calm;
        return ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 320),
          child: ListView.builder(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            itemCount: options.length,
            itemBuilder: (context, index) {
              final option = options[index];
              final selected = option.value.toString() == current?.toString();
              return Container(
                margin: const EdgeInsets.only(bottom: 2),
                decoration: BoxDecoration(
                  color: selected ? c.accentSoft : null,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: CalmListTile(
                  title: option.label,
                  onTap: () => Navigator.of(dialogContext).pop(option),
                  trailing: selected
                      ? Icon(Icons.check_rounded, size: 16, color: c.accent)
                      : null,
                ),
              );
            },
          ),
        );
      },
    );
  }

  /// 文本输入弹窗（CalmUI）：密码类字段自动隐藏明文。
  Future<String?> _showInputDialog(
    BuildContext context, {
    required String title,
    required String initialValue,
    required bool obscure,
  }) async {
    final controller = TextEditingController(text: initialValue);
    final result = await showCalmDialog<String>(
      context,
      title: title,
      icon: obscure ? Icons.lock_outline_rounded : Icons.edit_outlined,
      bodyBuilder: (dialogContext) => CalmTextField(
        controller: controller,
        hintText: title,
        prefixIcon: obscure ? Icons.lock_outline_rounded : null,
        obscureText: obscure,
        onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
      ),
      actionsBuilder: (dialogContext) => [
        CalmButton(
          label: t.common.cancel,
          variant: CalmButtonVariant.ghost,
          onPressed: () => Navigator.of(dialogContext).pop(),
        ),
        CalmButton(
          label: t.common.save,
          variant: CalmButtonVariant.primary,
          onPressed: () => Navigator.of(dialogContext).pop(controller.text),
        ),
      ],
    );
    controller.dispose();
    return result;
  }
}
