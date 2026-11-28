import 'dart:async';
import 'dart:io';

import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/comic_read/cubit/reader_cubit.dart';
import 'package:zephyr/page/comic_read/widgets/layout/read_layout.dart';
import 'package:zephyr/ui/ui.dart';
import 'package:zephyr/util/ohos/platform.dart';
import 'package:zephyr/util/ohos/file_bridge.dart';

class PageCountWidget extends StatefulWidget {
  final String epPages;
  final int Function()? getCurrentChapterStartSlot;
  final int Function()? getCurrentChapterSlotCount;
  final bool Function(int globalSlot)? isTransitionSlot;
  final String transitionText;

  const PageCountWidget({
    super.key,
    required this.epPages,
    this.getCurrentChapterStartSlot,
    this.getCurrentChapterSlotCount,
    this.isTransitionSlot,
    this.transitionText = '',
  });

  @override
  State<PageCountWidget> createState() => _PageCountWidgetState();
}

class _PageCountWidgetState extends State<PageCountWidget> {
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  ConnectivityResult _connectivityResult = ConnectivityResult.none;
  String _currentTime = '';
  Timer? _timer;
  final Battery _battery = Battery();
  int _batteryLevel = 100;
  BatteryState _batteryState = BatteryState.full;
  StreamSubscription<BatteryState>? _batteryStateSubscription;
  Timer? _ohosStatusTimer;

  @override
  void initState() {
    super.initState();
    if (isOhos) {
      _initOhosStatus();
    } else {
      _initConnectivity();
      _initBattery();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateTime();
      _startTimer();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ohosStatusTimer?.cancel();
    _connectivitySubscription?.cancel();
    _batteryStateSubscription?.cancel();
    super.dispose();
  }

  void _initOhosStatus() {
    _refreshOhosStatus();
    _ohosStatusTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _refreshOhosStatus();
    });
  }

  Future<void> _refreshOhosStatus() async {
    try {
      final types = await getOhosConnectivity();
      _updateConnectivityResult(
        types.map(_mapOhosConnectivity).toList(growable: false),
      );
    } catch (_) {}

    try {
      final info = await getOhosBatteryInfo();
      if (info != null && mounted) {
        setState(() {
          _batteryLevel = info.level;
          _batteryState = _mapOhosBatteryState(info.state);
        });
      }
    } catch (_) {}
  }

  ConnectivityResult _mapOhosConnectivity(String type) {
    switch (type) {
      case 'wifi':
        return ConnectivityResult.wifi;
      case 'mobile':
        return ConnectivityResult.mobile;
      case 'ethernet':
        return ConnectivityResult.ethernet;
      case 'bluetooth':
        return ConnectivityResult.bluetooth;
      case 'vpn':
        return ConnectivityResult.vpn;
      case 'none':
        return ConnectivityResult.none;
      default:
        return ConnectivityResult.other;
    }
  }

  BatteryState _mapOhosBatteryState(String state) {
    switch (state) {
      case 'charging':
        return BatteryState.charging;
      case 'full':
        return BatteryState.full;
      case 'discharging':
        return BatteryState.discharging;
      default:
        return BatteryState.unknown;
    }
  }

  void _initBattery() async {
    try {
      final level = await _battery.batteryLevel;
      if (mounted) {
        setState(() => _batteryLevel = level);
      }

      final state = await _battery.batteryState;
      if (mounted) {
        setState(() => _batteryState = state);
      }

      _batteryStateSubscription = _battery.onBatteryStateChanged.listen((
        state,
      ) {
        if (mounted) {
          setState(() => _batteryState = state);
        }
      });
    } catch (_) {}
  }

  IconData getBatteryIcon() {
    if (_batteryState == BatteryState.charging) {
      return Icons.battery_charging_full;
    }
    if (_batteryLevel >= 95) return Icons.battery_full;
    if (_batteryLevel >= 80) return Icons.battery_6_bar;
    if (_batteryLevel >= 60) return Icons.battery_5_bar;
    if (_batteryLevel >= 50) return Icons.battery_4_bar;
    if (_batteryLevel >= 30) return Icons.battery_3_bar;
    if (_batteryLevel >= 20) return Icons.battery_2_bar;
    if (_batteryLevel >= 10) return Icons.battery_1_bar;
    return Icons.battery_alert;
  }

  void _initConnectivity() async {
    try {
      final connectivity = Connectivity();
      final results = await connectivity.checkConnectivity();
      if (results.isNotEmpty) {
        _updateConnectivityResult(results);
      }
      _connectivitySubscription = connectivity.onConnectivityChanged.listen((
        results,
      ) {
        if (mounted && results.isNotEmpty) {
          _updateConnectivityResult(results);
        }
      });
    } catch (_) {}
  }

  void _updateConnectivityResult(List<ConnectivityResult> results) {
    final highestPriority = _getHighestPriorityResult(results);
    if (mounted && highestPriority != _connectivityResult) {
      setState(() {
        _connectivityResult = highestPriority;
      });
    }
  }

  ConnectivityResult _getHighestPriorityResult(
    List<ConnectivityResult> results,
  ) {
    const priorityOrder = [
      ConnectivityResult.wifi,
      ConnectivityResult.mobile,
      ConnectivityResult.satellite,
      ConnectivityResult.none,
      ConnectivityResult.ethernet,
      ConnectivityResult.bluetooth,
      ConnectivityResult.vpn,
      ConnectivityResult.other,
    ];
    for (var type in priorityOrder) {
      if (results.contains(type)) return type;
    }
    return ConnectivityResult.none;
  }

  // 获取网络状态图标
  IconData _getNetworkStatusIcon(ConnectivityResult result) {
    switch (result) {
      case ConnectivityResult.bluetooth:
        return Icons.bluetooth;
      case ConnectivityResult.wifi:
        return Icons.wifi;
      case ConnectivityResult.ethernet:
        return Icons.router;
      case ConnectivityResult.mobile:
        return Icons.network_cell;
      case ConnectivityResult.satellite:
        return Icons.satellite_alt;
      case ConnectivityResult.none:
        return Icons.signal_wifi_off;
      case ConnectivityResult.vpn:
        return Icons.vpn_key;
      case ConnectivityResult.other:
        return Icons.signal_cellular_off;
    }
  }

  void _updateTime() {
    final now = DateTime.now();
    final formattedTime =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    if (formattedTime != _currentTime) {
      setState(() => _currentTime = formattedTime);

      if (!isOhos) {
        _battery.batteryLevel
            .then((level) {
              if (mounted && _batteryLevel != level) {
                setState(() => _batteryLevel = level);
              }
            })
            .catchError((_) {});
      }
    }
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        _updateTime();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final pageIndex = context.select<ReaderCubit, int>(
      (value) => value.state.currentSlot,
    );
    final readSetting = context.select<GlobalSettingCubit, ReadSettingState>(
      (cubit) => cubit.state.readSetting,
    );

    final showPage = readSetting.pageInfoShowPage;
    final showNetwork = readSetting.pageInfoShowNetwork;
    final showBattery = readSetting.pageInfoShowBattery;
    final showTime = readSetting.pageInfoShowTime;
    final opacityPercent = readSetting.pageInfoOpacityPercent.clamp(20, 100);
    final fontSize = readSetting.pageInfoFontSize.clamp(10, 20).toDouble();

    if (!showPage && !showNetwork && !showBattery && !showTime) {
      return const Positioned(top: 0, left: 0, child: SizedBox.shrink());
    }

    final mediaPadding = MediaQuery.paddingOf(context);
    final edge = readSetting.pageInfoEdgePadding.clamp(0, 48).toDouble();
    final sideExtra =
        readSetting.pageInfoHorizontalPosition ==
            ReaderInfoHorizontalPosition.center
        ? 0.0
        : (Platform.isIOS ? 22.0 : 12.0);
    final verticalExtra = Platform.isIOS ? 6.0 : 2.0;
    final showInStatusBar =
        readSetting.pageInfoVerticalPosition ==
            ReaderInfoVerticalPosition.top &&
        readSetting.pageInfoTopInStatusBar;

    final verticalOffset =
        readSetting.pageInfoVerticalPosition == ReaderInfoVerticalPosition.top
        ? (showInStatusBar ? edge : mediaPadding.top + edge + verticalExtra)
        : mediaPadding.bottom + edge + verticalExtra;

    final parsedEpPages = int.tryParse(widget.epPages);
    final totalPageCount = (parsedEpPages != null && parsedEpPages > 0)
        ? parsedEpPages
        : 1;
    final chapterStartSlot = widget.getCurrentChapterStartSlot?.call() ?? 0;
    final chapterSlotCount =
        widget.getCurrentChapterSlotCount?.call() ?? totalPageCount;
    final isTransitionSlot = widget.isTransitionSlot?.call(pageIndex) ?? false;
    final String transitionText = widget.transitionText.isEmpty
        ? t.reader.chapterTransition
        : widget.transitionText;
    final String pageText;
    if (isTransitionSlot) {
      pageText = transitionText;
    } else {
      final localSlotIndex = (pageIndex - chapterStartSlot).clamp(
        0,
        chapterSlotCount > 0 ? chapterSlotCount - 1 : 0,
      );
      final currentDisplayPage = getDisplayPageNumber(
        slotIndex: localSlotIndex,
        enableDoublePage: readSetting.doublePageMode,
        insertLeadingBlank:
            readSetting.doublePageMode && readSetting.doublePageLeadingBlank,
      ).clamp(1, totalPageCount);
      pageText = '$currentDisplayPage/$totalPageCount';
    }

    final panel = _PageInfoPanel(
      pageText: pageText,
      showPage: showPage,
      showNetwork: showNetwork,
      showBattery: showBattery,
      showTime: showTime,
      currentTime: _currentTime,
      batteryLevel: _batteryLevel,
      networkIcon: _getNetworkStatusIcon(_connectivityResult),
      batteryIcon: getBatteryIcon(),
      opacityPercent: opacityPercent,
      fontSize: fontSize,
      // 信息浮层直接压在漫画上：底色/字色都要尊重阅读器自己的前景与背景色，
      // 透明度按用户设置平滑地“漏”出底下的画面。
      readerBackgroundColor: readSetting.resolveReaderBackgroundColor(
        Theme.of(context).brightness,
      ),
      readerForegroundColor: readSetting.resolveReaderForegroundColor(
        Theme.of(context).brightness,
      ),
    );

    final isTop =
        readSetting.pageInfoVerticalPosition == ReaderInfoVerticalPosition.top;
    final horizontalPosition = readSetting.pageInfoHorizontalPosition;

    if (horizontalPosition == ReaderInfoHorizontalPosition.center) {
      return Positioned(
        top: isTop ? verticalOffset : null,
        bottom: isTop ? null : verticalOffset,
        left: 0,
        right: 0,
        child: Align(
          alignment: isTop ? Alignment.topCenter : Alignment.bottomCenter,
          child: panel,
        ),
      );
    }

    final left = horizontalPosition == ReaderInfoHorizontalPosition.left
        ? mediaPadding.left + edge + sideExtra
        : null;
    final right = horizontalPosition == ReaderInfoHorizontalPosition.right
        ? mediaPadding.right + edge + sideExtra
        : null;

    return Positioned(
      top: isTop ? verticalOffset : null,
      bottom: isTop ? null : verticalOffset,
      left: left,
      right: right,
      child: panel,
    );
  }
}

class _PageInfoPanel extends StatelessWidget {
  final String pageText;
  final bool showPage;
  final bool showNetwork;
  final bool showBattery;
  final bool showTime;
  final String currentTime;
  final int batteryLevel;
  final IconData networkIcon;
  final IconData batteryIcon;
  final int opacityPercent;
  final double fontSize;
  final Color readerBackgroundColor;
  final Color readerForegroundColor;

  const _PageInfoPanel({
    required this.pageText,
    required this.showPage,
    required this.showNetwork,
    required this.showBattery,
    required this.showTime,
    required this.currentTime,
    required this.batteryLevel,
    required this.networkIcon,
    required this.batteryIcon,
    required this.opacityPercent,
    required this.fontSize,
    required this.readerBackgroundColor,
    required this.readerForegroundColor,
  });

  /// 胶囊里的字色：在 CalmUI 正文色与阅读器前景色之间取对比更强的那个。
  ///
  /// 阅读器允许“浅色主题 + 纯黑底”这类反主题组合，单靠 [CalmColors.text]
  /// 在低不透明度时可能糊在底上；阅读器前景色是用户自己选定的对比色，
  /// 两个候选都来自配置，不会出现写死的黑白。
  Color _pickInk(CalmColors c, Color capsule) {
    final calmContrast = _contrastRatio(c.text, capsule);
    final readerContrast = _contrastRatio(readerForegroundColor, capsule);
    return readerContrast > calmContrast ? readerForegroundColor : c.text;
  }

  static double _contrastRatio(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final lighter = la > lb ? la : lb;
    final darker = la > lb ? lb : la;
    return (lighter + 0.05) / (darker + 0.05);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    final alpha = (opacityPercent / 100).clamp(0.2, 1.0);
    final capsuleColor = Color.alphaBlend(
      c.surface.withValues(alpha: alpha),
      readerBackgroundColor,
    );
    final ink = _pickInk(c, capsuleColor);
    final mutedInk = Color.alphaBlend(
      ink.withValues(alpha: 0.74),
      capsuleColor,
    );
    final borderColor = Color.alphaBlend(
      ink.withValues(alpha: 0.14),
      capsuleColor,
    );

    final textStyle = TextStyle(
      color: ink,
      fontSize: fontSize,
      fontWeight: FontWeight.w500,
      height: 1.2,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final iconSize = (fontSize + 1).clamp(10.0, 24.0);

    final items = <Widget>[];
    if (showPage) {
      items.add(Text(pageText, style: textStyle));
    }
    if (showNetwork) {
      items.add(Icon(networkIcon, color: mutedInk, size: iconSize));
    }
    if (showBattery) {
      items.add(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(batteryIcon, color: mutedInk, size: iconSize),
            const SizedBox(width: 3),
            Text('$batteryLevel%', style: textStyle),
          ],
        ),
      );
    }
    if (showTime) {
      items.add(Text(currentTime, style: textStyle));
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: capsuleColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
        boxShadow: c.shadowSm,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (int i = 0; i < items.length; i++) ...[
              items[i],
              if (i != items.length - 1) const SizedBox(width: 8),
            ],
          ],
        ),
      ),
    );
  }
}
