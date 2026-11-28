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
      radius: 16,
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      child: Row(
        children: [
          CalmSkeletonBox(width: 38, height: 38, radius: 11),
          SizedBox(width: 11),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CalmSkeletonBox(width: 120, height: 12, radius: 6),
                SizedBox(height: 6),
                CalmSkeletonBox(width: 64, height: 10, radius: 5),
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
      radius: 16,
      padding: const EdgeInsets.fromLTRB(12, 11, 10, 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: c.dangerSoft,
              borderRadius: BorderRadius.circular(11),
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

  String _resolveVersion(Map<String, dynamic> info) {
    final raw = pluginState.version.trim().isNotEmpty
        ? pluginState.version.trim()
        : (info['version']?.toString().trim() ?? '');
    if (raw.isEmpty) return '';
    if (raw.startsWith('v') || raw.startsWith('V')) return raw;
    return 'v$raw';
  }

  Widget _buildIconPlaceholder(
    BuildContext context,
    String title,
    bool isEnabled,
  ) {
    final c = context.calm;
    final trimmed = title.trim();
    final initial = trimmed.isNotEmpty
        ? trimmed.characters.first.toUpperCase()
        : '';
    return ColoredBox(
      color: isEnabled ? c.accentSoft : c.surface2,
      child: Center(
        child: initial.isNotEmpty
            ? Text(
                initial,
                textHeightBehavior: kCalmTextHeightBehavior,
                strutStyle: calmStrut(15),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: isEnabled ? c.accent : c.text3,
                  height: 1.2,
                  leadingDistribution: TextLeadingDistribution.even,
                ),
              )
            : Icon(Icons.extension_outlined, size: 19, color: c.text3),
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
    final versionText = _resolveVersion(info);
    final iconUrl = info['iconUrl']?.toString().trim() ?? '';

    final iconWidget = AnimatedOpacity(
      duration: const Duration(milliseconds: 160),
      opacity: isEnabled ? 1 : 0.62,
      child: Container(
        width: 38,
        height: 38,
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: c.border.withValues(alpha: c.border.a * 0.85),
            width: 1,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(11),
          child: PluginIcon(
            url: iconUrl,
            placeholder: _buildIconPlaceholder(context, title, isEnabled),
          ),
        ),
      ),
    );

    final showTray = isEnabled && rawFunctions.isNotEmpty;
    final trayBg = Color.alphaBlend(
      c.surface2.withValues(alpha: 0.55),
      c.surface,
    );

    return CalmCard(
      radius: 16,
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  iconWidget,
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Flexible(
                              child: Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textHeightBehavior: kCalmTextHeightBehavior,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                  color: isEnabled ? c.text : c.text2,
                                  height: 1.25,
                                  leadingDistribution:
                                      TextLeadingDistribution.even,
                                ),
                              ),
                            ),
                            if (!isEnabled) ...[
                              const SizedBox(width: 6),
                              CalmBadge(
                                label: t.discover.disabled,
                                tone: CalmBadgeTone.neutral,
                              ),
                            ],
                          ],
                        ),
                        if (versionText.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            versionText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textHeightBehavior: kCalmTextHeightBehavior,
                            style: TextStyle(
                              fontSize: 11,
                              color: c.text3,
                              height: 1.25,
                              leadingDistribution: TextLeadingDistribution.even,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  // 插件关闭时搜索入口置灰（CalmIconButton 仅在 onPressed 为空时不响应）。
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 140),
                    opacity: isEnabled ? 1 : 0.35,
                    child: CalmIconButton(
                      icon: Icons.search_rounded,
                      ghost: true,
                      size: 30,
                      iconSize: 16,
                      tooltip: t.common.search,
                      onPressed: isEnabled ? onSearch : null,
                    ),
                  ),
                  const SizedBox(width: 2),
                  CalmIconButton(
                    icon: Icons.settings_outlined,
                    ghost: true,
                    size: 30,
                    iconSize: 16,
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
            ),
            // 下半区功能托盘：插件关闭时完全收起，只保留紧凑头部行。
            if (showTray)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
                decoration: BoxDecoration(
                  color: trayBg,
                  border: Border(
                    top: BorderSide(
                      color: c.border.withValues(alpha: c.border.a * 0.8),
                      width: 1,
                    ),
                  ),
                ),
                child: _buildFunctionButtons(context, rawFunctions),
              ),
          ],
        ),
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
      return _PluginFunctionKeycap(
        label: text.let(convertChineseForDisplay),
        onTap: enabled ? () => onAction(action) : null,
      );
    }).toList();
    return Wrap(spacing: 6, runSpacing: 6, children: chips);
  }
}

/// 动态功能键帽入口：功能来自 QJS 插件 JSON，白底轻描边 + 悬停亮主题色。
class _PluginFunctionKeycap extends StatefulWidget {
  const _PluginFunctionKeycap({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  State<_PluginFunctionKeycap> createState() => _PluginFunctionKeycapState();
}

class _PluginFunctionKeycapState extends State<_PluginFunctionKeycap> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    final enabled = widget.onTap != null;
    final bg = !enabled
        ? c.surface2.withValues(alpha: 0.5)
        : _pressed
        ? Color.alphaBlend(c.accent.withValues(alpha: 0.12), c.surface)
        : _hovered
        ? Color.alphaBlend(c.accent.withValues(alpha: 0.06), c.surface)
        : c.surface;
    final borderColor = !enabled
        ? c.border.withValues(alpha: c.border.a * 0.5)
        : (_hovered || _pressed)
        ? c.accent.withValues(alpha: 0.55)
        : c.border;
    final fg = !enabled
        ? c.text3
        : (_hovered || _pressed)
        ? c.accent
        : c.text;
    final chevronColor = (_hovered || _pressed)
        ? c.accent
        : c.text3.withValues(alpha: 0.75);

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _pressed && enabled ? 0.97 : 1.0,
          duration: const Duration(milliseconds: 100),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 130),
            curve: Curves.easeOut,
            height: 28,
            padding: EdgeInsets.only(left: 10, right: enabled ? 7 : 10),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: borderColor, width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  widget.label,
                  textHeightBehavior: kCalmTextHeightBehavior,
                  strutStyle: calmStrut(12),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: fg,
                    height: 1.2,
                    leadingDistribution: TextLeadingDistribution.even,
                  ),
                ),
                if (enabled) ...[
                  const SizedBox(width: 2),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 13,
                    color: chevronColor,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
