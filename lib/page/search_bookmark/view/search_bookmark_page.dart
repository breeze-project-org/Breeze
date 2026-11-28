import 'package:auto_route/auto_route.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart';
import 'package:zephyr/config/router/router.gr.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/cubit/plugin_registry_cubit.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/object_box/model.dart';
import 'package:zephyr/page/search/cubit/search_cubit.dart';
import 'package:zephyr/page/search_bookmark/cubit/search_bookmark_cubit.dart';
import 'package:zephyr/page/search_result/bloc/search_bloc.dart';
import 'package:zephyr/type/enum.dart';
import 'package:zephyr/ui/ui.dart';
import 'package:zephyr/widgets/comic_entry/models/models.dart';
import 'package:zephyr/widgets/comic_simplify_entry/cover.dart';
import 'package:zephyr/widgets/error_view.dart';
import 'package:zephyr/widgets/toast.dart';

/// 书签锚点封面：与追更页同一尺寸/同一组件。
const double _bookmarkCoverWidth = 84;
const double _bookmarkCoverHeight = 112;

/// 解析锚点封面，缺失时用 anchorComicId 兜底 id。
UnifiedComicCover _resolveBookmarkCover(SearchBookmark item) {
  final cover = item.anchorCover;
  return UnifiedComicCover(
    id: cover != null && cover.id.trim().isNotEmpty
        ? cover.id
        : item.anchorComicId,
    url: cover?.url ?? '',
    path: cover?.path ?? '',
    extern: cover?.extern ?? const <String, dynamic>{},
  );
}

/// 搜索书签管理页：列出全部插件的书签，支持按插件筛选、按时间排序。
/// 点一条即参数重放跳转结果页。
@RoutePage()
class SearchBookmarkPage extends StatelessWidget {
  const SearchBookmarkPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => SearchBookmarkCubit()..loadAll(),
      child: const _SearchBookmarkView(),
    );
  }
}

class _SearchBookmarkView extends StatelessWidget {
  const _SearchBookmarkView();

  @override
  Widget build(BuildContext context) {
    final total = context.watch<SearchBookmarkCubit>().state.items.length;

    return CalmPageScaffold(
      title: t.searchBookmark.title,
      badge: total == 0 ? null : '$total',
      maxContentWidth: 840,
      actions: [
        CalmIconButton(
          icon: Icons.tune_rounded,
          tooltip: t.searchBookmark.filter,
          onPressed: () => _openFilter(context),
        ),
      ],
      body: const _BookmarkList(),
    );
  }

  Future<void> _openFilter(BuildContext context) async {
    final cubit = context.read<SearchBookmarkCubit>();
    final names = {
      for (final s in cubit.state.availableSources)
        s: context.read<PluginRegistryCubit>().state.pluginName(s),
    };
    // 弹窗内的可变草稿：主体改它，点应用时才回写 cubit。
    final draft = _BookmarkFilterDraft(
      ascending: cubit.state.sortAscending,
      sources: Set<String>.from(cubit.state.selectedSources),
      probePages: context
          .read<GlobalSettingCubit>()
          .state
          .searchBookmarkProbePages,
      availableSources: cubit.state.availableSources,
      sourceNames: names,
    );

    final result = await showCalmDialog<_BookmarkFilterResult>(
      context,
      title: t.searchBookmark.filter,
      icon: Icons.tune_rounded,
      maxWidth: 460,
      bodyBuilder: (_) => StatefulBuilder(
        builder: (ctx, setState) =>
            _BookmarkFilterBody(draft: draft, onChanged: () => setState(() {})),
      ),
      actionsBuilder: (ctx) => [
        CalmButton(
          label: t.common.cancel,
          variant: CalmButtonVariant.ghost,
          onPressed: () => Navigator.of(ctx).pop(),
        ),
        CalmButton(
          label: t.common.apply,
          variant: CalmButtonVariant.primary,
          onPressed: () => Navigator.of(ctx).pop(
            _BookmarkFilterResult(
              sources: draft.sources,
              ascending: draft.ascending,
              probePages: draft.probePages,
            ),
          ),
        ),
      ],
    );

    if (result == null || !context.mounted) return;
    cubit.applyFilter(sources: result.sources, ascending: result.ascending);
    context.read<GlobalSettingCubit>().updateState(
      (current) =>
          current.copyWith(searchBookmarkProbePages: result.probePages),
    );
  }
}

/// 筛选弹窗的可变草稿（排序 / 图源多选 / 找回页数）。
class _BookmarkFilterDraft {
  _BookmarkFilterDraft({
    required this.ascending,
    required this.sources,
    required this.probePages,
    required this.availableSources,
    required this.sourceNames,
  });

  bool ascending;
  Set<String> sources;
  int probePages;
  final List<String> availableSources;
  final Map<String, String> sourceNames;

  bool get allSelected =>
      availableSources.isNotEmpty && sources.length == availableSources.length;

  String nameOf(String source) {
    final name = sourceNames[source]?.trim() ?? '';
    return name.isNotEmpty ? name : source;
  }
}

class _BookmarkFilterBody extends StatelessWidget {
  const _BookmarkFilterBody({required this.draft, required this.onChanged});

  final _BookmarkFilterDraft draft;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    final sortedSources = draft.availableSources.toList()
      ..sort((a, b) => draft.nameOf(a).compareTo(draft.nameOf(b)));

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CalmSectionHeader(title: t.searchBookmark.sort),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            CalmFilterChip(
              label: t.searchBookmark.sortNewest,
              selected: !draft.ascending,
              onSelected: (_) {
                draft.ascending = false;
                onChanged();
              },
            ),
            CalmFilterChip(
              label: t.searchBookmark.sortOldest,
              selected: draft.ascending,
              onSelected: (_) {
                draft.ascending = true;
                onChanged();
              },
            ),
          ],
        ),
        const SizedBox(height: 16),
        CalmSectionHeader(
          title: t.searchBookmark.source,
          countText:
              '${draft.sources.length} / ${draft.availableSources.length}',
          actionLabel: draft.allSelected
              ? t.searchBookmark.deselectAll
              : t.common.selectAll,
          onActionTap: () {
            if (draft.allSelected) {
              draft.sources.clear();
            } else {
              draft.sources = draft.availableSources.toSet();
            }
            onChanged();
          },
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final source in sortedSources)
              CalmFilterChip(
                label: draft.nameOf(source),
                selected: draft.sources.contains(source),
                onSelected: (selected) {
                  if (selected) {
                    draft.sources.add(source);
                  } else {
                    draft.sources.remove(source);
                  }
                  onChanged();
                },
              ),
          ],
        ),
        const SizedBox(height: 16),
        CalmSectionHeader(title: t.searchBookmark.probePages),
        const SizedBox(height: 4),
        Text(
          t.searchBookmark.probePagesSubtitle,
          style: TextStyle(fontSize: 11, color: c.text3, height: 1.4),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final v in const [0, 1, 2, 3, 5])
              CalmFilterChip(
                label: '$v',
                selected: draft.probePages == v,
                onSelected: (_) {
                  draft.probePages = v;
                  onChanged();
                },
              ),
          ],
        ),
      ],
    );
  }
}

class _BookmarkFilterResult {
  _BookmarkFilterResult({
    required Set<String> sources,
    required this.ascending,
    required this.probePages,
  }) : sources = Set<String>.from(sources);

  final Set<String> sources;
  final bool ascending;
  final int probePages;
}

class _BookmarkList extends StatelessWidget {
  const _BookmarkList();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SearchBookmarkCubit, SearchBookmarkState>(
      builder: (context, state) {
        switch (state.status) {
          case SearchBookmarkStatus.initial:
          case SearchBookmarkStatus.loading:
            return const Center(child: CalmLoading());
          case SearchBookmarkStatus.failure:
            return ErrorView(
              errorMessage: state.result,
              onRetry: () => context.read<SearchBookmarkCubit>().loadAll(),
            );
          case SearchBookmarkStatus.success:
            final visible = state.visibleItems;
            if (visible.isEmpty) {
              return _BookmarkEmptyView(filtered: state.items.isNotEmpty);
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
              itemCount: visible.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final item = visible[index];
                return _BookmarkRow(key: ValueKey(item.uniqueKey), item: item);
              },
            );
        }
      },
    );
  }
}

/// 空态：无书签 vs 筛选无结果两种文案。
class _BookmarkEmptyView extends StatelessWidget {
  const _BookmarkEmptyView({required this.filtered});

  final bool filtered;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: CalmEmptyState(
          icon: filtered
              ? Icons.filter_alt_off_rounded
              : Icons.bookmark_border_rounded,
          title: filtered
              ? t.searchBookmark.filteredEmpty
              : t.searchBookmark.empty,
          subtitle: filtered
              ? t.searchBookmark.filteredEmptyHint
              : t.searchBookmark.emptyHint,
        ),
      ),
    );
  }
}

/// 行首插件名徽章：独立订阅避免整表重建（行在 ListView builder 里）。
class _BookmarkSourceBadge extends StatelessWidget {
  const _BookmarkSourceBadge({required this.source});

  final String source;

  @override
  Widget build(BuildContext context) {
    return BlocSelector<PluginRegistryCubit, PluginRegistryState, String>(
      selector: (registry) => registry.pluginName(source),
      builder: (context, pluginLabel) {
        final label = pluginLabel.trim().isNotEmpty ? pluginLabel : source;
        return Align(
          alignment: Alignment.centerLeft,
          child: CalmBadge(
            label: label,
            icon: Icons.source_rounded,
            tone: CalmBadgeTone.neutral,
          ),
        );
      },
    );
  }
}

class _BookmarkRow extends StatelessWidget {
  const _BookmarkRow({super.key, required this.item});

  final SearchBookmark item;

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    final cover = _resolveBookmarkCover(item);
    final timeText = DateFormat('yyyy-MM-dd HH:mm:ss')
        .format(item.createdAt.toLocal());
    final anchorTitle = item.anchorTitle.trim();

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _jump(context),
      child: CalmCard(
        padding: EdgeInsets.zero,
        radius: 16,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(11),
                child: CoverWidget(
                  fileServer: cover.url,
                  path: cover.cachePath,
                  id: item.anchorComicId,
                  pictureType: PictureType.cover,
                  from: item.source,
                  roundedCorner: false,
                  width: _bookmarkCoverWidth,
                  height: _bookmarkCoverHeight,
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(2, 10, 2, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _BookmarkSourceBadge(source: item.source),
                    const SizedBox(height: 4),
                    Text(
                      item.keyword,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: c.text3),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      anchorTitle.isEmpty ? item.anchorComicId : anchorTitle,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: c.text,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      timeText,
                      textHeightBehavior: kCalmTextHeightBehavior,
                      strutStyle: calmStrut(10.5),
                      style: TextStyle(
                        fontSize: 10.5,
                        color: c.text3,
                        height: 1.2,
                        leadingDistribution: TextLeadingDistribution.even,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8, right: 8),
              child: CalmIconButton(
                icon: Icons.delete_outline_rounded,
                tooltip: t.common.delete,
                size: 30,
                iconSize: 15,
                onPressed: () => _confirmDelete(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final anchorTitle = item.anchorTitle.trim();
    final confirmed = await showCalmDialog<bool>(
      context,
      title: t.common.delete,
      subtitle: anchorTitle.isEmpty ? item.anchorComicId : anchorTitle,
      icon: Icons.delete_outline_rounded,
      tone: CalmTone.danger,
      bodyBuilder: (_) => Text(
        '${t.common.delete}？',
        style: TextStyle(fontSize: 12, color: context.calm.text2, height: 1.5),
      ),
      actionsBuilder: (ctx) => [
        CalmButton(
          label: t.common.cancel,
          variant: CalmButtonVariant.ghost,
          onPressed: () => Navigator.of(ctx).pop(false),
        ),
        CalmButton(
          label: t.common.delete,
          variant: CalmButtonVariant.danger,
          onPressed: () => Navigator.of(ctx).pop(true),
        ),
      ],
    );
    if (confirmed != true || !context.mounted) {
      return;
    }
    await context.read<SearchBookmarkCubit>().remove(item);
    if (context.mounted) {
      showSuccessToast(t.searchBookmark.deleted);
    }
  }

  void _jump(BuildContext context) {
    // 书签跳转回放：这一次请求带 isSearchAggregate=true，插件直抓
    // extern 里记下的 currentUrl；成功后 bloc 复位，后续翻页走正常逻辑。
    final newStates = SearchStates.initial().copyWith(
      from: item.source,
      searchKeyword: item.keyword,
      pluginExtern: Map<String, dynamic>.from(item.extern),
      isSearchAggregate: true,
    );
    final page = item.anchorPage < 1 ? 1 : item.anchorPage;
    SearchBookmarkReveal.request(item);
    showSuccessToast(t.searchBookmark.jumped(page: page));
    context.pushRoute(
      SearchResultRoute(
        searchEvent: SearchEvent().copyWith(
          searchStates: newStates,
          page: page,
        ),
      ),
    );
  }
}
