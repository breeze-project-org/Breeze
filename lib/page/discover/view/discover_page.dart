import 'package:auto_route/auto_route.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/router/router.gr.dart';
import 'package:zephyr/cubit/plugin_registry_cubit.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/discover/cubit/discover_cubit.dart';
import 'package:zephyr/page/discover/service/discover_router.dart';
import 'package:zephyr/page/discover/view/plugin_order_dialog.dart';
import 'package:zephyr/page/discover/widgets/plugin_card.dart';
import 'package:zephyr/page/search/cubit/search_cubit.dart';
import 'package:zephyr/plugin/plugin_registry_service.dart';
import 'package:zephyr/ui/ui.dart';
import 'package:zephyr/widgets/toast.dart';

@RoutePage()
class DiscoverPage extends StatelessWidget {
  const DiscoverPage({super.key});

  @override
  Widget build(BuildContext context) {
    final registry = context.read<PluginRegistryCubit>();
    return BlocProvider(
      create: (_) => DiscoverCubit(registry: registry)..load(),
      child: const _DiscoverView(),
    );
  }
}

class _DiscoverView extends StatelessWidget {
  const _DiscoverView();

  @override
  Widget build(BuildContext context) {
    return CalmPageScaffold(
      title: t.discover.title,
      showBack: false,
      maxContentWidth: 880,
      actions: [
        CalmIconButton(
          icon: Icons.reorder_rounded,
          tooltip: t.discover.customOrder,
          onPressed: () => showPluginOrderDialog(context),
        ),
        CalmIconButton(
          icon: Icons.search_rounded,
          tooltip: t.discover.search,
          onPressed: () => _search(context),
        ),
      ],
      body: RefreshIndicator(
        onRefresh: () => context.read<DiscoverCubit>().reload(),
        child: _buildPluginHome(context),
      ),
    );
  }

  Widget _buildPluginHome(BuildContext context) {
    return BlocBuilder<DiscoverCubit, DiscoverState>(
      builder: (context, state) {
        final plugins = state.plugins.values.toList();

        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 120),
          children: [
            _buildPluginStoreButton(context),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: CalmSectionHeader(
                title: t.discover.pluginManagement,
                countText: plugins.isEmpty ? null : '${plugins.length}',
              ),
            ),
            const SizedBox(height: 8),
            if (plugins.isEmpty)
              CalmEmptyState(
                icon: Icons.extension_outlined,
                title: t.discover.noPlugins,
                action: CalmButton(
                  label: t.discover.pluginStore,
                  icon: Icons.storefront_outlined,
                  variant: CalmButtonVariant.tonal,
                  size: CalmButtonSize.xs,
                  onPressed: () => context.pushRoute(const PluginStoreRoute()),
                ),
              )
            else
              for (final plugin in plugins)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _buildPluginCard(context, plugin, state),
                ),
          ],
        );
      },
    );
  }

  Widget _buildPluginCard(
    BuildContext context,
    PluginRuntimeState plugin,
    DiscoverState state,
  ) {
    final cubit = context.read<DiscoverCubit>();
    final info = state.infos[plugin.uuid];
    final error = state.infoErrors[plugin.uuid];

    return PluginCard(
      pluginUuid: plugin.uuid,
      pluginState: plugin,
      info: info,
      error: error,
      isToggling: state.togglingUuids.contains(plugin.uuid),
      onSearch: () => _openPluginSearch(context, plugin.uuid),
      onSettings: (title) => _openPluginSettings(context, plugin.uuid, title),
      onToggleEnabled: (enabled) => cubit.toggleEnabled(plugin.uuid, enabled),
      onRetry: () => cubit.retryLoadInfo(plugin.uuid),
      // 卡片动作属于该卡片的插件，必须用它自己的 uuid 派发；
      // 用全局默认插件（cubit.currentFrom）会把 A 的 fnPath 打到 B 的 bundle。
      onAction: (action) => DiscoverRouter.route(
        context,
        action: action,
        currentFrom: plugin.uuid,
      ),
    );
  }

  Widget _buildPluginStoreButton(BuildContext context) {
    final c = context.calm;
    return CalmCard(
      padding: EdgeInsets.zero,
      radius: 16,
      child: CalmListTile(
        title: t.discover.pluginStore,
        subtitle: t.discover.browseInstall,
        borderRadius: 16,
        onTap: () => context.pushRoute(const PluginStoreRoute()),
        leading: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: c.accentSoft,
            borderRadius: BorderRadius.circular(11),
          ),
          alignment: Alignment.center,
          child: Icon(Icons.storefront_outlined, size: 18, color: c.accent),
        ),
        trailing: Icon(Icons.chevron_right_rounded, size: 18, color: c.text3),
      ),
    );
  }

  void _openPluginSearch(BuildContext context, String from) {
    final source = from.trim();
    if (source.isEmpty) {
      showErrorToast(t.error.missingPluginSource(action: t.discover.search));
      return;
    }
    context.pushRoute(
      SearchRoute(
        searchState: SearchStates.initial().copyWith(from: source),
        aggregateMode: false,
      ),
    );
  }

  void _openPluginSettings(BuildContext context, String uuid, String title) {
    context.pushRoute(
      PluginSettingsRoute(
        from: uuid,
        pluginUuid: uuid,
        pluginRuntimeName: uuid,
        pluginDisplayName: title,
      ),
    );
  }

  void _search(BuildContext context) {
    final cubit = context.read<DiscoverCubit>();
    final source = cubit.currentFrom;
    if (source.isEmpty) {
      showErrorToast(t.discover.noPluginForSearch);
      return;
    }
    context.pushRoute(
      SearchRoute(
        searchState: SearchStates.initial().copyWith(from: source),
        aggregateMode: true,
      ),
    );
  }
}
