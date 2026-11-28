import 'package:material_ui/material_ui.dart';
import 'package:zephyr/ui/components/calm_button.dart';
import 'package:zephyr/ui/components/calm_chips.dart';
import 'package:zephyr/ui/theme/calm_theme.dart';

/// 统一轻盈页面顶栏（替代厚重 AppBar，支持返回键、标题/副标题、徽章与右侧操作）。
class CalmAppBar extends StatelessWidget {
  const CalmAppBar({
    super.key,
    required this.title,
    this.subtitle,
    this.badge,
    this.leading,
    this.showBack = true,
    this.onBack,
    this.actions = const [],
    this.showBottomBorder = true,
    this.borderRadius,
  });

  final String title;
  final String? subtitle;
  final String? badge;
  final Widget? leading;
  final bool showBack;
  final VoidCallback? onBack;
  final List<Widget> actions;
  final bool showBottomBorder;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    final canPop = Navigator.of(context).canPop();
    final effectiveLeading =
        leading ??
        (showBack && (onBack != null || canPop)
            ? CalmIconButton(
                icon: Icons.arrow_back_rounded,
                size: 32,
                iconSize: 17,
                tooltip: '返回',
                onPressed: onBack ?? () => Navigator.of(context).maybePop(),
              )
            : null);

    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: borderRadius,
        border: borderRadius != null
            ? Border.all(color: c.border)
            : showBottomBorder
            ? Border(bottom: BorderSide(color: c.border))
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (effectiveLeading != null) ...[
            effectiveLeading,
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textHeightBehavior: kCalmTextHeightBehavior,
                        strutStyle: calmStrut(14.5),
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: c.text,
                          height: 1.2,
                          leadingDistribution: TextLeadingDistribution.even,
                        ),
                      ),
                    ),
                    if (badge != null) ...[
                      const SizedBox(width: 8),
                      CalmBadge(label: badge!, tone: CalmBadgeTone.tonal),
                    ],
                  ],
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: c.text3, height: 1.2),
                  ),
                ],
              ],
            ),
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(width: 8),
            for (var i = 0; i < actions.length; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              actions[i],
            ],
          ],
        ],
      ),
    );
  }
}

/// 统一响应式页面外壳：顶部 CalmAppBar + 桌面端自动限宽居中内容区。
class CalmPageScaffold extends StatelessWidget {
  const CalmPageScaffold({
    super.key,
    required this.title,
    required this.body,
    this.subtitle,
    this.badge,
    this.showBack = true,
    this.onBack,
    this.actions = const [],
    this.maxContentWidth = 840,
    this.floatingActionButton,
  });

  final String title;
  final String? subtitle;
  final String? badge;
  final bool showBack;
  final VoidCallback? onBack;
  final List<Widget> actions;
  final double? maxContentWidth;
  final Widget body;
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    Widget content = body;
    if (maxContentWidth != null) {
      content = Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxContentWidth!),
          child: body,
        ),
      );
    }

    return Scaffold(
      backgroundColor: c.bg,
      floatingActionButton: floatingActionButton,
      body: SafeArea(
        child: Column(
          children: [
            CalmAppBar(
              title: title,
              subtitle: subtitle,
              badge: badge,
              showBack: showBack,
              onBack: onBack,
              actions: actions,
            ),
            Expanded(child: content),
          ],
        ),
      ),
    );
  }
}

/// 可折叠长文本（仅在确实溢出 maxLines 时显示「展开 / 收起」，用于漫画简介与长评论）。
class CalmExpandableText extends StatefulWidget {
  const CalmExpandableText({
    super.key,
    required this.text,
    this.maxLines = 2,
    this.style,
    this.expandLabel = '展开全部',
    this.collapseLabel = '收起',
  });

  final String text;
  final int maxLines;
  final TextStyle? style;
  final String expandLabel;
  final String collapseLabel;

  @override
  State<CalmExpandableText> createState() => _CalmExpandableTextState();
}

class _CalmExpandableTextState extends State<CalmExpandableText> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    final effectiveStyle =
        widget.style ?? TextStyle(fontSize: 12, color: c.text2, height: 1.5);

    return LayoutBuilder(
      builder: (ctx, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: effectiveStyle),
          maxLines: widget.maxLines,
          textDirection: Directionality.of(ctx),
          textScaler: MediaQuery.textScalerOf(ctx),
        )..layout(maxWidth: constraints.maxWidth);
        final overflows = painter.didExceedMaxLines;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.text,
              style: effectiveStyle,
              maxLines: _expanded ? null : widget.maxLines,
              overflow: _expanded
                  ? TextOverflow.visible
                  : TextOverflow.ellipsis,
            ),
            if (overflows)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () => setState(() => _expanded = !_expanded),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          _expanded ? widget.collapseLabel : widget.expandLabel,
                          textHeightBehavior: kCalmTextHeightBehavior,
                          strutStyle: calmStrut(11),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: c.accent,
                            height: 1.2,
                            leadingDistribution: TextLeadingDistribution.even,
                          ),
                        ),
                        Icon(
                          _expanded
                              ? Icons.keyboard_arrow_up_rounded
                              : Icons.keyboard_arrow_down_rounded,
                          size: 14,
                          color: c.accent,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// 主题色选择网格（设置页外观切换直接复用）。
class CalmColorGrid extends StatelessWidget {
  const CalmColorGrid({
    super.key,
    required this.selected,
    required this.onSelected,
    this.seeds = CalmSeed.values,
  });

  /// 当前选中的 Seed；为 null 时（比如用户自定义了任意主色）不高亮任何一项。
  final CalmSeed? selected;
  final ValueChanged<CalmSeed> onSelected;
  final List<CalmSeed> seeds;

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final seed in seeds)
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => onSelected(seed),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                height: 34,
                padding: const EdgeInsets.symmetric(horizontal: 11),
                decoration: BoxDecoration(
                  color: seed == selected ? c.accentSoft : c.surface2,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: seed == selected
                        ? c.accentBorder
                        : Colors.transparent,
                    width: 1.4,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: seed.swatch,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: seed == selected
                          ? const Icon(
                              Icons.check_rounded,
                              size: 10,
                              color: Colors.white,
                            )
                          : null,
                    ),
                    const SizedBox(width: 7),
                    Text(
                      seed.label,
                      textHeightBehavior: kCalmTextHeightBehavior,
                      strutStyle: calmStrut(11.5),
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: seed == selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: seed == selected ? c.accent : c.text2,
                        height: 1.2,
                        leadingDistribution: TextLeadingDistribution.even,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
