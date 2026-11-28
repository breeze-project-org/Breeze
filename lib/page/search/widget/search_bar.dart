import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/cubit/plugin_registry_cubit.dart';
import 'package:zephyr/network/http/plugin/unified_comic_plugin.dart';
import 'package:zephyr/page/search/cubit/search_cubit.dart';
import 'package:zephyr/page/search/method/on_search.dart';
import 'package:zephyr/page/search/widget/history.dart';
import 'package:zephyr/page/search/widget/search_input_dialog.dart';
import 'package:zephyr/page/search/widget/source_select_dialog.dart';
import 'package:zephyr/plugin/plugin_registry_service.dart';
import 'package:zephyr/plugin/local_comic_plugin.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/ui/ui.dart';
import 'package:zephyr/util/async/debouncer.dart';
import 'package:zephyr/widgets/multi_choice_list_dialog.dart';
import 'package:zephyr/widgets/toast.dart';

class SearchBar extends StatefulWidget {
  const SearchBar({super.key, this.aggregateMode = true});

  final bool aggregateMode;

  @override
  State<SearchBar> createState() => _SearchBarState();
}

class _SearchBarState extends State<SearchBar> {
  Map<String, bool> _aggregateSources = const {};
  // 输入时只同步 TextField 自身状态，cubit 的 keyword 用防抖延迟同步，
  // 避免每敲一个字母就触发上层 BlocBuilder 全量 rebuild。
  final _keywordDebouncer = Debouncer(milliseconds: 100);

  List<({String pluginId, String title})> _sourceOptions(BuildContext context) {
    final registry = context.read<PluginRegistryCubit>().state;
    final states = PluginRegistryService.I.sortPlugins(
      registry.plugins.values.where(
        (state) => !state.isDeleted && !isLocalComicPluginId(state.uuid),
      ),
    );
    return states
        .map(
          (state) =>
              (pluginId: state.uuid, title: registry.pluginName(state.uuid)),
        )
        .toList();
  }

  @override
  void initState() {
    super.initState();
    final initialState = context.read<SearchCubit>().state;
    _aggregateSources = Map<String, bool>.from(initialState.aggregateSources);
    HistoryWidget.registerPendingKeywordSyncCanceller(_keywordDebouncer.cancel);
  }

  @override
  void dispose() {
    HistoryWidget.registerPendingKeywordSyncCanceller(null);
    _keywordDebouncer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SearchCubit, SearchStates>(
      builder: (context, state) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            CalmIconButton(
              icon: Icons.arrow_back_rounded,
              tooltip: t.common.back,
              onPressed: () => context.maybePop(),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: SearchQueryField(
                query: state.searchKeyword,
                autoExpand: true,
                hintText: t.search.searchHint,
                semanticLabel: t.search.title,
                onChanged: (keyword) {
                  // 调度时记基线：开火时 cubit 若已被提交/dialog 回写改过，
                  // 说明这次输入已过期，直接丢弃，否则旧词盖掉新提交。
                  final scheduledBase = context
                      .read<SearchCubit>()
                      .state
                      .searchKeyword;
                  _keywordDebouncer.run(() {
                    if (!mounted) {
                      return;
                    }
                    final searchCubit = context.read<SearchCubit>();
                    if (searchCubit.state.searchKeyword != scheduledBase) {
                      return;
                    }
                    if (searchCubit.state.searchKeyword == keyword) {
                      return;
                    }
                    searchCubit.update(
                      searchCubit.state.copyWith(searchKeyword: keyword),
                    );
                  });
                },
                onSubmitted: (keyword) {
                  _keywordDebouncer.cancel();
                  onSearch(
                    context,
                    keyword,
                    aggregateMode: widget.aggregateMode,
                    aggregateSources: _aggregateSources,
                  );
                },
              ),
            ),
            const SizedBox(width: 6),
            CalmIconButton(
              icon: Icons.tune_rounded,
              tooltip: widget.aggregateMode
                  ? t.search.selectSourceTooltip
                  : t.search.advancedSearchOptions,
              onPressed: () async {
                // dialog 回写前丢弃残留输入同步，避免旧防抖把 dialog 回写盖掉。
                _keywordDebouncer.cancel();
                final searchCubit = context.read<SearchCubit>();
                if (widget.aggregateMode) {
                  final options = _sourceOptions(context);
                  if (_aggregateSources.isEmpty) {
                    _aggregateSources = {
                      for (final source in options) source.pluginId: true,
                    };
                  }
                  final selected = await showSourceSelectDialog(
                    context,
                    initial: _aggregateSources,
                    sourceOptions: options,
                  );
                  if (selected != null && mounted) {
                    searchCubit.update(
                      searchCubit.state.copyWith(
                        aggregateSources: Map<String, bool>.from(selected),
                      ),
                    );
                    setState(() {
                      _aggregateSources = selected;
                    });
                  }
                  return;
                }
                await _showSingleSourceAdvancedSearch(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showSingleSourceAdvancedSearch(BuildContext context) async {
    final searchCubit = context.read<SearchCubit>();
    final state = searchCubit.state;
    final source = state.from;

    if (source.trim().isEmpty) {
      showWarningToast(t.search.advancedSearchNotSupported);
      return;
    }
    final scheme = await _loadAdvancedSearchScheme(source, state.pluginExtern);
    if (!context.mounted) {
      return;
    }
    if (scheme == null) {
      showWarningToast(t.search.advancedSearchNotSupported);
      return;
    }

    final result = await showPluginAdvancedSearchDialog(
      context,
      initialState: state,
      fields: scheme.fields,
      values: scheme.values,
    );

    if (result == null || !context.mounted) return;
    searchCubit.update(result);
  }

  Future<_AdvancedSearchScheme?> _loadAdvancedSearchScheme(
    String source,
    Map<String, dynamic> extern,
  ) async {
    try {
      final response = await callUnifiedComicPlugin(
        pluginId: source,
        fnPath: 'getAdvancedSearchScheme',
        core: const <String, dynamic>{},
        extern: extern,
      );
      final scheme = Map<String, dynamic>.from(
        (response.data['scheme'] as Map?) ?? const <String, dynamic>{},
      );
      final data = Map<String, dynamic>.from(
        (response.data['data'] as Map?) ?? const <String, dynamic>{},
      );
      final fields = ((scheme['fields'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      if (fields.isEmpty) {
        return null;
      }

      final values = Map<String, dynamic>.from(
        (data['values'] as Map?) ?? const <String, dynamic>{},
      );
      _mergeExternValues(fields, extern, values);
      return _AdvancedSearchScheme(
        source: response.source.isNotEmpty ? response.source : source,
        fields: fields,
        values: values,
      );
    } catch (_) {
      return null;
    }
  }

  void _mergeExternValues(
    List<Map<String, dynamic>> fields,
    Map<String, dynamic> extern,
    Map<String, dynamic> values,
  ) {
    for (final field in fields) {
      final key = field['key']?.toString() ?? '';
      if (key.isEmpty || !extern.containsKey(key)) {
        continue;
      }
      final externValue = extern[key];
      if (externValue is Map) {
        values[key] = externValue.entries
            .where((entry) => entry.value == true)
            .map((entry) => entry.key.toString())
            .toList();
      } else {
        values[key] = externValue;
      }
    }
  }
}

class _AdvancedSearchScheme {
  const _AdvancedSearchScheme({
    required this.source,
    required this.fields,
    required this.values,
  });

  final String source;
  final List<Map<String, dynamic>> fields;
  final Map<String, dynamic> values;
}

/// 插件高级搜索弹窗：按插件下发的 schema 渲染 switch / text /
/// multiChoice / choice 四类字段，应用后回写 pluginExtern。
Future<SearchStates?> showPluginAdvancedSearchDialog(
  BuildContext context, {
  required SearchStates initialState,
  required List<Map<String, dynamic>> fields,
  required Map<String, dynamic> values,
}) {
  // 弹窗内的编辑副本：点应用时才回写，取消则整体丢弃。
  final draft = Map<String, dynamic>.from(values);

  return showCalmDialog<SearchStates>(
    context,
    title: t.search.advancedSearchOptions,
    icon: Icons.tune_rounded,
    maxWidth: 460,
    bodyBuilder: (_) => _AdvancedSearchFields(fields: fields, values: draft),
    actionsBuilder: (ctx) => [
      CalmButton(
        label: t.common.cancel,
        variant: CalmButtonVariant.ghost,
        onPressed: () => Navigator.of(ctx).pop(),
      ),
      CalmButton(
        label: t.common.apply,
        variant: CalmButtonVariant.primary,
        onPressed: () {
          final nextExtern = <String, dynamic>{...initialState.pluginExtern};
          for (final field in fields) {
            final key = field['key']?.toString() ?? '';
            final kind = field['kind']?.toString() ?? '';
            if (key.isEmpty) continue;
            if (kind == 'choice') {
              nextExtern[key] = draft[key];
            } else if (kind == 'multiChoice') {
              nextExtern[key] = _multiValuesOf(draft[key]);
            } else if (kind == 'switch') {
              nextExtern[key] = _switchValueOf(draft[key]);
            } else if (kind == 'text') {
              nextExtern[key] = _textValueOf(draft[key]);
            }
          }
          Navigator.of(ctx)
              .pop(initialState.copyWith(pluginExtern: nextExtern));
        },
      ),
    ],
  );
}

class _AdvancedSearchFields extends StatefulWidget {
  const _AdvancedSearchFields({required this.fields, required this.values});

  final List<Map<String, dynamic>> fields;

  /// 与调用方共享的可变草稿：子控件改它，应用时读它。
  final Map<String, dynamic> values;

  @override
  State<_AdvancedSearchFields> createState() => _AdvancedSearchFieldsState();
}

class _AdvancedSearchFieldsState extends State<_AdvancedSearchFields> {
  late final Map<String, dynamic> _values = widget.values;
  final Map<String, TextEditingController> _textControllers = {};

  @override
  void initState() {
    super.initState();
    for (final field in widget.fields) {
      if ((field['kind']?.toString() ?? 'choice') != 'text') continue;
      final key = field['key']?.toString() ?? '';
      if (key.isEmpty) continue;
      _textControllers[key] = TextEditingController(
        text: _textValueOf(_values[key]),
      );
    }
  }

  @override
  void dispose() {
    for (final controller in _textControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final field in widget.fields) _buildField(context, field),
      ],
    );
  }

  Widget _buildField(BuildContext context, Map<String, dynamic> field) {
    final c = context.calm;
    final key = field['key']?.toString() ?? '';
    final label = field['label']?.toString() ?? key;
    final kind = field['kind']?.toString() ?? 'choice';
    if (key.isEmpty) {
      return const SizedBox.shrink();
    }

    if (kind == 'switch') {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(fontSize: 12, color: c.text, height: 1.3),
              ),
            ),
            const SizedBox(width: 12),
            CalmSwitch(
              value: _switchValueOf(_values[key]),
              onChanged: (value) {
                setState(() {
                  _values[key] = value;
                });
              },
            ),
          ],
        ),
      );
    }

    if (kind == 'text') {
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionLabel(context, label),
            const SizedBox(height: 6),
            CalmTextField(
              controller: _textControllers[key],
              hintText: label,
              onChanged: (value) {
                _values[key] = value;
              },
            ),
          ],
        ),
      );
    }

    final options = ((field['options'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    if (options.isEmpty) {
      return const SizedBox.shrink();
    }
    if (kind == 'multiChoice') {
      final selected = _multiValuesOf(_values[key]);
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionLabel(context, label),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    selected.isEmpty
                        ? t.search.notSelected
                        : t.search.selectedCount(count: selected.length),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: c.text2),
                  ),
                ),
                const SizedBox(width: 10),
                CalmButton(
                  label: t.common.select,
                  size: CalmButtonSize.xs,
                  variant: CalmButtonVariant.secondary,
                  onPressed: () async {
                    final values = await showMultiChoiceListDialog(
                      context,
                      title: label,
                      options: options
                          .map(
                            (option) => MultiChoiceDialogOption(
                              label:
                                  option['label']?.toString() ??
                                  option['value']?.toString() ??
                                  '',
                              value: option['value']?.toString() ?? '',
                            ),
                          )
                          .toList(),
                      initialSelected: selected,
                      confirmText: t.common.apply,
                      useFilledConfirmButton: true,
                      width: 420,
                      height: 420,
                    );
                    if (values == null) {
                      return;
                    }
                    setState(() {
                      _values[key] = values.toList();
                    });
                  },
                ),
              ],
            ),
          ],
        ),
      );
    }

    if (kind != 'choice') {
      return const SizedBox.shrink();
    }

    final current = _values[key]?.toString() ?? '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel(context, label),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: options.map((option) {
              final value = option['value']?.toString() ?? '';
              final text = option['label']?.toString() ?? value;
              return CalmFilterChip(
                label: text,
                selected: current == value,
                onSelected: (selected) {
                  if (!selected) {
                    return;
                  }
                  setState(() {
                    _values[key] = option['value'];
                  });
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String label) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: context.calm.text2,
      ),
    );
  }
}

List<String> _multiValuesOf(dynamic value) {
  if (value is List) {
    return value.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
  }
  if (value is Map) {
    return value.entries
        .where((entry) => entry.value == true)
        .map((entry) => entry.key.toString())
        .where((e) => e.isNotEmpty)
        .toList();
  }
  return const <String>[];
}

bool _switchValueOf(dynamic value) {
  if (value is bool) {
    return value;
  }
  if (value is num) {
    return value != 0;
  }
  final text = value?.toString().toLowerCase();
  return text == 'true' || text == '1';
}

String _textValueOf(dynamic value) {
  return value == null ? '' : value.toString();
}
