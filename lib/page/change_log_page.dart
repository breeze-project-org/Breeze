import 'package:auto_route/auto_route.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:markdown_widget/markdown_widget.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/network/utils/github_proxy.dart';
import 'package:zephyr/service/update/check_update.dart';
import 'package:zephyr/service/update/json/github_release_json.dart';
import 'package:zephyr/ui/ui.dart';
import 'package:zephyr/util/error/error_filter.dart';
import 'package:zephyr/util/system/external_link.dart';

const _proxyReleasesApiUrl =
    '$breezeGithubApi/repos/breeze-project-org/Breeze/releases';
const _githubReleasesApiUrl =
    'https://api.github.com/repos/breeze-project-org/Breeze/releases';

@RoutePage()
class ChangelogPage extends StatefulWidget {
  const ChangelogPage({super.key});

  @override
  State<ChangelogPage> createState() => _ChangelogPageState();
}

class _ChangelogPageState extends State<ChangelogPage> {
  final ScrollController _scrollController = ScrollController();

  List<GithubReleaseJson> _releases = [];
  bool _isLoading = true; // 首次加载状态
  String? _errorMsg;

  // 分页相关变量
  int _page = 1;
  static const int _perPage = 20; // 每次请求多少条
  bool _hasMore = true; // 是否还有更多数据
  bool _isFetching = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    // 看过更新日志就清掉「更多」页的 NEW 徽标，同一版本不再提示。
    markChangelogSeen();
    // 首次进入自动刷新
    _fetchReleases(refresh: true);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (!_scrollController.hasClients ||
        !_hasMore ||
        _isFetching ||
        _scrollController.position.pixels <
            _scrollController.position.maxScrollExtent - 400) {
      return;
    }
    _fetchReleases();
  }

  /// 获取数据
  /// [refresh] 为 true 代表下拉刷新（重置页码），false 代表上拉加载（页码+1）
  Future<void> _fetchReleases({bool refresh = false}) async {
    if (_isFetching) return;
    _isFetching = true;
    if (!refresh && mounted) {
      setState(() {});
    }

    try {
      final requestPage = refresh ? 1 : _page;

      List<GithubReleaseJson>? newData;
      for (final url in [_proxyReleasesApiUrl, _githubReleasesApiUrl]) {
        try {
          final response = await fetch(
            url,
            query: {'page': requestPage, 'per_page': _perPage},
            headers: {'Accept': 'application/vnd.github.v3+json'},
          );

          final body = response.text;
          try {
            newData = githubReleaseJsonFromJson(body);
          } catch (e, st) {
            // 代理可能在 200 正文里塞入错误页，保留完整正文用于排查。
            logger.e(
              '更新日志解析失败 (HTTP ${response.status}): $body',
              error: e,
              stackTrace: st,
            );
            continue;
          }
          break;
        } on FetchException catch (e, st) {
          // 代理/镜像可能返回 HTML 或错误 JSON，保留完整正文用于排查。
          logger.e('HTTP ${e.status}: ${e.response.text}', stackTrace: st);
          // 当前请求失败时继续尝试下一个地址。
        } catch (e, st) {
          logger.e(e, stackTrace: st);
          // 当前请求失败时继续尝试下一个地址。
        }
      }

      final releases = newData;
      if (releases != null) {
        if (mounted) {
          setState(() {
            if (refresh) {
              _releases = releases;
              _errorMsg = null; // 刷新成功清除错误
            } else {
              _releases.addAll(releases);
            }

            // 更新页码和是否还有更多数据
            _page = requestPage + 1;
            // 如果返回的数据条数少于每页最大条数，说明没有下一页了
            _hasMore = releases.length >= _perPage;

            // 首次加载完成
            _isLoading = false;
          });
        }
      } else {
        throw Exception('所有更新日志请求地址均失败');
      }
    } catch (e) {
      logger.e(e);
      if (mounted) {
        // 如果是首次加载出错，显示全屏错误页面
        if (_releases.isEmpty && refresh) {
          setState(() {
            _isLoading = false;
            _errorMsg = normalizeSearchErrorMessage(e);
          });
        } else {
          // 如果是加载更多时出错，提示 Toast 或在底部显示失败
          CalmToast.show(
            context,
            title: t.changelog.loadFailedWithError(error: e),
            tone: CalmTone.warning,
          );
        }
      }
    } finally {
      _isFetching = false;
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> _launchUrl(String urlString) async {
    final Uri url = Uri.parse(urlString);
    if (!await openExternalUrl(url)) {
      if (mounted) {
        CalmToast.show(
          context,
          title: t.changelog.cannotOpenLink(url: urlString),
          tone: CalmTone.warning,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return CalmPageScaffold(
      title: t.changelog.title,
      maxContentWidth: 768,
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return Center(child: CalmLoading(label: t.common.loading, size: 22));
    }

    // 首次全屏错误
    if (_errorMsg != null && _releases.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: CalmErrorState(
              title: t.changelog.checkNetwork,
              errorDetail: _errorMsg!,
              errorDetailMaxLines: 3,
              primaryLabel: t.changelog.retry,
              onPrimary: () {
                setState(() {
                  _isLoading = true;
                  _errorMsg = null;
                });
                _fetchReleases(refresh: true);
              },
            ),
          ),
        ),
      );
    }

    if (_releases.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => _fetchReleases(refresh: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.6,
              child: Center(
                child: CalmEmptyState(
                  icon: Icons.history_rounded,
                  title: t.changelog.empty,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // 桌面端窄栏居中由 CalmPageScaffold(maxContentWidth: 768) 统一处理。
    return RefreshIndicator(
      onRefresh: () => _fetchReleases(refresh: true),
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        itemCount: _releases.length + (_hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _releases.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CalmLoading(size: 16)),
            );
          }
          final release = _releases[index];
          return KeyedSubtree(
            key: ValueKey(release.id),
            child: _ReleaseCard(release: release, onLinkTap: _launchUrl)
                .animate()
                .fade(duration: 400.ms)
                .slideY(begin: 0.1, end: 0, curve: Curves.easeOutQuad),
          );
        },
      ),
    );
  }
}

class _ReleaseCard extends StatelessWidget {
  final GithubReleaseJson release;
  final Function(String) onLinkTap;

  const _ReleaseCard({required this.release, required this.onLinkTap});

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    final dateStr = DateFormat('yyyy-MM-dd HH:mm')
        .format(release.publishedAt.toLocal());

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: CalmCard(
        padding: EdgeInsets.zero,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: true,
            shape: const Border(),
            collapsedShape: const Border(),
            tilePadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 6,
            ),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            title: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          CalmBadge(
                            label: release.tagName,
                            tone: CalmBadgeTone.accent,
                            icon: Icons.sell_outlined,
                          ),
                          if (release.prerelease)
                            const CalmBadge(
                              label: 'Pre',
                              tone: CalmBadgeTone.warning,
                            ),
                          if (release.draft)
                            const CalmBadge(
                              label: 'Draft',
                              tone: CalmBadgeTone.neutral,
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        t.changelog.publishedAt(date: dateStr),
                        style: TextStyle(
                          fontSize: 11,
                          color: c.text3,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
                CalmIconButton(
                  icon: Icons.open_in_new_rounded,
                  tooltip: t.changelog.viewInBrowser,
                  onPressed: () => onLinkTap(release.htmlUrl),
                ),
              ],
            ),
            children: [
              const CalmDivider(),
              const SizedBox(height: 10),
              MarkdownWidget(
                data: release.body,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                config: MarkdownConfig(
                  configs: [
                    PConfig(
                      textStyle: TextStyle(
                        fontSize: 12.5,
                        height: 1.65,
                        color: c.text,
                      ),
                    ),
                    LinkConfig(
                      style: TextStyle(
                        color: c.accent,
                        decoration: TextDecoration.underline,
                      ),
                      onTap: (url) => onLinkTap(url),
                    ),
                    CodeConfig(
                      style: TextStyle(
                        backgroundColor: c.surface2,
                        fontFamily: 'monospace',
                      ),
                    ),
                    PreConfig(
                      decoration: BoxDecoration(
                        color: c.surface2,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: c.border),
                      ),
                    ),
                  ],
                ),
              ),
              if (release.assets.isNotEmpty) ...[
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: c.bg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: c.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CalmSectionHeader(
                        title: t.changelog.attachments,
                        countText: '${release.assets.length}',
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: release.assets.map((asset) {
                          return _AttachmentChip(
                            name: asset.name,
                            sizeBytes: asset.size,
                            onTap: () => onLinkTap(asset.browserDownloadUrl),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AttachmentChip extends StatefulWidget {
  const _AttachmentChip({
    required this.name,
    required this.sizeBytes,
    required this.onTap,
  });

  final String name;
  final int sizeBytes;
  final VoidCallback onTap;

  @override
  State<_AttachmentChip> createState() => _AttachmentChipState();
}

class _AttachmentChipState extends State<_AttachmentChip> {
  bool _hovered = false;
  bool _pressed = false;

  String get _sizeLabel =>
      '${(widget.sizeBytes / 1024 / 1024).toStringAsFixed(1)} MB';

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    final bg = _pressed
        ? c.accentSoft
        : _hovered
        ? Color.alphaBlend(c.accent.withValues(alpha: 0.06), c.surface)
        : c.surface;

    return Tooltip(
      message: '${widget.name} · $_sizeLabel',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() {
          _hovered = false;
          _pressed = false;
        }),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          child: AnimatedScale(
            scale: _pressed ? 0.97 : 1.0,
            duration: const Duration(milliseconds: 100),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _hovered ? c.accentBorder : c.border),
                boxShadow: c.shadowSm,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(Icons.download_rounded, size: 13.5, color: c.accent),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      widget.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textHeightBehavior: kCalmTextHeightBehavior,
                      strutStyle: calmStrut(11.5),
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        color: _hovered ? c.accent : c.text,
                        height: 1.2,
                        leadingDistribution: TextLeadingDistribution.even,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _sizeLabel,
                    textHeightBehavior: kCalmTextHeightBehavior,
                    strutStyle: calmStrut(10.5),
                    style: TextStyle(
                      fontSize: 10.5,
                      color: c.text3,
                      height: 1.2,
                      leadingDistribution: TextLeadingDistribution.even,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
