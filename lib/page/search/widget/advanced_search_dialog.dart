import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/cubit/plugin_registry_cubit.dart';
import 'package:zephyr/page/search/cubit/search_cubit.dart';
import 'package:zephyr/plugin/plugin_registry_service.dart';
import 'package:zephyr/plugin/local_comic_plugin.dart';
import 'package:zephyr/type/pipe.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/ui/ui.dart';
import 'package:zephyr/util/text/chinese_convert.dart';

/// 高级搜索弹窗（数据源切换）。
///
/// 外部通过 `showDialog` 挂载时请用透明 `Dialog` 包一层，
/// 本组件自带 [CalmDialogSurface] 卡片（标题 / 主体 / 底部按钮齐全）。
class AdvancedSearchDialog extends StatefulWidget {
  final SearchStates initialState;
  final bool allowSourceSwitch;

  const AdvancedSearchDialog({
    super.key,
    required this.initialState,
    this.allowSourceSwitch = true,
  });

  @override
  State<AdvancedSearchDialog> createState() => _AdvancedSearchDialogState();
}

class _AdvancedSearchDialogState extends State<AdvancedSearchDialog> {
  late SearchStates _tempState;

  @override
  void initState() {
    super.initState();
    _tempState = widget.initialState.copyWith();
  }

  @override
  Widget build(BuildContext context) {
    return CalmDialogSurface(
      title: t.search.advancedSearchOptions,
      icon: Icons.tune_rounded,
      onClose: () => Navigator.of(context).pop(),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.allowSourceSwitch) ...[
            _buildSectionTitle(t.search.dataSource),
            const SizedBox(height: 8),
            _buildSourceRow(),
          ],
        ],
      ),
      actions: [
        CalmButton(
          label: t.common.cancel,
          variant: CalmButtonVariant.ghost,
          onPressed: () => Navigator.of(context).pop(),
        ),
        CalmButton(
          label: t.common.apply,
          variant: CalmButtonVariant.primary,
          onPressed: () => Navigator.of(context).pop(_tempState),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: context.calm.accent,
      ),
    );
  }

  Widget _buildSourceRow() {
    final registry = context.watch<PluginRegistryCubit>().state;
    final sources = PluginRegistryService.I.sortPlugins(
      registry.plugins.values.where(
        (plugin) =>
            plugin.isEnabled &&
            !plugin.isDeleted &&
            !isLocalComicPluginId(plugin.uuid),
      ),
    );

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: sources.map((plugin) {
        final name = registry.pluginName(plugin.uuid);
        return CalmFilterChip(
          label: name.let(convertChineseForDisplay),
          selected: _tempState.from == plugin.uuid,
          onSelected: (selected) {
            if (selected) {
              setState(() {
                _tempState = _tempState.copyWith(from: plugin.uuid);
              });
            }
          },
        );
      }).toList(),
    );
  }
}
