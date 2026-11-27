import 'package:zephyr/page/comments/model/comment_item.dart';
import 'package:zephyr/util/text/chinese_convert.dart';

/// 把评论屏蔽词统一成小写简体，去掉空白词和重复词。
///
/// 与搜索屏蔽词一致：忽略大小写，并做繁简无关匹配。
List<String> normalizeMaskedCommentKeywords(Iterable<String> keywords) {
  return keywords
      .map((keyword) => keyword.trim())
      .where((keyword) => keyword.isNotEmpty)
      .map(_normalizeMaskedText)
      .where((keyword) => keyword.isNotEmpty)
      .toSet()
      .toList();
}

/// 过滤正文命中屏蔽词的评论，并递归过滤楼中楼。
///
/// [maskedKeywords] 必须是 [normalizeMaskedCommentKeywords] 处理过的结果。
List<CommentItem> filterMaskedComments(
  List<CommentItem> comments,
  List<String> maskedKeywords,
) {
  if (comments.isEmpty || maskedKeywords.isEmpty) {
    return comments;
  }

  final visible = <CommentItem>[];
  for (final comment in comments) {
    if (_isMasked(comment.content, maskedKeywords)) {
      continue;
    }
    final replies = filterMaskedComments(comment.replies, maskedKeywords);
    visible.add(
      identical(replies, comment.replies)
          ? comment
          : comment.copyWith(replies: replies),
    );
  }
  return visible;
}

bool _isMasked(String content, List<String> maskedKeywords) {
  final normalized = _normalizeMaskedText(content);
  return maskedKeywords.any(normalized.contains);
}

String _normalizeMaskedText(String text) => t2s(text.toLowerCase());
