import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/plugin/plugin_registry_service.dart';
import 'package:zephyr/type/pipe.dart';
import 'package:zephyr/ui/ui.dart';
import 'package:zephyr/util/json/json_value.dart';
import 'package:zephyr/util/text/chinese_convert.dart';
import 'package:zephyr/widgets/plugin_icon.dart';

class PluginCard extends StatelessWidget {
  const PluginCard({
    super.key,
    required this.pluginUuid,
    required this.pluginState,
    required this.info,
    this.error,
    required this.isToggling,
    required this.onSearch,
    required this.onSettings,
    required this.onToggleEnabled,
    required this.onRetry,
    required this.onAction,
  });

  final String pluginUuid;
  final PluginRuntimeState pluginState;

  /// 全局 cubit 的 infos[uuid]：null 表示 DB 也没有缓存，等待补拉或手动重试。
  final Map<String, dynamic>? info;

  /// 全局 cubit 的 infoErrors[uuid]：有值表示最近一次 getInfo 失败。
  final String? error;
  final bool isToggling;
  final VoidCallback onSearch;
  final void Function(String title) onSettings;
  final ValueChanged<bool> onToggleEnabled;
  final VoidCallback onRetry;
  final Future<void> Function(Map<String, dynamic> action) onAction;

  @override
  Widget build(BuildContext context) {
    final data = info;
    if (data == null) {
      if (error != null) {
        return _buildError(context, error);
      }
      return _buildLoading(context);
    }
    return _buildLoaded(context, data);
  }

  /// 加载态：轻盈骨架行，避免整卡片转圈造成的跳动感。
  Widget _buildLoading(BuildContext context) {
    return const CalmCard(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      child: Row(
        children: [
          CalmSkeletonBox(width: 44, height: 44, radius: 12),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CalmSkeletonBox(width: 132, height: 12, radius: 6),
                SizedBox(height: 8),
                CalmSkeletonBox(width: 208, height: 10, radius: 5),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(BuildContext context, String? error) {
    final c = context.calm;
    return CalmCard(
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: c.dangerSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Icon(Icons.error_outline_rounded, size: 19, color: c.danger),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              t.discover.pluginInfoLoadFailed(error: error ?? ''),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, color: c.text2, height: 1.4),
            ),
          ),
          const SizedBox(width: 8),
          CalmButton(
            label: t.common.retry,
            icon: Icons.refresh_rounded,
            variant: CalmButtonVariant.ghost,
            size: CalmButtonSize.xs,
            onPressed: onRetry,
          ),
        ],
      ),
    );
  }

  Widget _buildLoaded(BuildContext context, Map<String, dynamic> info) {
    final c = context.calm;
    final isEnabled = pluginState.isEnabled;

    final rawFunctions = asJsonList(
      info['functions'] ?? info['function'] ?? const <dynamic>[],
    ).map((item) => asJsonMap(item)).toList();
    final pluginName = info['name']?.toString().trim() ?? '';
    final title = pluginName.isNotEmpty
        ? pluginName
        : t.discover.pluginCapability;
    final iconUrl = info['iconUrl']?.toString().trim() ?? '';
    final iconWidget = ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: PluginIcon(
        url: iconUrl,
        placeholder: ColoredBox(
          color: c.surface2,
          child: Center(
            child: Icon(Icons.extension_outlined, size: 20, color: c.text3),
          ),
        ),
      ),
    );

    return CalmCard(
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(width: 44, height: 44, child: iconWidget),
              const SizedBox(width: 11),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textHeightBehavior: kCalmTextHeightBehavior,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isEnabled ? c.text : c.text2,
                          height: 1.25,
                          leadingDistribution: TextLeadingDistribution.even,
                        ),
                      ),
                    ),
                    if (!isEnabled) ...[
                      const SizedBox(width: 7),
                      CalmBadge(
                        label: t.discover.disabled,
                        tone: CalmBadgeTone.neutral,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 6),
              // 插件关闭时搜索入口置灰（CalmIconButton 仅在 onPressed 为空时不响应）。
              AnimatedOpacity(
                duration: const Duration(milliseconds: 140),
                opacity: isEnabled ? 1 : 0.42,
                child: CalmIconButton(
                  icon: Icons.search_rounded,
                  size: 28,
                  iconSize: 15,
                  tooltip: t.common.search,
                  onPressed: isEnabled ? onSearch : null,
                ),
              ),
              const SizedBox(width: 4),
              CalmIconButton(
                icon: Icons.settings_outlined,
                size: 28,
                iconSize: 15,
                tooltip: t.discover.settings,
                onPressed: () => onSettings(title),
              ),
              const SizedBox(width: 8),
              if (isToggling)
                SizedBox(
                  width: 38,
                  height: 22,
                  child: Center(
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.8,
                        strokeCap: StrokeCap.round,
                        color: c.accent,
                        backgroundColor: c.accentSoft,
                      ),
                    ),
                  ),
                )
              else
                CalmSwitch(value: isEnabled, onChanged: onToggleEnabled),
            ],
          ),
          // 插件关闭时完全收起功能胶囊栏，只保留紧凑头部行。
          if (isEnabled && rawFunctions.isNotEmpty) ...[
            const SizedBox(height: 9),
            Padding(
              padding: const EdgeInsets.only(left: 55, right: 4),
              child: _buildFunctionButtons(context, rawFunctions),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFunctionButtons(
    BuildContext context,
    List<Map<String, dynamic>> rawFunctions,
  ) {
    final chips = rawFunctions.map((function) {
      final id = function['id']?.toString().trim() ?? '';
      final text = function['title']?.toString().trim() ?? t.discover.unnamed;
      var action = asJsonMap(function['action']);
      if (action.isEmpty && id.isNotEmpty) {
        action = {
          'type': 'openPluginFunction',
          'payload': {'id': id, 'title': text, 'presentation': 'page'},
        };
      }
      final enabled = action.isNotEmpty;
      return _PluginFunctionPill(
        label: text.let(convertChineseForDisplay),
        onTap: enabled ? () => onAction(action) : null,
      );
    }).toList();
    return Wrap(spacing: 6, runSpacing: 6, children: chips);
  }
}

/// 动态功能胶囊：功能来自 QJS 插件 JSON，不硬编码图标，保持纯文字紧凑胶囊。
class _PluginFunctionPill extends StatefulWidget {
  const _PluginFunctionPill({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  State<_PluginFunctionPill> createState() => _PluginFunctionPillState();
}

class _PluginFunctionPillState extends State<_PluginFunctionPill> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    final enabled = widget.onTap != null;
    final bg = !enabled
        ? c.surface2.withValues(alpha: 0.55)
        : _hovered
        ? Color.alphaBlend(c.accent.withValues(alpha: 0.08), c.accentSoft)
        : c.accentSoft;
    final fg = enabled ? c.accent : c.text3;

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 11),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                widget.label,
                textHeightBehavior: kCalmTextHeightBehavior,
                strutStyle: calmStrut(11.5),
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  color: fg,
                  height: 1.2,
                  leadingDistribution: TextLeadingDistribution.even,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
