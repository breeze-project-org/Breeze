import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/cubit/plugin_registry_cubit.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/plugin/plugin_registry_service.dart';
import 'package:zephyr/ui/ui.dart';

/// 自定义插件顺序：拖拽排序后保存，逻辑与原实现保持一致。
Future<void> showPluginOrderDialog(BuildContext context) async {
  await showCalmDialog<void>(
    context,
    title: t.discover.customOrder,
    subtitle: t.discover.pluginManagement,
    icon: Icons.reorder_rounded,
    bodyBuilder: (_) => PluginOrderDialog(
      initialPlugins: PluginRegistryService.I.orderedPlugins(),
    ),
  );
}

/// 排序编辑区（弹窗外壳由 [showCalmDialog] 提供）。
class PluginOrderDialog extends StatefulWidget {
  const PluginOrderDialog({super.key, required this.initialPlugins});

  final List<PluginRuntimeState> initialPlugins;

  @override
  State<PluginOrderDialog> createState() => _PluginOrderDialogState();
}

class _PluginOrderDialogState extends State<PluginOrderDialog> {
  late final List<PluginRuntimeState> _plugins = [...widget.initialPlugins];
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final maxHeight = (MediaQuery.sizeOf(context).height - 300)
        .clamp(200.0, 520.0)
        .toDouble();

    return SizedBox(
      height: maxHeight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ReorderableListView.builder(
              buildDefaultDragHandles: false,
              padding: EdgeInsets.zero,
              itemCount: _plugins.length,
              itemBuilder: (context, index) {
                final plugin = _plugins[index];
                return _PluginOrderRow(
                  key: ValueKey(plugin.uuid),
                  plugin: plugin,
                  index: index,
                );
              },
              onReorderItem: (oldIndex, newIndex) {
                setState(() {
                  final plugin = _plugins.removeAt(oldIndex);
                  _plugins.insert(newIndex, plugin);
                });
              },
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              CalmButton(
                label: t.discover.resetOrder,
                variant: CalmButtonVariant.ghost,
                size: CalmButtonSize.xs,
                onPressed: _saving ? null : _reset,
              ),
              CalmButton(
                label: t.common.cancel,
                variant: CalmButtonVariant.secondary,
                size: CalmButtonSize.xs,
                onPressed: _saving
                    ? null
                    : () => Navigator.of(context).maybePop(),
              ),
              CalmButton(
                label: t.common.apply,
                variant: CalmButtonVariant.primary,
                size: CalmButtonSize.xs,
                loading: _saving,
                onPressed: _saving ? null : _save,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await PluginRegistryService.I.reorderPlugins(
      _plugins.map((plugin) => plugin.uuid).toList(),
    );
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _reset() async {
    setState(() => _saving = true);
    await PluginRegistryService.I.resetPluginOrder();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }
}

/// 排序单行：独立 widget 订阅自己的名字，热切换只重建该行。
/// 不能在 ReorderableListView itemBuilder 里用 select（sliver 上下文断言）。
class _PluginOrderRow extends StatelessWidget {
  const _PluginOrderRow({super.key, required this.plugin, required this.index});

  final PluginRuntimeState plugin;
  final int index;

  @override
  Widget build(BuildContext context) {
    final name = context.select<PluginRegistryCubit, String>(
      (cubit) => cubit.state.pluginName(plugin.uuid),
    );
    final c = context.calm;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: c.surface2.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: CalmListTile(
              title: name,
              subtitle: plugin.isActive ? null : t.discover.disabled,
              leading: Icon(
                plugin.isActive
                    ? Icons.extension_rounded
                    : Icons.extension_off_outlined,
                size: 16,
                color: plugin.isActive ? c.accent : c.text3,
              ),
            ),
          ),
          ReorderableDragStartListener(
            index: index,
            child: MouseRegion(
              cursor: SystemMouseCursors.grab,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 10,
                ),
                child: Icon(
                  Icons.drag_indicator_rounded,
                  size: 16,
                  color: c.text3,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
