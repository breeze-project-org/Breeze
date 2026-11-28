import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/bookshelf/models/shelf_page_mode.dart';
import 'package:zephyr/page/bookshelf/widgets/bookshelf_filter_dialog.dart';
import 'package:zephyr/ui/ui.dart';

/// 记录弹窗回来的结果：`completed` 用来区分「取消返回 null」与「还没关」。
class _SheetOutcome {
  bool completed = false;
  BookshelfFilterResult? result;
}

class _SheetHost extends StatelessWidget {
  const _SheetHost({
    required this.outcome,
    required this.mode,
    required this.initialSort,
    required this.initialSources,
    required this.availableSources,
    required this.sourceOptions,
    required this.initialHideFolders,
  });

  final _SheetOutcome outcome;
  final ShelfPageMode mode;
  final String initialSort;
  final Set<String> initialSources;
  final List<String> availableSources;
  final List<BookshelfFilterSourceOption> sourceOptions;
  final bool initialHideFolders;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () async {
            final result = await showBookshelfFilterSheet(
              context,
              mode: mode,
              initialSort: initialSort,
              initialSources: initialSources,
              availableSources: availableSources,
              sourceOptions: sourceOptions,
              initialHideFolders: initialHideFolders,
            );
            outcome
              ..completed = true
              ..result = result;
          },
          child: const Text('open'),
        ),
      ),
    );
  }
}

BookshelfFilterSourceOption _option(String id) {
  return BookshelfFilterSourceOption(pluginId: id, title: '源$id');
}

/// 顶部拖拽条：宽 36 高 4 的圆角横条（由 CalmDialogSurface 提供）。
final Finder _dragHandle = find.byWidgetPredicate(
  (widget) =>
      widget is Container &&
      widget.constraints == const BoxConstraints.tightFor(width: 36, height: 4),
);

void main() {
  setUp(() async {
    // 命中测试落空直接判失败，避免「点偏了但测试照过」掩盖真实的交互问题。
    WidgetController.hitTestWarningShouldBeFatal = true;
    addTearDown(() => WidgetController.hitTestWarningShouldBeFatal = false);
    await LocaleSettings.setLocale(AppLocale.zhCn);
    addTearDown(LocaleSettings.useDeviceLocale);
  });

  Future<_SheetOutcome> openSheet(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    ShelfPageMode mode = ShelfPageMode.favorite,
    String initialSort = 'dd',
    Set<String>? initialSources,
    List<String> availableSources = const <String>[],
    List<BookshelfFilterSourceOption> sourceOptions =
        const <BookshelfFilterSourceOption>[],
    bool initialHideFolders = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final outcome = _SheetOutcome();
    await tester.pumpWidget(
      // 同一个 test 里会反复重开弹窗，换 key 丢掉旧 Navigator，避免上一次的
      // 弹层路由残留在新树里。
      MaterialApp(
        key: UniqueKey(),
        home: _SheetHost(
          outcome: outcome,
          mode: mode,
          initialSort: initialSort,
          initialSources: initialSources ?? availableSources.toSet(),
          availableSources: availableSources,
          sourceOptions: sourceOptions,
          initialHideFolders: initialHideFolders,
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return outcome;
  }

  CalmButton applyButton(WidgetTester tester) {
    return tester.widget<CalmButton>(
      find.widgetWithText(CalmButton, t.common.apply),
    );
  }

  Finder resetButton() => find.widgetWithText(CalmButton, t.common.reset);

  /// 漫画源计数徽章的语义色调：正常态 tonal，一个源都没选时切到 danger。
  CalmBadge countBadge(WidgetTester tester, String label) {
    return tester.widget<CalmBadge>(
      find.byWidgetPredicate(
        (widget) => widget is CalmBadge && widget.label == label,
      ),
    );
  }

  /// 选项行可能被压到滚动区可视范围之外，先滚进视野再正常点击。
  Future<void> tapOption(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  /// 读选项行最外层 AnimatedContainer 的装饰，用来校验选中态配色。
  BoxDecoration optionDecoration(WidgetTester tester, Finder finder) {
    final container = tester.widget<AnimatedContainer>(
      find
          .descendant(of: finder, matching: find.byType(AnimatedContainer))
          .first,
    );
    return container.decoration! as BoxDecoration;
  }

  testWidgets('窄屏以底部弹层展示，含拖拽条与完整分区', (tester) async {
    await openSheet(
      tester,
      size: const Size(390, 844),
      availableSources: const <String>['a', 'b'],
      sourceOptions: <BookshelfFilterSourceOption>[_option('a'), _option('b')],
    );

    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    expect(_dragHandle, findsOneWidget);
    expect(find.text(t.bookshelf.filter), findsOneWidget);
    expect(find.text(t.bookshelf.sort), findsOneWidget);
    expect(find.text(t.bookshelf.display), findsOneWidget);
    expect(find.text(t.bookshelf.source), findsOneWidget);
    expect(find.text(t.bookshelf.hideFolders), findsOneWidget);
    expect(find.text(t.common.reset), findsOneWidget);
    expect(find.text(t.common.apply), findsOneWidget);
  });

  testWidgets('宽屏以居中 Dialog 展示', (tester) async {
    await openSheet(
      tester,
      size: const Size(1024, 768),
      availableSources: const <String>['a', 'b'],
      sourceOptions: <BookshelfFilterSourceOption>[_option('a'), _option('b')],
    );

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    expect(_dragHandle, findsNothing);
    expect(find.text(t.bookshelf.filter), findsOneWidget);
    expect(find.text(t.bookshelf.sort), findsOneWidget);

    final dialogCenter = tester.getCenter(find.byType(Dialog));
    expect(dialogCenter.dx, closeTo(512, 1));
    expect(dialogCenter.dy, closeTo(384, 1));
  });

  testWidgets('排序/显示分区随模式变化：收藏与下载 4 项，历史 2 项且无显示分区', (tester) async {
    final sources = <String>['a'];
    final options = <BookshelfFilterSourceOption>[_option('a')];

    await openSheet(
      tester,
      mode: ShelfPageMode.favorite,
      availableSources: sources,
      sourceOptions: options,
    );
    expect(find.byType(CalmRadioTile<String>), findsNWidgets(4));
    expect(find.text(t.bookshelf.viewSortDesc), findsOneWidget);
    expect(find.text(t.bookshelf.viewSortAsc), findsOneWidget);
    expect(find.byType(CalmSwitch), findsOneWidget);
    expect(find.text(t.bookshelf.display), findsOneWidget);
    expect(find.text(t.bookshelf.hideFolders), findsOneWidget);

    await openSheet(
      tester,
      mode: ShelfPageMode.download,
      availableSources: sources,
      sourceOptions: options,
    );
    expect(find.byType(CalmRadioTile<String>), findsNWidgets(4));
    expect(find.text(t.bookshelf.viewSortDesc), findsOneWidget);
    expect(find.byType(CalmSwitch), findsOneWidget);

    await openSheet(
      tester,
      mode: ShelfPageMode.history,
      availableSources: sources,
      sourceOptions: options,
    );
    expect(find.byType(CalmRadioTile<String>), findsNWidgets(2));
    expect(find.text(t.bookshelf.viewSortDesc), findsNothing);
    expect(find.text(t.bookshelf.viewSortAsc), findsNothing);
    expect(find.text(t.bookshelf.sortDesc), findsOneWidget);
    expect(find.text(t.bookshelf.sortAsc), findsOneWidget);
    expect(find.byType(CalmSwitch), findsNothing);
    expect(find.text(t.bookshelf.display), findsNothing);
    expect(find.text(t.bookshelf.hideFolders), findsNothing);
  });

  testWidgets('点选排序 / 开关 / 反选漫画源后应用，返回准确草稿', (tester) async {
    final outcome = await openSheet(
      tester,
      availableSources: const <String>['a', 'b', 'c'],
      sourceOptions: <BookshelfFilterSourceOption>[
        _option('a'),
        _option('b'),
        _option('c'),
      ],
    );

    await tester.tap(find.text(t.bookshelf.sortAsc));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CalmSwitch));
    await tester.pumpAndSettle();
    await tapOption(tester, find.widgetWithText(CalmFilterChip, '源c'));

    await tester.tap(find.widgetWithText(CalmButton, t.common.apply));
    await tester.pumpAndSettle();

    expect(outcome.completed, isTrue);
    final result = outcome.result;
    expect(result, isNotNull);
    expect(result!.sort, 'da');
    expect(result.hideFolders, isTrue);
    expect(result.sources.length, 2);
    expect(result.sources.contains('a'), isTrue);
    expect(result.sources.contains('b'), isTrue);
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets('取消全选清空漫画源后计数为 0/N 且应用禁用，勾选后恢复', (tester) async {
    final outcome = await openSheet(
      tester,
      availableSources: const <String>['a', 'b', 'c'],
      sourceOptions: <BookshelfFilterSourceOption>[
        _option('a'),
        _option('b'),
        _option('c'),
      ],
    );

    expect(find.text('3/3'), findsOneWidget);
    expect(applyButton(tester).onPressed, isNotNull);
    expect(
      countBadge(tester, '3/3').tone,
      CalmBadgeTone.tonal,
      reason: '有选中时徽章是常规强调色',
    );

    await tester.tap(find.text(t.bookshelf.deselectAll));
    await tester.pumpAndSettle();

    expect(find.text('0/3'), findsOneWidget);
    expect(applyButton(tester).onPressed, isNull);
    expect(
      countBadge(tester, '0/3').tone,
      CalmBadgeTone.danger,
      reason: '一个源都没选时徽章切到危险色提示',
    );

    // 应用按钮此时是禁用的（onPressed 为 null），命中测试必然不落在按钮上，
    // 这里刻意用 warnIfMissed: false 验证「点了没反应」。
    await tester.tap(
      find.widgetWithText(CalmButton, t.common.apply),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(outcome.completed, isFalse);
    expect(outcome.result, isNull);

    await tapOption(tester, find.widgetWithText(CalmFilterChip, '源a'));

    expect(find.text('1/3'), findsOneWidget);
    expect(applyButton(tester).onPressed, isNotNull);
    expect(countBadge(tester, '1/3').tone, CalmBadgeTone.tonal);
  });

  testWidgets('initialSources 里的失效源被过滤，计数不越界且不出现在返回值里', (tester) async {
    final outcome = await openSheet(
      tester,
      initialSources: const <String>{'a', 'b', 'ghost'},
      availableSources: const <String>['a', 'b'],
      sourceOptions: <BookshelfFilterSourceOption>[_option('a'), _option('b')],
    );

    expect(find.text('2/2'), findsOneWidget);
    expect(find.text('3/2'), findsNothing);
    expect(
      find.text(t.bookshelf.deselectAll),
      findsOneWidget,
      reason: '有效源已全选，全选按钮应显示「取消全选」',
    );

    await tester.tap(find.widgetWithText(CalmButton, t.common.apply));
    await tester.pumpAndSettle();

    expect(outcome.result, isNotNull);
    expect(outcome.result!.sources, unorderedEquals(<String>['a', 'b']));
    expect(outcome.result!.sources.contains('ghost'), isFalse);
  });

  testWidgets('initialSources 全为失效源时按 0 选中处理，应用禁用', (tester) async {
    await openSheet(
      tester,
      initialSources: const <String>{'ghost', 'phantom'},
      availableSources: const <String>['a', 'b'],
      sourceOptions: <BookshelfFilterSourceOption>[_option('a'), _option('b')],
    );

    expect(find.text('0/2'), findsOneWidget);
    expect(find.text('2/2'), findsNothing);
    expect(applyButton(tester).onPressed, isNull);
    expect(find.text(t.common.selectAll), findsOneWidget);
  });

  testWidgets('窄屏打开后拉宽跨过 600px 断点，仍保持底部弹层不突变嵌套 Dialog', (tester) async {
    final outcome = await openSheet(
      tester,
      size: const Size(390, 844),
      availableSources: const <String>['a', 'b'],
      sourceOptions: <BookshelfFilterSourceOption>[_option('a'), _option('b')],
    );
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(_dragHandle, findsOneWidget);

    tester.view.physicalSize = const Size(1024, 768);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    expect(_dragHandle, findsOneWidget, reason: '拖拽条跟随宿主路由，不能消失');
    expect(find.text('2/2'), findsOneWidget);

    await tester.tap(find.widgetWithText(CalmButton, t.common.apply));
    await tester.pumpAndSettle();
    expect(outcome.completed, isTrue);
    expect(outcome.result, isNotNull);
  });

  testWidgets('宽屏打开后收窄到 600px 以下，Dialog 形态不退回底部弹层', (tester) async {
    await openSheet(
      tester,
      size: const Size(1024, 768),
      availableSources: const <String>['a', 'b'],
      sourceOptions: <BookshelfFilterSourceOption>[_option('a'), _option('b')],
    );
    expect(find.byType(Dialog), findsOneWidget);

    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    expect(_dragHandle, findsNothing, reason: 'Dialog 里不应冒出底部抽屉的拖拽条');
    expect(find.text('2/2'), findsOneWidget);
  });

  testWidgets('排序单选行与漫画源勾选行选中态统一使用主色高亮', (tester) async {
    await openSheet(
      tester,
      initialSort: 'da',
      initialSources: const <String>{'a'},
      availableSources: const <String>['a', 'b'],
      sourceOptions: <BookshelfFilterSourceOption>[_option('a'), _option('b')],
    );

    final calm = tester.element(find.byType(CalmRadioTile<String>).first).calm;

    final selectedSort = find.byWidgetPredicate(
      (widget) => widget is CalmRadioTile<String> && widget.value == 'da',
    );
    final unselectedSort = find.byWidgetPredicate(
      (widget) => widget is CalmRadioTile<String> && widget.value == 'dd',
    );
    final selectedSource = find.widgetWithText(CalmFilterChip, '源a');
    final unselectedSource = find.widgetWithText(CalmFilterChip, '源b');

    for (final finder in [selectedSort, unselectedSort, selectedSource]) {
      expect(finder, findsOneWidget);
    }

    expect(
      optionDecoration(tester, selectedSort).color,
      calm.accentSoft,
      reason: '选中的排序行用柔和主色底',
    );
    expect(
      optionDecoration(tester, selectedSource).color,
      calm.accentSoft,
      reason: '选中的漫画源行与排序行共用同一套选中配色',
    );
    expect(
      optionDecoration(tester, unselectedSort).color,
      isNot(calm.accentSoft),
    );
    expect(
      optionDecoration(tester, unselectedSource).color,
      isNot(calm.accentSoft),
    );

    // 两种控件的选中态都落到同一个主色上（图标 / 圆点取 c.accent）。
    final selectedSortText = tester.widget<Text>(
      find.descendant(
        of: selectedSort,
        matching: find.text(t.bookshelf.sortAsc),
      ),
    );
    expect(selectedSortText.style?.color, calm.accent);
    final selectedSourceText = tester.widget<Text>(
      find.descendant(of: selectedSource, matching: find.text('源a')),
    );
    expect(selectedSourceText.style?.color, calm.accent);
  });

  testWidgets('底部重置 / 取消 / 应用按钮之间留有间距且不重叠', (tester) async {
    await openSheet(
      tester,
      initialSort: 'da',
      initialSources: const <String>{'a'},
      availableSources: const <String>['a', 'b'],
      sourceOptions: <BookshelfFilterSourceOption>[_option('a'), _option('b')],
    );

    final resetRect = tester.getRect(resetButton());
    final cancelRect = tester.getRect(
      find.widgetWithText(CalmButton, t.common.cancel),
    );
    final applyRect = tester.getRect(
      find.widgetWithText(CalmButton, t.common.apply),
    );

    expect(
      (cancelRect.left - resetRect.right).abs(),
      greaterThanOrEqualTo(4),
      reason: '两个按钮紧贴会误触，至少保留 4px 间距',
    );
    expect(
      (applyRect.left - cancelRect.right).abs(),
      greaterThanOrEqualTo(4),
      reason: '两个按钮紧贴会误触，至少保留 4px 间距',
    );
    expect(resetRect.overlaps(cancelRect), isFalse);
    expect(cancelRect.overlaps(applyRect), isFalse);
    expect(resetRect.overlaps(applyRect), isFalse);
  });

  testWidgets('无可用漫画源时给出提示、隐藏全选按钮且应用仍可用', (tester) async {
    final outcome = await openSheet(tester);

    expect(find.text(t.bookshelf.source), findsOneWidget);
    expect(find.text(t.bookshelf.noFilterSource), findsOneWidget);
    expect(find.text(t.common.selectAll), findsNothing);
    expect(find.text(t.bookshelf.deselectAll), findsNothing);
    expect(find.byType(CalmFilterChip), findsNothing);
    expect(applyButton(tester).onPressed, isNotNull);

    await tester.tap(find.widgetWithText(CalmButton, t.common.apply));
    await tester.pumpAndSettle();

    expect(outcome.completed, isTrue);
    expect(outcome.result, isNotNull);
    expect(outcome.result!.sort, 'dd');
    expect(outcome.result!.sources, isEmpty);
    expect(outcome.result!.hideFolders, isFalse);
  });

  testWidgets('重置恢复默认草稿且不关闭弹窗，默认态下重置按钮禁用', (tester) async {
    final outcome = await openSheet(
      tester,
      initialSort: 'va',
      initialSources: const <String>{'a'},
      initialHideFolders: true,
      availableSources: const <String>['a', 'b', 'c'],
      sourceOptions: <BookshelfFilterSourceOption>[
        _option('a'),
        _option('b'),
        _option('c'),
      ],
    );

    expect(
      tester.widget<CalmButton>(resetButton()).onPressed,
      isNotNull,
      reason: '非默认草稿下重置可用',
    );
    expect(find.text('1/3'), findsOneWidget);

    await tester.tap(resetButton());
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsOneWidget);
    expect(
      tester.widget<CalmButton>(resetButton()).onPressed,
      isNull,
      reason: '恢复默认后重置按钮禁用',
    );
    expect(find.text('3/3'), findsOneWidget);
    expect(find.text(t.bookshelf.deselectAll), findsOneWidget);
    // 隐藏文件夹开关也一并回到关闭状态。
    expect(tester.widget<CalmSwitch>(find.byType(CalmSwitch)).value, isFalse);

    await tester.tap(find.widgetWithText(CalmButton, t.common.apply));
    await tester.pumpAndSettle();

    expect(outcome.result, isNotNull);
    expect(outcome.result!.sort, 'dd');
    expect(outcome.result!.hideFolders, isFalse);
    expect(outcome.result!.sources.length, 3);
  });

  testWidgets('取消与关闭按钮都返回 null', (tester) async {
    final sources = <String>['a'];
    final options = <BookshelfFilterSourceOption>[_option('a')];

    var outcome = await openSheet(
      tester,
      availableSources: sources,
      sourceOptions: options,
    );
    await tester.tap(find.widgetWithText(CalmButton, t.common.cancel));
    await tester.pumpAndSettle();
    expect(outcome.completed, isTrue);
    expect(outcome.result, isNull);
    expect(find.byType(BottomSheet), findsNothing);

    outcome = await openSheet(
      tester,
      availableSources: sources,
      sourceOptions: options,
    );
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    expect(outcome.completed, isTrue);
    expect(outcome.result, isNull);
    expect(find.byType(BottomSheet), findsNothing);

    outcome = await openSheet(
      tester,
      size: const Size(1024, 768),
      availableSources: sources,
      sourceOptions: options,
    );
    await tester.tap(find.widgetWithText(CalmButton, t.common.cancel));
    await tester.pumpAndSettle();
    expect(outcome.result, isNull);
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('极窄屏叠加长名称漫画源不出现布局溢出', (tester) async {
    await openSheet(
      tester,
      size: const Size(320, 568),
      availableSources: const <String>['a', 'b', 'c', 'd'],
      sourceOptions: const <BookshelfFilterSourceOption>[
        BookshelfFilterSourceOption(
          pluginId: 'a',
          title: '一个非常非常长的漫画源名称用于测试布局溢出情况 A',
        ),
        BookshelfFilterSourceOption(
          pluginId: 'b',
          title: '另一个特别特别长的漫画源名称用于测试布局溢出情况 B',
        ),
        BookshelfFilterSourceOption(
          pluginId: 'c',
          title: '第三个依旧很长的漫画源名称用于测试布局溢出情况 C',
        ),
        BookshelfFilterSourceOption(
          pluginId: 'd',
          title: '第四个同样很长的漫画源名称用于测试布局溢出情况 D',
        ),
      ],
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.text('4/4'), findsOneWidget);

    // 长名称需要能滚动到文案完整渲染，不触发 RenderFlex overflow。
    await tester.drag(
      find.text(t.bookshelf.sort),
      const Offset(0, -200),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
