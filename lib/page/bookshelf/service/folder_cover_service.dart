import 'package:zephyr/main.dart';
import 'package:zephyr/object_box/model.dart';
import 'package:zephyr/page/bookshelf/method/comic_shelf_resolver.dart';
import 'package:zephyr/widgets/comic_simplify_entry/comic_simplify_entry_info.dart';

/// 文件夹封面候选项：链接 key + 解析后的列表项。
class FolderCoverCandidate {
  const FolderCoverCandidate({
    required this.comicUniqueKey,
    required this.info,
  });

  final String comicUniqueKey;
  final ComicSimplifyEntryInfo info;
}

/// 文件夹封面候选漫画的读取。
///
/// 只列当前文件夹直属的 active 链接，按加入时间倒序；与自动封面
/// （最新加入的一本）保持同一套解析规则。
class FolderCoverService {
  const FolderCoverService._();

  static Future<List<FolderCoverCandidate>> listCandidates(
    ComicFolder folder,
  ) async {
    final links = await database.links.listActiveByFolder(
      folder.syncId,
      folder.typeData,
    );
    if (links.isEmpty) return const <FolderCoverCandidate>[];

    final resolved = await resolveShelfComicsByKeys(folder.type, <String>[
      for (final link in links) link.comicUniqueKey,
    ], database);
    final seen = <String>{};
    final candidates = <FolderCoverCandidate>[];
    for (final link in links) {
      final key = link.comicUniqueKey;
      if (key.isEmpty || !seen.add(key)) continue;
      final comic = resolved[key];
      if (comic == null) continue;
      candidates.add(
        FolderCoverCandidate(comicUniqueKey: key, info: comic.info),
      );
    }
    return candidates;
  }
}
