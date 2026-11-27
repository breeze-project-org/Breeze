import 'package:zephyr/util/text/chinese_convert.dart';

/// 搜索历史匹配用的归一化：忽略大小写，并做繁简无关转换。
String normalizeSearchHistoryText(String text) =>
    t2s(text.trim().toLowerCase());

/// 批量归一化历史记录；调用方可按列表身份缓存结果，避免每次输入都走 t2s。
List<String> normalizeSearchHistory(List<String> history) =>
    history.map(normalizeSearchHistoryText).toList();

/// 按当前输入过滤搜索历史。
///
/// - 空关键词返回原列表。
/// - 子串匹配，忽略大小写与繁简差异。
/// - 前缀命中排在其它子串命中之前；同一优先级内保持 [history] 的顺序。
///
/// [normalizedHistory] 必须是 [history] 经 [normalizeSearchHistory] 处理后的
/// 同序结果，长度不一致时会忽略并重新计算。
List<String> filterSearchHistory(
  List<String> history,
  String keyword, {
  List<String>? normalizedHistory,
}) {
  final query = normalizeSearchHistoryText(keyword);
  if (query.isEmpty || history.isEmpty) {
    return history;
  }

  final normalized =
      normalizedHistory != null && normalizedHistory.length == history.length
      ? normalizedHistory
      : normalizeSearchHistory(history);

  final prefixMatches = <String>[];
  final otherMatches = <String>[];
  for (var index = 0; index < history.length; index++) {
    final text = normalized[index];
    if (text.startsWith(query)) {
      prefixMatches.add(history[index]);
    } else if (text.contains(query)) {
      otherMatches.add(history[index]);
    }
  }
  return <String>[...prefixMatches, ...otherMatches];
}
