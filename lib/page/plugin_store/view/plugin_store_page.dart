import 'package:auto_route/auto_route.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/page/plugin_store/cubit/plugin_store_cubit.dart';
import 'package:zephyr/page/plugin_store/widgets/cloud_plugin_card.dart';
import 'package:zephyr/page/plugin_store/widgets/plugin_store_status_banner.dart';
import 'package:zephyr/plugin/utils/plugin_local_file_picker.dart';
import 'package:zephyr/ui/ui.dart';
import 'package:zephyr/util/system/external_link.dart';
import 'package:zephyr/widgets/toast.dart';

@RoutePage()
class PluginStorePage extends StatelessWidget {
  const PluginStorePage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => PluginStoreCubit()..loadCloudPlugins(),
      child: const _PluginStorePageContent(),
    );
  }
}

class _PluginStorePageContent extends StatefulWidget {
  const _PluginStorePageContent();

  @override
  State<_PluginStorePageContent> createState() =>
      _PluginStorePageContentState();
}

class _PluginStorePageContentState extends State<_PluginStorePageContent> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    setState(() {});
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PluginStoreCubit, PluginStoreState>(
      builder: (context, state) {
        return CalmPageScaffold(
          title: t.plugin.store,
          maxContentWidth: 840,
          actions: [
            CalmIconButton(
              icon: Icons.refresh_rounded,
              tooltip: t.common.refresh,
              onPressed: state.cloudLoading
                  ? null
                  : context.read<PluginStoreCubit>().loadCloudPlugins,
            ),
          ],
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              CalmTextField(
                controller: _searchController,
                prefixIcon: Icons.search_rounded,
                hintText: t.plugin.searchHint,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              _buildInstallButtons(state.installing),
              const SizedBox(height: 18),
              _buildCloudPluginsSection(state),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInstallButtons(bool installing) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        CalmButton(
          label: t.plugin.localInstall,
          icon: Icons.folder_open_outlined,
          variant: CalmButtonVariant.tonal,
          size: CalmButtonSize.sm,
          onPressed: installing ? null : _installFromLocal,
        ),
        CalmButton(
          label: t.plugin.networkInstall,
          icon: Icons.language_rounded,
          variant: CalmButtonVariant.secondary,
          size: CalmButtonSize.sm,
          onPressed: installing ? null : _installFromNetwork,
        ),
      ],
    );
  }

  Widget _buildCloudPluginsSection(PluginStoreState state) {
    final cubit = context.read<PluginStoreCubit>();
    final query = _searchController.text.trim().toLowerCase();
    final displayPlugins = state.cloudPlugins.where((item) {
      if (query.isEmpty) return true;
      final name = item.manifest.name.toLowerCase();
      final creator = item.manifest.authorOf(item.repo).toLowerCase();
      final repo = item.repo.toLowerCase();
      return name.contains(query) ||
          creator.contains(query) ||
          repo.contains(query);
    }).toList();

    final hasData = state.cloudPlugins.isNotEmpty;
    final hasError = state.cloudError.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (state.installing) ...[
          PluginStoreStatusBanner(message: state.installMessage),
          const SizedBox(height: 12),
        ],
        CalmSectionHeader(
          title: t.plugin.cloudPlugins,
          countText: hasData ? '${displayPlugins.length}' : null,
          trailing: state.cloudLoading
              ? const CalmLoading(size: 14)
              : CalmIconButton(
                  icon: Icons.refresh_rounded,
                  size: 26,
                  iconSize: 14,
                  tooltip: t.common.refresh,
                  onPressed: cubit.loadCloudPlugins,
                ),
        ),
        const SizedBox(height: 10),
        if (state.cloudLoading && !hasData)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 28),
            child: Center(child: CalmLoading(label: t.common.loading)),
          )
        else if (hasError && !hasData)
          CalmErrorState(
            title: t.plugin.cloudPlugins,
            errorDetail: state.cloudError,
            retryLabel: t.common.retry,
            onRetry: cubit.loadCloudPlugins,
          )
        else if (!hasData)
          CalmEmptyState(
            icon: Icons.cloud_off_rounded,
            title: t.plugin.noCloudPlugins,
          )
        else if (displayPlugins.isEmpty)
          CalmEmptyState(
            icon: Icons.search_off_rounded,
            title: t.plugin.noMatchingPlugins,
          )
        else
          Column(
            children: displayPlugins
                .map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: CloudPluginCard(
                      item: item,
                      installing: state.installing,
                      onOpenHome: _openExternalUrl,
                      onInstall: () => context
                          .read<PluginStoreCubit>()
                          .installFromCloud(item),
                    ),
                  ),
                )
                .toList(),
          ),
        if (hasError && hasData) ...[
          const SizedBox(height: 10),
          CalmStatusBanner(title: state.cloudError, tone: CalmTone.danger),
        ],
      ],
    );
  }

  Future<void> _openExternalUrl(String rawUrl) async {
    final resolved = rawUrl.trim();
    if (resolved.isEmpty) {
      return;
    }
    final uri = Uri.tryParse(resolved);
    if (uri == null) {
      showErrorToast(t.plugin.invalidLink(url: resolved));
      return;
    }
    final opened = await openExternalUrl(uri);
    if (!opened) {
      showErrorToast(t.plugin.cannotOpenLink(url: resolved));
    }
  }

  Future<void> _installFromLocal() async {
    try {
      final file = await pickPluginScriptFile();
      if (file == null) {
        return;
      }
      final bytes = await file.readAsBytes();
      if (!mounted) {
        return;
      }
      await context.read<PluginStoreCubit>().installFromLocalBytes(
        bytes,
        fileName: file.name,
      );
    } catch (e) {
      logger.e(e);
      showErrorToast(t.plugin.readLocalPluginFailed(error: e.toString()));
    }
  }

  Future<void> _installFromNetwork() async {
    final url = await _showInputDialog(
      context,
      title: t.plugin.addFromNetwork,
      hintText: t.plugin.networkInstallHint,
    );
    if (url == null) {
      return;
    }

    final resolvedUrl = url.trim();
    if (resolvedUrl.isEmpty) {
      showErrorToast(t.plugin.urlCannotBeEmpty);
      return;
    }

    if (!mounted) {
      return;
    }
    await context.read<PluginStoreCubit>().installFromNetworkUrl(resolvedUrl);
  }

  Future<String?> _showInputDialog(
    BuildContext context, {
    required String title,
    required String hintText,
  }) {
    final controller = TextEditingController();
    return showCalmDialog<String>(
      context,
      title: title,
      icon: Icons.link_rounded,
      bodyBuilder: (dialogContext) => CalmTextField(
        controller: controller,
        prefixIcon: Icons.link_rounded,
        hintText: hintText,
        onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
      ),
      actionsBuilder: (dialogContext) => [
        CalmButton(
          label: t.common.cancel,
          variant: CalmButtonVariant.ghost,
          size: CalmButtonSize.xs,
          onPressed: () => Navigator.of(dialogContext).pop(),
        ),
        CalmButton(
          label: t.plugin.startInstall,
          variant: CalmButtonVariant.primary,
          size: CalmButtonSize.xs,
          onPressed: () => Navigator.of(dialogContext).pop(controller.text),
        ),
      ],
    );
  }
}
