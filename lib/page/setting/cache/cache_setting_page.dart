import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/util/storage/get_path.dart';
import 'package:zephyr/util/storage/manage_cache.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/widgets/fluent_dropdown.dart';
import 'package:zephyr/widgets/toast.dart';

import 'package:zephyr/page/setting/common/setting_ui.dart';
import 'package:zephyr/main.dart';

const Map<int, String> _cacheLimitLabels = {
  536870912: '512 MB',
  1073741824: '1 GB',
  2147483648: '2 GB',
  4294967296: '4 GB',
  8589934592: '8 GB',
  17179869184: '16 GB',
};

final List<int> _cacheLimitOptions = _cacheLimitLabels.keys.toList()..sort();

@RoutePage()
class CacheSettingPage extends StatefulWidget {
  const CacheSettingPage({super.key});

  @override
  State<CacheSettingPage> createState() => _CacheSettingPageState();
}

class _CacheSettingPageState extends State<CacheSettingPage> {
  int? _cacheSizeBytes;
  bool _calculating = false;

  @override
  void initState() {
    super.initState();
    _calculateCacheSize();
  }

  Future<void> _calculateCacheSize() async {
    if (_calculating) return;
    setState(() => _calculating = true);

    try {
      final cachePath = await getCachePath();
      final directory = Directory(cachePath);
      if (!await directory.exists()) {
        if (!mounted) return;
        setState(() {
          _cacheSizeBytes = 0;
          _calculating = false;
        });
        return;
      }

      int totalSize = 0;
      final entities = directory.listSync(recursive: true);
      for (final entity in entities) {
        final isSentry = entity.path
            .split(Platform.pathSeparator)
            .contains('sentry');
        if (entity is File && !isSentry) {
          try {
            totalSize += await entity.length();
          } on FileSystemException {
            continue;
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _cacheSizeBytes = totalSize;
        _calculating = false;
      });
    } catch (e, st) {
      logger.e(e, stackTrace: st);
      if (!mounted) return;
      setState(() {
        _cacheSizeBytes = null;
        _calculating = false;
      });
    }
  }

  String _formatSize(int? bytes) {
    if (bytes == null) return t.cache.calculateFailed;
    if (bytes == 0) return '0 B';

    const gb = 1 << 30;
    const mb = 1 << 20;
    const kb = 1 << 10;

    if (bytes >= gb) {
      return '${(bytes / gb).toStringAsFixed(2)} GB';
    } else if (bytes >= mb) {
      return '${(bytes / mb).toStringAsFixed(1)} MB';
    } else if (bytes >= kb) {
      return '${(bytes / kb).toStringAsFixed(1)} KB';
    } else {
      return '$bytes B';
    }
  }

  Future<void> _handleClearCache() async {
    final confirmed = await showCalmDialog<bool>(
      context,
      title: t.cache.clearCache,
      icon: Icons.delete_sweep_outlined,
      tone: CalmTone.danger,
      bodyBuilder: (dialogContext) => Text(
        t.cache.clearCacheConfirm,
        style: TextStyle(fontSize: 12, color: dialogContext.calm.text2),
      ),
      actionsBuilder: (dialogContext) => [
        CalmButton(
          label: t.common.cancel,
          variant: CalmButtonVariant.ghost,
          onPressed: () => Navigator.of(dialogContext).pop(false),
        ),
        CalmButton(
          label: t.common.ok,
          variant: CalmButtonVariant.danger,
          onPressed: () => Navigator.of(dialogContext).pop(true),
        ),
      ],
    );

    if (confirmed != true) return;

    try {
      final cachePath = await getCachePath();
      await clearCache(cachePath);
      showSuccessToast(t.cache.cleared);
      _calculateCacheSize();
    } catch (e, st) {
      logger.e(e, stackTrace: st);
      showSuccessToast(t.cache.clearFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<GlobalSettingCubit>();
    final state = cubit.state;
    final effectiveCacheLimit =
        _cacheLimitOptions.contains(state.cacheSetting.cacheSizeLimit)
        ? state.cacheSetting.cacheSizeLimit
        : 1073741824;

    return SettingPageShell(
      title: t.cache.title,
      child: ListView(
        padding: kSettingPagePadding,
        children: [
          settingSectionTitle(
            context,
            t.cache.currentCache,
            icon: Icons.storage_outlined,
          ),
          settingCardGroup([
            CalmListTile(
              leading: settingTileIcon(Icons.storage_outlined),
              title: t.cache.cacheSize,
              subtitle: _calculating
                  ? t.cache.calculating
                  : _formatSize(_cacheSizeBytes),
              trailing: _calculating
                  ? const CalmLoading(size: 16)
                  : CalmIconButton(
                      icon: Icons.refresh_rounded,
                      tooltip: t.cache.recalculate,
                      onPressed: _calculateCacheSize,
                    ),
            ),
            CalmListTile(
              leading: settingTileIcon(Icons.cleaning_services_outlined),
              title: t.cache.manualClear,
              subtitle: t.cache.manualClearSubtitle,
              trailing: CalmButton(
                label: t.cache.clear,
                icon: Icons.delete_outline_rounded,
                variant: CalmButtonVariant.tonal,
                size: CalmButtonSize.xs,
                onPressed: _handleClearCache,
              ),
            ),
          ]),
          settingSectionTitle(
            context,
            t.cache.cacheLimit,
            icon: Icons.data_thresholding_outlined,
          ),
          settingCardGroup([
            CalmListTile(
              leading: settingTileIcon(Icons.data_thresholding_outlined),
              title: t.cache.sizeLimit,
              subtitle: t.cache.sizeLimitSubtitle,
              trailing: FluentDropdown<int>(
                value: effectiveCacheLimit,
                displayValue: _cacheLimitLabels[effectiveCacheLimit]!,
                items: _cacheLimitLabels,
                onChanged: (int value) {
                  cubit.updateCacheSetting(
                    (current) => current.copyWith(cacheSizeLimit: value),
                  );
                },
              ),
            ),
          ]),
          settingSectionTitle(
            context,
            t.cache.autoClean,
            icon: Icons.auto_delete_outlined,
          ),
          settingCardGroup([
            settingSwitchTile(
              icon: Icons.auto_delete_outlined,
              title: t.cache.autoClean,
              subtitle: t.cache.autoCleanSubtitle,
              value: state.cacheSetting.autoCleanCache,
              onChanged: (bool value) {
                cubit.updateCacheSetting(
                  (current) => current.copyWith(autoCleanCache: value),
                );
              },
            ),
          ]),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
