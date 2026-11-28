import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/page/search/method/filter_search_history.dart';
import 'package:zephyr/page/search/method/on_search.dart';
import 'package:zephyr/ui/ui.dart';

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
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: CalmSectionHeader(
                  title: t.search.history,
                  countText: history.isEmpty ? null : '${history.length}',
                ),
              ),
              // 排序 + 一键清空
              if (globalSettingState.searchHistory.isNotEmpty) ...[
                _buildSortButton(),
                const SizedBox(width: 2),
                CalmButton(
                  label: t.search.clearHistory,
                  icon: Icons.delete_outline_rounded,
                  size: CalmButtonSize.xs,
                  variant: CalmButtonVariant.ghost,
                  onPressed: _confirmResetHistory,
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
    return Tooltip(
      message: _isNewestFirst ? t.search.newestFirst : t.search.oldestFirst,
      child: CalmButton(
        label: _isNewestFirst ? t.search.descending : t.search.ascending,
        icon: _isNewestFirst ? Icons.history_rounded : Icons.history_toggle_off,
        size: CalmButtonSize.xs,
        variant: CalmButtonVariant.ghost,
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
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: CalmEmptyState(
          icon: Icons.manage_search_rounded,
          title: t.search.noHistory,
        ),
      ),
    );
  }

  Widget _buildNoMatch() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: CalmEmptyState(
          icon: Icons.search_off_rounded,
          title: t.search.noMatchingHistory,
        ),
      ),
    );
  }

  Widget _buildHistoryList(List<String> historyList) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: SizedBox(
        width: double.infinity,
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.start,
          children: [
            for (final historyItem in historyList)
              GestureDetector(
                // 长按删除单条（CalmInputChip 自身只处理点按）。
                onLongPress: () => _deleteSingle(historyItem),
                child: CalmInputChip(
                  label: historyItem,
                  icon: Icons.history_rounded,
                  onTap: () {
                    HistoryWidget.cancelPendingKeywordSync();
                    onSearch(
                      context,
                      historyItem,
                      aggregateMode: widget.aggregateMode,
                    );
                  },
                ),
              ),
          ],
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

  /// 一键清空是批量破坏性操作：先经统一确认弹窗再执行。
  Future<void> _confirmResetHistory() async {
    final confirmed = await showCalmDialog<bool>(
      context,
      title: t.search.clearHistory,
      subtitle: t.search.history,
      icon: Icons.delete_sweep_rounded,
      tone: CalmTone.danger,
      bodyBuilder: (_) => Text(
        '${t.search.clearHistory}？',
        style: TextStyle(fontSize: 12, color: context.calm.text2, height: 1.5),
      ),
      actionsBuilder: (ctx) => [
        CalmButton(
          label: t.common.cancel,
          variant: CalmButtonVariant.ghost,
          onPressed: () => Navigator.of(ctx).pop(false),
        ),
        CalmButton(
          label: t.common.confirm,
          variant: CalmButtonVariant.danger,
          onPressed: () => Navigator.of(ctx).pop(true),
        ),
      ],
    );
    if (confirmed != true || !mounted) {
      return;
    }
    _resetHistory();
  }

  void _resetHistory() {
    final globalSettingCubit = context.read<GlobalSettingCubit>();
    globalSettingCubit.resetState(
      (current, defaults) =>
          current.copyWith(searchHistory: defaults.searchHistory),
    );
  }
}
