import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/object_box/model.dart';
import 'package:zephyr/page/bookshelf/service/comic_folder_service.dart';
import 'package:zephyr/ui/ui.dart';
import 'package:zephyr/widgets/toast.dart';

/// 文件夹目标选择器（书架移动/复制 + 详情页本地收藏共用，CalmUI 版）。
///
/// 路径以 `/a/b` 形式表示；根目录用 [kComicFolderRootPath]（空串）表示。
/// 返回选中的路径集合；返回 null 表示用户取消了选择。
/// [allowEmptyConfirm] 为 true 时允许空选确认（详情页用空选表示取消收藏）。
Future<Set<String>?> showFolderTargetPicker(
  BuildContext context, {
  required ComicFolderType type,
  Set<String> initialSelectedPaths = const {},
  bool multiSelect = true,
  bool rootEnabled = true,
  Set<String> disabledSyncIds = const {},
  bool allowCreateFolder = true,
  bool allowEmptyConfirm = false,
  String? title,
  String? currentSyncId,
}) async {
  final folders = await ComicFolderService.listAllFolders(type);
  if (!context.mounted) return null;
  final syncIdMap = <String, ComicFolder>{
    for (final folder in folders) folder.syncId: folder,
  };
  final pathMap = <String, String>{
    for (final folder in folders)
      folder.syncId: ComicFolderService.folderPath(
        folder,
        syncIdMap: syncIdMap,
      ),
  };

  // 选中项放在 ValueNotifier 里：弹窗正文与底部「确定」按钮分处两棵子树，
  // 只有共享同一个可监听草稿，禁用态才能随勾选即时刷新。
  final selected = ValueNotifier<Set<String>>(
    Set<String>.from(initialSelectedPaths),
  );
  final result = await showCalmDialog<Set<String>>(
    context,
    title: title ?? t.bookshelf.selectTargetFolder,
    icon: Icons.drive_file_move_outline,
    maxWidth: 460,
    bodyBuilder: (dialogContext) => _FolderTargetPickerBody(
      type: type,
      initialFolders: folders,
      initialSyncIdMap: syncIdMap,
      initialPathMap: pathMap,
      multiSelect: multiSelect,
      rootEnabled: rootEnabled,
      allowCreateFolder: allowCreateFolder,
      disabledSyncIds: disabledSyncIds,
      currentSyncId: currentSyncId,
      selected: selected,
    ),
    actionsBuilder: (dialogContext) => [
      CalmButton(
        label: t.common.cancel,
        variant: CalmButtonVariant.ghost,
        onPressed: () => Navigator.of(dialogContext).pop(),
      ),
      ValueListenableBuilder<Set<String>>(
        valueListenable: selected,
        builder: (context, value, _) => CalmButton(
          label: t.common.ok,
          variant: CalmButtonVariant.primary,
          onPressed: allowEmptyConfirm || value.isNotEmpty
              ? () => Navigator.of(dialogContext).pop(Set<String>.from(value))
              : null,
        ),
      ),
    ],
  );
  selected.dispose();
  return result;
}

/// 选择器正文：文件夹森林 + 新建文件夹入口，勾选直接写回共享草稿。
class _FolderTargetPickerBody extends StatefulWidget {
  const _FolderTargetPickerBody({
    required this.type,
    required this.initialFolders,
    required this.initialSyncIdMap,
    required this.initialPathMap,
    required this.multiSelect,
    required this.rootEnabled,
    required this.allowCreateFolder,
    required this.disabledSyncIds,
    required this.currentSyncId,
    required this.selected,
  });

  final ComicFolderType type;
  final List<ComicFolder> initialFolders;
  final Map<String, ComicFolder> initialSyncIdMap;
  final Map<String, String> initialPathMap;
  final bool multiSelect;
  final bool rootEnabled;
  final bool allowCreateFolder;
  final Set<String> disabledSyncIds;
  final String? currentSyncId;
  final ValueNotifier<Set<String>> selected;

  @override
  State<_FolderTargetPickerBody> createState() =>
      _FolderTargetPickerBodyState();
}

class _FolderTargetPickerBodyState extends State<_FolderTargetPickerBody> {
  late List<ComicFolder> _folders = widget.initialFolders;
  late Map<String, ComicFolder> _syncIdMap = widget.initialSyncIdMap;
  late Map<String, String> _pathMap = widget.initialPathMap;
  final Set<String> _expandedPaths = <String>{};

  Future<void> _reloadFolders() async {
    _folders = await ComicFolderService.listAllFolders(widget.type);
    _syncIdMap = {for (final folder in _folders) folder.syncId: folder};
    _pathMap = {
      for (final folder in _folders)
        folder.syncId: ComicFolderService.folderPath(
          folder,
          syncIdMap: _syncIdMap,
        ),
    };
  }

  void _togglePath(String path) {
    final current = widget.selected.value;
    if (!widget.multiSelect) {
      widget.selected.value = <String>{path};
      return;
    }
    widget.selected.value = current.contains(path)
        ? (Set<String>.from(current)..remove(path))
        : (Set<String>.from(current)..add(path));
  }

  Future<void> _createFolderAtRoot() async {
    final name = await _askFolderName(context);
    if (name == null || name.trim().isEmpty) return;
    try {
      final folder = await ComicFolderService.createFolder(
        kComicFolderRootPath,
        name.trim(),
        widget.type,
      );
      await _reloadFolders();
      if (!mounted) return;
      final newPath = ComicFolderService.folderPath(
        folder,
        syncIdMap: _syncIdMap,
      );
      setState(() {});
      widget.selected.value = widget.multiSelect
          ? (Set<String>.from(widget.selected.value)..add(newPath))
          : <String>{newPath};
    } catch (e) {
      logger.e(e);
      showErrorToast(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final forest = buildFolderForest(_folders, _pathMap);
    return ValueListenableBuilder<Set<String>>(
      valueListenable: widget.selected,
      builder: (context, selectedPaths, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.allowCreateFolder)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: CalmButton(
                    label: t.bookshelf.createFolder,
                    icon: Icons.create_new_folder_outlined,
                    variant: CalmButtonVariant.tonal,
                    size: CalmButtonSize.xs,
                    onPressed: _createFolderAtRoot,
                  ),
                ),
              ),
            _RootTargetTile(
              selected: selectedPaths.contains(kComicFolderRootPath),
              enabled: widget.rootEnabled,
              multiSelect: widget.multiSelect,
              onTap: () => _togglePath(kComicFolderRootPath),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: CalmDivider(),
            ),
            for (final node in forest)
              buildFolderTreeTile(
                context: context,
                node: node,
                pathMap: _pathMap,
                expandedPaths: _expandedPaths,
                forbiddenSyncIds: widget.disabledSyncIds,
                selectedPaths: selectedPaths,
                singleSelect: !widget.multiSelect,
                currentSyncId: widget.currentSyncId,
                onToggleExpand: (path) => setState(() {
                  if (_expandedPaths.contains(path)) {
                    _expandedPaths.remove(path);
                  } else {
                    _expandedPaths.add(path);
                  }
                }),
                onSelect: _togglePath,
              ),
          ],
        );
      },
    );
  }
}

Future<String?> _askFolderName(BuildContext context) {
  final controller = TextEditingController();
  return showCalmDialog<String>(
    context,
    title: t.bookshelf.createFolder,
    icon: Icons.create_new_folder_outlined,
    bodyBuilder: (dialogContext) => CalmTextField(
      controller: controller,
      hintText: t.bookshelf.folderName,
      prefixIcon: Icons.folder_outlined,
      onSubmitted: (text) {
        final value = text.trim();
        if (value.isNotEmpty) Navigator.of(dialogContext).pop(value);
      },
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
          final text = controller.text.trim();
          if (text.isNotEmpty) Navigator.of(dialogContext).pop(text);
        },
      ),
    ],
  ).whenComplete(controller.dispose);
}

class _RootTargetTile extends StatelessWidget {
  const _RootTargetTile({
    required this.selected,
    required this.enabled,
    required this.multiSelect,
    required this.onTap,
  });

  final bool selected;
  final bool enabled;
  final bool multiSelect;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      decoration: BoxDecoration(
        color: selected ? c.accentSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: CalmListTile(
        title: t.common.root,
        leading: Icon(Icons.home_outlined, size: 16, color: c.text2),
        onTap: enabled ? onTap : null,
        trailing: multiSelect
            ? CalmCheckbox(
                value: selected,
                onChanged: enabled ? (_) => onTap() : null,
              )
            : _CalmRadioDot(selected: selected, enabled: enabled),
      ),
    );
  }
}

/// 单选态圆点：与 [CalmCheckbox] 同尺寸，保证单选/多选两种模式行高一致。
class _CalmRadioDot extends StatelessWidget {
  const _CalmRadioDot({required this.selected, required this.enabled});

  final bool selected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = context.calm;
    return AnimatedOpacity(
      opacity: enabled ? 1 : 0.45,
      duration: const Duration(milliseconds: 140),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? c.accent : Colors.transparent,
          border: Border.all(
            color: selected ? c.accent : c.borderStrong,
            width: 1.6,
          ),
        ),
        alignment: Alignment.center,
        child: AnimatedScale(
          scale: selected ? 1 : 0,
          duration: const Duration(milliseconds: 140),
          child: Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: c.accentFg,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}

class FolderNode {
  final ComicFolder folder;
  final List<FolderNode> children;

  FolderNode(this.folder) : children = [];
}

List<FolderNode> buildFolderForest(
  List<ComicFolder> folders,
  Map<String, String> pathMap,
) {
  final sorted = folders.toList()
    ..sort(
      (a, b) => (pathMap[a.syncId] ?? '').compareTo(pathMap[b.syncId] ?? ''),
    );
  final map = <String, FolderNode>{};
  final roots = <FolderNode>[];
  for (final folder in sorted) {
    final node = FolderNode(folder);
    map[folder.syncId] = node;
    final parentSyncId = folder.parentSyncId;
    if (parentSyncId == null || parentSyncId.isEmpty) {
      roots.add(node);
    } else {
      map[parentSyncId]?.children.add(node);
    }
  }
  return roots;
}

void collectForbiddenSyncIds(
  String syncId,
  List<ComicFolder> allFolders,
  Set<String> result,
) {
  if (!result.add(syncId)) return;
  for (final child in allFolders) {
    if (child.parentSyncId == syncId) {
      collectForbiddenSyncIds(child.syncId, allFolders, result);
    }
  }
}

Widget buildFolderTreeTile({
  required BuildContext context,
  required FolderNode node,
  required Map<String, String> pathMap,
  required Set<String> expandedPaths,
  required Set<String> forbiddenSyncIds,
  required Set<String> selectedPaths,
  bool singleSelect = false,
  String? currentSyncId,
  required ValueChanged<String> onToggleExpand,
  required ValueChanged<String> onSelect,
}) {
  final c = context.calm;
  final path = pathMap[node.folder.syncId] ?? '/${node.folder.name}';
  final syncId = node.folder.syncId;
  final isExpanded = expandedPaths.contains(path);
  final isCurrentPath = currentSyncId != null && syncId == currentSyncId;
  final isForbidden = isCurrentPath || forbiddenSyncIds.contains(syncId);
  final hasChildren = node.children.isNotEmpty;
  final isSelected = selectedPaths.contains(path) && !isForbidden;

  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        decoration: BoxDecoration(
          color: isSelected ? c.accentSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: CalmListTile(
          title: node.folder.name,
          borderRadius: 12,
          leading: hasChildren
              ? CalmIconButton(
                  icon: isExpanded
                      ? Icons.expand_more_rounded
                      : Icons.chevron_right_rounded,
                  size: 24,
                  iconSize: 16,
                  onPressed: () => onToggleExpand(path),
                )
              : SizedBox(
                  width: 24,
                  child: Icon(Icons.folder_outlined, size: 15, color: c.text3),
                ),
          onTap: isForbidden ? null : () => onSelect(path),
          trailing: Opacity(
            opacity: isForbidden ? 0.45 : 1,
            child: singleSelect
                ? _CalmRadioDot(selected: isSelected, enabled: !isForbidden)
                : CalmCheckbox(
                    value: isSelected,
                    onChanged: isForbidden ? null : (_) => onSelect(path),
                  ),
          ),
        ),
      ),
      if (isExpanded)
        Padding(
          padding: const EdgeInsets.only(left: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: node.children
                .map(
                  (child) => buildFolderTreeTile(
                    context: context,
                    node: child,
                    pathMap: pathMap,
                    expandedPaths: expandedPaths,
                    forbiddenSyncIds: forbiddenSyncIds,
                    selectedPaths: selectedPaths,
                    singleSelect: singleSelect,
                    currentSyncId: currentSyncId,
                    onToggleExpand: onToggleExpand,
                    onSelect: onSelect,
                  ),
                )
                .toList(),
          ),
        ),
    ],
  );
}
