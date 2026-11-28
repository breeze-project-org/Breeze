import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:zephyr/ui/ui.dart';
import 'package:zephyr/page/comic_info/models/favorite_workflow.dart';
import 'package:zephyr/network/http/plugin/unified_comic_plugin.dart';
import 'package:zephyr/object_box/model.dart';
import 'package:zephyr/page/bookshelf/service/comic_link_service.dart';
import 'package:zephyr/page/bookshelf/service/comic_folder_service.dart';
import 'package:zephyr/util/storage/path_util.dart';
import 'package:zephyr/page/comic_info/json/normal/normal_comic_all_info.dart';
import 'package:zephyr/widgets/toast.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/main.dart';

Future<bool> isLocalComicCollected({
  required String from,
  required String comicId,
}) async {
  final pluginId = (from).trim();
  final key = '$pluginId:$comicId';
  final unified = await database.favorites.getByKey(key);
  final collected = unified != null && unified.deleted == false;
  if (collected) {
    // 封面路径修复只是后台自愈，不阻塞收藏状态的首帧判定。
    unawaited(() async {
      try {
        await _repairFavoriteCoverPathIfNeeded(unified);
      } catch (e, s) {
        logger.e(e, stackTrace: s);
      }
    }());
  }
  return collected;
}

Future<bool> toggleLocalComicFavorite({
  required String from,
  required NormalComicAllInfo normalInfo,
  bool showToast = true,
}) async {
  final pluginId = (from).trim();
  final key = '$pluginId:${normalInfo.comicInfo.id}';
  final unified = await database.favorites.getByKey(key);

  if (unified != null && !unified.deleted) {
    await database.favorites.markDeletedByKey(key);
    await ComicLinkService.removeComicFromAll(key, ComicFolderType.favorite);
    if (showToast) {
      // showSuccessToast('已取消本地收藏');
    }
    return false;
  }

  await _ensureLocalFavoriteRecord(pluginId: pluginId, normalInfo: normalInfo);

  // 新收藏默认添加一条根目录链接
  await ComicLinkService.addComic(key, null, ComicFolderType.favorite);

  if (showToast) {
    // showSuccessToast('成功收藏到本地');
  }
  return true;
}

/// 确保本地收藏本体记录存在且未删除，返回 uniqueKey。
///
/// 已收藏时直接返回；从未收藏或曾取消时重建记录（复活保留 createdAt）。
/// 只负责本体记录，不动文件夹链接，调用方自行决定链接去向。
Future<String> _ensureLocalFavoriteRecord({
  required String pluginId,
  required NormalComicAllInfo normalInfo,
}) async {
  final comicInfo = normalInfo.comicInfo;
  final key = '$pluginId:${comicInfo.id}';
  final now = DateTime.now().toUtc();
  final unified = await database.favorites.getByKey(key);

  final downloadRows = await database.downloads.getShelfByKeys([key]);
  final download = downloadRows.isEmpty ? null : downloadRows.first;
  final titleOverride = download != null && !download.deleted
      ? download.titleOverride?.trim() ?? ''
      : '';
  final coverOverride = download != null && !download.deleted
      ? download.coverOverride
      : null;
  final effectiveTitle = titleOverride.isNotEmpty
      ? download!.title
      : comicInfo.title;
  final effectiveCover = coverOverride ?? _normalizedCover(comicInfo.cover);

  if (unified != null && unified.deleted == false) {
    if (titleOverride.isNotEmpty || coverOverride != null) {
      unified
        ..title = effectiveTitle
        ..cover = effectiveCover
        ..updatedAt = now;
      await database.favorites.put(unified);
    }
    return key;
  }

  final createdAt = unified?.createdAt ?? now;

  await database.favorites.put(
    UnifiedComicFavorite(
      id: unified?.id ?? 0,
      uniqueKey: key,
      source: pluginId,
      comicId: comicInfo.id,
      title: effectiveTitle,
      description: comicInfo.description,
      cover: effectiveCover,
      creator: _normalizedCreator(comicInfo.creator),
      titleMeta: comicInfo.titleMeta,
      metadata: comicInfo.metadata,
      createdAt: createdAt,
      updatedAt: now,
      deleted: false,
      schemaVersion: 2,
    ),
  );
  return key;
}

/// 该漫画当前所在的本地收藏文件夹路径集合（含根目录 [kComicFolderRootPath]）。
Future<Set<String>> localComicFavoriteFolderPaths({
  required String from,
  required String comicId,
}) async {
  final key = '${(from).trim()}:$comicId';
  final links = await ComicLinkService.linksOfComic(
    key,
    ComicFolderType.favorite,
  );
  if (links.isEmpty) return <String>{};
  final pathMap = await _favoriteFolderPathMap();
  final paths = <String>{};
  for (final link in links) {
    final folderSyncId = link.folderSyncId;
    if (folderSyncId == null || folderSyncId.isEmpty) {
      paths.add(kComicFolderRootPath);
      continue;
    }
    final path = pathMap[folderSyncId];
    // 文件夹已被彻底删除的孤儿链接：不纳入也不清理，保守保留。
    if (path != null) paths.add(path);
  }
  return paths;
}

Future<Map<String, String>> _favoriteFolderPathMap() async {
  final folders = await ComicFolderService.listAllFolders(
    ComicFolderType.favorite,
  );
  final syncIdMap = {for (final folder in folders) folder.syncId: folder};
  return {
    for (final folder in folders)
      folder.syncId: ComicFolderService.folderPath(
        folder,
        syncIdMap: syncIdMap,
      ),
  };
}

/// 长按选文件夹：把本地收藏的文件夹归属设置为 [targetPaths]。
///
/// 未收藏时先建本体再挂链接；已收藏时先加后删，避免中间零链接误删本体。
/// 空集合不做任何改动并返回当前状态（调用方应禁用空确认，取消收藏走点按）。
Future<bool> setLocalComicFavoriteFolders({
  required String from,
  required NormalComicAllInfo normalInfo,
  required Set<String> targetPaths,
}) async {
  final pluginId = (from).trim();
  final key = await _ensureLocalFavoriteRecord(
    pluginId: pluginId,
    normalInfo: normalInfo,
  );
  if (targetPaths.isEmpty) {
    return isLocalComicCollected(from: from, comicId: normalInfo.comicInfo.id);
  }

  // 先加后删：即使全不相交也不会出现零链接中间态。
  for (final path in targetPaths) {
    await ComicLinkService.addComic(
      key,
      path.isEmpty ? null : path,
      ComicFolderType.favorite,
    );
  }
  final currentPaths = <String, String?>{};
  final pathMap = await _favoriteFolderPathMap();
  for (final link in await ComicLinkService.linksOfComic(
    key,
    ComicFolderType.favorite,
  )) {
    final folderSyncId = link.folderSyncId;
    if (folderSyncId == null || folderSyncId.isEmpty) {
      currentPaths[kComicFolderRootPath] = null;
      continue;
    }
    final path = pathMap[folderSyncId];
    if (path != null) currentPaths[path] = path;
  }
  for (final entry in currentPaths.entries) {
    if (!targetPaths.contains(entry.key)) {
      await ComicLinkService.removeComic(
        key,
        entry.value,
        ComicFolderType.favorite,
      );
    }
  }
  return true;
}

ComicImage _normalizedCover(ComicImage image) {
  return image.copyWith(
    path: _resolveImagePath(id: image.id, url: image.url, rawPath: image.path),
  );
}

Creator _normalizedCreator(Creator creator) {
  return creator.copyWith(avatar: _normalizedCover(creator.avatar));
}

Future<void> _repairFavoriteCoverPathIfNeeded(
  UnifiedComicFavorite favorite,
) async {
  final cover = favorite.cover;
  if (cover.id.trim().isEmpty &&
      cover.url.trim().isEmpty &&
      cover.path.trim().isEmpty) {
    return;
  }
  if (cover.path.trim().isNotEmpty) {
    return;
  }

  final repairedPath = _resolveImagePath(
    id: cover.id.trim().isEmpty ? favorite.comicId : cover.id,
    url: cover.url,
    rawPath: cover.path,
  );
  if (repairedPath.isEmpty) {
    return;
  }

  favorite.cover = cover.copyWith(path: repairedPath);
  favorite.updatedAt = DateTime.now().toUtc();
  await database.favorites.put(favorite);
}

String _resolveImagePath({
  required String id,
  required String url,
  required String rawPath,
}) {
  final path = rawPath.trim();
  if (path.isNotEmpty) {
    return path;
  }

  final safeId = sanitizePathSegment(id.trim().isEmpty ? 'cover' : id);
  final extension = extractImageExtension(url);
  return '$safeId.$extension';
}

Future<bool> toggleCloudComicFavorite({
  required BuildContext context,
  required String from,
  String? pluginId,
  required String comicId,
  required bool currentStatus,
  bool legacyAllowCollected = true,
  String legacyAllowCollectedReason = '',
  String? collectionTargetId,
  String? collectionTargetName,
}) async {
  final result = await executeCloudFavoriteWorkflow(
    context: context,
    from: from,
    pluginId: pluginId,
    comicId: comicId,
    action: currentStatus
        ? ((collectionTargetId?.trim().isNotEmpty ?? false) ||
                  (collectionTargetName?.trim().isNotEmpty ?? false)
              ? FavoriteWorkflowAction.removeFromTarget
              : FavoriteWorkflowAction.removeAll)
        : FavoriteWorkflowAction.add,
    currentStatus: currentStatus,
    legacyAllowCollected: legacyAllowCollected,
    legacyAllowCollectedReason: legacyAllowCollectedReason,
    collectionTargetId: collectionTargetId,
    collectionTargetName: collectionTargetName,
  );
  if (result.status != FavoriteWorkflowStatus.completed) {
    throw FavoriteWorkflowIncompleteException(result);
  }
  final favorited = result.favorited;
  if (favorited is! bool) {
    throw StateError(t.comicInfo.pluginInvalidFavorited);
  }
  return favorited;
}

Future<FavoriteWorkflowExecutionResult> executeCloudFavoriteWorkflow({
  required BuildContext context,
  required String from,
  String? pluginId,
  required String comicId,
  required FavoriteWorkflowAction action,
  required bool currentStatus,
  bool legacyAllowCollected = true,
  String legacyAllowCollectedReason = '',
  String? collectionTargetId,
  String? collectionTargetName,
}) async {
  final resolvedPluginId = (pluginId?.trim().isNotEmpty ?? false)
      ? pluginId!.trim()
      : from.trim();
  try {
    return await _runFavoriteWorkflow(
      context: context,
      pluginId: resolvedPluginId,
      comicId: comicId,
      action: action,
      currentStatus: currentStatus,
      collectionTargetId: collectionTargetId,
      collectionTargetName: collectionTargetName,
    );
  } catch (error) {
    if (!_isMissingFavoriteWorkflowFunction(error)) {
      rethrow;
    }
    if (!legacyAllowCollected ||
        (action != FavoriteWorkflowAction.add &&
            action != FavoriteWorkflowAction.removeAll)) {
      throw FavoriteWorkflowUnsupportedException(legacyAllowCollectedReason);
    }
    return _runLegacyFavoriteWorkflow(
      context: context,
      pluginId: resolvedPluginId,
      comicId: comicId,
      action: action,
      currentStatus: currentStatus,
    );
  }
}

Future<FavoriteWorkflowExecutionResult> _runFavoriteWorkflow({
  required BuildContext context,
  required String pluginId,
  required String comicId,
  required FavoriteWorkflowAction action,
  required bool currentStatus,
  String? collectionTargetId,
  String? collectionTargetName,
}) async {
  final target = <String, dynamic>{};
  if (collectionTargetId?.trim().isNotEmpty ?? false) {
    target['id'] = collectionTargetId!.trim();
  }
  if (collectionTargetName?.trim().isNotEmpty ?? false) {
    target['name'] = collectionTargetName!.trim();
  }

  var response = await callUnifiedComicPlugin(
    pluginId: pluginId,
    fnPath: 'startFavoriteAction',
    core: {
      'comicId': comicId,
      'action': action.wireName,
      'currentFavorite': currentStatus,
      if (target.isNotEmpty) 'context': {'target': target},
    },
    extern: const <String, dynamic>{},
  );

  for (var step = 0; step < 16; step++) {
    final result = FavoriteWorkflowResult.fromJson(response.data);
    switch (result.status) {
      case FavoriteWorkflowStatus.completed:
        return _toExecutionResult(result);
      case FavoriteWorkflowStatus.partial:
      case FavoriteWorkflowStatus.failed:
      case FavoriteWorkflowStatus.cancelled:
        final executionResult = _toExecutionResult(result);
        if (result.status == FavoriteWorkflowStatus.failed) {
          final message = result.message?.trim() ?? '';
          throw StateError(
            message.isNotEmpty ? message : t.error.executionFailed,
          );
        }
        throw FavoriteWorkflowIncompleteException(executionResult);
      case FavoriteWorkflowStatus.awaitingInput:
        final token = result.continuationToken?.trim() ?? '';
        final input = result.input;
        if (token.isEmpty || input == null) {
          throw StateError('收藏工作流等待交互时缺少 continuationToken 或 input');
        }
        if (!context.mounted) {
          throw const FavoriteWorkflowIncompleteException(
            FavoriteWorkflowExecutionResult(
              status: FavoriteWorkflowStatus.cancelled,
              message: '页面已关闭，收藏操作已取消',
            ),
          );
        }
        final userInput = await _showFavoriteWorkflowInput(context, input);
        response = await callUnifiedComicPlugin(
          pluginId: pluginId,
          fnPath: 'continueFavoriteAction',
          core: {
            'comicId': comicId,
            'action': action.wireName,
            'continuationToken': token,
            'input': userInput ?? const <String, dynamic>{'cancelled': true},
          },
          extern: const <String, dynamic>{},
        );
    }
  }

  throw StateError('收藏工作流超过最大交互步骤');
}

FavoriteWorkflowExecutionResult _toExecutionResult(
  FavoriteWorkflowResult result,
) {
  return FavoriteWorkflowExecutionResult(
    status: result.status,
    favorited: result.favorited,
    committed: result.committed,
    message: result.message,
  );
}

Future<FavoriteWorkflowExecutionResult> _runLegacyFavoriteWorkflow({
  required BuildContext context,
  required String pluginId,
  required String comicId,
  required FavoriteWorkflowAction action,
  required bool currentStatus,
}) async {
  final result = await callUnifiedComicPlugin(
    pluginId: pluginId,
    fnPath: 'toggleFavorite',
    core: {'comicId': comicId, 'currentFavorite': currentStatus},
    extern: const <String, dynamic>{},
  );
  final data = result.data;
  final favorited = data['favorited'];
  if (favorited is! bool) {
    throw StateError(t.comicInfo.pluginInvalidFavorited);
  }

  final nextStep = data['nextStep']?.toString() ?? 'none';
  if (action != FavoriteWorkflowAction.add ||
      !favorited ||
      nextStep != 'selectFolder' ||
      !context.mounted) {
    return FavoriteWorkflowExecutionResult(
      status: FavoriteWorkflowStatus.completed,
      favorited: favorited,
      committed: true,
    );
  }

  final folders = await _listCloudFavoriteFolders(pluginId);
  if (!context.mounted || folders.isEmpty) {
    return FavoriteWorkflowExecutionResult(
      status: FavoriteWorkflowStatus.completed,
      favorited: favorited,
      committed: true,
    );
  }

  final selectedFolder = await _showFolderSelectionDialog(context, folders);
  if (selectedFolder == null || !context.mounted) {
    return FavoriteWorkflowExecutionResult(
      status: FavoriteWorkflowStatus.completed,
      favorited: favorited,
      committed: true,
    );
  }

  await _moveCloudFavoriteToFolder(
    from: pluginId,
    comicId: comicId,
    folder: selectedFolder,
  );
  showSuccessToast(t.comicInfo.addedToFolder(name: selectedFolder.name));
  return FavoriteWorkflowExecutionResult(
    status: FavoriteWorkflowStatus.completed,
    favorited: favorited,
    committed: true,
  );
}

bool _isMissingFavoriteWorkflowFunction(Object error) {
  final message = error.toString().toLowerCase();
  return message.contains('startfavoriteaction') &&
      (message.contains('not a function') ||
          message.contains('function path not found') ||
          message.contains('missing function') ||
          message.contains('undefined'));
}

Future<Map<String, dynamic>?> _showFavoriteWorkflowInput(
  BuildContext context,
  FavoriteWorkflowInput input,
) {
  return switch (input.type) {
    'select' => _showFavoriteWorkflowSelect(context, input),
    'text' => _showFavoriteWorkflowText(context, input),
    'confirm' => _showFavoriteWorkflowConfirm(context, input),
    'form' => _showFavoriteWorkflowForm(context, input),
    _ => throw StateError('不支持的收藏工作流交互类型：${input.type}'),
  };
}

/// 选择型交互的共享草稿：选中项 + 新建名 + 变更计数（驱动确认按钮可用态）。
///
/// 草稿由调用方创建并在 `showCalmDialog` 结束后统一释放，弹窗内部只读写它，
/// 避免 `StatefulBuilder` 里反复重建 controller 造成的泄漏。
class _WorkflowSelectDraft {
  _WorkflowSelectDraft(Iterable<String> initial) : selected = {...initial};

  final Set<String> selected;
  final TextEditingController createController = TextEditingController();
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  String get createdName => createController.text.trim();

  bool canConfirm(FavoriteWorkflowInput input) =>
      !input.required || selected.isNotEmpty || createdName.isNotEmpty;

  Map<String, dynamic> buildResult(FavoriteWorkflowInput input) {
    final value = input.isMultiple
        ? selected.toList()
        : selected.isEmpty
        ? null
        : selected.first;
    return {
      if (input.key?.isNotEmpty ?? false) 'key': input.key,
      'value': value,
      if (createdName.isNotEmpty) 'created': createdName,
    };
  }

  void dispose() {
    createController.dispose();
    revision.dispose();
  }
}

Future<Map<String, dynamic>?> _showFavoriteWorkflowSelect(
  BuildContext context,
  FavoriteWorkflowInput input,
) async {
  final draft = _WorkflowSelectDraft(
    input.options.where((option) => option.selected).map((option) => option.id),
  );
  final result = await showCalmDialog<Map<String, dynamic>>(
    context,
    title: input.title ?? t.comicInfo.addToCustomFolder,
    icon: Icons.folder_special_outlined,
    maxWidth: 460,
    bodyBuilder: (dialogContext) =>
        _FavoriteWorkflowSelectBody(input: input, draft: draft),
    actionsBuilder: (dialogContext) => [
      CalmButton(
        label: t.common.cancel,
        variant: CalmButtonVariant.ghost,
        onPressed: () => Navigator.of(dialogContext).pop(),
      ),
      ValueListenableBuilder<int>(
        valueListenable: draft.revision,
        builder: (context, _, _) => CalmButton(
          label: t.common.confirm,
          variant: CalmButtonVariant.primary,
          onPressed: draft.canConfirm(input)
              ? () => Navigator.of(dialogContext).pop(draft.buildResult(input))
              : null,
        ),
      ),
    ],
  ).whenComplete(draft.dispose);
  return result;
}

class _FavoriteWorkflowSelectBody extends StatefulWidget {
  const _FavoriteWorkflowSelectBody({required this.input, required this.draft});

  final FavoriteWorkflowInput input;
  final _WorkflowSelectDraft draft;

  @override
  State<_FavoriteWorkflowSelectBody> createState() =>
      _FavoriteWorkflowSelectBodyState();
}

class _FavoriteWorkflowSelectBodyState
    extends State<_FavoriteWorkflowSelectBody> {
  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    final input = widget.input;
    final draft = widget.draft;
    final description = input.description?.trim() ?? '';

    Widget optionDescription(String? text) {
      final trimmed = text?.trim() ?? '';
      if (trimmed.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(left: 26, bottom: 6),
        child: Text(
          trimmed,
          style: TextStyle(fontSize: 11, color: c.text3, height: 1.4),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (description.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              description,
              style: TextStyle(fontSize: 12, color: c.text2, height: 1.5),
            ),
          ),
        if (input.options.isNotEmpty)
          Column(
            children: [
              for (final option in input.options)
                if (input.isMultiple)
                  CalmCheckboxTile(
                    label: option.label,
                    subtitle: option.description,
                    value: draft.selected.contains(option.id),
                    onChanged: (value) => _toggle(option.id, value),
                  )
                else ...[
                  CalmRadioTile<String>(
                    label: option.label,
                    value: option.id,
                    groupValue: draft.selected.isEmpty
                        ? ''
                        : draft.selected.first,
                    onChanged: _selectSingle,
                  ),
                  optionDescription(option.description),
                ],
            ],
          ),
        if (input.allowCreate) ...[
          if (input.options.isNotEmpty) ...[
            const SizedBox(height: 6),
            const CalmDivider(),
            const SizedBox(height: 8),
          ],
          CalmTextField(
            controller: draft.createController,
            hintText: input.createField?.label ?? t.bookshelf.newFolder,
            prefixIcon: Icons.create_new_folder_outlined,
            onChanged: (_) => _onCreateChanged(),
          ),
        ],
      ],
    );
  }

  void _selectSingle(String id) {
    setState(() {
      widget.draft.selected
        ..clear()
        ..add(id);
      widget.draft.createController.clear();
    });
    widget.draft.revision.value++;
  }

  void _toggle(String id, bool value) {
    setState(() {
      if (value) {
        widget.draft.selected.add(id);
      } else {
        widget.draft.selected.remove(id);
      }
      widget.draft.createController.clear();
    });
    widget.draft.revision.value++;
  }

  void _onCreateChanged() {
    setState(() => widget.draft.selected.clear());
    widget.draft.revision.value++;
  }
}

Future<Map<String, dynamic>?> _showFavoriteWorkflowText(
  BuildContext context,
  FavoriteWorkflowInput input,
) async {
  final controller = TextEditingController();
  final revision = ValueNotifier<int>(0);

  Map<String, dynamic> payload() => {
    if (input.key?.isNotEmpty ?? false) 'key': input.key,
    'value': controller.text,
  };

  final result =
      await showCalmDialog<Map<String, dynamic>>(
        context,
        title: input.title ?? t.common.info,
        icon: Icons.edit_outlined,
        bodyBuilder: (dialogContext) => CalmTextField(
          controller: controller,
          hintText: input.description,
          prefixIcon: Icons.text_fields_rounded,
          onChanged: (_) => revision.value++,
          onSubmitted: (text) {
            if (!input.required || text.trim().isNotEmpty) {
              Navigator.of(dialogContext).pop(payload());
            }
          },
        ),
        actionsBuilder: (dialogContext) => [
          CalmButton(
            label: t.common.cancel,
            variant: CalmButtonVariant.ghost,
            onPressed: () => Navigator.of(dialogContext).pop(),
          ),
          ValueListenableBuilder<int>(
            valueListenable: revision,
            builder: (context, _, _) => CalmButton(
              label: t.common.confirm,
              variant: CalmButtonVariant.primary,
              onPressed: !input.required || controller.text.trim().isNotEmpty
                  ? () => Navigator.of(dialogContext).pop(payload())
                  : null,
            ),
          ),
        ],
      ).whenComplete(() {
        controller.dispose();
        revision.dispose();
      });
  return result;
}

Future<Map<String, dynamic>?> _showFavoriteWorkflowConfirm(
  BuildContext context,
  FavoriteWorkflowInput input,
) {
  final description = input.description?.trim() ?? '';
  return showCalmDialog<Map<String, dynamic>>(
    context,
    title: input.title ?? t.common.confirm,
    icon: Icons.help_outline_rounded,
    bodyBuilder: (dialogContext) => description.isEmpty
        ? const SizedBox.shrink()
        : Text(
            description,
            style: TextStyle(
              fontSize: 12.5,
              color: dialogContext.calm.text2,
              height: 1.5,
            ),
          ),
    actionsBuilder: (dialogContext) => [
      CalmButton(
        label: t.common.cancel,
        variant: CalmButtonVariant.ghost,
        onPressed: () => Navigator.of(dialogContext).pop(),
      ),
      CalmButton(
        label: t.common.confirm,
        variant: CalmButtonVariant.primary,
        onPressed: () => Navigator.of(dialogContext).pop({
          if (input.key?.isNotEmpty ?? false) 'key': input.key,
          'value': true,
        }),
      ),
    ],
  );
}

bool _isWorkflowTextField(String type) =>
    type != 'switch' &&
    type != 'confirm' &&
    type != 'choice' &&
    type != 'multiChoice';

/// 表单型交互的共享草稿：字段值 + 文本控制器 + 变更计数。
class _WorkflowFormDraft {
  _WorkflowFormDraft(this.input) {
    for (final field in input.fields) {
      if (field.defaultValue != null) {
        values[field.key] = field.defaultValue;
      } else if (field.type == 'switch' || field.type == 'confirm') {
        values[field.key] = false;
      } else if (field.type == 'multiChoice') {
        values[field.key] = <String>[];
      }
      if (_isWorkflowTextField(field.type)) {
        controllers[field.key] = TextEditingController(
          text: field.defaultValue?.toString() ?? '',
        );
      }
    }
  }

  final FavoriteWorkflowInput input;
  final Map<String, dynamic> values = <String, dynamic>{};
  final Map<String, TextEditingController> controllers =
      <String, TextEditingController>{};
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  bool get isValid {
    for (final field in input.fields.where((field) => field.required)) {
      final value = values[field.key];
      if (value == null ||
          value is String && value.trim().isEmpty ||
          value is List && value.isEmpty ||
          (field.type == 'switch' || field.type == 'confirm') &&
              value != true) {
        return false;
      }
    }
    return true;
  }

  void dispose() {
    for (final controller in controllers.values) {
      controller.dispose();
    }
    revision.dispose();
  }
}

Future<Map<String, dynamic>?> _showFavoriteWorkflowForm(
  BuildContext context,
  FavoriteWorkflowInput input,
) async {
  final draft = _WorkflowFormDraft(input);
  final result = await showCalmDialog<Map<String, dynamic>>(
    context,
    title: input.title ?? t.common.confirm,
    icon: Icons.checklist_rtl_rounded,
    maxWidth: 460,
    bodyBuilder: (dialogContext) =>
        _FavoriteWorkflowFormBody(input: input, draft: draft),
    actionsBuilder: (dialogContext) => [
      CalmButton(
        label: t.common.cancel,
        variant: CalmButtonVariant.ghost,
        onPressed: () => Navigator.of(dialogContext).pop(),
      ),
      ValueListenableBuilder<int>(
        valueListenable: draft.revision,
        builder: (context, _, _) => CalmButton(
          label: t.common.confirm,
          variant: CalmButtonVariant.primary,
          onPressed: draft.isValid
              ? () => Navigator.of(dialogContext)
                    .pop({'values': Map<String, dynamic>.from(draft.values)})
              : null,
        ),
      ),
    ],
  ).whenComplete(draft.dispose);
  return result;
}

class _FavoriteWorkflowFormBody extends StatefulWidget {
  const _FavoriteWorkflowFormBody({required this.input, required this.draft});

  final FavoriteWorkflowInput input;
  final _WorkflowFormDraft draft;

  @override
  State<_FavoriteWorkflowFormBody> createState() =>
      _FavoriteWorkflowFormBodyState();
}

class _FavoriteWorkflowFormBodyState extends State<_FavoriteWorkflowFormBody> {
  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    final input = widget.input;
    final description = input.description?.trim() ?? '';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (description.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              description,
              style: TextStyle(fontSize: 12, color: c.text2, height: 1.5),
            ),
          ),
        for (final field in input.fields)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _buildField(c, field),
          ),
      ],
    );
  }

  Widget _buildField(CalmColors c, FavoriteWorkflowField field) {
    final draft = widget.draft;
    switch (field.type) {
      case 'switch':
      case 'confirm':
        return CalmListTile(
          title: field.label,
          subtitle: field.description,
          trailing: CalmSwitch(
            value: draft.values[field.key] == true,
            onChanged: (value) {
              setState(() => draft.values[field.key] = value);
              draft.revision.value++;
            },
          ),
        );
      case 'choice':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _fieldLabel(c, field),
            _fieldDescription(c, field.description),
            for (final option in field.options) ...[
              CalmRadioTile<String>(
                label: option.label,
                value: option.id,
                groupValue: draft.values[field.key]?.toString() ?? '',
                onChanged: (value) {
                  setState(() => draft.values[field.key] = value);
                  draft.revision.value++;
                },
              ),
              _fieldDescription(c, option.description, left: 26),
            ],
          ],
        );
      case 'multiChoice':
        final selected = <String>[
          ...?(draft.values[field.key] as List?)?.cast<String>(),
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _fieldLabel(c, field),
            _fieldDescription(c, field.description),
            for (final option in field.options)
              CalmCheckboxTile(
                label: option.label,
                subtitle: option.description,
                value: selected.contains(option.id),
                onChanged: (value) {
                  setState(() {
                    if (value) {
                      selected.add(option.id);
                    } else {
                      selected.remove(option.id);
                    }
                    draft.values[field.key] = selected;
                  });
                  draft.revision.value++;
                },
              ),
          ],
        );
      case 'text':
      case 'password':
      case 'number':
      default:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _fieldLabel(c, field),
            CalmTextField(
              controller: draft.controllers[field.key],
              hintText: field.placeholder ?? field.label,
              obscureText: field.type == 'password',
              prefixIcon: field.type == 'password'
                  ? Icons.lock_outline_rounded
                  : null,
              keyboardType: field.type == 'number'
                  ? const TextInputType.numberWithOptions(decimal: true)
                  : null,
              onChanged: (value) {
                draft.values[field.key] = value;
                draft.revision.value++;
              },
            ),
          ],
        );
    }
  }

  Widget _fieldLabel(CalmColors c, FavoriteWorkflowField field) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        field.label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: c.text,
        ),
      ),
    );
  }

  Widget _fieldDescription(CalmColors c, String? text, {double left = 0}) {
    final trimmed = text?.trim() ?? '';
    if (trimmed.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(left: left, bottom: 4),
      child: Text(
        trimmed,
        style: TextStyle(fontSize: 11, color: c.text3, height: 1.4),
      ),
    );
  }
}

Future<bool> toggleCloudComicLike({
  required String from,
  required String comicId,
  required bool currentStatus,
}) async {
  final result = await callUnifiedComicPlugin(
    from: from,
    fnPath: 'toggleLike',
    core: {'comicId': comicId, 'currentLiked': currentStatus},
    extern: const <String, dynamic>{},
  );
  final data = result.data;
  if (data['liked'] is! bool) {
    throw StateError(t.comicInfo.pluginInvalidLiked);
  }
  return data['liked'] as bool;
}

Future<List<_FavoriteFolder>> _listCloudFavoriteFolders(String from) async {
  final result = await callUnifiedComicPlugin(
    from: from,
    fnPath: 'listFavoriteFolders',
    core: const <String, dynamic>{},
    extern: const <String, dynamic>{},
  );
  final data = result.data;
  final items = data['items'];
  if (items is! List) {
    return const <_FavoriteFolder>[];
  }
  return items
      .whereType<Map>()
      .map((item) => _FavoriteFolder.fromJson(Map<String, dynamic>.from(item)))
      .where((item) => item.id.isNotEmpty)
      .toList();
}

Future<void> _moveCloudFavoriteToFolder({
  required String from,
  required String comicId,
  required _FavoriteFolder folder,
}) async {
  await callUnifiedComicPlugin(
    from: from,
    fnPath: 'moveFavoriteToFolder',
    core: {
      'comicId': comicId,
      'folderId': folder.id,
      'folderName': folder.name,
    },
    extern: const <String, dynamic>{},
  );
}

Future<_FavoriteFolder?> _showFolderSelectionDialog(
  BuildContext context,
  List<_FavoriteFolder> folders,
) {
  final selected = ValueNotifier<_FavoriteFolder?>(null);
  return showCalmDialog<_FavoriteFolder>(
    context,
    title: t.comicInfo.addToCustomFolder,
    icon: Icons.folder_outlined,
    maxWidth: 460,
    bodyBuilder: (dialogContext) => _CloudFolderPickerBody(
      folders: folders,
      onSelected: (folder) => selected.value = folder,
    ),
    actionsBuilder: (dialogContext) => [
      CalmButton(
        label: t.comicInfo.skipAdd,
        variant: CalmButtonVariant.ghost,
        onPressed: () => Navigator.of(dialogContext).pop(),
      ),
      ValueListenableBuilder<_FavoriteFolder?>(
        valueListenable: selected,
        builder: (context, value, _) => CalmButton(
          label: t.comicInfo.confirmAdd,
          variant: CalmButtonVariant.primary,
          onPressed: value == null
              ? null
              : () => Navigator.of(dialogContext).pop(value),
        ),
      ),
    ],
  ).whenComplete(selected.dispose);
}

/// 云端收藏夹单选列表：淡底选中行，确认按钮随选择态启用。
class _CloudFolderPickerBody extends StatefulWidget {
  const _CloudFolderPickerBody({
    required this.folders,
    required this.onSelected,
  });

  final List<_FavoriteFolder> folders;
  final ValueChanged<_FavoriteFolder> onSelected;

  @override
  State<_CloudFolderPickerBody> createState() => _CloudFolderPickerBodyState();
}

class _CloudFolderPickerBodyState extends State<_CloudFolderPickerBody> {
  String? _selectedId;

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final folder in widget.folders)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CalmRadioTile<String>(
                  label: folder.name,
                  value: folder.id,
                  groupValue: _selectedId ?? '',
                  onChanged: (value) {
                    setState(() => _selectedId = value);
                    widget.onSelected(folder);
                  },
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 26, bottom: 4),
                  child: Text(
                    'ID: ${folder.id}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textHeightBehavior: kCalmTextHeightBehavior,
                    strutStyle: calmStrut(10.5),
                    style: TextStyle(
                      fontSize: 10.5,
                      color: c.text3,
                      height: 1.2,
                      leadingDistribution: TextLeadingDistribution.even,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _FavoriteFolder {
  const _FavoriteFolder({required this.id, required this.name});

  final String id;
  final String name;

  factory _FavoriteFolder.fromJson(Map<String, dynamic> json) {
    return _FavoriteFolder(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
    );
  }
}
