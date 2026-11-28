import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/search/widget/history.dart';
import 'package:zephyr/ui/ui.dart';

class _TestGlobalSettingCubit extends GlobalSettingCubit {
  _TestGlobalSettingCubit(List<String> history) {
    updateState((current) => current.copyWith(searchHistory: history));
  }

  @override
  void updateState(GlobalSettingState Function(GlobalSettingState) updates) {
    emit(updates(state));
  }
}

Widget _app(GlobalSettingCubit cubit, String keyword) {
  return BlocProvider<GlobalSettingCubit>.value(
    value: cubit,
    child: MaterialApp(
      home: Scaffold(body: HistoryWidget(keyword: keyword)),
    ),
  );
}

// 历史词条已迁到 CalmUI 的 CalmInputChip（label 为 String），
// finder 随之换成同名控件；下面的排序/过滤断言保持不变。
List<String> _chipLabels(WidgetTester tester) => tester
    .widgetList<CalmInputChip>(find.byType(CalmInputChip))
    .map((chip) => chip.label)
    .toList();

void main() {
  setUp(() async {
    await LocaleSettings.setLocale(AppLocale.zhCn);
    addTearDown(() => LocaleSettings.useDeviceLocale());
  });

  testWidgets('输入关键词时只显示匹配的历史，清空后恢复', (tester) async {
    final cubit = _TestGlobalSettingCubit(['One Piece', 'Naruto', 'Bleach']);
    await tester.pumpWidget(_app(cubit, ''));
    await tester.pump();
    expect(_chipLabels(tester), ['One Piece', 'Naruto', 'Bleach']);

    await tester.pumpWidget(_app(cubit, 'ONE'));
    await tester.pump();
    expect(_chipLabels(tester), ['One Piece']);

    await tester.pumpWidget(_app(cubit, ''));
    await tester.pump();
    expect(_chipLabels(tester), ['One Piece', 'Naruto', 'Bleach']);
  });

  testWidgets('前缀命中优先，无匹配时显示提示', (tester) async {
    final cubit = _TestGlobalSettingCubit(['xx naruto', 'naruto shippuden']);
    await tester.pumpWidget(_app(cubit, 'naruto'));
    await tester.pump();
    expect(_chipLabels(tester), ['naruto shippuden', 'xx naruto']);

    await tester.pumpWidget(_app(cubit, 'zzz'));
    await tester.pump();
    expect(find.byType(CalmInputChip), findsNothing);
    expect(find.text(t.search.noMatchingHistory), findsOneWidget);
  });

  testWidgets('完全没有历史时显示暂无记录', (tester) async {
    final cubit = _TestGlobalSettingCubit(const <String>[]);
    await tester.pumpWidget(_app(cubit, 'zzz'));
    await tester.pump();

    expect(find.text(t.search.noHistory), findsOneWidget);
    expect(find.text(t.search.noMatchingHistory), findsNothing);
  });
}
