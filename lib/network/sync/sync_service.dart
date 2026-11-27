import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/config/global/setting_updated_at.dart';
import 'package:zephyr/database/database.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/object_box/model.dart';
import 'package:zephyr/page/comic_follow/cubit/comic_follow_cubit.dart';
import 'package:zephyr/plugin/plugin_registry_service.dart';

import 'package:zephyr/network/sync/comic_sync_core.dart';
import 'package:zephyr/network/sync/plugin_sync_merge.dart';
import 'package:zephyr/network/sync/s3_sync_service.dart';
import 'package:zephyr/network/sync/settings_sync_payload.dart';
import 'package:zephyr/network/sync/webdav_sync_service.dart';
import 'package:zephyr/util/async/worker_pool.dart';
import 'package:zephyr/util/rust/rust_loader.dart';

const String _settingsSyncSchemaVersion = 'v3';
const String _settingsBlockMetaPrefsKey = 'sync.settings.block.meta.v3';

const String _appearanceBlockName = 'appearance';
const String _libraryBlockName = 'library';
const String _readerBlockName = 'reader';
const String _pluginsBlockName = 'plugins';

/// 旧版客户端认识的三个设置块；新版仍会生成，用于向后兼容。
const List<String> _legacySettingsBlockNames = <String>[
  _appearanceBlockName,
  _libraryBlockName,
  _readerBlockName,
];

bool isSyncServiceConfigured(GlobalSettingState state) {
  switch (state.syncSetting.syncServiceType) {
    case SyncServiceType.none:
      return false;
    case SyncServiceType.webdav:
      return WebDavSyncService.isConfigured(state);
    case SyncServiceType.s3:
      return S3SyncService.isConfigured(state);
  }
}

ComicSyncRemoteAdapter? createSyncAdapter(GlobalSettingState state) {
  if (!isSyncServiceConfigured(state)) {
    return null;
  }

  switch (state.syncSetting.syncServiceType) {
    case SyncServiceType.none:
      return null;
    case SyncServiceType.webdav:
      return WebDavSyncService(state);
    case SyncServiceType.s3:
      return S3SyncService(state);
  }
}

Future<void> autoSync(
  GlobalSettingState state, {
  GlobalSettingCubit? globalSettingCubit,
  ComicFollowCubit? comicFollowCubit,
}) async {
  final adapter = createSyncAdapter(state);
  if (adapter == null) {
    return;
  }

  await runComicSync(adapter, passphrase: state.syncSetting.encryptionKey);

  // 同步后重新加载追更列表，确保内存状态与数据库一致。
  await comicFollowCubit?.loadFromDatabase();

  if (!state.syncSetting.syncSettings && !state.syncSetting.syncPlugins) {
    logger.d('设置同步和插件同步均未启用，跳过配置同步');
    return;
  }

  await _syncSettings(
    adapter,
    globalSettingCubit: globalSettingCubit,
    currentGlobalSetting: state,
  );
}

/// 手动上传：漫画数据按本机覆盖云端；设置/插件按逐项同步逻辑合并后上传。
///
/// 包含漫画数据，以及开关已启用的设置 / 插件配置。
Future<void> manualUploadToCloud({
  required GlobalSettingState state,
  GlobalSettingCubit? globalSettingCubit,
  ComicFollowCubit? comicFollowCubit,
  bool forceOverwrite = false,
}) async {
  final adapter = createSyncAdapter(state);
  if (adapter == null) {
    throw StateError('未配置同步服务，请先选择并配置 WebDAV 或 S3');
  }

  final passphrase = state.syncSetting.encryptionKey;
  if (!forceOverwrite) {
    // 先确认现有云端数据能解密；失败时交给 UI 提示，不能静默覆盖。
    await ComicSyncCore.verifyRemoteComicDecryptable(
      adapter,
      passphrase: passphrase,
    );
    if (state.syncSetting.syncSettings || state.syncSetting.syncPlugins) {
      await _verifyRemoteSettingsDecryptable(adapter, passphrase: passphrase);
    }
  }

  await uploadComicData(adapter, passphrase: passphrase);
  if (state.syncSetting.syncSettings || state.syncSetting.syncPlugins) {
    await _syncSettings(
      adapter,
      globalSettingCubit: globalSettingCubit,
      currentGlobalSetting: state,
      overwriteRemote: forceOverwrite,
    );
  }

  // 同步后重新加载追更列表，确保内存状态与数据库一致。
  await comicFollowCubit?.loadFromDatabase();
}

/// 手动下载：漫画数据合并到本机；设置/插件按逐项同步逻辑应用较新值。
///
/// 包含漫画数据，以及开关已启用的设置 / 插件配置。
Future<void> manualDownloadFromCloud({
  required GlobalSettingState state,
  GlobalSettingCubit? globalSettingCubit,
  ComicFollowCubit? comicFollowCubit,
}) async {
  final adapter = createSyncAdapter(state);
  if (adapter == null) {
    throw StateError('未配置同步服务，请先选择并配置 WebDAV 或 S3');
  }

  await downloadComicData(adapter, passphrase: state.syncSetting.encryptionKey);
  if (state.syncSetting.syncSettings || state.syncSetting.syncPlugins) {
    await _syncSettings(
      adapter,
      globalSettingCubit: globalSettingCubit,
      currentGlobalSetting: state,
      uploadMerged: false,
      cleanupRemote: false,
    );
  }

  // 同步后重新加载追更列表，确保内存状态与数据库一致。
  await comicFollowCubit?.loadFromDatabase();
}

/// 只验证云端设置文件能否用当前密钥解密，不合并、不上传。
Future<void> _verifyRemoteSettingsDecryptable(
  ComicSyncRemoteAdapter adapter, {
  required String passphrase,
}) async {
  final allRemote = await adapter.listRemoteDataFiles();
  final syncRootFiles = allRemote.where(ComicSyncCore.isSyncRootPath).toList();
  final remoteMd5 = await _downloadRemoteText(
    adapter,
    _remoteSettingsMd5Path,
    returnEmptyIfMissing: true,
  );
  final remoteData = await _selectLatestRemoteSettingsData(
    adapter,
    syncRootFiles,
    remoteMd5,
  );
  if (remoteData == null) {
    return;
  }
  try {
    await _decodeSettingsPayload(
      remoteData.bytes,
      fallbackSyncTime: remoteData.timestamp,
      passphrase: passphrase,
    );
  } catch (_) {
    throw const SyncDecryptionException();
  }
}

Future<void> _syncSettings(
  ComicSyncRemoteAdapter adapter, {
  required GlobalSettingState currentGlobalSetting,
  GlobalSettingCubit? globalSettingCubit,
  bool uploadMerged = true,
  bool cleanupRemote = true,
  bool overwriteRemote = false,
}) async {
  final localGlobal = globalSettingCubit?.state ?? currentGlobalSetting;
  final passphrase = localGlobal.syncSetting.encryptionKey;
  final localSnapshot = await _buildLocalSettingsSnapshot(localGlobal);
  final localPayload = _buildSettingsPayload(localGlobal, localSnapshot);
  final localBytes = await ComicSyncCore.encodeEncryptedPayload(
    utf8.encode(jsonEncode(localPayload)),
    passphrase: passphrase,
  );
  final localMd5 = ComicSyncCore.calculateMd5(localBytes);

  if (overwriteRemote) {
    logger.d('[sync][settings] decision=overwrite reason=manual_force');
    await _uploadSettingsPayload(
      adapter,
      payloadBytes: localBytes,
      payloadMd5: localMd5,
      syncTime: localSnapshot.syncTime,
    );
    await _updateLocalSettingsSyncTime(
      localGlobal,
      syncTime: localSnapshot.syncTime,
      globalSettingCubit: globalSettingCubit,
    );
    if (cleanupRemote) {
      await _cleanupRemoteSettingsFiles(adapter);
    }
    return;
  }

  final allRemote = await adapter.listRemoteDataFiles();
  if (cleanupRemote) {
    final legacyFiles = allRemote
        .where(ComicSyncCore.isLegacyRemotePath)
        .toList();
    if (legacyFiles.isNotEmpty) {
      await adapter.deleteRemoteFiles(legacyFiles);
    }
  }
  final syncRootFiles = allRemote.where(ComicSyncCore.isSyncRootPath).toList();

  final remoteMd5 = await _downloadRemoteText(
    adapter,
    _remoteSettingsMd5Path,
    returnEmptyIfMissing: true,
  );

  logger.d(
    '[sync][settings] precheck localTime=${localSnapshot.syncTime} '
    'localMd5=$localMd5 remoteMd5=$remoteMd5 remoteFiles=${syncRootFiles.length}',
  );

  if (remoteMd5.isNotEmpty && remoteMd5 == localMd5) {
    logger.d('[sync][settings] decision=skip reason=md5_equal');
    if (cleanupRemote) {
      await _cleanupRemoteSettingsFiles(adapter);
    }
    await _updateLocalSettingsSyncTime(
      localGlobal,
      syncTime: localSnapshot.syncTime,
      globalSettingCubit: globalSettingCubit,
    );
    return;
  }

  final remoteData = await _selectLatestRemoteSettingsData(
    adapter,
    syncRootFiles,
    remoteMd5,
  );

  if (remoteMd5.isEmpty || remoteData == null) {
    if (!uploadMerged) {
      logger.d('[sync][settings] decision=skip reason=remote_missing');
      return;
    }
    logger.d('[sync][settings] decision=upload reason=remote_missing');
    await _uploadSettingsPayload(
      adapter,
      payloadBytes: localBytes,
      payloadMd5: localMd5,
      syncTime: localSnapshot.syncTime,
    );
    await _updateLocalSettingsSyncTime(
      localGlobal,
      syncTime: localSnapshot.syncTime,
      globalSettingCubit: globalSettingCubit,
    );
    if (cleanupRemote) {
      await _cleanupRemoteSettingsFiles(adapter);
    }
    return;
  }

  final remoteSnapshot = await _decodeSettingsPayload(
    remoteData.bytes,
    fallbackSyncTime: remoteData.timestamp,
    passphrase: passphrase,
  );
  final mergeResult = await _mergeSettingsSnapshots(
    localGlobal,
    localSnapshot,
    remoteSnapshot,
  );

  logger.d(
    '[sync][settings] compare localTime=${localSnapshot.syncTime} '
    'remoteTime=${remoteSnapshot.syncTime} mergedTime=${mergeResult.syncTime} '
    'localMd5=$localMd5 remoteMd5=$remoteMd5',
  );

  if (mergeResult.shouldApplyLocalState) {
    logger.d('[sync][settings] decision=apply_remote_blocks');
    await _applyMergedGlobalState(
      mergeResult.mergedState,
      globalSettingCubit: globalSettingCubit,
    );
  } else {
    await _updateLocalSettingsSyncTime(
      localGlobal,
      syncTime: mergeResult.syncTime,
      globalSettingCubit: globalSettingCubit,
    );
  }

  if (mergeResult.shouldApplyPluginData) {
    await _applyPluginBlockData(mergeResult.pluginBlockData);
  }

  await _persistLocalSettingsBlockMeta(mergeResult.localBlockMeta);

  if (!uploadMerged) {
    logger.d('[sync][settings] decision=skip_upload reason=download_only');
    return;
  }

  final mergedPayload = _buildSettingsPayload(
    mergeResult.mergedState,
    mergeResult.mergedSnapshot,
  );
  final mergedBytes = await ComicSyncCore.encodeEncryptedPayload(
    utf8.encode(jsonEncode(mergedPayload)),
    passphrase: passphrase,
  );
  final mergedMd5 = ComicSyncCore.calculateMd5(mergedBytes);

  if (mergedMd5 != remoteMd5) {
    logger.d('[sync][settings] decision=upload reason=merged_snapshot_changed');
    await _uploadSettingsPayload(
      adapter,
      payloadBytes: mergedBytes,
      payloadMd5: mergedMd5,
      syncTime: mergeResult.syncTime,
    );
  } else {
    logger.d(
      '[sync][settings] decision=skip_upload reason=merged_snapshot_equals_remote',
    );
  }

  if (cleanupRemote) {
    await _cleanupRemoteSettingsFiles(adapter);
  }
}

Map<String, dynamic> _buildSettingsPayload(
  GlobalSettingState globalSetting,
  _SettingsSnapshot snapshot,
) {
  final globalSettingJson = globalSetting.toJson();
  globalSettingJson.remove(settingUpdatedAtJsonKey);
  removeSettingPaths(globalSettingJson, localOnlySettingPaths);

  final pluginBlock = snapshot.blocks[_pluginsBlockName];
  final pluginConfigs = pluginBlock == null
      ? <Map<String, dynamic>>[]
      : _toJsonMapList(pluginBlock.data['pluginConfigs']);
  final pluginInfos = pluginBlock == null
      ? <Map<String, dynamic>>[]
      : _toJsonMapList(pluginBlock.data['pluginInfos']);

  return {
    'version': syncDataVersion,
    'schemaVersion': _settingsSyncSchemaVersion,
    'syncTime': snapshot.syncTime,
    'globalSetting': globalSettingJson,
    'settingItems': {
      for (final entry in snapshot.items.entries)
        entry.key: entry.value.toJson(),
    },
    'pluginConfigs': pluginConfigs,
    'pluginInfos': pluginInfos,
    'blocks': {
      for (final entry in snapshot.blocks.entries)
        entry.key: entry.value.toJson(),
    },
  };
}

Future<_SettingsSnapshot> _buildLocalSettingsSnapshot(
  GlobalSettingState globalSetting,
) async {
  final existingMeta = await _loadLocalSettingsBlockMeta();
  final nextMeta = Map<String, _LocalSettingsBlockMeta>.from(existingMeta);
  final blockPayloads = <String, _SettingsBlockPayload>{};
  final items = <String, SyncedSettingItem>{};
  final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;
  final baseTimestamp = globalSetting.syncSetting.settingsSyncTime > 0
      ? globalSetting.syncSetting.settingsSyncTime
      : 0;

  if (globalSetting.syncSetting.syncSettings) {
    final syncableData = extractSyncableSettingsData(globalSetting.toJson());
    final itemUpdatedAt = _buildLocalSettingItemUpdatedAt(
      state: globalSetting,
      data: syncableData,
      existingMeta: existingMeta,
    );
    items.addAll(
      buildSyncedSettingItems(
        data: syncableData,
        updatedAtByPath: itemUpdatedAt,
      ),
    );

    final legacyBlocks = _buildLegacySettingsBlocks(
      globalSetting,
      items: items,
    );
    for (final entry in legacyBlocks.entries) {
      blockPayloads[entry.key] = entry.value;
      nextMeta[entry.key] = _LocalSettingsBlockMeta.fromBlock(entry.value);
    }
  }

  if (globalSetting.syncSetting.syncPlugins) {
    final pluginData = await _buildPluginBlockData();
    final hash = _calculateStructuredMd5(pluginData);
    final previous = existingMeta[_pluginsBlockName];
    final pluginBaseTimestamp = _derivePluginBlockTimestamp(
      pluginData,
      fallback: baseTimestamp,
    );
    final updatedAt = previous == null
        ? pluginBaseTimestamp
        : previous.hash == hash
        ? _normalizeTimestamp(previous.updatedAt, fallback: pluginBaseTimestamp)
        : nowMs;
    final pluginBlock = _SettingsBlockPayload(
      name: _pluginsBlockName,
      updatedAt: updatedAt,
      fieldUpdatedAt: const <String, int>{},
      data: pluginData,
    );
    blockPayloads[_pluginsBlockName] = pluginBlock;
    nextMeta[_pluginsBlockName] = _LocalSettingsBlockMeta.fromBlock(
      pluginBlock,
    );
    logger.d(
      '[sync][plugins] local_snapshot '
      'count=${_toJsonMapList(pluginData['pluginInfos']).length} '
      'hash=$hash baseTs=$pluginBaseTimestamp finalTs=$updatedAt '
      'prevTs=${previous?.updatedAt ?? 0}',
    );
  }

  await _persistLocalSettingsBlockMeta(nextMeta);
  return _SettingsSnapshot(items: items, blocks: blockPayloads);
}

/// 优先使用 `GlobalSettingState.settingUpdatedAt`；旧版本没有逐项时间时，
/// 旧三块里的字段回退到上次同步的块时间，其余字段回退到上次同步时间；
/// 从未同步过则为 0 基准，仍然参与比较。
Map<String, int> _buildLocalSettingItemUpdatedAt({
  required GlobalSettingState state,
  required Map<String, dynamic> data,
  required Map<String, _LocalSettingsBlockMeta> existingMeta,
}) {
  final legacyBlockByPath = _legacyBlockByPath(state);
  final result = <String, int>{};
  for (final path in flattenSettingJson(data).keys) {
    final explicit = state.settingUpdatedAt[path] ?? 0;
    if (explicit > 0) {
      result[path] = explicit;
      continue;
    }
    final blockName = legacyBlockByPath[path];
    final meta = blockName == null ? null : existingMeta[blockName];
    final blockTime = meta == null
        ? 0
        : _normalizeTimestamp(meta.updatedAt, fallback: 0);
    final baseline = state.syncSetting.settingsSyncTime;
    result[path] = blockTime > 0 ? blockTime : (baseline > 0 ? baseline : 0);
  }
  return result;
}

Map<String, String> _legacyBlockByPath(GlobalSettingState state) {
  final blocks = _extractSyncableSettingsBlocks(state);
  final result = <String, String>{};
  for (final entry in blocks.entries) {
    final prefix = _settingsBlockPathPrefix(entry.key);
    for (final path in flattenSettingJson(entry.value).keys) {
      final statePath = prefix.isEmpty ? path : '$prefix.$path';
      result[statePath] = entry.key;
    }
  }
  return result;
}

/// 用逐项设置生成旧版三个块。
///
/// 旧客户端只认识 appearance / library / reader；这些块必须反映逐项合并
/// 后的状态，但块时间只由块内字段的时间决定，不会被无关字段抬高。
Map<String, _SettingsBlockPayload> _buildLegacySettingsBlocks(
  GlobalSettingState state, {
  required Map<String, SyncedSettingItem> items,
}) {
  final blocks = _extractSyncableSettingsBlocks(state);
  final result = <String, _SettingsBlockPayload>{};
  for (final entry in blocks.entries) {
    final blockName = entry.key;
    final data = entry.value;
    final prefix = _settingsBlockPathPrefix(blockName);
    final fieldUpdatedAt = <String, int>{};
    for (final path in flattenSettingJson(data).keys) {
      final statePath = prefix.isEmpty ? path : '$prefix.$path';
      fieldUpdatedAt[path] = items[statePath]?.updatedAt ?? 0;
    }
    final updatedAt = _resolveBlockUpdatedAt(fieldUpdatedAt, fallback: 0);
    result[blockName] = _SettingsBlockPayload(
      name: blockName,
      updatedAt: updatedAt,
      fieldUpdatedAt: fieldUpdatedAt,
      data: data,
    );
  }
  return result;
}

Future<_SettingsSnapshot> _decodeSettingsPayload(
  List<int> payloadBytes, {
  required int fallbackSyncTime,
  String passphrase = '',
}) async {
  final raw = await ComicSyncCore.decodeEncryptedPayload(
    payloadBytes,
    passphrase: passphrase,
  );
  final payloadRaw = jsonDecode(utf8.decode(raw));
  return _snapshotFromPayload(
    _toJsonMap(payloadRaw),
    fallbackSyncTime: fallbackSyncTime,
  );
}

_SettingsSnapshot _snapshotFromPayload(
  Map<String, dynamic> payload, {
  required int fallbackSyncTime,
}) {
  final blocksJson = _toJsonMap(payload['blocks']);
  final remoteSyncTime = _extractSyncTimeFromPayload(
    payload,
    fallbackFromFileName: fallbackSyncTime,
  );
  final blocks = <String, _SettingsBlockPayload>{};
  var items = parseSyncedSettingItems(
    payload[settingItemsPayloadKey],
    fallbackUpdatedAt: remoteSyncTime,
  );

  for (final entry in blocksJson.entries) {
    final blockJson = _toJsonMap(entry.value);
    final data = _toJsonMap(blockJson['data']);
    if (data.isEmpty) {
      continue;
    }
    final blockUpdatedAt = _normalizeTimestamp(
      int.tryParse(blockJson['updatedAt']?.toString() ?? ''),
      fallback: remoteSyncTime,
    );
    blocks[entry.key] = _SettingsBlockPayload(
      name: entry.key,
      updatedAt: blockUpdatedAt,
      fieldUpdatedAt: entry.key == _pluginsBlockName
          ? const <String, int>{}
          : settingTimestampsFromPayload(
              blockData: data,
              rawFieldUpdatedAt: blockJson['fieldUpdatedAt'],
              blockUpdatedAt: blockUpdatedAt,
            ),
      data: data,
    );
  }

  if (blocks.isEmpty) {
    final globalSettingJson = _toJsonMap(payload['globalSetting']);
    if (globalSettingJson.isNotEmpty) {
      final remoteGlobal = GlobalSettingState.fromJson(globalSettingJson);
      final legacyBlocks = _extractSyncableSettingsBlocks(remoteGlobal);
      for (final entry in legacyBlocks.entries) {
        blocks[entry.key] = _SettingsBlockPayload(
          name: entry.key,
          updatedAt: remoteSyncTime,
          fieldUpdatedAt: settingTimestampsForBlock(
            settingUpdatedAt: const <String, int>{},
            blockData: entry.value,
            pathPrefix: _settingsBlockPathPrefix(entry.key),
            fallback: remoteSyncTime,
          ),
          data: entry.value,
        );
      }
    }
  }

  if (items.isEmpty) {
    items = _synthesizeSyncedSettingItems(
      payload: payload,
      blocks: blocks,
      remoteSyncTime: remoteSyncTime,
    );
  }

  if (!blocks.containsKey(_pluginsBlockName)) {
    final pluginConfigs = _toJsonMapList(payload['pluginConfigs']);
    final pluginInfos = _toJsonMapList(payload['pluginInfos']);
    if (pluginConfigs.isNotEmpty || pluginInfos.isNotEmpty) {
      blocks[_pluginsBlockName] = _SettingsBlockPayload(
        name: _pluginsBlockName,
        updatedAt: remoteSyncTime,
        fieldUpdatedAt: const <String, int>{},
        data: {'pluginConfigs': pluginConfigs, 'pluginInfos': pluginInfos},
      );
    }
  }

  return _SettingsSnapshot(items: items, blocks: blocks);
}

/// 旧负载没有 `settingItems` 时，从 globalSetting + 旧版三个块合成逐项记录。
///
/// 只有旧版设置块（或完全没有块的远古负载）才合成；只有插件块时不能
/// 把对方的 globalSetting 当成“开启了设置同步”。
Map<String, SyncedSettingItem> _synthesizeSyncedSettingItems({
  required Map<String, dynamic> payload,
  required Map<String, _SettingsBlockPayload> blocks,
  required int remoteSyncTime,
}) {
  final hasLegacySettingsBlock = _legacySettingsBlockNames.any(
    blocks.containsKey,
  );
  if (!hasLegacySettingsBlock && blocks.isNotEmpty) {
    return <String, SyncedSettingItem>{};
  }

  final globalSettingJson = _toJsonMap(payload['globalSetting']);
  if (!hasLegacySettingsBlock && globalSettingJson.isEmpty) {
    return <String, SyncedSettingItem>{};
  }

  final fullData = globalSettingJson.isEmpty
      ? <String, dynamic>{}
      : extractSyncableSettingsData(globalSettingJson);
  for (final blockName in _legacySettingsBlockNames) {
    final block = blocks[blockName];
    if (block == null) {
      continue;
    }
    if (blockName == _readerBlockName) {
      fullData['readSetting'] = block.data;
    } else {
      fullData.addAll(block.data);
    }
  }
  if (fullData.isEmpty) {
    return <String, SyncedSettingItem>{};
  }

  final legacyTimestamps = <String, int>{};
  for (final blockName in _legacySettingsBlockNames) {
    final block = blocks[blockName];
    if (block == null) {
      continue;
    }
    final prefix = _settingsBlockPathPrefix(blockName);
    for (final entry in block.fieldUpdatedAt.entries) {
      final statePath = prefix.isEmpty ? entry.key : '$prefix.${entry.key}';
      final existing = legacyTimestamps[statePath] ?? 0;
      if (entry.value > existing) {
        legacyTimestamps[statePath] = entry.value;
      }
    }
  }

  final explicitTimestamps = <String, int>{};
  final rawTimestamps = _toJsonMap(globalSettingJson[settingUpdatedAtJsonKey]);
  for (final entry in rawTimestamps.entries) {
    final timestamp = int.tryParse(entry.value?.toString() ?? '') ?? 0;
    if (timestamp > 0) {
      explicitTimestamps[entry.key] = timestamp;
    }
  }

  final itemUpdatedAt = <String, int>{};
  for (final path in flattenSettingJson(fullData).keys) {
    itemUpdatedAt[path] = _normalizeTimestamp(
      legacyTimestamps[path] ?? explicitTimestamps[path],
      fallback: remoteSyncTime,
    );
  }
  return buildSyncedSettingItems(
    data: fullData,
    updatedAtByPath: itemUpdatedAt,
  );
}

Future<_SettingsMergeResult> _mergeSettingsSnapshots(
  GlobalSettingState localGlobal,
  _SettingsSnapshot localSnapshot,
  _SettingsSnapshot remoteSnapshot,
) async {
  final mergedBlocks = <String, _SettingsBlockPayload>{};
  final mergedItems = <String, SyncedSettingItem>{};
  final localBlockMeta = await _loadLocalSettingsBlockMeta();
  final nextMeta = Map<String, _LocalSettingsBlockMeta>.from(localBlockMeta);
  var shouldApplyLocalState = false;

  if (localGlobal.syncSetting.syncSettings) {
    mergedItems.addAll(
      mergeSyncedSettingItems(localSnapshot.items, remoteSnapshot.items),
    );
    shouldApplyLocalState = settingItemsDiffer(
      localSnapshot.items,
      mergedItems,
    );

    final mergedStateForLegacy = _applySettingItemsToState(
      localGlobal,
      mergedItems,
    );
    final legacyBlocks = _buildLegacySettingsBlocks(
      mergedStateForLegacy,
      items: mergedItems,
    );
    for (final entry in legacyBlocks.entries) {
      mergedBlocks[entry.key] = entry.value;
      nextMeta[entry.key] = _LocalSettingsBlockMeta.fromBlock(entry.value);
    }
  } else {
    // 本地关闭设置同步时，云端逐项设置只保留在负载中，不应用到本机。
    mergedItems.addAll(remoteSnapshot.items);
    for (final blockName in _legacySettingsBlockNames) {
      final remoteBlock = remoteSnapshot.blocks[blockName];
      if (remoteBlock != null) {
        mergedBlocks[blockName] = remoteBlock;
      }
    }
  }

  Map<String, dynamic> pluginBlockData = const <String, dynamic>{};
  var shouldApplyPluginData = false;

  final localPluginBlock = localSnapshot.blocks[_pluginsBlockName];
  final remotePluginBlock = remoteSnapshot.blocks[_pluginsBlockName];

  if (localGlobal.syncSetting.syncPlugins) {
    final mergedPluginBlock = _mergePluginBlocks(
      localPluginBlock,
      remotePluginBlock,
    );
    final decision = mergedPluginBlock == null
        ? 'none'
        : (localPluginBlock != null &&
              mergedPluginBlock.contentMd5 == localPluginBlock.contentMd5)
        ? 'local_or_merged_local'
        : (remotePluginBlock != null &&
              mergedPluginBlock.contentMd5 == remotePluginBlock.contentMd5)
        ? 'remote_or_merged_remote'
        : 'merged_union';
    logger.d(
      '[sync][plugins] merge '
      'localCount=${_pluginBlockCount(localPluginBlock)} '
      'localTs=${localPluginBlock?.updatedAt ?? 0} '
      'localHash=${localPluginBlock?.contentMd5 ?? ''} '
      'remoteCount=${_pluginBlockCount(remotePluginBlock)} '
      'remoteTs=${remotePluginBlock?.updatedAt ?? 0} '
      'remoteHash=${remotePluginBlock?.contentMd5 ?? ''} '
      'decision=$decision',
    );
    if (mergedPluginBlock != null) {
      mergedBlocks[_pluginsBlockName] = mergedPluginBlock;
      nextMeta[_pluginsBlockName] = _LocalSettingsBlockMeta.fromBlock(
        mergedPluginBlock,
      );
      pluginBlockData = mergedPluginBlock.data;
      if (!_sameBlock(localPluginBlock, mergedPluginBlock)) {
        shouldApplyPluginData = true;
      }
    }
  } else if (remotePluginBlock != null) {
    mergedBlocks[_pluginsBlockName] = remotePluginBlock;
    logger.d(
      '[sync][plugins] merge skipped_apply '
      'reason=local_sync_disabled remoteCount=${_pluginBlockCount(remotePluginBlock)} '
      'remoteTs=${remotePluginBlock.updatedAt}',
    );
  }

  var mergedSyncTime = localGlobal.syncSetting.syncSettings
      ? maxSyncedItemUpdatedAt(mergedItems)
      : 0;
  final pluginBlock = mergedBlocks[_pluginsBlockName];
  if (localGlobal.syncSetting.syncPlugins &&
      pluginBlock != null &&
      pluginBlock.updatedAt > mergedSyncTime) {
    mergedSyncTime = pluginBlock.updatedAt;
  }

  final mergedStateBase = localGlobal.syncSetting.syncSettings
      ? _applySettingItemsToState(localGlobal, mergedItems)
      : localGlobal;
  final mergedState = mergedStateBase.copyWith(
    syncSetting: localGlobal.syncSetting.copyWith(
      settingsSyncTime: mergedSyncTime,
    ),
  );

  return _SettingsMergeResult(
    mergedState: mergedState,
    mergedSnapshot: _SettingsSnapshot(items: mergedItems, blocks: mergedBlocks),
    syncTime: mergedSyncTime,
    shouldApplyLocalState: shouldApplyLocalState,
    shouldApplyPluginData: shouldApplyPluginData,
    pluginBlockData: pluginBlockData,
    localBlockMeta: nextMeta,
  );
}

Map<String, Map<String, dynamic>> _extractSyncableSettingsBlocks(
  GlobalSettingState state,
) {
  final json = _materializeJsonMap(state.toJson());
  return <String, Map<String, dynamic>>{
    _appearanceBlockName: <String, dynamic>{
      'dynamicColor': json['dynamicColor'],
      'themeMode': json['themeMode'],
      'isAMOLED': json['isAMOLED'],
      'seedColor': json['seedColor'],
      'locale': json['locale'],
      'showPluginHome': json['showPluginHome'],
      'showPluginCloudFavorite': json['showPluginCloudFavorite'],
      'welcomePageNum': json['welcomePageNum'],
    },
    _libraryBlockName: <String, dynamic>{
      'maskedKeywords': json['maskedKeywords'],
      'maskedCommentKeywords': json['maskedCommentKeywords'],
      'comicChoice': json['comicChoice'],
      'disableBika': json['disableBika'],
      'updateAccelerate': json['updateAccelerate'],
      'retryDownloadUntilSuccess': json['retryDownloadUntilSuccess'],
      'searchHistory': json['searchHistory'],
    },
    _readerBlockName: _toJsonMap(json['readSetting']),
  };
}

Future<Map<String, dynamic>> _buildPluginBlockData() {
  final handle = database.db.handle;
  return runInIsolate(buildPluginBlockDataInWorker, handle);
}

/// 后台 isolate 内组装插件同步块：`with-scripts` 查询与逐条 `toJson` 都不占 UI。
Future<Map<String, dynamic>> buildPluginBlockDataInWorker(int handle) async {
  await initRustLib();
  final db = Database.fromHandle(handle);
  // 同步负载必须带脚本，只有这条路径使用 with-scripts 查询。
  final infos = await db.plugins.listInfosWithScripts();
  final configs = await db.plugins.listConfigs();

  final deletedUuids = infos
      .where((item) => item.isDeleted)
      .map((item) => item.uuid.trim())
      .where((uuid) => uuid.isNotEmpty)
      .toSet();
  final blockedConfigNames = <String>{
    for (final uuid in deletedUuids)
      ..._buildPluginConfigNameCandidatesForSync(uuid),
  };

  final pluginConfigs = configs
      .map((item) {
        final name = item.name.trim();
        if (name.isEmpty || blockedConfigNames.contains(name)) {
          return <String, dynamic>{};
        }
        final json = item.toJson();
        json.remove('id');
        json['name'] = name;
        return json;
      })
      .where((item) => item.isNotEmpty)
      .toList();
  pluginConfigs.sort((a, b) {
    final aName = a['name']?.toString() ?? '';
    final bName = b['name']?.toString() ?? '';
    return aName.compareTo(bName);
  });

  final pluginInfos = infos.where((item) => !item.isDeleted).map((item) {
    final json = item.toJson();
    json.remove('id');
    return json;
  }).toList();
  pluginInfos.sort((a, b) {
    final aKey = '${a['uuid'] ?? ''}:${a['version'] ?? ''}';
    final bKey = '${b['uuid'] ?? ''}:${b['version'] ?? ''}';
    return aKey.compareTo(bKey);
  });

  return {'pluginConfigs': pluginConfigs, 'pluginInfos': pluginInfos};
}

GlobalSettingState _applySettingItemsToState(
  GlobalSettingState localState,
  Map<String, SyncedSettingItem> items, {
  bool keepNewerLocalTimestamps = true,
}) {
  final json = _materializeJsonMap(localState.toJson());
  applySyncedSettingItems(
    json,
    items,
    keepNewerLocalTimestamps: keepNewerLocalTimestamps,
  );

  // 本地专属字段不在 items 中，这里再兜底一次，避免旧负载把它们带回来。
  final merged = GlobalSettingState.fromJson(json);
  return merged.copyWith(
    syncSetting: localState.syncSetting,
    customExportPath: localState.customExportPath,
    appLockSetting: localState.appLockSetting,
    cacheSetting: localState.cacheSetting,
    enableMemoryDebug: localState.enableMemoryDebug,
    blockRustHttpRequests: localState.blockRustHttpRequests,
    logAddress: localState.logAddress,
    windowWidth: localState.windowWidth,
    windowHeight: localState.windowHeight,
    windowX: localState.windowX,
    windowY: localState.windowY,
    forceEnableImpeller: localState.forceEnableImpeller,
    androidKeepAliveEnabled: localState.androidKeepAliveEnabled,
    compatibleVersion: localState.compatibleVersion,
    themeInitState: localState.themeInitState,
    needCleanCache: localState.needCleanCache,
  );
}

Future<void> _applyMergedGlobalState(
  GlobalSettingState value, {
  required GlobalSettingCubit? globalSettingCubit,
}) async {
  if (globalSettingCubit != null) {
    globalSettingCubit.applySyncedState(value);
    return;
  }

  final user = await database.userSettings.getOrCreate();
  user.globalSetting = value;
  await database.userSettings.put(user);
}

/// 应用云端插件块：冲突判定、脚本合并与写回都在 worker 池内完成。
///
/// 只有注册表快照与 reconcile 留在 UI isolate——[PluginRegistryService] 是
/// 进程级单例，worker 里拿不到同一份状态。
Future<void> _applyPluginBlockData(Map<String, dynamic> pluginBlockData) async {
  final previousSnapshot = PluginRegistryService.I.snapshot;
  final result = await runInWorker(
    () => applyPluginBlockDataInWorker(
      PluginBlockApplyTask(
        handle: database.db.handle,
        pluginBlockData: pluginBlockData,
      ),
    ),
  );
  for (final warning in result.warnings) {
    logger.w('[sync][plugins] $warning');
  }
  logger.d(
    '[sync][plugins] apply_remote '
    'incomingInfos=${result.incomingInfos} incomingConfigs=${result.incomingConfigs} '
    'previousRegistry=${previousSnapshot.length}',
  );
  logger.d(
    '[sync][plugins] apply_remote_db '
    'upsertInfos=${result.upsertedInfos} totalLocalInfos=${result.totalLocalInfos} '
    'savedConfigs=${result.savedConfigs} '
    'skippedDeletedLocal=${result.skippedDeletedLocal} '
    'skippedBlockedConfig=${result.skippedBlockedConfig}',
  );

  await PluginRegistryService.I.reconcileAfterExternalSync(
    previousSnapshot: previousSnapshot,
    changedScriptUuids: result.changedScriptUuids.toSet(),
  );
}

class PluginBlockApplyTask {
  const PluginBlockApplyTask({
    required this.handle,
    required this.pluginBlockData,
  });

  final int handle;
  final Map<String, dynamic> pluginBlockData;
}

/// worker 池内应用到数据库后的统计；UI 侧只负责日志与注册表 reconcile。
class PluginBlockApplyResult {
  const PluginBlockApplyResult({
    required this.incomingInfos,
    required this.incomingConfigs,
    required this.upsertedInfos,
    required this.totalLocalInfos,
    required this.savedConfigs,
    required this.skippedDeletedLocal,
    required this.skippedBlockedConfig,
    required this.changedScriptUuids,
    required this.warnings,
  });

  final int incomingInfos;
  final int incomingConfigs;
  final int upsertedInfos;
  final int totalLocalInfos;
  final int savedConfigs;
  final int skippedDeletedLocal;
  final int skippedBlockedConfig;
  final List<String> changedScriptUuids;
  final List<String> warnings;
}

Future<PluginBlockApplyResult> applyPluginBlockDataInWorker(
  PluginBlockApplyTask task,
) async {
  await initRustLib();
  final db = Database.fromHandle(task.handle);
  final pluginBlockData = task.pluginBlockData;
  final pluginConfigJsonList = _toJsonMapList(pluginBlockData['pluginConfigs']);
  final pluginInfoJsonList = _toJsonMapList(pluginBlockData['pluginInfos']);
  final warnings = <String>[];

  // 冲突判定与写回都需要脚本，sync apply 是少数确实需要脚本的路径。
  final localPluginInfos = await db.plugins.listInfosWithScripts();
  final localPluginByUuid = <String, PluginInfo>{
    for (final item in localPluginInfos)
      if (item.uuid.trim().isNotEmpty) item.uuid.trim(): item,
  };
  final localDeletedUuids = localPluginByUuid.values
      .where((item) => item.isDeleted)
      .map((item) => item.uuid.trim())
      .where((uuid) => uuid.isNotEmpty)
      .toSet();

  final remotePluginEntries = <({String uuid, Map<String, dynamic> json})>[];
  for (final json in pluginInfoJsonList) {
    try {
      final parsed = PluginInfo.fromJson(json);
      final uuid = parsed.uuid.trim();
      if (uuid.isEmpty || parsed.isDeleted) {
        continue;
      }
      final normalized = parsed.toJson()
        ..remove('id')
        ..['uuid'] = uuid;
      remotePluginEntries.add((uuid: uuid, json: normalized));
    } catch (e) {
      warnings.add('忽略无效插件信息: $e');
    }
  }

  final infoUpserts = <PluginInfo>[];
  final changedScriptUuids = <String>{};
  var skippedDeletedLocal = 0;
  for (final remote in remotePluginEntries) {
    final uuid = remote.uuid;
    if (localDeletedUuids.contains(uuid)) {
      skippedDeletedLocal++;
      continue;
    }
    final existing = localPluginByUuid[uuid];
    final existingJson = existing == null
        ? null
        : (existing.toJson()..remove('id'));
    final resolvedJson = resolvePluginInfoForApply(existingJson, remote.json);
    final resolved = PluginInfo.fromJson(<String, dynamic>{
      ...resolvedJson,
      'id': existing?.id ?? 0,
    });
    final resolvedNormalized = resolved.toJson()..remove('id');
    if (existingJson != null &&
        samePluginInfoJson(existingJson, resolvedNormalized)) {
      continue;
    }
    if (existing == null || existing.originScript != resolved.originScript) {
      changedScriptUuids.add(uuid);
    }
    infoUpserts.add(resolved);
    localPluginByUuid[uuid] = resolved;
  }
  if (infoUpserts.isNotEmpty) {
    await db.plugins.putInfosWithScripts(infoUpserts);
  }

  final blockedConfigNames = <String>{
    for (final uuid in localDeletedUuids)
      ..._buildPluginConfigNameCandidatesForSync(uuid),
  };
  final existingConfigs = await db.plugins.listConfigs();
  final blockedConfigIds = <int>[];
  final localConfigByName = <String, PluginConfig>{
    for (final item in existingConfigs)
      if (item.name.trim().isNotEmpty &&
          !blockedConfigNames.contains(item.name.trim()))
        item.name.trim(): PluginConfig(
          id: item.id,
          name: item.name.trim(),
          config: item.config,
        ),
  };
  for (final item in existingConfigs) {
    final name = item.name.trim();
    if (name.isNotEmpty && blockedConfigNames.contains(name)) {
      blockedConfigIds.add(item.id);
    }
  }
  if (blockedConfigIds.isNotEmpty) {
    await db.plugins.removeConfigByIds(blockedConfigIds);
  }
  var skippedBlockedConfig = 0;
  for (final json in pluginConfigJsonList) {
    try {
      final parsed = PluginConfig.fromJson(json);
      final name = parsed.name.trim();
      if (name.isEmpty) {
        continue;
      }
      if (blockedConfigNames.contains(name)) {
        skippedBlockedConfig++;
        continue;
      }
      final existing = localConfigByName[name];
      localConfigByName[name] = PluginConfig(
        id: existing?.id ?? 0,
        name: name,
        config: parsed.config,
      );
    } catch (e) {
      warnings.add('忽略无效插件配置: $e');
    }
  }
  if (localConfigByName.isNotEmpty) {
    await db.plugins.putConfigs(localConfigByName.values.toList());
  }

  return PluginBlockApplyResult(
    incomingInfos: pluginInfoJsonList.length,
    incomingConfigs: pluginConfigJsonList.length,
    upsertedInfos: infoUpserts.length,
    totalLocalInfos: localPluginByUuid.length,
    savedConfigs: localConfigByName.length,
    skippedDeletedLocal: skippedDeletedLocal,
    skippedBlockedConfig: skippedBlockedConfig,
    changedScriptUuids: changedScriptUuids.toList(),
    warnings: warnings,
  );
}

Future<Map<String, _LocalSettingsBlockMeta>>
_loadLocalSettingsBlockMeta() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(_settingsBlockMetaPrefsKey);
  if (raw == null || raw.trim().isEmpty) {
    return <String, _LocalSettingsBlockMeta>{};
  }

  try {
    final json = _toJsonMap(jsonDecode(raw));
    return json.map(
      (key, value) =>
          MapEntry(key, _LocalSettingsBlockMeta.fromJson(_toJsonMap(value))),
    );
  } catch (e) {
    logger.w('[sync][settings] 本地块元数据读取失败，已忽略: $e');
    return <String, _LocalSettingsBlockMeta>{};
  }
}

Future<void> _persistLocalSettingsBlockMeta(
  Map<String, _LocalSettingsBlockMeta> nextMeta,
) async {
  final prefs = await SharedPreferences.getInstance();
  final payload = {
    for (final entry in nextMeta.entries) entry.key: entry.value.toJson(),
  };
  await prefs.setString(_settingsBlockMetaPrefsKey, jsonEncode(payload));
}

Future<void> _updateLocalSettingsSyncTime(
  GlobalSettingState localGlobal, {
  required int syncTime,
  required GlobalSettingCubit? globalSettingCubit,
}) async {
  final merged = localGlobal.copyWith(
    syncSetting: localGlobal.syncSetting.copyWith(settingsSyncTime: syncTime),
  );
  if (globalSettingCubit != null) {
    globalSettingCubit.applySyncedState(merged);
  } else {
    final user = await database.userSettings.getOrCreate();
    user.globalSetting = merged;
    await database.userSettings.put(user);
  }
}

Future<void> _uploadSettingsPayload(
  ComicSyncRemoteAdapter adapter, {
  required List<int> payloadBytes,
  required String payloadMd5,
  required int syncTime,
}) async {
  final fileName = ComicSyncCore.buildSettingsDataFileName(syncTime);
  await adapter.uploadRemoteFile(fileName, payloadBytes);
  await adapter.uploadRemoteFile(
    _remoteSettingsMd5Path,
    utf8.encode(payloadMd5),
    contentType: 'text/plain; charset=utf-8',
  );
  logger.d('[sync][settings] uploaded file=$fileName md5=$payloadMd5');
}

Future<void> _cleanupRemoteSettingsFiles(ComicSyncRemoteAdapter adapter) async {
  final allRemote = await adapter.listRemoteDataFiles();

  final legacyFiles = allRemote
      .where(ComicSyncCore.isLegacyRemotePath)
      .toList();
  if (legacyFiles.isNotEmpty) {
    await adapter.deleteRemoteFiles(legacyFiles);
  }

  final syncRootFiles = allRemote.where(ComicSyncCore.isSyncRootPath).toList();
  final settingsFiles = syncRootFiles.where((path) {
    final fileName = ComicSyncCore.extractFileName(path);
    return ComicSyncCore.isSettingsDataFileName(fileName);
  }).toList();
  final sorted = ComicSyncCore.sortSettingsFilesByTimestampDesc(settingsFiles);

  final keep = <String>{
    '${ComicSyncCore.syncRemoteRootName}/${ComicSyncCore.settingsMd5FileName}',
  };
  for (var i = 0; i < sorted.length; i++) {
    if (i < 3) {
      keep.add(ComicSyncCore.normalizeRemotePathNoLeadingSlash(sorted[i]));
    }
  }

  final stale = settingsFiles.where((path) {
    final normalized = ComicSyncCore.normalizeRemotePathNoLeadingSlash(path);
    return !keep.contains(normalized);
  }).toList();
  if (stale.isNotEmpty) {
    await adapter.deleteRemoteFiles(stale);
  }
}

Future<_RemoteSettingsData?> _selectLatestRemoteSettingsData(
  ComicSyncRemoteAdapter adapter,
  List<String> remotePaths,
  String remoteMd5,
) async {
  final sorted = ComicSyncCore.sortSettingsFilesByTimestampDesc(remotePaths);
  if (sorted.isEmpty || remoteMd5.isEmpty) {
    return null;
  }

  for (final path in sorted) {
    try {
      final bytes = await adapter.downloadRemoteFile(path);
      final md5 = ComicSyncCore.calculateMd5(bytes);
      if (md5 == remoteMd5) {
        return _RemoteSettingsData(
          bytes: bytes,
          timestamp:
              ComicSyncCore.extractSettingsTimestampFromRemotePath(path) ?? 0,
        );
      }
    } catch (e) {
      logger.w('远端设置文件读取失败，尝试更旧版本: $path, error: $e');
    }
  }

  return null;
}

int _extractSyncTimeFromPayload(
  Map<String, dynamic> payload, {
  required int fallbackFromFileName,
}) {
  final syncTime = int.tryParse(payload['syncTime']?.toString() ?? '') ?? 0;
  if (syncTime > 0) {
    return syncTime;
  }
  return fallbackFromFileName;
}

Future<String> _downloadRemoteText(
  ComicSyncRemoteAdapter adapter,
  String remotePath, {
  bool returnEmptyIfMissing = false,
}) async {
  final bytes = await _downloadRemoteBytes(
    adapter,
    remotePath,
    returnEmptyIfMissing: returnEmptyIfMissing,
  );
  if (bytes.isEmpty) {
    return '';
  }
  return utf8.decode(bytes).trim();
}

Future<List<int>> _downloadRemoteBytes(
  ComicSyncRemoteAdapter adapter,
  String remotePath, {
  bool returnEmptyIfMissing = false,
}) async {
  try {
    return await adapter.downloadRemoteFile(remotePath);
  } catch (e) {
    if (returnEmptyIfMissing && _isNotFoundError(e)) {
      return const [];
    }
    rethrow;
  }
}

bool _isNotFoundError(Object error) {
  final message = error.toString();
  final lower = message.toLowerCase();
  return message.contains('404') ||
      message.contains('NoSuchKey') ||
      message.contains('NoSuchObject') ||
      message.contains('NotFound') ||
      lower.contains('does not exist') ||
      lower.contains('specified key') ||
      lower.contains('no such key');
}

Map<String, dynamic> _toJsonMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return Map<String, dynamic>.from(value);
  }
  if (value is Map) {
    return value.map((key, val) => MapEntry(key.toString(), val));
  }
  return <String, dynamic>{};
}

List<Map<String, dynamic>> _toJsonMapList(Object? value) {
  final raw = (value as List? ?? const []);
  return raw
      .map((item) {
        if (item is Map<String, dynamic>) {
          return Map<String, dynamic>.from(item);
        }
        if (item is Map) {
          return item.map((key, val) => MapEntry(key.toString(), val));
        }
        return <String, dynamic>{};
      })
      .where((item) => item.isNotEmpty)
      .toList();
}

Map<String, dynamic> _materializeJsonMap(Map<String, dynamic> value) {
  return _toJsonMap(jsonDecode(jsonEncode(value)));
}

String _calculateStructuredMd5(Map<String, dynamic> data) {
  return ComicSyncCore.calculateMd5(utf8.encode(jsonEncode(data)));
}

int _derivePluginBlockTimestamp(
  Map<String, dynamic> pluginData, {
  required int fallback,
}) {
  final pluginInfos = _toJsonMapList(pluginData['pluginInfos']);
  var latest = 0;

  for (final item in pluginInfos) {
    final updatedAt = DateTime.tryParse(item['updatedAt']?.toString() ?? '');
    final insertedAt = DateTime.tryParse(item['insertedAt']?.toString() ?? '');
    final candidate = [
      updatedAt?.toUtc().millisecondsSinceEpoch ?? 0,
      insertedAt?.toUtc().millisecondsSinceEpoch ?? 0,
    ].fold<int>(0, (current, value) => value > current ? value : current);
    if (candidate > latest) {
      latest = candidate;
    }
  }

  return latest > 0 ? latest : fallback;
}

int _pluginBlockCount(_SettingsBlockPayload? block) {
  if (block == null) {
    return 0;
  }
  return _toJsonMapList(block.data['pluginInfos']).length;
}

_SettingsBlockPayload? _mergePluginBlocks(
  _SettingsBlockPayload? localBlock,
  _SettingsBlockPayload? remoteBlock,
) {
  if (localBlock == null) {
    return remoteBlock;
  }
  if (remoteBlock == null) {
    return localBlock;
  }
  if (_sameBlock(localBlock, remoteBlock)) {
    return localBlock;
  }

  final preferRemoteOnConflict = remoteBlock.updatedAt > localBlock.updatedAt;
  final mergedData = mergePluginBlockData(
    localBlock.data,
    remoteBlock.data,
    preferRemoteOnConflict: preferRemoteOnConflict,
  );
  final mergedMd5 = _calculateStructuredMd5(mergedData);
  if (mergedMd5 == localBlock.contentMd5) {
    return localBlock;
  }
  if (mergedMd5 == remoteBlock.contentMd5) {
    return remoteBlock;
  }

  return _SettingsBlockPayload(
    name: _pluginsBlockName,
    updatedAt: localBlock.updatedAt >= remoteBlock.updatedAt
        ? localBlock.updatedAt
        : remoteBlock.updatedAt,
    fieldUpdatedAt: const <String, int>{},
    data: mergedData,
  );
}

Set<String> _buildPluginConfigNameCandidatesForSync(String uuid) {
  final candidates = <String>{};
  for (final raw in <String>{uuid.trim()}) {
    for (final normalized in _normalizePluginNameCandidatesForSync(raw)) {
      candidates.add(normalized);
      candidates.add('($normalized)');
      final onceRuntime = 'plugin_info_${normalized.replaceAll('-', '_')}';
      candidates.add(onceRuntime);
      candidates.add('($onceRuntime)');
    }
  }
  return candidates.where((item) => item.trim().isNotEmpty).toSet();
}

Set<String> _normalizePluginNameCandidatesForSync(String raw) {
  final names = <String>{};
  var value = raw.trim();
  if (value.isEmpty) {
    return names;
  }
  names.add(value);

  while (value.length >= 2 && value.startsWith('(') && value.endsWith(')')) {
    value = value.substring(1, value.length - 1).trim();
    if (value.isEmpty) {
      break;
    }
    names.add(value);
  }

  return names;
}

String _settingsBlockPathPrefix(String blockName) {
  return blockName == _readerBlockName ? 'readSetting' : '';
}

int _resolveBlockUpdatedAt(
  Map<String, int> fieldUpdatedAt, {
  required int fallback,
}) {
  var result = fallback;
  for (final timestamp in fieldUpdatedAt.values) {
    if (timestamp > result) {
      result = timestamp;
    }
  }
  return result;
}

bool _sameBlock(_SettingsBlockPayload? a, _SettingsBlockPayload? b) {
  if (a == null || b == null) {
    return a == b;
  }
  return a.contentMd5 == b.contentMd5;
}

int _normalizeTimestamp(int? timestamp, {required int fallback}) {
  if (timestamp != null && timestamp > 0) {
    return timestamp;
  }
  return fallback;
}

/// 测试入口：完整执行一次“本地快照 + 远端负载解析 + 逐项合并 + 组装上传负载”。
@visibleForTesting
Future<({GlobalSettingState mergedState, Map<String, dynamic> payload})>
mergeSyncSettingsForTest({
  required GlobalSettingState local,
  required Map<String, dynamic> remotePayload,
  required int remoteFallbackSyncTime,
}) async {
  final localSnapshot = await _buildLocalSettingsSnapshot(local);
  final remoteSnapshot = _snapshotFromPayload(
    remotePayload,
    fallbackSyncTime: remoteFallbackSyncTime,
  );
  final result = await _mergeSettingsSnapshots(
    local,
    localSnapshot,
    remoteSnapshot,
  );
  return (
    mergedState: result.mergedState,
    payload: _buildSettingsPayload(result.mergedState, result.mergedSnapshot),
  );
}

String get _remoteSettingsMd5Path =>
    '${ComicSyncCore.syncRemoteRootName}/${ComicSyncCore.settingsMd5FileName}';

class _SettingsSnapshot {
  const _SettingsSnapshot({required this.items, required this.blocks});

  final Map<String, SyncedSettingItem> items;
  final Map<String, _SettingsBlockPayload> blocks;

  int get syncTime {
    var result = maxSyncedItemUpdatedAt(items);
    for (final block in blocks.values) {
      if (block.updatedAt > result) {
        result = block.updatedAt;
      }
    }
    return result;
  }
}

class _SettingsBlockPayload {
  _SettingsBlockPayload({
    required this.name,
    required this.updatedAt,
    required this.fieldUpdatedAt,
    required this.data,
  }) : contentMd5 = _calculateStructuredMd5(data);

  final String name;
  final int updatedAt;
  final Map<String, int> fieldUpdatedAt;
  final Map<String, dynamic> data;
  final String contentMd5;

  Map<String, dynamic> toJson() {
    return {
      'updatedAt': updatedAt,
      if (fieldUpdatedAt.isNotEmpty) 'fieldUpdatedAt': fieldUpdatedAt,
      'data': data,
    };
  }
}

class _LocalSettingsBlockMeta {
  const _LocalSettingsBlockMeta({required this.updatedAt, required this.hash});

  factory _LocalSettingsBlockMeta.fromBlock(_SettingsBlockPayload block) {
    return _LocalSettingsBlockMeta(
      updatedAt: block.updatedAt,
      hash: block.contentMd5,
    );
  }

  factory _LocalSettingsBlockMeta.fromJson(Map<String, dynamic> json) {
    return _LocalSettingsBlockMeta(
      updatedAt: int.tryParse(json['updatedAt']?.toString() ?? '') ?? 0,
      hash: json['hash']?.toString() ?? '',
    );
  }

  final int updatedAt;
  final String hash;

  Map<String, dynamic> toJson() {
    return {'updatedAt': updatedAt, 'hash': hash};
  }
}

class _SettingsMergeResult {
  const _SettingsMergeResult({
    required this.mergedState,
    required this.mergedSnapshot,
    required this.syncTime,
    required this.shouldApplyLocalState,
    required this.shouldApplyPluginData,
    required this.pluginBlockData,
    required this.localBlockMeta,
  });

  final GlobalSettingState mergedState;
  final _SettingsSnapshot mergedSnapshot;
  final int syncTime;
  final bool shouldApplyLocalState;
  final bool shouldApplyPluginData;
  final Map<String, dynamic> pluginBlockData;
  final Map<String, _LocalSettingsBlockMeta> localBlockMeta;
}

class _RemoteSettingsData {
  const _RemoteSettingsData({required this.bytes, required this.timestamp});

  final List<int> bytes;
  final int timestamp;
}
