import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/comic_info/method/export_comic.dart';
import 'package:zephyr/type/enum.dart';
import 'package:zephyr/ui/ui.dart';
import 'package:zephyr/util/storage/get_path.dart';
import 'package:zephyr/util/ohos/platform.dart';
import 'package:zephyr/util/ohos/file_bridge.dart';
import 'package:zephyr/util/system/permission.dart';
import 'package:zephyr/widgets/comic_simplify_entry/comic_simplify_entry_info.dart';
import 'package:zephyr/main.dart';

/// 批量导出选中的已下载漫画。
///
/// 返回成功导出的数量。导出失败的项目会被跳过，不会中断后续导出。
Future<int> batchExportComics({
  required BuildContext context,
  required List<ComicSimplifyEntryInfo> comics,
}) async {
  if (comics.isEmpty) return 0;

  final exportType = await _pickBatchExportType(context);
  if (exportType == null) return 0;

  String? stagingRoot;
  String? exportRoot;
  if (isOhos) {
    // OHOS(非 PC/2in1)不支持目录选择；导出到缓存后逐个走系统“另存为”。
    stagingRoot = await _createBatchStagingDir();
    exportRoot = stagingRoot;
  } else {
    exportRoot = await _resolveBatchExportDirectory();
  }
  if (exportRoot == null || exportRoot.trim().isEmpty) return 0;

  var success = 0;
  try {
    for (final comic in comics) {
      final from = comic.from.trim();
      if (from.isEmpty) continue;

      String? exportPath;
      if (exportType == ExportType.folder) {
        exportPath = exportRoot;
      } else {
        final safeTitle = _sanitizeFileName(
          comic.title.trim().isEmpty ? comic.id : comic.title,
        );
        exportPath = p.join(exportRoot, '$safeTitle.zip');
      }

      try {
        await exportComic(comic.id, exportType, from, path: exportPath);
        success++;
      } catch (e, st) {
        logger.e(e, stackTrace: st);
        // 继续导出下一本，避免单本失败导致整批中断。
      }
    }

    if (isOhos && success > 0) {
      var saved = 0;
      final entries = await Directory(exportRoot).list().toList();
      for (final entry in entries) {
        if (entry is! File) continue;
        final ok = await saveOhosFileToPicker(
          entry.path,
          suggestedName: p.basename(entry.path),
        );
        if (!ok) break;
        saved++;
      }
      return saved;
    }
    return success;
  } finally {
    if (stagingRoot != null) {
      try {
        await Directory(stagingRoot).delete(recursive: true);
      } catch (_) {}
    }
  }
}

Future<String> _createBatchStagingDir() async {
  final dir = Directory(
    p.join(
      await getCachePath(),
      'batch_export',
      '${DateTime.now().microsecondsSinceEpoch}',
    ),
  );
  await dir.create(recursive: true);
  return dir.path;
}

Future<ExportType?> _pickBatchExportType(BuildContext context) async {
  if (Platform.isIOS || isOhos) return ExportType.zip;
  // CalmUI 自适应弹窗：手机底部抽屉、平板与桌面居中卡片，与全应用选型弹窗一致。
  return showCalmDialog<ExportType>(
    context,
    title: t.bookshelf.batchExportTitle,
    subtitle: t.bookshelf.batchExportSubtitle,
    icon: Icons.ios_share_rounded,
    bodyBuilder: (dialogContext) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CalmListTile(
          leading: Icon(
            Icons.folder_outlined,
            size: 17,
            color: dialogContext.calm.accent,
          ),
          title: t.comicInfo.folder,
          onTap: () => Navigator.of(dialogContext).pop(ExportType.folder),
        ),
        CalmListTile(
          leading: Icon(
            Icons.folder_zip_outlined,
            size: 17,
            color: dialogContext.calm.accent,
          ),
          title: t.comicInfo.zip,
          onTap: () => Navigator.of(dialogContext).pop(ExportType.zip),
        ),
      ],
    ),
    actionsBuilder: (dialogContext) => [
      CalmButton(
        label: t.common.cancel,
        variant: CalmButtonVariant.ghost,
        onPressed: () => Navigator.of(dialogContext).pop(),
      ),
    ],
  );
}

Future<String?> _resolveBatchExportDirectory() async {
  // iOS 无目录选择器，导出到应用 Documents（可在「文件」App 中访问）
  if (Platform.isIOS) {
    return createDownloadDir();
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
  return getDirectoryPath();
}

String _sanitizeFileName(String input) {
  final safe = input
      .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
      .replaceAll(RegExp(r'\s+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  return safe.isEmpty ? 'comic' : safe;
}
