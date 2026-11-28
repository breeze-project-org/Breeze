import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/setting/global/sync_setting_page.dart';
import 'package:zephyr/ui/ui.dart';

class _TestGlobalSettingCubit extends GlobalSettingCubit {
  @override
  void updateState(GlobalSettingState Function(GlobalSettingState) updates) {
    emit(updates(state));
  }
}

Future<void> _pumpPage(WidgetTester tester, GlobalSettingCubit cubit) async {
  await tester.pumpWidget(
    BlocProvider<GlobalSettingCubit>.value(
      value: cubit,
      child: const MaterialApp(home: SyncSettingPage()),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('自定义同步密钥校验最小长度和空格', (tester) async {
    await LocaleSettings.setLocale(AppLocale.zhCn);
    final cubit = _TestGlobalSettingCubit();
    await _pumpPage(tester, cubit);

    await tester.tap(find.text(t.settings.customEncryptionKey));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(CalmTextField), 'short');
    await tester.tap(find.text(t.common.ok));
    await tester.pumpAndSettle();
    expect(
      find.text(t.settings.customEncryptionKeyTooShort(min: 8)),
      findsOneWidget,
    );
    expect(cubit.state.syncSetting.encryptionKey, isEmpty);

    await tester.enterText(find.byType(CalmTextField), 'has space');
    await tester.tap(find.text(t.common.ok));
    await tester.pumpAndSettle();
    expect(find.text(t.settings.customEncryptionKeyNoSpaces), findsOneWidget);
    expect(cubit.state.syncSetting.encryptionKey, isEmpty);

    await tester.enterText(find.byType(CalmTextField), 'valid-key-123');
    await tester.tap(find.text(t.common.ok));
    await tester.pumpAndSettle();
    expect(cubit.state.syncSetting.encryptionKey, 'valid-key-123');
  });

  testWidgets('已有短密钥原样不动时允许关闭对话框', (tester) async {
    await LocaleSettings.setLocale(AppLocale.zhCn);
    final cubit = _TestGlobalSettingCubit();
    cubit.emit(
      const GlobalSettingState().copyWith(
        syncSetting: const SyncSettingState().copyWith(encryptionKey: 'old'),
      ),
    );
    await _pumpPage(tester, cubit);

    await tester.tap(find.text(t.settings.customEncryptionKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.common.ok));
    await tester.pumpAndSettle();

    expect(cubit.state.syncSetting.encryptionKey, 'old');
    expect(
      find.text(t.settings.customEncryptionKeyTooShort(min: 8)),
      findsNothing,
    );
  });
}
