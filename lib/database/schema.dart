/// 初始 SQLite schema（v1），全部为显式 SQL。
///
/// 不使用 schema 反射/ORM；新增字段和索引直接改这里，并用下方版本号控制迁移。
const String databaseSchemaSql = r'''
-- 初始 SQLite schema（v1）。全部为显式 SQL，没有运行时 schema 反射。
CREATE TABLE IF NOT EXISTS app_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);

CREATE TABLE IF NOT EXISTS "BikaComicHistory" (
  "id" INTEGER PRIMARY KEY AUTOINCREMENT,
  "updatedAt" INTEGER NOT NULL DEFAULT 0,
  "thumbOriginalName" TEXT NOT NULL DEFAULT '',
  "thumbPath" TEXT NOT NULL DEFAULT '',
  "thumbFileServer" TEXT NOT NULL DEFAULT '',
  "author" TEXT NOT NULL DEFAULT '',
  "description" TEXT NOT NULL DEFAULT '',
  "chineseTeam" TEXT NOT NULL DEFAULT '',
  "createdAt" INTEGER NOT NULL DEFAULT 0,
  "finished" INTEGER NOT NULL DEFAULT 0,
  "categories" TEXT NOT NULL DEFAULT '[]',
  "title" TEXT NOT NULL DEFAULT '',
  "tags" TEXT NOT NULL DEFAULT '[]',
  "comicId" TEXT NOT NULL DEFAULT '',
  "likesCount" INTEGER NOT NULL DEFAULT 0,
  "history" INTEGER NOT NULL DEFAULT 0,
  "creatorId" TEXT NOT NULL DEFAULT '',
  "creatorGender" TEXT NOT NULL DEFAULT '',
  "creatorName" TEXT NOT NULL DEFAULT '',
  "creatorVerified" INTEGER NOT NULL DEFAULT 0,
  "creatorExp" INTEGER NOT NULL DEFAULT 0,
  "creatorLevel" INTEGER NOT NULL DEFAULT 0,
  "creatorCharacters" TEXT NOT NULL DEFAULT '[]',
  "creatorRole" TEXT NOT NULL DEFAULT '',
  "creatorTitle" TEXT NOT NULL DEFAULT '',
  "creatorAvatarOriginalName" TEXT NOT NULL DEFAULT '',
  "creatorAvatarPath" TEXT NOT NULL DEFAULT '',
  "creatorAvatarFileServer" TEXT NOT NULL DEFAULT '',
  "creatorSlogan" TEXT NOT NULL DEFAULT '',
  "pagesCount" INTEGER NOT NULL DEFAULT 0,
  "epsCount" INTEGER NOT NULL DEFAULT 0,
  "allowDownload" INTEGER NOT NULL DEFAULT 0,
  "allowComment" INTEGER NOT NULL DEFAULT 0,
  "totalLikes" INTEGER NOT NULL DEFAULT 0,
  "totalViews" INTEGER NOT NULL DEFAULT 0,
  "totalComments" INTEGER NOT NULL DEFAULT 0,
  "viewsCount" INTEGER NOT NULL DEFAULT 0,
  "commentsCount" INTEGER NOT NULL DEFAULT 0,
  "isFavourite" INTEGER NOT NULL DEFAULT 0,
  "isLiked" INTEGER NOT NULL DEFAULT 0,
  "order" INTEGER NOT NULL DEFAULT 0,
  "epPageCount" INTEGER NOT NULL DEFAULT 0,
  "epTitle" TEXT NOT NULL DEFAULT '',
  "creatorCharactersString" TEXT NOT NULL DEFAULT '',
  "categoriesString" TEXT NOT NULL DEFAULT '',
  "tagsString" TEXT NOT NULL DEFAULT '',
  "deleted" INTEGER NOT NULL DEFAULT 0,
  "epId" TEXT NOT NULL DEFAULT ''
);

CREATE TABLE IF NOT EXISTS "BikaComicDownload" (
  "id" INTEGER PRIMARY KEY AUTOINCREMENT,
  "comicId" TEXT NOT NULL DEFAULT '',
  "creatorId" TEXT NOT NULL DEFAULT '',
  "creatorGender" TEXT NOT NULL DEFAULT '',
  "creatorName" TEXT NOT NULL DEFAULT '',
  "creatorVerified" INTEGER NOT NULL DEFAULT 0,
  "creatorExp" INTEGER NOT NULL DEFAULT 0,
  "creatorLevel" INTEGER NOT NULL DEFAULT 0,
  "creatorCharacters" TEXT NOT NULL DEFAULT '[]',
  "creatorCharactersString" TEXT NOT NULL DEFAULT '',
  "creatorRole" TEXT NOT NULL DEFAULT '',
  "creatorTitle" TEXT NOT NULL DEFAULT '',
  "creatorAvatarOriginalName" TEXT NOT NULL DEFAULT '',
  "creatorAvatarPath" TEXT NOT NULL DEFAULT '',
  "creatorAvatarFileServer" TEXT NOT NULL DEFAULT '',
  "creatorSlogan" TEXT NOT NULL DEFAULT '',
  "title" TEXT NOT NULL DEFAULT '',
  "description" TEXT NOT NULL DEFAULT '',
  "thumbOriginalName" TEXT NOT NULL DEFAULT '',
  "thumbPath" TEXT NOT NULL DEFAULT '',
  "thumbFileServer" TEXT NOT NULL DEFAULT '',
  "author" TEXT NOT NULL DEFAULT '',
  "chineseTeam" TEXT NOT NULL DEFAULT '',
  "categories" TEXT NOT NULL DEFAULT '[]',
  "categoriesString" TEXT NOT NULL DEFAULT '',
  "tags" TEXT NOT NULL DEFAULT '[]',
  "tagsString" TEXT NOT NULL DEFAULT '',
  "pagesCount" INTEGER NOT NULL DEFAULT 0,
  "epsCount" INTEGER NOT NULL DEFAULT 0,
  "finished" INTEGER NOT NULL DEFAULT 0,
  "updatedAt" INTEGER NOT NULL DEFAULT 0,
  "createdAt" INTEGER NOT NULL DEFAULT 0,
  "allowDownload" INTEGER NOT NULL DEFAULT 0,
  "allowComment" INTEGER NOT NULL DEFAULT 0,
  "totalLikes" INTEGER NOT NULL DEFAULT 0,
  "totalViews" INTEGER NOT NULL DEFAULT 0,
  "totalComments" INTEGER NOT NULL DEFAULT 0,
  "viewsCount" INTEGER NOT NULL DEFAULT 0,
  "likesCount" INTEGER NOT NULL DEFAULT 0,
  "commentsCount" INTEGER NOT NULL DEFAULT 0,
  "isFavourite" INTEGER NOT NULL DEFAULT 0,
  "isLiked" INTEGER NOT NULL DEFAULT 0,
  "comicInfoAll" TEXT NOT NULL DEFAULT '',
  "epsTitle" TEXT NOT NULL DEFAULT '[]',
  "downloadTime" INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS "JmFavorite" (
  "id" INTEGER PRIMARY KEY AUTOINCREMENT,
  "comicId" TEXT NOT NULL DEFAULT '',
  "name" TEXT NOT NULL DEFAULT '',
  "description" TEXT NOT NULL DEFAULT '',
  "totalViews" TEXT NOT NULL DEFAULT '',
  "likes" TEXT NOT NULL DEFAULT '',
  "seriesId" TEXT NOT NULL DEFAULT '',
  "commentTotal" TEXT NOT NULL DEFAULT '',
  "author" TEXT NOT NULL DEFAULT '[]',
  "tags" TEXT NOT NULL DEFAULT '[]',
  "works" TEXT NOT NULL DEFAULT '[]',
  "actors" TEXT NOT NULL DEFAULT '[]',
  "liked" INTEGER NOT NULL DEFAULT 0,
  "isFavorite" INTEGER NOT NULL DEFAULT 0,
  "isAids" INTEGER NOT NULL DEFAULT 0,
  "price" TEXT NOT NULL DEFAULT '',
  "purchased" TEXT NOT NULL DEFAULT '',
  "addtime" TEXT NOT NULL DEFAULT '',
  "deleted" INTEGER NOT NULL DEFAULT 0,
  "history" INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS "JmHistory" (
  "id" INTEGER PRIMARY KEY AUTOINCREMENT,
  "comicId" TEXT NOT NULL DEFAULT '',
  "name" TEXT NOT NULL DEFAULT '',
  "description" TEXT NOT NULL DEFAULT '',
  "totalViews" TEXT NOT NULL DEFAULT '',
  "likes" TEXT NOT NULL DEFAULT '',
  "seriesId" TEXT NOT NULL DEFAULT '',
  "commentTotal" TEXT NOT NULL DEFAULT '',
  "author" TEXT NOT NULL DEFAULT '[]',
  "tags" TEXT NOT NULL DEFAULT '[]',
  "works" TEXT NOT NULL DEFAULT '[]',
  "actors" TEXT NOT NULL DEFAULT '[]',
  "liked" INTEGER NOT NULL DEFAULT 0,
  "isFavorite" INTEGER NOT NULL DEFAULT 0,
  "isAids" INTEGER NOT NULL DEFAULT 0,
  "price" TEXT NOT NULL DEFAULT '',
  "purchased" TEXT NOT NULL DEFAULT '',
  "addtime" TEXT NOT NULL DEFAULT '',
  "order" INTEGER NOT NULL DEFAULT 0,
  "epTitle" TEXT NOT NULL DEFAULT '',
  "epPageCount" INTEGER NOT NULL DEFAULT 0,
  "epId" TEXT NOT NULL DEFAULT '',
  "deleted" INTEGER NOT NULL DEFAULT 0,
  "history" INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS "JmDownload" (
  "id" INTEGER PRIMARY KEY AUTOINCREMENT,
  "comicId" TEXT NOT NULL DEFAULT '',
  "name" TEXT NOT NULL DEFAULT '',
  "addtime" TEXT NOT NULL DEFAULT '',
  "description" TEXT NOT NULL DEFAULT '',
  "totalViews" TEXT NOT NULL DEFAULT '',
  "likes" TEXT NOT NULL DEFAULT '',
  "seriesId" TEXT NOT NULL DEFAULT '',
  "commentTotal" TEXT NOT NULL DEFAULT '',
  "author" TEXT NOT NULL DEFAULT '[]',
  "tags" TEXT NOT NULL DEFAULT '[]',
  "works" TEXT NOT NULL DEFAULT '[]',
  "actors" TEXT NOT NULL DEFAULT '[]',
  "liked" INTEGER NOT NULL DEFAULT 0,
  "isFavorite" INTEGER NOT NULL DEFAULT 0,
  "isAids" INTEGER NOT NULL DEFAULT 0,
  "price" TEXT NOT NULL DEFAULT '',
  "purchased" TEXT NOT NULL DEFAULT '',
  "allInfo" TEXT NOT NULL DEFAULT '',
  "epsIds" TEXT NOT NULL DEFAULT '[]',
  "downloadTime" INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS "UserSetting" (
  "id" INTEGER PRIMARY KEY AUTOINCREMENT,
  "globalSettingData" TEXT,
  "bikaSettingData" TEXT,
  "jmSettingData" TEXT,
  "jmJwt" TEXT NOT NULL DEFAULT ''
);

CREATE TABLE IF NOT EXISTS "DownloadTask" (
  "id" INTEGER PRIMARY KEY AUTOINCREMENT,
  "isDownloading" INTEGER NOT NULL DEFAULT 0,
  "comicId" TEXT NOT NULL DEFAULT '',
  "comicName" TEXT NOT NULL DEFAULT '',
  "isCompleted" INTEGER NOT NULL DEFAULT 0,
  "status" TEXT NOT NULL DEFAULT '',
  "dbTaskInfoStr" TEXT
);

CREATE TABLE IF NOT EXISTS "PluginConfig" (
  "id" INTEGER PRIMARY KEY AUTOINCREMENT,
  "name" TEXT NOT NULL DEFAULT '',
  "config" TEXT NOT NULL DEFAULT ''
);

CREATE TABLE IF NOT EXISTS "PluginInfo" (
  "id" INTEGER PRIMARY KEY AUTOINCREMENT,
  "version" TEXT NOT NULL DEFAULT '',
  "insertedAt" INTEGER NOT NULL DEFAULT 0,
  "updatedAt" INTEGER NOT NULL DEFAULT 0,
  "isEnabled" INTEGER NOT NULL DEFAULT 0,
  "isDeleted" INTEGER NOT NULL DEFAULT 0,
  "uuid" TEXT NOT NULL DEFAULT '',
  "lastLoadSuccess" INTEGER NOT NULL DEFAULT 0,
  "lastLoadError" TEXT,
  "deletedAt" INTEGER,
  "debug" INTEGER NOT NULL DEFAULT 0,
  "debugUrl" TEXT,
  "getInfoJson" TEXT NOT NULL DEFAULT '',
  "sortOrder" INTEGER
);
CREATE UNIQUE INDEX IF NOT EXISTS "ux_PluginInfo_uuid" ON "PluginInfo" ("uuid");

-- 插件脚本单独存表：列表/状态更新等只读 PluginInfo，不把大段 JS 带进查询。
CREATE TABLE IF NOT EXISTS "PluginScript" (
  "uuid" TEXT PRIMARY KEY,
  "originScript" TEXT NOT NULL DEFAULT '',
  "revision" TEXT NOT NULL DEFAULT '',
  "scriptUpdatedAt" INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS "UnifiedComicDownload" (
  "id" INTEGER PRIMARY KEY AUTOINCREMENT,
  "uniqueKey" TEXT NOT NULL DEFAULT '',
  "source" TEXT NOT NULL DEFAULT '',
  "comicId" TEXT NOT NULL DEFAULT '',
  "title" TEXT NOT NULL DEFAULT '',
  "description" TEXT NOT NULL DEFAULT '',
  "storageRoot" TEXT NOT NULL DEFAULT '',
  "createdAt" INTEGER NOT NULL DEFAULT 0,
  "updatedAt" INTEGER NOT NULL DEFAULT 0,
  "downloadedAt" INTEGER NOT NULL DEFAULT 0,
  "deleted" INTEGER NOT NULL DEFAULT 0,
  "schemaVersion" INTEGER NOT NULL DEFAULT 0,
  "totalViews" INTEGER NOT NULL DEFAULT 0,
  "totalLikes" INTEGER NOT NULL DEFAULT 0,
  "totalComments" INTEGER NOT NULL DEFAULT 0,
  "isFavourite" INTEGER NOT NULL DEFAULT 0,
  "isLiked" INTEGER NOT NULL DEFAULT 0,
  "allowComment" INTEGER NOT NULL DEFAULT 0,
  "allowLike" INTEGER NOT NULL DEFAULT 0,
  "allowFavorite" INTEGER NOT NULL DEFAULT 0,
  "allowDownload" INTEGER NOT NULL DEFAULT 0,
  "cover" TEXT NOT NULL DEFAULT '',
  "creator" TEXT NOT NULL DEFAULT '',
  "titleMeta" TEXT NOT NULL DEFAULT '',
  "metadata" TEXT NOT NULL DEFAULT '',
  "chapters" TEXT NOT NULL DEFAULT '',
  "detailJson" TEXT NOT NULL DEFAULT '',
  "titleOverride" TEXT,
  "coverOverride" TEXT
);
CREATE UNIQUE INDEX IF NOT EXISTS "ux_UnifiedComicDownload_uniqueKey" ON "UnifiedComicDownload" ("uniqueKey");

CREATE TABLE IF NOT EXISTS "UnifiedComicFavorite" (
  "id" INTEGER PRIMARY KEY AUTOINCREMENT,
  "uniqueKey" TEXT NOT NULL DEFAULT '',
  "source" TEXT NOT NULL DEFAULT '',
  "comicId" TEXT NOT NULL DEFAULT '',
  "title" TEXT NOT NULL DEFAULT '',
  "description" TEXT NOT NULL DEFAULT '',
  "createdAt" INTEGER NOT NULL DEFAULT 0,
  "updatedAt" INTEGER NOT NULL DEFAULT 0,
  "deleted" INTEGER NOT NULL DEFAULT 0,
  "schemaVersion" INTEGER NOT NULL DEFAULT 0,
  "cover" TEXT NOT NULL DEFAULT '',
  "creator" TEXT NOT NULL DEFAULT '',
  "titleMeta" TEXT NOT NULL DEFAULT '',
  "metadata" TEXT NOT NULL DEFAULT ''
);
CREATE UNIQUE INDEX IF NOT EXISTS "ux_UnifiedComicFavorite_uniqueKey" ON "UnifiedComicFavorite" ("uniqueKey");

CREATE TABLE IF NOT EXISTS "UnifiedComicHistory" (
  "id" INTEGER PRIMARY KEY AUTOINCREMENT,
  "uniqueKey" TEXT NOT NULL DEFAULT '',
  "source" TEXT NOT NULL DEFAULT '',
  "comicId" TEXT NOT NULL DEFAULT '',
  "title" TEXT NOT NULL DEFAULT '',
  "description" TEXT NOT NULL DEFAULT '',
  "chapterId" TEXT NOT NULL DEFAULT '',
  "chapterTitle" TEXT NOT NULL DEFAULT '',
  "chapterOrder" INTEGER NOT NULL DEFAULT 0,
  "pageIndex" INTEGER NOT NULL DEFAULT 0,
  "lastReadAt" INTEGER NOT NULL DEFAULT 0,
  "deleted" INTEGER NOT NULL DEFAULT 0,
  "schemaVersion" INTEGER NOT NULL DEFAULT 0,
  "createdAt" INTEGER NOT NULL DEFAULT 0,
  "updatedAt" INTEGER NOT NULL DEFAULT 0,
  "cover" TEXT NOT NULL DEFAULT '',
  "creator" TEXT NOT NULL DEFAULT '',
  "titleMeta" TEXT NOT NULL DEFAULT '',
  "metadata" TEXT NOT NULL DEFAULT ''
);
CREATE UNIQUE INDEX IF NOT EXISTS "ux_UnifiedComicHistory_uniqueKey" ON "UnifiedComicHistory" ("uniqueKey");

CREATE TABLE IF NOT EXISTS "ComicFolder" (
  "id" INTEGER PRIMARY KEY AUTOINCREMENT,
  "uniqueKey" TEXT NOT NULL DEFAULT '',
  "name" TEXT NOT NULL DEFAULT '',
  "typeData" TEXT NOT NULL DEFAULT '',
  "versionVectorJson" TEXT NOT NULL DEFAULT '',
  "deletedAt" INTEGER,
  "createdAt" INTEGER NOT NULL DEFAULT 0,
  "updatedAt" INTEGER NOT NULL DEFAULT 0,
  "syncId" TEXT NOT NULL DEFAULT '',
  "parentSyncId" TEXT,
  "coverComicUniqueKey" TEXT
);
CREATE UNIQUE INDEX IF NOT EXISTS "ux_ComicFolder_uniqueKey" ON "ComicFolder" ("uniqueKey");
CREATE INDEX IF NOT EXISTS "ix_ComicFolder_syncId" ON "ComicFolder" ("syncId");
CREATE INDEX IF NOT EXISTS "ix_ComicFolder_parentSyncId" ON "ComicFolder" ("parentSyncId");

CREATE TABLE IF NOT EXISTS "ComicLink" (
  "id" INTEGER PRIMARY KEY AUTOINCREMENT,
  "uniqueKey" TEXT NOT NULL DEFAULT '',
  "typeData" TEXT NOT NULL DEFAULT '',
  "versionVectorJson" TEXT NOT NULL DEFAULT '',
  "deletedAt" INTEGER,
  "createdAt" INTEGER NOT NULL DEFAULT 0,
  "updatedAt" INTEGER NOT NULL DEFAULT 0,
  "comicUniqueKey" TEXT NOT NULL DEFAULT '',
  "folderSyncId" TEXT
);
CREATE UNIQUE INDEX IF NOT EXISTS "ux_ComicLink_uniqueKey" ON "ComicLink" ("uniqueKey");
CREATE INDEX IF NOT EXISTS "ix_ComicLink_folderSyncId" ON "ComicLink" ("folderSyncId");

CREATE TABLE IF NOT EXISTS "ComicFollow" (
  "id" INTEGER PRIMARY KEY AUTOINCREMENT,
  "uniqueKey" TEXT NOT NULL DEFAULT '',
  "source" TEXT NOT NULL DEFAULT '',
  "comicId" TEXT NOT NULL DEFAULT '',
  "title" TEXT NOT NULL DEFAULT '',
  "description" TEXT NOT NULL DEFAULT '',
  "cover" TEXT NOT NULL DEFAULT '',
  "creator" TEXT NOT NULL DEFAULT '',
  "titleMeta" TEXT NOT NULL DEFAULT '',
  "metadata" TEXT NOT NULL DEFAULT '',
  "lastChapterCount" INTEGER NOT NULL DEFAULT 0,
  "detectedChapterCount" INTEGER NOT NULL DEFAULT 0,
  "hasUpdate" INTEGER NOT NULL DEFAULT 0,
  "updateTime" INTEGER NOT NULL DEFAULT 0,
  "deleted" INTEGER NOT NULL DEFAULT 0,
  "createdAt" INTEGER NOT NULL DEFAULT 0,
  "updatedAt" INTEGER NOT NULL DEFAULT 0,
  "schemaVersion" INTEGER NOT NULL DEFAULT 0,
  "detectedChapterTitle" TEXT NOT NULL DEFAULT ''
);
CREATE UNIQUE INDEX IF NOT EXISTS "ux_ComicFollow_uniqueKey" ON "ComicFollow" ("uniqueKey");

CREATE TABLE IF NOT EXISTS "ComicReadPreference" (
  "id" INTEGER PRIMARY KEY AUTOINCREMENT,
  "uniqueKey" TEXT NOT NULL DEFAULT '',
  "source" TEXT NOT NULL DEFAULT '',
  "comicId" TEXT NOT NULL DEFAULT '',
  "readMode" INTEGER NOT NULL DEFAULT 0,
  "updatedAt" INTEGER NOT NULL DEFAULT 0,
  "deleted" INTEGER NOT NULL DEFAULT 0,
  "overridesJson" TEXT NOT NULL DEFAULT ''
);
CREATE UNIQUE INDEX IF NOT EXISTS "ux_ComicReadPreference_uniqueKey" ON "ComicReadPreference" ("uniqueKey");

CREATE TABLE IF NOT EXISTS "SearchBookmark" (
  "id" INTEGER PRIMARY KEY AUTOINCREMENT,
  "uniqueKey" TEXT NOT NULL DEFAULT '',
  "source" TEXT NOT NULL DEFAULT '',
  "keyword" TEXT NOT NULL DEFAULT '',
  "externJson" TEXT NOT NULL DEFAULT '',
  "anchorComicId" TEXT NOT NULL DEFAULT '',
  "anchorTitle" TEXT NOT NULL DEFAULT '',
  "anchorCover" TEXT NOT NULL DEFAULT '',
  "anchorPage" INTEGER NOT NULL DEFAULT 0,
  "createdAt" INTEGER NOT NULL DEFAULT 0,
  "updatedAt" INTEGER NOT NULL DEFAULT 0,
  "anchorIndex" INTEGER NOT NULL DEFAULT 0
);
CREATE UNIQUE INDEX IF NOT EXISTS "ux_SearchBookmark_uniqueKey" ON "SearchBookmark" ("uniqueKey");

CREATE TABLE IF NOT EXISTS "ComicReadChapter" (
  "id" INTEGER PRIMARY KEY AUTOINCREMENT,
  "uniqueKey" TEXT NOT NULL DEFAULT '',
  "source" TEXT NOT NULL DEFAULT '',
  "comicId" TEXT NOT NULL DEFAULT '',
  "chapterId" TEXT NOT NULL DEFAULT '',
  "chapterTitle" TEXT NOT NULL DEFAULT '',
  "chapterOrder" INTEGER NOT NULL DEFAULT 0,
  "readAt" INTEGER NOT NULL DEFAULT 0,
  "updatedAt" INTEGER NOT NULL DEFAULT 0
);
CREATE UNIQUE INDEX IF NOT EXISTS "ux_ComicReadChapter_uniqueKey" ON "ComicReadChapter" ("uniqueKey");
CREATE INDEX IF NOT EXISTS "ix_ComicReadChapter_source" ON "ComicReadChapter" ("source");
CREATE INDEX IF NOT EXISTS "ix_ComicReadChapter_comicId" ON "ComicReadChapter" ("comicId");

-- 所有表/索引创建成功后才标记版本，失败时下次启动会重试。
PRAGMA user_version = 3;
''';
