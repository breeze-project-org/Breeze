import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/plugin_store/models/cloud_plugin_item.dart';
import 'package:zephyr/plugin/plugin_registry_service.dart';
import 'package:zephyr/ui/ui.dart';
import 'package:zephyr/widgets/plugin_icon.dart';

class CloudPluginCard extends StatelessWidget {
  const CloudPluginCard({
    super.key,
    required this.item,
    required this.installing,
    required this.onOpenHome,
    required this.onInstall,
  });

  final CloudPluginItem item;
  final bool installing;
  final ValueChanged<String> onOpenHome;
  final VoidCallback onInstall;

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    final manifest = item.manifest;
    final localState = manifest.uuid.isNotEmpty
        ? PluginRegistryService.I.getByUuid(manifest.uuid)
        : null;
    final isInstalled = localState != null && !localState.isDeleted;
    final localVersion = localState?.version.trim() ?? '';
    final creatorText = manifest.authorOf(item.repo);
    final title = manifest.name.trim().isNotEmpty
        ? manifest.name.trim()
        : item.repo;

    return CalmCard(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      radius: 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CloudPluginIcon(iconUrl: manifest.iconUrl),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textHeightBehavior: kCalmTextHeightBehavior,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: c.text,
                              height: 1.25,
                              leadingDistribution: TextLeadingDistribution.even,
                            ),
                          ),
                        ),
                        if (isInstalled) ...[
                          const SizedBox(width: 8),
                          CalmBadge(
                            label: t.plugin.installed,
                            tone: CalmBadgeTone.success,
                            dot: true,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      isInstalled && localVersion.isNotEmpty
                          ? '${t.plugin.cloudVersion(version: manifest.version)}  ·  ${t.plugin.localVersion(version: localVersion)}'
                          : t.plugin.cloudVersion(version: manifest.version),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: c.text3,
                        height: 1.3,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    if (manifest.describe.trim().isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        manifest.describe.trim(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: c.text2,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              CalmBadge(
                label: _shortenBadgeLabel('${t.plugin.repo}: ${item.repo}'),
                tone: CalmBadgeTone.neutral,
              ),
              if (creatorText.isNotEmpty)
                CalmBadge(
                  label: _shortenBadgeLabel('${t.plugin.author}: $creatorText'),
                  tone: CalmBadgeTone.neutral,
                ),
            ],
          ),
          const SizedBox(height: 9),
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                if (manifest.home.trim().isNotEmpty)
                  CalmButton(
                    label: t.plugin.homepage,
                    icon: Icons.open_in_new_rounded,
                    size: CalmButtonSize.xs,
                    variant: CalmButtonVariant.ghost,
                    onPressed: installing
                        ? null
                        : () => onOpenHome(manifest.home.trim()),
                  ),
                if (item.githubRepositoryUrl.isNotEmpty)
                  CalmButton(
                    label: t.plugin.githubRepo,
                    icon: Icons.code_rounded,
                    size: CalmButtonSize.xs,
                    variant: CalmButtonVariant.ghost,
                    onPressed: installing
                        ? null
                        : () => onOpenHome(item.githubRepositoryUrl),
                  ),
                CalmButton(
                  label: isInstalled
                      ? t.plugin.downloadUpdate
                      : t.plugin.download,
                  icon: Icons.download_rounded,
                  size: CalmButtonSize.xs,
                  variant: isInstalled
                      ? CalmButtonVariant.secondary
                      : CalmButtonVariant.tonal,
                  loading: installing,
                  onPressed: installing ? null : onInstall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// CalmBadge 不换行也不省略：仓库/作者名过长时先截断，避免窄屏溢出。
  static String _shortenBadgeLabel(String value) {
    const maxLength = 40;
    return value.length <= maxLength
        ? value
        : '${value.substring(0, maxLength - 1)}…';
  }
}

class _CloudPluginIcon extends StatelessWidget {
  const _CloudPluginIcon({required this.iconUrl});

  final String iconUrl;

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 40,
        height: 40,
        color: c.surface2,
        alignment: Alignment.center,
        child: PluginIcon(
          url: iconUrl,
          placeholder: Icon(Icons.extension_outlined, size: 19, color: c.text3),
        ),
      ),
    );
  }
}
