import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/network/sync/comic_sync_core.dart';
import 'package:zephyr/network/sync/sync_service.dart';
import 'package:zephyr/page/comic_follow/cubit/comic_follow_cubit.dart';
import 'package:zephyr/page/setting/common/setting_ui.dart';
import 'package:zephyr/page/setting/global/widgets.dart';
import 'package:zephyr/util/event/event.dart';
import 'package:zephyr/widgets/fluent_dropdown.dart';
import 'package:zephyr/widgets/toast.dart';

/// 自定义同步密钥的最小长度；空串仍表示使用默认密钥。
const int _syncKeyMinLength = 8;

@RoutePage()
class SyncSettingPage extends StatefulWidget {
  const SyncSettingPage({super.key});

  @override
  State<SyncSettingPage> createState() => _SyncSettingPageState();
}

class _SyncSettingPageState extends State<SyncSettingPage> {
  bool _uploading = false;
  bool _downloading = false;

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<GlobalSettingCubit>();
    final state = cubit.state;
    final configuredSync = isSyncServiceConfigured(state);

    return SettingPageShell(
      title: t.settings.sync,
      child: ListView(
        padding: kSettingPagePadding,
        children: [
          settingSectionTitle(
            context,
            t.settings.sync,
            icon: Icons.sync_outlined,
          ),
          settingCardGroup([
            _syncServiceType(state, cubit),
            _encryptionKey(state, cubit),
            webdavSync(context, state.syncSetting.syncServiceType),
            if (configuredSync) _autoSync(state, cubit),
            if (configuredSync && state.syncSetting.autoSync)
              _syncInterval(state, cubit),
            if (configuredSync && state.syncSetting.autoSync)
              _syncNotify(state, cubit),
            if (configuredSync) _syncSettings(state, cubit),
            if (configuredSync) _syncPlugins(state, cubit),
          ]),
          if (configuredSync) ...[
            settingSectionTitle(
              context,
              t.settings.manualSyncSection,
              icon: Icons.cloud_upload_outlined,
            ),
            settingCardGroup([
              _buildManualSyncTile(
                icon: Icons.upload_outlined,
                title: t.settings.uploadToCloud,
                subtitle: t.settings.uploadToCloudSubtitle,
                actionLabel: t.settings.manualUpload,
                busy: _uploading,
                onPressed: _manualUpload,
              ),
              _buildManualSyncTile(
                icon: Icons.download_outlined,
                title: t.settings.downloadFromCloud,
                subtitle: t.settings.downloadFromCloudSubtitle,
                actionLabel: t.settings.manualDownload,
                busy: _downloading,
                onPressed: _manualDownload,
              ),
            ]),
          ],
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Future<void> _manualUpload() async {
    final cubit = context.read<GlobalSettingCubit>();
    setState(() => _uploading = true);
    try {
      try {
        await manualUploadToCloud(
          state: cubit.state,
          globalSettingCubit: cubit,
          comicFollowCubit: context.read<ComicFollowCubit>(),
        );
      } on SyncDecryptionException {
        final confirmed = await _confirmOverwriteCloud();
        if (!mounted || confirmed != true) {
          return;
        }
        await manualUploadToCloud(
          state: cubit.state,
          globalSettingCubit: cubit,
          comicFollowCubit: context.read<ComicFollowCubit>(),
          forceOverwrite: true,
        );
      }
      if (mounted) showSuccessToast(t.settings.manualUploadSuccess);
    } catch (e, s) {
      logger.e('手动上传失败', error: e, stackTrace: s);
      if (mounted) {
        if (e is SyncDecryptionException) {
          showErrorToast(
            t.settings.syncKeyErrorCannotDecrypt,
            title: t.settings.syncKeyErrorTitle,
          );
        } else {
          showErrorToast('${t.settings.manualSyncFailed}: $e');
        }
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<bool?> _confirmOverwriteCloud() {
    return showCalmDialog<bool>(
      context,
      title: t.settings.syncKeyErrorTitle,
      icon: Icons.key_off_outlined,
      tone: CalmTone.warning,
      bodyBuilder: (dialogContext) => Text(
        t.settings.syncKeyOverwriteConfirm,
        style: TextStyle(fontSize: 12, color: dialogContext.calm.text2),
      ),
      actionsBuilder: (dialogContext) => [
        CalmButton(
          label: t.common.cancel,
          variant: CalmButtonVariant.ghost,
          onPressed: () => Navigator.of(dialogContext).pop(false),
        ),
        CalmButton(
          label: t.settings.syncKeyContinueUpload,
          variant: CalmButtonVariant.primary,
          onPressed: () => Navigator.of(dialogContext).pop(true),
        ),
      ],
    );
  }

  Future<void> _manualDownload() async {
    final cubit = context.read<GlobalSettingCubit>();
    setState(() => _downloading = true);
    try {
      await manualDownloadFromCloud(
        state: cubit.state,
        globalSettingCubit: cubit,
        comicFollowCubit: context.read<ComicFollowCubit>(),
      );
      if (mounted) showSuccessToast(t.settings.manualDownloadSuccess);
    } catch (e, s) {
      logger.e('手动下载失败', error: e, stackTrace: s);
      if (mounted) {
        if (e is SyncDecryptionException) {
          showErrorToast(
            t.settings.syncKeyErrorCannotDecrypt,
            title: t.settings.syncKeyErrorTitle,
          );
        } else {
          showErrorToast('${t.settings.manualSyncFailed}: $e');
        }
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Widget _buildManualSyncTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required String actionLabel,
    required bool busy,
    required VoidCallback onPressed,
  }) {
    return CalmListTile(
      leading: settingTileIcon(icon),
      title: title,
      subtitle: subtitle,
      trailing: CalmButton(
        label: actionLabel,
        variant: CalmButtonVariant.tonal,
        size: CalmButtonSize.xs,
        loading: busy,
        onPressed: busy ? null : onPressed,
      ),
    );
  }

  Widget _encryptionKey(GlobalSettingState state, GlobalSettingCubit cubit) {
    final key = state.syncSetting.encryptionKey;
    return settingActionTile(
      icon: Icons.key_outlined,
      title: t.settings.customEncryptionKey,
      subtitle: key.isEmpty
          ? t.settings.customEncryptionKeyDefault
          : t.settings.customEncryptionKeySet,
      onTap: () => _editEncryptionKey(state.syncSetting, cubit),
    );
  }

  Future<void> _editEncryptionKey(
    SyncSettingState syncSetting,
    GlobalSettingCubit cubit,
  ) async {
    final controller = TextEditingController(text: syncSetting.encryptionKey);
    final error = ValueNotifier<String?>(null);

    final result = await showCalmDialog<String>(
      context,
      title: t.settings.customEncryptionKey,
      subtitle: t.settings.customEncryptionKeySubtitle,
      icon: Icons.key_outlined,
      bodyBuilder: (dialogContext) => ValueListenableBuilder<String?>(
        valueListenable: error,
        builder: (context, errorText, _) => CalmTextField(
          controller: controller,
          hintText: t.settings.customEncryptionKeyHint,
          prefixIcon: Icons.vpn_key_outlined,
          obscureText: true,
          errorText: errorText,
          onChanged: (_) {
            if (error.value != null) error.value = null;
          },
        ),
      ),
      actionsBuilder: (dialogContext) => [
        CalmButton(
          label: t.common.cancel,
          variant: CalmButtonVariant.ghost,
          onPressed: () => Navigator.of(dialogContext).pop(),
        ),
        CalmButton(
          label: t.common.ok,
          variant: CalmButtonVariant.primary,
          onPressed: () {
            final raw = controller.text;
            // 旧密钥可能不满足新规则；原样不改时直接放行。
            if (raw == syncSetting.encryptionKey) {
              Navigator.of(dialogContext).pop(raw);
              return;
            }
            if (raw.isEmpty) {
              Navigator.of(dialogContext).pop(raw);
              return;
            }
            if (raw.contains(RegExp(r'\s'))) {
              error.value = t.settings.customEncryptionKeyNoSpaces;
              return;
            }
            if (raw.length < _syncKeyMinLength) {
              error.value = t.settings.customEncryptionKeyTooShort(
                min: _syncKeyMinLength,
              );
              return;
            }
            Navigator.of(dialogContext).pop(raw);
          },
        ),
      ],
    );
    controller.dispose();
    error.dispose();

    if (result == null || result == syncSetting.encryptionKey) {
      return;
    }
    cubit.updateSyncSetting(
      (current) => current.copyWith(encryptionKey: result),
    );
    showSuccessToast(t.settings.customEncryptionKeyChanged);
  }

  Widget _syncServiceType(GlobalSettingState state, GlobalSettingCubit cubit) {
    final syncServiceItems = <SyncServiceType, String>{
      SyncServiceType.none: t.settings.syncServiceNone,
      SyncServiceType.webdav: t.settings.syncServiceWebdav,
      SyncServiceType.s3: t.settings.syncServiceS3,
    };

    return CalmListTile(
      leading: settingTileIcon(Icons.storage_outlined),
      title: t.settings.syncService,
      subtitle: t.settings.syncServiceSubtitle,
      trailing: FluentDropdown<SyncServiceType>(
        value: state.syncSetting.syncServiceType,
        displayValue: syncServiceItems[state.syncSetting.syncServiceType]!,
        items: syncServiceItems,
        onChanged: (SyncServiceType value) {
          if (value == state.syncSetting.syncServiceType) return;
          cubit.updateSyncSetting(
            (current) => current.copyWith(
              syncServiceType: value,
              syncSettings: value == SyncServiceType.none
                  ? false
                  : current.syncSettings,
            ),
          );
        },
      ),
    );
  }

  Widget _autoSync(GlobalSettingState state, GlobalSettingCubit cubit) {
    return settingSwitchTile(
      icon: Icons.cloud_sync_outlined,
      title: t.settings.autoSync,
      subtitle: t.settings.autoSyncSubtitle,
      value: state.syncSetting.autoSync,
      onChanged: (bool value) {
        cubit.updateSyncSetting((current) => current.copyWith(autoSync: value));
        if (value) {
          eventBus.fire(NoticeSync());
        }
      },
    );
  }

  Widget _syncInterval(GlobalSettingState state, GlobalSettingCubit cubit) {
    final syncSetting = state.syncSetting;
    return settingActionTile(
      icon: Icons.timer_outlined,
      title: t.settings.syncInterval,
      subtitle: t.settings.syncIntervalSubtitle,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CalmBadge(
            label:
                '${syncSetting.syncInterval} ${syncSetting.syncIntervalUnit.label}',
            tone: CalmBadgeTone.tonal,
          ),
          const SizedBox(width: 6),
          Icon(
            Icons.chevron_right_rounded,
            size: 18,
            color: context.calm.text3,
          ),
        ],
      ),
      onTap: () => _editSyncInterval(syncSetting, cubit),
    );
  }

  Future<void> _editSyncInterval(
    SyncSettingState syncSetting,
    GlobalSettingCubit cubit,
  ) async {
    final controller = TextEditingController(
      text: syncSetting.syncInterval.toString(),
    );
    final error = ValueNotifier<String?>(null);
    var unit = syncSetting.syncIntervalUnit;

    final result = await showCalmDialog<({int value, SyncIntervalUnit unit})>(
      context,
      title: t.settings.syncInterval,
      subtitle: t.settings.syncIntervalSubtitle,
      icon: Icons.timer_outlined,
      bodyBuilder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ValueListenableBuilder<String?>(
              valueListenable: error,
              builder: (context, errorText, _) => CalmTextField(
                controller: controller,
                hintText: t.settings.syncIntervalValue,
                prefixIcon: Icons.timer_outlined,
                errorText: errorText,
                keyboardType: TextInputType.number,
                onChanged: (_) {
                  if (error.value != null) error.value = null;
                },
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Text(
                  t.settings.syncIntervalUnitLabel,
                  style: TextStyle(
                    fontSize: 12,
                    color: dialogContext.calm.text2,
                  ),
                ),
                const Spacer(),
                FluentDropdown<SyncIntervalUnit>(
                  value: unit,
                  displayValue: unit.label,
                  items: <SyncIntervalUnit, String>{
                    SyncIntervalUnit.second: t.settings.syncIntervalUnitSecond,
                    SyncIntervalUnit.minute: t.settings.syncIntervalUnitMinute,
                    SyncIntervalUnit.hour: t.settings.syncIntervalUnitHour,
                  },
                  onChanged: (value) {
                    setDialogState(() => unit = value);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
      actionsBuilder: (dialogContext) => [
        CalmButton(
          label: t.common.cancel,
          variant: CalmButtonVariant.ghost,
          onPressed: () => Navigator.of(dialogContext).pop(),
        ),
        CalmButton(
          label: t.common.ok,
          variant: CalmButtonVariant.primary,
          onPressed: () {
            final value = int.tryParse(controller.text.trim());
            if (value == null || value <= 0) {
              error.value = t.settings.syncIntervalInvalid;
              return;
            }
            Navigator.of(dialogContext).pop((value: value, unit: unit));
          },
        ),
      ],
    );
    controller.dispose();
    error.dispose();

    if (result == null) {
      return;
    }
    if (result.value == syncSetting.syncInterval &&
        result.unit == syncSetting.syncIntervalUnit) {
      return;
    }
    cubit.updateSyncSetting(
      (current) => current.copyWith(
        syncInterval: result.value,
        syncIntervalUnit: result.unit,
      ),
    );
    showSuccessToast(t.common.settingSaved);
  }

  Widget _syncNotify(GlobalSettingState state, GlobalSettingCubit cubit) {
    return settingSwitchTile(
      icon: Icons.notifications_active_outlined,
      title: t.settings.syncNotify,
      subtitle: t.settings.syncNotifySubtitle,
      value: state.syncSetting.syncNotify,
      onChanged: (bool value) {
        cubit.updateSyncSetting(
          (current) => current.copyWith(syncNotify: value),
        );
      },
    );
  }

  Widget _syncSettings(GlobalSettingState state, GlobalSettingCubit cubit) {
    return settingSwitchTile(
      icon: Icons.tune_outlined,
      title: t.settings.syncSettings,
      subtitle: t.settings.syncSettingsSubtitle,
      value: state.syncSetting.syncSettings,
      onChanged: (bool value) {
        cubit.updateSyncSetting(
          (current) => current.copyWith(syncSettings: value),
        );
      },
    );
  }

  Widget _syncPlugins(GlobalSettingState state, GlobalSettingCubit cubit) {
    return settingSwitchTile(
      icon: Icons.extension_outlined,
      title: t.settings.syncPlugins,
      subtitle: t.settings.syncPluginsSubtitle,
      value: state.syncSetting.syncPlugins,
      onChanged: (bool value) {
        cubit.updateSyncSetting(
          (current) => current.copyWith(syncPlugins: value),
        );
      },
    );
  }
}
