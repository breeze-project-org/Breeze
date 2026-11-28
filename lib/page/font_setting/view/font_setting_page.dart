import 'package:auto_route/annotations.dart';
import 'package:file_selector/file_selector.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as path;
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/setting/common/setting_ui.dart';
import 'package:zephyr/util/font/font_profile.dart';
import 'package:zephyr/widgets/toast.dart';

@RoutePage()
class FontSettingPage extends StatelessWidget {
  const FontSettingPage({super.key});

  static const _weights = <int>[100, 200, 300, 400, 500, 600, 700, 800, 900];
  static final _sampleText = t.fontSetting.sampleText;

  @override
  Widget build(BuildContext context) {
    return SettingPageShell(
      title: t.fontSetting.title,
      actions: [
        CalmIconButton(
          icon: Icons.restart_alt_rounded,
          tooltip: t.fontSetting.clear,
          onPressed: _clearAll,
        ),
      ],
      child: AnimatedBuilder(
        animation: FontProfileController.instance,
        builder: (context, _) {
          final controller = FontProfileController.instance;
          return ListView(
            padding: kSettingPagePadding,
            children: [
              CalmStatusBanner(title: t.fontSetting.hint),
              settingSectionTitle(
                context,
                t.fontSetting.title,
                icon: Icons.font_download_outlined,
              ),
              CalmCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (var i = 0; i < _weights.length; i++) ...[
                      _FontWeightTile(
                        weight: _weights[i],
                        label: fontWeightLabels[_weights[i]]!,
                        filePath: controller.pathForWeight(_weights[i]) ?? '',
                        sampleText: _sampleText,
                        onPick: () => _pickWeight(_weights[i]),
                        onClear:
                            (controller.pathForWeight(_weights[i]) ?? '')
                                .isEmpty
                            ? null
                            : () => _saveWeight(_weights[i], ''),
                      ),
                      if (i != _weights.length - 1)
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12),
                          child: CalmDivider(),
                        ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }

  Future<void> _pickWeight(int weight) async {
    const typeGroup = XTypeGroup(
      label: 'font',
      extensions: ['ttf', 'otf', 'ttc'],
      uniformTypeIdentifiers: ['public.font'],
    );
    final file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file == null) return;
    await _saveWeight(weight, file.path);
  }

  Future<void> _saveWeight(int weight, String filePath) async {
    final ok = await FontProfileController.instance.setPath(weight, filePath);
    if (!ok) {
      showErrorToast(t.fontSetting.loadFailed);
      return;
    }
    showSuccessToast(
      filePath.isEmpty ? t.fontSetting.cleared : t.fontSetting.saved,
    );
  }

  Future<void> _clearAll() async {
    await FontProfileController.instance.clearAll();
    showSuccessToast(t.fontSetting.allCleared);
  }
}

/// 单个字重行：左侧 w100–w900 徽章 + 文件名/实时预览 + 选文件/清除图标按钮。
class _FontWeightTile extends StatelessWidget {
  const _FontWeightTile({
    required this.weight,
    required this.label,
    required this.filePath,
    required this.sampleText,
    required this.onPick,
    required this.onClear,
  });

  final int weight;
  final String label;
  final String filePath;
  final String sampleText;
  final VoidCallback onPick;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    final fontWeight = _toFontWeight(weight);
    // 实时预览：直接用当前字重加载的自定义字体渲染示例文本。
    final previewStyle = FontProfileController.instance.applyStyleForWeight(
      TextStyle(fontWeight: fontWeight, fontSize: 13.5, color: c.text),
      weight,
    );

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: c.rowVPadding),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 44,
            child: Center(child: CalmBadge(label: 'w$weight')),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        filePath.isEmpty
                            ? t.fontSetting.noFileSelected
                            : path.basename(filePath),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: c.text,
                          height: 1.3,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      label,
                      style: TextStyle(fontSize: 10.5, color: c.text3),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  sampleText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: previewStyle,
                ),
                if (filePath.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    filePath,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10, color: c.text3),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (onClear != null)
            CalmIconButton(
              icon: Icons.close_rounded,
              tooltip: t.fontSetting.clearFile,
              onPressed: onClear,
              size: 28,
              iconSize: 14,
            ),
          const SizedBox(width: 4),
          CalmIconButton(
            icon: Icons.folder_open_rounded,
            tooltip: t.fontSetting.selectFile,
            selected: filePath.isNotEmpty,
            onPressed: onPick,
            size: 28,
            iconSize: 15,
          ),
        ],
      ),
    );
  }

  FontWeight _toFontWeight(int weight) {
    switch (weight) {
      case 100:
        return FontWeight.w100;
      case 200:
        return FontWeight.w200;
      case 300:
        return FontWeight.w300;
      case 400:
        return FontWeight.w400;
      case 500:
        return FontWeight.w500;
      case 600:
        return FontWeight.w600;
      case 700:
        return FontWeight.w700;
      case 800:
        return FontWeight.w800;
      default:
        return FontWeight.w900;
    }
  }
}
