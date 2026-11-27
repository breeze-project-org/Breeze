import 'package:uuid/uuid.dart';
import 'package:zephyr/database/database.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/network/sync/sync_device_id.dart';
import 'package:zephyr/object_box/model.dart';
import 'package:zephyr/object_box/model_json_codec.dart';
import 'package:zephyr/main.dart';

const String kComicFolderRootPath = '';

class ComicFolderService {
  static String get _deviceId => syncDeviceId;

  static String get _newSyncId => const Uuid().v4();

  /// 根据路径获取文件夹的 syncId，根目录返回 null。
  ///
  /// [includeDeleted] 为 true 时也会查找已被软删除的文件夹，
  /// 用于在删除后清理其下的链接等场景。
  static Future<String?> folderSyncIdByPath(
    String? path,
    ComicFolderType type, {
    bool includeDeleted = false,
    Database? db,
  }) async {
    if (path == null || path.isEmpty) return null;
    final target = db ?? database;
    final folder = await target.folders.getByUniqueKey(
      await _uniqueKey(path, type, db: target),
    );
    if (folder == null) return null;
    if (!includeDeleted && folder.deletedAt != null) return null;
    return folder.syncId;
  }

  /// 根据文件夹的 parentSyncId 链计算其显示路径（如 /a/b）。
  static String folderPath(
    ComicFolder folder, {
    required Map<String, ComicFolder> syncIdMap,
  }) {
    final parts = <String>[];
    final visited = <String>{};
    ComicFolder? current = folder;
    while (current != null) {
      if (current.syncId.isNotEmpty && !visited.add(current.syncId)) break;
      parts.add(current.name);
      final parentId = current.parentSyncId;
      if (parentId == null || parentId.isEmpty) break;
      current = syncIdMap[parentId];
    }
    return '/${parts.reversed.join('/')}'; // single folder => /name
  }

  static String _folderPath(String parentPath, String name) {
    final safeName = name.trim();
    if (parentPath == kComicFolderRootPath) {
      return '/$safeName';
    }
    return '$parentPath/$safeName';
  }

  static Future<String> _uniqueKey(
    String path,
    ComicFolderType type, {
    Database? db,
  }) async {
    final parentPath = _parentPath(path);
    final parentSyncId = parentPath == kComicFolderRootPath
        ? ''
        : (await folderSyncIdByPath(parentPath, type, db: db) ?? '');
    final name = path == kComicFolderRootPath ? '' : path.split('/').last;
    return '$parentSyncId|$name|${type.name}';
  }

  static Future<String?> _parentSyncIdByPath(
    String? parentPath,
    ComicFolderType type, {
    Database? db,
  }) async {
    if (parentPath == null || parentPath.isEmpty) return null;
    return folderSyncIdByPath(parentPath, type, db: db);
  }

  static String _parentPath(String path) {
    if (path == kComicFolderRootPath) return kComicFolderRootPath;
    final trimmed = path.endsWith('/')
        ? path.substring(0, path.length - 1)
        : path;
    final index = trimmed.lastIndexOf('/');
    if (index <= 0) return kComicFolderRootPath;
    return trimmed.substring(0, index);
  }

  static Map<String, int> _bumpVersionVector(Map<String, int> vector) {
    return bumpVersionVector(vector, _deviceId);
  }

  static int _now() {
    return DateTime.now().toUtc().millisecondsSinceEpoch;
  }

  /// 列出当前路径下的直接子文件夹
  static Future<List<ComicFolder>> listChildFolders(
    String parentPath,
    ComicFolderType type, {
    bool sortAscending = false,
    Database? db,
  }) async {
    final parentSyncId = await _parentSyncIdByPath(parentPath, type, db: db);
    return (db ?? database).folders.listActiveChildren(
      parentSyncId,
      type.name,
      ascending: sortAscending,
    );
  }

  /// 列出该类型下所有未删除的文件夹（不区分层级）
  static Future<List<ComicFolder>> listAllFolders(
    ComicFolderType type, {
    bool sortAscending = false,
  }) {
    return database.folders.listActiveByType(
      type.name,
      ascending: sortAscending,
    );
  }

  /// 获取文件夹名称
  static Future<String?> folderName(String path, ComicFolderType type) async {
    if (path == kComicFolderRootPath) return null;
    final folder = await database.folders.getByUniqueKey(
      await _uniqueKey(path, type),
    );
    return folder?.name;
  }

  /// 创建文件夹
  static Future<ComicFolder> createFolder(
    String parentPath,
    String name,
    ComicFolderType type,
  ) async {
    final safeName = name.trim();
    if (safeName.isEmpty) {
      throw ArgumentError(t.bookshelf.folderNameEmpty);
    }
    if (safeName.contains('/')) {
      throw ArgumentError(t.bookshelf.folderNameSlash);
    }

    final parentSyncId = await _parentSyncIdByPath(parentPath, type);
    final uniqueKey = '${parentSyncId ?? ''}|$safeName|${type.name}';

    final existed = await database.folders.getByUniqueKey(uniqueKey);
    if (existed != null) {
      if (existed.deletedAt != null) {
        //  Tombstone 复活
        final now = _now();
        existed
          ..name = safeName
          ..deletedAt = null
          ..coverComicUniqueKey = null
          ..createdAt = now
          ..updatedAt = now
          ..versionVector = _bumpVersionVector(existed.versionVector);
        await database.folders.put(existed);
        return existed;
      }
      throw StateError(t.bookshelf.folderNameExists);
    }

    final now = _now();
    final folder = ComicFolder(
      syncId: _newSyncId,
      parentSyncId: parentSyncId,
      uniqueKey: uniqueKey,
      name: safeName,
      typeData: type.name,
      versionVector: {_deviceId: 1},
      createdAt: now,
      updatedAt: now,
    );
    await database.folders.put(folder);
    return folder;
  }

  /// 软删除文件夹及其下所有子文件夹
  static Future<void> deleteFolder(String path, ComicFolderType type) async {
    if (path == kComicFolderRootPath) return;
    final now = _now();

    final folder = await database.folders.getByUniqueKey(
      await _uniqueKey(path, type),
    );
    if (folder == null || folder.deletedAt != null) return;

    folder
      ..deletedAt = now
      ..updatedAt = now
      ..versionVector = _bumpVersionVector(folder.versionVector);
    await database.folders.put(folder);

    // 级联删除子文件夹（软删除）
    final subtreeSyncIds = await _collectSubtreeSyncIds(folder.syncId, type);
    subtreeSyncIds.remove(folder.syncId);
    if (subtreeSyncIds.isEmpty) return;

    final children = await database.folders.listBySyncIds(
      subtreeSyncIds.toList(),
    );
    final changed = <ComicFolder>[];
    for (final child in children) {
      if (child.deletedAt != null) continue;
      child
        ..deletedAt = now
        ..updatedAt = now
        ..versionVector = _bumpVersionVector(child.versionVector);
      changed.add(child);
    }
    if (changed.isNotEmpty) {
      await database.folders.putMany(changed);
    }
  }

  /// 设置文件夹封面漫画；null / 空表示恢复自动封面。
  static Future<void> setFolderCover(
    ComicFolder folder,
    String? comicUniqueKey,
  ) async {
    if (folder.deletedAt != null) return;
    final normalized = comicUniqueKey?.trim();
    final next = normalized == null || normalized.isEmpty ? null : normalized;
    if ((folder.coverComicUniqueKey ?? '') == (next ?? '')) return;

    final now = _now();
    folder
      ..coverComicUniqueKey = next
      ..updatedAt = now
      ..versionVector = _bumpVersionVector(folder.versionVector);
    await database.folders.put(folder);
  }

  /// 重命名文件夹
  static Future<void> renameFolder(
    String path,
    String newName,
    ComicFolderType type,
  ) async {
    final safeName = newName.trim();
    if (path == kComicFolderRootPath || safeName.isEmpty) return;
    if (safeName.contains('/')) {
      throw ArgumentError(t.bookshelf.folderNameSlash);
    }

    final folder = await database.folders.getByUniqueKey(
      await _uniqueKey(path, type),
    );
    if (folder == null || folder.deletedAt != null) return;

    final parentPath = _parentPath(path);
    final newPath = _folderPath(parentPath, safeName);
    final newUniqueKey = await _uniqueKey(newPath, type);

    // 检查目标名称是否冲突
    final duplicated = await database.folders.getByUniqueKey(newUniqueKey);
    if (duplicated != null && duplicated.id != folder.id) {
      if (duplicated.deletedAt == null) {
        throw StateError(t.bookshelf.folderNameExists);
      }
      //  Tombstone 冲突：先物理删除旧的 tombstone
      await database.folders.removeById(duplicated.id);
    }

    final now = _now();
    folder
      ..name = safeName
      ..uniqueKey = newUniqueKey
      ..updatedAt = now
      ..versionVector = _bumpVersionVector(folder.versionVector);
    await database.folders.put(folder);
  }

  // ==================== 批量操作 ====================

  /// 批量移动文件夹到目标路径下。
  /// 会检查：不能移动到自己、不能移动到后代路径下。
  static Future<void> batchMoveFolders(
    Set<String> paths,
    String targetPath,
    ComicFolderType type,
  ) async {
    for (final path in paths) {
      _validateMoveTarget(path, targetPath);
    }

    final now = _now();
    for (final path in paths) {
      final folder = await database.folders.getByUniqueKey(
        await _uniqueKey(path, type),
      );
      if (folder == null || folder.deletedAt != null) continue;

      final folderName = folder.name;
      final newPath = _folderPath(targetPath, folderName);
      final newUniqueKey = await _uniqueKey(newPath, type);

      // 目标位置若存在 tombstone，先物理清理
      final duplicated = await database.folders.getByUniqueKey(newUniqueKey);
      if (duplicated != null && duplicated.id != folder.id) {
        if (duplicated.deletedAt == null) {
          throw StateError(
            t.bookshelf.targetFolderNameExists(name: folderName),
          );
        }
        await database.folders.removeById(duplicated.id);
      }

      await _moveFolderInternal(folder, newPath, now, type);
    }
  }

  /// 批量复制文件夹到目标路径下。
  /// 若目标位置已有同名文件夹，会自动重命名（加序号后缀）。
  static Future<void> batchCopyFolders(
    Set<String> paths,
    String targetPath,
    ComicFolderType type,
  ) async {
    for (final path in paths) {
      if (path == targetPath || targetPath.startsWith('$path/')) {
        throw StateError(t.bookshelf.cannotCopyFolderToSelfOrChild);
      }
    }

    final now = _now();
    final targetParentSyncId = await _parentSyncIdByPath(targetPath, type);
    for (final path in paths) {
      final sourceFolder = await database.folders.getByUniqueKey(
        await _uniqueKey(path, type),
      );
      if (sourceFolder == null || sourceFolder.deletedAt != null) continue;

      await _copyFolderRecursive(sourceFolder, targetParentSyncId, type, now);
    }
  }

  /// 批量删除文件夹（递归软删除）。
  static Future<void> batchDeleteFolders(
    Set<String> paths,
    ComicFolderType type,
  ) async {
    for (final path in paths) {
      await deleteFolder(path, type);
    }
  }

  static void _validateMoveTarget(String sourcePath, String targetPath) {
    if (sourcePath == targetPath) {
      throw StateError(t.bookshelf.cannotMoveFolderToSelf);
    }
    if (targetPath.startsWith('$sourcePath/')) {
      throw StateError(t.bookshelf.cannotMoveParentToChild);
    }
  }

  /// 移动单个文件夹的内部实现（不校验，直接执行）。
  static Future<void> _moveFolderInternal(
    ComicFolder folder,
    String newPath,
    int now,
    ComicFolderType type,
  ) async {
    final newUniqueKey = await _uniqueKey(newPath, type);
    final newParentSyncId = await _parentSyncIdByPath(
      _parentPath(newPath),
      type,
    );

    folder
      ..name = newPath.split('/').last
      ..parentSyncId = newParentSyncId
      ..uniqueKey = newUniqueKey
      ..updatedAt = now
      ..versionVector = _bumpVersionVector(folder.versionVector);
    await database.folders.put(folder);
  }

  /// 递归复制文件夹。
  static Future<void> _copyFolderRecursive(
    ComicFolder sourceFolder,
    String? targetParentSyncId,
    ComicFolderType type,
    int now,
  ) async {
    // 确定目标名称，处理重名
    final parentKey = targetParentSyncId ?? '';
    var targetName = sourceFolder.name;
    var suffix = 1;
    while (true) {
      final candidateKey = '$parentKey|$targetName|${type.name}';
      final exists = await database.folders.getByUniqueKey(candidateKey);
      if (exists == null) break;
      suffix++;
      targetName = '${sourceFolder.name} ($suffix)';
    }

    // 创建目标文件夹
    final targetFolder = ComicFolder(
      syncId: _newSyncId,
      parentSyncId: targetParentSyncId,
      uniqueKey: '$parentKey|$targetName|${type.name}',
      name: targetName,
      typeData: type.name,
      versionVector: {_deviceId: 1},
      createdAt: now,
      updatedAt: now,
      coverComicUniqueKey: sourceFolder.coverComicUniqueKey,
    );
    await database.folders.put(targetFolder);

    // 复制当前文件夹下的链接
    final links = await database.links.listActiveByFolder(
      sourceFolder.syncId,
      type.name,
    );
    if (links.isNotEmpty) {
      await database.links.putMany([
        for (final link in links)
          ComicLink(
            uniqueKey:
                '${link.comicUniqueKey}|${targetFolder.syncId}|${type.name}',
            comicUniqueKey: link.comicUniqueKey,
            folderSyncId: targetFolder.syncId,
            typeData: type.name,
            versionVector: {_deviceId: 1},
            createdAt: now,
            updatedAt: now,
          ),
      ]);
    }

    // 递归复制子文件夹
    final children = await database.folders.listActiveChildren(
      sourceFolder.syncId,
      type.name,
    );
    for (final child in children) {
      await _copyFolderRecursive(child, targetFolder.syncId, type, now);
    }
  }

  static Future<Set<String>> _collectSubtreeSyncIds(
    String rootSyncId,
    ComicFolderType type,
  ) async {
    final result = <String>{rootSyncId};
    final queue = [rootSyncId];
    while (queue.isNotEmpty) {
      final parentId = queue.removeLast();
      final children = await database.folders.listActiveChildren(
        parentId,
        type.name,
      );
      for (final child in children) {
        if (result.add(child.syncId)) queue.add(child.syncId);
      }
    }
    return result;
  }
}
