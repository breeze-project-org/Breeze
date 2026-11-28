import 'dart:async';
import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_sticky_header/flutter_sticky_header.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:zephyr/util/ohos/platform.dart';
import 'package:zephyr/util/ohos/file_bridge.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/config/router/router.dart';
import 'package:zephyr/config/router/router.gr.dart' show ComicEditRoute;
import 'package:zephyr/cubit/string_select.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/page/comic_follow/cubit/comic_follow_cubit.dart';
import 'package:zephyr/page/comic_edit/method/comic_edit_service.dart';
import 'package:zephyr/page/comic_info/comic_info.dart';
import 'package:zephyr/page/comic_info/json/normal/normal_comic_all_info.dart';
import 'package:zephyr/page/download/models/download_chapter.dart';
import 'package:zephyr/service/reader/comic_read_chapter_repository.dart';
import 'package:zephyr/type/enum.dart';
import 'package:zephyr/type/pipe.dart';
import 'package:zephyr/ui/ui.dart';
import 'package:zephyr/util/error/error_filter.dart';
import 'package:zephyr/util/storage/get_path.dart';
import 'package:zephyr/util/json/json_value.dart';
import 'package:zephyr/util/system/permission.dart';
import 'package:zephyr/util/text/chinese_convert.dart';
import 'package:zephyr/widgets/comic_entry/models/models.dart';
import 'package:zephyr/widgets/error_view.dart';
import 'package:zephyr/widgets/toast.dart';

enum MenuOption { export, follow, edit }

@RoutePage()
class ComicInfoPage extends StatelessWidget {
  final String comicId;
  final String from;
  final ComicEntryType type;
  final Map<String, dynamic>? extern;
  final String? collectionTargetId;
  final String? collectionTargetName;

  const ComicInfoPage({
    super.key,
    required this.comicId,
    required this.from,
    required this.type,
    this.extern,
    this.collectionTargetId,
    this.collectionTargetName,
  });

  @override
  Widget build(BuildContext context) {
    final resolvedFrom = from.trim();
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => StringSelectCubit()),
        BlocProvider(
          create: (context) =>
              GetComicInfoBloc(context.read<StringSelectCubit>())..add(
                GetComicInfoEvent(
                  comicId: comicId,
                  from: resolvedFrom,
                  type: type,
                  extern: extern,
                ),
              ),
        ),
      ],
      child: _ComicInfo(
        comicId: comicId,
        type: type,
        from: resolvedFrom,
        extern: extern,
        collectionTargetId: collectionTargetId,
        collectionTargetName: collectionTargetName,
      ),
    );
  }
}

class _ComicInfo extends StatefulWidget {
  final String comicId;
  final ComicEntryType type;
  final String from;
  final Map<String, dynamic>? extern;
  final String? collectionTargetId;
  final String? collectionTargetName;

  const _ComicInfo({
    required this.comicId,
    required this.type,
    required this.from,
    this.extern,
    this.collectionTargetId,
    this.collectionTargetName,
  });

  @override
  _ComicInfoState createState() => _ComicInfoState();
}

class _ComicInfoState extends State<_ComicInfo>
    with AutomaticKeepAliveClientMixin {
  ComicEntryType get type => widget.type;

  @override
  bool get wantKeepAlive => true;

  dynamic comicInfoDyn;
  late ComicEntryType _type;
  late String _comicId;
  bool _loadingComplete = false;
  bool _isReversed = false;
  String _title = "";
  late final EpisodeDownloadController _dlController =
      EpisodeDownloadController();
  // 已折叠的章节组（存组标题 key）。默认全展开；漫画切换时清空。
  final Set<String> _collapsedGroups = {};
  String _collapsedForComic = '';
  NormalComicAllInfo? _currentInfo;
  // 已读章节 id 集合：与当前漫画绑定，首次由详情 bloc 随详情返回；
  // 阅读器写库后经 repository 变更流刷新。
  Set<String> _readChapterIds = const {};
  StreamSubscription<String>? _readChapterSubscription;
  // 追更线上总数同步护栏：记住已同步到的章节数。数字变大才再同步一次，
  // 下拉刷新后长出的新话不会被吞；下载入口的 comicInfoDyn 是本地快照
  // （已下载数），不能当线上总数写——只在 PluginComicDetailSource 时同步。
  final Map<String, int> _followSyncedCounts = {};

  // 章节显示顺序缓存：raw 列表实例不变且倒序开关不变时直接复用，
  // 避免每次 build 都 sort + reversed.toList()。
  // 非倒序时 display 与 sorted 同引用，零拷贝。
  List<dynamic>? _epsRawRef;
  List<dynamic> _sortedEps = const [];
  List<dynamic> _displayEps = const [];
  bool _displayEpsReversed = false;
  bool _displayEpsValid = false;

  // 章节分组缓存：displayEps 同引用时直接复用，避免每次 build 都
  // List.generate(N) + N 次 trim + Map 查找。倒序切换会换 displayEps
  // 引用（见 _resolveDisplayEps），自然 miss 重算。
  List<dynamic>? _groupedEpsRef;
  List<ChapterGroup<int>> _indexGroups = const [];

  List<dynamic> _resolveDisplayEps(List<dynamic> rawEps) {
    if (!identical(rawEps, _epsRawRef)) {
      _epsRawRef = rawEps;
      _sortedEps = sortChaptersByOrder(
        List<dynamic>.from(rawEps),
        (e) => (e as Ep).order,
      );
      _displayEpsValid = false;
    }
    if (!_displayEpsValid || _displayEpsReversed != _isReversed) {
      _displayEps = _isReversed ? _sortedEps.reversed.toList() : _sortedEps;
      _displayEpsReversed = _isReversed;
      _displayEpsValid = true;
    }
    return _displayEps;
  }

  @override
  void initState() {
    super.initState();
    _type = type;
    _comicId = widget.comicId;
    _isReversed = context
        .read<GlobalSettingCubit>()
        .state
        .bookshelfSetting
        .reverseChapters;
    _readChapterSubscription = ComicReadChapterRepository.instance.changes
        .listen(_onReadChaptersChanged);
  }

  @override
  void dispose() {
    _readChapterSubscription?.cancel();
    _dlController.dispose();
    super.dispose();
  }

  String get _readChapterComicKey => '${widget.from.trim()}:${_comicId.trim()}';

  void _onReadChaptersChanged(String comicKey) {
    if (!mounted) return;
    if (comicKey != _readChapterComicKey) return;
    _reloadReadChapters();
  }

  Future<void> _reloadReadChapters() async {
    final key = _readChapterComicKey;
    final ids = await ComicReadChapterRepository.instance.readChapterIds(
      source: widget.from,
      comicId: _comicId,
    );
    if (!mounted || key != _readChapterComicKey) return;
    setState(() {
      _readChapterIds = ids;
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final c = context.calm;
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildTopBar(context),
            Expanded(
              child: Stack(
                children: [
                  BlocBuilder<GetComicInfoBloc, GetComicInfoState>(
                    builder: (context, state) {
                      switch (state.status) {
                        case GetComicInfoStatus.initial:
                          return const Center(child: CalmLoading());
                        case GetComicInfoStatus.failure:
                          if (state.result.contains("under review") &&
                              state.result.contains("1014")) {
                            return Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 420,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                  ),
                                  child: CalmEmptyState(
                                    icon: Icons.block_rounded,
                                    title: t.comicInfo.discontinued,
                                    subtitle: state.result.toString(),
                                    action: CalmButton(
                                      label: t.comicInfo.back,
                                      icon: Icons.arrow_back_rounded,
                                      variant: CalmButtonVariant.tonal,
                                      onPressed: () => context.pop(),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }
                          return ErrorView(
                            errorMessage: t.comicInfo.loadFailedWithError(
                              error: state.result.toString(),
                            ),
                            onRetry: () {
                              context.read<GetComicInfoBloc>().add(
                                GetComicInfoEvent(
                                  comicId: _comicId,
                                  from: widget.from,
                                  type: _type,
                                  extern: widget.extern,
                                ),
                              );
                            },
                          );
                        case GetComicInfoStatus.success:
                          comicInfoDyn = state.comicInfo;
                          _currentInfo = state.allInfo;
                          _comicId = state.comicId ?? _comicId;
                          // 已读集合与历史摘要随详情返回；这里只同步，不再异步查库。
                          _readChapterIds = state.readChapterIds;
                          _syncFollowFromOnlineDetail(
                            state.comicInfo,
                            state.allInfo!,
                          );
                          return _infoView(
                            state.allInfo!,
                            state.localCollected,
                          );
                      }
                    },
                  ),
                  BlocBuilder<
                    EpisodeDownloadStatusCubit,
                    EpisodeDownloadStatusState
                  >(
                    bloc: _dlController.statusCubit,
                    builder: (context, _) =>
                        BlocBuilder<EpisodeSelectionCubit, int>(
                          bloc: _dlController.selectionCubit,
                          builder: (context, _) => _SelectionActionBar(
                            controller: _dlController,
                            isDownloadType: _type == ComicEntryType.download,
                          ),
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButtonLocation:
          context.watch<GlobalSettingCubit>().state.leftHandModeEnabled
          ? FloatingActionButtonLocation.startFloat
          : FloatingActionButtonLocation.endFloat,
      floatingActionButton: BlocBuilder<EpisodeSelectionCubit, int>(
        bloc: _dlController.selectionCubit,
        builder: (context, _) {
          if (_dlController.selectionMode) {
            return const SizedBox.shrink();
          }
          return _loadingComplete
              ? BlocBuilder<StringSelectCubit, String>(
                  builder: (context, stringSelectDate) {
                    return _ReadActionButton(
                      hasHistory: stringSelectDate.isNotEmpty,
                      onPressed: () => goToComicRead(
                        context,
                        _comicId,
                        widget.type,
                        comicInfoDyn,
                        widget.from,
                      ),
                    );
                  },
                )
              : const SizedBox.shrink();
        },
      ),
    );
  }

  /// 轻盈顶栏：返回 / 回首页 / 追更 / 更多菜单，黑边框与阴影全部去掉。
  Widget _buildTopBar(BuildContext context) {
    final c = context.calm;
    return CalmAppBar(
      title: _title,
      onBack: () => context.pop(),
      actions: [
        CalmIconButton(
          icon: Icons.home_rounded,
          tooltip: t.navigation.home,
          size: 32,
          iconSize: 17,
          onPressed: () => popToRoot(context),
        ),
        BlocSelector<ComicFollowCubit, ComicFollowState, bool>(
          selector: (state) => state.isFollowing(widget.from, _comicId),
          builder: (context, isFollowing) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CalmIconButton(
                  icon: isFollowing
                      ? Icons.notifications_active_rounded
                      : Icons.notifications_none_rounded,
                  tooltip: isFollowing
                      ? t.comicInfo.unfollow
                      : t.comicInfo.follow,
                  selected: isFollowing,
                  size: 32,
                  iconSize: 17,
                  onPressed: () => _toggleFollow(isFollowing),
                ),
                const SizedBox(width: 6),
                CalmPopupMenuButton<MenuOption>(
                  onSelected: (MenuOption item) {
                    switch (item) {
                      case MenuOption.export:
                        _handleExport();
                        break;
                      case MenuOption.edit:
                        _handleEdit();
                        break;
                      case MenuOption.follow:
                        _toggleFollow(isFollowing);
                        break;
                    }
                  },
                  entries: _buildMenuEntries(isFollowing),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: c.surface2,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.more_horiz_rounded,
                      size: 17,
                      color: c.text2,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  List<CalmPopupMenuEntry<MenuOption>> _buildMenuEntries(bool isFollowing) {
    return [
      CalmPopupMenuEntry<MenuOption>.item(
        value: MenuOption.follow,
        label: isFollowing ? t.comicInfo.unfollow : t.comicInfo.follow,
        icon: isFollowing
            ? Icons.notifications_off_rounded
            : Icons.notifications_active_rounded,
      ),
      if (_type == ComicEntryType.download) ...[
        CalmPopupMenuEntry<MenuOption>.item(
          value: MenuOption.edit,
          label: t.comicEdit.title,
          icon: Icons.edit_outlined,
        ),
        CalmPopupMenuEntry<MenuOption>.item(
          value: MenuOption.export,
          label: t.comicInfo.exportComic,
          icon: Icons.save_alt_rounded,
        ),
      ],
    ];
  }

  Widget _infoView(NormalComicAllInfo normalComicAllInfo, bool localCollected) {
    final comicInfo = normalComicAllInfo.comicInfo;
    _title = comicInfo.title;
    final globalSetting = context.watch<GlobalSettingCubit>().state;
    final clickCoverToStartReading = globalSetting.clickCoverToStartReading;
    final showOperationActions =
        globalSetting.comicDetailSetting.hasVisibleActions;

    if (!_loadingComplete) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => setState(() => _loadingComplete = true),
      );
    }

    // 带缓存：bloc 同实例 + 倒序开关不变时零计算，直接复用上次结果。
    final displayEps = _resolveDisplayEps(normalComicAllInfo.eps);
    // 下载类型进来的一定是本地记录（只含已下载章节）；在线页插件允许下载时
    // 才显示章节下载按钮。
    final showDownloadUi =
        normalComicAllInfo.allowDownload || _type == ComicEntryType.download;
    // controller 绑定（key 不变时内部早退，零成本）；漫画切换时清空折叠态。
    _dlController.attach(
      from: widget.from,
      comicId: _comicId,
      comicTitle: comicInfo.title,
      allowDownload: showDownloadUi,
    );
    final comicKey = '${widget.from}:$_comicId';
    if (_collapsedForComic != comicKey) {
      _collapsedForComic = comicKey;
      _collapsedGroups.clear();
    }
    final previewCapability = ComicPreviewCapability.fromInfo(
      normalComicAllInfo,
    );
    final showPreview =
        _type != ComicEntryType.download && previewCapability.enabled;

    return BlocSelector<StringSelectCubit, String, bool>(
      selector: (state) => state.isNotEmpty,
      builder: (context, hasHistory) {
        final refreshable = RefreshIndicator(
          onRefresh: () async {
            _type = ComicEntryType.normal;
            _isReversed = context
                .read<GlobalSettingCubit>()
                .state
                .bookshelfSetting
                .reverseChapters;

            context.read<GetComicInfoBloc>().add(
              GetComicInfoEvent(
                comicId: _comicId,
                from: widget.from,
                type: _type,
                extern: widget.extern,
              ),
            );
            setState(() {
              _loadingComplete = false;
            });
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.only(top: 8),
                sliver: _constrainedSliver(
                  SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ComicParticularsWidget(
                          comicInfo: comicInfo,
                          from: widget.from,
                          type: _type,
                          onCoverTap: clickCoverToStartReading
                              ? () => goToComicRead(
                                  context,
                                  _comicId,
                                  _type,
                                  comicInfoDyn,
                                  widget.from,
                                )
                              : null,
                          onContinueRead: hasHistory
                              ? () => goToComicRead(
                                  context,
                                  _comicId,
                                  _type,
                                  comicInfoDyn,
                                  widget.from,
                                )
                              : null,
                        ),
                        if (showOperationActions) ...[
                          _buildDivider(),
                          ComicOperationWidget(
                            normalInfo: normalComicAllInfo,
                            from: widget.from,
                            collectionTargetId: widget.collectionTargetId,
                            collectionTargetName: widget.collectionTargetName,
                            comicInfo: comicInfoDyn,
                            initialCollected: localCollected,
                          ),
                        ],
                        if (comicInfo.metadata.isNotEmpty ||
                            comicInfo.description.trim().isNotEmpty) ...[
                          _buildDivider(),
                          _SectionCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                for (final meta in comicInfo.metadata) ...[
                                  AllChipWidget(
                                    comicId: comicInfo.id,
                                    metadata: meta,
                                    from: widget.from,
                                  ),
                                  const SizedBox(height: 6),
                                ],
                                if (comicInfo.description.trim().isNotEmpty)
                                  _DescriptionCard(
                                    description: comicInfo.description.let(
                                      convertChineseForDisplay,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                        if (comicInfo.creator.name.trim().isNotEmpty ||
                            comicInfo.creator.avatar.url.trim().isNotEmpty) ...[
                          _buildDivider(),
                          _SectionCard(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 460,
                                ),
                                child: CreatorInfoWidget(
                                  creator: comicInfo.creator,
                                  from: widget.from,
                                  imageKey: comicInfo.id,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              // 章节头：标题 + 计数/倒序 badge（虚拟化列表的 header sliver）。
              _constrainedSliver(
                SliverToBoxAdapter(
                  child: Column(
                    children: [
                      _buildDivider(),
                      _EpisodeHeader(
                        title: t.comicInfo.chapterList,
                        countText: _chapterCountLabel(displayEps),
                        icon: _isReversed
                            ? Icons.south_rounded
                            : Icons.north_rounded,
                        onToggleOrder: _toggleOrder,
                      ),
                    ],
                  ),
                ),
              ),
              // 章节列表：单组走扁平 Sliver，多组直接展开为多个顶层 sliver
              // （组头 pinned + 组内容），后组吸顶时自然顶掉前组。
              ..._buildEpisodeSlivers(
                context: context,
                displayEps: displayEps,
                showDownloadUi: showDownloadUi,
                allInfo: comicInfoDyn,
                epsLength: normalComicAllInfo.eps.length,
                downloadDisabledReason: normalComicAllInfo.allowDownloadReason,
              ),
              if (normalComicAllInfo.recommend.isNotEmpty &&
                  _resolveRecommendItems(normalComicAllInfo.recommend)
                      .isNotEmpty)
                _constrainedSliver(
                  SliverToBoxAdapter(
                    child: Column(
                      children: [
                        _buildDivider(),
                        _SectionCard(
                          title: t.comicInfo.related,
                          child: RecommendWidget(
                            comicList: _resolveRecommendItems(
                              normalComicAllInfo.recommend,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (showPreview) ...[
                _constrainedSliver(const ComicPreviewSliver()),
              ],
              const SliverPadding(
                padding: EdgeInsets.only(bottom: 180),
                sliver: SliverToBoxAdapter(child: SizedBox.shrink()),
              ),
            ],
          ),
        );

        if (!showPreview) return refreshable;

        return BlocProvider(
          key: ValueKey('preview:${widget.from}:$_comicId'),
          create: (_) => ComicPreviewBloc(
            comicId: _comicId,
            from: widget.from,
            capability: previewCapability,
            extern: widget.extern ?? const <String, dynamic>{},
          )..add(const LoadComicPreview()),
          child: Builder(
            builder: (context) => NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification.metrics.pixels >=
                    notification.metrics.maxScrollExtent * 0.9) {
                  context.read<ComicPreviewBloc>().add(
                    const LoadComicPreview(loadMore: true),
                  );
                }
                return false;
              },
              child: refreshable,
            ),
          ),
        );
      },
    );
  }

  Widget _constrainedSliver(Widget sliver) {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final horizontalPadding = _constrainedHorizontalPadding(
          constraints.crossAxisExtent,
        );
        return SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          sliver: sliver,
        );
      },
    );
  }

  Widget _buildDivider() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 10),
      child: CalmDivider(),
    );
  }

  String _buildZipFileName() {
    final rawName = _title.trim().isEmpty ? _comicId : _title.trim();
    final safeName = rawName.replaceAll(RegExp(r'[<>:"/\\|?* ]'), '_');
    return '$safeName.zip';
  }

  Future<ExportType?> _pickExportType() async {
    if (Platform.isIOS || isOhos) return ExportType.zip;

    return showCalmDialog<ExportType>(
      context,
      title: t.comicInfo.exportTitle,
      subtitle: t.comicInfo.exportSubtitle,
      icon: Icons.save_alt_rounded,
      actionsBuilder: (dialogContext) => [
        CalmButton(
          label: t.common.cancel,
          variant: CalmButtonVariant.ghost,
          onPressed: () => Navigator.of(dialogContext).pop(),
        ),
        CalmButton(
          label: t.comicInfo.folder,
          icon: Icons.folder_outlined,
          variant: CalmButtonVariant.tonal,
          onPressed: () => Navigator.of(dialogContext).pop(ExportType.folder),
        ),
        CalmButton(
          label: t.comicInfo.zip,
          icon: Icons.folder_zip_outlined,
          variant: CalmButtonVariant.primary,
          onPressed: () => Navigator.of(dialogContext).pop(ExportType.zip),
        ),
      ],
      bodyBuilder: (dialogContext) => const SizedBox.shrink(),
    );
  }

  Future<String?> _pickExportDirectory() async => getDirectoryPath();

  Future<String?> _resolveExportDirectory() async {
    // iOS / OHOS 无可用目录选择器，导出到缓存后再系统保存/分享。
    if (Platform.isIOS || isOhos) {
      return getCachePath();
    }
    final customPath = globalSetting.customExportPath.trim();
    if (customPath.isNotEmpty) {
      return customPath;
    }
    if (Platform.isAndroid) {
      final granted = await requestExportPermission();
      if (!granted) {
        throw StateError(t.comicInfo.exportPermissionDenied);
      }
      return createDownloadDir();
    }
    return _pickExportDirectory();
  }

  void _logExportPath(String path) {
    if (!(Platform.isAndroid ||
        Platform.isMacOS ||
        Platform.isWindows ||
        Platform.isLinux)) {
      return;
    }

    final displayPath = Platform.isAndroid
        ? _simplifyAndroidPathForLog(path)
        : path;
    logger.d('Exported comic path: $displayPath');
  }

  String _simplifyAndroidPathForLog(String path) {
    final normalized = path.replaceAll('\\', '/');
    final downloadIndex = normalized.indexOf('/Download/');
    if (downloadIndex >= 0) {
      return normalized.substring(downloadIndex + 1);
    }
    return normalized;
  }

  void _showExportDirectory(String exportedPath, ExportType exportType) {
    if (!(Platform.isAndroid ||
        Platform.isMacOS ||
        Platform.isWindows ||
        Platform.isLinux)) {
      return;
    }

    final exportDirectory = exportType == ExportType.zip
        ? p.dirname(exportedPath)
        : exportedPath;
    final displayPath = Platform.isAndroid
        ? _simplifyAndroidPathForLog(exportDirectory)
        : exportDirectory;
    showInfoToast(
      t.comicInfo.exportDirectory(displayPath: displayPath),
      duration: const Duration(seconds: 5),
    );
  }

  // 编辑逻辑
  Future<void> _handleEdit() async {
    const service = ComicEditService();
    if (await service.hasIncompleteDownload(widget.from, _comicId)) {
      showErrorToast(t.comicEdit.lockedMessage);
      return;
    }
    if (!mounted) return;

    await context.pushRoute(
      ComicEditRoute(from: widget.from, comicId: _comicId),
    );
    if (!mounted) return;
    context.read<GetComicInfoBloc>().add(
      GetComicInfoEvent(
        comicId: _comicId,
        from: widget.from,
        type: _type,
        extern: widget.extern,
      ),
    );
  }

  // 导出逻辑
  Future<void> _handleExport() async {
    try {
      if (!mounted) return;

      final exportType = await _pickExportType();
      if (exportType == null) return;

      final exportDir = await _resolveExportDirectory();
      if (exportDir == null) return;

      final zipFileName = _buildZipFileName();
      final targetZipPath = p.join(exportDir, zipFileName);

      if (isOhos) {
        final saved = await saveOhosFileToPicker(
          targetZipPath,
          suggestedName: zipFileName,
        );
        if (saved) {
          showSuccessToast(t.comicInfo.exportSuccess);
          try {
            await File(targetZipPath).delete();
          } catch (_) {}
        }
        return;
      }

      if (Platform.isIOS) {
        // 不写入 cacheZipPath：open_file 在分享面板弹出后即返回，
        // finally 里删除会导致用户还没保存文件就被删掉。
        final iosZipPath = targetZipPath;
        final iosZipFile = File(iosZipPath);
        if (await iosZipFile.exists()) {
          await iosZipFile.delete();
        }

        await exportComic(
          _comicId,
          ExportType.zip,
          widget.from,
          path: iosZipPath,
        );

        // 弹出系统分享面板，用户可「存储到文件」
        await openFileWithSystem(iosZipPath);
        showSuccessToast(t.comicInfo.exportSuccess);
        _logExportPath(iosZipPath);
        return;
      }

      final exportPath = exportType == ExportType.zip
          ? targetZipPath
          : exportDir;

      final exportedPath = await exportComic(
        _comicId,
        exportType,
        widget.from,
        path: exportPath,
      );
      _showExportDirectory(exportedPath, exportType);
      _logExportPath(exportedPath);
    } catch (e) {
      logger.e(e);
      final errorMessage = e is StateError
          ? e.message.toString()
          : t.comicInfo.exportFailedWithError(
              error: normalizeSearchErrorMessage(e),
            );
      showErrorToast(errorMessage, duration: const Duration(seconds: 5));
    }
  }

  // 切换章节列表的倒序/正序显示
  void _toggleOrder() => setState(() => _isReversed = !_isReversed);

  /// 章节计数文案：只显示总数 `N 话`。各组明细已在组头上（`组名 · N 话`），
  /// 头部 badge 不再重复，窄屏下省位置。
  String _chapterCountLabel(List<dynamic> displayEps) {
    return t.comicInfo.episodeCount(count: displayEps.length);
  }

  Future<void> _toggleFollow(bool isFollowing) async {
    final info = _currentInfo;
    if (info == null) {
      showErrorToast(t.comicInfo.detailsNotLoaded);
      return;
    }

    if (isFollowing) {
      await _confirmAndRemoveFollow(info.comicInfo.title);
      return;
    }

    await context.read<ComicFollowCubit>().addOrUpdateFollow(
      source: widget.from,
      comicId: _comicId,
      info: info,
      lastChapterCount: info.eps.length,
    );
    if (mounted) {
      showSuccessToast(t.comicInfo.followed);
    }
  }

  Future<void> _confirmAndRemoveFollow(String title) async {
    final confirmed = await showCalmDialog<bool>(
      context,
      title: t.comicInfo.confirmUnfollowTitle,
      icon: Icons.notifications_off_rounded,
      tone: CalmTone.warning,
      bodyBuilder: (dialogContext) => Text(
        t.comicInfo.confirmUnfollowContent(title: title),
        style: TextStyle(
          fontSize: 12.5,
          color: dialogContext.calm.text2,
          height: 1.5,
        ),
      ),
      actionsBuilder: (dialogContext) => [
        CalmButton(
          label: t.common.cancel,
          variant: CalmButtonVariant.ghost,
          onPressed: () => Navigator.of(dialogContext).pop(false),
        ),
        CalmButton(
          label: t.common.ok,
          variant: CalmButtonVariant.danger,
          onPressed: () => Navigator.of(dialogContext).pop(true),
        ),
      ],
    );
    if (confirmed != true) {
      return;
    }
    if (!mounted) {
      return;
    }
    await context.read<ComicFollowCubit>().removeFollow(widget.from, _comicId);
    if (mounted) {
      showSuccessToast(t.comicInfo.unfollowed);
    }
  }

  List<UnifiedComicListItem> _resolveRecommendItems(List<Recommend> recommend) {
    return recommend
        .map((item) {
          // 优先使用 extern 中的 unifiedItem
          final unifiedJson = asJsonMap(item.extern)['unifiedItem'];
          if (unifiedJson != null) return asJsonMap(unifiedJson);

          // 否则从 Recommend 对象构造 JSON
          return item.toJson();
        })
        .where((json) => json.isNotEmpty)
        .map(
          (json) =>
              UnifiedComicListItem.fromJson(json).copyWith(source: widget.from),
        )
        .toList();
  }

  /// 进在线详情即确认：把当前线上总数记为已确认基线并清掉红点。
  ///
  /// 只有 `comicInfo` 是 [PluginComicDetailSource]（在线详情）时才同步：
  /// 下载入口的是本地快照（已下载数），不能当线上总数写。
  void _syncFollowFromOnlineDetail(dynamic comicInfo, NormalComicAllInfo info) {
    if (comicInfo is! PluginComicDetailSource) return;
    final comicId = info.comicInfo.id;
    final eps = comicInfo.eps;
    if (eps.isEmpty) return;
    // 同一数只同步一次；下拉刷新后变大才再同步。
    if ((_followSyncedCounts[comicId] ?? 0) >= eps.length) return;
    _followSyncedCounts[comicId] = eps.length;
    final latest = eps.reduce(
      (left, right) => left.order >= right.order ? left : right,
    );
    context.read<ComicFollowCubit>().syncFollowFromDetailAndPersist(
      source: widget.from,
      comicId: comicId,
      onlineChapterCount: eps.length,
      onlineLatestTitle: latest.name,
    );
  }

  void _toggleGroup(String groupKey) {
    setState(() {
      if (_collapsedGroups.contains(groupKey)) {
        _collapsedGroups.remove(groupKey);
      } else {
        _collapsedGroups.add(groupKey);
      }
    });
  }

  Future<void> _onChapterAction(
    BuildContext context,
    DownloadChapter chapter,
    bool downloadAllowed,
  ) async {
    if (!downloadAllowed) {
      _showDownloadDisabledToast('');
      return;
    }
    final status = _dlController.statusOf(chapter);
    switch (status) {
      case ChapterDownloadStatus.notDownloaded:
      case ChapterDownloadStatus.failed:
        await _dlController.downloadSingle(context, chapter);
        break;
      case ChapterDownloadStatus.queued:
      case ChapterDownloadStatus.downloading:
        await _dlController.cancelChapter(context, chapter);
        break;
      case ChapterDownloadStatus.downloaded:
        final wholeDeleted = await _dlController.deleteSingle(context, chapter);
        if (wholeDeleted && _type == ComicEntryType.download) {
          if (context.mounted) context.pop();
        }
        break;
    }
  }

  // 选中态/下载态不在这里读取，行内各自订阅 selectionCubit / statusCubit。
  // [doc] 与 [chapter] 一一对应（同一下标），[index] 为组内下标，
  // [displayTotal] 为组内总数（扁平路径传 null，即今天的行为）。
  Widget _buildEpisodeRow(
    BuildContext context, {
    required DownloadChapter chapter,
    required Ep doc,
    required int index,
    required int? displayTotal,
    required dynamic allInfo,
    required int epsLength,
    required bool downloadAllowed,
    required String downloadDisabledReason,
  }) {
    return EpButtonWidget(
      key: ValueKey(chapter.id),
      doc: doc,
      chapter: chapter,
      controller: _dlController,
      allInfo: allInfo,
      epsLength: epsLength,
      displayTotal: displayTotal,
      type: _type,
      comicId: _comicId,
      from: widget.from,
      index: index,
      isReversed: _isReversed,
      isRead: _readChapterIds.contains(chapter.id),
      downloadAllowed: downloadAllowed,
      downloadDisabledReason: downloadDisabledReason,
      onAction: () => _onChapterAction(context, chapter, downloadAllowed),
      onToggleSelect: () => _dlController.toggleSelect(chapter.id),
      onEnterSelect: () {
        if (!downloadAllowed) {
          _showDownloadDisabledToast(downloadDisabledReason);
          return;
        }
        _dlController.enterSelection(chapter.id);
      },
    );
  }

  void _showDownloadDisabledToast(String reason) {
    final trimmed = reason.trim();
    showInfoToast(trimmed.isNotEmpty ? trimmed : t.comicInfo.downloadForbidden);
  }

  /// 章节区顶层 slivers：单组走扁平 Sliver，多组直接展开
  /// （组头 pinned + 组内容），后组吸顶时自然顶掉前组。
  ///
  /// 组头/组内容各自包一层 SliverLayoutBuilder 算内容宽度（断点与水平边距），
  /// 与其它区共用 `_constrainedSliver` 逻辑，不再经 `SliverMainAxisGroup` 中转。
  List<Widget> _buildEpisodeSlivers({
    required BuildContext context,
    required List<dynamic> displayEps,
    required bool showDownloadUi,
    required dynamic allInfo,
    required int epsLength,
    required String downloadDisabledReason,
  }) {
    // adapt 带元素级缓存：displayEps 引用不变时直接复用，不重建 DownloadChapter。
    final chapters = _dlController.adaptEps(displayEps);
    if (chapters.isEmpty) {
      return [
        _constrainedSliver(
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: CalmEmptyState(
                icon: Icons.menu_book_outlined,
                title: t.comicInfo.noChapters,
              ),
            ),
          ),
        ),
      ];
    }

    // 多组时按下标切段（displayEps 已全局排序，组顺序=首次出现顺序，
    // 倒序开关翻转的是整条 displayEps，即全局翻转）。
    final indexGroups = _groupDisplayIndices(displayEps);
    // 宽度快照：只与视口宽有关，build 期算一次。SliverConstraints 含
    // scrollOffset——继续用 SliverLayoutBuilder 算宽度会滚动每帧重跑，
    // header 的普通 LayoutBuilder 是 Box 约束不受影响，保留。
    final metrics = EpisodeSliverMetrics.of(MediaQuery.sizeOf(context).width);
    if (indexGroups.length <= 1) {
      return [
        _FlatEpisodeSliver(
          chapters: chapters,
          displayEps: displayEps,
          metrics: metrics,
          rowBuilder: (context, chapter, doc, index) => _buildEpisodeRow(
            context,
            chapter: chapter,
            doc: doc,
            index: index,
            displayTotal: null,
            allInfo: allInfo,
            epsLength: epsLength,
            downloadAllowed: showDownloadUi,
            downloadDisabledReason: downloadDisabledReason,
          ),
        ),
      ];
    }
    final slivers = <Widget>[];
    for (var g = 0; g < indexGroups.length; g++) {
      final indices = indexGroups[g].items;
      final groupKey = indexGroups[g].title;
      final expanded = !_collapsedGroups.contains(groupKey);
      slivers.add(
        // 用 flutter_sticky_header 的 SliverStickyHeader：header 与内容绑在
        // 同一个 render object 里，顶替由库原生处理。注意库不做组间间距，
        // 由本组内容底部统一留 12（见 _GroupEpisodeSliver），组头自身不再加
        // topPadding——header 内部留白会参与吸顶高度，导致顶替错位。
        SliverStickyHeader(
          header: _ChapterGroupHeaderBar(
            horizontalPadding: metrics.horizontalPadding,
            title: chapterGroupDisplayTitle(
              indexGroups[g].title,
              t.comicInfo.untitledGroup,
            ),
            countLabel: t.comicInfo.groupEpisodeCount(count: indices.length),
            // 下载列表点击时才按下标收集，不在每次 build 预分配 O(N) List。
            onDownloadGroup: showDownloadUi
                ? () => _downloadGroup(context, [
                    for (final i in indices) chapters[i],
                  ])
                : null,
            onToggle: () => _toggleGroup(groupKey),
            expanded: expanded,
          ),
          // 折叠组内容传 null：库只留吸顶头，章节行 widget 都不建。
          sliver: expanded
              ? _GroupEpisodeSliver(
                  chapters: chapters,
                  displayEps: displayEps,
                  indices: indices,
                  metrics: metrics,
                  rowBuilder: (context, chapter, doc, index) =>
                      _buildEpisodeRow(
                        context,
                        chapter: chapter,
                        doc: doc,
                        index: index,
                        displayTotal: indices.length,
                        allInfo: allInfo,
                        epsLength: epsLength,
                        downloadAllowed: showDownloadUi,
                        downloadDisabledReason: downloadDisabledReason,
                      ),
                )
              : null,
        ),
      );
    }
    return slivers;
  }

  /// 组头“下载本组”：只下可下载子集（未下载/失败），空则 toast 提示。
  Future<void> _downloadGroup(
    BuildContext context,
    List<DownloadChapter> groupChapters,
  ) {
    return _dlController.downloadChapters(context, groupChapters);
  }

  /// 按下标分组：返回与 displayEps 对齐的下标组（组顺序=首次出现顺序）。
  ///
  /// 带引用缓存：displayEps 同引用时直接复用上次切段。下载进度 tick、
  /// 选中态等触发的父 build 不再跑 `List.generate(N) + N 次 trim`。
  /// 倒序切换/刷新会换 displayEps 引用，自然 miss 重算。
  List<ChapterGroup<int>> _groupDisplayIndices(List<dynamic> displayEps) {
    final cachedRef = _groupedEpsRef;
    if (identical(displayEps, cachedRef)) return _indexGroups;
    final groups = groupIndicesByTitle(
      displayEps.length,
      (i) => resolveChapterGroupTitle(
        groupTitle: (displayEps[i] as Ep).groupTitle,
      ),
    );
    _groupedEpsRef = displayEps;
    _indexGroups = groups;
    return groups;
  }
}

/// 章节网格断点（按内容宽度算）：<560 单列，<720 一列、<960 两列，
/// ≥960 按 320 maxExtent 网格。与今天扁平路径同一份规则。
SliverGridDelegate episodeGridDelegateFor(double contentWidth) {
  if (contentWidth >= 960) {
    return const SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: 320,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      mainAxisExtent: EpButtonWidget.fixedHeight,
    );
  }
  return SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: contentWidth >= 720 ? 2 : 1,
    mainAxisSpacing: 12,
    crossAxisSpacing: 12,
    mainAxisExtent: EpButtonWidget.fixedHeight,
  );
}

typedef EpisodeRowBuilder = Widget Function(
  BuildContext context,
  DownloadChapter chapter,
  Ep doc,
  int index,
);

/// 扁平章节 sliver（单组/老数据）：宽度由外层快照传入，只建可视行。
class _FlatEpisodeSliver extends StatelessWidget {
  const _FlatEpisodeSliver({
    required this.chapters,
    required this.displayEps,
    required this.rowBuilder,
    required this.metrics,
  });

  final List<DownloadChapter> chapters;
  final List<dynamic> displayEps;
  final EpisodeRowBuilder rowBuilder;

  /// 外层一次算好的宽度/边距：SliverLayoutBuilder 的 builder 含 scrollOffset，
  /// 滚动每帧重跑；这里直接复用，不再参与滚动重建。
  final EpisodeSliverMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final padding = EdgeInsets.only(
      left: metrics.horizontalPadding,
      right: metrics.horizontalPadding,
      top: 12,
      bottom: 12,
    );
    if (metrics.singleColumn) {
      return SliverPadding(
        padding: padding,
        sliver: SliverList.builder(
          itemCount: chapters.length,
          itemBuilder: (context, i) {
            final chapter = chapters[i];
            return Padding(
              key: ValueKey('pad:${chapter.id}'),
              padding: const EdgeInsets.only(bottom: 10),
              child: rowBuilder(context, chapter, displayEps[i] as Ep, i),
            );
          },
        ),
      );
    }
    return SliverPadding(
      padding: padding,
      sliver: SliverGrid.builder(
        itemCount: chapters.length,
        gridDelegate: metrics.gridDelegate!,
        itemBuilder: (context, i) =>
            rowBuilder(context, chapters[i], displayEps[i] as Ep, i),
      ),
    );
  }
}

/// 章节区宽度快照：build 时按视口宽算一次，滚动路径不再重算。
///
/// SliverConstraints 含 scrollOffset，SliverLayoutBuilder.builder 滚动每帧
/// 重跑（constraints != 上次必然 rebuild）。而宽度只与 crossAxisExtent 有关，
/// CustomScrollView 里它等于视口宽（除旋转/分屏外不变），这里用 MediaQuery
/// 在 build 期快照，彻底脱离滚动 layout 回调。
class EpisodeSliverMetrics {
  const EpisodeSliverMetrics({
    required this.horizontalPadding,
    required this.singleColumn,
    required this.gridDelegate,
  });

  factory EpisodeSliverMetrics.of(double viewportWidth) {
    final horizontalPadding = _constrainedHorizontalPadding(viewportWidth);
    final contentWidth = viewportWidth - horizontalPadding * 2;
    return EpisodeSliverMetrics(
      horizontalPadding: horizontalPadding,
      singleColumn: contentWidth < 560,
      gridDelegate: contentWidth < 560
          ? null
          : episodeGridDelegateFor(contentWidth),
    );
  }

  final double horizontalPadding;
  final bool singleColumn;
  final SliverGridDelegate? gridDelegate;
}

/// 单组章节 sliver：宽度由外层快照传入，无外层边距（组头已占位）。
class _GroupEpisodeSliver extends StatelessWidget {
  const _GroupEpisodeSliver({
    required this.chapters,
    required this.displayEps,
    required this.indices,
    required this.rowBuilder,
    required this.metrics,
  });

  final List<DownloadChapter> chapters;
  final List<dynamic> displayEps;
  final List<int> indices;
  final EpisodeRowBuilder rowBuilder;
  final EpisodeSliverMetrics metrics;

  @override
  Widget build(BuildContext context) {
    // 组内容左右对齐组头：组头包了同样的水平 padding；
    // 底部留 12 与下组头呼应。
    final padding = EdgeInsets.only(
      left: metrics.horizontalPadding,
      right: metrics.horizontalPadding,
      bottom: 12,
    );
    if (metrics.singleColumn) {
      return SliverPadding(
        padding: padding,
        sliver: SliverList.builder(
          itemCount: indices.length,
          itemBuilder: (context, j) {
            final i = indices[j];
            final chapter = chapters[i];
            return Padding(
              key: ValueKey('pad:${chapter.id}'),
              padding: const EdgeInsets.only(bottom: 10),
              child: rowBuilder(context, chapter, displayEps[i] as Ep, j),
            );
          },
        ),
      );
    }
    return SliverPadding(
      padding: padding,
      sliver: SliverGrid.builder(
        itemCount: indices.length,
        gridDelegate: metrics.gridDelegate!,
        itemBuilder: (context, j) {
          final i = indices[j];
          return rowBuilder(context, chapters[i], displayEps[i] as Ep, j);
        },
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child, this.title});

  final String? title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SizedBox(
        width: double.infinity,
        child: CalmCard(
          radius: 16,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (title != null) ...[
                CalmSectionHeader(title: title!),
                const SizedBox(height: 10),
              ],
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _DescriptionCard extends StatefulWidget {
  const _DescriptionCard({required this.description});

  final String description;

  @override
  State<_DescriptionCard> createState() => _DescriptionCardState();
}

class _DescriptionCardState extends State<_DescriptionCard> {
  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        CalmSectionHeader(title: t.comicInfo.description),
        const SizedBox(height: 8),
        CalmExpandableText(
          text: widget.description,
          maxLines: 5,
          expandLabel: t.comicInfo.expandFullText,
          collapseLabel: t.comicInfo.collapse,
          style: TextStyle(fontSize: 12.5, color: c.text2, height: 1.65),
        ),
      ],
    );
  }
}

/// 内容区水平边距：与 _ComicInfoState._constrainedSliver 同一份算法，
/// 章节 sliver 自带 SliverLayoutBuilder，用它算出内容宽度后再选单列/网格。
double _constrainedHorizontalPadding(double crossAxisExtent) =>
    ((crossAxisExtent - 1120) / 2).clamp(20.0, double.infinity).toDouble();

/// 章节列表头：轻盈分组头 + 计数 + 倒序切换。
class _EpisodeHeader extends StatelessWidget {
  const _EpisodeHeader({
    required this.title,
    required this.countText,
    required this.icon,
    required this.onToggleOrder,
  });

  final String title;
  final String countText;
  final IconData icon;
  final VoidCallback onToggleOrder;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 6),
      child: CalmSectionHeader(
        title: title,
        countText: countText,
        trailing: CalmIconButton(
          icon: icon,
          tooltip: t.bookshelf.sort,
          size: 28,
          iconSize: 15,
          onPressed: onToggleOrder,
        ),
      ),
    );
  }
}

/// 分组吸顶头：组名 + 计数 + 下载本组。背景不透明，吸顶时内容从下方滑过。
///
/// 普通 widget（高度自适应），交给 flutter_sticky_header 的
/// [SliverStickyHeader] 处理吸顶与顶替，不再手写 delegate 高度。
/// 与章节内容区同一套居中（窄屏左右 20，宽屏与章节行对齐）。

class _ChapterGroupHeaderBar extends StatelessWidget {
  const _ChapterGroupHeaderBar({
    required this.title,
    required this.countLabel,
    required this.onDownloadGroup,
    required this.onToggle,
    required this.expanded,
    required this.horizontalPadding,
  });

  final String title;
  final String countLabel;
  final VoidCallback? onDownloadGroup;
  final VoidCallback onToggle;
  final bool expanded;

  /// 外层 build 期按视口宽算好的水平边距（见 EpisodeSliverMetrics）。
  /// 组头在 SliverStickyHeader 的 header 槽里是 RenderBox 约束，
  /// 复用同一份值即可，不再包 LayoutBuilder。
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    // 与章节内容区同一套居中：全宽 Container 下 Center + 最大内容宽约束，
    // 窄屏下左右 20，宽屏下与章节行左右对齐。吸顶时整条背景不断层。
    final c = context.calm;
    final viewportWidth = MediaQuery.sizeOf(context).width;
    return Container(
      color: c.bg,
      padding: const EdgeInsets.only(bottom: 8),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: (viewportWidth - horizontalPadding * 2).clamp(
              0.0,
              double.infinity,
            ),
          ),
          // 整条胶囊可点展开/折叠；下载按钮自己拦截手势，不冒泡。
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onToggle,
              child: Container(
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: c.surface2,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    AnimatedRotation(
                      turns: expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 160),
                      curve: Curves.easeOutCubic,
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 17,
                        color: c.text2,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textHeightBehavior: kCalmTextHeightBehavior,
                        strutStyle: calmStrut(12.5),
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: c.text,
                          height: 1.2,
                          leadingDistribution: TextLeadingDistribution.even,
                        ),
                      ),
                    ),
                    const SizedBox(width: 7),
                    CalmBadge(label: countLabel, tone: CalmBadgeTone.neutral),
                    const Spacer(),
                    if (onDownloadGroup != null)
                      CalmIconButton(
                        icon: Icons.download_outlined,
                        tooltip: t.comicInfo.downloadGroup,
                        size: 28,
                        iconSize: 15,
                        onPressed: onDownloadGroup,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SelectionActionBar extends StatelessWidget {
  const _SelectionActionBar({
    required this.controller,
    required this.isDownloadType,
  });

  final EpisodeDownloadController controller;
  final bool isDownloadType;

  @override
  Widget build(BuildContext context) {
    final chapters = controller.lastChapters;
    final selected = chapters
        .where((c) => controller.selectedIds.contains(c.id))
        .toList();
    final downloadable = controller.downloadableOf(selected);
    final deletable = controller.downloadedOf(selected);
    final allSelected =
        chapters.isNotEmpty && selected.length >= chapters.length;

    final inSelection = controller.selectionMode;
    return Positioned(
      bottom: 8,
      left: 8,
      right: 8,
      child: IgnorePointer(
        ignoring: !inSelection,
        child: AnimatedSlide(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          offset: inSelection ? Offset.zero : const Offset(0, 1.0),
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 160),
            opacity: inSelection ? 1 : 0,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: CalmBatchActionBar(
                  selectedCount: controller.selectedIds.length,
                  onClose: controller.exitSelection,
                  actions: [
                    CalmButton(
                      label: allSelected
                          ? t.bookshelf.deselectAll
                          : t.common.selectAll,
                      icon: allSelected
                          ? Icons.deselect_rounded
                          : Icons.select_all_rounded,
                      variant: CalmButtonVariant.ghost,
                      size: CalmButtonSize.xs,
                      onPressed: chapters.isEmpty
                          ? null
                          : () {
                              if (allSelected) {
                                controller.clearSelection();
                              } else {
                                controller.selectAll(chapters.map((c) => c.id));
                              }
                            },
                    ),
                    CalmButton(
                      label: t.comicInfo.download,
                      icon: Icons.download_outlined,
                      variant: CalmButtonVariant.primary,
                      size: CalmButtonSize.xs,
                      onPressed: downloadable.isEmpty
                          ? null
                          : () async {
                              await controller.downloadChapters(
                                context,
                                selected,
                              );
                            },
                    ),
                    CalmButton(
                      label: t.common.delete,
                      icon: Icons.delete_outline_rounded,
                      variant: CalmButtonVariant.danger,
                      size: CalmButtonSize.xs,
                      onPressed: deletable.isEmpty
                          ? null
                          : () async {
                              final wholeDeleted = await controller
                                  .deleteChapters(context, selected);
                              if (wholeDeleted) {
                                controller.exitSelection();
                                if (isDownloadType && context.mounted) {
                                  context.pop();
                                }
                              }
                            },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReadActionButton extends StatelessWidget {
  const _ReadActionButton({required this.hasHistory, required this.onPressed});

  final bool hasHistory;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    // 轻盈浮空胶囊：不用 FloatingActionButton，也就没有 Hero tag 撞车问题
    // （从带 FAB 的页面 push 进来时旧路由共享默认 tag 会抛错）。
    return CalmButton(
      label: hasHistory ? t.comicInfo.continueRead : t.comicInfo.startRead,
      icon: hasHistory ? Icons.history_rounded : Icons.menu_book_rounded,
      variant: CalmButtonVariant.primary,
      size: CalmButtonSize.md,
      onPressed: onPressed,
    );
  }
}
