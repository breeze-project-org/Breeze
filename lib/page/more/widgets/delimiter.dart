import 'package:material_ui/material_ui.dart';
import 'package:zephyr/ui/ui.dart';

/// 旧版内容分隔线（保留类名向后兼容），改为 CalmUI 的柔和细分割线。
class Delimiter extends StatelessWidget {
  const Delimiter({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: const CalmDivider(),
    );
  }
}
