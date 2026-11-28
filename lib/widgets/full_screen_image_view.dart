import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:file_selector/file_selector.dart';
import 'package:gal/gal.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:photo_view/photo_view.dart';
import 'package:zephyr/config/global/global.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/page/comic_info/method/export_comic.dart';
import 'package:zephyr/ui/ui.dart';
import 'package:zephyr/util/error/error_filter.dart';
import 'package:zephyr/util/ohos/file_bridge.dart';
import 'package:zephyr/util/ohos/platform.dart';
import 'package:zephyr/widgets/toast.dart';

@RoutePage()
class FullScreenImagePage extends StatelessWidget {
  final String imagePath;

  const FullScreenImagePage({super.key, required this.imagePath});

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    // 看图沉浸底色：跟随主题色相压到极暗，避免纯黑割裂感，也不刺眼。
    final immersiveBg = Color.alphaBlend(
      Colors.black.withValues(alpha: 0.92),
      c.bg,
    );

    return Scaffold(
      backgroundColor: immersiveBg,
      body: Stack(
        children: [
          // 图片部分
          PhotoView(
            imageProvider: FileImage(File(imagePath)),
            minScale: PhotoViewComputedScale.contained,
            maxScale: PhotoViewComputedScale.covered * 2,
            initialScale: PhotoViewComputedScale.contained,
          ),

          // 顶部柔和渐隐浮层 + 胶囊关闭按钮
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.42),
                    Colors.transparent,
                  ],
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                  child: Row(
                    children: [
                      CalmIconButton(
                        icon: Icons.close_rounded,
                        tooltip: t.common.close,
                        size: 34,
                        iconSize: 18,
                        onPressed: () => context.pop(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // 底部柔和渐隐浮层 + 胶囊保存按钮
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.42),
                    Colors.transparent,
                  ],
                ),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      CalmButton(
                        label: t.common.save,
                        icon: Icons.download_rounded,
                        variant: CalmButtonVariant.tonal,
                        size: CalmButtonSize.sm,
                        onPressed: _saveImage,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveImage() async {
    logger.d("download image");

    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      // 桌面端使用文件选择器
      try {
        final result = await _saveImageWithSelector(imagePath);
        if (result.isNotEmpty) {
          showSuccessToast(t.reader.imageSavedTo(path: result));
        }
      } catch (e, s) {
        logger.e("桌面端保存图片失败", error: e, stackTrace: s);
        showErrorToast(
          t.reader.imageSaveFailedWithError(
            error: normalizeSearchErrorMessage(e),
          ),
        );
      }
    } else if (Platform.isAndroid || Platform.isIOS || isOhos) {
      // 移动端 (iOS & Android) 使用 gal 插件保存到相册
      await _saveImageMobile(imagePath);
    }
  }

  // 桌面端保存逻辑：弹出目录选择器
  Future<String> _saveImageWithSelector(String inputImagePath) async {
    final inputFile = File(inputImagePath);
    final ext = await detectImageExtension(inputFile);

    final rawName = inputFile.uri.pathSegments.last;
    final suggestedName = p.extension(rawName).isEmpty
        ? '$rawName$ext'
        : rawName;

    final typeGroup = XTypeGroup(
      label: 'images',
      extensions: [ext.substring(1)],
    );

    final result = await getSaveLocation(
      suggestedName: suggestedName,
      acceptedTypeGroups: [typeGroup],
    );

    if (result == null) {
      return ''; // 用户取消了选择
    }

    await inputFile.copy(result.path);
    return result.path;
  }

  // 移动端保存逻辑：利用 gal 写入系统相册
  Future<void> _saveImageMobile(String inputImagePath) async {
    try {
      if (isOhos) {
        // OHOS：走系统相册保存对话框（photoAccessHelper），不依赖 gal。
        final inputFile = File(inputImagePath);
        final ext = await detectImageExtension(inputFile);
        final tempFile = await inputFile.copy(
          p.join(
            Directory.systemTemp.path,
            '${DateTime.now().millisecondsSinceEpoch}$ext',
          ),
        );
        try {
          await saveImageToOhosGallery(tempFile.path);
          showSuccessToast(t.reader.imageSavedToAlbum);
        } finally {
          try {
            await tempFile.delete();
          } catch (_) {}
        }
        return;
      }

      // 检查是否已有相册写入权限，如果没有则申请
      if (!await Gal.hasPermission()) {
        await Gal.requestPermission();
      }

      final inputFile = File(inputImagePath);
      final ext = await detectImageExtension(inputFile);

      // gal 对无后缀文件会报 NOT_SUPPORTED_FORMAT，
      // 先根据真实文件头生成带后缀的临时文件再保存
      final tempDir = Directory.systemTemp;
      final fileName = '${DateTime.now().millisecondsSinceEpoch}$ext';
      final tempPath = p.join(tempDir.path, fileName);
      final tempFile = await inputFile.copy(tempPath);

      try {
        // 将图片放入相册
        await Gal.putImage(
          tempFile.path,
          album: Platform.isIOS ? null : appName,
        );
        showSuccessToast(t.reader.imageSavedToAlbum);
      } finally {
        // 清理临时文件，忽略删除失败
        try {
          await tempFile.delete();
        } catch (_) {}
      }
    } on GalException catch (e) {
      logger.e("Gal 保存异常", error: e);
      // 根据 GalException 的类型给出更精确的提示
      if (e.type == GalExceptionType.permissionDenied) {
        showErrorToast(t.reader.saveImagePermissionDenied);
      } else {
        showErrorToast(
          t.reader.imageSaveFailedWithError(error: e.type.message),
        );
      }
    } catch (e, s) {
      logger.e("移动端保存图片发生未知异常", error: e, stackTrace: s);
      showErrorToast(t.reader.imageSaveFailed);
    }
  }
}
