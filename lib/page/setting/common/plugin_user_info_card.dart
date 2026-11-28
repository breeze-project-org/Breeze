import 'package:material_ui/material_ui.dart';
import 'package:zephyr/ui/ui.dart';
import 'package:zephyr/widgets/comic_simplify_entry/cover.dart';
import 'package:zephyr/type/enum.dart';

/// 插件账号信息卡（CalmUI 版）：圆角头像 + 最多三行文本。
class PluginUserInfoCard extends StatelessWidget {
  const PluginUserInfoCard({
    super.key,
    required this.from,
    required this.avatarUrl,
    required this.avatarPath,
    required this.lines,
  });

  final String from;
  final String avatarUrl;
  final String avatarPath;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    final displayLines = lines
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .take(3)
        .toList();

    if (displayLines.isEmpty &&
        avatarUrl.trim().isEmpty &&
        avatarPath.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    return CalmCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _buildAvatar(),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < displayLines.length; i++)
                  Padding(
                    padding: EdgeInsets.only(
                      bottom: i == displayLines.length - 1 ? 0 : 4,
                    ),
                    child: Text(
                      displayLines[i],
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: i == 0 ? 12.5 : 11.5,
                        fontWeight: i == 0 ? FontWeight.w600 : FontWeight.w400,
                        color: i == 0 ? c.text : c.text2,
                        height: 1.35,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar() {
    return Builder(
      builder: (context) {
        final c = context.calm;
        final hasAvatar =
            avatarUrl.trim().isNotEmpty || avatarPath.trim().isNotEmpty;
        if (!hasAvatar) {
          return CalmAvatar(
            icon: Icons.person_rounded,
            size: 56,
            backgroundColor: c.surface2,
            foregroundColor: c.text3,
          );
        }
        return Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: c.surface2,
            border: Border.all(color: c.accentBorder, width: 1.5),
          ),
          clipBehavior: Clip.antiAlias,
          child: CoverWidget(
            fileServer: avatarUrl,
            path: avatarPath,
            id: 'plugin_user_avatar',
            pictureType: PictureType.user,
            from: from,
            width: 56,
            height: 56,
          ),
        );
      },
    );
  }
}
