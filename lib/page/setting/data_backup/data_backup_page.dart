import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:file_selector/file_selector.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:zephyr/main.dart';
import 'package:zephyr/page/setting/common/setting_ui.dart';
import 'package:zephyr/service/update/check_update.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/util/storage/get_path.dart';
import 'package:zephyr/util/ohos/platform.dart';
import 'package:zephyr/util/ohos/file_bridge.dart';
import 'package:zephyr/util/system/permission.dart';
import 'package:zephyr/widgets/toast.dart';

import 'package:zephyr/page/setting/data_backup/method.dart';

@RoutePage()
class DataBackupPage extends StatefulWidget {
  const DataBackupPage({super.key});

  @override
  State<DataBackupPage> createState() => _DataBackupPageState();
}

class _DataBackupPageState extends State<DataBackupPage> {
  bool _includeDownloads = true;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return SettingPageShell(
      title: t.dataBackup.title,
      child: ListView(
        padding: kSettingPagePadding,
        children: [
          settingSectionTitle(
            context,
            t.dataBackup.exportSection,
            icon: Icons.file_upload_outlined,
          ),
          settingCardGroup([
            settingSwitchTile(
              icon: Icons.folder_outlined,
              title: t.dataBackup.includeDownloads,
              subtitle: t.dataBackup.includeDownloadsSubtitle,
              value: _includeDownloads,
              onChanged: _busy
                  ? null
                  : (value) => setState(() => _includeDownloads = value),
            ),
            settingActionTile(
              icon: Icons.archive_outlined,
              title: t.dataBackup.exportData,
              subtitle: t.dataBackup.exportDataSubtitle,
              onTap: _busy ? null : _exportData,
            ),
          ]),
          settingSectionTitle(
            context,
            t.dataBackup.importSection,
            icon: Icons.file_download_outlined,
          ),
          settingCardGroup([
            settingActionTile(
              icon: Icons.unarchive_outlined,
              title: t.dataBackup.importData,
              subtitle: t.dataBackup.importDataSubtitle,
              onTap: _busy ? null : _importData,
            ),
          ]),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Future<void> _exportData() async {
    // Android 写入用户自选目录需要「所有文件访问」权限，否则会 Permission denied
    final granted = await requestExportPermission();
    if (!granted) {
      showErrorToast(t.comicInfo.exportPermissionDenied);
      return;
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final fileName = 'Breeze-export-$timestamp.zip';
    late final String zipPath;

    // iOS / OHOS 没有可写的目录路径：先写缓存，再走系统分享/另存为。
    if (Platform.isIOS || isOhos) {
      final cachePath = await getCachePath();
      zipPath = p.join(cachePath, fileName);
    } else {
      String? selectedDir;
      try {
        selectedDir = await getDirectoryPath();
      } catch (e, s) {
        logger.e('选择导出目录失败', error: e, stackTrace: s);
        showErrorToast('${t.dataBackup.selectExportDirFailed}：$e');
        return;
      }

      if (selectedDir == null || selectedDir.trim().isEmpty) return;
      zipPath = p.join(selectedDir, fileName);
    }

    if (!mounted) return;
    _setBusy(true);
    _showLoadingDialog(t.dataBackup.exporting);

    try {
      await exportBreezeBackup(
        zipPath: zipPath,
        includeDownloads: _includeDownloads,
      );
      if (!mounted) return;
      Navigator.of(context).pop();

      if (isOhos) {
        final saved = await saveOhosFileToPicker(
          zipPath,
          suggestedName: fileName,
        );
        if (saved) {
          showSuccessToast(t.dataBackup.exportSuccess);
          try {
            await File(zipPath).delete();
          } catch (_) {}
        }
      } else if (Platform.isIOS) {
        // 先提示再弹系统分享面板，避免对话框盖住分享 UI
        showSuccessToast(t.dataBackup.exportShareHint);
        await openFileWithSystem(zipPath);
      } else {
        await _showResultDialog(
          t.dataBackup.exportSuccess,
          t.dataBackup.savedTo(path: zipPath),
        );
      }
    } catch (e, s) {
      if (mounted) Navigator.of(context).pop();
      logger.e('导出数据失败', error: e, stackTrace: s);
      showErrorToast('${t.dataBackup.exportFailed}：$e');
    } finally {
      _setBusy(false);
    }
  }

  Future<void> _importData() async {
    if (!mounted) return;
    _setBusy(true);
    _showLoadingDialog(t.dataBackup.processingBackup);

    final String? filePath;
    try {
      filePath = await _pickImportZipPath();
    } catch (e, s) {
      if (mounted) Navigator.of(context).pop();
      logger.e('选择备份文件失败', error: e, stackTrace: s);
      showErrorToast('${t.dataBackup.selectBackupFailed}：$e');
      _setBusy(false);
      return;
    }

    if (filePath == null) {
      if (mounted) Navigator.of(context).pop();
      _setBusy(false);
      return;
    }

    if (!mounted) return;
    Navigator.of(context).pop();
    _showLoadingDialog(t.dataBackup.readingBackup);

    late final BackupConfig config;
    try {
      config = await readBackupConfig(filePath, skipCopy: Platform.isAndroid);
    } catch (e, s) {
      if (mounted) Navigator.of(context).pop();
      logger.e('读取备份失败', error: e, stackTrace: s);
      showErrorToast('${t.dataBackup.readBackupFailed}：$e');
      _setBusy(false);
      return;
    }

    if (!mounted) {
      _cleanupImportCache(config);
      _setBusy(false);
      return;
    }
    Navigator.of(context).pop();

    final currentVersion = await getAppVersion();
    final confirmed = await _showImportConfirmDialog(
      exportedVersion: config.version,
      currentVersion: currentVersion,
      includeDownloads: config.includeDownloads,
    );

    if (!confirmed) {
      _cleanupImportCache(config);
      _setBusy(false);
      return;
    }

    if (!mounted) {
      _cleanupImportCache(config);
      _setBusy(false);
      return;
    }
    _showLoadingDialog(t.dataBackup.importing);

    try {
      await applyBreezeBackupImport(config);
      if (!mounted) return;
      Navigator.of(context).pop();
      await _showRestartDialog();
    } catch (e, s) {
      if (mounted) Navigator.of(context).pop();
      logger.e('导入数据失败', error: e, stackTrace: s);
      showErrorToast('${t.dataBackup.importFailed}：$e');
    } finally {
      _setBusy(false);
    }
  }

  void _setBusy(bool value) {
    if (mounted) setState(() => _busy = value);
  }

  /// 不可中断的加载弹窗：`barrierDismissible: false` + `preventPop: true`，
  /// 避免用户返回键关掉弹窗后，调用处的 Navigator.pop() 误关真正的页面路由。
  void _showLoadingDialog(String message) {
    showCalmDialog<void>(
      context,
      title: message,
      icon: Icons.hourglass_top_rounded,
      barrierDismissible: false,
      preventPop: true,
      bodyBuilder: (dialogContext) => const CalmProgressBar(height: 5),
    );
  }

  Future<void> _showResultDialog(String title, String message) async {
    if (!mounted) return;
    await showCalmDialog<void>(
      context,
      title: title,
      icon: Icons.task_alt_rounded,
      tone: CalmTone.success,
      bodyBuilder: (dialogContext) => Text(
        message,
        style: TextStyle(fontSize: 12, color: dialogContext.calm.text2),
      ),
      actionsBuilder: (dialogContext) => [
        CalmButton(
          label: t.common.ok,
          variant: CalmButtonVariant.primary,
          onPressed: () => Navigator.of(dialogContext).pop(),
        ),
      ],
    );
  }

  /// 选择要导入的 zip 备份文件。
  ///
  /// Android 上使用原生 MethodChannel 选择器，把文件直接拷贝到应用缓存，
  /// 绕过 [file_selector] 选择大文件时把整个文件读入内存导致的 OOM；
  /// 其他平台继续使用 [file_selector]。
  Future<String?> _pickImportZipPath() async {
    if (isOhos) {
      logger.i('OHOS 平台，使用系统文件选择器');
      return pickOhosFile(suffixes: const ['zip']);
    }
    if (Platform.isAndroid) {
      logger.i('Android 平台，使用原生选择器');
      return pickBackupZipAndroid();
    }

    logger.i('非 Android 平台，使用 file_selector');
    final file = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(
          label: 'zip',
          extensions: ['zip'],
          uniformTypeIdentifiers: ['public.zip-archive'],
        ),
      ],
    );
    return file?.path;
  }

  void _cleanupImportCache(BackupConfig config) {
    try {
      Directory(config.cacheDir).deleteSync(recursive: true);
    } catch (_) {}
  }

  Future<bool> _showImportConfirmDialog({
    required String exportedVersion,
    required String currentVersion,
    required bool includeDownloads,
  }) async {
    if (!mounted) return false;
    final versionMismatch = exportedVersion != currentVersion;

    final result = await showCalmDialog<bool>(
      context,
      title: t.dataBackup.importTitle,
      icon: Icons.unarchive_outlined,
      tone: versionMismatch ? CalmTone.warning : CalmTone.info,
      bodyBuilder: (dialogContext) {
        final c = dialogContext.calm;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              t.dataBackup.importConfirm,
              style: TextStyle(fontSize: 12, color: c.text2, height: 1.5),
            ),
            if (includeDownloads) ...[
              const SizedBox(height: 12),
              CalmStatusBanner(
                title: t.dataBackup.includesDownloadsWarning,
                tone: CalmTone.warning,
              ),
            ],
            if (versionMismatch) ...[
              const SizedBox(height: 12),
              CalmStatusBanner(
                title: t.dataBackup.versionMismatch,
                tone: CalmTone.danger,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      t.dataBackup.exportedVersion(version: exportedVersion),
                      style: TextStyle(fontSize: 11.5, color: c.text2),
                    ),
                  ),
                  CalmBadge(
                    label: exportedVersion,
                    tone: CalmBadgeTone.neutral,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      t.dataBackup.currentVersion(version: currentVersion),
                      style: TextStyle(fontSize: 11.5, color: c.text2),
                    ),
                  ),
                  CalmBadge(label: currentVersion, tone: CalmBadgeTone.accent),
                ],
              ),
            ],
          ],
        );
      },
      actionsBuilder: (dialogContext) => [
        CalmButton(
          label: t.common.cancel,
          variant: CalmButtonVariant.ghost,
          onPressed: () => Navigator.of(dialogContext).pop(false),
        ),
        CalmButton(
          label: t.dataBackup.kContinue,
          variant: CalmButtonVariant.primary,
          onPressed: () => Navigator.of(dialogContext).pop(true),
        ),
      ],
    );

    return result == true;
  }

  Future<void> _showRestartDialog() async {
    if (!mounted) return;
    await showCalmDialog<void>(
      context,
      title: t.dataBackup.importSuccess,
      icon: Icons.restart_alt_rounded,
      tone: CalmTone.success,
      bodyBuilder: (dialogContext) => Text(
        t.dataBackup.restartPrompt,
        style: TextStyle(fontSize: 12, color: dialogContext.calm.text2),
      ),
      actionsBuilder: (dialogContext) => [
        CalmButton(
          label: t.common.ok,
          variant: CalmButtonVariant.primary,
          onPressed: () => Navigator.of(dialogContext).pop(),
        ),
      ],
    );
  }
}
