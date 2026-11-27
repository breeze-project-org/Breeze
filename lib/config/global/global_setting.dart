// 全局设置

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/config/global/color_theme_types.dart';
import 'package:zephyr/config/global/setting_updated_at.dart';
import 'package:zephyr/i18n/i18n_helper.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/util/json/converter.dart';

part 'global_setting.freezed.dart';
part 'global_setting.g.dart';

enum ReaderInfoVerticalPosition { top, bottom }

enum ReaderInfoHorizontalPosition { left, center, right }

enum ReaderBackgroundMode { auto, black, white, grey }

enum ReaderTapPageTurnMode { fullScreen, leftHand, rightHand }

enum SyncServiceType { none, webdav, s3 }

/// 自动同步间隔单位。
enum SyncIntervalUnit { second, minute, hour }

/// 代理协议类型。
enum ProxyType { http, socks5 }

/// DoH 默认端点，与 Rust 侧 `DEFAULT_DOH_PROVIDERS` 保持一致。
///
/// 腾讯 `doh.pub` 只有 JSON 路径干净且墙内最快；两家瑞士解析器走 RFC 8484。
const List<String> defaultDohProviders = [
  'https://doh.pub/dns-query',
  'https://dns.digitale-gesellschaft.ch/dns-query',
  'https://doh.applied-privacy.net/query',
];

extension SyncServiceTypeExtension on SyncServiceType {
  String get label {
    switch (this) {
      case SyncServiceType.none:
        return t.common.disabled;
      case SyncServiceType.webdav:
        return 'WebDAV';
      case SyncServiceType.s3:
        return 'S3';
    }
  }
}

extension SyncIntervalUnitExtension on SyncIntervalUnit {
  String get label {
    switch (this) {
      case SyncIntervalUnit.second:
        return t.settings.syncIntervalUnitSecond;
      case SyncIntervalUnit.minute:
        return t.settings.syncIntervalUnitMinute;
      case SyncIntervalUnit.hour:
        return t.settings.syncIntervalUnitHour;
    }
  }

  /// 把设置值换算成定时器间隔；0/负数按 1 处理，避免忙循环。
  Duration durationFor(int value) {
    final safeValue = value < 1 ? 1 : value;
    switch (this) {
      case SyncIntervalUnit.second:
        return Duration(seconds: safeValue);
      case SyncIntervalUnit.minute:
        return Duration(minutes: safeValue);
      case SyncIntervalUnit.hour:
        return Duration(hours: safeValue);
    }
  }
}

// 简繁转换模式:off 不转换;simplified 转简体;traditional 转繁体
enum ChineseConvertMode { off, simplified, traditional }

extension ChineseConvertModeExtension on ChineseConvertMode {
  String get label {
    switch (this) {
      case ChineseConvertMode.off:
        return t.settings.chineseConvertOff;
      case ChineseConvertMode.simplified:
        return t.settings.chineseConvertSimplified;
      case ChineseConvertMode.traditional:
        return t.settings.chineseConvertTraditional;
    }
  }

  // 对应的 OpenCC 配置文件名;off 时返回空字符串(不转换)
  String get openccConfig {
    switch (this) {
      case ChineseConvertMode.off:
        return '';
      case ChineseConvertMode.simplified:
        return 'tw2sp.json';
      case ChineseConvertMode.traditional:
        return 's2twp.json';
    }
  }
}

/// 墨水屏整屏刷新方式。
///
/// 应用拿不到厂商的 EPD 局部刷新接口，只能靠整屏色块切换迫使驱动走一次全刷。
enum EinkRefreshMode { none, whiteFlash, fullFlash }

extension EinkRefreshModeExtension on EinkRefreshMode {
  String get label {
    switch (this) {
      case EinkRefreshMode.none:
        return t.settings.einkRefreshNone;
      case EinkRefreshMode.whiteFlash:
        return t.settings.einkRefreshWhite;
      case EinkRefreshMode.fullFlash:
        return t.settings.einkRefreshFull;
    }
  }
}

/// 路由构建器拿不到 BuildContext，瞬时切页开关在这里留一份同步好的镜像。
bool eInkInstantRoutes = false;

const Color readerBackgroundBlack = Colors.black;
const Color readerBackgroundWhite = Colors.white;
const Color readerBackgroundGrey = Color(0xFF2D2D2D);

extension ReadSettingStateBackgroundColor on ReadSettingState {
  Color resolveReaderBackgroundColor(Brightness brightness) {
    switch (readerBackgroundMode) {
      case ReaderBackgroundMode.auto:
        return brightness == Brightness.dark
            ? readerBackgroundBlack
            : readerBackgroundWhite;
      case ReaderBackgroundMode.black:
        return readerBackgroundBlack;
      case ReaderBackgroundMode.white:
        return readerBackgroundWhite;
      case ReaderBackgroundMode.grey:
        return readerBackgroundGrey;
    }
  }

  Color resolveReaderForegroundColor(Brightness brightness) {
    final backgroundColor = resolveReaderBackgroundColor(brightness);
    return backgroundColor.computeLuminance() < 0.5
        ? Colors.white
        : Colors.black;
  }
}

GlobalSettingState _globalSettingState = const GlobalSettingState();

GlobalSettingState get globalSetting => _globalSettingState;

/// 桌面平台（含 Web）：滚动条可以靠鼠标悬停重新唤出并拖动。
bool get isDesktopScrollbarPlatform {
  if (kIsWeb) return true;
  return defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.macOS;
}

/// 触摸平台（Android / iOS / OHOS）：没有悬停唤出，且 Android 默认
/// `interactive: false`，滚动停止后 thumb 既不可见也无法命中。
bool get isTouchScrollbarPlatform => !isDesktopScrollbarPlatform;

/// 滚动条显示开关的平台默认值：桌面端显示，移动端隐藏。
bool get defaultShowScrollbar => isDesktopScrollbarPlatform;

@freezed
abstract class GlobalSettingState with _$GlobalSettingState {
  const factory GlobalSettingState({
    @Default(true) bool dynamicColor,
    @Default(ThemeMode.system) ThemeMode themeMode,
    @Default(true) bool isAMOLED,
    @ColorConverter() @Default(Color(0xFFEF5350)) Color seedColor,
    @Default(0) int themeInitState,
    @LocaleConverter() @Default(Locale('zh', 'CN')) Locale locale,
    @Default(true) bool localeFollowsSystem,
    @Default(0) int welcomePageNum,
    @Default(true) bool showPluginHome,
    @Default(true) bool showPluginCloudFavorite,
    @Default(true) bool showSearchBookmark,
    // null = 跟随平台默认值（桌面端显示、移动端隐藏），用户切换后写入显式值。
    bool? showScrollbar,
    @Default(false) bool alwaysShowScrollbar,

    /// 每个设置项的最近修改时间（UTC 毫秒时间戳），键为设置 JSON 路径，
    /// 例如 `themeMode`、`readSetting.readMode`。只记录改动过的项，未记录
    /// 的项在同步时回退到旧版块级时间。
    @Default(<String, int>{}) Map<String, int> settingUpdatedAt,
    @Default(SyncSettingState()) SyncSettingState syncSetting,
    @Default([]) List<String> maskedKeywords,
    @Default([]) List<String> maskedCommentKeywords,
    @Default(true) bool socks5ProxyEnabled,
    @Default('') String socks5Proxy,
    @Default(false) bool needCleanCache,
    @Default(1) int comicChoice,
    @Default(false) bool disableBika,
    @Default(false) bool enableMemoryDebug,
    @Default(false) bool blockRustHttpRequests,
    @Default('') String logAddress,
    @Default(false) bool forceEnableImpeller,
    @Default(false) bool androidKeepAliveEnabled,
    @Default(false) bool backPressExitEnabled,
    @Default(true) bool updateAccelerate,
    @Default(true) bool retryDownloadUntilSuccess,
    @Default(false) bool autoFollowOnCollect,
    @Default(false) bool autoCloudCollectOnLocalFavorite,
    @Default(false) bool leftHandModeEnabled,
    @Default(false) bool clickCoverToStartReading,
    @Default([]) List<String> searchHistory,
    @Default(ProxySettingState()) ProxySettingState proxySetting,
    // DoH：默认开启并使用内置推荐端点；用户可关闭或增删端点。
    @Default(DohSettingState()) DohSettingState dohSetting,
    // 内网拦截：默认关闭（放行内网 / 保留地址段），与 Rust 侧初始值一致。
    @Default(false) bool blockPrivateNetwork,
    // 搜索书签邻页找回：向后最多探测页数（0=只找本页）；向前固定 1 页。
    @Default(3) int searchBookmarkProbePages,
    @Default(1280.0) double windowWidth,
    @Default(720.0) double windowHeight,
    @Default(0) double windowX,
    @Default(0) double windowY,
    @Default(ReadSettingState()) ReadSettingState readSetting,
    @Default('') String customExportPath,
    @Default(AppLockSettingState()) AppLockSettingState appLockSetting,
    @Default("") String compatibleVersion,
    @Default(CacheSettingState()) CacheSettingState cacheSetting,
    @Default(ChineseConvertMode.off) ChineseConvertMode chineseConvertMode,
    @Default(BookshelfSettingState()) BookshelfSettingState bookshelfSetting,
    @Default(EInkSettingState()) EInkSettingState eInkSetting,
    @Default(ComicDetailSettingState())
    ComicDetailSettingState comicDetailSetting,
  }) = _GlobalSettingState;

  factory GlobalSettingState.fromJson(Map<String, dynamic> json) =>
      _$GlobalSettingStateFromJson(json);
}

extension GlobalSettingStateScrollbarX on GlobalSettingState {
  /// 实际是否显示滚动条；用户未切换过时按平台默认值。
  bool get effectiveShowScrollbar => showScrollbar ?? defaultShowScrollbar;
}

@freezed
abstract class CacheSettingState with _$CacheSettingState {
  const factory CacheSettingState({
    @Default(true) bool autoCleanCache,
    @Default(1073741824) int cacheSizeLimit,
  }) = _CacheSettingState;

  factory CacheSettingState.fromJson(Map<String, dynamic> json) =>
      _$CacheSettingStateFromJson(json);
}

@freezed
abstract class AppLockSettingState with _$AppLockSettingState {
  const AppLockSettingState._();

  const factory AppLockSettingState({
    @Default(false) bool enabled,
    @Default('') String gesturePasswordHash,
    @Default('') String resetPinHash,
  }) = _AppLockSettingState;

  factory AppLockSettingState.fromJson(Map<String, dynamic> json) =>
      _$AppLockSettingStateFromJson(json);

  bool get hasGesturePassword => gesturePasswordHash.trim().isNotEmpty;

  bool get hasResetPin => resetPinHash.trim().isNotEmpty;

  bool get isReady => hasGesturePassword && hasResetPin;
}

@freezed
abstract class ProxySettingState with _$ProxySettingState {
  const factory ProxySettingState({
    @Default(false) bool enabled,
    @Default(ProxyType.http) ProxyType type,
    @Default('') String address,
  }) = _ProxySettingState;

  factory ProxySettingState.fromJson(Map<String, dynamic> json) =>
      _$ProxySettingStateFromJson(json);
}

@freezed
abstract class DohSettingState with _$DohSettingState {
  const factory DohSettingState({
    @Default(false) bool enabled,
    @Default(defaultDohProviders) List<String> providers,
  }) = _DohSettingState;

  factory DohSettingState.fromJson(Map<String, dynamic> json) =>
      _$DohSettingStateFromJson(json);
}

@freezed
abstract class WebDavSettingState with _$WebDavSettingState {
  const factory WebDavSettingState({
    @Default('') String host,
    @Default('') String username,
    @Default('') String password,
  }) = _WebDavSettingState;

  factory WebDavSettingState.fromJson(Map<String, dynamic> json) =>
      _$WebDavSettingStateFromJson(json);
}

@freezed
abstract class S3SettingState with _$S3SettingState {
  const factory S3SettingState({
    @Default('') String endpoint,
    @Default('') String accessKey,
    @Default('') String secretKey,
    @Default('') String bucket,
    @Default('') String region,
    @Default(true) bool useSSL,
    @Default(0) int port,
    @Default(false) bool pathStyle,
  }) = _S3SettingState;

  factory S3SettingState.fromJson(Map<String, dynamic> json) =>
      _$S3SettingStateFromJson(json);
}

@freezed
abstract class SyncSettingState with _$SyncSettingState {
  const factory SyncSettingState({
    @Default(SyncServiceType.none) SyncServiceType syncServiceType,

    /// 自定义同步加密密钥；空串使用内置默认密钥，兼容旧同步数据。
    @Default('') String encryptionKey,
    @Default(WebDavSettingState()) WebDavSettingState webdavSetting,
    @Default(S3SettingState()) S3SettingState s3Setting,
    @Default(false) bool syncSettings,
    @Default(false) bool syncPlugins,
    @Default(true) bool autoSync,

    /// 自动同步间隔数值 + 单位，默认 5 分钟。
    @Default(5) int syncInterval,
    @Default(SyncIntervalUnit.minute) SyncIntervalUnit syncIntervalUnit,
    @Default(true) bool syncNotify,
    @Default(0) int settingsSyncTime,
  }) = _SyncSettingState;

  factory SyncSettingState.fromJson(Map<String, dynamic> json) =>
      _$SyncSettingStateFromJson(json);
}

@freezed
abstract class ReadSettingState with _$ReadSettingState {
  const factory ReadSettingState({
    @Default(false) bool noAnimation,
    @Default(true) bool comicReadTopContainer,
    @Default(0) int readMode,
    @Default(ReaderTapPageTurnMode.rightHand)
    ReaderTapPageTurnMode tapPageTurnMode,
    @Default(false) bool tapPageTurnInWebtoon,
    @Default(false) bool reverseHorizontalPageTurn,
    @Default(ReaderBackgroundMode.auto)
    ReaderBackgroundMode readerBackgroundMode,
    @Default(true) bool readFilterEnabled,
    @Default(50) int readFilterOpacityPercent,
    @Default(false) bool einkOptimization,
    @Default(120) int einkDelayMs,
    @Default(false) bool autoScroll,
    @Default(false) bool autoScrollHidePauseButton,
    @Default(false) bool autoScrollSmooth,
    @Default(1600) int autoScrollColumnIntervalMs,
    @Default(3000) int autoScrollPageIntervalMs,
    @Default(72) int autoScrollColumnDistancePercent,
    @Default(3) int preloadImageCount,
    @Default(1) int preloadChapterCount,
    @Default(false) bool landscapeReader,
    @Default(false) bool showStatusBar,
    @Default(false) bool autoDoublePageInLandscape,
    @Default(false) bool doublePageMode,
    @Default(false) bool doublePageSeamless,
    @Default(false) bool doublePageLeadingBlank,
    @Default(false) bool sidePaddingEnabled,
    @Default(10) int sidePaddingPercent,
    @Default(true) bool volumeKeyPageTurn,
    @Default(72) int volumeKeyPageTurnDistancePercent,
    @Default(false) bool doubleTapZoom,
    @Default(false) bool doubleTapOpenMenu,
    @Default(false) bool zoomedContinuousScroll,
    @Default(true) bool pageInfoShowPage,
    @Default(true) bool pageInfoShowNetwork,
    @Default(false) bool pageInfoShowBattery,
    @Default(true) bool pageInfoShowTime,
    @Default(ReaderInfoVerticalPosition.bottom)
    ReaderInfoVerticalPosition pageInfoVerticalPosition,
    @Default(false) bool pageInfoTopInStatusBar,
    @Default(ReaderInfoHorizontalPosition.left)
    ReaderInfoHorizontalPosition pageInfoHorizontalPosition,
    @Default(12) int pageInfoEdgePadding,
    @Default(82) int pageInfoOpacityPercent,
    @Default(12) int pageInfoFontSize,
  }) = _ReadSettingState;

  factory ReadSettingState.fromJson(Map<String, dynamic> json) =>
      _$ReadSettingStateFromJson(json);
}

@freezed
abstract class EInkSettingState with _$EInkSettingState {
  const EInkSettingState._();

  const factory EInkSettingState({
    /// 墨水屏模式总开关。命中 e-ink 设备时首启自动打开，用户手动关掉后不再自动开启。
    @Default(false) bool enabled,

    /// 设备检测是否已经处理过一次，避免每次启动都覆盖用户的选择。
    @Default(false) bool detectionHandled,

    /// 页面跳转不做滑动/淡入动画，直接出图。
    @Default(true) bool noRouteTransition,

    /// 滚动到边界不回弹。
    @Default(true) bool noScrollBounce,

    /// 图片加载占位不转圈（转圈会驱动墨水屏持续局刷，残影很重）。
    @Default(true) bool noLoadingSpinner,

    @Default(EinkRefreshMode.fullFlash) EinkRefreshMode refreshMode,

    /// 每翻多少页自动整屏刷新一次；0 表示不自动刷新。
    @Default(5) int autoRefreshEveryNTurns,

    @Default(true) bool showRefreshButton,
  }) = _EInkSettingState;

  factory EInkSettingState.fromJson(Map<String, dynamic> json) =>
      _$EInkSettingStateFromJson(json);

  bool get shouldRemoveRouteTransition => enabled && noRouteTransition;

  bool get shouldRemoveScrollBounce => enabled && noScrollBounce;

  bool get shouldRemoveLoadingSpinner => enabled && noLoadingSpinner;

  bool get canFullRefresh => enabled && refreshMode != EinkRefreshMode.none;

  int get autoRefreshTurns => autoRefreshEveryNTurns.clamp(0, 50);
}

@freezed
abstract class BookshelfSettingState with _$BookshelfSettingState {
  const factory BookshelfSettingState({
    @Default(0) int homePageIndex,
    @Default(false) bool rememberFavoriteSort,
    @Default('dd') String favoriteSort,
    @Default(false) bool rememberHistorySort,
    @Default('dd') String historySort,
    @Default(false) bool rememberDownloadSort,
    @Default('dd') String downloadSort,
    @Default(false) bool hideFavoriteFolders,
    @Default(false) bool hideDownloadFolders,
    @Default(false) bool detailLayout,
    @Default(false) bool reverseChapters,
  }) = _BookshelfSettingState;

  factory BookshelfSettingState.fromJson(Map<String, dynamic> json) =>
      _$BookshelfSettingStateFromJson(json);
}

/// 漫画详情页显示样式。
///
/// 功能按钮区固定有四个按钮，各自独立控制显隐；隐藏只影响展示，
/// 不影响收藏、点赞等实际状态与自动逻辑。
@freezed
abstract class ComicDetailSettingState with _$ComicDetailSettingState {
  const factory ComicDetailSettingState({
    @Default(true) bool showLikeAction,
    @Default(true) bool showCommentAction,
    @Default(true) bool showLocalCollectAction,
    @Default(true) bool showCloudCollectAction,
  }) = _ComicDetailSettingState;

  factory ComicDetailSettingState.fromJson(Map<String, dynamic> json) =>
      _$ComicDetailSettingStateFromJson(json);
}

extension ComicDetailSettingStateX on ComicDetailSettingState {
  /// 四个功能按钮是否至少显示一个；全关时详情页整块操作区（含分隔线）不占位。
  bool get hasVisibleActions =>
      showLikeAction ||
      showCommentAction ||
      showLocalCollectAction ||
      showCloudCollectAction;
}

class GlobalSettingCubit extends Cubit<GlobalSettingState> {
  // 构造函数，传入由 freezed 生成的默认 state
  GlobalSettingCubit() : super(const GlobalSettingState());

  // 用于获取 freezed 中定义的默认值的便捷实例
  static const _defaults = GlobalSettingState();
  // colorThemeList[6].color 是动态的，不能在 const 中，单独处理
  late final Color _defaultSeedColor = colorThemeList[6].color;

  Future<void> initBox() async {
    final userSetting = await database.userSettings.getOrCreate();
    final persisted = _hydrateUpdatedAt(userSetting.globalSetting);
    _globalSettingState = persisted;
    _syncRuntimeFlags(persisted);
    emit(persisted);
    if (!mapEquals(
      persisted.settingUpdatedAt,
      userSetting.globalSetting.settingUpdatedAt,
    )) {
      unawaited(_persistGlobalSetting(persisted));
    }
  }

  GlobalSettingState get defaults =>
      _defaults.copyWith(seedColor: _defaultSeedColor);

  void updateALl(GlobalSettingState state) {
    _persistAndEmit(state);
  }

  void updateState(
    GlobalSettingState Function(GlobalSettingState current) updates,
  ) {
    final newState = updates(state);
    _persistAndEmit(newState);
  }

  void updateReadSetting(
    ReadSettingState Function(ReadSettingState current) updates,
  ) {
    updateState(
      (current) => current.copyWith(readSetting: updates(current.readSetting)),
    );
  }

  void updateSyncSetting(
    SyncSettingState Function(SyncSettingState current) updates,
  ) {
    updateState(
      (current) => current.copyWith(syncSetting: updates(current.syncSetting)),
    );
  }

  void updateCacheSetting(
    CacheSettingState Function(CacheSettingState current) updates,
  ) {
    updateState(
      (current) =>
          current.copyWith(cacheSetting: updates(current.cacheSetting)),
    );
  }

  void updateBookshelfSetting(
    BookshelfSettingState Function(BookshelfSettingState current) updates,
  ) {
    updateState(
      (current) =>
          current.copyWith(bookshelfSetting: updates(current.bookshelfSetting)),
    );
  }

  void updateEInkSetting(
    EInkSettingState Function(EInkSettingState current) updates,
  ) {
    updateState(
      (current) => current.copyWith(eInkSetting: updates(current.eInkSetting)),
    );
  }

  void updateComicDetailSetting(
    ComicDetailSettingState Function(ComicDetailSettingState current) updates,
  ) {
    updateState(
      (current) => current.copyWith(
        comicDetailSetting: updates(current.comicDetailSetting),
      ),
    );
  }

  /// 设置应用显示语言。
  ///
  /// [locale] 为目标 Flutter Locale；[followsSystem] 为 true 时表示跟随系统。
  /// 该方法会自动持久化、切换 slang 当前 locale，并同步 Rust 侧错误消息语言。
  /// 如果 [locale] 无法匹配到已支持的语言，则回退到英文。
  Future<void> setLocale(Locale locale, {bool followsSystem = false}) async {
    final appLocale = I18nHelper.toAppLocale(locale) ?? AppLocale.enUs;

    await LocaleSettings.setLocale(appLocale);
    I18nHelper.setRustErrorLanguage(appLocale);

    updateState(
      (current) => current.copyWith(
        locale: I18nHelper.toFlutterLocale(appLocale),
        localeFollowsSystem: followsSystem,
      ),
    );
  }

  /// 根据系统 locale 设置应用语言。
  /// 无法匹配时由 [setLocale] 自动回退到英文。
  Future<void> setSystemLocale(Locale systemLocale) async {
    await setLocale(systemLocale, followsSystem: true);
  }

  void updateWebDavSetting(
    WebDavSettingState Function(WebDavSettingState current) updates,
  ) {
    updateSyncSetting(
      (current) =>
          current.copyWith(webdavSetting: updates(current.webdavSetting)),
    );
  }

  void resetState(
    GlobalSettingState Function(
      GlobalSettingState current,
      GlobalSettingState defaults,
    )
    updates,
  ) {
    final newState = updates(state, defaults);
    _persistAndEmit(newState);
  }

  void _persistAndEmit(GlobalSettingState newState) {
    final normalizedState = _preserveCompatibleVersion(newState, state);
    _syncRuntimeFlags(normalizedState);
    if (_withoutSyncMetadata(normalizedState) == _withoutSyncMetadata(state)) {
      return;
    }

    final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;
    final updatedTimestamps = updateSettingUpdatedAt(
      previous: state.toJson(),
      next: normalizedState.toJson(),
      current: state.settingUpdatedAt,
      now: nowMs,
    );
    final persistedState = normalizedState.copyWith(
      settingUpdatedAt: hydrateSettingUpdatedAt(
        stateJson: normalizedState.toJson(),
        current: updatedTimestamps,
        baseline: normalizedState.syncSetting.settingsSyncTime,
      ),
      syncSetting: normalizedState.syncSetting.copyWith(
        settingsSyncTime: nowMs,
      ),
    );
    _updateDataBase(persistedState);
    emit(persistedState);
  }

  void applySyncedState(GlobalSettingState value) {
    final normalized = _hydrateUpdatedAt(
      _preserveCompatibleVersion(value, state),
    );
    _syncRuntimeFlags(normalized);
    _updateDataBase(normalized);
    emit(normalized);
  }

  /// 备份导入：数据库已由导入 worker 按原始 JSON 写好，这里只替换内存状态。
  void adoptRestoredState(GlobalSettingState value) {
    _syncRuntimeFlags(value);
    _globalSettingState = value;
    emit(value);
  }

  GlobalSettingState _hydrateUpdatedAt(GlobalSettingState value) {
    final hydrated = hydrateSettingUpdatedAt(
      stateJson: value.toJson(),
      current: value.settingUpdatedAt,
      baseline: value.syncSetting.settingsSyncTime,
    );
    if (mapEquals(hydrated, value.settingUpdatedAt)) {
      return value;
    }
    return value.copyWith(settingUpdatedAt: hydrated);
  }

  void _syncRuntimeFlags(GlobalSettingState value) {
    eInkInstantRoutes = value.eInkSetting.shouldRemoveRouteTransition;
  }

  GlobalSettingState _preserveCompatibleVersion(
    GlobalSettingState incoming,
    GlobalSettingState fallback,
  ) {
    if (incoming.compatibleVersion.trim().isNotEmpty) {
      return incoming;
    }
    final preserved = fallback.compatibleVersion.trim();
    if (preserved.isEmpty) {
      return incoming;
    }
    return incoming.copyWith(compatibleVersion: preserved);
  }

  GlobalSettingState _withoutSyncMetadata(GlobalSettingState value) {
    return value.copyWith(
      settingUpdatedAt: const <String, int>{},
      syncSetting: value.syncSetting.copyWith(settingsSyncTime: 0),
    );
  }

  void _updateDataBase(GlobalSettingState state) {
    _globalSettingState = state;
    unawaited(_persistGlobalSetting(state));
  }

  Future<void> _persistGlobalSetting(GlobalSettingState state) async {
    final userSetting = await database.userSettings.get();
    if (userSetting == null) return;
    var toSave = state;
    final existingVersion = userSetting.globalSetting.compatibleVersion.trim();
    if (toSave.compatibleVersion.trim().isEmpty && existingVersion.isNotEmpty) {
      toSave = toSave.copyWith(compatibleVersion: existingVersion);
    }
    userSetting.globalSetting = toSave;
    await database.userSettings.put(userSetting);
  }
}
