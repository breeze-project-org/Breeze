import 'package:material_ui/material_ui.dart';
import 'package:zephyr/ui/ui.dart';

/// 可横向滚动的单行标题（长标题不换行、不截断，鼠标可横向拖动）。
class ScrollableTitle extends StatelessWidget {
  const ScrollableTitle({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Text(
        text,
        textHeightBehavior: kCalmTextHeightBehavior,
        strutStyle: calmStrut(15),
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: c.text,
          height: 1.2,
          leadingDistribution: TextLeadingDistribution.even,
        ),
      ),
    );
  }
}
