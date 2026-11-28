import 'dart:ui';

import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';
import 'package:zephyr/cubit/string_select.dart';
import 'package:zephyr/page/comic_info/comic_info.dart';
import 'package:zephyr/page/download/adapters/download_chapter_adapter.dart';
import 'package:zephyr/page/comic_read/cubit/reader_cubit.dart';
import 'package:zephyr/page/comic_read/method/jump_chapter.dart';
import 'package:zephyr/page/comic_read/widgets/dialogs/button_dialog.dart';
import 'package:zephyr/page/comic_read/widgets/settings/reader_settings_sheet.dart';
import 'package:zephyr/type/enum.dart';
import 'package:zephyr/ui/ui.dart';
import 'package:zephyr/util/context/context_extensions.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/config/router/router.dart';
import 'package:zephyr/config/router/router.gr.dart';
import 'package:zephyr/i18n/strings.g.dart';

class BottomWidget extends StatefulWidget {
  final ComicEntryType type;
  final dynamic comicInfo;
  final Widget sliderWidget;
  final int order;
  final int epsNumber;
  final String comicId;
  final String from;
  final JumpChapter jumpChapter;
  final ValueChanged<bool>? onLandscapeChanged;
  final ValueChanged<bool>? onDoublePageModeChanged;

  const BottomWidget({
    super.key,
    required this.type,
    required this.comicInfo,
    required this.sliderWidget,
    required this.order,
    required this.epsNumber,
    required this.comicId,
    required this.from,
    required this.jumpChapter,
    this.onLandscapeChanged,
    this.onDoublePageModeChanged,
  });

  @override
  State<BottomWidget> createState() => _BottomWidgetState();
}

class _BottomWidgetState extends State<BottomWidget> {
  bool get isDownload =>
      widget.type == ComicEntryType.download ||
      widget.type == ComicEntryType.historyAndDownload;

  JumpChapter get jumpChapter => widget.jumpChapter;

  final Duration _animationDuration = const Duration(milliseconds: 300); // 动画时长

  late ComicEntryType tempType;
  late String comicId;
  List<UnifiedComicChapterRef> chapterRefs = [];

  @override
  void initState() {
    super.initState();

    tempType = widget.type;
    comicId = widget.comicId;
    if (tempType == ComicEntryType.historyAndDownload) {
      tempType = ComicEntryType.download;
    }
    if (tempType == ComicEntryType.history) {
      tempType = ComicEntryType.normal;
    }
    chapterRefs = resolveUnifiedComicChapters(widget.comicInfo, widget.from);
  }

  @override
  Widget build(BuildContext context) {
    final isMenuVisible = context.select(
      (ReaderCubit cubit) => cubit.state.isMenuVisible,
    );
    // 墨水屏：控制条滑动的中间帧只会攒成残影，直接出图。
    final animationDuration =
        context.select(
          (GlobalSettingCubit cubit) => cubit.state.eInkSetting.enabled,
        )
        ? Duration.zero
        : _animationDuration;
    final bottomSafeHeight = context.bottomSafeHeight;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isWideLayout = screenWidth >= 840;
    final topMaxWidth = (screenWidth * 0.56).clamp(380.0, 720.0).toDouble();
    final bottomMaxWidth = (screenWidth * (screenWidth >= 1200 ? 0.62 : 0.74))
        .clamp(560.0, 980.0)
        .toDouble();
    final isCompactLayout =
        screenWidth >= 600 && MediaQuery.sizeOf(context).height <= 600;

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: IgnorePointer(
        ignoring: !isMenuVisible,
        child: AnimatedSlide(
          duration: animationDuration,
          curve: Curves.easeOutCubic,
          offset: isMenuVisible ? Offset.zero : const Offset(0, 1),
          child: Padding(
            padding: EdgeInsets.only(bottom: 6 + bottomSafeHeight),
            child: isCompactLayout
                ? _buildCompactControls(
                    maxWidth: bottomMaxWidth,
                    isWideLayout: isWideLayout,
                  )
                : _buildRegularControls(
                    topMaxWidth: topMaxWidth,
                    bottomMaxWidth: bottomMaxWidth,
                    isWideLayout: isWideLayout,
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildRegularControls({
    required double topMaxWidth,
    required double bottomMaxWidth,
    required bool isWideLayout,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Align(
            alignment: Alignment.center,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: isWideLayout ? topMaxWidth : double.infinity,
              ),
              child: _buildControlButtons(),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Align(
            alignment: Alignment.center,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: isWideLayout ? bottomMaxWidth : double.infinity,
              ),
              child: Row(children: [widget.sliderWidget]),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCompactControls({
    required double maxWidth,
    required bool isWideLayout,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Align(
        alignment: Alignment.center,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: isWideLayout ? maxWidth : double.infinity,
          ),
          child: Row(
            children: [
              _buildControlButtons(),
              const SizedBox(width: 12),
              widget.sliderWidget,
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControlButtons() {
    final c = context.calm;
    Widget divider() => Container(
      width: 1,
      height: 18,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: c.borderStrong,
    );

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        boxShadow: c.shadowMd,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: c.surface.withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: c.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ChapterNavigationButton(
                  icon: Icons.skip_previous_rounded,
                  tooltip: t.reader.previousChapter,
                  isEnabled: jumpChapter.havePrev,
                  onTap: () => _jumpToChapter(true),
                ),
                divider(),
                FloatingActionIconButton(
                  icon: Icons.home_rounded,
                  tooltip: t.reader.backToHome,
                  onPressed: () => popToRoot(context),
                ),
                const SizedBox(width: 2),
                FloatingActionIconButton(
                  icon: Icons.list_alt_rounded,
                  tooltip: t.reader.selectChapter,
                  isEnabled: chapterRefs.isNotEmpty,
                  onPressed: _selectJumpChapter,
                ),
                const SizedBox(width: 2),
                FloatingActionIconButton(
                  icon: Icons.tune_rounded,
                  tooltip: t.reader.settings,
                  onPressed: _openSettingsPanel,
                ),
                divider(),
                ChapterNavigationButton(
                  icon: Icons.skip_next_rounded,
                  tooltip: t.reader.nextChapter,
                  isEnabled: jumpChapter.haveNext,
                  onTap: () => _jumpToChapter(false),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openSettingsPanel() {
    final readerCubit = context.read<ReaderCubit>();
    showReaderSettingsSheet(
      context,
      changePageIndex: (int value) {
        readerCubit.updateCurrentSlot(value);
        readerCubit.updateSliderChanged(0.0);
      },
      onLandscapeChanged: widget.onLandscapeChanged,
      onDoublePageModeChanged: widget.onDoublePageModeChanged,
      source: widget.from,
      comicId: widget.comicId,
    );
  }

  Future<void> _jumpToChapter(bool isPrev) async {
    final dialogMessage = isPrev
        ? t.reader.previousChapter
        : t.reader.nextChapter;
    final result = await buttonDialog(
      context,
      t.reader.jumpToChapterTitle,
      t.reader.jumpToChapterMessage(chapter: dialogMessage),
    );
    if (!result) return;
    if (!mounted) return;
    jumpChapter.jumpToChapter(context, isPrev);
  }

  Future<void> _selectJumpChapter() async {
    final router = AutoRouter.of(context);
    final initialIndex = jumpChapter.currentChapterIndexIn(chapterRefs);
    final result = await showCalmDialog<UnifiedComicChapterRef>(
      context,
      title: t.reader.selectChapter,
      icon: Icons.list_alt_rounded,
      barrierDismissible: false, // 不允许点击外部区域关闭对话框
      bodyBuilder: (dialogContext) => _ChapterPickerDialog(
        refs: chapterRefs,
        initialIndex: initialIndex,
        onSelected: (ep) => Navigator.of(dialogContext).pop(ep),
      ),
      actionsBuilder: (dialogContext) => [
        CalmButton(
          label: t.common.cancel,
          variant: CalmButtonVariant.ghost,
          onPressed: () => Navigator.of(dialogContext).pop(),
        ),
      ],
    );
    if (result != null && mounted) {
      final chapter = const DownloadChapterAdapter().fromChapterRef(result);
      router.replace(
        ComicReadRoute(
          key: Key(Uuid().v4()),
          comicInfo: widget.comicInfo,
          comicId: comicId,
          type: tempType,
          order: chapter.order,
          chapterId: chapter.id,
          requestId: result.requestId.trim(),
          storageChapterId: result.storageChapterId.trim(),
          logicalKey: chapter.id,
          chapterExtern: Map<String, dynamic>.from(chapter.extern),
          epsNumber: widget.epsNumber,
          from: widget.from,
          stringSelectCubit: context.read<StringSelectCubit>(),
        ),
      );
    }
  }
}

class _ChapterPickerDialog extends StatefulWidget {
  final List<UnifiedComicChapterRef> refs;
  final int initialIndex;
  final ValueChanged<UnifiedComicChapterRef> onSelected;

  const _ChapterPickerDialog({
    required this.refs,
    required this.initialIndex,
    required this.onSelected,
  });

  @override
  State<_ChapterPickerDialog> createState() => _ChapterPickerDialogState();
}

class _ChapterPickerDialogState extends State<_ChapterPickerDialog> {
  // 行高只是估算（章节名可能换行），用于对话框高度与首屏定位；
  // 精确定位靠 _targetKey + ensureVisible。
  static const double _estimatedRowHeight = 34.0;
  static const double _estimatedGroupHeaderHeight = 30.0;
  static const int _maxRevealAttempts = 3;

  GlobalKey? _targetKey;
  late final ScrollController _scrollController;
  int _revealAttempts = 0;

  /// 扁平行：组头（不可点）与章节交错，单组时无组头，与今天一致。
  late final List<_PickerRow> _rows = _buildRows(widget.refs);
  late final int _initialRow = _hasValidInitial
      ? _rows.indexWhere(
          (row) =>
              row is _PickerChapterRow &&
              row.globalIndex == widget.initialIndex,
        )
      : -1;

  bool get _hasValidInitial =>
      widget.initialIndex >= 0 && widget.initialIndex < widget.refs.length;

  static List<_PickerRow> _buildRows(List<UnifiedComicChapterRef> refs) {
    final groups = groupChaptersByTitle<UnifiedComicChapterRef>(
      refs,
      (ref) => ref.groupTitle,
    );
    if (groups.length <= 1) {
      return [
        for (var i = 0; i < refs.length; i++)
          _PickerChapterRow(ref: refs[i], globalIndex: i),
      ];
    }
    final rows = <_PickerRow>[];
    var globalIndex = 0;
    for (final group in groups) {
      rows.add(_PickerGroupRow(title: group.title));
      for (final ref in group.items) {
        rows.add(_PickerChapterRow(ref: ref, globalIndex: globalIndex));
        globalIndex++;
      }
    }
    return rows;
  }

  double _estimatedOffsetForRow(int row) {
    var offset = 0.0;
    for (var i = 0; i < row && i < _rows.length; i++) {
      offset += _rows[i] is _PickerGroupRow
          ? _estimatedGroupHeaderHeight
          : _estimatedRowHeight;
    }
    return offset;
  }

  @override
  void initState() {
    super.initState();
    // 原来是 List.generate(refs.length) 建 N 个 GlobalKey，
    // 全局注册 + 阻碍复用；现在只给当前章节留 1 个。
    if (_initialRow >= 0) {
      _targetKey = GlobalKey();
      _scrollController = ScrollController(
        initialScrollOffset: _estimatedOffsetForRow(_initialRow),
      );
    } else {
      _scrollController = ScrollController();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealInitial());
  }

  /// 直接定位到当前章节（无动画）。目标行还没建出来时先跳到估算位置，
  /// 下一帧再精确定位；超过次数就停在估算位置附近，不死循环。
  void _revealInitial() {
    if (!mounted || _revealAttempts >= _maxRevealAttempts) return;
    _revealAttempts++;
    final key = _targetKey;
    if (key == null || _initialRow < 0) return;
    final targetContext = key.currentContext;
    if (targetContext == null) {
      if (_scrollController.hasClients) {
        final max = _scrollController.position.maxScrollExtent;
        _scrollController.jumpTo(
          _estimatedOffsetForRow(_initialRow).clamp(0.0, max),
        );
      }
      WidgetsBinding.instance.addPostFrameCallback((_) => _revealInitial());
      return;
    }
    Scrollable.ensureVisible(
      targetContext,
      alignment: 0.5,
      alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    // 定高（按估算行高撑，封顶 50% 屏高）：ListView 高度有界，
    // 不用 shrinkWrap 也能懒加载，只建可视行。
    final screenSize = MediaQuery.sizeOf(context);
    final maxHeight = screenSize.height * 0.5;
    final listHeight = (_estimatedOffsetForRow(_rows.length) + 16).clamp(
      120.0,
      maxHeight,
    );
    // 桌面端别撑满：最多 440，手机上占 90% 屏宽。
    final listWidth = (screenSize.width * 0.9).clamp(0.0, 440.0).toDouble();

    return SizedBox(
      width: listWidth,
      height: listHeight,
      child: ListView.builder(
        controller: _scrollController,
        itemCount: _rows.length,
        itemBuilder: (context, i) {
          final row = _rows[i];
          if (row is _PickerGroupRow) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              child: CalmSectionHeader(
                title: chapterGroupDisplayTitle(
                  row.title,
                  t.comicInfo.untitledGroup,
                ),
              ),
            );
          }
          final chapterRow = row as _PickerChapterRow;
          final ref = chapterRow.ref;
          final isCurrent = i == _initialRow;
          return Container(
            key: isCurrent ? _targetKey : null,
            margin: const EdgeInsets.symmetric(vertical: 1),
            decoration: BoxDecoration(
              color: isCurrent ? c.accentSoft : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: CalmListTile(
              title: ref.name,
              onTap: () => widget.onSelected(ref),
              trailing: isCurrent
                  ? Icon(Icons.check_circle_rounded, size: 16, color: c.accent)
                  : null,
            ),
          );
        },
      ),
    );
  }
}

sealed class _PickerRow {
  const _PickerRow();
}

/// 组头行（不可点）。单组时无此行。
class _PickerGroupRow extends _PickerRow {
  const _PickerGroupRow({required this.title});

  final String title;
}

/// 章节行，[globalIndex] 对应 refs 下标（用于定位当前章）。
class _PickerChapterRow extends _PickerRow {
  const _PickerChapterRow({required this.ref, required this.globalIndex});

  final UnifiedComicChapterRef ref;
  final int globalIndex;
}

class ChapterNavigationButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool isEnabled;
  final VoidCallback onTap;

  const ChapterNavigationButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.isEnabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return _CalmCircleIconButton(
      tooltip: tooltip,
      isEnabled: isEnabled,
      onPressed: onTap,
      icon: icon,
    );
  }
}

class FloatingActionIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool isEnabled;
  final VoidCallback onPressed;

  const FloatingActionIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.isEnabled = true,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return _CalmCircleIconButton(
      tooltip: tooltip,
      isEnabled: isEnabled,
      onPressed: onPressed,
      icon: icon,
    );
  }
}

/// 阅读器操作栏上的轻盈透明图标按钮：静息态无底色，避免「胶囊套圆钮」的视觉拥挤；
/// 悬停与按下时给出柔和圆底反馈，禁用态压暗。
class _CalmCircleIconButton extends StatefulWidget {
  final String tooltip;
  final bool isEnabled;
  final VoidCallback onPressed;
  final IconData icon;

  const _CalmCircleIconButton({
    required this.tooltip,
    required this.isEnabled,
    required this.onPressed,
    required this.icon,
  });

  @override
  State<_CalmCircleIconButton> createState() => _CalmCircleIconButtonState();
}

class _CalmCircleIconButtonState extends State<_CalmCircleIconButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    final enabled = widget.isEnabled;
    final bg = !enabled
        ? Colors.transparent
        : _pressed
        ? c.accentSoft
        : _hovered
        ? c.surfaceHover
        : Colors.transparent;
    final fg = !enabled
        ? c.text3.withValues(alpha: 0.45)
        : (_hovered || _pressed)
        ? c.accent
        : c.text2;

    Widget child = MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: enabled ? (_) => setState(() => _hovered = true) : null,
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? widget.onPressed : null,
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: _pressed ? 0.92 : 1.0,
          duration: const Duration(milliseconds: 100),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            width: 38,
            height: 36,
            decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Icon(widget.icon, size: 19, color: fg),
          ),
        ),
      ),
    );

    if (widget.tooltip.isNotEmpty) {
      child = Tooltip(message: widget.tooltip, child: child);
    }
    return child;
  }
}
