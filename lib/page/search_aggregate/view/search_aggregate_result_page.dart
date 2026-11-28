import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/cubit/plugin_registry_cubit.dart';
import 'package:zephyr/plugin/plugin_registry_service.dart';
import 'package:zephyr/plugin/local_comic_plugin.dart';
import 'package:zephyr/page/search/cubit/search_cubit.dart';
import 'package:zephyr/page/search/widget/search_input_dialog.dart';
import 'package:zephyr/page/search/widget/source_select_dialog.dart';
import 'package:zephyr/page/search_result/bloc/search_bloc.dart';
import 'package:zephyr/config/router/router.gr.dart';
import 'package:zephyr/ui/ui.dart';
import 'package:zephyr/widgets/comic_simplify_entry/comic_simplify_entry.dart';
import 'package:zephyr/widgets/comic_simplify_entry/comic_simplify_entry_info.dart';
import 'package:zephyr/widgets/comic_simplify_entry/comic_simplify_entry_mapper.dart';

import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/search_aggregate/cubit/search_aggregate_cubit.dart';

@RoutePage()
class SearchAggregateResultPage extends StatelessWidget
    implements AutoRouteWrapper {
  const SearchAggregateResultPage({
    super.key,
    required this.searchEvent,
    this.searchCubit,
    this.selectedSources = const <String, bool>{},
  });

  final SearchEvent searchEvent;
  final SearchCubit? searchCubit;
  final Map<String, bool> selectedSources;

  @override
  Widget wrappedRoute(BuildContext context) {
    final registry = context.read<PluginRegistryCubit>().state;
    final visiblePlugins = PluginRegistryService.I.sortPlugins(
      registry.plugins.values.where(
        (state) => !state.isDeleted && !isLocalComicPluginId(state.uuid),
      ),
    );
    final initial = selectedSources.isNotEmpty
        ? {for (final entry in selectedSources.entries) entry.key: entry.value}
        : {for (final plugin in visiblePlugins) plugin.uuid: plugin.isEnabled};
    return MultiBlocProvider(
      providers: [
        searchCubit != null
            ? BlocProvider.value(value: searchCubit!)
            : BlocProvider(
                create: (_) => SearchCubit(searchEvent.searchStates),
              ),
        BlocProvider(
          create: (_) =>
              AggregateSearchCubit(searchEvent, initialSelectedSources: initial)
                ..search(),
        ),
      ],
      child: this,
    );
  }

  @override
  Widget build(BuildContext context) {
    return _SearchAggregateResultPage(searchEvent: searchEvent);
  }
}

class _SearchAggregateResultPage extends StatefulWidget {
  const _SearchAggregateResultPage({required this.searchEvent});

  final SearchEvent searchEvent;

  @override
  State<_SearchAggregateResultPage> createState() =>
      _SearchAggregateResultPageState();
}

class _SearchAggregateResultPageState
    extends State<_SearchAggregateResultPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final keyword = widget.searchEvent.searchStates.searchKeyword.trim();
      if (keyword.isEmpty || !mounted) {
        return;
      }
      final historyItem = _buildHistoryItem(widget.searchEvent);
      final settingCubit = context.read<GlobalSettingCubit>();
      final history = settingCubit.state.searchHistory.toList();
      history
        ..remove(historyItem)
        ..insert(0, historyItem);
      await Future.delayed(const Duration(milliseconds: 200));
      if (!mounted) {
        return;
      }
      settingCubit.updateState(
        (current) =>
            current.copyWith(searchHistory: history.take(200).toList()),
      );
    });
  }

  String _buildHistoryItem(SearchEvent event) {
    return event.searchStates.searchKeyword.trim();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: c.bg,
        foregroundColor: c.text,
        surfaceTintColor: Colors.transparent,
        automaticallyImplyLeading: false,
        titleSpacing: 0,
        title: _SearchBarTrigger(searchEvent: widget.searchEvent),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1, color: c.border),
        ),
      ),
      body: Column(
        children: [
          const _FilterChipsRow(),
          Expanded(
            child: BlocBuilder<AggregateSearchCubit, AggregateSearchState>(
              builder: (context, state) {
                final hasAnyResponse =
                    state.results.isNotEmpty || state.errors.isNotEmpty;
                if (state.status == AggregateSearchStatus.loading &&
                    !hasAnyResponse) {
                  return const Center(child: CalmLoading());
                }
                return Stack(
                  children: [
                    _ResultList(searchEvent: widget.searchEvent, state: state),
                    if (state.status == AggregateSearchStatus.loading)
                      const Align(
                        alignment: Alignment.topCenter,
                        child: CalmProgressBar(height: 3),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchBarTrigger extends StatelessWidget {
  const _SearchBarTrigger({required this.searchEvent});

  final SearchEvent searchEvent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 10, right: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          CalmIconButton(
            icon: Icons.arrow_back_rounded,
            tooltip: t.common.back,
            onPressed: () => context.maybePop(),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: SearchQueryField(
              query: searchEvent.searchStates.searchKeyword,
              hintText: t.search.searchHint,
              semanticLabel: t.search.title,
              onTap: () => _openSearchPage(context),
            ),
          ),
          const SizedBox(width: 6),
          CalmIconButton(
            icon: Icons.tune_rounded,
            tooltip: t.search.selectSourceTooltip,
            onPressed: () => _showSourceDialog(context),
          ),
        ],
      ),
    );
  }

  void _openSearchPage(BuildContext context) {
    final stack = context.router.stack;
    if (stack.length > 1 && stack[stack.length - 2].name == SearchRoute.name) {
      context.maybePop();
      return;
    }

    context.replaceRoute(
      SearchRoute(
        key: ValueKey(const Uuid().v4()),
        searchState: context.read<SearchCubit>().state,
        aggregateMode: true,
      ),
    );
  }

  Future<void> _showSourceDialog(BuildContext context) async {
    final cubit = context.read<AggregateSearchCubit>();
    final options = _sourceOptions(context, cubit.state.selectedSources.keys);
    final selected = await showSourceSelectDialog(
      context,
      initial: cubit.state.selectedSources,
      sourceOptions: options,
    );
    if (selected != null) {
      await cubit.applySelectedSources(selected);
    }
  }

  List<({String pluginId, String title})> _sourceOptions(
    BuildContext context,
    Iterable<String> selectedKeys,
  ) {
    final registry = context.read<PluginRegistryCubit>().state;
    final ordered = PluginRegistryService.I.sortPlugins(
      registry.plugins.values.where((state) => !state.isDeleted),
    );
    final selectedSet = selectedKeys.toSet();
    final result = <({String pluginId, String title})>[];
    for (final plugin in ordered) {
      if (!selectedSet.contains(plugin.uuid)) {
        continue;
      }
      result.add((
        pluginId: plugin.uuid,
        title: registry.pluginName(plugin.uuid),
      ));
    }
    return result;
  }
}

class _FilterChipsRow extends StatelessWidget {
  const _FilterChipsRow();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AggregateSearchCubit, AggregateSearchState>(
      builder: (context, state) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              alignment: WrapAlignment.start,
              spacing: 8,
              runSpacing: 8,
              children: [
                CalmFilterChip(
                  label: t.search.hasResults,
                  selected: state.showHasResults,
                  onSelected: (value) => context
                      .read<AggregateSearchCubit>()
                      .toggleHasResults(value),
                ),
                CalmFilterChip(
                  label: t.search.showErrors,
                  selected: state.showErrors,
                  onSelected: (value) => context
                      .read<AggregateSearchCubit>()
                      .toggleShowErrors(value),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ResultList extends StatelessWidget {
  const _ResultList({required this.searchEvent, required this.state});

  final SearchEvent searchEvent;
  final AggregateSearchState state;

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    final children = <Widget>[];
    final registry = context.watch<PluginRegistryCubit>().state;
    final selectedIds = state.selectedSources.keys.toSet();
    final pluginIds = PluginRegistryService.I
        .sortPlugins(
          registry.plugins.values.where(
            (plugin) => selectedIds.contains(plugin.uuid),
          ),
        )
        .map((plugin) => plugin.uuid)
        .toList();
    for (final pluginId in pluginIds) {
      final selected = state.selectedSources[pluginId] ?? false;
      if (!selected) {
        continue;
      }

      final items = state.results[pluginId] ?? const <dynamic>[];
      final error = state.errors[pluginId] ?? '';
      final refreshing = state.refreshingSources.contains(pluginId);

      final shouldShowResultSection = items.isNotEmpty || !state.showHasResults;
      if (shouldShowResultSection) {
        final List<ComicSimplifyEntryInfo> entries = items.isNotEmpty
            ? mapToUnifiedComicSimplifyEntryInfoList(items)
            : const <ComicSimplifyEntryInfo>[];
        children.add(
          Padding(
            key: ValueKey('aggregate-source-$pluginId'),
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 旧实现整行可点进单源搜索结果页；分组头 + 「更多」胶囊都保留这个入口。
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _openSourceSearch(context, pluginId),
                  child: CalmSectionHeader(
                    title: _sourceTitle(context, pluginId),
                    countText: t.search.resultCount(count: items.length),
                    actionLabel: t.common.more,
                    onActionTap: () => _openSourceSearch(context, pluginId),
                  ),
                ),
                const SizedBox(height: 8),
                if (entries.isNotEmpty)
                  ComicFixedSizeHorizontalList(
                    key: ValueKey('aggregate-list-$pluginId'),
                    entries: entries,
                    spacing: 10,
                    itemWidth: 112,
                  ),
                if (entries.isEmpty)
                  CalmStatusBanner(title: t.search.noResults),
              ],
            ),
          ),
        );
      }

      if (state.showErrors && error.isNotEmpty) {
        children.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CalmStatusBanner(
                  title: t.search.loadFailedForSource(
                    source: _sourceTitle(context, pluginId),
                  ),
                  tone: CalmTone.danger,
                  trailing: refreshing
                      ? const CalmLoading(size: 16)
                      : CalmIconButton(
                          icon: Icons.refresh_rounded,
                          tooltip: t.common.refresh,
                          size: 26,
                          iconSize: 14,
                          onPressed: () => context
                              .read<AggregateSearchCubit>()
                              .refreshSource(pluginId),
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 5, 4, 0),
                  child: Text(
                    error,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: c.text2),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    }

    if (children.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: CalmEmptyState(
            icon: Icons.travel_explore_rounded,
            title: t.search.noResults,
          ),
        ),
      );
    }

    return ListView(children: children);
  }

  String _sourceTitle(BuildContext context, String pluginId) {
    return context.select<PluginRegistryCubit, String>(
      (cubit) => cubit.state.pluginName(pluginId),
    );
  }

  void _openSourceSearch(BuildContext context, String pluginId) {
    final currentStates = searchEvent.searchStates;
    context.pushRoute(
      SearchResultRoute(
        key: ValueKey(const Uuid().v4()),
        searchEvent: searchEvent.copyWith(
          searchStates: currentStates.copyWith(from: pluginId),
          page: 1,
        ),
        searchCubit: context.read<SearchCubit>(),
      ),
    );
  }
}
