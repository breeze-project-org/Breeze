import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/model/comic_info_meta.dart';
import 'package:zephyr/object_box/model.dart';
import 'package:zephyr/page/bookshelf/cubit/bookshelf_search_cubit.dart';
import 'package:zephyr/page/bookshelf/models/shelf_page_mode.dart';
import 'package:zephyr/page/bookshelf/service/comic_folder_service.dart';
import 'package:zephyr/page/bookshelf/service/comic_link_service.dart';
import 'package:zephyr/page/bookshelf/widgets/folder_shelf_page.dart';
import 'package:zephyr/util/rust/rust_loader.dart';
import 'package:zephyr/widgets/comic_simplify_entry/cover.dart';

import '../test_helper.dart';

void main() {
  setUpAll(() async {
    await initRustLib(silent: true);
    await TestDatabaseHelper.setUpTestDatabase();
  });
  tearDownAll(TestDatabaseHelper.tearDownTestDatabase);
  tearDown(TestDatabaseHelper.cleanComicFolderBoxes);

  Future<void> waitFor(
    WidgetTester tester,
    bool Function() condition, {
    required String description,
  }) async {
    for (var i = 0; i < 120; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
      if (condition()) return;
    }
    throw StateError('等待 $description 超时');
  }

  Future<GlobalSettingCubit> pumpShelf(WidgetTester tester) async {
    await LocaleSettings.setLocale(AppLocale.zhCn);
    addTearDown(LocaleSettings.useDeviceLocale);
    final global = GlobalSettingCubit();
    addTearDown(global.close);
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<GlobalSettingCubit>.value(value: global),
          BlocProvider<BookshelfSearchCubit>(
            create: (_) => BookshelfSearchCubit(),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: FolderShelfPage(
              mode: ShelfPageMode.favorite,
              isActive: true,
            ),
          ),
        ),
      ),
    );
    return global;
  }

  testWidgets('文件夹卡片显示自动封面', (tester) async {
    await tester.runAsync(() async {
      await ComicFolderService.createFolder(
        '',
        'CoverFolder',
        ComicFolderType.favorite,
      );
      final favorite = createTestFavorite('test:folder-cover')
        ..cover = const ComicImage(
          id: 'cover-id',
          url: '',
          name: '',
          path: 'folder-cover.jpg',
          extern: {'path': 'folder-cover.jpg'},
        );
      await database.favorites.put(favorite);
      await ComicLinkService.addComic(
        favorite.uniqueKey,
        '/CoverFolder',
        ComicFolderType.favorite,
      );
    });

    await pumpShelf(tester);
    await waitFor(
      tester,
      () => find.byType(CoverWidget).evaluate().any(
        (element) =>
            (element.widget as CoverWidget).path == 'folder-cover.jpg',
      ),
      description: '文件夹自动封面',
    );
    expect(find.text('CoverFolder'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('筛选的隐藏文件夹开关立即生效', (tester) async {
    late UnifiedComicFavorite rootComic;
    await tester.runAsync(() async {
      await ComicFolderService.createFolder(
        '',
        'HideMe',
        ComicFolderType.favorite,
      );
      rootComic = createTestFavorite('test:root-comic');
      await database.favorites.put(rootComic);
      await ComicLinkService.addComic(
        rootComic.uniqueKey,
        null,
        ComicFolderType.favorite,
      );
    });

    final global = await pumpShelf(tester);
    await waitFor(
      tester,
      () => find.text('HideMe').evaluate().isNotEmpty,
      description: '文件夹出现',
    );
    expect(find.text(rootComic.title), findsOneWidget);

    global.updateBookshelfSetting(
      (setting) => setting.copyWith(hideFavoriteFolders: true),
    );
    await waitFor(
      tester,
      () => find.text('HideMe').evaluate().isEmpty,
      description: '文件夹隐藏',
    );
    expect(find.text(rootComic.title), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });
}
