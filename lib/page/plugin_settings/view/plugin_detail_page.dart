import 'package:auto_route/auto_route.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:markdown_widget/markdown_widget.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/network/http/plugin/unified_comic_plugin.dart';
import 'package:zephyr/util/system/external_link.dart';
import 'package:zephyr/page/plugin_settings/models/plugin_detail.dart';
import 'package:zephyr/cubit/plugin_registry_cubit.dart';
import 'package:zephyr/page/setting/common/setting_ui.dart';
import 'package:zephyr/util/error/error_filter.dart';
import 'package:zephyr/util/json/json_value.dart';
import 'package:zephyr/widgets/plugin_icon.dart';
import 'package:zephyr/widgets/toast.dart';
import 'package:zephyr/main.dart';

/// 新插件详情页（CalmUI 版）：简介 + 作者 + md 长文 + 主页入口。
/// 长文按需调 `getPluginDetail` 获取，不在列表/设置页预取。
@RoutePage()
class PluginDetailPage extends StatefulWidget {
  const PluginDetailPage({
    super.key,
    required this.from,
    required this.pluginUuid,
    required this.pluginDisplayName,
  });

  final String from;
  final String pluginUuid;
  final String pluginDisplayName;

  @override
  State<PluginDetailPage> createState() => _PluginDetailPageState();
}

class _PluginDetailPageState extends State<PluginDetailPage> {
  bool _loading = true;
  String? _error;
  PluginDetail? _detail;
  String _iconUrl = '';
  String _version = '';
  String _cachedHome = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final registry = context.read<PluginRegistryCubit>().state;
      final cached = registry.infos[widget.pluginUuid];
      final localVersion =
          registry.plugins[widget.pluginUuid]?.version.trim() ?? '';
      final response = await callUnifiedComicPlugin(
        from: widget.from,
        fnPath: 'getPluginDetail',
        core: const <String, dynamic>{},
        extern: const <String, dynamic>{},
      );
      final detail = PluginDetail.fromMap(
        response.data,
        source: response.source,
      );
      if (!mounted) return;
      setState(() {
        _detail = detail;
        final cachedMap = asJsonMap(cached);
        _iconUrl = cachedMap['iconUrl']?.toString().trim() ?? '';
        _version = localVersion;
        _cachedHome = cachedMap['home']?.toString().trim() ?? '';
        _loading = false;
      });
    } catch (e) {
      logger.e(e);
      if (!mounted) return;
      setState(() {
        _error = normalizeSearchErrorMessage(e);
        _loading = false;
      });
    }
  }

  Future<void> _openHome(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null) {
      showErrorToast(t.plugin.invalidLink(url: url.trim()));
      return;
    }
    final opened = await openExternalUrl(uri);
    if (!opened) {
      showErrorToast(t.plugin.cannotOpenLink(url: url.trim()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final home = (_detail?.homeWithFallback(_cachedHome) ?? _cachedHome).trim();
    return SettingPageShell(
      title: widget.pluginDisplayName,
      subtitle: _version.isEmpty ? null : _version,
      actions: [
        if (home.isNotEmpty)
          CalmIconButton(
            icon: Icons.home_rounded,
            tooltip: t.plugin.homepage,
            onPressed: () => _openHome(home),
          ),
      ],
      child: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return Center(child: CalmLoading(label: t.common.loading));
    }
    if (_error != null) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: CalmErrorState(
              title: t.common.loadingFailed,
              errorDetail: _error!,
              errorDetailMaxLines: 4,
              retryLabel: t.common.retry,
              onRetry: _load,
            ),
          ),
        ),
      );
    }

    final c = context.calm;
    final detail = _detail!;
    final home = detail.homeWithFallback(_cachedHome).trim();
    final markdownConfig = MarkdownConfig(
      configs: [
        LinkConfig(
          style: TextStyle(
            color: c.accent,
            decoration: TextDecoration.underline,
            decorationColor: c.accent.withValues(alpha: 0.5),
          ),
          onTap: _openHome,
        ),
      ],
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: [
        _buildHeaderCard(context, detail),
        if (detail.creatorName.isNotEmpty ||
            detail.creatorDescribe.isNotEmpty) ...[
          const SizedBox(height: 12),
          _buildAuthorCard(context, detail),
        ],
        if (detail.describe.isNotEmpty) ...[
          const SizedBox(height: 12),
          _buildDescriptionCard(markdownConfig, detail.describe),
        ],
        if (home.isNotEmpty) ...[
          const SizedBox(height: 16),
          CalmButton(
            label: t.plugin.homepage,
            icon: Icons.home_rounded,
            variant: CalmButtonVariant.secondary,
            size: CalmButtonSize.md,
            expand: true,
            onPressed: () => _openHome(home),
          ),
        ],
      ],
    );
  }

  /// 顶部信息卡：头像 + 插件名 + 版本/来源徽章 + 版本/标识元信息。
  Widget _buildHeaderCard(BuildContext context, PluginDetail detail) {
    final c = context.calm;
    return CalmCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: SizedBox(
                  width: 72,
                  height: 72,
                  child: PluginIcon(
                    url: _iconUrl,
                    placeholder: Container(
                      color: c.surface2,
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.extension_outlined,
                        size: 30,
                        color: c.text3,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.pluginDisplayName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: c.text,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (_version.isNotEmpty)
                          CalmBadge(
                            label: _version,
                            tone: CalmBadgeTone.accent,
                            icon: Icons.sell_outlined,
                          ),
                        if (detail.source.isNotEmpty)
                          CalmBadge(
                            label: detail.source,
                            tone: CalmBadgeTone.neutral,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const CalmDivider(),
          _buildMetaRow(context, 'UUID', widget.pluginUuid),
        ],
      ),
    );
  }

  Widget _buildMetaRow(BuildContext context, String label, String value) {
    final c = context.calm;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: c.text3, height: 1.35),
            ),
          ),
          Expanded(
            child: CalmExpandableText(
              text: value,
              maxLines: 2,
              style: TextStyle(
                fontSize: 11.5,
                color: c.text2,
                height: 1.45,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 作者区：独立卡片，简介走可折叠文本，与插件长文视觉分离。
  Widget _buildAuthorCard(BuildContext context, PluginDetail detail) {
    final c = context.calm;
    return CalmCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildAuthorIcon(context, detail),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        detail.creatorName.isNotEmpty
                            ? detail.creatorName
                            : t.plugin.author,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: c.text,
                          height: 1.3,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    CalmBadge(
                      label: t.plugin.author,
                      tone: CalmBadgeTone.tonal,
                    ),
                  ],
                ),
                if (detail.creatorDescribe.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  CalmExpandableText(
                    text: detail.creatorDescribe,
                    maxLines: 3,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: c.text2,
                      height: 1.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 描述卡：纯文本走可折叠 [CalmExpandableText]，带 md 结构时仍交给 MarkdownWidget
  /// 渲染（保留链接与标题层级），两者都不丢内容。
  Widget _buildDescriptionCard(MarkdownConfig markdownConfig, String raw) {
    final c = context.calm;
    final text = raw.trim();
    return CalmCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CalmBadge(label: t.plugin.description, tone: CalmBadgeTone.tonal),
            ],
          ),
          const SizedBox(height: 10),
          if (_hasMarkdownSyntax(text))
            MarkdownWidget(
              data: text,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              config: markdownConfig,
            )
          else
            CalmExpandableText(
              text: text,
              maxLines: 5,
              style: TextStyle(fontSize: 11.5, color: c.text2, height: 1.55),
            ),
        ],
      ),
    );
  }

  /// 粗略判断是否用了 markdown 结构语法（标题/列表/引用/表格/链接/代码/加粗）。
  bool _hasMarkdownSyntax(String text) {
    return RegExp(
      r'(^|\n)\s{0,3}(#{1,6}\s|[-*+]\s|\d+\.\s|>|\|)|\]\(|`|\*\*|__',
    ).hasMatch(text);
  }

  /// 作者头像：有则 40px 圆角展示，无则人形图标占位。
  Widget _buildAuthorIcon(BuildContext context, PluginDetail detail) {
    final c = context.calm;
    if (detail.creatorIconUrl.isEmpty) {
      return Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: Icon(Icons.person_outline_rounded, size: 20, color: c.text3),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 40,
        height: 40,
        child: PluginIcon(
          url: detail.creatorIconUrl,
          placeholder: Container(
            color: c.surface2,
            alignment: Alignment.center,
            child: Icon(Icons.person_outline_rounded, size: 20, color: c.text3),
          ),
        ),
      ),
    );
  }
}
