import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;
import 'package:zephyr/cubit/string_select.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/network/http/plugin/qjs_download_runtime.dart';
import 'package:zephyr/page/comic_info/comic_info.dart';
import 'package:zephyr/page/comic_info/json/normal/normal_comic_all_info.dart'
    show ComicInfo, ComicInfoActionItem;
import 'package:zephyr/cubit/plugin_registry_cubit.dart';
import 'package:zephyr/src/rust/api/simple.dart';
import 'package:zephyr/type/enum.dart';
import 'package:zephyr/type/pipe.dart';
import 'package:zephyr/ui/ui.dart';
import 'package:zephyr/util/storage/get_path.dart';
import 'package:zephyr/util/text/chinese_convert.dart';
import 'package:zephyr/widgets/picture_bloc/models/picture_info.dart';
import 'package:zephyr/widgets/toast.dart';

class ComicParticularsWidget extends StatelessWidget {
  final ComicInfo comicInfo;
  final String from;
  final ComicEntryType type;
  final VoidCallback? onContinueRead;
  final VoidCallback? onCoverTap;

  const ComicParticularsWidget({
    super.key,
    required this.comicInfo,
    required this.from,
    required this.type,
    this.onContinueRead,
    this.onCoverTap,
  });

  @override
  Widget build(BuildContext context) {
    final pictureInfo = PictureInfo(
      from: from,
      url: comicInfo.cover.url,
      path: comicInfo.cover.path,
      chapterId: '',
      pictureType: PictureType.cover,
      cartoonId: comicInfo.id,
    );

    return SizedBox(
      width: double.infinity,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 520;
          final info = _InfoColumn(
            comicInfo: comicInfo,
            from: from,
            type: type,
            onContinueRead: onContinueRead,
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Align(
                  child: _framedCover(
                    context,
                    Cover(
                      pictureInfo: pictureInfo,
                      height: 220,
                      borderRadius: 16,
                      onTap: onCoverTap,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                info,
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _framedCover(
                context,
                Cover(
                  pictureInfo: pictureInfo,
                  height: 230,
                  borderRadius: 16,
                  onTap: onCoverTap,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(child: info),
            ],
          );
        },
      ),
    );
  }

  /// 封面外框：柔和弥散投影，让封面从画布上“浮”起来一格。
  Widget _framedCover(BuildContext context, Widget cover) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: context.calm.shadowMd,
      ),
      child: cover,
    );
  }
}

class _InfoColumn extends StatefulWidget {
  const _InfoColumn({
    required this.comicInfo,
    required this.from,
    required this.type,
    required this.onContinueRead,
  });

  final ComicInfo comicInfo;
  final String from;
  final ComicEntryType type;
  final VoidCallback? onContinueRead;

  @override
  State<_InfoColumn> createState() => _InfoColumnState();
}

class _InfoColumnState extends State<_InfoColumn> {
  int? _storageSize;

  @override
  void initState() {
    super.initState();
    if (widget.type == ComicEntryType.download) {
      _calculateStorageSize();
    }
  }

  Future<void> _calculateStorageSize() async {
    try {
      final downloadPath = await getDownloadPath();
      int totalSize = 0;
      var foundDirectory = false;

      for (final storagePath in await _storageRoots(downloadPath)) {
        final dir = Directory(storagePath);
        try {
          if (!await dir.exists()) continue;
          foundDirectory = true;
          await for (final entity in dir.list(
            recursive: true,
            followLinks: false,
          )) {
            if (entity is File) {
              try {
                totalSize += await entity.length();
              } on FileSystemException {
                continue;
              }
            }
          }
        } on FileSystemException {
          // 某个历史目录不可访问时，继续统计其他兼容目录。
        }
      }

      if (foundDirectory && mounted) {
        setState(() => _storageSize = totalSize);
      }
    } catch (e, st) {
      logger.e(e, stackTrace: st);
      // ignore errors
    }
  }

  Future<List<String>> _storageRoots(String downloadPath) async {
    final roots = <String, String>{};
    void addRoot(String path) {
      final normalized = p.normalize(p.absolute(path));
      final key = Platform.isWindows ? normalized.toLowerCase() : normalized;
      roots[key] = normalized;
    }

    final comicId = widget.comicInfo.id.trim();
    final sourceCandidates = <String>{
      widget.from.trim(),
      normalizePluginId(widget.from),
    }..removeWhere((source) => source.isEmpty);

    for (final source in sourceCandidates) {
      // 当前下载布局：hash(from)/hash(cartoonId)。
      try {
        addRoot(
          p.join(
            downloadPath,
            encodePath(path: source),
            encodePath(path: comicId),
          ),
        );
      } catch (e, st) {
        logger.e(e, stackTrace: st);
        // Rust 编码服务尚未就绪时，仍继续统计历史目录。
      }

      // c703e334 产生的旧编码目录。
      try {
        addRoot(
          p.join(downloadPath, source, 'original', encodePath(path: comicId)),
        );
      } catch (_) {}

      // 更早的未编码目录。
      addRoot(p.join(downloadPath, source, 'original', comicId));
    }

    // 旧数据库记录可能保存了当时实际使用的绝对 storageRoot。
    for (final source in sourceCandidates) {
      // 只取 storageRoot：不把 chapters/detailJson 这些大列拉进 UI isolate。
      final rows = await database.downloads.getShelfByKeys([
        '$source:$comicId',
      ]);
      final storedRoot = rows.isEmpty ? '' : rows.first.storageRoot.trim();
      if (storedRoot.isNotEmpty && p.isAbsolute(storedRoot)) {
        addRoot(storedRoot);
      }
    }

    return roots.values.toList();
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  @override
  Widget build(BuildContext context) {
    final displaySource = context.select<PluginRegistryCubit, String>(
      (cubit) => cubit.state.pluginName(_normalizePluginId(widget.from)),
    );
    final c = context.calm;
    final titleStyle = TextStyle(
      fontSize: 19,
      fontWeight: FontWeight.w600,
      height: 1.25,
      letterSpacing: -0.2,
      color: c.text,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _InfoPill(icon: Icons.extension_outlined, label: displaySource),
            if (_storageSize != null)
              _InfoPill(
                icon: Icons.storage_rounded,
                label: _formatFileSize(_storageSize!),
              ),
          ],
        ),
        const SizedBox(height: 12),
        SelectableText(
          widget.comicInfo.title.let(convertChineseForDisplay),
          style: titleStyle,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: widget.comicInfo.titleMeta
              .map((item) => _MetaPill(item: item))
              .toList(),
        ),
        _ContinueReadingBanner(onContinueRead: widget.onContinueRead),
      ],
    );
  }

  String _normalizePluginId(String raw) {
    var value = raw.trim();
    while (value.length >= 2 && value.startsWith('(') && value.endsWith(')')) {
      value = value.substring(1, value.length - 1).trim();
    }
    return value;
  }
}

class _ContinueReadingBanner extends StatelessWidget {
  const _ContinueReadingBanner({required this.onContinueRead});

  final VoidCallback? onContinueRead;

  @override
  Widget build(BuildContext context) {
    return BlocSelector<StringSelectCubit, String, String>(
      selector: (state) => state,
      builder: (context, stringSelectDate) {
        if (stringSelectDate.isEmpty) {
          return const SizedBox.shrink();
        }
        final c = context.calm;
        return Padding(
          padding: const EdgeInsets.only(top: 14),
          child: MouseRegion(
            cursor: onContinueRead != null
                ? SystemMouseCursors.click
                : SystemMouseCursors.basic,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onContinueRead,
              child: SizedBox(
                width: double.infinity,
                child: CalmCard(
                  radius: 14,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  color: c.accentSoft,
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: c.surface.withValues(alpha: 0.72),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.history_rounded,
                          size: 17,
                          color: c.accent,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              t.comicInfo.readHistory,
                              textHeightBehavior: kCalmTextHeightBehavior,
                              strutStyle: calmStrut(10.5),
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: c.accent,
                                height: 1.2,
                                leadingDistribution:
                                    TextLeadingDistribution.even,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              stringSelectDate,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textHeightBehavior: kCalmTextHeightBehavior,
                              strutStyle: calmStrut(12),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: c.text,
                                height: 1.2,
                                leadingDistribution:
                                    TextLeadingDistribution.even,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (onContinueRead != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          t.comicInfo.continueRead,
                          textHeightBehavior: kCalmTextHeightBehavior,
                          strutStyle: calmStrut(11.5),
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: c.accent,
                            height: 1.2,
                            leadingDistribution: TextLeadingDistribution.even,
                          ),
                        ),
                        const SizedBox(width: 2),
                        Icon(
                          Icons.play_arrow_rounded,
                          size: 18,
                          color: c.accent,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({required this.item});

  final ComicInfoActionItem item;

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    final pill = Container(
      constraints: const BoxConstraints(minHeight: 26),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Center(
        widthFactor: 1.0,
        heightFactor: 1.0,
        child: Text(
          item.name.let(convertChineseForDisplay),
          textAlign: TextAlign.center,
          softWrap: true,
          textHeightBehavior: kCalmTextHeightBehavior,
          strutStyle: calmStrut(11.5),
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
            color: c.text2,
            height: 1.2,
            leadingDistribution: TextLeadingDistribution.even,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );

    return GestureDetector(
      onLongPress: () async {
        final copyText = item.onLongPress?.trim().isNotEmpty == true
            ? item.onLongPress!.trim()
            : item.name;
        await Clipboard.setData(ClipboardData(text: copyText));
        showSuccessToast(
          t.comicInfo.copied(label: item.name.let(convertChineseForDisplay)),
        );
      },
      child: pill,
    );
  }
}

/// 头部信息胶囊：插件来源 / 本地占用，柔底无硬边框。
class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 12, color: c.text3),
          const SizedBox(width: 5),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textHeightBehavior: kCalmTextHeightBehavior,
            strutStyle: calmStrut(11),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: c.text2,
              height: 1.2,
              leadingDistribution: TextLeadingDistribution.even,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
