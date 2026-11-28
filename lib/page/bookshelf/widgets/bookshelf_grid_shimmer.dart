import 'package:material_ui/material_ui.dart';
import 'package:zephyr/ui/ui.dart';
import 'package:zephyr/widgets/comic_simplify_entry/comic_simplify_entry.dart'
    show kComicCardBorderRadius;
import 'package:zephyr/widgets/comic_simplify_entry/comic_simplify_entry_grid.dart';

/// 书架首屏骨架屏：与真实网格同列宽/同间距的轻盈骨架块，逐块呼吸淡入淡出。
class BookshelfGridShimmer extends StatelessWidget {
  const BookshelfGridShimmer({super.key, this.itemCount = 12});

  final int itemCount;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(10),
      gridDelegate: buildComicSimplifyEntryGridDelegate(),
      itemCount: itemCount,
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      itemBuilder: (context, index) {
        // 网格单元是紧约束：直接铺满，圆角与漫画卡片保持一致。
        return LayoutBuilder(
          builder: (context, constraints) => CalmSkeletonBox(
            height: constraints.maxHeight,
            radius: kComicCardBorderRadius,
          ),
        );
      },
    );
  }
}
