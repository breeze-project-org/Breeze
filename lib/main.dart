import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:auto_route/auto_route.dart';
import 'package:desktop_webview_linux/desktop_webview_linux.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:event_bus/event_bus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:logger/logger.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:window_manager/window_manager.dart';
import 'package:worker_manager/worker_manager.dart';
import 'package:zephyr/config/global/global.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/config/router/router.dart';
import 'package:zephyr/cubit/comic_read_preference_cubit.dart';
import 'package:zephyr/cubit/plugin_registry_cubit.dart';
import 'package:zephyr/i18n/i18n_helper.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/i18n/system_locale_service.dart';
import 'package:zephyr/network/http/wind_http.dart';
import 'package:zephyr/util/network/doh_setting.dart';
import 'package:zephyr/util/network/network_policy.dart';
import 'package:zephyr/util/system/process_exit.dart';
import 'package:zephyr/util/network/proxy_setting.dart';
import 'package:zephyr/network/sync/sync_device_id.dart';
import 'package:zephyr/database/database.dart';
import 'package:zephyr/database/app_database.dart';
import 'package:zephyr/object_box/model.dart';
import 'package:zephyr/page/comic_follow/cubit/comic_follow_cubit.dart';
import 'package:zephyr/platform/desktop/desktop_window.dart';
import 'package:zephyr/platform/desktop/system_tray.dart';
import 'package:zephyr/platform/desktop/window_logic.dart';
import 'package:zephyr/platform/eink/eink_device.dart';
import 'package:zephyr/service/reader/reader_desktop_fullscreen_service.dart';
import 'package:zephyr/service/startup_database_snapshot_service.dart';
import 'package:zephyr/src/rust/api/qjs.dart';
import 'package:zephyr/src/rust/api/simple.dart';
import 'package:zephyr/src/rust/api/system.dart' as rust_system;
import 'package:zephyr/ui/ui.dart';
import 'package:zephyr/util/device/responsive.dart';
import 'package:zephyr/util/error/error_filter.dart';
import 'package:zephyr/util/error/uncaught_error_log.dart';
import 'package:zephyr/util/ohos/platform.dart';
import 'package:zephyr/util/ohos/file_bridge.dart';
import 'package:zephyr/util/ohos/platform_plugins.dart';
import 'package:zephyr/util/font/font_profile.dart';
import 'package:zephyr/util/storage/get_path.dart';
import 'package:zephyr/util/storage/manage_cache.dart';
import 'package:zephyr/util/rust/rust_loader.dart';
import 'package:zephyr/widgets/database_incompatible_app.dart';
import 'package:zephyr/widgets/desktop/custom_title_bar.dart';
import 'package:zephyr/widgets/desktop/intent.dart';
import 'package:zephyr/main.dart';

export 'package:zephyr/network/http/wind_http.dart'
    show WindHttp, FetchResponse, FetchException, fetch, fetchDirect;

Database? _database;
Database get database => _database!;
set database(Database value) => _database = value;

final appRouter = AppRouter();

// 全局事件总线实例
EventBus eventBus = EventBus();

var logger = Logger(
  printer: TersePrettyPrinter(),
  // filter: MyAlwaysLogFilter(),
  // output: RemoteOutput(),
);

List<String> cfIpList = [];

final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

/// 直接复用路由自己的 Navigator key：MaterialApp.router 会自建 Navigator，
/// 传进来的独立 GlobalKey 不会被挂上，只有这个 key 拿得到当前 overlay。
final navigatorKey = appRouter.navigatorKey;

class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior({
    this.showScrollbar = true,
    this.alwaysVisible = false,
  });

  final bool showScrollbar;
  final bool alwaysVisible;

  @override
  Set<PointerDeviceKind> get dragDevices => {
    ...super.dragDevices,
    PointerDeviceKind.mouse,
  };

  @override
  bool shouldNotify(covariant ScrollBehavior oldDelegate) {
    return oldDelegate is! AppScrollBehavior ||
        showScrollbar != oldDelegate.showScrollbar ||
        alwaysVisible != oldDelegate.alwaysVisible;
  }

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    // 与 Material 默认一致：横向 ScrollView 不自动加滚动条，
    // 避免 PageView / TabBarView 等周期滚动容器被加上常驻横条。
    if (!showScrollbar ||
        axisDirectionToAxis(details.direction) == Axis.horizontal) {
      return child;
    }
    // 触摸平台没有 hover 唤出滚动条，且 Android 默认 interactive=false；
    // 直接沿用 Material Scrollbar 还会在固定 600ms 后淡出，手指来不及按住。
    // 因此移动端改用 RawScrollbar：闲置后照常隐藏，但把可见窗口延长到 2s，
    // 期间可以直接拖动 thumb；“常驻”开关仍然控制是否永久显示。
    if (isTouchScrollbarPlatform) {
      final theme = Theme.of(context);
      final thumbColor = theme.platform == TargetPlatform.android
          ? theme.highlightColor
          : theme.colorScheme.onSurface.withValues(
              alpha: theme.brightness == Brightness.light ? 0.1 : 0.3,
            );
      return RawScrollbar(
        controller: details.controller,
        thumbVisibility: alwaysVisible,
        interactive: true,
        timeToFade: const Duration(seconds: 2),
        thickness: 6,
        radius: const Radius.circular(3),
        thumbColor: thumbColor,
        child: child,
      );
    }
    return Scrollbar(
      controller: details.controller,
      thumbVisibility: alwaysVisible,
      thickness: 6,
      radius: const Radius.circular(3),
      child: child,
    );
  }
}

class RemoteOutput extends LogOutput {
  final String url;

  RemoteOutput(this.url);

  @override
  void output(OutputEvent event) {
    _sendToServer(event.lines.join('\n'), event.level);
  }

  Future<void> _sendToServer(String message, Level level) async {
    try {
      await fetch(
        url,
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: {'level': level.name, 'message': '\n$message'},
        timeout: const Duration(seconds: 5),
      );
    } catch (e) {
      debugPrint(e.toString());
    }
  }
}

class MyAlwaysLogFilter extends LogFilter {
  @override
  bool shouldLog(LogEvent event) => true; // 强制通过所有日志
}

Future<void> _initOhosUncaughtErrorLogger() async {
  try {
    final logDirectory = await getLogDirectoryPath();
    await initUncaughtErrorFileLogger(logDirectory);
  } catch (_) {
    // 启动早期拿不到目录时保留控制台输出，不阻断应用启动。
  }
}

void _installFallbackErrorHandlers() {
  // 捕获 Flutter 框架层错误（如 Widget 构建中的异常）
  FlutterError.onError = (FlutterErrorDetails details) {
    logger.e(
      "Flutter Framework Error",
      error: details.exception,
      stackTrace: details.stack,
    );
    logUncaughtError(
      details.exception,
      details.stack ?? StackTrace.current,
      source: "Flutter Framework Error",
    );
  };

  // 捕获异步错误和底层错误（如 Future.error, Timer 等）
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    logger.e("Async/Platform Error", error: error, stackTrace: stack);
    logUncaughtError(error, stack, source: "Async/Platform Error");
    return true; // 表示错误已被处理
  };
}

Future<void> main(List<String> args) async {
  // 1. 基础初始化
  WidgetsFlutterBinding.ensureInitialized();
  installOhosPlatformPlugins();

  // OHOS 没有 Sentry；在启动最早期准备未捕获异常文件日志，
  // 普通业务日志不落盘，避免账号密码等敏感参数进入文件。
  if (isOhos) {
    await _initOhosUncaughtErrorLogger();
    _installFallbackErrorHandlers();
  }

  // desktop_webview_linux 必需的标题栏子进程入口
  // 不添加会导致 Linux 下 WebView 窗口关闭时 segfault 崩溃
  if (!kIsWeb && Platform.isLinux && runWebViewTitleBarWidget(args)) {
    return;
  }

  const sentryDsn = String.fromEnvironment('sentry_dsn', defaultValue: '');

  // OHOS 上 Sentry 的 native 侧不可用，直接跳过初始化（Dart 事件也没有传输通道）。
  if (sentryDsn.isEmpty || isOhos) {
    // 1. 如果是调试模式，配置 logger 捕获全局错误
    if (kDebugMode || sentryDsn.isEmpty || isOhos) {
      // OHOS 已在启动最早期安装同一组处理器；这里避免重复覆盖。
      if (!isOhos) {
        _installFallbackErrorHandlers();
      }
    }

    try {
      // 2. 执行业务初始化
      final (globalSettingCubit, pluginRegistryCubit) = await _initServices();

      final comicFollowCubit = ComicFollowCubit();
      final comicReadPreferenceCubit = ComicReadPreferenceCubit();

      runApp(
        MultiBlocProvider(
          providers: [
            BlocProvider.value(value: globalSettingCubit),
            BlocProvider.value(value: pluginRegistryCubit),
            BlocProvider.value(value: comicFollowCubit),
            BlocProvider.value(value: comicReadPreferenceCubit),
          ],
          child: const MyApp(),
        ),
      );
    } on DatabaseIncompatibleException {
      await _runDatabaseIncompatibleApp();
    } catch (e, stack) {
      // 捕获初始化阶段（_initServices）可能抛出的异常
      if (kDebugMode || sentryDsn.isEmpty || isOhos) {
        logger.e("App Setup Failed", error: e, stackTrace: stack);
        logUncaughtError(e, stack, source: "App Setup Failed");
      }
    }

    return;
  }

  // 2. 使用 Sentry 包装整个应用生命周期
  await SentryFlutter.init(
    (options) {
      options.dsn = sentryDsn;

      // 开启默认的个人信息采集（IP/Header），有助于分析用户分布
      options.sendDefaultPii = true;

      // 仅在调试模式下打印 Sentry 内部日志
      options.debug = kDebugMode;

      // --- Sentry Sponsored Business 特权配置 ---
      // 性能追踪采样率
      options.tracesSampleRate = 1.0;

      // sentry_flutter 10.0.0-alpha.5 暂不提供 Dart 侧性能剖析采样配置。

      // Android 上暂时关闭 Replay，规避原生侧生命周期卡顿/ANR 风险。
      if (Platform.isAndroid) {
        options.replay.sessionSampleRate = 0.0;
        options.replay.onErrorSampleRate = 0.0;
      } else {
        // 会话回放设置：平时抽样 10%，遇到错误时 100% 录制
        options.replay.sessionSampleRate = 0.1;
        options.replay.onErrorSampleRate = 1.0;
      }

      // 附加线程信息和堆栈，增强原生层（Rust/C++）错误分析
      options.attachThreads = true;
      options.attachStacktrace = true;

      // 插件常把 `data:` URL（整张 base64 图）当 URL 传给 fetch：
      // 失败后巨型 base64 会污染异常文本、面包屑与附件。展示层清洗，
      // 原始异常与重试判定不受影响。
      options.beforeSend = sanitizeSentryEvent;
    },
    appRunner: () async {
      try {
        final (globalSettingCubit, pluginRegistryCubit) = await _initServices();
        final comicFollowCubit = ComicFollowCubit();
        final comicReadPreferenceCubit = ComicReadPreferenceCubit();

        await addArchitectureTagsToSentry();

        runApp(
          SentryWidget(
            child: MultiBlocProvider(
              providers: [
                BlocProvider.value(value: globalSettingCubit),
                BlocProvider.value(value: pluginRegistryCubit),
                BlocProvider.value(value: comicFollowCubit),
                BlocProvider.value(value: comicReadPreferenceCubit),
              ],
              child: MyApp(),
            ),
          ),
        );
      } on DatabaseIncompatibleException {
        await _runDatabaseIncompatibleApp();
      } catch (exception, stackTrace) {
        await Sentry.captureException(exception, stackTrace: stackTrace);
      }
    },
  );
}

/// 数据库版本高于当前代码时，用最小应用提示用户升级，而不是直接崩溃。
Future<void> _runDatabaseIncompatibleApp() async {
  try {
    final systemInfo = await SystemLocaleService.getInfo();
    final appLocale = I18nHelper.toAppLocale(systemInfo.locale);
    if (appLocale != null) {
      LocaleSettings.setLocale(appLocale);
    }
  } catch (_) {
    // 语言探测失败时保持默认语言。
  }
  runApp(const DatabaseIncompatibleApp());
}

Future<(GlobalSettingCubit, PluginRegistryCubit)> _initServices() async {
  // 初始化rust
  await initRustLib();
  // 同步设备 ID 必须在打开数据库（v5→v6 迁移会用它提升版本向量）之前就绪。
  // 写入 Rust 侧缓存后，后台 isolate 也能同步读到同一个值。
  await ensureSyncDeviceId();

  // 初始化 i18n：先设置默认中文，待 GlobalSettingCubit 加载后再根据用户设置或系统语言切换。
  LocaleSettings.setLocale(AppLocale.enUs);
  I18nHelper.setRustErrorLanguage(AppLocale.enUs);

  // 初始化工作线程
  await workerManager.init(isolatesCount: Platform.numberOfProcessors);

  // 关掉rust端，主要是anyhow的堆栈调用信息
  enableStacktrace(enabled: false);

  // release 下可用 --dart-define=rust_log=true 打开 Rust 日志；
  // 级别仍可被 RUST_LOG 覆盖（默认 debug，DNS/HTTP 噪音已静音）。
  enableRustLog(enabled: kDebugMode || const bool.fromEnvironment('rust_log'));

  if (kDebugMode) {
    setQjsErrorStackEnabled(enabled: true);
    // debug 下展示原样，方便调试；精简开关默认关闭。
    setSimplifyPluginErrorDisplay(enabled: false);
    // 配置http代理，方便开发测试
    await _tryApplyHttpProxyFromEnv();
  } else {
    setQjsErrorStackEnabled(enabled: false);
    // release 下 logAddress 已知后才决定是否精简，见下方日志转发分支。
    setSimplifyPluginErrorDisplay(enabled: false);
  }

  // 初始化前台任务（Android 专用）
  if (Platform.isAndroid) {
    FlutterForegroundTask.initCommunicationPort();
  }

  // 重采样触控刷新率
  GestureBinding.instance.resamplingEnabled = true;

  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      statusBarColor: Colors.transparent,
    ),
  );

  final isWin = Platform.isWindows;
  final cache = PaintingBinding.instance.imageCache;

  // 设置图片缓存数量和内存占用大小（桌面端设置的稍微大点）
  cache.maximumSizeBytes = 200 * 1024 * 1024 * (isWin ? 3 : 1);
  cache.maximumSize = 50 * (isWin ? 3 : 1);

  // 如果是手机的话就固定为只能使用横屏模式
  if (!isTabletWithOutContext()) {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }

  final dbRoot = await getDbPath();
  database = await Database.open(
    path: '$dbRoot/breeze_db.sqlite3',
    legacyObjectBoxDir: '$dbRoot/breeze_db',
    archiveLegacyData: true,
  );
  final settingFuture = database.userSettings.get();
  final setting = await settingFuture;
  if (setting == null) {
    await database.userSettings.put(UserSetting());
  }

  final globalSettingCubit = GlobalSettingCubit();
  await globalSettingCubit.initBox();
  setHttpRequestsBlocked(
    blocked: globalSettingCubit.state.blockRustHttpRequests,
  );

  // 根据用户设置或系统语言初始化应用语言
  if (globalSettingCubit.state.localeFollowsSystem) {
    final systemInfo = await SystemLocaleService.getInfo();
    await globalSettingCubit.setSystemLocale(systemInfo.locale);
  } else {
    await globalSettingCubit.setLocale(globalSettingCubit.state.locale);
  }

  await FontProfileController.instance.init();

  final pluginRegistryCubit = PluginRegistryCubit();

  if (globalSettingCubit.state.needCleanCache) {
    await clearCache(await getCachePath());
  }

  applyProxySetting(globalSettingCubit.state.proxySetting);
  applyDohSetting(globalSettingCubit.state.dohSetting);
  applyPrivateNetworkPolicy(
    blockPrivateNetwork: globalSettingCubit.state.blockPrivateNetwork,
  );

  // 设置日志转发（包含flutter和qjs的日志）
  final logAddress = globalSettingCubit.state.logAddress;

  if (logAddress.trim().isNotEmpty) {
    if (!kDebugMode) {
      logger = Logger(
        printer: TersePrettyPrinter(),
        filter: MyAlwaysLogFilter(),
        output: RemoteOutput(logAddress),
      );
    }
    setLogHttpForward(url: logAddress);
    setQjsErrorStackEnabled(enabled: true);
    // release + 配了日志转发：Rust 下发完整堆栈供远端诊断，
    // 本地展示精简为 Error: 一行；debug 下保持原样。
    // 调试页改动 logAddress 后重启生效。
    if (!kDebugMode) {
      setSimplifyPluginErrorDisplay(enabled: true);
    }
  }

  // 关掉缓存定时清理(rust端)
  setHostCacheGcEnabled(enabled: false);

  setTlsVerifyEnabled(enabled: false);

  await applyEinkAutoDetection(globalSettingCubit);

  // Rust 已在本函数开头初始化；快照查询和 Brotli 压缩都在后台 isolate 执行，
  // 再延后到首帧之后，避免启动阶段和 UI 争抢 CPU/磁盘。
  WidgetsBinding.instance.addPostFrameCallback((_) {
    Future<void>.delayed(
      const Duration(seconds: 2),
      saveStartupDatabaseSnapshot,
    ).ignore();
  });

  return (globalSettingCubit, pluginRegistryCubit);
}

Future<void> _tryApplyHttpProxyFromEnv() async {
  if (!kDebugMode) return;

  final rawProxy = await _readProxyFromEnvAsset();
  if (rawProxy == null || rawProxy.isEmpty) return;

  final proxyUrl =
      rawProxy.startsWith('http://') || rawProxy.startsWith('https://')
      ? rawProxy
      : 'http://$rawProxy';

  final reachable = await _probeProxyWithTimeout(proxyUrl);
  if (!reachable) return;

  applyProxySetting(
    ProxySettingState(enabled: true, type: ProxyType.http, address: proxyUrl),
  );
}

Future<String?> _readProxyFromEnvAsset() async {
  try {
    final content = await rootBundle.loadString('.env.proxy');
    for (final rawLine in const LineSplitter().convert(content)) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      if (!line.startsWith('proxy=')) continue;
      final value = line.substring('proxy='.length).trim();
      if (value.isNotEmpty) return value;
    }
  } catch (_) {
    return null;
  }
  return null;
}

Future<bool> _probeProxyWithTimeout(String proxyUrl) async {
  try {
    final response = await WindHttp(
      httpProxy: proxyUrl,
      connectTimeout: const Duration(seconds: 3),
      receiveTimeout: const Duration(seconds: 3),
      followRedirects: false,
    ).fetch('http://www.gstatic.com/generate_204');
    return response.status >= 200 && response.status < 500;
  } on FetchException catch (e) {
    return e.status >= 200 && e.status < 500;
  } catch (_) {
    return false;
  }
}

Widget _buildDynamicColor({
  required Widget Function(ColorScheme? light, ColorScheme? dark) builder,
}) {
  if (isOhos) {
    // OHOS 没有 dynamic_color 平台实现，直接跳过插件调用。
    return builder(null, null);
  }
  return DynamicColorBuilder(builder: builder);
}

Future<void> addArchitectureTagsToSentry() async {
  try {
    final is64Bit = sizeOf<Pointer>() == 8;
    final appArchitecture = is64Bit ? '64-bit' : '32-bit';

    String deviceSupportedAbis = 'unknown';

    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      deviceSupportedAbis = androidInfo.supportedAbis.join(', ');
    } else if (Platform.isIOS) {
      final iosInfo = await DeviceInfoPlugin().iosInfo;
      deviceSupportedAbis = 'arm64 (${iosInfo.utsname.machine})';
    } else if (isOhos) {
      final info = await getOhosDeviceInfo();
      deviceSupportedAbis = info?.abis.join(', ') ?? 'unknown';
    } else if (Platform.isWindows) {
      deviceSupportedAbis =
          Platform.environment['PROCESSOR_ARCHITECTURE'] ?? 'unknown';
    } else if (Platform.isLinux) {
      try {
        final result = Process.runSync('uname', ['-m']);
        deviceSupportedAbis = result.stdout.toString().trim();
      } catch (_) {
        deviceSupportedAbis = 'unknown';
      }
    } else if (Platform.isMacOS) {
      final macInfo = await DeviceInfoPlugin().macOsInfo;
      deviceSupportedAbis = macInfo.arch;
    }

    Sentry.configureScope((scope) {
      scope.setTag('app_runtime_arch', appArchitecture);
      scope.setTag('device_supported_abis', deviceSupportedAbis);

      scope.addBreadcrumb(
        Breadcrumb(
          message:
              'Architecture Info - App: $appArchitecture, Device: $deviceSupportedAbis',
          category: 'system.architecture',
        ),
      );
    });
  } catch (e, stack) {
    await Sentry.captureException(e, stackTrace: stack);
  }
}

/// 桌面关闭确认框的两个出口；取消用 null 表示。
enum _CloseConfirmAction { hide, close }

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  /// 主窗口事件监听句柄，dispose 时注销。
  ListenerId? _windowListenerId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      _attachWindowEvents();
      WindowLogic.initWindow(context);
    }
    initSystemTray(
      onShowWindow: showMainWindow,
      onExitApp: _performGracefulExit,
    );

    if (Platform.isLinux) {
      _linuxWindowChannel.setMethodCallHandler((call) async {
        if (call.method == 'windowCloseRequested') {
          _handleCloseRequest();
        }
      });
    }

    // 启动命名管道监听，用于接收外部退出信号（仅 Windows）
    if (Platform.isWindows) {
      rust_system.startShutdownListener().listen((shouldExit) {
        if (shouldExit) {
          _performGracefulExit();
        }
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      final listenerId = _windowListenerId;
      if (listenerId != null) {
        mainWindow?.removeListener(listenerId);
        _windowListenerId = null;
      }
      disposeSystemTray();
    }
    super.dispose();
  }

  /// 注册主窗口事件监听（窗口尚未创建时下一帧重试一次）。
  void _attachWindowEvents() {
    if (_windowListenerId != null) return;
    final window = mainWindow;
    if (window == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _windowListenerId != null) return;
        final retryWindow = mainWindow;
        if (retryWindow == null) {
          logger.w('主窗口事件监听注册失败：窗口尚未就绪');
          return;
        }
        _windowListenerId = retryWindow.addListener(_handleWindowEvent);
      });
      return;
    }
    _windowListenerId = window.addListener(_handleWindowEvent);
  }

  void _handleWindowEvent(WindowEvent event) {
    switch (event) {
      case WindowResizedEvent():
      case WindowMovedEvent():
        WindowLogic.saveWindowState(context);
      // 最大化/还原（含从最小化恢复）都会影响保存的尺寸，立即落盘。
      case WindowMaximizedEvent():
      case WindowRestoredEvent():
        WindowLogic.saveWindowStateImmediately(context);
      case WindowFocusedEvent():
        if (mounted) setState(() {});
      // 关闭请求一律先拦下，由 _handleCloseRequest 决定隐藏还是退出。
      case WindowCloseRequestedEvent(:final request):
        request.cancel();
        _handleCloseRequest();
      // ignore: unreachable_switch_case
      case _:
        break;
    }
  }

  /// 应用级退出请求不一定经过窗口关闭回调，退出前补存一次窗口状态。
  @override
  Future<AppExitResponse> didRequestAppExit() async {
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      await WindowLogic.saveWindowStateImmediately(context);
    }
    return AppExitResponse.exit;
  }

  /// 立即隐藏窗口再退出，让用户感知不到 Dart VM 清理的延迟
  Future<void> _forceExit() async {
    await WindowLogic.saveWindowStateImmediately(context);
    // 先隐藏窗口（同步 FFI 调用，零延迟），再强杀进程，
    // 让用户感知不到 Dart VM 回收的延迟。
    mainWindow?.hide();
    await database.close();
    nuclearKillProcess();
  }

  bool _handlingCloseRequest = false;

  static const MethodChannel _linuxWindowChannel = MethodChannel(
    'breeze/linux/window',
  );

  Future<void> _handleCloseRequest() async {
    if (_handlingCloseRequest) return;
    _handlingCloseRequest = true;
    try {
      final closeBehavior = await WindowLogic.loadCloseBehavior();
      switch (closeBehavior) {
        case DesktopCloseBehavior.hide:
          await _hideWindow();
          return;
        case DesktopCloseBehavior.close:
          await _forceExit();
          return;
        case DesktopCloseBehavior.ask:
          break;
      }

      if (Platform.isLinux) {
        mainWindow?.show();
      }
      final dialogContext = appRouter.navigatorKey.currentContext;
      if (dialogContext == null || !dialogContext.mounted) {
        await _forceExit();
        return;
      }
      var rememberChoice = false;
      final choice = await showCalmDialog<_CloseConfirmAction>(
        dialogContext,
        title: '提示',
        subtitle: '隐藏到托盘或关闭程序',
        icon: Icons.power_settings_new_rounded,
        tone: CalmTone.warning,
        bodyBuilder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) => CalmCheckboxTile(
            label: '记住我的选择',
            value: rememberChoice,
            onChanged: (value) => setDialogState(() => rememberChoice = value),
          ),
        ),
        actionsBuilder: (ctx) => [
          CalmButton(
            label: '取消',
            variant: CalmButtonVariant.ghost,
            onPressed: () => Navigator.of(ctx).pop(),
          ),
          CalmButton(
            label: '隐藏',
            variant: CalmButtonVariant.tonal,
            onPressed: () => Navigator.of(ctx).pop(_CloseConfirmAction.hide),
          ),
          CalmButton(
            label: '关闭',
            variant: CalmButtonVariant.danger,
            onPressed: () => Navigator.of(ctx).pop(_CloseConfirmAction.close),
          ),
        ],
      );
      switch (choice) {
        case _CloseConfirmAction.hide:
          if (rememberChoice) {
            await WindowLogic.saveCloseBehavior(DesktopCloseBehavior.hide);
          }
          await _hideWindow();
        case _CloseConfirmAction.close:
          if (rememberChoice) {
            await WindowLogic.saveCloseBehavior(DesktopCloseBehavior.close);
          }
          await _forceExit();
        case null:
          break;
      }
    } finally {
      _handlingCloseRequest = false;
    }
  }

  /// 隐藏窗口到任务栏托盘，不退出程序
  Future<void> _hideWindow() async {
    await WindowLogic.saveWindowStateImmediately(context);
    mainWindow?.hide();
  }

  Future<void> _performGracefulExit() async {
    await _forceExit();
  }

  @override
  Widget build(BuildContext context) {
    return TranslationProvider(
      child: AnimatedBuilder(
        animation: FontProfileController.instance,
        builder: (context, _) {
          final globalSettingState = context.watch<GlobalSettingCubit>().state;

          return _buildDynamicColor(
            builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
              // 动态取色可用时直接用系统主色，否则回退到用户自定义主题色。
              final lightSeed =
                  (globalSettingState.dynamicColor &&
                      !isOhos &&
                      lightDynamic != null)
                  ? lightDynamic.primary
                  : globalSettingState.seedColor;
              final darkSeed =
                  (globalSettingState.dynamicColor &&
                      !isOhos &&
                      darkDynamic != null)
                  ? darkDynamic.primary
                  : globalSettingState.seedColor;

              // CalmTheme 自己按平台注入中文字体（含 Linux Noto Sans CJK SC），
              // 这里只负责挂载用户在 FontProfileController 选的自定义字体。
              TextTheme withConfiguredFonts(TextTheme base) =>
                  FontProfileController.instance.applyToTextTheme(base);

              return MaterialApp.router(
                routerConfig: appRouter.config(
                  navigatorObservers: () => [AutoRouteObserver()],
                ),
                scrollBehavior: AppScrollBehavior(
                  showScrollbar: globalSettingState.effectiveShowScrollbar,
                  alwaysVisible: globalSettingState.alwaysShowScrollbar,
                ),
                builder: (context, child) {
                  Widget content = Actions(
                    actions: <Type, Action<Intent>>{
                      EscapeIntent: CallbackAction<EscapeIntent>(
                        onInvoke: (intent) {
                          // 先让当前焦点失焦，避免 pop 时 InputDecorator 才第一次变 dirty；
                          // 再把 pop 推迟到下一帧，让失焦引发的重建在当前帧完成。
                          FocusManager.instance.primaryFocus?.unfocus();
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            appRouter.maybePop();
                          });
                          return null;
                        },
                      ),
                    },
                    child: Shortcuts(
                      shortcuts: <ShortcutActivator, Intent>{
                        const SingleActivator(LogicalKeyboardKey.escape):
                            const EscapeIntent(),
                      },
                      child: Focus(autofocus: true, child: child!),
                    ),
                  );

                  content = Listener(
                    onPointerDown: (PointerDownEvent event) {
                      if (event.buttons & kBackMouseButton != 0) {
                        appRouter.maybePop();
                      }
                    },
                    child: content,
                  );

                  if (Platform.isWindows ||
                      Platform.isLinux ||
                      Platform.isMacOS) {
                    final desktopContent = content;
                    content = ValueListenableBuilder<bool>(
                      valueListenable: ReaderDesktopFullscreenService
                          .instance
                          .fullscreenNotifier,
                      builder: (context, isReaderFullscreen, _) {
                        return Column(
                          children: [
                            if (!isReaderFullscreen) const CustomTitleBar(),
                            Expanded(child: desktopContent),
                          ],
                        );
                      },
                    );
                  }
                  // 第三方依赖仍有 legacy Material widget，需要这个桥接层提供旧主题
                  // 与本地化上下文；待依赖迁移后可移除。
                  // ignore: deprecated_member_use
                  return MaterialUiCompatibilityBridge(child: content);
                },
                locale: TranslationProvider.of(context).flutterLocale,
                title: appName,
                themeMode: globalSettingState.themeMode,
                supportedLocales: AppLocaleUtils.supportedLocales,
                localizationsDelegates: GlobalMaterialLocalizations.delegates,
                theme: CalmTheme.build(
                  brightness: Brightness.light,
                  seedColor: lightSeed,
                  textThemeTransform: withConfiguredFonts,
                ),
                // 墨水屏：CalmTheme 默认已是 NoSplash，不会在 EPD 上留残影。
                darkTheme: CalmTheme.build(
                  brightness: Brightness.dark,
                  seedColor: darkSeed,
                  isAmoled: globalSettingState.isAMOLED,
                  textThemeTransform: withConfiguredFonts,
                ),
              );
            },
          );
        },
      ),
    );
  }
}
