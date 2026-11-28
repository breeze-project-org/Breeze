import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/discover/view/discover_scheme_renderer.dart';
import 'package:zephyr/page/plugin_function/cubit/plugin_function_cubit.dart';
import 'package:zephyr/ui/ui.dart';

/// 插件函数弹窗：外部用 `showDialog` 直接构造，这里自行包一层透明 Dialog，
/// 内部统一走 [CalmDialogSurface]（与 showCalmDialog 视觉一致）。
class PluginFunctionDialog extends StatelessWidget {
  const PluginFunctionDialog({
    super.key,
    required this.from,
    required this.functionId,
    required this.title,
    required this.onAction,
    required this.dialogWidth,
  });

  final String from;
  final String functionId;
  final String title;
  final Future<void> Function(Map<String, dynamic> action) onAction;
  final double dialogWidth;

  @override
  Widget build(BuildContext context) {
    final width = dialogWidth.clamp(280.0, 560.0).toDouble();
    final isPhone = MediaQuery.sizeOf(context).width < 600;
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      // 外部用 showDialog 直接构造：手机贴底、平板/桌面居中，与 showCalmDialog 一致。
      alignment: isPhone ? Alignment.bottomCenter : Alignment.center,
      insetPadding: isPhone
          ? const EdgeInsets.all(8)
          : const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width),
        child: BlocProvider(
          create: (_) =>
              PluginFunctionCubit()..load(from: from, functionId: functionId),
          child: CalmDialogSurface(
            title: title,
            icon: Icons.widgets_outlined,
            isBottomSheet: isPhone,
            body: SizedBox(
              width: width,
              height: 320,
              child: BlocBuilder<PluginFunctionCubit, PluginFunctionState>(
                builder: (context, state) {
                  final cubit = context.read<PluginFunctionCubit>();
                  if (state.loading) {
                    return Center(child: CalmLoading(label: t.common.loading));
                  }

                  if (state.error.isNotEmpty) {
                    return Center(
                      child: CalmErrorState(
                        title: t.common.loadingFailed,
                        errorDetail: state.error,
                        retryLabel: t.common.retry,
                        onRetry: () =>
                            cubit.load(from: from, functionId: functionId),
                      ),
                    );
                  }

                  final renderer = const DiscoverSchemeRenderer();
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
            ),
            actions: [
              CalmButton(
                label: t.common.close,
                variant: CalmButtonVariant.ghost,
                size: CalmButtonSize.xs,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
