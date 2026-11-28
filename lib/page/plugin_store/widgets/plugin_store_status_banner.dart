import 'package:material_ui/material_ui.dart';
import 'package:zephyr/ui/ui.dart';

/// 插件安装进度横幅：语义 info（accentSoft）+ 右侧轻量转圈。
class PluginStoreStatusBanner extends StatelessWidget {
  const PluginStoreStatusBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final trimmedMessage = message.trim();
    if (trimmedMessage.isEmpty) {
      return const SizedBox.shrink();
    }

    return CalmStatusBanner(
      title: trimmedMessage,
      tone: CalmTone.info,
      trailing: const CalmLoading(size: 14),
    );
  }
}
