import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/network/http/plugin/unified_plugin_envelope.dart';
import 'package:zephyr/network/http/plugin/unified_comic_plugin.dart';
import 'package:zephyr/database/plugin_config.dart';
import 'package:zephyr/page/setting/common/setting_ui.dart';
import 'package:zephyr/widgets/fluent_dropdown.dart';
import 'package:zephyr/widgets/toast.dart';
import 'package:zephyr/util/json/json_value.dart';
import 'package:zephyr/main.dart';

/// 插件 schema 驱动的设置区（完全保留原有动态字段渲染与保存逻辑，仅替换外观）。
class PluginSettingSchemeSection extends StatefulWidget {
  const PluginSettingSchemeSection({
    super.key,
    required this.from,
    required this.pluginName,
    this.onValueChanged,
  });

  final String from;
  final String pluginName;
  final Future<void> Function(String key, dynamic value)? onValueChanged;

  @override
  State<PluginSettingSchemeSection> createState() =>
      _PluginSettingSchemeSectionState();
}

class _PluginSettingSchemeSectionState
    extends State<PluginSettingSchemeSection> {
  late Future<UnifiedPluginEnvelope> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<UnifiedPluginEnvelope> _load() async {
    final response = await callUnifiedComicPlugin(
      from: widget.from,
      fnPath: 'getSettingsBundle',
      core: const <String, dynamic>{},
      extern: const <String, dynamic>{},
    );
    return UnifiedPluginEnvelope.fromMap(
      response.data,
      source: response.source,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<UnifiedPluginEnvelope>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: CalmLoading(label: t.plugin.pluginSettingsLoading),
          );
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return CalmStatusBanner(
            title: t.plugin.pluginSettingsLoadFailed,
            tone: CalmTone.danger,
            trailing: CalmIconButton(
              icon: Icons.refresh_rounded,
              size: 26,
              iconSize: 14,
              onPressed: () => setState(() => _future = _load()),
            ),
          );
        }

        final envelope = snapshot.data!;
        final sections = asJsonList(envelope.scheme['sections'])
            .map((item) => asJsonMap(item))
            .toList();
        final values = asJsonMap(envelope.data['values']);
        final widgets = <Widget>[];

        for (final section in sections) {
          final title = section['title']?.toString() ?? '';
          if (title.isNotEmpty) {
            widgets.add(settingSectionTitle(context, title));
          }
          final fields = asJsonList(
            section['fields'],
          ).map((item) => asJsonMap(item));
          widgets.add(
            settingCardGroup([
              for (final field in fields) _buildField(field, values),
            ]),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: widgets,
        );
      },
    );
  }

  Widget _buildField(Map<String, dynamic> field, Map<String, dynamic> values) {
    final key = field['key']?.toString() ?? '';
    final label = field['label']?.toString() ?? key;
    final kind = field['kind']?.toString() ?? 'text';
    final value = values[key];

    if (kind == 'select') {
      final options = asJsonList(field['options'])
          .map((e) => e.toString())
          .toList();
      final current =
          value?.toString() ?? (options.isNotEmpty ? options.first : '');
      final effectiveValue = options.contains(current)
          ? current
          : (options.isEmpty ? '' : options.first);
      return CalmListTile(
        leading: settingTileIcon(Icons.tune_rounded),
        title: label,
        trailing: FluentDropdown<String>(
          value: effectiveValue,
          displayValue: effectiveValue,
          items: {for (final option in options) option: option},
          onChanged: options.isEmpty
              ? null
              : (next) async {
                  await _persistField(key, next);
                },
        ),
      );
    }

    if (kind == 'switch') {
      final current = value == true;
      return settingSwitchTile(
        icon: Icons.toggle_on_outlined,
        title: label,
        value: current,
        onChanged: (next) async {
          await _persistField(key, next);
        },
      );
    }

    return settingActionTile(
      icon: Icons.edit_outlined,
      title: label,
      subtitle: value?.toString() ?? '',
      onTap: () async {
        final next = await _showInputDialog(
          context,
          title: label,
          initialValue: value?.toString() ?? '',
          obscure: kind == 'password',
        );
        if (next == null) return;
        await _persistField(key, next);
      },
    );
  }

  Future<void> _persistField(String key, dynamic value) async {
    await savePluginConfigValue(widget.pluginName, key, value);
    if (widget.onValueChanged != null) {
      await widget.onValueChanged!(key, value);
    }
    if (!mounted) return;
    showSuccessToast(t.plugin.saved);
    setState(() => _future = _load());
  }
}

class PluginAdvancedActionSection extends StatefulWidget {
  const PluginAdvancedActionSection({super.key, required this.from});

  final String from;

  @override
  State<PluginAdvancedActionSection> createState() =>
      _PluginAdvancedActionSectionState();
}

class _PluginAdvancedActionSectionState
    extends State<PluginAdvancedActionSection> {
  late Future<UnifiedPluginEnvelope> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<UnifiedPluginEnvelope> _load() async {
    final response = await callUnifiedComicPlugin(
      from: widget.from,
      fnPath: 'getCapabilitiesBundle',
      core: const <String, dynamic>{},
      extern: const <String, dynamic>{},
    );
    return UnifiedPluginEnvelope.fromMap(
      response.data,
      source: response.source,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<UnifiedPluginEnvelope>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: CalmLoading(label: t.plugin.pluginSettingsLoading),
          );
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return const SizedBox.shrink();
        }

        final actions = asJsonList(snapshot.data!.scheme['actions'])
            .map((item) => asJsonMap(item))
            .toList();
        if (actions.isEmpty) {
          return const SizedBox.shrink();
        }

        return settingCardGroup(
          actions.map((action) {
            final title =
                action['title']?.toString() ?? t.plugin.unnamedAction;
            final fnPath = action['fnPath']?.toString() ?? '';
            return CalmListTile(
              leading: settingTileIcon(Icons.extension_outlined),
              title: title,
              subtitle: fnPath,
              trailing: Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: context.calm.text3,
              ),
              onTap: () async {
                if (fnPath.isEmpty) {
                  showInfoToast(t.plugin.actionNotExecutable);
                  return;
                }

                try {
                  final pageContext = context;
                  final result = await callUnifiedComicPlugin(
                    from: widget.from,
                    fnPath: fnPath,
                    core: const <String, dynamic>{},
                    extern: const <String, dynamic>{},
                  );

                  if (!pageContext.mounted) return;
                  final pretty = const JsonEncoder.withIndent(
                    '  ',
                  ).convert(result);
                  await showCalmDialog<void>(
                    pageContext,
                    title: title,
                    subtitle: fnPath,
                    icon: Icons.extension_outlined,
                    maxWidth: 520,
                    bodyBuilder: (dialogContext) => Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: dialogContext.calm.bg,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: SelectableText(
                        pretty,
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.45,
                          color: dialogContext.calm.text2,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                    actionsBuilder: (dialogContext) => [
                      CalmButton(
                        label: t.common.close,
                        variant: CalmButtonVariant.primary,
                        onPressed: () => Navigator.of(dialogContext).pop(),
                      ),
                    ],
                  );
                } catch (e) {
                  logger.e(e);
                  showInfoToast(t.plugin.executeFailed(error: e));
                }
              },
            );
          }).toList(),
        );
      },
    );
  }
}

Future<String?> _showInputDialog(
  BuildContext context, {
  required String title,
  required String initialValue,
  required bool obscure,
}) async {
  final controller = TextEditingController(text: initialValue);
  final value = await showCalmDialog<String>(
    context,
    title: title,
    icon: Icons.edit_outlined,
    bodyBuilder: (dialogContext) => CalmTextField(
      controller: controller,
      hintText: title,
      obscureText: obscure,
      prefixIcon: obscure ? Icons.lock_outline_rounded : Icons.edit_outlined,
      onSubmitted: (text) => Navigator.of(dialogContext).pop(text),
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
  return value;
}
