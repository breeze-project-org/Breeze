import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/page/comic_read/bloc/page_bloc.dart';
import 'package:zephyr/ui/ui.dart';

class ComicErrorWidget extends StatelessWidget {
  final PageState state;
  final PageEvent event;

  const ComicErrorWidget({super.key, required this.state, required this.event});

  @override
  Widget build(BuildContext context) {
    logger.d(state.errorMessage);
    // 离线章节目录为空时不是加载失败，回到上一页即可，不给重试按钮。
    final isChapterMissing = state.errorMessage.toLowerCase().contains(
      'no element',
    );

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: isChapterMissing
              ? CalmEmptyState(
                  icon: Icons.download_for_offline_outlined,
                  title: t.reader.chapterNotDownloaded,
                  action: CalmButton(
                    label: t.common.back,
                    icon: Icons.arrow_back_rounded,
                    variant: CalmButtonVariant.secondary,
                    // 阅读页是全屏路由，eink 设备上没有可靠的手势返回；
                    // 错误页必须自带退出键，否则会被困在这里。
                    onPressed: () => context.pop(),
                  ),
                )
              : CalmErrorState(
                  title: t.error.loadFailed,
                  errorDetail: state.errorMessage.toString(),
                  errorDetailMaxLines: 3,
                  primaryLabel: t.common.back,
                  onPrimary: () => context.pop(),
                  retryLabel: t.common.retry,
                  onRetry: () => context.read<PageBloc>().add(event),
                ),
        ),
      ),
    );
  }
}
