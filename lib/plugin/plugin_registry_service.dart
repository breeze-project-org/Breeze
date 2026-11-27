import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:zephyr/main.dart';
import 'package:zephyr/network/http/plugin/qjs_call_exception.dart';
import 'package:zephyr/object_box/model.dart';
import 'package:zephyr/page/bookshelf/service/comic_link_service.dart';
import 'package:zephyr/plugin/local_comic_plugin.dart';
import 'package:zephyr/plugin/models/plugin_runtime_state.dart';
import 'package:zephyr/plugin/plugin_bytecode_cache.dart';
import 'package:zephyr/plugin/plugin_runtime_manager.dart';
import 'package:zephyr/src/rust/api/qjs.dart';
import 'package:zephyr/src/rust/qjs.dart';
import 'package:zephyr/util/storage/get_path.dart';
import 'package:zephyr/util/json/json_value.dart';

export 'package:zephyr/plugin/models/plugin_runtime_state.dart';

class PluginRegistryService {
  PluginRegistryService._();

  static final PluginRegistryService I = PluginRegistryService._();

  static String _qjsCallErrorMessage(Object error) {
    if (error is QjsCallFailure) {
      return error.message;
    }
    return error.toString();
  }

  final Map<String, PluginRuntimeState> _states = {};
  final _streamController =
      StreamController<Map<String, PluginRuntimeState>>.broadcast();
  Stream<Map<String, PluginRuntimeState>> get stream =>
      _streamController.stream;

  Map<String, PluginRuntimeState> get snapshot => Map.unmodifiable(_states);

  final Set<String> _pluginInitDone = <String>{};

  /// init 已成功跑完的插件（内存态，重启后重新跑 init 恢复）。
  ///
  /// 与 [updateLoadResult] 的 lastLoadSuccess 独立：后者 getInfo 成功也会写，
  /// 不能表达“init 跑完”。安装/启用流程不等待本集合，只后台标记。
  final Set<String> _pluginInitOk = <String>{};

  bool isPluginInitOk(String uuid) => _pluginInitOk.contains(uuid);

  void _markInitOk(String uuid) {
    _pluginInitOk.add(uuid);
  }

  void _clearInitOk(String uuid) {
    _pluginInitOk.remove(uuid);
  }

  /// 已持久化的 getInfo JSON 内存镜像：启动/刷新时从 DB 全量载入。
  ///
  /// 数据库访问全部异步，但 getInfo 兜底读取在若干同步路径（如发现页
  /// 合并 DB 兜底）中被调用，因此这里缓存一份，写路径同步更新。
  final Map<String, String> _persistedInfoJson = {};
  final Map<String, Map<String, dynamic>> _pluginInfoCache = {};
  final _infoStreamController =
      StreamController<Map<String, Map<String, dynamic>>>.broadcast();
  final Map<String, String> _infoErrorCache = {};
  final _infoErrorStreamController =
      StreamController<Map<String, String>>.broadcast();

  /// getInfo 状态流：fetch 成功 / 缓存失效时广播，供全局 cubit 热切换。
  /// 只读快照走 [infoSnapshot]，订阅增量走本流。
  Stream<Map<String, Map<String, dynamic>>> get infoStream =>
      _infoStreamController.stream;

  Map<String, Map<String, dynamic>> get infoSnapshot =>
      Map.unmodifiable(_pluginInfoCache);

  /// getInfo 失败态：只保留最近一次错误，fetch 成功即清除。
  Stream<Map<String, String>> get infoErrorStream =>
      _infoErrorStreamController.stream;

  Map<String, String> get infoErrorSnapshot =>
      Map.unmodifiable(_infoErrorCache);

  PluginRuntimeState? getByUuid(String uuid) => _states[uuid];

  /// 同步读内存/DB 兜底的 getInfo（仅 service 内部与特殊路径使用）。
  ///
  /// UI 层一律订阅全局 cubit 的 infos/infoErrors 做热切换，
  /// 不再直接调本方法，避免状态不一致（插件更新后新功能不显示）。
  Map<String, dynamic>? getCachedPluginInfo(String uuid) {
    final cached = _pluginInfoCache[uuid];
    if (cached != null) {
      return cached;
    }
    final persisted = readPersistedGetInfoJson(uuid);
    if (persisted.isEmpty) {
      return null;
    }
    try {
      final decoded = requireJsonMap(jsonDecode(persisted));
      _pluginInfoCache[uuid] = decoded;
      return decoded;
    } catch (_) {
      return null;
    }
  }

  Future<void> init() async {
    await refreshFromDb();
  }

  Future<void> refreshFromDb() async {
    final list = await database.plugins.listInfos();
    _states
      ..clear()
      ..addEntries(list.map((item) => MapEntry(item.uuid, _toState(item))));
    _persistedInfoJson
      ..clear()
      ..addEntries(
        list.map((item) => MapEntry(item.uuid, item.getInfoJson.trim())),
      );
    _hydrateInfoCache(list);
    _emit();
  }

  /// 用数据库里的 `getInfoJson` 水合内存缓存，不执行任何插件脚本。
  ///
  /// 启动/同步后只需要展示插件基本信息，正常路径下 `getInfoJson` 在安装、
  /// 更新、启用时就已写好；只有历史数据缺失或损坏时才由
  /// [loadMissingPluginInfos] 补拉。
  void _hydrateInfoCache(List<PluginInfo> list) {
    _pluginInfoCache.clear();
    for (final item in list) {
      if (item.isDeleted) {
        continue;
      }
      final raw = item.getInfoJson.trim();
      if (raw.isEmpty) {
        continue;
      }
      try {
        final decoded = requireJsonMap(jsonDecode(raw));
        if (decoded.isEmpty) {
          continue;
        }
        _pluginInfoCache[item.uuid] = decoded;
      } catch (e, st) {
        logger.w('插件 getInfo 缓存解析失败: ${item.uuid}', error: e, stackTrace: st);
      }
    }

    final local = _states[kLocalComicPluginId];
    if (local != null && !local.isDeleted) {
      _pluginInfoCache[kLocalComicPluginId] = localComicPluginInfo();
    }

    var errorChanged = false;
    for (final uuid in _pluginInfoCache.keys) {
      if (_infoErrorCache.remove(uuid) != null) {
        errorChanged = true;
      }
    }
    if (errorChanged) {
      _infoErrorStreamController.add(infoErrorSnapshot);
    }
    _infoStreamController.add(infoSnapshot);
  }

  Future<void> reconcileAfterExternalSync({
    Map<String, PluginRuntimeState>? previousSnapshot,
    Set<String> changedScriptUuids = const <String>{},
  }) async {
    final previous = Map<String, PluginRuntimeState>.from(
      previousSnapshot ?? snapshot,
    );
    logger.d('[plugin-sync] reconcile_start previous=${previous.length}');

    await refreshFromDb();

    final current = snapshot;
    final affected = <String>{...previous.keys, ...current.keys}.where((uuid) {
      final before = previous[uuid];
      final after = current[uuid];
      if (before == null || after == null) {
        return true;
      }
      return before.version != after.version ||
          before.updatedAt != after.updatedAt ||
          changedScriptUuids.contains(uuid) ||
          before.isEnabled != after.isEnabled ||
          before.isDeleted != after.isDeleted ||
          before.debug != after.debug ||
          before.debugUrl != after.debugUrl;
    }).toList();
    logger.d(
      '[plugin-sync] reconcile_diff current=${current.length} '
      'affected=${affected.length} uuids=${affected.join(',')}',
    );

    var infoFallbackNeeded = false;
    for (final uuid in affected) {
      if (isLocalComicPluginId(uuid)) continue;
      _pluginInitDone.remove(uuid);
      _clearInitOk(uuid);

      // 禁用/删除的插件不会重建 runtime，也不该执行 getInfo；
      // 它们的基本信息保留 refreshFromDb 从 getInfoJson 水合的结果。
      if (current[uuid]?.isActive != true) {
        continue;
      }
      _dropInfoCache(uuid);

      final runtimeName = resolveRuntimeName(uuid);
      try {
        await PluginRuntimeManager.I.dropIfPresent(runtimeName);
      } catch (e, st) {
        logger.w('同步后清理插件 runtime 失败: $uuid', error: e, stackTrace: st);
      }
    }

    for (final uuid in affected) {
      if (isLocalComicPluginId(uuid)) continue;
      final plugin = current[uuid];
      if (plugin == null || !plugin.isActive) {
        continue;
      }

      final runtimeName = resolveRuntimeName(uuid);
      try {
        await ensurePluginRuntimeReady(plugin, runtimeName: runtimeName);
        await runPluginInitIfNeeded(plugin, runtimeName: runtimeName);
        // 脚本可能随同步变化，重建 runtime 后刷新一次 getInfo 并持久化。
        await fetchPluginInfo(uuid: plugin.uuid, runtimeName: runtimeName);
      } catch (e, st) {
        infoFallbackNeeded = true;
        logger.w('同步后重建插件 runtime 失败: $uuid', error: e, stackTrace: st);
      }
    }
    if (infoFallbackNeeded) {
      // 重建/刷新失败时回退到同步下发的 getInfoJson，至少保证基本信息可展示。
      _hydrateInfoCache(await database.plugins.listInfos());
    }
    logger.d(
      '[plugin-sync] reconcile_done active=${current.values.where((e) => e.isActive).length}',
    );
  }

  Future<void> initializeGlobalRuntime() async {
    const globalRuntimeName = 'global';
    final ready = await isQjsRuntimeInitialized(name: globalRuntimeName);
    if (!ready) {
      await buildQjsRuntime(
        request: const QjsRuntimeBuildRequest(
          runtimeName: globalRuntimeName,
          injectFilesystem: false,
        ),
      );
    }
  }

  Future<void>? _missingInfoLoad;

  /// 只给 DB 里没有可用 `getInfoJson` 的插件补拉 getInfo。
  ///
  /// 正常启动/同步路径直接读 DB 水合缓存；这里仅兜底历史版本安装的插件
  /// （`getInfoJson` 为空或损坏）。重复调用共享同一个 in-flight future，
  /// 避免 discover 页与启动流程同时拉同一批插件。
  Future<void> loadMissingPluginInfos() {
    final running = _missingInfoLoad;
    if (running != null) {
      return running;
    }
    final future = _loadMissingPluginInfos().whenComplete(() {
      _missingInfoLoad = null;
    });
    _missingInfoLoad = future;
    return future;
  }

  Future<void> _loadMissingPluginInfos() async {
    final plugins = _states.values
        .where(
          (item) => !item.isDeleted && !_pluginInfoCache.containsKey(item.uuid),
        )
        .toList();
    if (plugins.isEmpty) {
      return;
    }
    // 串行补拉：每个 fetchPluginInfo 都会 spawn DB worker isolate + QJS runtime，
    // 并发跑整批会和书架/首页的 isolate 抢 CPU 与数据库读。
    for (final plugin in plugins) {
      final runtimeName = resolveRuntimeName(plugin.uuid);
      try {
        await fetchPluginInfo(uuid: plugin.uuid, runtimeName: runtimeName);
      } catch (e) {
        logger.w('插件 getInfo 补拉失败: ${plugin.uuid}', error: e);
        await updateLoadResult(
          plugin.uuid,
          success: false,
          error: _qjsCallErrorMessage(e),
        );
      }
    }
  }

  Future<Map<String, dynamic>> fetchPluginInfo({
    required String uuid,
    required String runtimeName,
  }) async {
    final plugin = _states[uuid];
    if (plugin == null || plugin.isDeleted) {
      throw StateError('插件不可用: $uuid');
    }

    if (isLocalComicPluginId(uuid)) {
      final info = localComicPluginInfo();
      _pluginInfoCache[uuid] = info;
      _infoStreamController.add(infoSnapshot);
      if (_infoErrorCache.remove(uuid) != null) {
        _infoErrorStreamController.add(infoErrorSnapshot);
      }
      await updateLoadResult(uuid, success: true, error: null);
      return info;
    }

    final onceRuntimeName = 'plugin_info_${uuid.replaceAll('-', '_')}';
    Map<String, dynamic> decoded;
    try {
      // getInfo 预热也走常驻 runtime：字节码命中时不读完整脚本。
      await PluginRuntimeManager.I.install(
        pluginId: uuid,
        runtimeName: onceRuntimeName,
        pluginDebug: plugin.debug,
        loadSource: () => _resolveBundleJs(plugin),
      );
      final result = await qjsTaskCall(
        runtimeName: onceRuntimeName,
        source: uuid,
        taskGroupKey: '',
        isOnce: false,
        fnPath: 'getInfo',
        argsJson: '{}',
      );
      final raw = utf8.decode(result.bytes, allowMalformed: true);
      decoded = requireJsonMap(jsonDecode(raw));
    } catch (e) {
      _infoErrorCache[uuid] = _qjsCallErrorMessage(e);
      _infoErrorStreamController.add(infoErrorSnapshot);
      if (e is QjsCallFailure) {
        throw QjsCallException(source: e.source, message: e.message, cause: e);
      }
      rethrow;
    }
    _pluginInfoCache[uuid] = decoded;
    _infoStreamController.add(infoSnapshot);
    if (_infoErrorCache.remove(uuid) != null) {
      _infoErrorStreamController.add(infoErrorSnapshot);
    }
    await updateLoadResult(uuid, success: true, error: null);
    await persistGetInfoJson(uuid, jsonEncode(decoded));
    return decoded;
  }

  /// 持久化 getInfo JSON 字符串（不清理 runtime / 内存 cache）。
  Future<void> persistGetInfoJson(String uuid, String getInfoJson) async {
    final normalized = getInfoJson.trim();
    final found = await database.plugins.getInfoByUuid(uuid);
    if (found == null) {
      return;
    }
    if (found.getInfoJson == normalized) {
      _persistedInfoJson[uuid] = normalized;
      return;
    }
    found.getInfoJson = normalized;
    // 仅缓存元数据，不改 updatedAt，避免触发无意义的同步冲突。
    await database.plugins.putInfo(found);
    _persistedInfoJson[uuid] = normalized;
  }

  /// 读取已持久化的 getInfo JSON 字符串（内存镜像，[refreshFromDb] 载入）。
  String readPersistedGetInfoJson(String uuid) {
    return _persistedInfoJson[uuid]?.trim() ?? '';
  }

  List<PluginRuntimeState> activePlugins() {
    return _states.values
        .where((item) => item.isActive && !isLocalComicPluginId(item.uuid))
        .toList()
      ..sort((a, b) => a.insertedAt.compareTo(b.insertedAt));
  }

  /// 按用户自定义顺序返回插件；旧记录或新插件回退到安装时间。
  List<PluginRuntimeState> sortPlugins(Iterable<PluginRuntimeState> plugins) {
    final result = plugins.toList();
    result.sort(_comparePluginOrder);
    return result;
  }

  List<PluginRuntimeState> orderedPlugins({bool includeDeleted = false}) {
    return sortPlugins(
      _states.values.where(
        (plugin) =>
            !isLocalComicPluginId(plugin.uuid) &&
            (includeDeleted || !plugin.isDeleted),
      ),
    );
  }

  Future<void> reorderPlugins(List<String> orderedUuids) async {
    final visible = orderedPlugins();
    final visibleByUuid = <String, PluginRuntimeState>{
      for (final plugin in visible) plugin.uuid: plugin,
    };
    final normalizedUuids = <String>[];
    final seen = <String>{};
    for (final uuid in orderedUuids) {
      if (visibleByUuid.containsKey(uuid) && seen.add(uuid)) {
        normalizedUuids.add(uuid);
      }
    }
    for (final plugin in visible) {
      if (seen.add(plugin.uuid)) {
        normalizedUuids.add(plugin.uuid);
      }
    }

    final infos = await database.plugins.listInfos();
    final infoByUuid = <String, PluginInfo>{
      for (final info in infos)
        if (!info.isDeleted && info.uuid.trim().isNotEmpty) info.uuid: info,
    };
    final now = DateTime.now().toUtc();
    final changedInfos = <PluginInfo>[];
    for (var index = 0; index < normalizedUuids.length; index++) {
      final info = infoByUuid[normalizedUuids[index]];
      if (info == null || info.sortOrder == index) {
        continue;
      }
      info.sortOrder = index;
      info.updatedAt = now;
      changedInfos.add(info);
      _states[info.uuid] = _toState(info);
    }
    if (changedInfos.isEmpty) {
      return;
    }
    await database.plugins.putInfos(changedInfos);
    _emit();
  }

  Future<void> resetPluginOrder() async {
    final infos = (await database.plugins.listInfos())
        .where((info) => !info.isDeleted && info.sortOrder != null)
        .toList();
    if (infos.isEmpty) {
      return;
    }

    final now = DateTime.now().toUtc();
    for (final info in infos) {
      info.sortOrder = null;
      info.updatedAt = now;
      _states[info.uuid] = _toState(info);
    }
    await database.plugins.putInfos(infos);
    _emit();
  }

  List<PluginRuntimeState> updateCheckTargets() {
    return activePlugins();
  }

  Future<void> runForUpdateTargets(
    Future<void> Function(PluginRuntimeState plugin) task,
  ) async {
    final targets = updateCheckTargets();
    for (final plugin in targets) {
      await task(plugin);
    }
  }

  List<String> getEnabledUuids() {
    return _states.values
        .where(
          (item) =>
              item.isEnabled &&
              !item.isDeleted &&
              !isLocalComicPluginId(item.uuid),
        )
        .map((item) => item.uuid)
        .toList();
  }

  int getActivePluginCount() {
    return _states.values
        .where((item) => item.isActive && !isLocalComicPluginId(item.uuid))
        .length;
  }

  bool isAnyPluginEnabled() {
    return _states.values.any(
      (item) => item.isActive && !isLocalComicPluginId(item.uuid),
    );
  }

  List<PluginRuntimeState> getSortedActivePlugins() {
    return activePlugins();
  }

  Future<void> upsert(PluginInfo info) async {
    await database.plugins.putInfoWithScript(info);
    _persistedInfoJson[info.uuid] = info.getInfoJson.trim();
    _states[info.uuid] = _toState(info);
    _dropInfoCache(info.uuid);
    _pluginInitDone.remove(info.uuid);
    _clearInitOk(info.uuid);
    _emit();
  }

  Future<void> setEnabled(String uuid, bool enabled) async {
    final found = await database.plugins.getInfoByUuid(uuid);
    if (found == null) {
      return;
    }
    found.isEnabled = enabled;
    found.updatedAt = DateTime.now().toUtc();
    await database.plugins.putInfo(found);
    _states[uuid] = _toState(found);
    // 禁用不执行脚本，DB 里的 getInfo 仍然有效，保留缓存供列表展示；
    // 只有启用需要丢弃旧缓存并在 runtime 就绪后重新拉取。
    if (enabled) {
      _dropInfoCache(uuid);
    }
    _pluginInitDone.remove(uuid);
    _clearInitOk(uuid);
    _emit();
    final runtimeName = resolveRuntimeName(uuid);
    if (enabled) {
      await ensurePluginRuntimeReady(_states[uuid]!, runtimeName: runtimeName);
      await runPluginInitIfNeeded(_states[uuid]!, runtimeName: runtimeName);
      try {
        await fetchPluginInfo(uuid: uuid, runtimeName: runtimeName);
      } catch (e, st) {
        logger.w('启用插件后刷新 info 失败: $uuid', error: e, stackTrace: st);
      }
    } else {
      try {
        await PluginRuntimeManager.I.dropIfPresent(runtimeName);
      } catch (e, st) {
        logger.w('禁用插件时释放 runtime 失败: $uuid', error: e, stackTrace: st);
      }
    }
  }

  Future<void> updateLoadResult(
    String uuid, {
    required bool success,
    String? error,
  }) async {
    final found = await database.plugins.getInfoByUuid(uuid);
    if (found == null) {
      return;
    }
    found.lastLoadSuccess = success;
    found.lastLoadError = error;
    // 加载结果只是本机运行状态。不能刷新 updatedAt，否则同步会把
    // “这台设备加载得晚”当成元数据更新，覆盖其它设备的启停/排序等真实变更。
    await database.plugins.putInfo(found);
    _states[uuid] = _toState(found);
    _emit();
  }

  Future<void> updateDebugConfig(
    String uuid, {
    required bool debug,
    String? debugUrl,
  }) async {
    final found = await database.plugins.getInfoByUuid(uuid);
    if (found == null) {
      return;
    }
    found.debug = debug;
    found.debugUrl = debugUrl?.trim().isEmpty == true ? null : debugUrl?.trim();
    found.updatedAt = DateTime.now().toUtc();
    await database.plugins.putInfo(found);
    _states[uuid] = _toState(found);
    _pluginInitDone.remove(uuid);
    _clearInitOk(uuid);
    _emit();
    // 用 debug bundle / DB bundle 后台刷新 getInfo（内存 + getInfoJson），
    // 让详情页/书架/搜索的插件名跟上调试中的脚本；不阻塞返回，
    // 失败时保留旧名字（getCachedPluginInfo 会用 persisted getInfo 兜底）。
    unawaited(() async {
      try {
        await fetchPluginInfo(uuid: uuid, runtimeName: uuid);
      } catch (e, st) {
        logger.w('调试配置更新后刷新 getInfo 失败: $uuid', error: e, stackTrace: st);
      }
    }());
  }

  Future<void> deletePlugin(String uuid) async {
    if (isLocalComicPluginId(uuid)) {
      return;
    }
    final found = await database.plugins.getInfoByUuid(uuid);
    if (found == null) {
      throw StateError('插件不存在: $uuid');
    }

    final runtimeName = resolveRuntimeName(uuid);
    final infoRuntimeName = 'plugin_info_${uuid.replaceAll('-', '_')}';
    for (final name in <String>[runtimeName, infoRuntimeName]) {
      try {
        await PluginRuntimeManager.I.dropIfPresent(name);
      } catch (e, st) {
        logger.e(e, stackTrace: st);
        // runtime 失败不阻断删除主流程
      }
    }

    await PluginBytecodeCache.instance.delete(runtimeName);
    await _deletePluginDownloadFolders(uuid);
    await _deletePluginConfigs(uuid);
    await _deletePluginRelatedData(uuid);
    await _deletePluginDownloadTasks(uuid);

    final now = DateTime.now().toUtc();
    found
      ..originScript = ''
      ..isEnabled = false
      ..isDeleted = true
      ..deletedAt = now
      ..updatedAt = now
      ..lastLoadSuccess = false
      ..lastLoadError = null;
    // 空脚本会让 putInfoWithScript 在同一事务里删除 PluginScript 行。
    await database.plugins.putInfoWithScript(found);
    _states[uuid] = _toState(found);
    _dropInfoCache(uuid);
    _persistedInfoJson.remove(uuid);
    _pluginInitDone.remove(uuid);
    _clearInitOk(uuid);
    _emit();
  }

  Future<void> _deletePluginDownloadFolders(String uuid) async {
    final downloadRoot = await getDownloadPath();
    final root = p.join(downloadRoot, uuid);
    final directory = Directory(root);
    final exists = await directory.exists();
    if (!exists) {
      return;
    }
    try {
      await directory.delete(recursive: true);
    } catch (e) {
      throw StateError('删除下载目录失败: $root, error: $e');
    }
  }

  Future<void> _deletePluginRelatedData(String uuid) async {
    // 只按来源取键：getAll() 会把整张收藏/历史/下载表解码到 UI isolate，
    // 历史表上千行时删一次插件就卡掉一两百毫秒。
    final favoriteKeys = await database.favorites.listKeysBySource(uuid);
    final historyKeys = await database.histories.listKeysBySource(uuid);
    final downloadKeys = await database.downloads.listKeysBySource(uuid);

    // 收藏/历史属于同步数据，应当软删除（标记 deleted），让同步能把删除传播出去。
    for (final key in favoriteKeys) {
      await ComicLinkService.removeComicFromAll(key, ComicFolderType.favorite);
    }

    // 历史记录没有 ComicLink，只需要软删除本体。
    await database.histories.markDeletedByKeys(historyKeys);

    // 下载记录不参与同步，直接物理删除。
    for (final key in downloadKeys) {
      await ComicLinkService.removeComicFromAll(key, ComicFolderType.download);
    }
  }

  Future<void> _deletePluginDownloadTasks(String uuid) async {
    final tasks = await database.downloadTasks.getAll();
    final idsToDelete = tasks
        .where((task) => task.taskInfo?.from == uuid)
        .map((task) => task.id)
        .toList();
    if (idsToDelete.isNotEmpty) {
      await database.downloadTasks.removeByIds(idsToDelete);
    }
  }

  Future<void> _deletePluginConfigs(String uuid) async {
    final candidateNames = _buildPluginConfigNameCandidates(uuid);
    if (candidateNames.isEmpty) {
      return;
    }

    final configs = await database.plugins.listConfigs();
    final idsToDelete = configs
        .where((item) => candidateNames.contains(item.name.trim()))
        .map((item) => item.id)
        .toList();
    if (idsToDelete.isEmpty) {
      return;
    }
    await database.plugins.removeConfigByIds(idsToDelete);
  }

  Set<String> _buildPluginConfigNameCandidates(String uuid) {
    final candidates = <String>{};
    for (final raw in <String>{uuid, resolveRuntimeName(uuid)}) {
      for (final normalized in _normalizePluginNameCandidates(raw)) {
        candidates.add(normalized);
        candidates.add('($normalized)');
        final onceRuntime = 'plugin_info_${normalized.replaceAll('-', '_')}';
        candidates.add(onceRuntime);
        candidates.add('($onceRuntime)');
      }
    }
    return candidates.where((item) => item.trim().isNotEmpty).toSet();
  }

  Set<String> _normalizePluginNameCandidates(String raw) {
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

  String resolveRuntimeName(String uuid) {
    return uuid;
  }

  Future<void> ensurePluginRuntimeReady(
    PluginRuntimeState plugin, {
    required String runtimeName,
  }) async {
    await PluginRuntimeManager.I.install(
      pluginId: plugin.uuid,
      runtimeName: runtimeName,
      pluginDebug: plugin.debug,
      loadSource: () => _resolveBundleJs(plugin),
    );
    _pluginInitDone.remove(plugin.uuid);
    _clearInitOk(plugin.uuid);
  }

  Future<void> runPluginInitIfNeeded(
    PluginRuntimeState plugin, {
    required String runtimeName,
  }) async {
    if (_pluginInitDone.contains(plugin.uuid)) {
      return;
    }

    // init 不需要等待结果，触发后即返回，避免阻塞安装/启用流程。
    // 执行与去重由 PluginRuntimeManager 负责：成功（或未实现）才记
    // _pluginInitOk，失败不记，不阻塞、不抛。
    unawaited(() async {
      try {
        final outcome = await PluginRuntimeManager.I.ensureInit(
          pluginId: plugin.uuid,
          runtimeName: runtimeName,
        );
        if (!outcome.success) {
          await updateLoadResult(
            plugin.uuid,
            success: false,
            error: 'init 执行失败: ${outcome.error}',
          );
          logger.w('插件 init 执行失败: ${plugin.uuid}', error: outcome.error);
          return;
        }
        _pluginInitDone.add(plugin.uuid);
        _markInitOk(plugin.uuid);
        if (outcome.notImplemented) {
          logger.w('插件未实现 init，已跳过: ${plugin.uuid}');
          return;
        }
        await updateLoadResult(plugin.uuid, success: true, error: null);
      } catch (e) {
        logger.w('插件 init 异步执行失败: ${plugin.uuid}', error: e);
      }
    }());
  }

  Future<String> _resolveBundleJs(PluginRuntimeState plugin) async {
    if (plugin.debug && (plugin.debugUrl?.trim().isNotEmpty ?? false)) {
      try {
        final response = await fetchDirect(plugin.debugUrl!.trim());
        final debugBundle = response.text;
        if (debugBundle.trim().isNotEmpty) {
          logger.d('[plugin-bundle] source=debugUrl plugin=${plugin.uuid}');
          return debugBundle;
        }
        throw StateError('debug bundle 为空');
      } catch (e) {
        await updateLoadResult(
          plugin.uuid,
          success: false,
          error: 'debug bundle 拉取失败: $e',
        );
        logger.w('debug bundle 拉取失败，回退数据库: ${plugin.uuid}', error: e);
      }
    }

    final dbBundle = await _loadPluginBundleFromDb(plugin.uuid);
    if (dbBundle != null) {
      logger.d('[plugin-bundle] source=db plugin=${plugin.uuid}');
      return dbBundle;
    }

    throw StateError('bundle_js不能为空: ${plugin.uuid}');
  }

  Future<String?> _loadPluginBundleFromDb(String pluginId) async {
    final text = await database.plugins.getScriptByUuid(pluginId);
    if (text.trim().isEmpty) {
      return null;
    }
    return text;
  }

  PluginRuntimeState _toState(PluginInfo item) {
    return PluginRuntimeState(
      uuid: item.uuid,
      version: item.version,
      isEnabled: item.isEnabled,
      isDeleted: item.isDeleted,
      debug: item.debug,
      debugUrl: item.debugUrl,
      lastLoadSuccess: item.lastLoadSuccess,
      lastLoadError: item.lastLoadError,
      sortOrder: item.sortOrder,
      insertedAt: item.insertedAt,
      updatedAt: item.updatedAt,
      deletedAt: item.deletedAt,
    );
  }

  void _emit() {
    _streamController.add(snapshot);
  }

  /// 丢弃内存 info 缓存并广播：调用方重新按需拉取，订阅方热切换。
  void _dropInfoCache(String uuid) {
    var changed = _pluginInfoCache.remove(uuid) != null;
    if (_infoErrorCache.remove(uuid) != null) {
      changed = true;
      _infoErrorStreamController.add(infoErrorSnapshot);
    }
    if (changed) {
      _infoStreamController.add(infoSnapshot);
    }
  }

  int _comparePluginOrder(PluginRuntimeState a, PluginRuntimeState b) {
    final aOrder = a.sortOrder;
    final bOrder = b.sortOrder;
    if (aOrder != null && bOrder != null && aOrder != bOrder) {
      return aOrder.compareTo(bOrder);
    }
    if (aOrder != null && bOrder == null) {
      return -1;
    }
    if (aOrder == null && bOrder != null) {
      return 1;
    }

    final insertedCompare = a.insertedAt.compareTo(b.insertedAt);
    if (insertedCompare != 0) {
      return insertedCompare;
    }
    return a.uuid.compareTo(b.uuid);
  }
}
