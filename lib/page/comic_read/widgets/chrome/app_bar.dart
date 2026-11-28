import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/ui/ui.dart';
import 'package:zephyr/page/comic_read/cubit/reader_cubit.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/config/global/global_setting.dart';

class ComicReadAppBar extends StatelessWidget {
  final String title;
  final ValueChanged<int> changePageIndex;
  final bool isDesktopFullscreen;
  final VoidCallback? onToggleFullscreen;

  const ComicReadAppBar({
    super.key,
    required this.title,
    required this.changePageIndex,
    this.isDesktopFullscreen = false,
    this.onToggleFullscreen,
  });

  @override
  Widget build(BuildContext context) {
    final isMenuVisible = context.select(
      (ReaderCubit cubit) => cubit.state.isMenuVisible,
    );
    // 墨水屏：工具栏滑入滑出的中间帧只会攒成残影，直接出图。
    final eInkInstant = context.select(
      (GlobalSettingCubit cubit) => cubit.state.eInkSetting.enabled,
    );
    final c = context.calm;
    const radius = BorderRadius.vertical(bottom: Radius.circular(14));
    // 自发浮层不再走 AppBar，状态栏图标明暗要手动跟卡片表面亮度对齐。
    final surfaceIsDark = c.surface.computeLuminance() < 0.5;

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: IgnorePointer(
        ignoring: !isMenuVisible,
        child: AnimatedSlide(
          duration: eInkInstant
              ? Duration.zero
              : const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
          offset: isMenuVisible ? Offset.zero : const Offset(0, -1),
          child: AnnotatedRegion<SystemUiOverlayStyle>(
            value: SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: surfaceIsDark
                  ? Brightness.light
                  : Brightness.dark,
              statusBarBrightness: surfaceIsDark
                  ? Brightness.dark
                  : Brightness.light,
            ),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: radius,
                boxShadow: c.shadowMd,
              ),
              child: ClipRRect(
                borderRadius: radius,
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: c.surface.withValues(alpha: 0.94),
                      border: Border(bottom: BorderSide(color: c.border)),
                    ),
                    child: SafeArea(
                      bottom: false,
                      child: SizedBox(
                        height: 50,
                        child: Row(
                          children: [
                            Expanded(
                              child: _ScrollableReaderTitle(text: title),
                            ),
                            if (onToggleFullscreen != null) ...[
                              CalmIconButton(
                                icon: isDesktopFullscreen
                                    ? Icons.fullscreen_exit_rounded
                                    : Icons.fullscreen_rounded,
                                tooltip: isDesktopFullscreen
                                    ? t.reader.exitFullscreen
                                    : t.reader.enterFullscreen,
                                onPressed: onToggleFullscreen,
                                size: 34,
                                iconSize: 18,
                              ),
                              const SizedBox(width: 10),
                            ] else
                              const SizedBox(width: 12),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 阅读器标题：单行、超长可横向拖动，颜色跟随 [context.calm] 的正文色。
class _ScrollableReaderTitle extends StatelessWidget {
  final String text;

  const _ScrollableReaderTitle({required this.text});

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    return Align(
      alignment: Alignment.centerLeft,
      // 桌面端也能用鼠标直接拖看超长章节名（默认鼠标不可拖动）。
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(
          scrollbars: false,
          dragDevices: const {
            PointerDeviceKind.touch,
            PointerDeviceKind.mouse,
            PointerDeviceKind.trackpad,
            PointerDeviceKind.stylus,
          },
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Text(
            text,
            maxLines: 1,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: c.text,
            ),
          ),
        ),
      ),
    );
  }
}
