import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/page/more/more.dart';
import 'package:zephyr/page/setting/common/setting_ui.dart';

@RoutePage()
class MorePage extends StatelessWidget {
  const MorePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.calm.bg,
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 768),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
              children: [
                _buildHeader(context),
                const SizedBox(height: 6),
                const SettingsWidget(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 轻盈居中的品牌头：圆角图标 + Breeze 标题（无厚重卡片与描边）。
  Widget _buildHeader(BuildContext context) {
    final c = context.calm;
    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            boxShadow: c.shadowMd,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Image.asset(
              'asset/image/app-icon.png',
              width: 76,
              height: 76,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Breeze',
          textHeightBehavior: kCalmTextHeightBehavior,
          strutStyle: calmStrut(20),
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: c.text,
            height: 1.2,
            leadingDistribution: TextLeadingDistribution.even,
          ),
        ),
        const SizedBox(height: 14),
      ],
    );
  }
}
