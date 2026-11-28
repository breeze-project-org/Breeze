import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_reorderable_grid_view/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pool/pool.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/network/http/picture/picture.dart';
import 'package:zephyr/page/bookshelf/method/local_comic_picker.dart';
import 'package:zephyr/page/comic_edit/cubit/comic_edit_cubit.dart';
import 'package:zephyr/page/comic_edit/method/comic_edit_debug.dart';
import 'package:zephyr/page/comic_edit/method/comic_edit_document.dart';
import 'package:zephyr/service/download/download_asset_store.dart';
import 'package:zephyr/type/enum.dart';
import 'package:zephyr/ui/ui.dart';
import 'package:zephyr/util/ohos/platform.dart';
import 'package:zephyr/widgets/fluent_dropdown.dart';
import 'package:zephyr/widgets/toast.dart';

const double _kWideBreakpoint = 900;
const double _kCompactMaxWidth = 840;
const double _kWideMaxWidth = 1180;

@RoutePage()
class ComicEditPage extends StatelessWidget {
  const ComicEditPage({super.key, required this.from, required this.comicId});

  final String from;
  final String comicId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => ComicEditCubit(from: from, comicId: comicId)..load(),
      child: const _ComicEditView(),
    );
  }
}

class _ComicEditView extends StatefulWidget {
  const _ComicEditView();

  @override
  State<_ComicEditView> createState() => _ComicEditViewState();
}

class _ComicEditViewState extends State<_ComicEditView> {
  final TextEditingController _titleController = TextEditingController();

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  /// 文档里的标题变化时同步输入框，但不覆盖用户正在输入的相同内容。
  void _syncTitle(String title) {
    if (_titleController.text != title) {
      _titleController.text = title;
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<ComicEditCubit, ComicEditState>(
      listenWhen: (previous, next) =>
          next.error.isNotEmpty && previous.error != next.error,
      listener: (context, state) => showErrorToast(state.error),
      child: BlocListener<ComicEditCubit, ComicEditState>(
        listenWhen: (previous, next) => previous.title != next.title,
        listener: (context, state) => _syncTitle(state.title),
        child: BlocBuilder<ComicEditCubit, ComicEditState>(
          builder: (context, state) {
            final cubit = context.read<ComicEditCubit>();
            final canEdit = !state.busy && !state.loading && !state.locked;
            return CalmPageScaffold(
              title: t.comicEdit.title,
              maxContentWidth: null,
              actions: [
                CalmIconButton(
                  icon: Icons.refresh_rounded,
                  tooltip: t.common.reload,
                  onPressed: state.busy ? null : cubit.load,
                ),
                CalmButton(
                  label: t.comicEdit.saveTitle,
                  icon: Icons.check_rounded,
                  variant: CalmButtonVariant.primary,
                  size: CalmButtonSize.sm,
                  loading: state.busy,
                  onPressed: canEdit
                      ? () => cubit.saveTitle(_titleController.text)
                      : null,
                ),
              ],
              body: _buildBody(state),
            );
          },
        ),
      ),
    );
  }

  Widget _buildBody(ComicEditState state) {
    if (state.loading) {
      return const Center(child: CalmLoading(size: 22));
    }
    if (state.locked) {
      return const _LockedView();
    }
    if (state.document == null) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: CalmEmptyState(
              icon: Icons.cloud_off_rounded,
              title: t.comicEdit.loadFailed,
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        if (state.busy) const CalmProgressBar(height: 2),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= _kWideBreakpoint;
              final layout = wide
                  ? _WideEditLayout(
                      state: state,
                      titleController: _titleController,
                    )
                  : _CompactEditLayout(
                      state: state,
                      titleController: _titleController,
                    );
              return Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: wide ? _kWideMaxWidth : _kCompactMaxWidth,
                  ),
                  child: SizedBox(width: double.infinity, child: layout),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _LockedView extends StatelessWidget {
  const _LockedView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: CalmEmptyState(
            icon: Icons.lock_outline_rounded,
            title: t.comicEdit.lockedTitle,
            subtitle: t.comicEdit.lockedMessage,
            action: CalmButton(
              label: t.common.back,
              variant: CalmButtonVariant.secondary,
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
        ),
      ),
    );
  }
}

/// 窄屏：胶囊分段切换「基本信息 / 章节 / 图片」。
class _CompactEditLayout extends StatefulWidget {
  const _CompactEditLayout({
    required this.state,
    required this.titleController,
  });

  final ComicEditState state;
  final TextEditingController titleController;

  @override
  State<_CompactEditLayout> createState() => _CompactEditLayoutState();
}

class _CompactEditLayoutState extends State<_CompactEditLayout> {
  int _index = 0;

  void _openImagesTab() {
    if (!mounted) return;
    setState(() => _index = 2);
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: Align(
            alignment: Alignment.centerLeft,
            child: CalmSegmentedControl<int>(
              value: _index,
              options: [
                (
                  value: 0,
                  label: t.comicEdit.basicInfo,
                  icon: Icons.info_outline_rounded,
                ),
                (
                  value: 1,
                  label: t.comicEdit.chapters,
                  icon: Icons.list_alt_rounded,
                ),
                (
                  value: 2,
                  label: t.comicEdit.images,
                  icon: Icons.photo_library_outlined,
                ),
              ],
              onChanged: (value) => setState(() => _index = value),
            ),
          ),
        ),
        Expanded(
          child: switch (_index) {
            1 => _ChaptersSection(state: state, onOpenImages: _openImagesTab),
            2 => _ImagesTab(state: state),
            _ => _BasicInfoTab(
              state: state,
              titleController: widget.titleController,
            ),
          },
        ),
      ],
    );
  }
}

/// 宽屏：左侧章节栏 + 右侧封面/信息与图片宫格分栏。
class _WideEditLayout extends StatelessWidget {
  const _WideEditLayout({required this.state, required this.titleController});

  final ComicEditState state;
  final TextEditingController titleController;

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: 340, child: _ChapterListPane(state: state)),
        VerticalDivider(width: 1, color: c.border),
        Expanded(
          child: Column(
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 300),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                  child: _BasicInfoSection(
                    state: state,
                    titleController: titleController,
                  ),
                ),
              ),
              const CalmDivider(),
              Expanded(
                child: _ImageGridPane(state: state, showChapterTitle: true),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BasicInfoTab extends StatelessWidget {
  const _BasicInfoTab({required this.state, required this.titleController});

  final ComicEditState state;
  final TextEditingController titleController;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _BasicInfoSection(state: state, titleController: titleController),
      ],
    );
  }
}

/// 封面预览 + 标题输入 + 更换封面动作（桌面与手机共用一套）。
class _BasicInfoSection extends StatelessWidget {
  const _BasicInfoSection({required this.state, required this.titleController});

  final ComicEditState state;
  final TextEditingController titleController;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ComicEditCubit>();
    final coverPath = state.cover['path']?.toString().trim() ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CalmSectionHeader(title: t.comicEdit.comicTitle),
        const SizedBox(height: 8),
        CalmCard(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CoverPreview(
                from: cubit.from,
                comicId: cubit.comicId,
                path: coverPath,
                width: 104,
                height: 143,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CalmTextArea(
                      controller: titleController,
                      hintText: t.comicEdit.titleHint,
                      minLines: 1,
                      maxLines: 6,
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        CalmButton(
                          label: t.comicEdit.changeCover,
                          icon: Icons.image_outlined,
                          variant: CalmButtonVariant.secondary,
                          size: CalmButtonSize.sm,
                          onPressed: state.busy
                              ? null
                              : () => _pickCover(cubit),
                        ),
                        CalmButton(
                          label: t.comicEdit.chooseFromComic,
                          icon: Icons.collections_outlined,
                          variant: CalmButtonVariant.secondary,
                          size: CalmButtonSize.sm,
                          onPressed: state.busy
                              ? null
                              : () =>
                                    _pickCoverFromComic(context, cubit, state),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CoverPreview extends StatelessWidget {
  const _CoverPreview({
    required this.from,
    required this.comicId,
    required this.path,
    this.width = 160,
    this.height = 220,
  });

  final String from;
  final String comicId;
  final String path;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    final placeholder = Container(
      color: c.surface2,
      alignment: Alignment.center,
      child: Icon(Icons.image_outlined, size: 32, color: c.text3),
    );
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: c.shadowSm,
      ),
      clipBehavior: Clip.antiAlias,
      child: path.isEmpty
          ? placeholder
          : FutureBuilder<String>(
              future: findCachedPicturePath(
                from: from,
                path: path,
                cartoonId: comicId,
                pictureType: PictureType.cover,
              ),
              builder: (context, snapshot) {
                final local = snapshot.data ?? '';
                if (local.isEmpty) {
                  return placeholder;
                }
                return Image.file(File(local), fit: BoxFit.cover);
              },
            ),
    );
  }
}

class _ChaptersSection extends StatelessWidget {
  const _ChaptersSection({required this.state, this.onOpenImages});

  final ComicEditState state;
  final VoidCallback? onOpenImages;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: _ChaptersToolbar(state: state, onOpenImages: onOpenImages),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _ChaptersList(state: state, onOpenImages: onOpenImages),
        ),
      ],
    );
  }
}

class _ChapterListPane extends StatelessWidget {
  const _ChapterListPane({required this.state});

  final ComicEditState state;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: _ChaptersToolbar(state: state, onOpenImages: null),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _ChaptersList(
            state: state,
            onOpenImages: null,
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
          ),
        ),
      ],
    );
  }
}

/// 章节区标题 + 导入/新增动作。
class _ChaptersToolbar extends StatelessWidget {
  const _ChaptersToolbar({required this.state, this.onOpenImages});

  final ComicEditState state;
  final VoidCallback? onOpenImages;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ComicEditCubit>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CalmSectionHeader(
          title: t.comicEdit.chapters,
          countText: '${state.chapters.length}',
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            CalmButton(
              label: t.comicEdit.importChapters,
              icon: Icons.playlist_add,
              variant: CalmButtonVariant.secondary,
              size: CalmButtonSize.sm,
              onPressed: state.busy
                  ? null
                  : () => _importChapters(context, cubit),
            ),
            CalmButton(
              label: t.comicEdit.importImages,
              icon: Icons.add_photo_alternate_outlined,
              variant: CalmButtonVariant.secondary,
              size: CalmButtonSize.sm,
              onPressed: state.busy
                  ? null
                  : () => _importImages(context, cubit, state),
            ),
            CalmButton(
              label: t.comicEdit.addChapter,
              icon: Icons.add_rounded,
              variant: CalmButtonVariant.tonal,
              size: CalmButtonSize.sm,
              onPressed: state.busy
                  ? null
                  : () => _addChapter(context, cubit, onAdded: onOpenImages),
            ),
          ],
        ),
      ],
    );
  }
}

class _ChaptersList extends StatelessWidget {
  const _ChaptersList({
    required this.state,
    this.onOpenImages,
    this.padding = const EdgeInsets.fromLTRB(16, 4, 16, 24),
  });

  final ComicEditState state;
  final VoidCallback? onOpenImages;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ComicEditCubit>();
    final chapters = state.chapters;
    if (chapters.isEmpty) {
      return Padding(
        padding: padding,
        child: Align(
          alignment: Alignment.topCenter,
          child: CalmEmptyState(
            icon: Icons.list_alt_rounded,
            title: t.comicEdit.noChapters,
          ),
        ),
      );
    }

    return ReorderableListView.builder(
      padding: padding,
      itemCount: chapters.length,
      buildDefaultDragHandles: false,
      onReorderItem: (oldIndex, newIndex) =>
          cubit.reorderChapters(oldIndex, newIndex),
      itemBuilder: (context, index) {
        final chapter = chapters[index];
        final id = comicEditChapterId(chapter);
        return _ChapterTile(
          key: ValueKey(id),
          chapter: chapter,
          index: index,
          selected: id == state.selectedChapterId,
          onTap: () {
            cubit.selectChapter(id);
            onOpenImages?.call();
          },
          onRename: () => _renameChapter(context, cubit, chapter),
          onEditVolume: () => _editChapterVolume(context, cubit, chapter),
        );
      },
    );
  }
}

class _ChapterTile extends StatelessWidget {
  const _ChapterTile({
    super.key,
    required this.chapter,
    required this.index,
    required this.selected,
    required this.onTap,
    required this.onRename,
    required this.onEditVolume,
  });

  final Map<String, dynamic> chapter;
  final int index;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onEditVolume;

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    final name = chapter['name']?.toString() ?? '';
    final volume = chapter['groupTitle']?.toString().trim() ?? '';
    final count = ((chapter['images'] as List?) ?? const []).length;
    final subtitle = volume.isEmpty
        ? t.comicEdit.pagesCount(count: count)
        : '${t.comicEdit.volumeLabel(name: volume)} · '
              '${t.comicEdit.pagesCount(count: count)}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
            decoration: BoxDecoration(
              color: selected ? c.accentSoft : c.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: selected ? c.accentBorder : c.border),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected ? c.surface : c.surface2,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${index + 1}',
                    textHeightBehavior: kCalmTextHeightBehavior,
                    strutStyle: calmStrut(11),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: selected ? c.accent : c.text2,
                      height: 1.2,
                      leadingDistribution: TextLeadingDistribution.even,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        name.isEmpty ? t.comicEdit.chapterName : name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: c.text,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.5,
                          color: c.text3,
                          height: 1.3,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                CalmIconButton(
                  icon: Icons.edit_outlined,
                  tooltip: t.comicEdit.renameChapter,
                  size: 26,
                  iconSize: 14,
                  onPressed: onRename,
                ),
                const SizedBox(width: 4),
                CalmIconButton(
                  icon: Icons.book_outlined,
                  tooltip: t.comicEdit.editVolume,
                  size: 26,
                  iconSize: 14,
                  onPressed: onEditVolume,
                ),
                const SizedBox(width: 4),
                ReorderableDragStartListener(
                  index: index,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 6,
                    ),
                    child: Icon(
                      Icons.drag_handle_rounded,
                      size: 18,
                      color: c.text3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ImagesTab extends StatelessWidget {
  const _ImagesTab({required this.state});

  final ComicEditState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ComicEditCubit>();
    final chapter = state.selectedChapter;
    if (state.chapters.isEmpty || chapter == null) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: CalmEmptyState(
              icon: Icons.list_alt_rounded,
              title: t.comicEdit.noChapters,
            ),
          ),
        ),
      );
    }

    final currentId = comicEditChapterId(chapter);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FluentDropdown<String>(
              value: currentId,
              displayValue: _chapterDisplayName(chapter),
              items: {
                for (final item in state.chapters)
                  comicEditChapterId(item): _chapterDisplayName(item),
              },
              onChanged: state.busy ? null : cubit.selectChapter,
            ),
          ),
        ),
        Expanded(child: _ImageGridPane(state: state)),
      ],
    );
  }
}

class _ResolvedImage {
  const _ResolvedImage({required this.path, required this.localPath});

  final String path;
  final String localPath;
}

class _ImageGridPane extends StatefulWidget {
  const _ImageGridPane({required this.state, this.showChapterTitle = false});

  final ComicEditState state;
  final bool showChapterTitle;

  @override
  State<_ImageGridPane> createState() => _ImageGridPaneState();
}

class _ImageGridPaneState extends State<_ImageGridPane> {
  final ScrollController _scrollController = ScrollController();
  String _loadedChapterId = '';
  String _loadedSignature = '';
  Future<List<_ResolvedImage>> _imagesFuture = Future.value(const []);

  @override
  void initState() {
    super.initState();
    _startLoad();
  }

  @override
  void didUpdateWidget(covariant _ImageGridPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    final chapter = widget.state.selectedChapter;
    if (chapter == null) {
      if (_loadedChapterId.isNotEmpty) {
        _loadedChapterId = '';
        _loadedSignature = '';
        _imagesFuture = Future.value(const []);
      }
      return;
    }
    final chapterId = comicEditChapterId(chapter);
    final signature = _signatureFor(chapter);
    if (chapterId != _loadedChapterId || signature != _loadedSignature) {
      _startLoad();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _startLoad() {
    final chapter = widget.state.selectedChapter;
    if (chapter == null) {
      _loadedChapterId = '';
      _loadedSignature = '';
      _imagesFuture = Future.value(const []);
      return;
    }
    _loadedChapterId = comicEditChapterId(chapter);
    _loadedSignature = _signatureFor(chapter);
    final cubit = context.read<ComicEditCubit>();
    _imagesFuture = _resolveImages(
      from: cubit.from,
      comicId: cubit.comicId,
      chapter: chapter,
      images: widget.state.selectedImages,
    );
  }

  String _signatureFor(Map<String, dynamic> chapter) {
    final paths =
        ((chapter['images'] as List?) ?? const <dynamic>[])
            .whereType<Map>()
            .map((image) => image['path']?.toString() ?? '')
            .where((path) => path.isNotEmpty)
            .toList()
          ..sort();
    return paths.join('|');
  }

  Future<List<_ResolvedImage>> _resolveImages({
    required String from,
    required String comicId,
    required Map<String, dynamic> chapter,
    required List<Map<String, dynamic>> images,
  }) async {
    final storageId = comicEditChapterStorageId(chapter);
    final stopwatch = Stopwatch()..start();
    final pool = Pool(8);
    try {
      final resolved = await Future.wait(
        images.map(
          (image) => pool.withResource(() async {
            final path = image['path']?.toString() ?? '';
            var localPath = '';
            if (path.isNotEmpty) {
              try {
                final resolver = debugComicEditImagePathResolver;
                if (resolver != null) {
                  localPath = await resolver(
                    from: from,
                    comicId: comicId,
                    storageChapterId: storageId,
                    path: path,
                  );
                } else {
                  final store = DownloadAssetStore(
                    from: from,
                    path: path,
                    cartoonId: comicId,
                    chapterId: '',
                    storageChapterId: storageId,
                    pictureType: PictureType.page,
                  );
                  final existing = await store.findExistingDownload();
                  localPath = existing?.path ?? '';
                }
              } catch (_) {}
            }
            return _ResolvedImage(path: path, localPath: localPath);
          }),
        ),
      );
      final remaining = const Duration(milliseconds: 120) - stopwatch.elapsed;
      if (remaining > Duration.zero) {
        await Future<void>.delayed(remaining);
      }
      return resolved;
    } finally {
      await pool.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    final state = widget.state;
    final cubit = context.read<ComicEditCubit>();
    final chapter = state.selectedChapter;
    if (state.chapters.isEmpty || chapter == null) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: CalmEmptyState(
              icon: Icons.list_alt_rounded,
              title: t.comicEdit.noChapters,
            ),
          ),
        ),
      );
    }

    final chapterName = _chapterDisplayName(chapter);
    final images = state.selectedImages;
    final paths = images
        .map((image) => image['path']?.toString() ?? '')
        .where((path) => path.isNotEmpty)
        .toList();

    final hasSelection = state.selectedImagePaths.isNotEmpty;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Stack(
      fit: StackFit.expand,
      children: [
        Column(
          children: [
            if (widget.showChapterTitle)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        chapterName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: c.text,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      t.comicEdit.reorderHint,
                      style: TextStyle(fontSize: 10.5, color: c.text3),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: images.isEmpty
                  ? Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: CalmEmptyState(
                            icon: Icons.photo_library_outlined,
                            title: t.comicEdit.emptyChapter,
                          ),
                        ),
                      ),
                    )
                  : FutureBuilder<List<_ResolvedImage>>(
                      future: _imagesFuture,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState != ConnectionState.done) {
                          return const Center(child: CalmLoading(size: 22));
                        }
                        if (snapshot.hasError) {
                          return Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 420),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: CalmEmptyState(
                                  icon: Icons.broken_image_outlined,
                                  title: t.comicEdit.loadFailed,
                                ),
                              ),
                            ),
                          );
                        }
                        final resolvedByPath = {
                          for (final item
                              in snapshot.data ?? const <_ResolvedImage>[])
                            item.path: item,
                        };
                        return ReorderableBuilder<String>.builder(
                          itemCount: images.length,
                          scrollController: _scrollController,
                          onReorder: (reorderedListFunction) {
                            final ordered = reorderedListFunction(paths);
                            cubit.reorderImages(ordered);
                          },
                          childBuilder: (itemBuilder) {
                            return GridView.builder(
                              controller: _scrollController,
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                              itemCount: images.length,
                              gridDelegate:
                                  const SliverGridDelegateWithMaxCrossAxisExtent(
                                    maxCrossAxisExtent: 150,
                                    mainAxisSpacing: 8,
                                    crossAxisSpacing: 8,
                                    childAspectRatio: 0.68,
                                  ),
                              itemBuilder: (context, index) {
                                final path = paths[index];
                                return itemBuilder(
                                  _ImageTile(
                                    key: ValueKey(path),
                                    localPath:
                                        resolvedByPath[path]?.localPath ?? '',
                                    index: index,
                                    selected: state.selectedImagePaths.contains(
                                      path,
                                    ),
                                    onTap: () => cubit.toggleImage(path),
                                  ),
                                  index,
                                );
                              },
                            );
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
        Positioned(
          bottom: 10 + bottomInset,
          left: 12,
          right: 12,
          child: IgnorePointer(
            ignoring: !hasSelection,
            child: AnimatedSlide(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              offset: hasSelection ? Offset.zero : const Offset(0, 1),
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 160),
                opacity: hasSelection ? 1 : 0,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: c.surface,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: c.borderStrong),
                        boxShadow: c.shadowMd,
                      ),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Text(
                              t.comicEdit.selectedCount(
                                count: state.selectedImagePaths.length,
                              ),
                              textHeightBehavior: kCalmTextHeightBehavior,
                              strutStyle: calmStrut(12),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: c.accent,
                                height: 1.2,
                                leadingDistribution:
                                    TextLeadingDistribution.even,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ),
                          Container(
                            width: 1,
                            height: 16,
                            color: c.borderStrong,
                          ),
                          CalmButton(
                            label: t.comicEdit.selectAll,
                            icon: Icons.select_all_rounded,
                            variant: CalmButtonVariant.ghost,
                            size: CalmButtonSize.xs,
                            onPressed: state.busy
                                ? null
                                : cubit.selectAllImages,
                          ),
                          CalmButton(
                            label: t.comicEdit.moveToChapter,
                            icon: Icons.drive_file_move_outline,
                            variant: CalmButtonVariant.secondary,
                            size: CalmButtonSize.xs,
                            onPressed: state.busy
                                ? null
                                : () => _moveSelected(context, cubit, state),
                          ),
                          CalmButton(
                            label: t.common.delete,
                            icon: Icons.delete_outline,
                            variant: CalmButtonVariant.danger,
                            size: CalmButtonSize.xs,
                            onPressed: state.busy
                                ? null
                                : () => _deleteSelected(context, cubit, state),
                          ),
                          CalmIconButton(
                            icon: Icons.close_rounded,
                            tooltip: t.comicEdit.clearSelection,
                            size: 26,
                            iconSize: 14,
                            onPressed: cubit.clearSelection,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _deleteSelected(
    BuildContext context,
    ComicEditCubit cubit,
    ComicEditState state,
  ) async {
    final count = state.selectedImagePaths.length;
    if (count == 0) return;
    final confirmed = await showCalmDialog<bool>(
      context,
      title: t.comicEdit.deleteImagesTitle,
      subtitle: t.comicEdit.deleteImagesMessage(count: count),
      icon: Icons.delete_outline_rounded,
      tone: CalmTone.danger,
      bodyBuilder: (ctx) => const SizedBox.shrink(),
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
    if (confirmed != true) return;
    await cubit.deleteSelectedImages();
  }

  Future<void> _moveSelected(
    BuildContext context,
    ComicEditCubit cubit,
    ComicEditState state,
  ) async {
    final targets = state.chapters
        .where(
          (chapter) => comicEditChapterId(chapter) != state.selectedChapterId,
        )
        .toList();
    if (targets.isEmpty) return;

    final target = await showCalmDialog<String>(
      context,
      title: t.comicEdit.moveToChapter,
      icon: Icons.drive_file_move_outline,
      maxWidth: 440,
      bodyBuilder: (ctx) => _ChapterPickerList(
        chapters: targets,
        currentId: '',
        onPick: (id) => Navigator.of(ctx).pop(id),
      ),
      actionsBuilder: (ctx) => [
        CalmButton(
          label: t.common.cancel,
          variant: CalmButtonVariant.ghost,
          onPressed: () => Navigator.of(ctx).pop(),
        ),
      ],
    );
    if (target == null) return;
    await cubit.moveSelectedToChapter(target);
  }
}

class _ImageTile extends StatelessWidget {
  const _ImageTile({
    super.key,
    required this.localPath,
    required this.index,
    required this.selected,
    required this.onTap,
  });

  final String localPath;
  final int index;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    return RepaintBoundary(
      child: GestureDetector(
        onTap: onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: c.surface2,
                borderRadius: BorderRadius.circular(12),
              ),
              child: localPath.isEmpty
                  ? Icon(Icons.broken_image_outlined, color: c.text3)
                  : Image.file(
                      File(localPath),
                      fit: BoxFit.cover,
                      cacheWidth: 360,
                    ),
            ),
            Positioned(
              left: 5,
              bottom: 5,
              child: Container(
                height: 18,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  color: c.surface.withValues(alpha: 0.88),
                  borderRadius: BorderRadius.circular(999),
                ),
                alignment: Alignment.center,
                child: Text(
                  '${index + 1}',
                  textHeightBehavior: kCalmTextHeightBehavior,
                  strutStyle: calmStrut(10.5),
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: c.text2,
                    height: 1.2,
                    leadingDistribution: TextLeadingDistribution.even,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
            if (selected)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: c.accent.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: c.accent, width: 2),
                  ),
                  child: Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: const EdgeInsets.all(5),
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: c.accent,
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.check_rounded,
                          size: 13,
                          color: c.accentFg,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 选择章节 / 封面图片
// ---------------------------------------------------------------------------

class _ChapterPickerList extends StatelessWidget {
  const _ChapterPickerList({
    required this.chapters,
    required this.currentId,
    required this.onPick,
  });

  final List<Map<String, dynamic>> chapters;
  final String currentId;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 320,
      child: ListView(
        children: [
          for (final entry in chapters.asMap().entries)
            _ChapterPickerTile(
              chapter: entry.value,
              index: entry.key,
              selected: comicEditChapterId(entry.value) == currentId,
              onTap: () => onPick(comicEditChapterId(entry.value)),
            ),
        ],
      ),
    );
  }
}

class _ChapterPickerTile extends StatelessWidget {
  const _ChapterPickerTile({
    required this.chapter,
    required this.index,
    required this.selected,
    required this.onTap,
  });

  final Map<String, dynamic> chapter;
  final int index;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    final count = ((chapter['images'] as List?) ?? const []).length;
    return CalmListTile(
      title: _chapterDisplayName(chapter),
      subtitle: t.comicEdit.pagesCount(count: count),
      leading: Container(
        width: 24,
        height: 24,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? c.accentSoft : c.surface2,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          '${index + 1}',
          textHeightBehavior: kCalmTextHeightBehavior,
          strutStyle: calmStrut(11),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: selected ? c.accent : c.text2,
            height: 1.2,
            leadingDistribution: TextLeadingDistribution.even,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
      trailing: selected ? Icon(Icons.check, size: 16, color: c.accent) : null,
      onTap: onTap,
    );
  }
}

class _CoverImageSelection {
  const _CoverImageSelection({
    required this.chapterId,
    required this.imagePath,
  });

  final String chapterId;
  final String imagePath;
}

Future<void> _pickCoverFromComic(
  BuildContext context,
  ComicEditCubit cubit,
  ComicEditState state,
) async {
  final selection = await showCalmDialog<_CoverImageSelection>(
    context,
    title: t.comicEdit.chooseCoverImage,
    icon: Icons.collections_outlined,
    maxWidth: 560,
    bodyBuilder: (ctx) => _CoverImagePickerBody(
      from: cubit.from,
      comicId: cubit.comicId,
      chapters: state.chapters,
      onPick: (value) => Navigator.of(ctx).pop(value),
    ),
    actionsBuilder: (ctx) => [
      CalmButton(
        label: t.common.cancel,
        variant: CalmButtonVariant.ghost,
        onPressed: () => Navigator.of(ctx).pop(),
      ),
    ],
  );
  if (selection == null) return;
  await cubit.saveCoverFromImage(selection.chapterId, selection.imagePath);
}

class _CoverImagePickerBody extends StatefulWidget {
  const _CoverImagePickerBody({
    required this.from,
    required this.comicId,
    required this.chapters,
    required this.onPick,
  });

  final String from;
  final String comicId;
  final List<Map<String, dynamic>> chapters;
  final ValueChanged<_CoverImageSelection> onPick;

  @override
  State<_CoverImagePickerBody> createState() => _CoverImagePickerBodyState();
}

class _CoverImagePickerBodyState extends State<_CoverImagePickerBody> {
  String _chapterId = '';
  Future<Map<String, String>> _pathsFuture = Future.value(const {});

  @override
  void initState() {
    super.initState();
    _chapterId = widget.chapters.isEmpty
        ? ''
        : comicEditChapterId(widget.chapters.first);
    _startLoad();
  }

  Map<String, dynamic>? get _chapter {
    for (final chapter in widget.chapters) {
      if (comicEditChapterId(chapter) == _chapterId) return chapter;
    }
    return widget.chapters.isEmpty ? null : widget.chapters.first;
  }

  List<Map<String, dynamic>> get _images {
    final chapter = _chapter;
    if (chapter == null) return const [];
    return ((chapter['images'] as List?) ?? const <dynamic>[])
        .whereType<Map>()
        .map((image) => Map<String, dynamic>.from(image))
        .toList();
  }

  void _startLoad() {
    final chapter = _chapter;
    if (chapter == null) {
      _pathsFuture = Future.value(const {});
      return;
    }
    _pathsFuture = _resolvePaths(chapter);
  }

  Future<Map<String, String>> _resolvePaths(
    Map<String, dynamic> chapter,
  ) async {
    final storageId = comicEditChapterStorageId(chapter);
    final images = ((chapter['images'] as List?) ?? const <dynamic>[])
        .whereType<Map>()
        .map((image) => Map<String, dynamic>.from(image))
        .toList();
    final pool = Pool(8);
    try {
      final entries = await Future.wait(
        images.map(
          (image) => pool.withResource(() async {
            final path = image['path']?.toString() ?? '';
            var local = '';
            if (path.isNotEmpty) {
              try {
                final resolver = debugComicEditImagePathResolver;
                if (resolver != null) {
                  local = await resolver(
                    from: widget.from,
                    comicId: widget.comicId,
                    storageChapterId: storageId,
                    path: path,
                  );
                } else {
                  final store = DownloadAssetStore(
                    from: widget.from,
                    path: path,
                    cartoonId: widget.comicId,
                    chapterId: '',
                    storageChapterId: storageId,
                    pictureType: PictureType.page,
                  );
                  final existing = await store.findExistingDownload();
                  local = existing?.path ?? '';
                }
              } catch (_) {}
            }
            return MapEntry(path, local);
          }),
        ),
      );
      return Map.fromEntries(entries);
    } finally {
      await pool.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    final images = _images;
    final chapter = _chapter;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.chapters.isNotEmpty) ...[
          FluentDropdown<String>(
            value: _chapterId,
            displayValue: chapter == null ? '' : _chapterDisplayName(chapter),
            items: {
              for (final chapter in widget.chapters)
                comicEditChapterId(chapter): _chapterDisplayName(chapter),
            },
            onChanged: (value) {
              setState(() {
                _chapterId = value;
                _startLoad();
              });
            },
          ),
          const SizedBox(height: 12),
        ],
        SizedBox(
          height: 380,
          child: images.isEmpty
              ? Align(
                  alignment: Alignment.topCenter,
                  child: CalmEmptyState(
                    icon: Icons.photo_library_outlined,
                    title: t.comicEdit.emptyChapter,
                  ),
                )
              : FutureBuilder<Map<String, String>>(
                  future: _pathsFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(child: CalmLoading(size: 20));
                    }
                    final paths = snapshot.data ?? const <String, String>{};
                    return GridView.builder(
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 130,
                            mainAxisSpacing: 8,
                            crossAxisSpacing: 8,
                            childAspectRatio: 0.68,
                          ),
                      itemCount: images.length,
                      itemBuilder: (context, index) {
                        final image = images[index];
                        final path = image['path']?.toString() ?? '';
                        final local = paths[path] ?? '';
                        return MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                            onTap: () => widget.onPick(
                              _CoverImageSelection(
                                chapterId: _chapterId,
                                imagePath: path,
                              ),
                            ),
                            child: Container(
                              clipBehavior: Clip.antiAlias,
                              decoration: BoxDecoration(
                                color: c.surface2,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: local.isEmpty
                                  ? Icon(
                                      Icons.broken_image_outlined,
                                      color: c.text3,
                                    )
                                  : Image.file(
                                      File(local),
                                      fit: BoxFit.cover,
                                      cacheWidth: 280,
                                    ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 文件选择与章节弹窗
// ---------------------------------------------------------------------------

Future<void> _pickCover(ComicEditCubit cubit) async {
  const typeGroup = XTypeGroup(
    label: 'images',
    extensions: <String>['jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp'],
  );
  final file = await openFile(acceptedTypeGroups: [typeGroup]);
  if (file == null) return;
  await cubit.saveCover(File(file.path));
}

Future<void> _importChapters(BuildContext context, ComicEditCubit cubit) async {
  final choice = await showCalmSheet<String>(
    context,
    title: t.comicEdit.importChapters,
    builder: (ctx) {
      final c = ctx.calm;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!Platform.isIOS && !isOhos)
            CalmListTile(
              leading: Icon(
                Icons.folder_open_outlined,
                size: 18,
                color: c.text2,
              ),
              title: t.bookshelf.importExternalFolder,
              subtitle: t.bookshelf.importExternalFolderHint,
              onTap: () => Navigator.of(ctx).pop('folder'),
            ),
          CalmListTile(
            leading: Icon(Icons.archive_outlined, size: 18, color: c.text2),
            title: t.bookshelf.importExternalArchive,
            subtitle: t.bookshelf.importExternalArchiveHint,
            onTap: () => Navigator.of(ctx).pop('archive'),
          ),
        ],
      );
    },
  );
  if (choice == null) return;

  try {
    final picked = choice == 'folder'
        ? await pickLocalComicDirectory()
        : await pickLocalComicArchive();
    if (picked == null) return;
    await cubit.importChaptersFromPath(
      sourcePath: picked.path,
      isDirectory: picked.isDirectory,
      cleanupRoot: picked.cleanupRoot,
      uncategorizedName: t.bookshelf.importUncategorized,
    );
  } catch (e) {
    showErrorToast(t.error.importFailed(error: e.toString()));
  }
}

Future<void> _importImages(
  BuildContext context,
  ComicEditCubit cubit,
  ComicEditState state,
) async {
  if (state.chapters.isEmpty) {
    showErrorToast(t.comicEdit.noChapters);
    return;
  }
  final chapterId = await _pickChapterForImport(context, state);
  if (chapterId == null) return;

  const typeGroup = XTypeGroup(
    label: 'images',
    extensions: <String>['jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp'],
  );
  final files = await openFiles(acceptedTypeGroups: const [typeGroup]);
  if (files.isEmpty) return;
  await cubit.importImagesToChapter(
    chapterId,
    files.map((file) => File(file.path)).toList(),
  );
}

/// 导入图片前先选目标章节，默认当前章节。
Future<String?> _pickChapterForImport(
  BuildContext context,
  ComicEditState state,
) async {
  final chapters = state.chapters;
  if (chapters.isEmpty) return null;
  final currentId = state.selectedChapterId.isNotEmpty
      ? state.selectedChapterId
      : comicEditChapterId(chapters.first);
  return showCalmDialog<String>(
    context,
    title: t.comicEdit.selectChapter,
    icon: Icons.list_alt_rounded,
    maxWidth: 440,
    bodyBuilder: (ctx) => _ChapterPickerList(
      chapters: chapters,
      currentId: currentId,
      onPick: (id) => Navigator.of(ctx).pop(id),
    ),
    actionsBuilder: (ctx) => [
      CalmButton(
        label: t.common.cancel,
        variant: CalmButtonVariant.ghost,
        onPressed: () => Navigator.of(ctx).pop(),
      ),
    ],
  );
}

String _chapterDisplayName(Map<String, dynamic> chapter) {
  final name = chapter['name']?.toString() ?? '';
  return name.isEmpty ? t.comicEdit.chapterName : name;
}

Future<void> _editChapterVolume(
  BuildContext context,
  ComicEditCubit cubit,
  Map<String, dynamic> chapter,
) async {
  final value = await _showNameDialog(
    context,
    title: t.comicEdit.editVolume,
    hint: t.comicEdit.volumeHint,
    initial: chapter['groupTitle']?.toString() ?? '',
  );
  if (value == null) return;
  await cubit.setChapterVolume(comicEditChapterId(chapter), value);
}

Future<void> _renameChapter(
  BuildContext context,
  ComicEditCubit cubit,
  Map<String, dynamic> chapter,
) async {
  final value = await _showNameDialog(
    context,
    title: t.comicEdit.renameChapter,
    hint: t.comicEdit.chapterNameHint,
    initial: chapter['name']?.toString() ?? '',
  );
  if (value == null) return;
  await cubit.renameChapter(comicEditChapterId(chapter), value);
}

Future<void> _addChapter(
  BuildContext context,
  ComicEditCubit cubit, {
  VoidCallback? onAdded,
}) async {
  final value = await _showNameDialog(
    context,
    title: t.comicEdit.addChapter,
    hint: t.comicEdit.addChapterHint,
  );
  if (value == null) return;
  await cubit.addChapter(value);
  onAdded?.call();
}

Future<String?> _showNameDialog(
  BuildContext context, {
  required String title,
  required String hint,
  String initial = '',
}) async {
  final controller = TextEditingController(text: initial);
  var value = initial;
  final result = await showCalmDialog<String>(
    context,
    title: title,
    icon: Icons.edit_outlined,
    maxWidth: 440,
    bodyBuilder: (ctx) => CalmTextField(
      controller: controller,
      hintText: hint,
      clearable: true,
      onChanged: (next) => value = next,
      onSubmitted: (next) => Navigator.of(ctx).pop(next),
    ),
    actionsBuilder: (ctx) => [
      CalmButton(
        label: t.common.cancel,
        variant: CalmButtonVariant.ghost,
        onPressed: () => Navigator.of(ctx).pop(),
      ),
      CalmButton(
        label: t.common.ok,
        variant: CalmButtonVariant.primary,
        onPressed: () => Navigator.of(ctx).pop(value),
      ),
    ],
  );
  controller.dispose();
  return result;
}
