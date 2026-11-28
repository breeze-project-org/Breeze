import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:file_selector/file_selector.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/page/setting/common/setting_ui.dart';
import 'package:zephyr/page/setting/real_sr/service/android_ncnn_model_config.dart';
import 'package:zephyr/page/setting/real_sr/service/desktop_ncnn_model_config.dart';
import 'package:zephyr/page/setting/real_sr/service/real_sr_settings.dart';
import 'package:zephyr/page/setting/real_sr/service/real_sr_super_resolution.dart';
import 'package:zephyr/type/enum.dart';
import 'package:zephyr/util/coreml/coreml_model_config.dart';
import 'package:zephyr/util/system/external_link.dart';
import 'package:zephyr/widgets/fluent_dropdown.dart';
import 'package:zephyr/widgets/toast.dart';

final Map<int, String> _concurrencyLabels = {
  1: '1',
  2: '2',
  4: '4',
  6: '6',
  8: '8',
  0: t.realSr.unlimited,
};

const Map<int, String> _tileSizeLabels = {
  0: '0',
  128: '128',
  256: '256',
  512: '512',
  1024: '1024',
};

final List<int> _concurrencyOptions = _concurrencyLabels.keys.toList()..sort();
final List<int> _tileSizeOptions = _tileSizeLabels.keys.toList()..sort();

@RoutePage()
class RealSrSettingPage extends StatefulWidget {
  const RealSrSettingPage({super.key});

  @override
  State<RealSrSettingPage> createState() => _RealSrSettingPageState();
}

class _RealSrSettingPageState extends State<RealSrSettingPage> {
  bool _loading = true;
  bool _autoUpscale = false;
  RealSrResolutionThreshold _resolutionThreshold =
      RealSrResolutionThreshold.p720;
  int _concurrency = 2;
  int _tileSize = 0;
  AndroidNcnnMode _desktopNcnnMode = DesktopNcnnModelConfig.defaultMode;
  AndroidNcnnNoise _desktopNcnnNoise = DesktopNcnnModelConfig.defaultNoise;
  CoreMLModelFamily _coreMLFamily = CoreMLModelConfig.defaultFamily;
  CoreMLModelVariant _coreMLVariant = CoreMLModelConfig.defaultVariant;
  bool _isAvailable = false;
  bool _downloading = false;
  bool _importing = false;
  double _downloadProgress = 0;

  bool get _usesCoreML => Platform.isIOS || Platform.isMacOS;

  List<RealSrResolutionThreshold> get _availableThresholds {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      return RealSrResolutionThreshold.values;
    }
    return const [
      RealSrResolutionThreshold.p540,
      RealSrResolutionThreshold.p720,
      RealSrResolutionThreshold.p1080,
    ];
  }

  RealSrResolutionThreshold get _effectiveThreshold {
    if (_availableThresholds.contains(_resolutionThreshold)) {
      return _resolutionThreshold;
    }
    return RealSrResolutionThreshold.p1080;
  }

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final family = await RealSrSettings.loadCoreMLFamily();
    final variant = await RealSrSettings.loadCoreMLVariant(family);
    final results = await Future.wait([
      RealSrSettings.loadAutoUpscale(),
      RealSrSettings.loadResolutionThreshold(),
      RealSrSettings.loadConcurrency(),
      RealSrSettings.loadTileSize(),
      RealSrSettings.loadDesktopNcnnMode(),
      RealSrSettings.loadDesktopNcnnNoise(),
      RealSrSuperResolution.isAvailable,
    ]);

    if (!mounted) return;
    setState(() {
      _autoUpscale = results[0] as bool;
      _resolutionThreshold = results[1] as RealSrResolutionThreshold;
      _concurrency = results[2] as int;
      _tileSize = results[3] as int;
      _desktopNcnnMode = results[4] as AndroidNcnnMode;
      _desktopNcnnNoise = results[5] as AndroidNcnnNoise;
      _isAvailable = results[6] as bool;
      _coreMLFamily = family;
      _coreMLVariant = variant;
      _loading = false;
    });
  }

  Future<void> _setAutoUpscale(bool value) async {
    await RealSrSettings.saveAutoUpscale(value);
    setState(() => _autoUpscale = value);
  }

  Future<void> _setResolutionThreshold(RealSrResolutionThreshold value) async {
    await RealSrSettings.saveResolutionThreshold(value);
    setState(() => _resolutionThreshold = value);
  }

  Future<void> _setConcurrency(int value) async {
    await RealSrSettings.saveConcurrency(value);
    setState(() => _concurrency = value);
  }

  Future<void> _setTileSize(int value) async {
    await RealSrSettings.saveTileSize(value);
    setState(() => _tileSize = value);
  }

  Future<void> _setDesktopNcnnMode(AndroidNcnnMode value) async {
    await RealSrSettings.saveDesktopNcnnMode(value);
    setState(() => _desktopNcnnMode = value);
  }

  Future<void> _setDesktopNcnnNoise(AndroidNcnnNoise value) async {
    await RealSrSettings.saveDesktopNcnnNoise(value);
    setState(() => _desktopNcnnNoise = value);
  }

  Future<void> _setCoreMLFamily(CoreMLModelFamily value) async {
    final newVariant = value.variants.first;
    await Future.wait([
      RealSrSettings.saveCoreMLFamily(value),
      RealSrSettings.saveCoreMLVariant(newVariant),
    ]);
    setState(() {
      _coreMLFamily = value;
      _coreMLVariant = newVariant;
    });
  }

  Future<void> _setCoreMLVariant(CoreMLModelVariant value) async {
    await RealSrSettings.saveCoreMLVariant(value);
    setState(() => _coreMLVariant = value);
  }

  Future<void> _refreshAvailability() async {
    final available = await RealSrSuperResolution.isAvailable;
    if (mounted) setState(() => _isAvailable = available);
  }

  Future<void> _downloadModel() async {
    setState(() {
      _downloading = true;
      _downloadProgress = 0;
    });

    try {
      await RealSrSuperResolution.downloadModel(
        force: _isAvailable,
        onProgress: (received, total) {
          if (!mounted || total <= 0) return;
          setState(() => _downloadProgress = received / total);
        },
      );
    } catch (e, s) {
      logger.e('模型下载失败', error: e, stackTrace: s);
      showErrorToast('${t.realSr.modelDownloadFailed}: $e');
    } finally {
      if (mounted) {
        setState(() => _downloading = false);
        await _refreshAvailability();
      }
    }
  }

  Future<void> _deleteModel() async {
    final confirmed = await showCalmDialog<bool>(
      context,
      title: t.realSr.deleteModel,
      icon: Icons.delete_outline_rounded,
      tone: CalmTone.danger,
      bodyBuilder: (dialogContext) => Text(
        t.realSr.deleteModelConfirm,
        style: TextStyle(fontSize: 12, color: dialogContext.calm.text2),
      ),
      actionsBuilder: (dialogContext) => [
        CalmButton(
          label: t.common.cancel,
          variant: CalmButtonVariant.ghost,
          onPressed: () => Navigator.of(dialogContext).pop(false),
        ),
        CalmButton(
          label: t.common.delete,
          variant: CalmButtonVariant.danger,
          onPressed: () => Navigator.of(dialogContext).pop(true),
        ),
      ],
    );

    if (confirmed != true || !mounted) return;

    try {
      await RealSrSuperResolution.deleteModel();
      showSuccessToast(t.realSr.modelDeleted);
    } catch (e, s) {
      logger.e('模型删除失败', error: e, stackTrace: s);
      showErrorToast('${t.realSr.modelDeleteFailed}: $e');
    } finally {
      if (mounted) await _refreshAvailability();
    }
  }

  Future<void> _openManualDownloadUrl() async {
    final url = RealSrSuperResolution.manualDownloadUrl;
    if (url == null) {
      showErrorToast(t.realSr.manualDownloadUnsupported);
      return;
    }
    final opened = await openExternalUrl(Uri.parse(url));
    if (!opened && mounted) {
      showErrorToast(t.realSr.openDownloadUrlFailed);
    }
  }

  Future<void> _importModel() async {
    // iOS 没有系统声明的 7z UTI，使用通用数据类型后由导入逻辑校验 7z 魔数。
    final typeGroup = Platform.isIOS
        ? const XTypeGroup(label: '7z')
        : const XTypeGroup(label: '7z', extensions: ['7z']);
    final XFile? file;
    try {
      file = await openFile(acceptedTypeGroups: [typeGroup]);
    } catch (e) {
      logger.e(e);
      showErrorToast('${t.realSr.modelImportFailed}: $e');
      return;
    }
    if (file == null) return;

    setState(() => _importing = true);
    try {
      await RealSrSuperResolution.importModelArchive(file.path);
      if (mounted) showSuccessToast(t.realSr.modelImportSuccess);
    } catch (e, s) {
      logger.e('模型导入失败', error: e, stackTrace: s);
      if (mounted) {
        showErrorToast('${t.realSr.modelImportFailed}: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _importing = false);
        await _refreshAvailability();
      }
    }
  }

  String get _coreMLBlockInfo {
    final blockSize = _coreMLVariant.config['blockSize'] as int? ?? 0;
    final shrinkSize = _coreMLVariant.config['shrinkSize'] as int? ?? 0;
    final contentSize = CoreMLModelConfig.contentBlockSize(_coreMLVariant);
    return t.realSr.blockInfoFormat(
      contentSize: contentSize,
      blockSize: blockSize,
      shrinkSize: shrinkSize,
    );
  }

  List<Widget> _buildModelItems() {
    if (_usesCoreML) {
      return [
        CalmListTile(
          leading: settingTileIcon(Icons.speed_outlined),
          title: t.realSr.model,
          subtitle: t.realSr.modelSubtitle,
          trailing: FluentDropdown<CoreMLModelFamily>(
            value: _coreMLFamily,
            displayValue: _coreMLFamily.localizedLabel,
            items: {
              for (final family in CoreMLModelConfig.families)
                family: family.localizedLabel,
            },
            onChanged: _setCoreMLFamily,
          ),
        ),
        CalmListTile(
          leading: settingTileIcon(Icons.healing_outlined),
          title: t.realSr.noiseLevel,
          subtitle: t.realSr.noiseLevelSubtitle,
          trailing: FluentDropdown<CoreMLModelVariant>(
            value: _coreMLVariant,
            displayValue: _coreMLVariant.localizedDisplayName,
            items: {
              for (final variant in _coreMLFamily.variants)
                variant: variant.localizedDisplayName,
            },
            onChanged: _setCoreMLVariant,
          ),
        ),
        CalmListTile(
          leading: settingTileIcon(Icons.grid_view_outlined),
          title: t.realSr.blockInfo,
          subtitle: _coreMLBlockInfo,
          trailing: Tooltip(
            triggerMode: TooltipTriggerMode.tap,
            showDuration: const Duration(seconds: 5),
            message: t.realSr.blockInfoTooltip,
            child: Icon(
              Icons.help_outline_rounded,
              size: 16,
              color: context.calm.text3,
            ),
          ),
        ),
      ];
    }

    if (Platform.isAndroid) {
      return [
        CalmListTile(
          leading: settingTileIcon(Icons.info_outline_rounded),
          title: t.realSr.androidSuperResolution,
          subtitle: t.realSr.androidSuperResolutionSubtitle,
        ),
      ];
    }

    return [
      CalmListTile(
        leading: settingTileIcon(Icons.speed_outlined),
        title: t.realSr.desktopStrategy,
        subtitle: t.realSr.desktopStrategySubtitle,
        trailing: FluentDropdown<AndroidNcnnMode>(
          value: _desktopNcnnMode,
          displayValue: _desktopNcnnMode.label,
          items: {for (final mode in AndroidNcnnMode.values) mode: mode.label},
          onChanged: _setDesktopNcnnMode,
        ),
      ),
      CalmListTile(
        leading: settingTileIcon(Icons.healing_outlined),
        title: t.realSr.desktopNoiseLevel,
        subtitle: t.realSr.desktopNoiseLevelSubtitle,
        trailing: FluentDropdown<AndroidNcnnNoise>(
          value: _desktopNcnnNoise,
          displayValue: _desktopNcnnNoise.label,
          items: {
            for (final noise in AndroidNcnnNoise.values) noise: noise.label,
          },
          onChanged: _setDesktopNcnnNoise,
        ),
      ),
    ];
  }

  Widget _buildModelManagementTile() {
    if (_downloading) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: CalmProgressBar(
          value: _downloadProgress,
          label: t.realSr.downloadingModel,
          trailingText: '${(_downloadProgress * 100).toStringAsFixed(1)}%',
        ),
      );
    }

    if (_isAvailable) {
      return CalmListTile(
        leading: settingTileIcon(Icons.check_circle_outline_rounded),
        title: t.realSr.modelReady,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CalmButton(
              label: t.realSr.deleteModel,
              variant: CalmButtonVariant.danger,
              size: CalmButtonSize.xs,
              onPressed: _deleteModel,
            ),
            const SizedBox(width: 6),
            CalmButton(
              label: t.realSr.redownload,
              variant: CalmButtonVariant.secondary,
              size: CalmButtonSize.xs,
              onPressed: _downloadModel,
            ),
          ],
        ),
      );
    }

    return CalmListTile(
      leading: settingTileIcon(Icons.warning_amber_rounded),
      title: t.realSr.modelNotDownloaded,
      subtitle: t.realSr.modelNotDownloadedSubtitle,
      trailing: CalmButton(
        label: t.realSr.downloadModel,
        icon: Icons.download_rounded,
        variant: CalmButtonVariant.primary,
        size: CalmButtonSize.xs,
        onPressed: _downloadModel,
      ),
    );
  }

  Widget _buildManualDownloadTile() {
    final url = RealSrSuperResolution.manualDownloadUrl;
    if (url == null) {
      return CalmListTile(
        leading: settingTileIcon(Icons.open_in_browser_outlined),
        title: t.realSr.manualDownload,
        subtitle: t.realSr.manualDownloadUnsupported,
      );
    }
    return CalmListTile(
      leading: settingTileIcon(Icons.open_in_browser_outlined),
      title: t.realSr.manualDownload,
      subtitle: url,
      trailing: CalmButton(
        label: t.realSr.openDownloadUrl,
        variant: CalmButtonVariant.ghost,
        size: CalmButtonSize.xs,
        onPressed: _openManualDownloadUrl,
      ),
    );
  }

  Widget _buildImportModelTile() {
    return CalmListTile(
      leading: settingTileIcon(Icons.file_open_outlined),
      title: t.realSr.importModel,
      subtitle: t.realSr.importModelSubtitle,
      trailing: _importing
          ? const CalmLoading(size: 16)
          : CalmButton(
              label: t.realSr.importModelAction,
              variant: CalmButtonVariant.secondary,
              size: CalmButtonSize.xs,
              onPressed: _importModel,
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SettingPageShell(
      title: t.realSr.title,
      child: _loading
          ? const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : ListView(
              padding: kSettingPagePadding,
              children: [
                settingSectionTitle(context, t.realSr.autoUpscaleSection),
                settingCardGroup([
                  settingSwitchTile(
                    icon: Icons.auto_fix_high_outlined,
                    title: t.realSr.autoUpscale,
                    subtitle: !_isAvailable
                        ? t.realSr.autoUpscaleSubtitleUnavailable
                        : t.realSr.autoUpscaleSubtitleAvailable,
                    value: _autoUpscale,
                    onChanged: _setAutoUpscale,
                  ),
                ]),

                settingSectionTitle(context, t.realSr.conditionSection),
                settingCardGroup([
                  CalmListTile(
                    leading: settingTileIcon(Icons.hd_outlined),
                    title: t.realSr.resolutionThreshold,
                    subtitle: t.realSr.resolutionThresholdSubtitle,
                    trailing: FluentDropdown<RealSrResolutionThreshold>(
                      value: _effectiveThreshold,
                      displayValue: _effectiveThreshold.label,
                      items: {
                        for (final threshold in _availableThresholds)
                          threshold: threshold.label,
                      },
                      onChanged: _setResolutionThreshold,
                    ),
                  ),
                ]),

                settingSectionTitle(context, t.realSr.performanceSection),
                settingCardGroup([
                  Builder(
                    builder: (context) {
                      final effective =
                          _concurrencyOptions.contains(_concurrency)
                          ? _concurrency
                          : RealSrSettings.defaultConcurrency;
                      return CalmListTile(
                        leading: settingTileIcon(Icons.speed_outlined),
                        title: t.realSr.concurrency,
                        subtitle: t.realSr.concurrencySubtitle,
                        trailing: FluentDropdown<int>(
                          value: effective,
                          displayValue: _concurrencyLabels[effective]!,
                          items: {
                            for (final option in _concurrencyOptions)
                              option: _concurrencyLabels[option]!,
                          },
                          onChanged: _setConcurrency,
                        ),
                      );
                    },
                  ),
                  if (!_usesCoreML)
                    Builder(
                      builder: (context) {
                        final effective = _tileSizeOptions.contains(_tileSize)
                            ? _tileSize
                            : 0;
                        return CalmListTile(
                          leading: settingTileIcon(Icons.grid_on_outlined),
                          title: t.realSr.tileSize,
                          subtitle: t.realSr.tileSizeSubtitle,
                          trailing: FluentDropdown<int>(
                            value: effective,
                            displayValue: _tileSizeLabels[effective]!,
                            items: {
                              for (final option in _tileSizeOptions)
                                option: _tileSizeLabels[option]!,
                            },
                            onChanged: _setTileSize,
                          ),
                        );
                      },
                    ),
                ]),

                settingSectionTitle(context, t.realSr.modelSection),
                settingCardGroup(_buildModelItems()),

                settingSectionTitle(context, t.realSr.modelManagementSection),
                settingCardGroup([
                  _buildModelManagementTile(),
                  _buildManualDownloadTile(),
                  _buildImportModelTile(),
                ]),
                const SizedBox(height: 32),
              ],
            ),
    );
  }
}
