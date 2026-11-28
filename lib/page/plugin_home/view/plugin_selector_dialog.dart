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

/// 插件列表：图标 + 名称 + 标识，点行即选中并关闭。
class _PluginSelectorList extends StatelessWidget {
  const _PluginSelectorList({
    required this.candidates,
    required this.selectedId,
  });

  final List<String> candidates;
  final String selectedId;

  @override
  Widget build(BuildContext context) {
    if (candidates.isEmpty) {
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
      constraints: const BoxConstraints(maxHeight: 360),
      child: ListView.builder(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: candidates.length,
        itemBuilder: (context, index) {
          final c = context.calm;
          final uuid = candidates[index];
          final selected = uuid == selectedId;
          return Container(
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
