import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/ui/ui.dart';

/// 书架空态：居中轻盈占位 + 可选刷新胶囊，整页仍可下拉刷新。
class BookshelfEmptyView extends StatelessWidget {
  const BookshelfEmptyView({
    super.key,
    this.title = '',
    this.icon = Icons.folder_open_outlined,
    this.onRefresh,
  });

  final String title;
  final IconData icon;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async => onRefresh?.call(),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 内容不足一屏时也撑满高度，让空态垂直居中、下拉手势有落点。
          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: CalmEmptyState(
                  icon: icon,
                  title: title.isEmpty ? t.comicList.nothingHere : title,
                  action: onRefresh == null
                      ? null
                      : CalmButton(
                          label: t.common.refresh,
                          icon: Icons.refresh_rounded,
                          variant: CalmButtonVariant.secondary,
                          size: CalmButtonSize.sm,
                          onPressed: onRefresh,
                        ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
