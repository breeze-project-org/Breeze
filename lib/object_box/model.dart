import 'dart:convert';

import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:zephyr/config/bika/bika_setting.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/config/jm/jm_setting.dart';
import 'package:zephyr/model/comic_info_meta.dart';
import 'package:zephyr/object_box/model_json_codec.dart';
import 'package:zephyr/service/download/models/download_task_json.dart';

part 'model.g.dart';

// SQLite 只把 JSON 列当 TEXT 存，模型侧不再需要为了 2048 长度限制把结构压成
// 字符串：cover/creator/titleMeta/metadata 等字段用 [ComicImage]/[Creator]/
// 列表表示，由 `model_json_codec.dart` 在读写边界与旧 JSON 字符串互转。
// `toJson()` 仍输出旧字符串格式，保证备份与云同步的向后兼容。

/// 旧版本数据/同步 payload 可能缺少后加的字段。日期统一回退到 epoch，
/// 其余字段用各实体 [fromJson] 里的默认 map 补齐；null 视为缺失。
const String _epochIso = '1970-01-01T00:00:00.000Z';

Map<String, dynamic> _withModelDefaults(
  Map<String, dynamic> json,
  Map<String, Object?> defaults,
) {
  final out = <String, dynamic>{...defaults};
  for (final entry in json.entries) {
    if (entry.value != null) out[entry.key] = entry.value;
  }
  return out;
}

@JsonSerializable()
@Deprecated("不再使用，仅作为迁移时作为参考数据结构")
class BikaComicHistory {
  int id;

  String comicId;
  String creatorId;
  String creatorGender;
  String creatorName;
  bool creatorVerified;
  int creatorExp;
  int creatorLevel;
  List<String> creatorCharacters;
  String creatorCharactersString;
  String creatorRole;
  String creatorTitle;
  String creatorAvatarOriginalName;
  String creatorAvatarPath;
  String creatorAvatarFileServer;
  String creatorSlogan;
  String title;
  String description;
  String thumbOriginalName;
  String thumbPath;
  String thumbFileServer;
  String author;
  String chineseTeam;
  List<String> categories;
  String categoriesString;
  List<String> tags;
  String tagsString;
  int pagesCount;
  int epsCount;
  bool finished;
  DateTime updatedAt;
  DateTime createdAt;
  bool allowDownload;
  bool allowComment;
  int totalLikes;
  int totalViews;
  int totalComments;
  int viewsCount;
  int likesCount;
  int commentsCount;
  bool isFavourite;
  bool isLiked;
  DateTime history;

  // 下面都是章节的观看历史信息
  int order;
  String epTitle;
  int epPageCount;
  String epId;

  bool deleted;

  BikaComicHistory({
    this.id = 0,
    required this.comicId,
    required this.creatorId,
    required this.creatorGender,
    required this.creatorName,
    required this.creatorVerified,
    required this.creatorExp,
    required this.creatorLevel,
    required this.creatorCharacters,
    required this.creatorCharactersString,
    required this.creatorRole,
    required this.creatorTitle,
    required this.creatorAvatarOriginalName,
    required this.creatorAvatarPath,
    required this.creatorAvatarFileServer,
    required this.creatorSlogan,
    required this.title,
    required this.description,
    required this.thumbOriginalName,
    required this.thumbPath,
    required this.thumbFileServer,
    required this.author,
    required this.chineseTeam,
    required this.categories,
    required this.categoriesString,
    required this.tags,
    required this.tagsString,
    required this.pagesCount,
    required this.epsCount,
    required this.finished,
    required this.updatedAt,
    required this.createdAt,
    required this.allowDownload,
    required this.allowComment,
    required this.totalLikes,
    required this.totalViews,
    required this.totalComments,
    required this.viewsCount,
    required this.likesCount,
    required this.commentsCount,
    required this.isFavourite,
    required this.isLiked,
    required this.history,
    required this.order,
    required this.epTitle,
    required this.epPageCount,
    required this.epId,
    required this.deleted,
  });

  Map<String, dynamic> toJson() => _$BikaComicHistoryToJson(this);

  // 实现 fromJson 方法
  factory BikaComicHistory.fromJson(Map<String, dynamic> json) =>
      _$BikaComicHistoryFromJson(json);

  @override
  String toString() {
    return jsonEncode(toJson());
  }
}

@JsonSerializable()
@Deprecated("不再使用，仅作为迁移时作为参考数据结构")
class BikaComicDownload {
  int id;

  String comicId;
  String creatorId;
  String creatorGender;
  String creatorName;
  bool creatorVerified;
  int creatorExp;
  int creatorLevel;
  List<String> creatorCharacters;
  String creatorCharactersString;
  String creatorRole;
  String creatorTitle;
  String creatorAvatarOriginalName;
  String creatorAvatarPath;
  String creatorAvatarFileServer;
  String creatorSlogan;
  String title;
  String description;
  String thumbOriginalName;
  String thumbPath;
  String thumbFileServer;
  String author;
  String chineseTeam;
  List<String> categories;
  String categoriesString;
  List<String> tags;
  String tagsString;
  int pagesCount;
  int epsCount;
  bool finished;
  DateTime updatedAt;
  DateTime createdAt;
  bool allowDownload;
  bool allowComment;
  int totalLikes;
  int totalViews;
  int totalComments;
  int viewsCount;
  int likesCount;
  int commentsCount;
  bool isFavourite;
  bool isLiked;
  DateTime downloadTime;

  // 这个用来放已经下载好的章节的标题，用来检测是否下载了
  List<String> epsTitle;

  // 这个用来放漫画的全部的信息，是一个json字符串
  String comicInfoAll;

  BikaComicDownload({
    this.id = 0,
    required this.comicId,
    required this.creatorId,
    required this.creatorGender,
    required this.creatorName,
    required this.creatorVerified,
    required this.creatorExp,
    required this.creatorLevel,
    required this.creatorCharacters,
    required this.creatorCharactersString,
    required this.creatorRole,
    required this.creatorTitle,
    required this.creatorAvatarOriginalName,
    required this.creatorAvatarPath,
    required this.creatorAvatarFileServer,
    required this.creatorSlogan,
    required this.title,
    required this.description,
    required this.thumbOriginalName,
    required this.thumbPath,
    required this.thumbFileServer,
    required this.author,
    required this.chineseTeam,
    required this.categories,
    required this.categoriesString,
    required this.tags,
    required this.tagsString,
    required this.pagesCount,
    required this.epsCount,
    required this.finished,
    required this.updatedAt,
    required this.createdAt,
    required this.allowDownload,
    required this.allowComment,
    required this.totalLikes,
    required this.totalViews,
    required this.totalComments,
    required this.viewsCount,
    required this.likesCount,
    required this.commentsCount,
    required this.isFavourite,
    required this.isLiked,
    required this.downloadTime,
    required this.epsTitle,
    required this.comicInfoAll,
  });

  Map<String, dynamic> toJson() => _$BikaComicDownloadToJson(this);

  factory BikaComicDownload.fromJson(Map<String, dynamic> json) =>
      _$BikaComicDownloadFromJson(json);

  @override
  String toString() {
    return jsonEncode(toJson());
  }
}

@JsonSerializable()
@Deprecated("不再使用，仅作为迁移时作为参考数据结构")
class JmFavorite {
  int id;

  String comicId;
  String name;
  String addtime;
  String description;
  String totalViews;
  String likes;
  String seriesId;
  String commentTotal;
  List<String> author;
  List<String> tags;
  List<String> works;
  List<String> actors;
  bool liked;
  bool isFavorite;
  bool isAids;
  String price;
  String purchased;

  bool deleted;
  DateTime history;

  JmFavorite({
    this.id = 0,
    required this.comicId,
    required this.name,
    required this.addtime,
    required this.description,
    required this.totalViews,
    required this.likes,
    required this.seriesId,
    required this.commentTotal,
    required this.author,
    required this.tags,
    required this.works,
    required this.actors,
    required this.liked,
    required this.isFavorite,
    required this.isAids,
    required this.price,
    required this.purchased,
    required this.deleted,
    required this.history,
  });

  Map<String, dynamic> toJson() => _$JmFavoriteToJson(this);

  factory JmFavorite.fromJson(Map<String, dynamic> json) =>
      _$JmFavoriteFromJson(json);

  @override
  String toString() {
    return jsonEncode(toJson());
  }
}

@JsonSerializable()
@Deprecated("不再使用，仅作为迁移时作为参考数据结构")
class JmHistory {
  int id;

  String comicId;
  String name;
  String addtime;
  String description;
  String totalViews;
  String likes;
  String seriesId;
  String commentTotal;
  List<String> author;
  List<String> tags;
  List<String> works;
  List<String> actors;
  bool liked;
  bool isFavorite;
  bool isAids;
  String price;
  String purchased;

  // 下面都是章节的观看历史信息
  int order;
  String epTitle;
  int epPageCount;
  String epId;

  bool deleted;
  DateTime history;

  JmHistory({
    this.id = 0,
    required this.comicId,
    required this.name,
    required this.addtime,
    required this.description,
    required this.totalViews,
    required this.likes,
    required this.seriesId,
    required this.commentTotal,
    required this.author,
    required this.tags,
    required this.works,
    required this.actors,
    required this.liked,
    required this.isFavorite,
    required this.isAids,
    required this.price,
    required this.purchased,
    required this.order,
    required this.epTitle,
    required this.epPageCount,
    required this.epId,
    required this.deleted,
    required this.history,
  });

  Map<String, dynamic> toJson() => _$JmHistoryToJson(this);

  factory JmHistory.fromJson(Map<String, dynamic> json) =>
      _$JmHistoryFromJson(json);

  @override
  String toString() {
    return jsonEncode(toJson());
  }
}

@JsonSerializable()
@Deprecated("不再使用，仅作为迁移时作为参考数据结构")
class JmDownload {
  int id;

  String comicId;
  String name;
  String addtime;
  String description;
  String totalViews;
  String likes;
  String seriesId;
  String commentTotal;
  List<String> author;
  List<String> tags;
  List<String> works;
  List<String> actors;
  bool liked;
  bool isFavorite;
  bool isAids;
  String price;
  String purchased;
  // 这个用来放已经下载好的章节的id，用来检测是否下载了
  List<String> epsIds;
  String allInfo;
  DateTime downloadTime;

  JmDownload({
    this.id = 0,
    required this.comicId,
    required this.name,
    required this.addtime,
    required this.description,
    required this.totalViews,
    required this.likes,
    required this.seriesId,
    required this.commentTotal,
    required this.author,
    required this.tags,
    required this.works,
    required this.actors,
    required this.liked,
    required this.isFavorite,
    required this.isAids,
    required this.price,
    required this.purchased,
    required this.epsIds,
    required this.allInfo,
    required this.downloadTime,
  });

  Map<String, dynamic> toJson() => _$JmDownloadToJson(this);

  factory JmDownload.fromJson(Map<String, dynamic> json) =>
      _$JmDownloadFromJson(json);

  @override
  String toString() {
    return jsonEncode(toJson());
  }
}

@JsonSerializable()
class UnifiedComicFavorite {
  int id;

  String uniqueKey;

  String source;
  String comicId;
  String title;
  String description;
  @JsonKey(fromJson: comicImageFromField, toJson: comicImageToField)
  ComicImage cover;
  @JsonKey(fromJson: creatorFromField, toJson: creatorToField)
  Creator creator;
  @JsonKey(fromJson: comicTitleMetaFromField, toJson: comicTitleMetaToField)
  List<ComicInfoActionItem> titleMeta;
  @JsonKey(fromJson: comicMetadataFromField, toJson: comicMetadataToField)
  List<ComicInfoMetadata> metadata;
  DateTime createdAt;
  DateTime updatedAt;
  bool deleted;
  int schemaVersion;

  UnifiedComicFavorite({
    this.id = 0,
    required this.uniqueKey,
    required this.source,
    required this.comicId,
    required this.title,
    required this.description,
    required this.cover,
    required this.creator,
    required this.titleMeta,
    required this.metadata,
    required this.createdAt,
    required this.updatedAt,
    required this.deleted,
    required this.schemaVersion,
  });

  Map<String, dynamic> toJson() => _$UnifiedComicFavoriteToJson(this);

  factory UnifiedComicFavorite.fromJson(Map<String, dynamic> json) =>
      _$UnifiedComicFavoriteFromJson(
        _withModelDefaults(json, const <String, Object?>{
          'id': 0,
          'uniqueKey': '',
          'source': '',
          'comicId': '',
          'title': '',
          'description': '',
          'cover': '',
          'creator': '',
          'titleMeta': '',
          'metadata': '',
          'createdAt': _epochIso,
          'updatedAt': _epochIso,
          'deleted': false,
          'schemaVersion': 0,
        }),
      );

  @override
  String toString() {
    return jsonEncode(toJson());
  }
}

@JsonSerializable()
class UnifiedComicHistory {
  int id;

  String uniqueKey;

  String source;
  String comicId;
  String title;
  String description;
  @JsonKey(fromJson: comicImageFromField, toJson: comicImageToField)
  ComicImage cover;
  @JsonKey(fromJson: creatorFromField, toJson: creatorToField)
  Creator creator;
  @JsonKey(fromJson: comicTitleMetaFromField, toJson: comicTitleMetaToField)
  List<ComicInfoActionItem> titleMeta;
  @JsonKey(fromJson: comicMetadataFromField, toJson: comicMetadataToField)
  List<ComicInfoMetadata> metadata;
  String chapterId;
  String chapterTitle;
  int chapterOrder;
  int pageIndex;
  DateTime createdAt;
  DateTime lastReadAt;
  DateTime updatedAt;
  bool deleted;
  int schemaVersion;

  UnifiedComicHistory({
    this.id = 0,
    required this.uniqueKey,
    required this.source,
    required this.comicId,
    required this.title,
    required this.description,
    required this.cover,
    required this.creator,
    required this.titleMeta,
    required this.metadata,
    required this.chapterId,
    required this.chapterTitle,
    required this.chapterOrder,
    required this.pageIndex,
    required this.createdAt,
    required this.lastReadAt,
    required this.updatedAt,
    required this.deleted,
    required this.schemaVersion,
  });

  Map<String, dynamic> toJson() => _$UnifiedComicHistoryToJson(this);

  factory UnifiedComicHistory.fromJson(Map<String, dynamic> json) =>
      _$UnifiedComicHistoryFromJson(
        _withModelDefaults(json, const <String, Object?>{
          'id': 0,
          'uniqueKey': '',
          'source': '',
          'comicId': '',
          'title': '',
          'description': '',
          'cover': '',
          'creator': '',
          'titleMeta': '',
          'metadata': '',
          'chapterId': '',
          'chapterTitle': '',
          'chapterOrder': 0,
          'pageIndex': 0,
          'createdAt': _epochIso,
          'lastReadAt': _epochIso,
          'updatedAt': _epochIso,
          'deleted': false,
          'schemaVersion': 0,
        }),
      );

  @override
  String toString() {
    return jsonEncode(toJson());
  }
}

@JsonSerializable()
class UnifiedComicDownload {
  int id;

  String uniqueKey;

  String source;
  String comicId;
  String title;
  String description;
  @JsonKey(fromJson: comicImageFromField, toJson: comicImageToField)
  ComicImage cover;
  @JsonKey(fromJson: creatorFromField, toJson: creatorToField)
  Creator creator;
  @JsonKey(fromJson: comicTitleMetaFromField, toJson: comicTitleMetaToField)
  List<ComicInfoActionItem> titleMeta;
  @JsonKey(fromJson: comicMetadataFromField, toJson: comicMetadataToField)
  List<ComicInfoMetadata> metadata;
  int totalViews;
  int totalLikes;
  int totalComments;
  bool isFavourite;
  bool isLiked;
  bool allowComment;
  bool allowLike;
  bool allowFavorite;
  bool allowDownload;
  String chapters;
  String detailJson;
  String storageRoot;
  DateTime createdAt;
  DateTime updatedAt;
  DateTime downloadedAt;
  bool deleted;
  int schemaVersion;

  /// 用户自定义标题；null/空表示未修改，[title] 为生效值。
  ///
  /// 下载保存只更新源站字段，不会清空本字段；读取方继续用 [title]，
  /// 因此书架/搜索/详情/导出无需感知 override。
  String? titleOverride;

  /// 用户自定义封面（`ComicImage` JSON）；null/空表示未修改。
  @JsonKey(fromJson: comicImageOrNullFromField, toJson: comicImageOrNullToField)
  ComicImage? coverOverride;

  UnifiedComicDownload({
    this.id = 0,
    required this.uniqueKey,
    required this.source,
    required this.comicId,
    required this.title,
    required this.description,
    required this.cover,
    required this.creator,
    required this.titleMeta,
    required this.metadata,
    required this.totalViews,
    required this.totalLikes,
    required this.totalComments,
    required this.isFavourite,
    required this.isLiked,
    required this.allowComment,
    required this.allowLike,
    required this.allowFavorite,
    required this.allowDownload,
    required this.chapters,
    required this.detailJson,
    required this.storageRoot,
    required this.createdAt,
    required this.updatedAt,
    required this.downloadedAt,
    required this.deleted,
    required this.schemaVersion,
    this.titleOverride,
    this.coverOverride,
  });

  Map<String, dynamic> toJson() => _$UnifiedComicDownloadToJson(this);

  factory UnifiedComicDownload.fromJson(Map<String, dynamic> json) =>
      _$UnifiedComicDownloadFromJson(
        _withModelDefaults(json, const <String, Object?>{
          'id': 0,
          'uniqueKey': '',
          'source': '',
          'comicId': '',
          'title': '',
          'description': '',
          'cover': '',
          'creator': '',
          'titleMeta': '',
          'metadata': '',
          'totalViews': 0,
          'totalLikes': 0,
          'totalComments': 0,
          'isFavourite': false,
          'isLiked': false,
          'allowComment': false,
          'allowLike': false,
          'allowFavorite': false,
          'allowDownload': false,
          'chapters': '',
          'detailJson': '',
          'storageRoot': '',
          'createdAt': _epochIso,
          'updatedAt': _epochIso,
          'downloadedAt': _epochIso,
          'deleted': false,
          'schemaVersion': 0,
        }),
      );

  @override
  String toString() {
    return jsonEncode(toJson());
  }
}

@JsonSerializable()
class UserSetting {
  int id;

  // 1. ObjectBox 存储字段 (String 类型)
  String? globalSettingData;
  String? bikaSettingData;
  String? jmSettingData;
  String jmJwt;

  // 2. 内存缓存字段 (@Transient)
  GlobalSettingState? _globalSetting;
  BikaSettingState? _bikaSetting;
  JmSettingState? _jmSetting;

  UserSetting({
    this.id = 0,
    this.globalSettingData,
    this.bikaSettingData,
    this.jmSettingData,
    this.jmJwt = '',
  });

  GlobalSettingState get globalSetting {
    if (_globalSetting == null && globalSettingData != null) {
      _globalSetting = GlobalSettingState.fromJson(
        jsonDecode(globalSettingData!),
      );
    }
    return _globalSetting ??= GlobalSettingState();
  }

  set globalSetting(GlobalSettingState value) {
    _globalSetting = value;
    globalSettingData = jsonEncode(value.toJson());
  }

  BikaSettingState get bikaSetting {
    if (_bikaSetting == null && bikaSettingData != null) {
      _bikaSetting = BikaSettingState.fromJson(jsonDecode(bikaSettingData!));
    }
    return _bikaSetting ??= BikaSettingState();
  }

  set bikaSetting(BikaSettingState value) {
    _bikaSetting = value;
    bikaSettingData = jsonEncode(value.toJson());
  }

  JmSettingState get jmSetting {
    if (_jmSetting == null && jmSettingData != null) {
      _jmSetting = JmSettingState.fromJson(jsonDecode(jmSettingData!));
    }
    return _jmSetting ??= JmSettingState();
  }

  set jmSetting(JmSettingState value) {
    _jmSetting = value;
    jmSettingData = jsonEncode(value.toJson());
  }

  Map<String, dynamic> toJson() => _$UserSettingToJson(this);

  factory UserSetting.fromJson(Map<String, dynamic> json) =>
      _$UserSettingFromJson(json);

  @override
  String toString() {
    return jsonEncode(toJson());
  }
}

@JsonSerializable()
class DownloadTask {
  DownloadTask();

  int id = 0;

  String comicId = "";

  String comicName = "";

  bool isCompleted = false;

  bool isDownloading = false;

  String status = "";

  /// 版本化任务 payload（检查点、章节引用等）。
  ///
  /// SQLite 列与旧备份仍使用 `dbTaskInfoStr` 的 JSON 字符串格式，
  /// 由 codec 在读写边界转换。
  @JsonKey(
    name: 'dbTaskInfoStr',
    fromJson: downloadTaskInfoFromField,
    toJson: downloadTaskInfoToField,
  )
  DownloadTaskJson? taskInfo;

  Map<String, dynamic> toJson() => _$DownloadTaskToJson(this);

  factory DownloadTask.fromJson(Map<String, dynamic> json) =>
      _$DownloadTaskFromJson(json);

  @override
  String toString() {
    return jsonEncode(toJson());
  }
}

@JsonSerializable()
class PluginConfig {
  int id;

  String name;

  String config;

  PluginConfig({this.id = 0, required this.name, required this.config});

  Map<String, dynamic> toJson() => _$PluginConfigToJson(this);

  factory PluginConfig.fromJson(Map<String, dynamic> json) =>
      _$PluginConfigFromJson(json);

  @override
  String toString() {
    return jsonEncode(toJson());
  }
}

@JsonSerializable()
class PluginInfo {
  int id = 0;

  String uuid;

  String version;

  /// 插件脚本。PluginInfo 表不存这一列：
  /// 默认查询返回空串，只有安装/同步/备份或显式 with-script 查询才填充。
  String originScript;

  /// 脚本内容的最后变更时间（Unix 毫秒）。
  ///
  /// 随 with-script 查询返回，同步时用于单独判断脚本新旧：
  /// 插件加载结果会刷新 [updatedAt]，不能让“加载得晚”覆盖更新的脚本。
  int scriptUpdatedAt;

  bool lastLoadSuccess;

  String? lastLoadError;

  DateTime insertedAt;

  DateTime updatedAt;

  bool isEnabled;

  bool isDeleted;

  DateTime? deletedAt;

  /// 用户自定义的插件顺序；为空时回退到 [insertedAt]。
  int? sortOrder;

  bool debug = false;

  String? debugUrl;

  /// getInfo 返回的完整 JSON 字符串缓存（用于更新通道 npmName / updateUrl 等）。
  String getInfoJson;

  PluginInfo({
    this.id = 0,
    required this.uuid,
    required this.version,
    required this.originScript,
    this.scriptUpdatedAt = 0,
    required this.insertedAt,
    required this.updatedAt,
    required this.isEnabled,
    required this.isDeleted,
    this.deletedAt,
    required this.lastLoadSuccess,
    this.lastLoadError,
    this.sortOrder,
    required this.debug,
    this.debugUrl,
    this.getInfoJson = '',
  });

  Map<String, dynamic> toJson() => _$PluginInfoToJson(this);

  factory PluginInfo.fromJson(Map<String, dynamic> json) =>
      _$PluginInfoFromJson(
        _withModelDefaults(json, const <String, Object?>{
          'id': 0,
          'uuid': '',
          'version': '',
          'insertedAt': _epochIso,
          'updatedAt': _epochIso,
          'isEnabled': false,
          'isDeleted': false,
          'lastLoadSuccess': false,
          'originScript': '',
          'scriptUpdatedAt': 0,
          'getInfoJson': '',
          'debug': false,
        }),
      );

  @override
  String toString() {
    return jsonEncode(toJson());
  }
}

@JsonSerializable()
class ComicFollow {
  int id;

  String uniqueKey;

  String source;
  String comicId;
  String title;
  String description;
  @JsonKey(fromJson: comicImageFromField, toJson: comicImageToField)
  ComicImage cover;
  @JsonKey(fromJson: creatorFromField, toJson: creatorToField)
  Creator creator;
  @JsonKey(fromJson: comicTitleMetaFromField, toJson: comicTitleMetaToField)
  List<ComicInfoActionItem> titleMeta;
  @JsonKey(fromJson: comicMetadataFromField, toJson: comicMetadataToField)
  List<ComicInfoMetadata> metadata;

  /// 上次进入漫画 / 加入追更时的章节数
  int lastChapterCount;

  /// 检测到的最新章节数
  int detectedChapterCount;

  /// 检测到的最新章节名称
  String detectedChapterTitle;

  /// 是否有更新
  bool hasUpdate;

  /// 最近一次检测是否失败（仅内存，不持久化）
  @JsonKey(includeFromJson: false, includeToJson: false)
  bool lastCheckFailed;

  DateTime updateTime;

  bool deleted;

  DateTime createdAt;

  DateTime updatedAt;

  int schemaVersion;

  ComicFollow({
    this.id = 0,
    required this.uniqueKey,
    required this.source,
    required this.comicId,
    required this.title,
    required this.description,
    required this.cover,
    required this.creator,
    required this.titleMeta,
    required this.metadata,
    required this.lastChapterCount,
    required this.detectedChapterCount,
    this.detectedChapterTitle = '',
    required this.hasUpdate,
    this.lastCheckFailed = false,
    required this.updateTime,
    required this.deleted,
    required this.createdAt,
    required this.updatedAt,
    required this.schemaVersion,
  });

  ComicFollow copyWith({
    int? id,
    String? uniqueKey,
    String? source,
    String? comicId,
    String? title,
    String? description,
    ComicImage? cover,
    Creator? creator,
    List<ComicInfoActionItem>? titleMeta,
    List<ComicInfoMetadata>? metadata,
    int? lastChapterCount,
    int? detectedChapterCount,
    String? detectedChapterTitle,
    bool? hasUpdate,
    bool? lastCheckFailed,
    DateTime? updateTime,
    bool? deleted,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? schemaVersion,
  }) {
    return ComicFollow(
      id: id ?? this.id,
      uniqueKey: uniqueKey ?? this.uniqueKey,
      source: source ?? this.source,
      comicId: comicId ?? this.comicId,
      title: title ?? this.title,
      description: description ?? this.description,
      cover: cover ?? this.cover,
      creator: creator ?? this.creator,
      titleMeta: titleMeta ?? this.titleMeta,
      metadata: metadata ?? this.metadata,
      lastChapterCount: lastChapterCount ?? this.lastChapterCount,
      detectedChapterCount: detectedChapterCount ?? this.detectedChapterCount,
      detectedChapterTitle: detectedChapterTitle ?? this.detectedChapterTitle,
      hasUpdate: hasUpdate ?? this.hasUpdate,
      lastCheckFailed: lastCheckFailed ?? this.lastCheckFailed,
      updateTime: updateTime ?? this.updateTime,
      deleted: deleted ?? this.deleted,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      schemaVersion: schemaVersion ?? this.schemaVersion,
    );
  }

  Map<String, dynamic> toJson() => _$ComicFollowToJson(this);

  factory ComicFollow.fromJson(Map<String, dynamic> json) =>
      _$ComicFollowFromJson(
        _withModelDefaults(json, const <String, Object?>{
          'id': 0,
          'uniqueKey': '',
          'source': '',
          'comicId': '',
          'title': '',
          'description': '',
          'cover': '',
          'creator': '',
          'titleMeta': '',
          'metadata': '',
          'lastChapterCount': 0,
          'detectedChapterCount': 0,
          'detectedChapterTitle': '',
          'hasUpdate': false,
          'updateTime': _epochIso,
          'deleted': false,
          'createdAt': _epochIso,
          'updatedAt': _epochIso,
          'schemaVersion': 0,
        }),
      );

  @override
  String toString() {
    return jsonEncode(toJson());
  }
}

/// 漫画文件夹/链接类型：收藏、历史、下载
enum ComicFolderType { favorite, history, download }

@JsonSerializable()
class ComicFolder {
  int id;

  /// 全局稳定同步 ID，创建后不变，跨设备同步时使用。
  @JsonKey(defaultValue: '')
  String syncId;

  /// 父文件夹的 syncId，null 表示根目录
  String? parentSyncId;

  /// 复合唯一键：parentSyncId|name|typeData
  String uniqueKey;

  /// 显示名称
  String name;

  /// 实际存储的枚举名称：favorite / history / download
  String typeData;

  @JsonKey(includeFromJson: false, includeToJson: false)
  ComicFolderType get type => ComicFolderType.values.byName(typeData);

  set type(ComicFolderType value) => typeData = value.name;

  /// 版本向量：`{deviceId: counter}`，用于并发冲突裁决。
  @JsonKey(
    name: 'versionVectorJson',
    fromJson: versionVectorFromField,
    toJson: versionVectorToField,
  )
  Map<String, int> versionVector;

  /// 软删除时间戳（毫秒），null 表示未删除
  int? deletedAt;

  /// 创建时间戳（毫秒）
  int createdAt;

  /// 最后修改时间戳（毫秒）
  int updatedAt;

  /// 用户指定封面漫画的 uniqueKey（`source:comicId`）。
  ///
  /// null / 空表示自动取文件夹里最新加入的漫画封面。
  String? coverComicUniqueKey;

  ComicFolder({
    this.id = 0,
    required this.syncId,
    this.parentSyncId,
    required this.uniqueKey,
    required this.name,
    required this.typeData,
    required this.versionVector,
    this.deletedAt,
    required this.createdAt,
    required this.updatedAt,
    this.coverComicUniqueKey,
  });

  Map<String, dynamic> toJson() => _$ComicFolderToJson(this);

  factory ComicFolder.fromJson(Map<String, dynamic> json) =>
      _$ComicFolderFromJson(
        _withModelDefaults(json, const <String, Object?>{
          'id': 0,
          'syncId': '',
          'uniqueKey': '',
          'name': '',
          'typeData': '',
          'versionVectorJson': '',
          'createdAt': 0,
          'updatedAt': 0,
        }),
      );

  @override
  String toString() {
    return jsonEncode(toJson());
  }
}

@JsonSerializable()
class ComicLink {
  int id;

  /// 复合唯一键：comicUniqueKey|folderSyncId|typeData
  String uniqueKey;

  /// 漫画全局唯一标识（如 UnifiedComicFavorite 的 uniqueKey）
  String comicUniqueKey;

  /// 所属文件夹的 syncId，null 表示根目录
  String? folderSyncId;

  /// 实际存储的枚举名称：favorite / history / download
  String typeData;

  @JsonKey(includeFromJson: false, includeToJson: false)
  ComicFolderType get type => ComicFolderType.values.byName(typeData);

  set type(ComicFolderType value) => typeData = value.name;

  /// 版本向量：`{deviceId: counter}`，用于并发冲突裁决。
  @JsonKey(
    name: 'versionVectorJson',
    fromJson: versionVectorFromField,
    toJson: versionVectorToField,
  )
  Map<String, int> versionVector;

  /// 软删除时间戳（毫秒），null 表示未删除
  int? deletedAt;

  /// 创建时间戳（毫秒）
  int createdAt;

  /// 最后修改时间戳（毫秒）
  int updatedAt;

  ComicLink({
    this.id = 0,
    required this.uniqueKey,
    required this.comicUniqueKey,
    this.folderSyncId,
    required this.typeData,
    required this.versionVector,
    this.deletedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => _$ComicLinkToJson(this);

  factory ComicLink.fromJson(Map<String, dynamic> json) => _$ComicLinkFromJson(
    _withModelDefaults(json, const <String, Object?>{
      'id': 0,
      'uniqueKey': '',
      'comicUniqueKey': '',
      'typeData': '',
      'versionVectorJson': '',
      'createdAt': 0,
      'updatedAt': 0,
    }),
  );

  @override
  String toString() {
    return jsonEncode(toJson());
  }
}

/// 单本漫画独立阅读设置（稀疏 patch，与全局共用一套 JSON 结构）。
///
/// [overrides] 只存用户显式改过的键（如 `{"readMode":2}`），键名与
/// `ReadSettingState.toJson()` 对齐；没有 key = 没设置 = 跟随全局。
/// 有记录且 [deleted] 为 false 表示启用了本漫特定设置；
/// 删除时清空 patch 并立 [deleted] 墓碑，靠 LWW 同步到其它设备。
/// 合并规则：unix 时间戳（[updatedAt]）更大的保留，与收藏/历史同一套 LWW。
@JsonSerializable()
class ComicReadPreference {
  int id;

  /// 复合唯一键：`$source:$comicId`，与历史/收藏保持一致。
  String uniqueKey;

  String source;
  String comicId;

  /// 本漫独立设置：与全局共用一套 `ReadSettingState` 结构。
  ///
  /// 列里只存用户显式改过的键（稀疏，如 `{"readMode":2}`）；
  /// 返回 null 表示没有覆盖 = 跟随全局（含墓碑行）。
  @JsonKey(
    name: 'overridesJson',
    fromJson: jsonObjectFromField,
    toJson: jsonObjectToField,
  )
  Map<String, dynamic> overrides;

  /// v12 前的单字段存储，已被 [overrides] 取代。
  ///
  /// 保留该列仅用于 v11→v12 存量迁移读取，读写一律走 [overrides]；
  /// 存量转完后的版本可删除此列。
  @Deprecated('由 overrides 取代，仅迁移读取使用')
  @JsonKey(includeToJson: false)
  int readMode;

  DateTime updatedAt;

  bool deleted;

  ComicReadPreference({
    this.id = 0,
    required this.uniqueKey,
    required this.source,
    required this.comicId,
    this.overrides = const <String, dynamic>{},
    @Deprecated('由 overrides 取代，仅迁移读取使用') this.readMode = 0,
    required this.updatedAt,
    this.deleted = false,
  });

  /// 本漫独立设置：与全局共用一套 `ReadSettingState` 结构。
  ///
  /// 列里只存用户显式改过的键（稀疏，如 `{"readMode":2}`）；
  /// 返回 null 表示没有覆盖 = 跟随全局（含墓碑行）。
  /// record 的 `keys` 是精确的 key 集合：“有没有设置”看它，不看值。
  /// 脏数据兜底：解析失败返回 null。
  @JsonKey(includeFromJson: false, includeToJson: false)
  ({ReadSettingState setting, Set<String> keys})? get overrideSetting {
    if (deleted) return null;
    final patch = _readOverridePatch();
    if (patch.isEmpty) return null;
    try {
      return (
        setting: ReadSettingState.fromJson(patch),
        keys: patch.keys.toSet(),
      );
    } catch (_) {
      return null;
    }
  }

  /// 用 [updated] 相对 [current] 的变化更新本列，返回实际变化的 key。
  ///
  /// [includeKeys] 强制记录的键（即使值没变，如首次快照 readMode）。
  /// 只改列内容，不碰 `updatedAt`，落盘由调用方 `box.put`。
  Set<String> applyChanges(
    ReadSettingState current,
    ReadSettingState updated, {
    Set<String> includeKeys = const {},
  }) {
    final before = current.toJson();
    final after = updated.toJson();
    final delta = <String, dynamic>{};
    for (final key in after.keys) {
      if (before[key] != after[key]) delta[key] = after[key];
    }
    for (final key in includeKeys) {
      if (after.containsKey(key)) delta[key] = after[key];
    }
    if (delta.isEmpty) return const {};
    final patch = Map<String, dynamic>.of(_readOverridePatch())
      ..addAll(_sanitizeOverridePatch(delta));
    overrides = patch;
    return delta.keys.toSet();
  }

  /// 解析并清洗后的 patch（内部用）。
  Map<String, dynamic> _readOverridePatch() =>
      _sanitizeOverridePatch(overrides);

  Map<String, dynamic> toJson() => _$ComicReadPreferenceToJson(this);

  /// 兼容 v11 及更早：老数据只有 `readMode` 整列，转成 `{"readMode":x}` patch。
  /// 缺 `readMode` 时（新版备份/同步）补 0，生成的 `fromJson` 才能安全解析。
  factory ComicReadPreference.fromJson(Map<String, dynamic> json) {
    json = Map.of(
      _withModelDefaults(json, const <String, Object?>{
        'id': 0,
        'uniqueKey': '',
        'source': '',
        'comicId': '',
        'readMode': 0,
        'updatedAt': _epochIso,
        'deleted': false,
      }),
    );
    if (!json.containsKey('overridesJson') && json['readMode'] is num) {
      json['overridesJson'] = jsonEncode({
        'readMode': (json['readMode'] as num).toInt().clamp(0, 2),
      });
    }
    json['overridesJson'] ??= '{}';
    return _$ComicReadPreferenceFromJson(json);
  }

  @override
  String toString() {
    return jsonEncode(toJson());
  }
}

/// 搜索书签：记录一次搜索现场 + 锚点漫画，跳转时参数重放直达记录页。
///
/// 不做排序键提取、不做定位探测，无需插件声明：快照只是搜索参数重放。
/// [uniqueKey] 复合唯一：`$source|$keyword|$anchorComicId`。
@JsonSerializable()
class SearchBookmark {
  int id;

  String uniqueKey;

  /// 插件 uuid。
  String source;

  /// 搜索关键词（trim 后）。
  String keyword;

  /// 记录时的完整搜索 extern（含分类筛选等，排序也在里面）。
  @JsonKey(
    name: 'externJson',
    fromJson: searchBookmarkExternFromField,
    toJson: searchBookmarkExternToField,
  )
  Map<String, dynamic> extern;

  /// 锚点漫画 id。
  String anchorComicId;

  /// 锚点漫画标题（列表展示用）。
  String anchorTitle;

  /// 锚点漫画封面（ComicImage JSON，可空）。
  @JsonKey(
    fromJson: comicImageOrNullFromField,
    toJson: searchBookmarkCoverToField,
  )
  ComicImage? anchorCover;

  /// 记录时锚点所在的页码（跳转目标）。
  int anchorPage;

  /// 记录时锚点在页内的序号（从 0 起，用于精确定位）。
  /// 老数据缺省为 0，揭示时回退 id 查找。
  @JsonKey(defaultValue: 0)
  int anchorIndex;

  DateTime createdAt;

  DateTime updatedAt;

  SearchBookmark({
    this.id = 0,
    required this.uniqueKey,
    required this.source,
    required this.keyword,
    this.extern = const <String, dynamic>{},
    required this.anchorComicId,
    required this.anchorTitle,
    this.anchorCover,
    required this.anchorPage,
    this.anchorIndex = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => _$SearchBookmarkToJson(this);

  factory SearchBookmark.fromJson(Map<String, dynamic> json) =>
      _$SearchBookmarkFromJson(
        _withModelDefaults(json, const <String, Object?>{
          'id': 0,
          'uniqueKey': '',
          'source': '',
          'keyword': '',
          'externJson': '',
          'anchorComicId': '',
          'anchorTitle': '',
          'anchorCover': '',
          'anchorPage': 0,
          'anchorIndex': 0,
          'createdAt': _epochIso,
          'updatedAt': _epochIso,
        }),
      );

  @override
  String toString() {
    return jsonEncode(toJson());
  }
}

/// 搜索书签复合唯一键：`$source|$keyword|$anchorComicId`。
String searchBookmarkUniqueKey(
  String source,
  String keyword,
  String anchorComicId,
) {
  return '${source.trim()}|${keyword.trim()}|${anchorComicId.trim()}';
}

/// 已读章节记录：详情页据此把读过的章节置灰。
///
/// 只记录“打开过阅读器”的章节，不做进度百分比；[uniqueKey] 复合唯一：
/// `$source:$comicId:$chapterId`，同一章重复打开只更新 [readAt]。
/// 参与云同步（同一章按 [updatedAt] 新覆盖旧），并随数据备份导出/导入。
@JsonSerializable()
class ComicReadChapter {
  int id;

  String uniqueKey;

  /// 插件 uuid。
  String source;

  /// 漫画 id。
  String comicId;

  /// 章节宿主内部匹配 key（与详情页 [DownloadChapter.id] / 阅读器 epId 一致）。
  String chapterId;

  /// 章节标题快照，便于调试/后续展示。
  String chapterTitle;

  /// 章节顺序快照。
  int chapterOrder;

  DateTime readAt;

  DateTime updatedAt;

  ComicReadChapter({
    this.id = 0,
    required this.uniqueKey,
    required this.source,
    required this.comicId,
    required this.chapterId,
    required this.chapterTitle,
    required this.chapterOrder,
    required this.readAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => _$ComicReadChapterToJson(this);

  factory ComicReadChapter.fromJson(Map<String, dynamic> json) =>
      _$ComicReadChapterFromJson(
        _withModelDefaults(json, const <String, Object?>{
          'id': 0,
          'uniqueKey': '',
          'source': '',
          'comicId': '',
          'chapterId': '',
          'chapterTitle': '',
          'chapterOrder': 0,
          'readAt': _epochIso,
          'updatedAt': _epochIso,
        }),
      );

  @override
  String toString() {
    return jsonEncode(toJson());
  }
}

/// 已读章节复合唯一键：`$source:$comicId:$chapterId`。
String comicReadChapterUniqueKey(
  String source,
  String comicId,
  String chapterId,
) {
  return '${source.trim()}:${comicId.trim()}:${chapterId.trim()}';
}

/// 只保留 `ReadSettingState` 认识的 key，脏 key（旧版本残留/手改）直接丢弃。
///
/// 白名单与类型都从 `ReadSettingState` 自身派生：以后加字段零改动，
/// 类型按默认值的运行时类型校验（`readMode` 额外钳到 0~2）。
Map<String, dynamic> sanitizeReadSettingPatch(Map<String, dynamic> patch) {
  if (patch.isEmpty) return const {};
  final defaults = const ReadSettingState().toJson();
  final clean = <String, dynamic>{};
  for (final entry in patch.entries) {
    final key = entry.key;
    if (!defaults.containsKey(key)) continue;
    final value = entry.value;
    final fallback = defaults[key];
    if (fallback is bool && value is bool) {
      clean[key] = value;
    } else if (fallback is int && value is num) {
      clean[key] = key == 'readMode'
          ? value.toInt().clamp(0, 2)
          : value.toInt();
    } else if (fallback is String && value is String) {
      clean[key] = value;
    }
  }
  return clean;
}

/// Entity 内部复用（同库私有）：与 [sanitizeReadSettingPatch] 同一实现。
Map<String, dynamic> _sanitizeOverridePatch(Map<String, dynamic> patch) =>
    sanitizeReadSettingPatch(patch);
