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

GlobalSettingState _configuredState() {
  return const GlobalSettingState().copyWith(
    syncSetting: const SyncSettingState().copyWith(
      syncServiceType: SyncServiceType.webdav,
      webdavSetting: const WebDavSettingState(
        host: 'https://example.com/dav',
        username: 'user',
        password: 'pass',
      ),
      autoSync: true,
    ),
  );
}

void main() {
  test('同步间隔默认 5 分钟，单位换算正确', () {
    const setting = SyncSettingState();
    expect(setting.syncInterval, 5);
    expect(setting.syncIntervalUnit, SyncIntervalUnit.minute);
    expect(
      setting.syncIntervalUnit.durationFor(setting.syncInterval),
      const Duration(minutes: 5),
    );

    expect(
      SyncIntervalUnit.second.durationFor(30),
      const Duration(seconds: 30),
    );
    expect(SyncIntervalUnit.hour.durationFor(2), const Duration(hours: 2));
    expect(SyncIntervalUnit.minute.durationFor(0), const Duration(minutes: 1));
  });

  test('同步间隔可持久化，旧配置缺字段时回退默认值', () {
    final json = const SyncSettingState()
        .copyWith(syncInterval: 90, syncIntervalUnit: SyncIntervalUnit.second)
        .toJson();
    final restored = SyncSettingState.fromJson(json);
    expect(restored.syncInterval, 90);
    expect(restored.syncIntervalUnit, SyncIntervalUnit.second);

    final legacy = SyncSettingState.fromJson(<String, dynamic>{
      'syncServiceType': 'webdav',
    });
    expect(legacy.syncInterval, 5);
    expect(legacy.syncIntervalUnit, SyncIntervalUnit.minute);
  });

  testWidgets('同步设置页可修改间隔数值和单位', (tester) async {
    await LocaleSettings.setLocale(AppLocale.zhCn);
    final cubit = _TestGlobalSettingCubit();
    cubit.emit(_configuredState());

    await tester.pumpWidget(
      BlocProvider<GlobalSettingCubit>.value(
        value: cubit,
        child: const MaterialApp(home: SyncSettingPage()),
      ),
    );
    await tester.pump();

    await tester.tap(find.text(t.settings.syncInterval));
    await tester.pumpAndSettle();
    expect(find.byType(CalmTextField), findsOneWidget);

    await tester.enterText(find.byType(CalmTextField), '30');
    await tester.tap(find.text(t.settings.syncIntervalUnitMinute));
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.settings.syncIntervalUnitSecond).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.common.ok));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(cubit.state.syncSetting.syncInterval, 30);
    expect(cubit.state.syncSetting.syncIntervalUnit, SyncIntervalUnit.second);
  });

  testWidgets('间隔数值非法时不保存', (tester) async {
    await LocaleSettings.setLocale(AppLocale.zhCn);
    final cubit = _TestGlobalSettingCubit();
    cubit.emit(_configuredState());

    await tester.pumpWidget(
      BlocProvider<GlobalSettingCubit>.value(
        value: cubit,
        child: const MaterialApp(home: SyncSettingPage()),
      ),
    );
    await tester.pump();

    await tester.tap(find.text(t.settings.syncInterval));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(CalmTextField), '0');
    await tester.tap(find.text(t.common.ok));
    await tester.pumpAndSettle();

    expect(find.text(t.settings.syncIntervalInvalid), findsOneWidget);
    expect(cubit.state.syncSetting.syncInterval, 5);
    expect(cubit.state.syncSetting.syncIntervalUnit, SyncIntervalUnit.minute);
  });
}
