import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/page/setting/global/appearance_setting_page.dart';
import 'package:zephyr/ui/ui.dart';

class _TestGlobalSettingCubit extends GlobalSettingCubit {
  @override
  void updateState(GlobalSettingState Function(GlobalSettingState) updates) {
    emit(updates(state));
  }
}

void main() {
  test('滚动条显示默认值按平台区分', () {
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(const GlobalSettingState().effectiveShowScrollbar, isFalse);
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(const GlobalSettingState().effectiveShowScrollbar, isFalse);

    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    expect(const GlobalSettingState().effectiveShowScrollbar, isTrue);
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    expect(const GlobalSettingState().effectiveShowScrollbar, isTrue);
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    expect(const GlobalSettingState().effectiveShowScrollbar, isTrue);

    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(
      const GlobalSettingState(showScrollbar: false).effectiveShowScrollbar,
      isFalse,
    );
    expect(
      const GlobalSettingState(showScrollbar: true).effectiveShowScrollbar,
      isTrue,
    );
  });

  test('旧配置缺少滚动条字段时回退到平台默认', () {
    final json = const GlobalSettingState(showScrollbar: true).toJson()
      ..remove('showScrollbar')
      ..remove('alwaysShowScrollbar');

    final restored = GlobalSettingState.fromJson(json);
    expect(restored.showScrollbar, isNull);
    expect(restored.alwaysShowScrollbar, isFalse);
  });

  testWidgets('关闭滚动条时不包 Scrollbar', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        scrollBehavior: const AppScrollBehavior(showScrollbar: false),
        home: Scaffold(
          body: ListView(children: const [SizedBox(height: 2000)]),
        ),
      ),
    );
    expect(find.byType(Scrollbar), findsNothing);
  });

  testWidgets('Android 滚动条闲置后隐藏，淡出前可拖动', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        scrollBehavior: const AppScrollBehavior(showScrollbar: true),
        home: Scaffold(
          body: ListView(
            controller: controller,
            children: const [SizedBox(height: 2000)],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final scrollbar = tester.widget<RawScrollbar>(find.byType(RawScrollbar));
    expect(scrollbar.interactive, isTrue);
    expect(scrollbar.thumbVisibility, isFalse, reason: '未开启“常驻”时，停止滚动后仍应自动隐藏');
    expect(scrollbar.timeToFade, const Duration(seconds: 2));
    expect(scrollbar.thickness, 6);

    // 滚动后 thumb 淡入并保持 2s：此窗口内可直接按住拖动。
    controller.jumpTo(200);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final gesture = await tester.startGesture(const Offset(797, 150));
    await tester.pump();
    await gesture.moveBy(const Offset(0, 100));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(controller.offset, greaterThan(200));

    // 闲置超过 timeToFade 后隐藏；同样位置向下拖走的是列表而非 thumb。
    controller.jumpTo(200);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    await tester.dragFrom(const Offset(797, 150), const Offset(0, 100));
    await tester.pumpAndSettle();
    expect(controller.offset, lessThan(200));
  });

  testWidgets('桌面端滚动条按常驻开关决定 thumb 是否常驻', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    await tester.pumpWidget(
      MaterialApp(
        scrollBehavior: const AppScrollBehavior(showScrollbar: true),
        home: Scaffold(
          body: ListView(children: const [SizedBox(height: 2000)]),
        ),
      ),
    );
    var scrollbar = tester.widget<Scrollbar>(find.byType(Scrollbar));
    expect(scrollbar.interactive, isNull);
    expect(scrollbar.thumbVisibility, isFalse);

    await tester.pumpWidget(
      MaterialApp(
        scrollBehavior: const AppScrollBehavior(
          showScrollbar: true,
          alwaysVisible: true,
        ),
        home: Scaffold(
          body: ListView(children: const [SizedBox(height: 2000)]),
        ),
      ),
    );
    scrollbar = tester.widget<Scrollbar>(find.byType(Scrollbar));
    expect(scrollbar.thumbVisibility, isTrue);
    expect(scrollbar.thickness, 6);
  });

  testWidgets('外观设置页可切换滚动条显示与常驻', (tester) async {
    await LocaleSettings.setLocale(AppLocale.zhCn);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    final cubit = _TestGlobalSettingCubit();
    await tester.pumpWidget(
      BlocProvider<GlobalSettingCubit>.value(
        value: cubit,
        child: const MaterialApp(home: AppearanceSettingPage()),
      ),
    );

    await tester.scrollUntilVisible(
      find.text(t.settings.showScrollbar),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    final showTile = find.widgetWithText(
      CalmListTile,
      t.settings.showScrollbar,
    );
    expect(
      tester
          .widget<CalmSwitch>(
            find.descendant(of: showTile, matching: find.byType(CalmSwitch)),
          )
          .value,
      isFalse,
    );
    expect(find.text(t.settings.alwaysShowScrollbar), findsNothing);

    await tester.tap(find.text(t.settings.showScrollbar));
    await tester.pump();
    expect(cubit.state.showScrollbar, isTrue);
    await tester.pump();

    await tester.scrollUntilVisible(
      find.text(t.settings.alwaysShowScrollbar),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.settings.alwaysShowScrollbar));
    await tester.pump();
    expect(cubit.state.alwaysShowScrollbar, isTrue);
  });
}
