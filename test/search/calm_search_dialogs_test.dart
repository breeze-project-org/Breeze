import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/search/widget/history.dart';
import 'package:zephyr/page/search/widget/source_select_dialog.dart';
import 'package:zephyr/page/search_result/widgets/categories_select.dart';
import 'package:zephyr/page/search_result/widgets/page_skip.dart';
import 'package:zephyr/ui/ui.dart';

/// CalmUI 迁移后的搜索系弹窗冒烟测试：
/// 统一走 showCalmDialog 后，弹窗仍能正常打开、切换取值、应用/取消返回。
class _StubGlobalSettingCubit extends GlobalSettingCubit {
  _StubGlobalSettingCubit(List<String> history) {
    updateState((current) => current.copyWith(searchHistory: history));
  }

  @override
  void updateState(GlobalSettingState Function(GlobalSettingState) updates) {
    emit(updates(state));
  }

  @override
  void resetState(
    GlobalSettingState Function(
      GlobalSettingState current,
      GlobalSettingState defaults,
    )
    updates,
  ) {
    emit(updates(state, const GlobalSettingState()));
  }
}

late BuildContext _ctx;

Future<void> _pumpHost(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: CalmTheme.build(brightness: Brightness.light),
      home: Scaffold(
        body: Builder(
          builder: (context) {
            _ctx = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  setUp(() async {
    await LocaleSettings.setLocale(AppLocale.zhCn);
    addTearDown(() => LocaleSettings.useDeviceLocale());
  });

  testWidgets('图源选择弹窗：可切换并返回应用后的结果', (tester) async {
    await _pumpHost(tester);
    Map<String, bool>? result;
    unawaited(
      showSourceSelectDialog(
        _ctx,
        initial: const {'a': true, 'b': true},
        sourceOptions: const [
          (pluginId: 'a', title: 'Alpha'),
          (pluginId: 'b', title: 'Beta'),
        ],
      ).then((value) => result = value),
    );
    await tester.pumpAndSettle();

    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);

    await tester.tap(find.text('Beta'));
    await tester.pump();
    await tester.tap(find.widgetWithText(CalmButton, t.common.apply));
    await tester.pumpAndSettle();

    expect(result, {'a': true, 'b': false});
  });

  testWidgets('跳页弹窗：非数字被过滤，页码必须 >= 1', (tester) async {
    await _pumpHost(tester);
    int? page;
    unawaited(
      showNumberInputDialog(
        context: _ctx,
        initialValue: 3,
      ).then((value) => page = value),
    );
    await tester.pumpAndSettle();

    // digitsOnly 等价行为：非数字字符不留在输入框。
    await tester.enterText(find.byType(TextField), 'a1b2');
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '12',
    );

    // 0 属于越界页码：弹窗不关，给出错误提示。
    await tester.enterText(find.byType(TextField), '0');
    await tester.tap(find.widgetWithText(CalmButton, t.common.next));
    await tester.pumpAndSettle();
    expect(page, isNull);
    expect(find.byType(TextField), findsOneWidget);

    await tester.enterText(find.byType(TextField), '12');
    await tester.tap(find.widgetWithText(CalmButton, t.common.next));
    await tester.pumpAndSettle();
    expect(page, 12);
  });

  testWidgets('分类弹窗：复选切换后返回结果', (tester) async {
    await _pumpHost(tester);
    Map<String, bool>? result;
    unawaited(
      showCategoryDialog(_ctx, const {
        '奇幻': true,
        '校园': false,
      }).then((value) => result = value),
    );
    await tester.pumpAndSettle();

    expect(find.byType(CalmCheckboxTile), findsNWidgets(2));
    await tester.tap(find.text('校园'));
    await tester.pump();
    await tester.tap(find.widgetWithText(CalmButton, t.common.ok));
    await tester.pumpAndSettle();

    expect(result, {'奇幻': true, '校园': true});
  });

  testWidgets('搜索历史：一键清空需确认，确认后清空并显示空态', (tester) async {
    final cubit = _StubGlobalSettingCubit(['One Piece', 'Naruto']);
    await tester.pumpWidget(
      BlocProvider<GlobalSettingCubit>.value(
        value: cubit,
        child: MaterialApp(
          theme: CalmTheme.build(brightness: Brightness.light),
          home: Scaffold(body: HistoryWidget(keyword: '')),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(CalmInputChip), findsNWidgets(2));

    // 取消：历史保持不动。
    await tester.tap(find.widgetWithText(CalmButton, t.search.clearHistory));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CalmButton, t.common.cancel));
    await tester.pumpAndSettle();
    expect(find.byType(CalmInputChip), findsNWidgets(2));

    // 确认：全部清空并落到空态。
    await tester.tap(find.widgetWithText(CalmButton, t.search.clearHistory));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CalmButton, t.common.confirm));
    await tester.pumpAndSettle();

    expect(find.byType(CalmInputChip), findsNothing);
    expect(find.text(t.search.noHistory), findsOneWidget);
  });
}
