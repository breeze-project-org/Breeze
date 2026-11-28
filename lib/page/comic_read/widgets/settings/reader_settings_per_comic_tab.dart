part of 'reader_settings_sheet.dart';

/// 第四个 tab：本漫设置。
///
/// 只留阅读模式、自动阅读、翻页模式三个 Section，其它（背景、预加载、
/// 阅读体验、手势扩展、信息条）是全局专属，不进本漫。
/// 复用同一套 Section 组件，整棵树包一层 [_PerComicScope] 钉死写目标——
/// 里面所有控件读有效值、写本漫 patch。
/// 无覆盖进 tab 显示的即全局值，改哪个记哪个（稀疏）；
/// 阅读模式标题右边的“跟随全局”删整行本漫设置，回到无覆盖。
class _ReaderSettingsPerComicTab extends StatelessWidget {
  final ValueChanged<int> changePageIndex;
  final ValueChanged<bool>? onLandscapeChanged;
  final ValueChanged<bool>? onDoublePageModeChanged;
  final String source;
  final String comicId;
  final bool isAndroidPhone;

  const _ReaderSettingsPerComicTab({
    required this.changePageIndex,
    this.onLandscapeChanged,
    this.onDoublePageModeChanged,
    required this.source,
    required this.comicId,
    required this.isAndroidPhone,
  });

  @override
  Widget build(BuildContext context) {
    return _PerComicScope(
      perComic: true,
      child: _SettingsTabContent(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 编辑目标徽章：一眼看出这里改的是本漫覆盖，不是全局。
            // “跟随全局”（删整行覆盖）仍留在阅读模式分组头右侧，见 _ReadModeSection。
            Row(
              children: [
                CalmBadge(
                  label: t.reader.perComicThisComic,
                  tone: CalmBadgeTone.tonal,
                  icon: Icons.bookmark_added_outlined,
                ),
              ],
            ),
            const SizedBox(height: 14),
            _ReadModeSection(
              changePageIndex: changePageIndex,
              onLandscapeChanged: onLandscapeChanged,
              onDoublePageModeChanged: onDoublePageModeChanged,
            ),
            const SizedBox(height: 18),
            const _AutoReadSection(),
            const SizedBox(height: 18),
            const _TapPageTurnModeSection(),
          ],
        ),
      ),
    );
  }
}
