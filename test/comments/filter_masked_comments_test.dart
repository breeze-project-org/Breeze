import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/page/comments/method/filter_masked_comments.dart';
import 'package:zephyr/page/comments/model/comment_item.dart';

CommentItem _comment(
  String id,
  String content, {
  List<CommentItem> replies = const <CommentItem>[],
}) {
  return CommentItem(
    id: id,
    authorName: 'user',
    avatarUrl: '',
    avatarPath: '',
    content: content,
    createdAt: '',
    replyCount: replies.length,
    replies: replies,
    extern: const <String, dynamic>{},
  );
}

void main() {
  test('忽略大小写与空白，递归过滤楼中楼', () {
    final keywords = normalizeMaskedCommentKeywords(<String>[' usdt ', '']);

    final comments = <CommentItem>[
      _comment('1', 'USDT 广告', replies: <CommentItem>[_comment('1-1', '正常回复')]),
      _comment(
        '2',
        '正常评论',
        replies: <CommentItem>[
          _comment('2-1', '加V usdt 群'),
          _comment('2-2', '正常回复'),
        ],
      ),
      _comment('3', '普通评论'),
    ];

    final filtered = filterMaskedComments(comments, keywords);

    expect(filtered.map((item) => item.id), <String>['2', '3']);
    expect(filtered.first.replies.map((item) => item.id), <String>['2-2']);
  });

  test('没有屏蔽词时返回原列表', () {
    final comments = <CommentItem>[_comment('1', '任意内容')];

    expect(
      identical(filterMaskedComments(comments, const <String>[]), comments),
      isTrue,
    );
  });
}
