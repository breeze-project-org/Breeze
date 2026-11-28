import 'package:auto_route/auto_route.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/comic_list/cubit/comic_list_cubit.dart';
import 'package:zephyr/page/comic_list/models/comic_list_scene.dart';
import 'package:zephyr/page/comic_list/scene_filter/plugin_list_filter_dialog.dart';
import 'package:zephyr/page/comic_list/view/plugin_paged_comic_list_view.dart';
import 'package:zephyr/ui/ui.dart';
import 'package:zephyr/widgets/error_view.dart';

@RoutePage()
class ComicListPage extends StatelessWidget {
  const ComicListPage({
    super.key,
    this.title,
    this.scene,
    this.sceneSource,
    this.sceneBundleFnPath,
    this.sceneBundleFnPathFallback,
  });

  final String? title;
  final ComicListScene? scene;
  final String? sceneSource;
  final String? sceneBundleFnPath;
  final String? sceneBundleFnPathFallback;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => ComicListCubit(
        initialScene: scene,
        sceneSource: sceneSource,
        sceneBundleFnPath: sceneBundleFnPath,
        sceneBundleFnPathFallback: sceneBundleFnPathFallback,
      ),
      child: _ComicListView(title: title),
    );
  }
}

class _ComicListView extends StatefulWidget {
  const _ComicListView({this.title});

  final String? title;

  @override
  State<_ComicListView> createState() => _ComicListViewState();
}

class _ComicListViewState extends State<_ComicListView>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return BlocBuilder<ComicListCubit, ComicListState>(
      builder: (context, state) {
        final pageTitle =
            widget.title ?? (state.scene?.title ?? t.comicList.defaultTitle);

        return CalmPageScaffold(
          title: pageTitle,
          // 漫画宫格需要占满整行（桌面端也铺满），限宽交给宫格自身的断点。
          maxContentWidth: null,
          actions: [
            if (state.requiresFilter)
              CalmIconButton(
                icon: Icons.tune_rounded,
                tooltip: t.comicList.filter,
                selected: _hasActiveFilter(state),
                onPressed: () => _openFilterDialog(context),
              ),
          ],
          body: _buildBody(context, state),
        );
      },
    );
  }

  /// 当前筛选是否偏离插件给的默认值（用于顶栏筛选入口的激活态）。
  bool _hasActiveFilter(ComicListState state) {
    final bundle = state.filterBundle;
    if (bundle == null || state.filterSelections.isEmpty) {
      return false;
    }
    final defaults = bundle.defaultSelections;
    for (final entry in state.filterSelections.entries) {
      if (defaults[entry.key] != entry.value) {
        return true;
      }
    }
    return false;
  }

  Widget _buildBody(BuildContext context, ComicListState state) {
    final currentFrom = state.currentFrom;

    if (currentFrom.isEmpty) {
      return _centered(
        CalmEmptyState(
          icon: Icons.extension_off_rounded,
          title: t.comicList.missingSource,
        ),
      );
    }

    if (state.sceneLoading) {
      return const Center(child: CalmLoading(size: 22));
    }

    if (state.sceneError != null) {
      return _centered(
        ErrorView(
          errorMessage: state.sceneError!,
          loginPluginId: state.sceneLoginPluginId,
          onRetry: () => context.read<ComicListCubit>().reload(),
        ),
      );
    }

    if (state.requiresFilter &&
        state.filterLoading &&
        !state.hasResolvedFilter) {
      return const Center(child: CalmLoading(size: 22));
    }

    if (state.requiresFilter &&
        state.filterError != null &&
        !state.hasResolvedFilter) {
      return _centered(
        ErrorView(
          errorMessage: state.filterError!,
          loginPluginId: state.filterLoginPluginId,
          onRetry: () => context.read<ComicListCubit>().loadFilter(),
        ),
      );
    }

    final scene = state.scene;
    if (scene != null) {
      return _buildSceneBody(state, scene);
    }

    return _centered(
      CalmEmptyState(icon: Icons.inbox_rounded, title: t.comicList.nothingHere),
    );
  }

  Widget _centered(Widget child) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(padding: const EdgeInsets.all(16), child: child),
      ),
    );
  }

  Widget _buildSceneBody(ComicListState state, ComicListScene scene) {
    final request = scene.body.request!;
    final filterCore = state.resolvedFilterCore;
    final filterExtern = state.resolvedFilterExtern;
    final listCore = <String, dynamic>{...request.core, ...filterCore};
    final listExtern = <String, dynamic>{...request.extern, ...filterExtern};
    final collectionTargetId = _resolveCollectionTargetId(
      request: request,
      core: listCore,
      extern: listExtern,
    );

    return PluginPagedComicListView(
      key: ValueKey('${request.fnPath}_${listCore}_$listExtern'),
      pluginId: state.currentFrom,
      fnPath: request.fnPath,
      coreBuilder: (page) => {'page': page, ...listCore},
      externBuilder: (_) => listExtern,
      collectionTargetId: collectionTargetId,
      detailed: context
          .watch<GlobalSettingCubit>()
          .state
          .bookshelfSetting
          .detailLayout,
    );
  }

  String? _resolveCollectionTargetId({
    required ComicListRequestConfig request,
    required Map<String, dynamic> core,
    required Map<String, dynamic> extern,
  }) {
    final isCloudFavoriteScene =
        request.fnPath == 'getCloudFavoriteData' ||
        extern['source']?.toString() == 'cloudFavorite';
    if (!isCloudFavoriteScene) {
      return null;
    }
    final targetId = core['folderId'] ?? extern['folderId'];
    final normalized = targetId?.toString().trim() ?? '';
    return normalized.isEmpty ? null : normalized;
  }

  Future<void> _openFilterDialog(BuildContext context) async {
    final cubit = context.read<ComicListCubit>();

    if (!cubit.state.hasResolvedFilter) {
      await cubit.loadFilter();
    }

    final bundle = cubit.state.filterBundle;
    if (!context.mounted || bundle == null) {
      return;
    }

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => PluginListFilterDialog(
        scheme: bundle.scheme,
        initialSelections: cubit.state.filterSelections.isNotEmpty
            ? cubit.state.filterSelections
            : bundle.defaultSelections,
      ),
    );

    if (result == null || !context.mounted) {
      return;
    }

    cubit.applyFilterSelections(result);
  }
}
