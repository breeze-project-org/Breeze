import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:zephyr/main.dart';
import 'package:zephyr/util/ohos/platform.dart';
import 'package:zephyr/util/ohos/notification.dart';
import 'package:zephyr/object_box/model.dart';
import 'package:zephyr/page/comic_info/method/get_plugin_detail.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/widgets/toast.dart';

const _kMaxRetryCount = 3;
const _kComicUpdateChannelId = 'comic_update_channel';
final _kComicUpdateChannelName = t.comicFollow.updateChannelName;
final _kComicUpdateChannelDesc = t.comicFollow.updateChannelDesc;

class ComicFollowDetection {
  const ComicFollowDetection({
    required this.chapterCount,
    required this.latestChapterTitle,
  });

  final int chapterCount;
  final String latestChapterTitle;
}

class ComicFollowService {
  static final ComicFollowService instance = ComicFollowService._();

  ComicFollowService._();

  String uniqueKey(String source, String comicId) {
    return '${source.trim()}:${comicId.trim()}';
  }

  /// 保存或更新追更记录（直接写入数据库）
  Future<void> putFollow(ComicFollow follow) async {
    // uniqueKey 有唯一约束：新对象若与已有记录同 key，先复用已有 ID，
    // 否则 put 会插入新行并触发唯一约束冲突。
    if (follow.id == 0) {
      final existing = await getFollowByUniqueKey(follow.uniqueKey);
      if (existing != null) {
        follow.id = existing.id;
      }
    }
    await database.follows.put(follow);
  }

  /// 查询全部未删除的追更记录
  Future<List<ComicFollow>> listActiveFollows() async =>
      database.follows.listActive();

  /// 查询未删除的阅读历史，供追更页关联阅读进度和最后阅读时间。
  Future<Map<String, UnifiedComicHistory>> listActiveHistories() async {
    final histories = await database.histories.listActiveInWorker();
    return {for (final history in histories) history.uniqueKey: history};
  }

  /// 按 uniqueKey 查询追更记录（包含已删除的），用于更新或复活旧记录
  Future<ComicFollow?> getFollowByUniqueKey(String uniqueKey) =>
      database.follows.getByKey(uniqueKey);

  /// 检测单部漫画的当前章节，失败时返回 null，最多重试 3 次
  Future<ComicFollowDetection?> detectChapter(ComicFollow follow) async {
    for (var attempt = 0; attempt < _kMaxRetryCount; attempt++) {
      try {
        final result = await getComicDetailByPlugin(
          follow.comicId,
          follow.source,
        );
        final eps = result.normalInfo.eps;
        final latest = eps.isEmpty
            ? null
            : eps.reduce(
                (left, right) => left.order >= right.order ? left : right,
              );
        return ComicFollowDetection(
          chapterCount: eps.length,
          latestChapterTitle: latest == null ? '' : latest.name,
        );
      } catch (e, s) {
        logger.w(
          '追更检测失败 ${follow.source}:${follow.comicId} (attempt ${attempt + 1}/$_kMaxRetryCount)',
          error: e,
          stackTrace: s,
        );
        if (attempt < _kMaxRetryCount - 1) {
          await Future.delayed(const Duration(seconds: 1));
        }
      }
    }
    return null;
  }

  /// 发送更新通知与应用内提示
  Future<void> notifyUpdate(int updateCount) async {
    final title = t.comicFollow.updateTitle;
    final body = updateCount == 1
        ? t.comicFollow.updatedComicsSingle
        : t.comicFollow.updatedComicsMultiple(count: updateCount);

    try {
      final id = DateTime.now().millisecondsSinceEpoch % 2147483647;
      if (isOhos) {
        await publishOhosNotification(id: id, title: title, body: body);
      } else {
        await flutterLocalNotificationsPlugin.show(
          id: id,
          title: title,
          body: body,
          notificationDetails: _notificationDetails(),
        );
      }
    } catch (e, s) {
      logger.e('追更通知发送失败', error: e, stackTrace: s);
    }

    try {
      eventBus.fire(
        ToastEvent(
          type: ToastType.info,
          title: title,
          message: body,
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e, s) {
      logger.e('追更 Toast 发送失败', error: e, stackTrace: s);
    }
  }

  NotificationDetails _notificationDetails() {
    final androidDetails = AndroidNotificationDetails(
      _kComicUpdateChannelId,
      _kComicUpdateChannelName,
      channelDescription: _kComicUpdateChannelDesc,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );
    const darwinDetails = DarwinNotificationDetails();
    final linuxDetails = LinuxNotificationDetails(
      urgency: LinuxNotificationUrgency.normal,
    );
    const windowsDetails = WindowsNotificationDetails();
    return NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
      linux: linuxDetails,
      windows: windowsDetails,
    );
  }
}
