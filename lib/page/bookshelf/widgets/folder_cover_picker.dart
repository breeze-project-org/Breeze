import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/object_box/model.dart';
import 'package:zephyr/page/bookshelf/service/folder_cover_service.dart';
import 'package:zephyr/ui/ui.dart';
import 'package:zephyr/widgets/comic_simplify_entry/cover.dart';

/// 封面选择结果。null key 表示恢复“自动”。
class FolderCoverChoice {
  const FolderCoverChoice.auto() : comicUniqueKey = null;
  const FolderCoverChoice.comic(String this.comicUniqueKey);

  final String? comicUniqueKey;
}

/// 文件夹封面选择弹窗（CalmUI 版）：列出文件夹内直属漫画与“自动”选项。
///
/// 返回值语义不变：null 表示取消，[FolderCoverChoice.auto] 表示恢复自动封面。
Future<FolderCoverChoice?> showFolderCoverPicker(
  BuildContext context, {
  required ComicFolder folder,
}) {
  final candidates = FolderCoverService.listCandidates(folder);
  final currentKey = folder.coverComicUniqueKey?.trim() ?? '';
  return showCalmDialog<FolderCoverChoice>(
    context,
    title: t.bookshelf.changeFolderCover,
    icon: Icons.image_outlined,
    maxWidth: 380,
    bodyBuilder: (dialogContext) {
      final c = dialogContext.calm;
      // 手机端随视口收敛，桌面端保持 400 上限，长列表在框内滚动。
      final height = math.min(
        400.0,
        MediaQuery.sizeOf(dialogContext).height * 0.6,
      );
      return SizedBox(
        width: double.infinity,
        height: height,
        child: FutureBuilder<List<FolderCoverCandidate>>(
          future: candidates,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CalmLoading());
            }
            final comics = snapshot.data ?? const <FolderCoverCandidate>[];
            final rows = <Widget>[
              _CoverPickerRow(
                title: t.bookshelf.folderCoverAuto,
                selected: currentKey.isEmpty,
                leading: Container(
                  width: 40,
                  height: 54,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: c.surface2,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.autorenew_rounded,
                    size: 20,
                    color: c.accent,
                  ),
                ),
                onTap: () =>
                    Navigator.of(dialogContext)
                        .pop(const FolderCoverChoice.auto()),
              ),
              if (comics.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 14, 6, 6),
                  child: Text(
                    t.bookshelf.folderCoverEmpty,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: c.text3, height: 1.4),
                  ),
                )
              else
                for (final candidate in comics)
                  _CoverPickerRow(
                    title: candidate.info.title,
                    selected: currentKey == candidate.comicUniqueKey,
                    leading: CoverWidget(
                      fileServer: candidate.info.fileServer,
                      path: candidate.info.path,
                      id: candidate.info.id,
                      pictureType: candidate.info.pictureType,
                      from: candidate.info.from,
                      width: 40,
                      height: 54,
                    ),
                    onTap: () => Navigator.of(dialogContext)
                        .pop(FolderCoverChoice.comic(candidate.comicUniqueKey)),
                  ),
            ];
            return ListView(padding: EdgeInsets.zero, children: rows);
          },
        ),
      );
    },
    actionsBuilder: (dialogContext) => [
      CalmButton(
        label: t.common.cancel,
        variant: CalmButtonVariant.ghost,
        onPressed: () => Navigator.of(dialogContext).pop(),
      ),
    ],
  );
}

/// 封面候选行：左封面缩略图 + 标题 + 选中勾。选中态用柔和高亮底。
class _CoverPickerRow extends StatelessWidget {
  const _CoverPickerRow({
    required this.title,
    required this.leading,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final Widget leading;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: selected ? c.accentSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: CalmListTile(
        title: title,
        leading: leading,
        onTap: onTap,
        trailing: selected
            ? Icon(Icons.check_rounded, size: 17, color: c.accent)
            : null,
      ),
    );
  }
}
