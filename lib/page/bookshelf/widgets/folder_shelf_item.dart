import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/object_box/model.dart';
import 'package:zephyr/type/pipe.dart';
import 'package:zephyr/ui/ui.dart';
import 'package:zephyr/util/text/chinese_convert.dart';
import 'package:zephyr/widgets/comic_simplify_entry/comic_simplify_entry.dart'
    show kComicCardBorderRadius;
import 'package:zephyr/widgets/comic_simplify_entry/comic_simplify_entry_info.dart';
import 'package:zephyr/widgets/comic_simplify_entry/cover.dart';

/// 书架里的文件夹条目（CalmUI 版）。
///
/// 网格态：轻盈浮空卡片（`c.surface` + `shadowSm`）拼封面 + 底部信息条，
/// 选中时用 `c.accent` 描边与勾选圆标；详情态：与漫画详情行同高的紧凑横行。
class FolderShelfItem extends StatelessWidget {
  const FolderShelfItem({
    super.key,
    required this.folder,
    this.onTap,
    this.onLongPress,
    this.onSecondaryTapDown,
    this.selectionMode = false,
    this.isSelected = false,
    this.detailed = false,
    this.comicCount,
    this.coverInfo,
  });

  final ComicFolder folder;
  final VoidCallback? onTap;
  final GestureLongPressStartCallback? onLongPress;
  final GestureTapDownCallback? onSecondaryTapDown;
  final bool selectionMode;
  final bool isSelected;

  /// 详情模式：横行样式，对齐漫画详情行（同高、同底色、小图标 + 标题 + 数量）。
  final bool detailed;

  /// 文件夹漫画总数（含所有子孙子文件夹）；null 时不显示数量徽章。
  final int? comicCount;

  /// 文件夹封面用的漫画；null 时回退到文件夹图标。
  final ComicSimplifyEntryInfo? coverInfo;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          onLongPressStart: onLongPress,
          onSecondaryTapDown: onSecondaryTapDown,
          child: detailed
              ? _buildDetailedRow(context, constraints.maxWidth)
              : _buildGridCard(context, constraints.maxWidth),
        );
      },
    );
  }

  /// 网格卡片：固定宽高比（宽 = 列宽、高 = 宽 / 0.75），封面 + 底部信息条。
  Widget _buildGridCard(BuildContext context, double width) {
    final c = context.calm;
    final height = width / 0.75;
    final radius = BorderRadius.circular(kComicCardBorderRadius);
    final count = comicCount;

    return SizedBox(
      width: width,
      height: height,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: radius,
          boxShadow: isSelected ? c.shadowMd : c.shadowSm,
        ),
        // 描边用 foregroundDecoration：普通 decoration 的边框会被封面盖住。
        child: Container(
          foregroundDecoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(
              color: isSelected ? c.accent : c.border,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  // 封面区实际尺寸由信息条高度反推，交给 LayoutBuilder 精确下发：
                  // 传大尺寸会让封面按错误目标框解码并被裁掉一截。
                  child: LayoutBuilder(
                    builder: (context, coverConstraints) {
                      final coverWidth = coverConstraints.maxWidth;
                      final coverHeight = coverConstraints.maxHeight;
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          // 有封面就用封面，否则回退柔和的文件夹图标底。
                          if (coverInfo != null)
                            CoverWidget(
                              key: ValueKey(
                                'folder-cover-${folder.syncId}-'
                                '${coverInfo!.from}:${coverInfo!.id}:${coverInfo!.path}',
                              ),
                              fileServer: coverInfo!.fileServer,
                              path: coverInfo!.path,
                              id: coverInfo!.id,
                              pictureType: coverInfo!.pictureType,
                              from: coverInfo!.from,
                              roundedCorner: false,
                              width: coverWidth,
                              height: coverHeight,
                            )
                          else
                            Container(
                              color: isSelected ? c.accentSoft : c.surface2,
                              alignment: Alignment.center,
                              child: Icon(
                                Icons.folder_rounded,
                                size: coverWidth * 0.34,
                                color: isSelected ? c.accent : c.text3,
                              ),
                            ),
                          // 封面模式下左上角保留小文件夹标记，避免和漫画卡片混淆。
                          if (coverInfo != null)
                            Positioned(
                              top: 6,
                              left: 6,
                              child: Container(
                                width: 22,
                                height: 22,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: c.surface.withValues(alpha: 0.92),
                                  borderRadius: BorderRadius.circular(7),
                                  boxShadow: c.shadowSm,
                                ),
                                child: Icon(
                                  Icons.folder_rounded,
                                  size: 13,
                                  color: c.accent,
                                ),
                              ),
                            ),
                          // 选择指示器：常驻 + 缩放淡入，进入多选模式时不凭空弹出。
                          Positioned(
                            top: 6,
                            right: 6,
                            child: AnimatedScale(
                              scale: selectionMode ? 1.0 : 0.0,
                              duration: const Duration(milliseconds: 180),
                              curve: Curves.easeOutCubic,
                              child: AnimatedOpacity(
                                opacity: selectionMode ? 1.0 : 0.0,
                                duration: const Duration(milliseconds: 180),
                                curve: Curves.easeOutCubic,
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 180),
                                  width: 26,
                                  height: 26,
                                  decoration: BoxDecoration(
                                    color: isSelected ? c.accent : c.surface,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: c.surface,
                                      width: 2,
                                    ),
                                    boxShadow: c.shadowSm,
                                  ),
                                  child: AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 180),
                                    child: Icon(
                                      isSelected
                                          ? Icons.check_rounded
                                          : Icons
                                                .radio_button_unchecked_rounded,
                                      key: ValueKey(isSelected),
                                      color: isSelected ? c.accentFg : c.text3,
                                      size: 17,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                // 信息条：不叠在封面上，直接用不透明的 surface 承接文字，
                // 保证浅色 / 深色和任意封面下都有稳定对比度。
                Container(
                  color: c.surface,
                  padding: const EdgeInsets.fromLTRB(7, 5, 7, 6),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        folder.name.let(convertChineseForDisplay),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textHeightBehavior: kCalmTextHeightBehavior,
                        strutStyle: calmStrut(11.5),
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: c.text,
                          height: 1.2,
                          leadingDistribution: TextLeadingDistribution.even,
                        ),
                      ),
                      if (count != null) ...[
                        const SizedBox(height: 3),
                        CalmBadge(
                          label: t.bookshelf.folderComicCount(count: count),
                          tone: CalmBadgeTone.neutral,
                          icon: Icons.menu_book_rounded,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 详情横行：固定高度 64，与漫画行同高；超宽居中限 720。
  ///
  /// 左侧用文件夹小图标代替封面，避免单列下大卡片被拉成巨型方块。
  Widget _buildDetailedRow(BuildContext context, double width) {
    final c = context.calm;
    final count = comicCount;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Tooltip(
        message: folder.name.let(convertChineseForDisplay),
        waitDuration: const Duration(milliseconds: 500),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: width > kDetailRowMaxWidth ? kDetailRowMaxWidth : width,
            ),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                color: isSelected && selectionMode ? c.accentSoft : c.surface,
                borderRadius: BorderRadius.circular(10),
                boxShadow: c.shadowSm,
              ),
              // 同样用 foregroundDecoration 画选中描边：不能被左侧封面盖住。
              foregroundDecoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isSelected && selectionMode ? c.accent : c.border,
                  width: isSelected && selectionMode ? 2 : 1,
                ),
              ),
              padding: const EdgeInsets.all(4),
              child: SizedBox(
                height: 56,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: SizedBox(
                        width: 42,
                        height: 56,
                        child: coverInfo == null
                            ? ColoredBox(
                                color: c.surface2,
                                child: Icon(
                                  Icons.folder_rounded,
                                  size: 24,
                                  color: c.accent,
                                ),
                              )
                            : CoverWidget(
                                fileServer: coverInfo!.fileServer,
                                path: coverInfo!.path,
                                id: coverInfo!.id,
                                pictureType: coverInfo!.pictureType,
                                from: coverInfo!.from,
                                roundedCorner: false,
                                width: 42,
                                height: 56,
                              ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            folder.name.let(convertChineseForDisplay),
                            textHeightBehavior: kCalmTextHeightBehavior,
                            strutStyle: calmStrut(12.5),
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: c.text,
                              height: 1.2,
                              leadingDistribution: TextLeadingDistribution.even,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (count != null) ...[
                            const SizedBox(height: 5),
                            Text(
                              t.bookshelf.folderComicCount(count: count),
                              textHeightBehavior: kCalmTextHeightBehavior,
                              strutStyle: calmStrut(11),
                              style: TextStyle(
                                fontSize: 11,
                                color: c.text3,
                                height: 1.2,
                                leadingDistribution:
                                    TextLeadingDistribution.even,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                    // 右侧常驻 30 宽：选择模式徽章 / 普通模式箭头交叉淡入淡出，
                    // 进入多选模式时不跳变。
                    SizedBox(
                      width: 30,
                      height: 30,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 160),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeOutCubic,
                        transitionBuilder:
                            (Widget child, Animation<double> animation) {
                              return ScaleTransition(
                                scale: animation,
                                child: FadeTransition(
                                  opacity: animation,
                                  child: child,
                                ),
                              );
                            },
                        layoutBuilder:
                            (
                              Widget? currentChild,
                              List<Widget> previousChildren,
                            ) {
                              return Stack(
                                alignment: Alignment.center,
                                children: <Widget>[
                                  ...previousChildren,
                                  ?currentChild,
                                ],
                              );
                            },
                        child: selectionMode
                            ? AnimatedContainer(
                                key: const ValueKey('badge'),
                                duration: const Duration(milliseconds: 160),
                                curve: Curves.easeOutCubic,
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: isSelected ? c.accent : c.surface,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isSelected
                                        ? c.accent
                                        : c.borderStrong,
                                    width: 2,
                                  ),
                                ),
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 160),
                                  child: Icon(
                                    isSelected
                                        ? Icons.check_rounded
                                        : Icons.radio_button_unchecked_rounded,
                                    key: ValueKey(isSelected),
                                    color: isSelected ? c.accentFg : c.text3,
                                    size: 18,
                                  ),
                                ),
                              )
                            : Icon(
                                key: const ValueKey('arrow'),
                                Icons.chevron_right_rounded,
                                color: c.text3,
                              ),
                      ),
                    ),
                    const SizedBox(width: 4),
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
