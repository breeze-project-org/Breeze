import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/ui/ui.dart';

/// 数据库 schema 比当前代码新时的兜底界面。
///
/// 通常出现在用户降级安装（旧版本覆盖新版本）后，SQLite 的
/// `user_version` 高于当前代码。此时不进入正常应用，只提示用户升级。
class DatabaseIncompatibleApp extends StatelessWidget {
  const DatabaseIncompatibleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: CalmTheme.build(brightness: Brightness.light),
      darkTheme: CalmTheme.build(brightness: Brightness.dark),
      home: const _DatabaseIncompatibleView(),
    );
  }
}

/// 兜底提示页：独立最小 MaterialApp 内的单页提示，不依赖业务层与导航。
class _DatabaseIncompatibleView extends StatelessWidget {
  const _DatabaseIncompatibleView();

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              // 不再套一层 CalmCard：CalmEmptyState 自带柔和面板底，
              // 再包卡片会变成“盒中盒”的厚重结构。
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const CalmEmptyState(
                    icon: Icons.storage_rounded,
                    title: 'Breeze',
                  ),
                  CalmStatusBanner(
                    title: t.database.incompatible,
                    tone: CalmTone.warning,
                  ),
                  const SizedBox(height: 18),
                  Center(
                    child: CalmButton(
                      label: t.common.close,
                      icon: Icons.power_settings_new_rounded,
                      variant: CalmButtonVariant.primary,
                      onPressed: () => SystemNavigator.pop(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
