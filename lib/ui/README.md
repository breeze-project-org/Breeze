# CalmUI · Breeze 基础组件库指南

`lib/ui/` 是 Breeze 面向 **五端（Windows / macOS / Linux / iOS / Android）** 的基础 UI 组件库。  
本目录**只存放无业务耦合的基础组件与主题令牌**；具体业务模块（如书架文件夹、插件卡片、漫画详情等）在各自页面层用这里的基础组件组合搭建。

---

## 一、设计理念

### 1. 轻盈开朗，低攻击性
- **拒绝沉闷与厚重**：弃用暗灰旧纸感与“边框套边框”的厚重盒子；浅色采用随主题色轻微染底的清透画布，深色采用通透低眩光的夜蓝灰而非纯黑。
- **靠面与微影分层，少用硬边框**：页面底色（`bg`）→ 浮空卡片（`surface` + `shadowSm`）→ 次级交互控件（`surface2` 柔和胶囊），让界面透气、开朗且耐看。
- **低饱和高活力主题色**：内置 6 套清爽不刺眼的 Seed 色（晴空 / 薄荷 / 珊瑚 / 柑橘 / 鸢尾 / 樱粉），按钮、开关、胶囊和画布底色统一联动，不与漫画封面抢视觉焦点。

### 2. 高信息密度，内容优先
- **紧凑字阶与等宽数字**：核心字号控制在 `10.5px – 15px` 之间；所有章节数、未读数、文件大小与时间统一启用 `FontFeature.tabularFigures()`，列表纵向扫描不跳动。
- **双密度切换（`CalmDensity`）**：提供 `compact`（默认，高信息密度）与 `comfortable`（舒适）两档，列表行与组件内边距通过 `context.calm.rowVPadding` 自动响应。
- **动效克制轻快**：按钮与图标采用轻微按压缩放（`0.97` / `0.94`）和 `120–220ms` 缓动，去掉沉重的水波纹（`NoSplash.splashFactory`）。

### 3. 五端自适应规范
所有浮层与布局按屏幕宽度自动适配，调用方无需手写平台判断：

| 断点 | 设备形态 | 推荐导航形态 | 弹窗 / 抽屉 / 通知表现 |
| --- | --- | --- | --- |
| `< 600px` | 手机 Mobile | 底部 `NavigationBar` | 弹窗与抽屉从底部带抓手滑出；Toast 顶部居中 |
| `600 – 1024px` | 平板 Tablet | 左侧 `NavigationRail` | 弹窗居中卡片；抽屉右侧滑出；Toast 右上角 |
| `>= 1024px` | 桌面 Desktop | 可折叠侧栏 + 分栏 | 弹窗居中卡片；抽屉右侧滑出；Toast 右上角 |

### 4. 跨平台 CJK 字体与光学居中
- `CalmTheme.build` 按平台自动注入中文字体与回退链（Windows `Microsoft YaHei UI`、macOS/iOS `PingFang SC`、Linux `Noto Sans CJK SC`），避免 Windows 下汉字回退到日文字体导致粗细不一。
- 胶囊按钮、徽章与标签统一使用 `kCalmTextHeightBehavior` 与 `calmStrut(fontSize)`（`height: 1.2` + `TextLeadingDistribution.even`），彻底解决微软雅黑在胶囊内偏下及中英数基线错位的问题。

---

## 二、快速上手与独立预览

### 1. 秒启热重载预览页
开发或调整基础组件时，直接运行独立演示入口（跳过 Rust / 数据库 / 后台任务初始化，热重载极快）：

```bash
flutter run -d windows -t lib/main_ui_demo.dart
```

### 2. 在应用中挂载主题
统一通过桶文件导入：

```dart
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/ui/ui.dart';

MaterialApp(
  locale: const Locale('zh', 'CN'),
  supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  theme: CalmTheme.build(
    brightness: Brightness.light,
    seed: CalmSeed.sky,
    density: CalmDensity.compact,
  ),
  darkTheme: CalmTheme.build(
    brightness: Brightness.dark,
    seed: CalmSeed.sky,
    density: CalmDensity.compact,
  ),
  home: ...,
);
```

### 3. 在任意 Widget 中读取颜色与密度令牌

```dart
final c = context.calm;

Container(
  color: c.surface,
  padding: EdgeInsets.symmetric(vertical: c.rowVPadding, horizontal: 12),
  child: Text('标题', style: TextStyle(color: c.text)),
);
```

---

## 三、目录结构与组件速查

```text
lib/ui/
├── ui.dart                         # 统一导出入口（外部只引这一个文件）
├── README.md                       # 本说明文档
├── theme/
│   └── calm_theme.dart             # CalmSeed / CalmDensity / CalmColors / CalmTheme / CJK 行高工具
└── components/
    ├── calm_button.dart            # CalmButton / CalmIconButton
    ├── calm_controls.dart          # CalmSwitch / CalmTriCheckbox / CalmRadioTile / CalmTextField / CalmTextArea / CalmSlider / CalmDropdown
    ├── calm_selection.dart         # CalmCheckbox / CalmCheckboxTile / CalmStepper / CalmPinField / showCalmMultiChoiceDialog
    ├── calm_chips.dart             # CalmBadge / CalmFilterChip / CalmInputChip / CalmSegmentedControl / CalmPillTabs
    ├── calm_display.dart           # CalmProgressBar / CalmAvatar / CalmDivider
    ├── calm_layout.dart            # CalmAppBar / CalmPageScaffold / CalmExpandableText / CalmColorGrid
    ├── calm_navigation.dart        # CalmNavItem / CalmBottomNavBar / CalmNavRail / CalmSidebarItem / CalmUnderlineTabs / CalmBreadcrumb
    ├── calm_overlay_actions.dart   # CalmPopupMenuButton / showCalmContextMenu / CalmBatchActionBar / CalmSpeedDial
    ├── calm_surface.dart           # CalmCard / CalmSectionHeader / CalmListTile / CalmExpansionTile
    └── calm_feedback.dart          # CalmToast / CalmToastCard / showCalmDialog / CalmDialogSurface / showCalmSheet / CalmStatusBanner / CalmEmptyState / CalmErrorState / CalmSkeletonBox / CalmLoading / CalmBottomLoader
```

### 1. 按钮（`calm_button.dart`）
选择层级原则：一个视觉区域尽量只有 **1 个** `primary` 主按钮；辅助强调优先用 `tonal`；次要操作用 `secondary` / `ghost`；不可逆删除用 `danger`。

```dart
CalmButton(
  label: '继续阅读',
  icon: Icons.play_arrow_rounded,
  variant: CalmButtonVariant.primary, // primary | tonal | secondary | ghost | danger
  size: CalmButtonSize.sm,            // xs(26) | sm(30) | md(35)
  loading: false,
  onPressed: () {},
)

CalmIconButton(
  icon: Icons.bookmark_rounded,
  selected: isFavorite,
  tooltip: '收藏',
  onPressed: () {},
)
```

### 2. 表单与筛选控件（`calm_controls.dart`）

```dart
// 开关（38×22 胶囊，严格垂直居中）
CalmSwitch(value: enabled, onChanged: (v) {})

// 三态筛选框（点击循环：忽略 none -> 包含 include -> 排除 exclude）
CalmTriCheckbox(label: '奇幻', state: state, onChanged: (next) {})

// 单选行
CalmRadioTile<String>(label: '日漫右翻 (RTL)', value: 'rtl', groupValue: dir, onChanged: (v) {})

// 胶囊输入框 / 搜索框（内置清空按钮、密码显隐、快捷键提示、错误提示）
CalmTextField(
  controller: ctrl,
  prefixIcon: Icons.search_rounded,
  hintText: '搜索书名、作者、标签…',
  shortcutHint: 'Ctrl K',
)

// Fluent 风格下拉选择器（选中项左侧 3px 居中竖条，无对勾）
CalmDropdown<String>(
  value: sortKey,
  items: const [
    (value: 'updated', label: '按最近更新排序', meta: '默认'),
    (value: 'unread', label: '按未读话数排序', meta: '追更'),
  ],
  onChanged: (v) {},
)

// 滑块
CalmSlider(
  label: '图片预加载页数',
  value: pages,
  min: 1,
  max: 10,
  divisions: 9,
  valueText: '${pages.round()} 页',
  onChanged: (v) {},
)
```

### 3. 徽章、筛选芯片与分段标签（`calm_chips.dart`）

```dart
// 语义徽章（accent | tonal | neutral | success | warning | danger）
CalmBadge(label: '连载中', dot: true, tone: CalmBadgeTone.success)

// 可多选筛选芯片
CalmFilterChip(label: '已离线', selected: onlyOffline, onSelected: (v) {})

// 胶囊分段控件
CalmSegmentedControl<String>(
  value: viewMode,
  options: const [
    (value: 'grid', label: '网格', icon: Icons.grid_view_rounded),
    (value: 'list', label: '列表', icon: Icons.view_list_rounded),
  ],
  onChanged: (v) {},
)

// 计数胶囊标签栏（Text.rich 同基线对齐）
CalmPillTabs<String>(
  value: tab,
  items: const [
    (value: 'all', label: '全部', count: 138),
    (value: 'unread', label: '未读', count: 12),
  ],
  onChanged: (v) {},
)
```

### 4. 容器、分组头与列表行（`calm_surface.dart`）

```dart
CalmSectionHeader(
  title: '本周热门连载',
  countText: '48 部',
  actionLabel: '更多',
  onActionTap: () {},
)

CalmCard(
  child: Column(
    children: [
      CalmListTile(
        title: '定时检查书架更新',
        subtitle: '每 12 小时静默检查一次',
        trailing: CalmSwitch(value: autoCheck, onChanged: (v) {}),
      ),
      CalmExpansionTile(
        title: '高级网络选项',
        child: ...,
      ),
    ],
  ),
)
```

### 5. 顶部通知、自适应弹窗与状态页（`calm_feedback.dart`）

```dart
// 顶部悬浮通知（桌面右上角 / 手机顶部居中，支持标题 + 详细内容 + 操作按钮）
CalmToast.show(
  context,
  title: '五端进度同步完成',
  description: '已通过 WebDAV 合并 14 条阅读记录。',
  tone: CalmTone.success, // info | success | warning | danger
  actionLabel: '撤销',
  onAction: () {},
);

// 自适应弹窗（手机底部带抓手滑出 / 平板与桌面居中卡片）
showCalmDialog<void>(
  context,
  title: '确认删除离线章节？',
  subtitle: '书架收藏与阅读进度会完整保留',
  icon: Icons.warning_amber_rounded,
  tone: CalmTone.danger,
  bodyBuilder: (ctx) => Text('将释放 142 MB 本地缓存。'),
  actionsBuilder: (ctx) => [
    CalmButton(label: '取消', variant: CalmButtonVariant.ghost, onPressed: () => Navigator.pop(ctx)),
    CalmButton(label: '确认删除', variant: CalmButtonVariant.danger, onPressed: () {}),
  ],
);

// 自适应抽屉（手机 BottomSheet / 大屏右侧 SideSheet）
showCalmSheet<void>(
  context,
  title: '筛选与显示设置',
  builder: (ctx) => ...,
);

// 页内状态横幅 / 空态 / 错误态（内置一键复制错误 + 双按钮） / 骨架屏
CalmStatusBanner(title: '检测到 Cloudflare 验证', tone: CalmTone.warning);
CalmEmptyState(icon: Icons.menu_book_rounded, title: '暂无漫画');
CalmErrorState(title: '需要重新登录', errorDetail: 'HTTP 401', primaryLabel: '去登录', onPrimary: () {}, onRetry: () {});
CalmSkeletonBox(width: 120, height: 12);
```

---

## 四、后续开发约定（红线）

1. **包路径导入**：严格遵守项目 `analysis_options.yaml` 中的 `always_use_package_imports: true`，统一用 `package:zephyr/ui/...` 和 `package:material_ui/material_ui.dart`。
2. **禁止写死黑白色值**：所有前景色、底色、边框与阴影均从 `context.calm` 获取，保证浅色 / 深色和 6 套主题色切换零割裂。
3. **禁止对汉字使用裸 `height: 1.0`**：所有固定高度胶囊内的单行文本必须配 `kCalmTextHeightBehavior` 和 `calmStrut(fontSize)`，并在混排不同字号时优先用 `Text.rich` 对齐基线。
4. **禁止在 `Wrap` 内的无宽 `Container` 上写 `alignment: Alignment.center`**：否则会被撑满整行；需要「动态宽度 + 严格居中」时，改用 `Center(widthFactor: 1.0, heightFactor: 1.0)` 或 `Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.center)`。
5. **保持组件纯粹**：`lib/ui/` 不依赖 `database`、`plugin`、`cubit`、`i18n` 等业务层；业务特化卡片请放在对应 `lib/page/**/widgets/` 下组合实现。

---

## 五、已补齐的基础组件清单

本阶段核心基础组件已全部完成并通过 `flutter analyze` 验证：

- [x] `CalmCheckbox` / `CalmCheckboxTile`（常规二态复选框）
- [x] `CalmPopupMenuButton`（上下文动作菜单 / 桌面右键菜单，带图标、分割线、快捷键提示）
- [x] `CalmProgressBar`（定长/不定长线性进度条，用于下载任务与存储容量）
- [x] 自适应导航基础件（`CalmBottomNavBar` / `CalmNavRail` / `CalmSidebarItem` / `CalmUnderlineTabs` / `CalmBreadcrumb`）
- [x] `CalmBatchActionBar`（多选态底部悬浮批量操作胶囊条）& `CalmSpeedDial`
- [x] `CalmAvatar`、`CalmDivider`、`CalmStepper`（数字加减器）、`CalmPinField`（分段 PIN 输入框）、`showCalmMultiChoiceDialog`
- [x] `CalmAppBar` / `CalmPageScaffold`（统一轻盈二级页顶栏与桌面限宽居中壳）
- [x] `CalmTextArea`（多行文本域与字数统计）、`CalmInputChip`（可删除标签芯片）
- [x] `showCalmContextMenu`（任意坐标右键弹出菜单，自动防出屏）
- [x] `CalmLoading` / `CalmBottomLoader`（分页列表三态加载底栏）、`CalmExpandableText`（溢出自动折叠长文本）、`CalmColorGrid`（主题色选择网格）与全局轻盈 `TooltipTheme`
