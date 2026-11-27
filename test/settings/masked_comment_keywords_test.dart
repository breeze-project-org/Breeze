import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/setting/global/content_network_setting_page.dart';

class _TestGlobalSettingCubit extends GlobalSettingCubit {
  @override
  void updateState(GlobalSettingState Function(GlobalSettingState) updates) {
    emit(updates(state));
  }
}

void main() {
  testWidgets('评论屏蔽词可增删且不影响搜索屏蔽词', (tester) async {
    await LocaleSettings.setLocale(AppLocale.zhCn);
    final cubit = _TestGlobalSettingCubit();
    await tester.pumpWidget(
      BlocProvider<GlobalSettingCubit>.value(
        value: cubit,
        child: const MaterialApp(home: ContentNetworkSettingPage()),
      ),
    );
    await tester.pump();

    await tester.tap(find.text(t.settings.maskedCommentKeywords));
    await tester.pumpAndSettle();
    final dialog = find.byType(Dialog);
    expect(
      find.descendant(
        of: dialog,
        matching: find.text(t.settings.maskedCommentKeywordsEmpty),
      ),
      findsOneWidget,
    );

    await tester.enterText(
      find.descendant(of: dialog, matching: find.byType(TextField)),
      '广告',
    );
    await tester.tap(
      find.descendant(of: dialog, matching: find.byIcon(Icons.add)),
    );
    await tester.pump();

    expect(cubit.state.maskedCommentKeywords, <String>['广告']);
    expect(cubit.state.maskedKeywords, isEmpty);

    await tester.tap(
      find.descendant(of: dialog, matching: find.byIcon(Icons.close)),
    );
    await tester.pump();
    expect(cubit.state.maskedCommentKeywords, isEmpty);
  });
}
