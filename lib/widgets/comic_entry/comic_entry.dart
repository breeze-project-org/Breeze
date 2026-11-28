import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/ui/ui.dart';
import 'package:zephyr/widgets/comic_entry/models/models.dart';
import 'package:zephyr/widgets/comic_simplify_entry/cover.dart';
import 'package:zephyr/widgets/toast.dart';

import 'package:zephyr/main.dart';
import 'package:zephyr/network/http/picture/picture.dart';
import 'package:zephyr/config/router/router.gr.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/type/enum.dart';

class ComicEntryWidget extends StatelessWidget {
  const ComicEntryWidget({
    super.key,
    required this.comic,
    this.type = ComicEntryType.normal,
    this.refresh,
    this.pictureType,
  });

  final UnifiedComicListItem comic;
  final ComicEntryType type;
  final VoidCallback? refresh;
  final PictureType? pictureType;

  static const double _coverWidth = 100;
  static const double _coverHeight = 133;
  static const double _radius = 14;

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    final statText = _buildStatText();

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        context.pushRoute(
          ComicInfoRoute(comicId: comic.id, type: type, from: comic.from),
        );
      },
      onLongPress: type == ComicEntryType.normal
          ? null
          : () => _showDeleteDialog(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: CalmCard(
          padding: EdgeInsets.zero,
          radius: _radius,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(_radius),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CoverWidget(
                  fileServer: comic.cover.url,
                  path: comic.cover.cachePath,
                  id: comic.id,
                  pictureType: pictureType ?? PictureType.cover,
                  from: comic.from,
                  roundedCorner: false,
                  width: _coverWidth,
                  height: _coverHeight,
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        minHeight: _coverHeight,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                comic.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                  color: c.text,
                                  height: 1.3,
                                ),
                              ),
                              if (comic.primaryText.isNotEmpty) ...[
                                const SizedBox(height: 5),
                                Text(
                                  comic.primaryText,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textHeightBehavior: kCalmTextHeightBehavior,
                                  strutStyle: calmStrut(11.5),
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w500,
                                    color: c.accent,
                                    height: 1.2,
                                    leadingDistribution:
                                        TextLeadingDistribution.even,
                                  ),
                                ),
                              ],
                              if (comic.secondaryText.isNotEmpty) ...[
                                const SizedBox(height: 5),
                                Text(
                                  comic.secondaryText,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: c.text2,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                              if (comic.updatedAtText.isNotEmpty) ...[
                                const SizedBox(height: 5),
                                Text(
                                  t.comicEntry.updatedAt(
                                    time: comic.updatedAtText,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textHeightBehavior: kCalmTextHeightBehavior,
                                  strutStyle: calmStrut(10.5),
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    color: c.text3,
                                    height: 1.2,
                                    leadingDistribution:
                                        TextLeadingDistribution.even,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                          Wrap(
                            spacing: 8,
                            runSpacing: 5,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              CalmBadge(
                                label: comic.finished
                                    ? t.comicEntry.finished
                                    : t.comicEntry.ongoing,
                                dot: true,
                                tone: comic.finished
                                    ? CalmBadgeTone.success
                                    : CalmBadgeTone.tonal,
                              ),
                              if (statText.isNotEmpty)
                                Text(
                                  statText,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textHeightBehavior: kCalmTextHeightBehavior,
                                  strutStyle: calmStrut(10.5),
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    color: c.text3,
                                    height: 1.2,
                                    leadingDistribution:
                                        TextLeadingDistribution.even,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
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

  String _buildStatText() {
    final stats = <String>[];
    if (comic.likesCount > 0) {
      stats.add(t.comicEntry.likes(count: comic.likesCount));
    }
    if (comic.viewsCount > 0) {
      stats.add(t.comicEntry.views(count: comic.viewsCount));
    }
    return stats.join('  ');
  }

  Future<void> _showDeleteDialog(BuildContext context) async {
    final (title, content) = _dialogContent();
    if (title.isEmpty) {
      return;
    }

    final confirmed = await showCalmDialog<bool>(
      context,
      title: title,
      icon: Icons.delete_outline_rounded,
      tone: CalmTone.danger,
      bodyBuilder: (dialogContext) => Text(
        content,
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
    if (confirmed == true) {
      await _handleDelete();
    }
  }

  (String, String) _dialogContent() {
    return switch (type) {
      ComicEntryType.favorite => (
        t.comicEntry.deleteFavorite,
        t.comicEntry.deleteFavoriteConfirm(title: comic.title),
      ),
      ComicEntryType.history => (
        t.comicEntry.deleteHistory,
        t.comicEntry.deleteHistoryConfirm(title: comic.title),
      ),
      ComicEntryType.download => (
        t.comicEntry.deleteDownload,
        t.comicEntry.deleteDownloadConfirm(title: comic.title),
      ),
      _ => ('', ''),
    };
  }

  Future<void> _handleDelete() async {
    try {
      if (type == ComicEntryType.favorite) {
        await _deleteFavorite();
      } else if (type == ComicEntryType.history) {
        await _deleteHistory();
      } else if (type == ComicEntryType.download) {
        await _deleteDownload();
      }
      refresh?.call();
    } catch (e, s) {
      logger.e('删除失败', error: e, stackTrace: s);
      showErrorToast(t.comicEntry.deleteFailed);
    }
  }

  Future<void> _deleteFavorite() async {
    final uniqueKey = '${comic.from.trim()}:${comic.id}';
    await database.favorites.markDeletedByKey(uniqueKey);
  }

  Future<void> _deleteHistory() async {
    final uniqueKey = '${comic.from.trim()}:${comic.id}';
    await database.histories.markDeletedByKey(uniqueKey);
  }

  Future<void> _deleteDownload() async {
    final uniqueKey = '${comic.from.trim()}:${comic.id}';
    final temp = await database.downloads.getByKey(uniqueKey);

    if (temp != null) {
      await database.downloads.removeById(temp.id);
    }

    await _deleteDownloadDirectory();
  }

  Future<void> _deleteDownloadDirectory() async {
    await deleteComicDownloadDirectory(comic.from, comic.id);
  }
}
