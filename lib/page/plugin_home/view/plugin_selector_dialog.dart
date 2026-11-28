import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/cubit/plugin_registry_cubit.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/ui/ui.dart';
import 'package:zephyr/widgets/plugin_icon.dart';

/// 插件选择器（CalmUI 版）：只列出标准位支持的已启用插件，不预调用探测。
///
/// 自适应弹窗（手机底部抽屉 / 大屏居中卡片）+ 选中项 accentSoft 高亮，
/// 返回值与选择回调保持不变。
Future<String?> showPluginHomeSelector(
  BuildContext context, {
  required List<String> candidates,
  required String selectedId,
}) {
  return showCalmDialog<String>(
    context,
    title: t.search.selectSource,
    icon: Icons.extension_outlined,
    maxWidth: 380,
    bodyBuilder: (_) =>
        _PluginSelectorList(candidates: candidates, selectedId: selectedId),
    actionsBuilder: (dialogContext) => [
      CalmButton(
        label: t.common.cancel,
        variant: CalmButtonVariant.ghost,
        onPressed: () => Navigator.of(dialogContext).pop(),
      ),
    ],
  );
}

/// 插件列表：图标 + 名称 + 标识，点行即选中并关闭，打开时自动定位到已选源。
class _PluginSelectorList extends StatefulWidget {
  const _PluginSelectorList({
    required this.candidates,
    required this.selectedId,
  });

  final List<String> candidates;
  final String selectedId;

  @override
  State<_PluginSelectorList> createState() => _PluginSelectorListState();
}

class _PluginSelectorListState extends State<_PluginSelectorList> {
  static const double _maxListHeight = 360;
  static const double _estimatedItemHeight = 52;
  static const int _maxRevealAttempts = 5;

  late final ScrollController _scrollController;
  GlobalKey? _selectedKey;
  late int _selectedIndex;
  int _revealAttempts = 0;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.candidates.indexOf(widget.selectedId);
    if (_selectedIndex >= 0) {
      _selectedKey = GlobalKey();
      _scrollController = ScrollController(
        initialScrollOffset: _estimatedInitialOffset(),
      );
      WidgetsBinding.instance.addPostFrameCallback((_) => _revealSelected());
    } else {
      _scrollController = ScrollController();
    }
  }

  @override
  void didUpdateWidget(covariant _PluginSelectorList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedId == widget.selectedId &&
        listEquals(oldWidget.candidates, widget.candidates)) {
      return;
    }
    _selectedIndex = widget.candidates.indexOf(widget.selectedId);
    _selectedKey = _selectedIndex >= 0 ? GlobalKey() : null;
    _revealAttempts = 0;
    if (_selectedIndex >= 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _revealSelected());
    }
  }

  double _estimatedInitialOffset() {
    if (_selectedIndex < 0) {
      return 0;
    }
    final estimatedTotal = widget.candidates.length * _estimatedItemHeight;
    if (estimatedTotal <= _maxListHeight) {
      return 0;
    }
    final maxOffset = estimatedTotal - _maxListHeight;
    final target =
        (_selectedIndex + 0.5) * _estimatedItemHeight - _maxListHeight / 2;
    return target.clamp(0.0, maxOffset);
  }

  /// 首帧布局后精确滚到当前选中源（无动画，尽量居中）。
  ///
  /// 若真实行高与估算值偏差较大导致目标尚未被 ListView 构建，
  /// 先按当前估算总高比例跳到附近，下一帧再用 ensureVisible 精定位。
  void _revealSelected() {
    if (!mounted || _revealAttempts >= _maxRevealAttempts) {
      return;
    }
    _revealAttempts++;
    final key = _selectedKey;
    if (key == null || _selectedIndex < 0) {
      return;
    }
    final targetContext = key.currentContext;
    if (targetContext == null) {
      if (_scrollController.hasClients && widget.candidates.isNotEmpty) {
        final position = _scrollController.position;
        final max = position.maxScrollExtent;
        final estimatedTotal = max + position.viewportDimension;
        final ratio = (_selectedIndex + 0.5) / widget.candidates.length;
        final target = (estimatedTotal * ratio - position.viewportDimension / 2)
            .clamp(0.0, max);
        _scrollController.jumpTo(target);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) => _revealSelected());
      return;
    }
    Scrollable.ensureVisible(
      targetContext,
      alignment: 0.5,
      alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.candidates.isEmpty) {
      return CalmEmptyState(
        icon: Icons.extension_outlined,
        title: t.plugin.noMatchingPlugins,
      );
    }

    // 名字与图标跟着全局 infos 热切换。
    final infos = context
        .select<PluginRegistryCubit, Map<String, Map<String, dynamic>>>(
          (cubit) => cubit.state.infos,
        );
    String nameOf(String uuid) {
      final name = infos[uuid]?['name']?.toString().trim() ?? '';
      return name.isNotEmpty ? name : t.common.loading;
    }

    String iconOf(String uuid) =>
        infos[uuid]?['iconUrl']?.toString().trim() ?? '';

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: _maxListHeight),
      child: ListView.builder(
        controller: _scrollController,
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: widget.candidates.length,
        itemBuilder: (context, index) {
          final c = context.calm;
          final uuid = widget.candidates[index];
          final selected = uuid == widget.selectedId;
          return Container(
            key: selected ? _selectedKey : null,
            margin: const EdgeInsets.only(bottom: 2),
            decoration: BoxDecoration(
              color: selected ? c.accentSoft : null,
              borderRadius: BorderRadius.circular(12),
            ),
            child: CalmListTile(
              title: nameOf(uuid),
              subtitle: uuid,
              leading: _PluginSelectorIcon(url: iconOf(uuid)),
              trailing: selected
                  ? Icon(Icons.check_rounded, size: 16, color: c.accent)
                  : null,
              onTap: () => Navigator.of(context).pop(uuid),
            ),
          );
        },
      ),
    );
  }
}

/// 30×30 圆角插件图标（无图标时给柔和的功能方块占位）。
class _PluginSelectorIcon extends StatelessWidget {
  const _PluginSelectorIcon({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    return ClipRRect(
      borderRadius: BorderRadius.circular(9),
      child: SizedBox(
        width: 30,
        height: 30,
        child: PluginIcon(
          url: url,
          placeholder: Container(
            color: c.surface2,
            alignment: Alignment.center,
            child: Icon(Icons.extension_outlined, size: 15, color: c.text3),
          ),
        ),
      ),
    );
  }
}
