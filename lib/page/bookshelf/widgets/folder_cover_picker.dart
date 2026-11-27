import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/object_box/model.dart';
import 'package:zephyr/page/bookshelf/service/folder_cover_service.dart';
import 'package:zephyr/widgets/comic_simplify_entry/cover.dart';

/// 封面选择结果。null key 表示恢复“自动”。
class FolderCoverChoice {
  const FolderCoverChoice.auto() : comicUniqueKey = null;
  const FolderCoverChoice.comic(String this.comicUniqueKey);

  final String? comicUniqueKey;
}

/// 文件夹封面选择弹窗：列出文件夹内直属漫画与“自动”选项。
///
/// 返回 null 表示取消。
Future<FolderCoverChoice?> showFolderCoverPicker(
  BuildContext context, {
  required ComicFolder folder,
}) {
  final candidates = FolderCoverService.listCandidates(folder);
  final currentKey = folder.coverComicUniqueKey?.trim() ?? '';
  return showDialog<FolderCoverChoice>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: Text(t.bookshelf.changeFolderCover),
        content: SizedBox(
          width: 340,
          height: 400,
          child: FutureBuilder<List<FolderCoverCandidate>>(
            future: candidates,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              final comics = snapshot.data ?? const <FolderCoverCandidate>[];
              return ListView.builder(
                itemCount: comics.isEmpty ? 2 : comics.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Container(
                        width: 40,
                        height: 54,
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(
                          Icons.autorenew_rounded,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      title: Text(t.bookshelf.folderCoverAuto),
                      trailing: currentKey.isEmpty
                          ? const Icon(Icons.check_rounded)
                          : null,
                      onTap: () =>
                          Navigator.of(dialogContext)
                              .pop(const FolderCoverChoice.auto()),
                    );
                  }
                  if (comics.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 48),
                      child: Text(
                        t.bookshelf.folderCoverEmpty,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                    );
                  }
                  final candidate = comics[index - 1];
                  final info = candidate.info;
                  final selected = currentKey == candidate.comicUniqueKey;
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: CoverWidget(
                      fileServer: info.fileServer,
                      path: info.path,
                      id: info.id,
                      pictureType: info.pictureType,
                      from: info.from,
                      width: 40,
                      height: 54,
                    ),
                    title: Text(
                      info.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: selected ? const Icon(Icons.check_rounded) : null,
                    onTap: () => Navigator.of(dialogContext)
                        .pop(FolderCoverChoice.comic(candidate.comicUniqueKey)),
                  );
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(t.common.cancel),
          ),
        ],
      );
    },
  );
}
