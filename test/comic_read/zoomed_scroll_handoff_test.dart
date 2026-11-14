import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zephyr/page/comic_read/method/zoomed_scroll_handoff.dart';
import 'package:zephyr/page/comic_read/widgets/settings/reader_scroll_experiment_switch.dart';
import 'package:zephyr/page/comic_read/widgets/settings/reader_settings_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('experimental preference defaults off and survives reloads', () async {
    SharedPreferences.setMockInitialValues({});
    await loadZoomedContinuousScrollEnabled();
    expect(zoomedContinuousScrollEnabled.value, false);
    await setZoomedContinuousScrollEnabled(true);
    zoomedContinuousScrollEnabled.value = false;
    await loadZoomedContinuousScrollEnabled();
    expect(zoomedContinuousScrollEnabled.value, true);
    await setZoomedContinuousScrollEnabled(false);
    zoomedContinuousScrollEnabled.value = true;
    await loadZoomedContinuousScrollEnabled();
    expect(zoomedContinuousScrollEnabled.value, false);
  });

  testWidgets('zoomed vertical drags continue through multiple list images', (
    tester,
  ) async {
    final scroll = ScrollController();
    final transform = TransformationController(
      Matrix4.identity()..scaleByDouble(2, 2, 1, 1),
    );
    final handoff = ZoomedScrollHandoff();
    var userDragNotifications = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 300,
            height: 400,
            child: InteractiveViewer(
              panAxis: PanAxis.horizontal,
              transformationController: transform,
              minScale: 1,
              maxScale: 4,
              onInteractionStart: (_) => handoff.start(transform),
              onInteractionUpdate: (details) => handoff.update(
                details: details,
                transformation: transform,
                scrollController: scroll,
                enabled: true,
              ),
              onInteractionEnd: handoff.end,
              child: NotificationListener<ScrollStartNotification>(
                onNotification: (notification) {
                  if (notification.dragDetails != null) {
                    userDragNotifications++;
                  }
                  return false;
                },
                child: ListView.builder(
                  controller: scroll,
                  physics: const NeverScrollableScrollPhysics(
                    parent: ClampingScrollPhysics(),
                  ),
                  itemExtent: 400,
                  itemCount: 5,
                  itemBuilder: (_, index) => ColoredBox(
                    color: index.isEven ? Colors.red : Colors.blue,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final viewer = find.byType(InteractiveViewer);
    // 视口尚未抵达缩放边界时，纵向拖动就应由列表接管。
    await tester.drag(viewer, const Offset(0, -100));
    await tester.pumpAndSettle();
    expect(scroll.offset, greaterThan(0));
    for (var i = 0; i < 8; i++) {
      await tester.drag(viewer, const Offset(0, -250));
      await tester.pumpAndSettle();
    }
    // 已越过第一张图，且没有通过缩小来恢复滚动。
    expect(scroll.offset, greaterThan(400));
    expect(userDragNotifications, greaterThan(0));
    expect(transform.value.getMaxScaleOnAxis(), closeTo(2, 0.001));

    for (var i = 0; i < 20; i++) {
      await tester.drag(viewer, const Offset(0, 250));
      await tester.pumpAndSettle();
    }
    expect(scroll.offset, closeTo(0, 0.001));

    // 双指捏合不应被当成列表拖动；横向单页模式也不参与转交。
    for (final enabled in [true, false]) {
      handoff.start(transform);
      handoff.update(
        details: ScaleUpdateDetails(
          focalPointDelta: const Offset(0, -100),
          pointerCount: enabled ? 2 : 1,
        ),
        transformation: transform,
        scrollController: scroll,
        enabled: enabled,
      );
      expect(scroll.offset, 0);
    }

    // 转交后松手应交由列表物理效果处理，取消时应释放手势状态。
    handoff.start(transform);
    handoff.update(
      details: ScaleUpdateDetails(
        focalPointDelta: const Offset(0, -100),
        pointerCount: 1,
      ),
      transformation: transform,
      scrollController: scroll,
      enabled: true,
    );
    expect(handoff.isActive, isTrue);
    handoff.end(ScaleEndDetails(
      velocity: const Velocity(pixelsPerSecond: Offset(0, -1200)),
    ));
    expect(handoff.isActive, isTrue);
    final releasedOffset = scroll.offset;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(scroll.offset, greaterThan(releasedOffset));
    handoff.cancel();
    expect(handoff.isActive, isFalse);
    final cancelledOffset = scroll.offset;
    await tester.pump(const Duration(milliseconds: 200));
    expect(scroll.offset, closeTo(cancelledOffset, 0.001));

    await tester.pumpWidget(const SizedBox.shrink());
    scroll.dispose();
    transform.dispose();
  });

  testWidgets('experimental switch starts disabled and can be toggled', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    zoomedContinuousScrollEnabled.value = false;
    addTearDown(() => zoomedContinuousScrollEnabled.value = false);
    // 与实际设置面板一样使用 material_ui 的 App、主题及 Material 祖先。
    // 旧 flutter/material.dart 控件在这个环境中会缺少匹配的祖先/本地化。
    for (final brightness in Brightness.values) {
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(brightness: brightness),
        home: const Scaffold(
          body: SingleChildScrollView(
            child: Material(child: ReaderScrollExperimentSwitch()),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Continuous scrolling while zoomed (experimental)'),
          findsOneWidget);
      expect(find.byType(SwitchListTile), findsNothing);
      expect(tester.widget<Switch>(find.byType(Switch)).value,
          false);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(zoomedContinuousScrollEnabled.value, true);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(zoomedContinuousScrollEnabled.value, false);
      expect(tester.takeException(), isNull);
    }
  });
}
