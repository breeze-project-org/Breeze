import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/page/discover/view/discover_scheme_renderer.dart';
import 'package:zephyr/page/plugin_function/cubit/plugin_function_cubit.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/ui/ui.dart';

@RoutePage()
class PluginFunctionPage extends StatelessWidget {
  const PluginFunctionPage({
    super.key,
    required this.from,
    required this.functionId,
    required this.title,
    required this.onAction,
  });

  final String from;
  final String functionId;
  final String title;
  final Future<void> Function(Map<String, dynamic> action) onAction;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) =>
          PluginFunctionCubit()..load(from: from, functionId: functionId),
      child: _PluginFunctionView(
        from: from,
        title: title,
        functionId: functionId,
        onAction: onAction,
      ),
    );
  }
}

/// 插件动态功能页（CalmUI 版）：轻盈顶栏 + 三态（加载 / 错误 / 正常渲染）。
///
/// 内部仍由 [DiscoverSchemeRenderer] 解析插件下发的 QJS 页面 schema 并分派 action，
/// 本页只负责外壳与状态，cubit 状态与回调签名保持不变。
class _PluginFunctionView extends StatelessWidget {
  const _PluginFunctionView({
    required this.from,
    required this.title,
    required this.functionId,
    required this.onAction,
  });

  final String from;
  final String title;
  final String functionId;
  final Future<void> Function(Map<String, dynamic> action) onAction;

  @override
  Widget build(BuildContext context) {
    final renderer = const DiscoverSchemeRenderer();
    return CalmPageScaffold(
      title: title,
      maxContentWidth: 960,
      body: BlocBuilder<PluginFunctionCubit, PluginFunctionState>(
        builder: (context, state) {
          if (state.loading) {
            return Center(child: CalmLoading(label: t.common.loading));
          }
          if (state.error.isNotEmpty) {
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: CalmErrorState(
                    title: t.common.loadingFailed,
                    errorDetail: state.error,
                    errorDetailMaxLines: 4,
                    retryLabel: t.common.retry,
                    onRetry: () => context.read<PluginFunctionCubit>().load(
                      from: from,
                      functionId: functionId,
                    ),
                  ),
                ),
              ),
            );
          }
          return renderer.buildPage(
            context,
            from: from,
            scheme: state.scheme,
            data: state.data,
            onReachBottom: () async {},
            onAction: onAction,
            isLoadingMore: false,
            showLoadMoreRetry: false,
            onRetryLoadMore: () {},
          );
        },
      ),
    );
  }
}
