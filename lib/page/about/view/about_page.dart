import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/network/utils/github_proxy.dart';
import 'package:zephyr/page/setting/common/setting_ui.dart';

import 'package:zephyr/service/update/check_update.dart';
import 'package:zephyr/util/system/external_link.dart';

@RoutePage()
class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  String _appVersion = t.about.loading;
  List<Map<String, dynamic>> _contributors = [];
  bool _contributorsLoading = true;
  String? _contributorsError;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    final version = await getAppVersion();
    await _fetchContributors();

    if (mounted) {
      setState(() {
        _appVersion = version;
      });
    }
  }

  Future<void> _fetchContributors() async {
    const repoPath = '/repos/breeze-project-org/Breeze/contributors';
    final urls = [
      ...mirrorBaseUrls.map((base) => '${base}https://api.github.com$repoPath'),
      'https://api.github.com$repoPath',
    ];
    try {
      for (final url in urls) {
        try {
          final response = await fetch(
            url,
            headers: const {
              'User-Agent': 'Breeze',
              'Accept': 'application/vnd.github+json',
            },
            query: {'per_page': 20},
          );
          if (mounted) {
            final data = response.json;
            setState(() {
              _contributors = List<Map<String, dynamic>>.from(
                data is List ? data : const [],
              );
              _contributorsLoading = false;
            });
            return;
          }
        } catch (_) {
          continue;
        }
      }
      if (mounted) {
        setState(() {
          _contributorsError = t.about.fetchFailed;
          _contributorsLoading = false;
        });
      }
    } catch (e) {
      logger.e(e);
      if (mounted) {
        setState(() {
          _contributorsError = t.about.networkError;
          _contributorsLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    return SettingPageShell(
      title: t.about.title,
      badge: _appVersion,
      child: ListView(
        padding: kSettingPagePadding,
        children: [
          const SizedBox(height: 8),
          _buildHeader(),
          const SizedBox(height: 22),
          _buildSection(
            icon: Icons.folder_special_outlined,
            title: t.about.projectAddress,
            desc: t.about.projectAddressDesc,
            linkText: t.about.projectLink,
            url: 'https://github.com/breeze-project-org/Breeze',
          ),
          const SizedBox(height: 12),
          _buildContributorsSection(),
          const SizedBox(height: 12),
          _buildSection(
            icon: Icons.chat_bubble_outline_rounded,
            title: t.about.contact,
            desc: t.about.contactDesc,
            linkText: 'Telegram: @breeze_zh_cn',
            url: 'https://t.me/breeze_zh_cn',
          ),
          const SizedBox(height: 12),
          _buildSection(
            icon: Icons.build_outlined,
            title: t.about.feedback,
            desc: t.about.feedbackDesc,
            linkText: t.about.feedbackLink,
            url: 'https://github.com/breeze-project-org/Breeze/issues',
          ),
          const SizedBox(height: 20),
          Center(
            child: CalmButton(
              label: t.about.disclaimer,
              icon: Icons.gavel_rounded,
              variant: CalmButtonVariant.secondary,
              onPressed: _showDisclaimerDialog,
            ),
          ),
          const SizedBox(height: 20),
          Center(
            child: Text(
              t.about.version(version: _appVersion),
              textHeightBehavior: kCalmTextHeightBehavior,
              strutStyle: calmStrut(11.5),
              style: TextStyle(
                fontSize: 11.5,
                color: c.text3,
                height: 1.2,
                leadingDistribution: TextLeadingDistribution.even,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: 28),
        ],
      ),
    );
  }

  // --- 组件构建方法 ---

  /// 顶部品牌区：圆角应用图标 + 标题 + 版本胶囊。
  Widget _buildHeader() {
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
              width: 84,
              height: 84,
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'Breeze',
          textHeightBehavior: kCalmTextHeightBehavior,
          strutStyle: calmStrut(21),
          style: TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w700,
            color: c.text,
            height: 1.2,
            leadingDistribution: TextLeadingDistribution.even,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            CalmBadge(
              label: t.about.version(version: _appVersion),
              tone: CalmBadgeTone.tonal,
              icon: Icons.sell_outlined,
            ),
            const SizedBox(width: 6),
            CalmBadge(
              label: 'windy',
              tone: CalmBadgeTone.neutral,
              icon: Icons.person_outline_rounded,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSection({
    required IconData icon,
    required String title,
    required String desc,
    required String linkText,
    required String url,
  }) {
    return CalmCard(
      padding: EdgeInsets.zero,
      child: _LinkCard(
        icon: icon,
        title: title,
        desc: desc,
        linkText: linkText,
        onTap: () => _launchURL(url),
      ),
    );
  }

  Widget _buildContributorsSection() {
    final c = context.calm;
    return CalmCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.favorite_border_rounded, size: 15, color: c.accent),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  t.about.contributors,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: c.text,
                  ),
                ),
              ),
              CalmBadge(
                label: t.about.contributorsCount(count: _contributors.length),
                tone: CalmBadgeTone.neutral,
              ),
            ],
          ),
          const SizedBox(height: 10),
          const CalmDivider(),
          const SizedBox(height: 12),
          if (_contributorsLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: CalmLoading()),
            )
          else if (_contributorsError != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Center(
                child: Text(
                  _contributorsError!,
                  style: TextStyle(fontSize: 11.5, color: c.text3),
                ),
              ),
            )
          else
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _contributors.map((contributor) {
                return _buildContributorAvatar(
                  avatarUrl: contributor['avatar_url'] ?? '',
                  login: contributor['login'] ?? '',
                  contributions: contributor['contributions'] ?? 0,
                  htmlUrl: contributor['html_url'] ?? '',
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildContributorAvatar({
    required String avatarUrl,
    required String login,
    required int contributions,
    required String htmlUrl,
  }) {
    return Tooltip(
      message: t.about.contributionsTooltip(
        login: login,
        count: contributions,
      ),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => _launchURL(htmlUrl),
          child: _ContributorAvatar(avatarUrl: avatarUrl, login: login),
        ),
      ),
    );
  }

  // --- 免责声明弹窗 ---
  void _showDisclaimerDialog() {
    showCalmDialog<void>(
      context,
      title: t.about.disclaimerTitle,
      subtitle: t.about.disclaimer,
      icon: Icons.gavel_rounded,
      maxWidth: 560,
      bodyBuilder: (ctx) {
        final c = ctx.calm;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _DisclaimerItem(
              t.about.disclaimerItem1Title,
              t.about.disclaimerItem1Content,
            ),
            _DisclaimerItem(
              t.about.disclaimerItem2Title,
              t.about.disclaimerItem2Content,
            ),
            _DisclaimerItem(
              t.about.disclaimerItem3Title,
              t.about.disclaimerItem3Content,
            ),
            _DisclaimerItem(
              t.about.disclaimerItem4Title,
              t.about.disclaimerItem4Content,
            ),
            _DisclaimerItem(
              t.about.disclaimerItem5Title,
              t.about.disclaimerItem5Content,
            ),
            _DisclaimerItem(
              t.about.disclaimerItem6Title,
              t.about.disclaimerItem6Content,
            ),
            _DisclaimerItem(
              t.about.disclaimerItem7Title,
              t.about.disclaimerItem7Content,
            ),
            _DisclaimerItem(
              t.about.disclaimerItem8Title,
              t.about.disclaimerItem8Content,
            ),
            const SizedBox(height: 8),
            CalmStatusBanner(
              title: t.about.disclaimerImportantContent,
              tone: CalmTone.warning,
            ),
            const SizedBox(height: 4),
            Text(
              t.about.disclaimerImportant,
              style: TextStyle(fontSize: 11, color: c.text3),
            ),
          ],
        );
      },
      actionsBuilder: (ctx) => [
        CalmButton(
          label: t.common.close,
          variant: CalmButtonVariant.primary,
          onPressed: () => Navigator.of(ctx).pop(),
        ),
      ],
    );
  }

  Future<void> _launchURL(String url) async {
    final Uri uri = Uri.parse(url);
    if (!await openExternalUrl(uri)) {
      logger.e('无法打开链接: $url');
    }
  }
}

// 辅助组件：项目信息卡片（图标 + 标题 + 描述 + 可点击链接行）
class _LinkCard extends StatefulWidget {
  const _LinkCard({
    required this.icon,
    required this.title,
    required this.desc,
    required this.linkText,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String desc;
  final String linkText;
  final VoidCallback onTap;

  @override
  State<_LinkCard> createState() => _LinkCardState();
}

class _LinkCardState extends State<_LinkCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: c.rowVPadding),
          decoration: BoxDecoration(
            color: _hovered
                ? c.surface2.withValues(alpha: 0.7)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: c.accentSoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(widget.icon, size: 16, color: c.accent),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: c.text,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      widget.desc,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: c.text2,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      widget.linkText,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: c.accent,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Icon(
                  Icons.open_in_new_rounded,
                  size: 15,
                  color: c.text3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// 辅助组件：贡献者头像（网络头像 + 首字兜底 + 柔和描边环）
class _ContributorAvatar extends StatelessWidget {
  const _ContributorAvatar({required this.avatarUrl, required this.login});

  final String avatarUrl;
  final String login;

  static const double _size = 42;

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    final fallback = CalmAvatar(
      text: login,
      size: _size,
      backgroundColor: c.surface2,
      foregroundColor: c.text2,
    );
    if (avatarUrl.trim().isEmpty) return fallback;

    return Container(
      width: _size,
      height: _size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: c.surface2,
        border: Border.all(color: c.accentBorder, width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.network(
        avatarUrl,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }
}

// 辅助组件：免责声明条目
class _DisclaimerItem extends StatelessWidget {
  final String title;
  final String content;
  const _DisclaimerItem(this.title, this.content);

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: c.text,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            content,
            style: TextStyle(fontSize: 11.5, color: c.text2, height: 1.5),
          ),
        ],
      ),
    );
  }
}
