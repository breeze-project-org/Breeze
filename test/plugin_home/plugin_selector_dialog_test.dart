import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/cubit/plugin_registry_cubit.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/plugin_home/view/plugin_selector_dialog.dart';
import 'package:zephyr/ui/ui.dart';

class _StubPluginRegistryCubit extends Cubit<PluginRegistryState>
    implements PluginRegistryCubit {
  _StubPluginRegistryCubit(super.initialState);

  @override
  Future<void> refresh() async {}
}

late BuildContext _ctx;

Future<void> _pumpHost(
  WidgetTester tester, {
  required PluginRegistryCubit registry,
  Size size = const Size(400, 800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    BlocProvider<PluginRegistryCubit>.value(
      value: registry,
      child: MaterialApp(
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
    ),
  );
  await tester.pump();
}

PluginRegistryCubit _buildRegistry(int count, {bool longUuid = false}) {
  final infos = <String, Map<String, dynamic>>{};
  for (var i = 0; i < count; i++) {
    final id = longUuid
        ? 'plugin-long-identifier-wrapping-multiple-lines-source-$i'
        : 'source-$i';
    infos[id] = {'name': '漫画源 $i'};
  }
  return _StubPluginRegistryCubit(PluginRegistryState(infos: infos));
}

void main() {
  setUp(() async {
    await LocaleSettings.setLocale(AppLocale.zhCn);
    addTearDown(() => LocaleSettings.useDeviceLocale());
  });

  testWidgets('打开选择漫画源弹窗时自动定位到底部已选中的漫画源（手机底抽屉）', (tester) async {
    final registry = _buildRegistry(24);
    addTearDown(registry.close);
    final candidates = registry.state.infos.keys.toList();
    const selectedId = 'source-21';

    await _pumpHost(tester, registry: registry, size: const Size(400, 800));

    String? picked;
    unawaited(
      showPluginHomeSelector(
        _ctx,
        candidates: candidates,
        selectedId: selectedId,
      ).then((value) => picked = value),
    );
    await tester.pumpAndSettle();

    final listView = find.byType(ListView);
    expect(listView, findsOneWidget);
    final listRect = tester.getRect(listView);

    final selectedItem = find.text('漫画源 21');
    expect(selectedItem, findsOneWidget);
    final itemRect = tester.getRect(selectedItem);
    expect(itemRect.top, greaterThanOrEqualTo(listRect.top));
    expect(itemRect.bottom, lessThanOrEqualTo(listRect.bottom));

    await tester.tap(selectedItem);
    await tester.pumpAndSettle();
    expect(picked, selectedId);
  });

  testWidgets('长标题/多行副标题下也能通过重定位精准居中显示底部选中项（桌面弹窗）', (tester) async {
    final registry = _buildRegistry(30, longUuid: true);
    addTearDown(registry.close);
    final candidates = registry.state.infos.keys.toList();
    final selectedId = candidates[20];

    await _pumpHost(tester, registry: registry, size: const Size(900, 720));

    unawaited(
      showPluginHomeSelector(
        _ctx,
        candidates: candidates,
        selectedId: selectedId,
      ),
    );
    await tester.pumpAndSettle();

    final listRect = tester.getRect(find.byType(ListView));
    final selectedItem = find.text('漫画源 20');
    expect(selectedItem, findsOneWidget);
    final itemRect = tester.getRect(selectedItem);
    expect(itemRect.top, greaterThanOrEqualTo(listRect.top));
    expect(itemRect.bottom, lessThanOrEqualTo(listRect.bottom));
    expect(
      (itemRect.center.dy - listRect.center.dy).abs(),
      lessThanOrEqualTo(50),
    );
  });

  testWidgets('短列表且选中最后一项时不会产生越界空白', (tester) async {
    final registry = _buildRegistry(3);
    addTearDown(registry.close);
    final candidates = registry.state.infos.keys.toList();

    await _pumpHost(tester, registry: registry);

    unawaited(
      showPluginHomeSelector(
        _ctx,
        candidates: candidates,
        selectedId: 'source-2',
      ),
    );
    await tester.pumpAndSettle();

    final scrollable = tester.state<ScrollableState>(
      find.descendant(
        of: find.byType(ListView),
        matching: find.byType(Scrollable),
      ),
    );
    expect(scrollable.position.pixels, 0);
    expect(find.text('漫画源 0'), findsOneWidget);
    expect(find.text('漫画源 2'), findsOneWidget);
  });
}
