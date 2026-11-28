import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/object_box/model.dart';
import 'package:zephyr/page/bookshelf/bloc/folder_shelf_bloc.dart';
import 'package:zephyr/page/bookshelf/cubit/bookshelf_search_cubit.dart';
import 'package:zephyr/page/bookshelf/models/shelf_page_mode.dart';
import 'package:zephyr/page/bookshelf/service/comic_folder_service.dart';
import 'package:zephyr/page/bookshelf/widgets/folder_shelf_item.dart';
import 'package:zephyr/page/bookshelf/widgets/folder_shelf_page.dart';

import '../test_helper.dart';

/// 书架文件夹返回：进子文件夹后按系统返回逐级回退，到根放行。
///
/// 回归背景：书架 tab 嵌在 PersistentTabView 内部 Navigator 里，文件夹下钻
/// 是 bloc 状态而非路由 push；该库在非首页 tab 按返回时内部 `canPop == false`
/// 就直接切回首页，tab 内部的 PopScope 永远收不到事件（三导航时代书架是
/// tab 0，库走 maybePop 转发，所以没暴露）。
/// 修复用 LocalHistoryEntry 把「待处理返回」注册到 tab 内部路由上：
/// 有 entry → 库正常 pop → entry 消费 → bloc 回退一级；
/// 到根（entry 已清）→ 放行，库按既有逻辑切 tab/退应用。
///
/// 注意：testWidgets 测试体跑在 FakeAsync zone，真异步（SQLite IO）
/// 必须包在 tester.runAsync 里走真实时间，否则零 CPU 卡死；
/// pump 只负责刷 microtask + 重建帧。
void main() {
  // setUpAll 跑在真实 zone，可以直接做真异步初始化。
  setUpAll(() async {
    await TestDatabaseHelper.setUpTestDatabase();
  });
  tearDownAll(() async {
    await TestDatabaseHelper.tearDownTestDatabase();
  });
  tearDown(TestDatabaseHelper.cleanComicFolderBoxes);

  /// 等指定 finder 出现/消失的通用轮询（真实等待 + pump 刷重建）。
  Future<void> waitFor(
    WidgetTester tester,
    Finder finder,
    String timeoutMessage,
  ) async {
    for (var i = 0; i < 150; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump();
      if (finder.evaluate().isNotEmpty) return;
    }
    throw StateError(timeoutMessage);
  }

  /// 等指定文案出现：真实等待让后台查询回包，pump 刷重建。
  /// loading 态有 shimmer 无限动画，不能用 pumpAndSettle。
  Future<void> waitForText(WidgetTester tester, String text) async {
    await waitFor(tester, find.text(text), '等待 "$text" 出现超时');
  }

  /// 列表区域（[FolderShelfItem] 行）内的文案。
  ///
  /// 进子文件夹后面包屑（CalmBreadcrumb）会显示当前文件夹名，直接 find.text
  /// 会命中面包屑而不是列表行，所以文件夹行的断言必须限定到列表项子树。
  Finder itemText(String text) => find.descendant(
    of: find.byType(FolderShelfItem),
    matching: find.text(text),
  );

  /// 等列表行文案出现（面包屑里的同名路径段不算）。
  Future<void> waitForItemText(WidgetTester tester, String text) async {
    await waitFor(tester, itemText(text), '等待列表项 "$text" 出现超时');
  }

  /// 等列表行文案消失（load 完成后文件夹行不再出现；面包屑不算）。
  Future<void> waitForItemTextGone(WidgetTester tester, String text) async {
    for (var i = 0; i < 150; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump();
      if (itemText(text).evaluate().isEmpty) return;
    }
    throw StateError('等待列表项 "$text" 消失超时');
  }

  Future<void> pumpShelf(
    WidgetTester tester, {
    ShelfPageMode mode = ShelfPageMode.favorite,
  }) async {
    await LocaleSettings.setLocale(AppLocale.zhCn);
    addTearDown(() => LocaleSettings.useDeviceLocale());

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<GlobalSettingCubit>(create: (_) => GlobalSettingCubit()),
          BlocProvider<BookshelfSearchCubit>(
            create: (_) => BookshelfSearchCubit(),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(body: FolderShelfPage(mode: mode, isActive: true)),
        ),
      ),
    );
  }

  /// 取页面内部的 bloc：FolderShelfPage 自己创建 BlocProvider，
  /// 从 BlocConsumer 的 context 向上读。
  FolderShelfBloc shelfBlocOf(WidgetTester tester) {
    final finder = find.byWidgetPredicate(
      (widget) => widget is BlocConsumer<FolderShelfBloc, FolderShelfState>,
    );
    return BlocProvider.of<FolderShelfBloc>(tester.element(finder));
  }

  /// 主列表（GridView / CustomScrollView）的滚动位置；空态/加载态返回 null。
  double? shelfOffset(WidgetTester tester) {
    final finder = find.descendant(
      of: find.byWidgetPredicate(
        (widget) => widget is GridView || widget is CustomScrollView,
      ),
      matching: find.byType(Scrollable),
    );
    if (finder.evaluate().isEmpty) return null;
    return tester.state<ScrollableState>(finder).position.pixels;
  }

  /// 等 bloc 进入某路径且 load 完成（isLoading 结束）。
  Future<void> waitForShelfPath(
    WidgetTester tester,
    bool Function(String path) predicate,
  ) async {
    for (var i = 0; i < 150; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump();
      final state = shelfBlocOf(tester).state;
      if (!state.isLoading && predicate(state.currentPath)) return;
    }
    throw StateError('等待书架路径超时（当前 "${shelfBlocOf(tester).state.currentPath}"）');
  }

  /// 等列表滚动位置回到 [expected]（帧后恢复是异步的，多推几帧）。
  Future<void> waitForShelfOffset(WidgetTester tester, double expected) async {
    for (var i = 0; i < 100; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      final current = shelfOffset(tester);
      if (current != null && (current - expected).abs() <= 0.5) return;
    }
    throw StateError('等待滚动偏移 $expected 超时（当前 ${shelfOffset(tester)}）');
  }

  /// 当前视口内第一个匹配名称的文件夹行（按名称正则挑一个把名字取出来）。
  /// 缓存区里的行也会被构建，必须按卡片中心是否落在列表视口内过滤。
  String visibleFolderName(WidgetTester tester, RegExp pattern) {
    final viewport = tester.getRect(find.byType(GridView));
    for (final item in tester.widgetList<FolderShelfItem>(
      find.byType(FolderShelfItem),
    )) {
      final name = item.folder.name;
      if (!pattern.hasMatch(name)) continue;
      final rect = tester.getRect(find.byWidget(item));
      if (viewport.contains(rect.center)) return name;
    }
    throw StateError('当前视口内没有文件夹行');
  }

  /// 根目录向下滚动一段，返回停稳后的偏移（必须 > 0）。
  Future<double> scrollRootDown(WidgetTester tester) async {
    await tester.fling(find.byType(GridView), const Offset(0, -1200), 2000);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final offset = shelfOffset(tester);
    expect(offset, isNotNull);
    expect(offset!, greaterThan(0));
    return offset;
  }

  /// 建 [count] 个根文件夹（f00/f01...），每个挂一个子文件夹 [childName]。
  Future<void> seedFolders(
    ComicFolderType type,
    int count, {
    String childName = 'inner',
  }) async {
    final prefix = type == ComicFolderType.download ? 'd' : 'f';
    for (var i = 0; i < count; i++) {
      final name = '$prefix${i.toString().padLeft(2, '0')}';
      await ComicFolderService.createFolder('', name, type);
      await ComicFolderService.createFolder('/$name', childName, type);
    }
  }

  testWidgets('进两级文件夹后返回逐级回退，到根放行', (tester) async {
    await tester.runAsync(() async {
      final parent = await ComicFolderService.createFolder(
        '',
        'parent',
        ComicFolderType.favorite,
      );
      final all = await database.folders.getAll();
      final parentPath = ComicFolderService.folderPath(
        parent,
        syncIdMap: {for (final f in all) f.syncId: f},
      );
      await ComicFolderService.createFolder(
        parentPath,
        'child',
        ComicFolderType.favorite,
      );
    });

    await pumpShelf(tester);
    await waitForItemText(tester, 'parent');

    // 进 parent，再进 child。
    // 下面全部断言限定在列表行（FolderShelfItem）：进子文件夹后面包屑
    // CalmBreadcrumb 会同时显示当前文件夹名，未限定的 find.text 会误命中。
    await tester.tap(itemText('parent'));
    await waitForItemText(tester, 'child');
    expect(itemText('parent'), findsNothing);

    await tester.tap(itemText('child'));
    // child 为空文件夹：load 完成后文件夹行消失（显示空态）。
    await waitForItemTextGone(tester, 'child');

    // 第一次返回：child -> parent（entry 消费，路由仍在）。
    var consumed = await tester.binding.handlePopRoute();
    expect(consumed, isTrue);
    await waitForItemText(tester, 'child');

    // 第二次返回：parent -> 根。
    consumed = await tester.binding.handlePopRoute();
    expect(consumed, isTrue);
    await waitForItemText(tester, 'parent');

    // 到根：entry 已清，不再拦截，放行给导航（路由本身不被 pop）。
    consumed = await tester.binding.handlePopRoute();
    expect(consumed, isFalse);
    await tester.pump();
    expect(itemText('parent'), findsOneWidget);
    // 放行测试体结束时的 FakeAsync 检查：把一次性 Timer 跑完。
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('根目录直接返回不拦截', (tester) async {
    await tester.runAsync(() async {
      await ComicFolderService.createFolder(
        '',
        'solo',
        ComicFolderType.favorite,
      );
    });

    await pumpShelf(tester);
    await waitForText(tester, 'solo');

    final consumed = await tester.binding.handlePopRoute();
    expect(consumed, isFalse);
    await tester.pump();
    expect(find.text('solo'), findsOneWidget);
    // 放行测试体结束时的 FakeAsync 检查：把一次性 Timer 跑完。
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('进文件夹时列表先回顶再渲染', (tester) async {
    await tester.runAsync(() async {
      for (var i = 0; i < 40; i++) {
        await ComicFolderService.createFolder(
          '',
          'f${i.toString().padLeft(2, '0')}',
          ComicFolderType.favorite,
        );
      }
    });

    await pumpShelf(tester);
    // 默认倒序，最晚建的 f39 在最前（懒加载只渲染可见行，等 f00 必超时）。
    await waitForText(tester, 'f39');

    double offset() => tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .pixels;

    // 向下滚一段：offset > 0。fling 有惯性，多推几帧等它停稳再点，
    // 否则 tap 会打偏（hitTestWarning）根本没进文件夹。
    await tester.fling(find.byType(GridView), const Offset(0, -2000), 2000);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(offset(), greaterThan(0));

    // 点当前可见的任一文件夹：路径变化 → 回顶。
    final visibleName = tester
        .widgetList<Text>(find.byType(Text))
        .map((w) => w.data ?? '')
        .firstWhere((s) => RegExp(r'^f\d\d$').hasMatch(s));
    await tester.tap(find.text(visibleName));
    // 进子文件夹后面包屑仍显示文件夹名，不能用文本消失断言；
    // 等 bloc 路径切过去，再断言已回顶。
    String currentPath() => tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .context
        .read<FolderShelfBloc>()
        .state
        .currentPath;
    for (var i = 0; i < 150; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump();
      if (currentPath().isNotEmpty) break;
    }
    expect(currentPath(), isNotEmpty);
    await tester.pump();
    expect(offset(), 0);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('收藏：返回根目录恢复滚动位置，重进子目录回到顶部', (tester) async {
    await tester.runAsync(() async {
      await seedFolders(ComicFolderType.favorite, 40);
    });

    await pumpShelf(tester);
    await waitForText(tester, 'f39');

    final initialOffset = await scrollRootDown(tester);
    expect(initialOffset, greaterThan(0));

    // 视口内挑一个文件夹：卡片都在视口外时 ensureVisible 会把它拉进来。
    final folderName = visibleFolderName(tester, RegExp(r'^f\d\d$'));
    await Scrollable.ensureVisible(
      tester.element(itemText(folderName)),
      duration: Duration.zero,
    );
    await tester.pump();
    final rootOffset = shelfOffset(tester)!;
    expect(rootOffset, greaterThan(0));

    // 进子文件夹：新列表从顶部开始。
    await tester.tap(itemText(folderName));
    await waitForShelfPath(tester, (path) => path == '/$folderName');
    await waitForItemText(tester, 'inner');
    expect(shelfOffset(tester), 0);

    // 系统返回：子目录 -> 根，恢复根目录偏移。
    expect(await tester.binding.handlePopRoute(), isTrue);
    await waitForShelfPath(tester, (path) => path.isEmpty);
    await waitForItemText(tester, folderName);
    await waitForShelfOffset(tester, rootOffset);

    // 再进同一子目录：必须仍然从 0 开始，不能带上次的位置。
    await tester.tap(itemText(folderName));
    await waitForShelfPath(tester, (path) => path == '/$folderName');
    await waitForItemText(tester, 'inner');
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      expect(shelfOffset(tester), 0);
    }
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('收藏：从空文件夹返回也恢复根目录滚动位置', (tester) async {
    await tester.runAsync(() async {
      for (var i = 0; i < 40; i++) {
        await ComicFolderService.createFolder(
          '',
          'f${i.toString().padLeft(2, '0')}',
          ComicFolderType.favorite,
        );
      }
      // empty 建得最晚 → 倒序排在最顶，滚动后在视口外，直接发事件进入。
      await ComicFolderService.createFolder(
        '',
        'empty',
        ComicFolderType.favorite,
      );
    });

    await pumpShelf(tester);
    await waitForText(tester, 'f39');
    final rootOffset = await scrollRootDown(tester);

    shelfBlocOf(tester).add(const FolderShelfEnterFolder('/empty'));
    await waitForShelfPath(tester, (path) => path == '/empty');
    // 空文件夹是空态单列滚动视图，不挂主列表控制器。
    expect(shelfOffset(tester), isNull);

    expect(await tester.binding.handlePopRoute(), isTrue);
    await waitForShelfPath(tester, (path) => path.isEmpty);
    await waitForShelfOffset(tester, rootOffset);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('下载：面包屑返回与 GoBack 都恢复根目录滚动位置', (tester) async {
    await tester.runAsync(() async {
      await seedFolders(ComicFolderType.download, 40, childName: 'sub');
    });

    await pumpShelf(tester, mode: ShelfPageMode.download);
    await waitForText(tester, 'd39');

    final initialOffset = await scrollRootDown(tester);
    expect(initialOffset, greaterThan(0));

    final folderName = visibleFolderName(tester, RegExp(r'^d\d\d?$'));
    await Scrollable.ensureVisible(
      tester.element(itemText(folderName)),
      duration: Duration.zero,
    );
    await tester.pump();
    final rootOffset = shelfOffset(tester)!;
    expect(rootOffset, greaterThan(0));

    // 面包屑返回按钮：GoBack 回根并恢复。
    await tester.tap(itemText(folderName));
    await waitForShelfPath(tester, (path) => path == '/$folderName');
    await waitForItemText(tester, 'sub');
    expect(shelfOffset(tester), 0);
    // 面包屑滑入动画 220ms，等它停稳再点。
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await waitForShelfPath(tester, (path) => path.isEmpty);
    await waitForShelfOffset(tester, rootOffset);

    // 再进一次，直接发 GoBack 事件：同样恢复。
    await tester.tap(itemText(folderName));
    await waitForShelfPath(tester, (path) => path == '/$folderName');
    await waitForItemText(tester, 'sub');
    shelfBlocOf(tester).add(const FolderShelfGoBack());
    await waitForShelfPath(tester, (path) => path.isEmpty);
    await waitForShelfOffset(tester, rootOffset);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('多级目录：逐级返回分别恢复各级滚动位置', (tester) async {
    await tester.runAsync(() async {
      // parent 先建 → 倒序排在最后一行，滚到底才可见。
      await ComicFolderService.createFolder(
        '',
        'parent',
        ComicFolderType.favorite,
      );
      for (var i = 0; i < 30; i++) {
        await ComicFolderService.createFolder(
          '',
          'f${i.toString().padLeft(2, '0')}',
          ComicFolderType.favorite,
        );
      }
      for (var i = 0; i < 30; i++) {
        await ComicFolderService.createFolder(
          '/parent',
          'c${i.toString().padLeft(2, '0')}',
          ComicFolderType.favorite,
        );
      }
    });

    await pumpShelf(tester);
    await waitForText(tester, 'f29');

    // 根目录滚到底，parent 是最后一行。
    await tester.fling(find.byType(GridView), const Offset(0, -4000), 3000);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    if (itemText('parent').evaluate().isEmpty) {
      await tester.fling(find.byType(GridView), const Offset(0, -2000), 2000);
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }
    await Scrollable.ensureVisible(
      tester.element(itemText('parent')),
      duration: Duration.zero,
    );
    await tester.pump();
    final rootOffset = shelfOffset(tester)!;
    expect(rootOffset, greaterThan(0));

    // 进 parent：从顶部开始，随后在 parent 内向下滚动。
    await tester.tap(itemText('parent'));
    await waitForShelfPath(tester, (path) => path == '/parent');
    await waitForItemText(tester, 'c29');
    expect(shelfOffset(tester), 0);

    await tester.fling(find.byType(GridView), const Offset(0, -800), 2000);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final childName = visibleFolderName(tester, RegExp(r'^c\d\d$'));
    await Scrollable.ensureVisible(
      tester.element(itemText(childName)),
      duration: Duration.zero,
    );
    await tester.pump();
    final parentOffset = shelfOffset(tester)!;
    expect(parentOffset, greaterThan(0));

    // 进子目录（空文件夹）。
    await tester.tap(itemText(childName));
    await waitForShelfPath(tester, (path) => path == '/parent/$childName');
    expect(shelfOffset(tester), isNull);

    // 子目录 -> parent：恢复 parent 偏移。
    expect(await tester.binding.handlePopRoute(), isTrue);
    await waitForShelfPath(tester, (path) => path == '/parent');
    await waitForShelfOffset(tester, parentOffset);

    // parent -> 根：恢复根目录偏移。
    expect(await tester.binding.handlePopRoute(), isTrue);
    await waitForShelfPath(tester, (path) => path.isEmpty);
    await waitForShelfOffset(tester, rootOffset);
    await tester.pump(const Duration(seconds: 5));
  });
}
