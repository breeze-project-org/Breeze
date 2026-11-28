import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/router/router.gr.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/ui/ui.dart';
import 'package:zephyr/widgets/toast.dart';

class ErrorView extends StatelessWidget {
  final String errorMessage;
  final VoidCallback onRetry;

  /// 登录错误对应的插件 uuid（空 = 非登录错误）。
  /// 非空时显示“登录/重试”两个按钮，登录进 LoginRoute，回来后由 onRetry 拉数据。
  /// 只有压住全局 NeedLogin 的调用方（新两页）会传本参数，
  /// 其他页走全局登录确认框，本参数恒空。
  final String loginPluginId;

  const ErrorView({
    super.key,
    required this.errorMessage,
    required this.onRetry,
    this.loginPluginId = '',
  });

  @override
  Widget build(BuildContext context) {
    final needLogin = loginPluginId.isNotEmpty;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: CalmErrorState(
          title: needLogin ? t.navigation.needLoginTitle : t.common.error,
          errorDetail: errorMessage,
          errorDetailMaxLines: 3,
          primaryLabel: needLogin ? t.login.loginButton : null,
          onPrimary: needLogin
              ? () async {
                  await context.pushRoute(LoginRoute(from: loginPluginId));
                  onRetry();
                }
              : null,
          onRetry: onRetry,
          retryLabel: t.common.reload,
          onCopied: () => showSuccessToast(t.common.copy),
        ),
      ),
    );
  }
}
