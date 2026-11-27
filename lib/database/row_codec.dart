import 'dart:convert';

/// SQLite 行的基础类型转换。
///
/// 数据库里 date 存 Unix 毫秒整数、bool 存 0/1、字符串列表存 JSON 文本；
/// `model.dart` 的 `fromJson` 仍按 ISO 字符串/List 读取，所以仓库层在
/// 调用 `fromJson` 之前用这些函数把行还原成模型 JSON 的形状。
DateTime? dateFromDb(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  final ms = (value as num).toInt();
  if (ms == 0) return null;
  return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
}

String dateIsoFromDb(Object? value) {
  final date =
      dateFromDb(value) ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  return date.toIso8601String();
}

String? nullableDateIsoFromDb(Object? value) =>
    dateFromDb(value)?.toIso8601String();

int? dateToDb(DateTime? value) => value?.toUtc().millisecondsSinceEpoch;

bool boolFromDb(Object? value) => value == true || (value is num && value != 0);

int boolToDb(bool value) => value ? 1 : 0;

List<String> stringListFromDb(Object? value) {
  if (value == null) return const <String>[];
  if (value is List) return value.map((e) => e.toString()).toList();
  final text = value.toString();
  if (text.isEmpty) return const <String>[];
  final decoded = jsonDecode(text);
  if (decoded is! List) return const <String>[];
  return decoded.map((e) => e.toString()).toList();
}

String stringListToDb(List<String> value) => jsonEncode(value);

/// 把 SQLite 行中的 date/bool/list 列还原成 `fromJson` 需要的形状。
Map<String, dynamic> normalizeRow(
  Map<String, dynamic> row, {
  Set<String> dates = const <String>{},
  Set<String> nullableDates = const <String>{},
  Set<String> bools = const <String>{},
  Set<String> stringLists = const <String>{},
}) {
  final out = Map<String, dynamic>.from(row);
  for (final field in dates) {
    if (out.containsKey(field)) out[field] = dateIsoFromDb(out[field]);
  }
  for (final field in nullableDates) {
    if (out.containsKey(field)) out[field] = nullableDateIsoFromDb(out[field]);
  }
  for (final field in bools) {
    if (out.containsKey(field)) out[field] = boolFromDb(out[field]);
  }
  for (final field in stringLists) {
    if (out.containsKey(field)) out[field] = stringListFromDb(out[field]);
  }
  return out;
}

Map<String, dynamic> withDefaultId(Map<String, dynamic> row) {
  row['id'] ??= 0;
  return row;
}

/// `SELECT "uniqueKey" ...` 的行解码：只回传键，不解码整行。
List<String> uniqueKeysFromRows(List<Map<String, dynamic>> rows) =>
    <String>[for (final row in rows) row['uniqueKey'] as String];
