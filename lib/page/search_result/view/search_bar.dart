import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';
import 'package:zephyr/config/router/router.gr.dart';
import 'package:zephyr/network/http/plugin/unified_comic_plugin.dart';
import 'package:zephyr/page/search/cubit/search_cubit.dart';
import 'package:zephyr/page/search/widget/search_bar.dart'
    show showPluginAdvancedSearchDialog;
import 'package:zephyr/page/search/widget/search_input_dialog.dart';
import 'package:zephyr/page/search_result/bloc/search_bloc.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/ui/ui.dart';
import 'package:zephyr/widgets/toast.dart';

class SearchResultBar extends StatelessWidget implements PreferredSizeWidget {
  const SearchResultBar({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.calm;

    return AppBar(
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: c.bg,
      foregroundColor: c.text,
      surfaceTintColor: Colors.transparent,
      titleSpacing: 0, // 清除默认边距，完全自定义
      automaticallyImplyLeading: false, // 禁用默认返回键，我们自己画
      // 2. 核心内容区域
      title: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 左侧返回按钮
            CalmIconButton(
              icon: Icons.arrow_back_rounded,
              tooltip: t.common.back,
              onPressed: () => context.maybePop(),
            ),

            // 中间的紧凑搜索入口，点击后在原位置展开完整输入框
            Expanded(
              child: BlocBuilder<SearchCubit, SearchStates>(
                builder: (context, state) => SearchQueryField(
                  query: state.searchKeyword,
                  hintText: t.search.searchHint,
                  semanticLabel: t.search.title,
                  onTap: () => _openSearchPage(context),
                ),
              ),
            ),

            // 右侧高级搜索按钮
            CalmIconButton(
              icon: Icons.tune_rounded,
              tooltip: t.search.advancedSearchOptions,
              onPressed: () {
                _search(context);
              },
            ),
          ],
        ),
      ),

      // 3. 底部分割线
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Divider(height: 1, thickness: 1, color: c.border),
      ),
    );
  }

  void _openSearchPage(BuildContext context) {
    final stack = context.router.stack;
    if (stack.length <= 1) {
      return;
    }

    final previousRoute = stack[stack.length - 2];
    if (previousRoute.name == SearchRoute.name) {
      context.maybePop();
      return;
    }

    context.replaceRoute(
      SearchRoute(
        key: ValueKey(const Uuid().v4()),
        searchState: context.read<SearchCubit>().state,
        aggregateMode: false,
      ),
    );
  }

  Future<void> _search(BuildContext context) async {
    final searchCubit = context.read<SearchCubit>();
    final source = searchCubit.state.from;
    if (source.trim().isEmpty) {
      showWarningToast(t.search.advancedSearchNotSupported);
      return;
    }
    final scheme = await _loadAdvancedSearchScheme(
      source,
      searchCubit.state.pluginExtern,
    );
    if (!context.mounted) {
      return;
    }
    if (scheme == null) {
      showWarningToast(t.search.advancedSearchNotSupported);
      return;
    }
    final states = await showPluginAdvancedSearchDialog(
      context,
      initialState: searchCubit.state,
      fields: scheme.fields,
      values: scheme.values,
    );

    if (states == null) return;
    searchCubit.update(states);
    if (!context.mounted) return;

    final searchBloc = context.read<SearchBloc>();
    searchBloc.add(SearchEvent().copyWith(searchStates: searchCubit.state));
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + 1); // 高度要加上分割线

  Future<_AdvancedSearchScheme?> _loadAdvancedSearchScheme(
    String from,
    Map<String, dynamic> extern,
  ) async {
    try {
      final response = await callUnifiedComicPlugin(
        from: from,
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
        source: response.source.isNotEmpty ? response.source : from,
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
