import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/search/method/filter_search_history.dart';
import 'package:zephyr/page/search/method/on_search.dart';

class HistoryWidget extends StatefulWidget {
  const HistoryWidget({
    super.key,
    this.aggregateMode = true,
    this.keyword = '',
  });

  final bool aggregateMode;

  /// 当前输入；非空时只展示模糊匹配的历史记录。
  final String keyword;

  /// 点历史词条前调用，丢弃 [SearchBar] 里待触发的输入防抖。
  /// 不丢的话：输入框旧词的防抖在提交后才开火，把新词盖掉。
  static VoidCallback? _cancelPendingKeywordSync;

  static void registerPendingKeywordSyncCanceller(VoidCallback? canceller) {
    _cancelPendingKeywordSync = canceller;
  }

  static void cancelPendingKeywordSync() {
    _cancelPendingKeywordSync?.call();
  }

  @override
  State<HistoryWidget> createState() => _HistoryWidgetState();
}

class _HistoryWidgetState extends State<HistoryWidget> {
  bool _isNewestFirst = true;
  List<String>? _normalizedHistorySource;
  List<String> _normalizedHistory = const <String>[];

  /// 历史列表未变化时复用归一化结果，避免每次输入都重新走 t2s。
  List<String> _normalizedHistoryFor(List<String> history) {
    if (!identical(_normalizedHistorySource, history)) {
      _normalizedHistorySource = history;
      _normalizedHistory = normalizeSearchHistory(history);
    }
    return _normalizedHistory;
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final globalSettingState = context.watch<GlobalSettingCubit>().state;
    final history = globalSettingState.searchHistory;
    final normalizedHistory = _normalizedHistoryFor(history);
    final orderedHistory = _isNewestFirst ? history : history.reversed.toList();
    final orderedNormalizedHistory = _isNewestFirst
        ? normalizedHistory
        : normalizedHistory.reversed.toList();
    final visibleHistory = filterSearchHistory(
      orderedHistory,
      widget.keyword,
      normalizedHistory: orderedNormalizedHistory,
    );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
          child: Row(
            children: [
              Text(
                t.search.history,
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),

              // 排序按钮
              if (globalSettingState.searchHistory.isNotEmpty) ...[
                _buildSortButton(),

                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20),
                  tooltip: t.search.clearHistory,
                  color: colorScheme.outline,
                  onPressed: _resetHistory,
                ),
              ],
            ],
          ),
        ),

        // --- 3. 历史记录内容区域 ---
        Expanded(
          child: history.isEmpty
              ? _buildEmpty()
              : visibleHistory.isEmpty
              ? _buildNoMatch()
              : _buildHistoryList(visibleHistory),
        ),
      ],
    );
  }

  Widget _buildSortButton() {
    final colorScheme = Theme.of(context).colorScheme;

    return Tooltip(
      message: _isNewestFirst ? t.search.newestFirst : t.search.oldestFirst,
      child: TextButton.icon(
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          minimumSize: const Size(0, 36),
        ),
        icon: Icon(
          _isNewestFirst ? Icons.history : Icons.history_toggle_off, // 图标随状态变
          size: 18,
          color: colorScheme.primary,
        ),
        label: Text(
          _isNewestFirst ? t.search.descending : t.search.ascending,
          style: TextStyle(fontSize: 12, color: colorScheme.primary),
        ),
        onPressed: () {
          setState(() {
            _isNewestFirst = !_isNewestFirst;
          });
        },
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.manage_search,
            size: 64,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
          const SizedBox(height: 16),
          Text(
            t.search.noHistory,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoMatch() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search_off,
            size: 64,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
          const SizedBox(height: 16),
          Text(
            t.search.noMatchingHistory,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryList(List<String> historyList) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SizedBox(
        width: double.infinity,
        child: Wrap(
          spacing: 12.0,
          runSpacing: 12.0,
          alignment: WrapAlignment.start,
          children: historyList.map((historyItem) {
            return GestureDetector(
              onLongPress: () => _deleteSingle(historyItem),
              child: InputChip(
                label: Text(historyItem),
                labelStyle: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 14,
                ),
                backgroundColor: Theme.of(context)
                    .colorScheme
                    .surfaceContainerLow,
                side: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  width: 1.0,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 0),
                onPressed: () {
                  HistoryWidget.cancelPendingKeywordSync();
                  onSearch(
                    context,
                    historyItem,
                    aggregateMode: widget.aggregateMode,
                  );
                },
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  void _deleteSingle(String historyItem) {
    final globalSettingCubit = context.read<GlobalSettingCubit>();
    final List<String> newHistory = List.from(
      globalSettingCubit.state.searchHistory,
    );
    newHistory.remove(historyItem);
    globalSettingCubit.updateState(
      (current) => current.copyWith(searchHistory: newHistory),
    );
  }

  void _resetHistory() {
    final globalSettingCubit = context.read<GlobalSettingCubit>();
    globalSettingCubit.resetState(
      (current, defaults) =>
          current.copyWith(searchHistory: defaults.searchHistory),
    );
  }
}
