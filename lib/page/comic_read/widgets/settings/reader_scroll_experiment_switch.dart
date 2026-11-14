import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 设备本地实验项，不加入正式阅读偏好和同步数据；首次安装默认关闭。
const _zoomedScrollPreferenceKey = 'reader.zoomedContinuousScrollEnabled';
final zoomedContinuousScrollEnabled = ValueNotifier<bool>(false);

Future<void> loadZoomedContinuousScrollEnabled() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    zoomedContinuousScrollEnabled.value =
        prefs.getBool(_zoomedScrollPreferenceKey) ?? false;
  } catch (error) {
    debugPrint('Unable to load zoomed scrolling preference: $error');
  }
}

Future<void> setZoomedContinuousScrollEnabled(bool enabled) async {
  final prefs = await SharedPreferences.getInstance();
  if (await prefs.setBool(_zoomedScrollPreferenceKey, enabled)) {
    zoomedContinuousScrollEnabled.value = enabled;
  }
}
