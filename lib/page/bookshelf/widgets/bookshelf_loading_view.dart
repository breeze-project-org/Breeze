import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/ui/ui.dart';

/// 书架首屏加载占位：轻盈环形指示器 + 短提示。
class BookshelfLoadingView extends StatelessWidget {
  const BookshelfLoadingView({super.key, this.message = ''});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: CalmLoading(
        label: message.isEmpty ? t.common.loading : message,
        size: 26,
      ),
    );
  }
}
