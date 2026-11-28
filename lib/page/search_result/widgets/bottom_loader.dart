import 'package:material_ui/material_ui.dart';
import 'package:zephyr/ui/ui.dart';

/// 分页列表底部加载条。
///
/// 保持旧的 `const BottomLoader()` 无参构造（书架预览、插件漫画宫格等
/// 多处复用），视觉交给 [CalmBottomLoader] 统一。
class BottomLoader extends StatelessWidget {
  const BottomLoader({super.key});

  @override
  Widget build(BuildContext context) {
    return const CalmBottomLoader(status: CalmBottomLoaderStatus.loading);
  }
}
