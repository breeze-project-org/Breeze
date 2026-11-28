import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/page/comic_read/cubit/reader_cubit.dart';
import 'package:zephyr/page/comic_read/widgets/overlay/page_count.dart';
import 'package:zephyr/ui/ui.dart';

void main() {
  Widget harness({
    required GlobalSettingCubit globalCubit,
    required ReaderCubit readerCubit,
    Brightness brightness = Brightness.light,
  }) {
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: globalCubit),
        BlocProvider.value(value: readerCubit),
      ],
      child: MaterialApp(
        theme: ThemeData(brightness: brightness),
        home: const Scaffold(
          body: Stack(
            children: [
              PageCountWidget(epPages: '12'),
            ],
          ),
        ),
      ),
    );
  }

  BoxDecoration capsuleDecoration(WidgetTester tester) {
    final decoratedBoxes = tester.widgetList<DecoratedBox>(
      find.descendant(
        of: find.byType(PageCountWidget),
        matching: find.byType(DecoratedBox),
      ),
    );
    // 内层胶囊带 color；外层只承接 shadow。
    return decoratedBoxes
        .map((box) => box.decoration as BoxDecoration)
        .firstWhere((decoration) => decoration.color != null);
  }

  testWidgets('阅读器信息条背景透明度跟随 pageInfoOpacityPercent 变化并带高斯模糊', (
    tester,
  ) async {
    final globalCubit = GlobalSettingCubit();
    addTearDown(globalCubit.close);
    final readerCubit = ReaderCubit()
      ..updateTotalSlots(12)
      ..updateCurrentSlot(0);
    addTearDown(readerCubit.close);

    globalCubit.emit(
      globalCubit.state.copyWith(
        readSetting: globalCubit.state.readSetting.copyWith(
          pageInfoShowPage: true,
          pageInfoShowNetwork: false,
          pageInfoShowBattery: false,
          pageInfoShowTime: false,
          pageInfoOpacityPercent: 20,
        ),
      ),
    );

    await tester.pumpWidget(
      harness(globalCubit: globalCubit, readerCubit: readerCubit),
    );
    await tester.pump();

    expect(capsuleDecoration(tester).color!.a, closeTo(0.2, 0.01));
    expect(
      find.descendant(
        of: find.byType(PageCountWidget),
        matching: find.byType(BackdropFilter),
      ),
      findsOneWidget,
    );

    globalCubit.emit(
      globalCubit.state.copyWith(
        readSetting: globalCubit.state.readSetting.copyWith(
          pageInfoOpacityPercent: 50,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(capsuleDecoration(tester).color!.a, closeTo(0.5, 0.01));
    expect(
      find.descendant(
        of: find.byType(PageCountWidget),
        matching: find.byType(BackdropFilter),
      ),
      findsOneWidget,
    );

    globalCubit.emit(
      globalCubit.state.copyWith(
        readSetting: globalCubit.state.readSetting.copyWith(
          pageInfoOpacityPercent: 100,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(capsuleDecoration(tester).color!.a, closeTo(1.0, 0.01));
    expect(
      find.descendant(
        of: find.byType(PageCountWidget),
        matching: find.byType(BackdropFilter),
      ),
      findsNothing,
    );
  });

  testWidgets('浅色主题配合黑色阅读背景在 50% 透明度下仍使用深色文字与白底成对显示', (
    tester,
  ) async {
    final globalCubit = GlobalSettingCubit();
    addTearDown(globalCubit.close);
    final readerCubit = ReaderCubit()
      ..updateTotalSlots(12)
      ..updateCurrentSlot(0);
    addTearDown(readerCubit.close);

    globalCubit.emit(
      globalCubit.state.copyWith(
        readSetting: globalCubit.state.readSetting.copyWith(
          readerBackgroundMode: ReaderBackgroundMode.black,
          pageInfoShowPage: true,
          pageInfoShowNetwork: false,
          pageInfoShowBattery: false,
          pageInfoShowTime: false,
          pageInfoOpacityPercent: 50,
        ),
      ),
    );

    await tester.pumpWidget(
      harness(
        globalCubit: globalCubit,
        readerCubit: readerCubit,
        brightness: Brightness.light,
      ),
    );
    await tester.pump();

    final textFinder = find.descendant(
      of: find.byType(PageCountWidget),
      matching: find.text('1/12'),
    );
    final text = tester.widget<Text>(textFinder);
    final expectedInk = tester.element(textFinder).calm.text;
    expect(text.style?.color, expectedInk);
    expect(capsuleDecoration(tester).color!.a, closeTo(0.5, 0.01));
  });
}
