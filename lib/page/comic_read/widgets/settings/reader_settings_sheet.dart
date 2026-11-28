import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/ui/ui.dart';
import 'package:zephyr/util/ohos/platform.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/cubit/comic_read_preference_cubit.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/widgets/fluent_dropdown.dart';

part 'reader_settings_gesture_tab.dart';
part 'reader_settings_info_tab.dart';
part 'reader_settings_read_tab.dart';
part 'reader_settings_per_comic_tab.dart';

Future<void> showReaderSettingsSheet(
  BuildContext context, {
  ValueChanged<int>? changePageIndex,
  ValueChanged<bool>? onLandscapeChanged,
  ValueChanged<bool>? onDoublePageModeChanged,
  String source = '',
  String comicId = '',
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierLabel: t.common.close,
    isDismissible: true,
    enableDrag: true,
    builder: (context) {
      // 外层钉死全局：前三个 tab 与全局入口恒写全局，不回退读 cubit；
      // 第四个 tab 内层的 perComic:true 会覆盖这一层。
      return _PerComicScope(
        perComic: false,
        child: _ReaderSettingsSheet(
          changePageIndex: changePageIndex ?? (_) {},
          onLandscapeChanged: onLandscapeChanged,
          onDoublePageModeChanged: onDoublePageModeChanged,
          source: source,
          comicId: comicId,
        ),
      );
    },
  );
}

class _ReaderSettingsSheet extends StatelessWidget {
  final ValueChanged<int> changePageIndex;
  final ValueChanged<bool>? onLandscapeChanged;
  final ValueChanged<bool>? onDoublePageModeChanged;
  final String source;
  final String comicId;

  const _ReaderSettingsSheet({
    required this.changePageIndex,
    this.onLandscapeChanged,
    this.onDoublePageModeChanged,
    this.source = '',
    this.comicId = '',
  });

  @override
  Widget build(BuildContext context) {
    final mediaSize = MediaQuery.sizeOf(context);
    final maxHeight = mediaSize.height * 0.7;
    final isAndroidPhone =
        !kIsWeb && Platform.isAndroid && mediaSize.shortestSide < 600;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Stack(
          children: [
            // 卡片外部的空白点击直接关闭（框体自身占满全屏，默认遮罩点不透）。
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).maybePop(),
                child: const SizedBox.expand(),
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: SizedBox(
                  height: maxHeight,
                  child: _ReaderSettingsCard(
                    changePageIndex: changePageIndex,
                    isAndroidPhone: isAndroidPhone,
                    onLandscapeChanged: onLandscapeChanged,
                    onDoublePageModeChanged: onDoublePageModeChanged,
                    source: source,
                    comicId: comicId,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReaderSettingsCard extends StatelessWidget {
  final ValueChanged<int> changePageIndex;
  final bool isAndroidPhone;
  final ValueChanged<bool>? onLandscapeChanged;
  final ValueChanged<bool>? onDoublePageModeChanged;
  final String source;
  final String comicId;

  const _ReaderSettingsCard({
    required this.changePageIndex,
    required this.isAndroidPhone,
    this.onLandscapeChanged,
    this.onDoublePageModeChanged,
    this.source = '',
    this.comicId = '',
  });

  @override
  Widget build(BuildContext context) {
    final c = context.calm;

    final perComicAvailable =
        source.trim().isNotEmpty && comicId.trim().isNotEmpty;
    final tabLength = perComicAvailable ? 4 : 3;

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: c.border),
        boxShadow: c.shadowMd,
      ),
      clipBehavior: Clip.antiAlias,
      child: DefaultTabController(
        length: tabLength,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ReaderSettingsHeader(showPerComicTab: perComicAvailable),
            Expanded(
              child: TabBarView(
                children: [
                  _ReaderSettingsReadTab(
                    changePageIndex: changePageIndex,
                    onLandscapeChanged: onLandscapeChanged,
                    onDoublePageModeChanged: onDoublePageModeChanged,
                    source: source,
                    comicId: comicId,
                  ),
                  _ReaderSettingsGestureTab(isAndroidPhone: isAndroidPhone),
                  const _ReaderSettingsInfoTab(),
                  if (perComicAvailable)
                    _ReaderSettingsPerComicTab(
                      changePageIndex: changePageIndex,
                      onLandscapeChanged: onLandscapeChanged,
                      onDoublePageModeChanged: onDoublePageModeChanged,
                      source: source,
                      comicId: comicId,
                      isAndroidPhone: isAndroidPhone,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 设置页头部：抓手 + 轻盈 TabBar（阅读页入口多一个“本漫”tab）。
class _ReaderSettingsHeader extends StatelessWidget {
  final bool showPerComicTab;

  const _ReaderSettingsHeader({this.showPerComicTab = false});

  @override
  Widget build(BuildContext context) {
    final c = context.calm;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).maybePop(),
            child: Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: c.borderStrong,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            padding: EdgeInsets.zero,
            dividerHeight: 0,
            indicatorColor: c.accent,
            indicatorSize: TabBarIndicatorSize.label,
            indicatorWeight: 2,
            splashFactory: NoSplash.splashFactory,
            overlayColor: const WidgetStatePropertyAll<Color>(
              Colors.transparent,
            ),
            labelColor: c.text,
            unselectedLabelColor: c.text3,
            labelPadding: const EdgeInsets.symmetric(horizontal: 12),
            labelStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
            unselectedLabelStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
            tabs: [
              Tab(height: 40, text: t.reader.settings),
              Tab(height: 40, text: t.reader.gesture),
              Tab(height: 40, text: t.reader.infoBar),
              if (showPerComicTab)
                Tab(height: 40, text: t.reader.perComicThisComic),
            ],
          ),
        ),
        Divider(height: 1, thickness: 1, color: c.border),
      ],
    );
  }
}

class _SettingsNoticeCard extends StatelessWidget {
  final String text;
  final CalmTone tone;

  const _SettingsNoticeCard({required this.text, this.tone = CalmTone.info});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
      child: CalmStatusBanner(title: text, tone: tone),
    );
  }
}

class _SettingsTabContent extends StatelessWidget {
  final Widget child;

  const _SettingsTabContent({required this.child});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      child: child,
    );
  }
}

/// 阅读设置 sheet 内通用的“读目标值 + 按目标写”。
/// 读：[watchTargetReadSetting]——本漫 tab 读有效值（patch 已合并），其余只读全局。
/// 写：按当前编辑目标路由——改全局走 `GlobalSettingCubit`，
/// 改本漫走 `ComicReadPreferenceCubit.updateField`，只写变化的 key。
/// 需要震动反馈由调用方自己加；需要跳页（如切阅读模式）也由调用方自己调。
///
/// 写目标只看 [_PerComicScope]：外层恒包 `perComic: false`，
/// 第四个“本漫”tab 内层包 `perComic: true`，里面所有控件读写全钉本漫。
/// 加新设置项只写一遍 Section，第四 tab 复用同一个，不写第二遍。
extension EffectiveReadSettingX on BuildContext {
  /// 当前编辑目标是不是本漫：只看最近的 [_PerComicScope]，不回退读 cubit。
  ///
  /// 旧漫画的绑定状态漏不进全局页——全局入口与前三个 tab 恒为 false。
  bool get isEditingPerComic => _PerComicScope.maybeOf(this)?.perComic ?? false;

  /// 当前编辑目标的值：本漫 tab 读有效值，其余只读全局。
  ///
  /// 设置 UI 一律读这个，保证“显示什么就改什么”；渲染层继续用
  /// [ComicReadPreferenceContextX.watchEffectiveReadSetting]。
  ReadSettingState watchTargetReadSetting() {
    if (isEditingPerComic) return watchEffectiveReadSetting();
    return watch<GlobalSettingCubit>().state.readSetting;
  }

  /// 按编辑目标写入：本漫→patch（只含变化 key），全局→全局设置。
  Future<Set<String>> updateEffectiveReadSetting(
    ReadSettingState effective,
    ReadSettingState Function(ReadSettingState current) fn,
  ) {
    if (isEditingPerComic) {
      return read<ComicReadPreferenceCubit>().updateField(effective, fn);
    }
    read<GlobalSettingCubit>().updateReadSetting(fn);
    return Future.value(const <String>{});
  }
}

/// 钉死子树写目标：`perComic: true` 包住第四 tab，里面全写本漫。
class _PerComicScope extends InheritedWidget {
  final bool perComic;

  const _PerComicScope({required this.perComic, required super.child});

  static _PerComicScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<_PerComicScope>();
  }

  @override
  bool updateShouldNotify(_PerComicScope oldWidget) {
    return perComic != oldWidget.perComic;
  }
}

/// 一个设置分组：轻盈分组头 + 一张零内边距圆角卡片，行间用柔和细线分隔。
///
/// 卡内不再套卡：开关行 / 下拉行 / 滑块行都直接铺在卡片上，
/// 芯片组与提示条作为带内边距的整块参与分隔。
class _SettingsSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  /// 标题行右侧动作（如本漫 tab 阅读模式旁的“跟随全局”）。
  final Widget? trailing;

  const _SettingsSection({
    required this.title,
    required this.children,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      rows.add(children[i]);
      if (i != children.length - 1) {
        rows.add(
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: CalmDivider(),
          ),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        CalmSectionHeader(title: title, trailing: trailing),
        const SizedBox(height: 8),
        // 抽屉本身就是一张 surface 卡片，分组再用 surface 会变成“卡套卡”；
        // 这里用画布色（bg）做柔和分组块，分割线 / 悬停 / 胶囊芯片都还能分层。
        CalmCard(
          color: c.bg,
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: rows,
          ),
        ),
      ],
    );
  }
}

/// 分组内的一排胶囊芯片（阅读模式 / 主题 / 背景 / 位置等单选）。
class _SettingsChipRow extends StatelessWidget {
  final List<Widget> children;

  const _SettingsChipRow(this.children);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 11),
      child: Wrap(spacing: 8, runSpacing: 8, children: children),
    );
  }
}

class _SettingsChoiceChip extends StatelessWidget {
  final String title;
  final bool selected;
  final VoidCallback onTap;

  const _SettingsChoiceChip({
    required this.title,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return CalmFilterChip(
      label: title,
      selected: selected,
      onSelected: (_) => onTap(),
    );
  }
}

class _SettingsSwitchTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SettingsSwitchTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return CalmListTile(
      title: title,
      subtitle: subtitle,
      onTap: () => onChanged(!value),
      trailing: CalmSwitch(value: value, onChanged: onChanged),
    );
  }
}

class _SettingsDropdownTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final int value;
  final List<int> values;
  final ValueChanged<int> onChanged;

  const _SettingsDropdownTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.values,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return CalmListTile(
      title: title,
      subtitle: subtitle,
      trailing: FluentDropdown<int>(
        value: value,
        displayValue: value.toString(),
        items: {for (final option in values) option: option.toString()},
        onChanged: onChanged,
      ),
    );
  }
}

class _SettingsSliderCard extends StatelessWidget {
  final String title;
  final int value;
  final int min;
  final int max;
  final int divisions;
  final String suffix;
  final bool enabled;
  final ValueChanged<int> onChanged;

  const _SettingsSliderCard({
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.suffix,
    this.enabled = true,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final slider = CalmSlider(
      label: title,
      valueText: '$value $suffix',
      value: value.clamp(min, max).toDouble(),
      min: min.toDouble(),
      max: max.toDouble(),
      divisions: divisions,
      onChanged: (newValue) {
        final nextValue = newValue.round().clamp(min, max);
        if (nextValue != value) {
          HapticFeedback.selectionClick();
          onChanged(nextValue);
        }
      },
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: enabled
          ? slider
          : IgnorePointer(child: Opacity(opacity: 0.45, child: slider)),
    );
  }
}
