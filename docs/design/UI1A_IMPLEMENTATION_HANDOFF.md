# UI-1A · 实现交接（设计师稿 → ArkTS）

> 基准 `7e8cf8b`。本文件是**实现准备**，不是高保真视觉稿；不含任何生产代码改动。
> 目的：让后续 UI-1B 在拿到正式视觉稿后，能直接对照组件树、状态与事件接口落地。

## 1. 原稿元素 ↔ 页面映射（区分产品 UI 与原型脚手架）

原稿 `lightbearing_ui.html`（67 行）里同时存在**产品 UI** 与**原型自身的设计说明面板**，实现时必须区分：

| 原稿区域 | 性质 | 是否属产品 UI | 说明 |
|---|---|---|---|
| `.sidebar`（256px 左侧导航 + 应用图标 + PAGES 列表 + 页脚说明） | 原型导航脚手架（桌面演示） | ❌ | 产品在手机上是底部 5 Tab；侧栏只在 Expanded/Large 布局出现，且条目需按产品信息架构重排 |
| `.rpanel`「DESIGN SYSTEM」栏（token 面板、图标构想、交互与网格说明、工程映射） | **设计说明面板** | ❌ | 纯设计交付物，绝不进入 App |
| `.shell` 三栏 grid（256 + 主区 + 292） | 演示布局 | ❌（作为思路） | 可作为 Expanded/Large 的双/三栏参照，但不能照搬像素值 |
| 页面主体（`APP.pages` 定义的 10 页内容：hero、card、statrow、linechart、fields、timeline、listitem…） | 产品 UI 原型 | ✅ | 这是视觉与信息层级的唯一有效来源 |
| `mobiletabs`（≤780px 时出现的横向 tabs） | 原型的移动降级 | ⚠️ | 仅示意，产品形态（底部 Tab vs 顶部 tabs）需由视觉稿决定 |

页面级映射（原稿 10 页 ↔ 实现 13 页）：

| 原稿 | 实现 | 备注 |
|---|---|---|
| home | `HomePage` | 1:1 |
| sunpath | `SunPathPage` | 1:1 |
| reverse | `ReversePage` | 1:1 |
| locations | `LocationsPage` | 1:1 |
| compass | `CompassPage` | 1:1 |
| map | `MapPage` | 1:1 |
| planner | `PlannerPage` | 1:1 |
| calendar | `CalendarPage` | 1:1 |
| compare | `ComparePage` | 1:1 |
| settings | `SettingsPage` | 1:1 |
| — | `Index`（Navigation + NavDestination 外壳） | 原稿无（原型是单页切换）；需视觉稿明确导航壳 |
| — | `PlaceDetailPage` / `PlanDetailPage` | 原稿无；需按 locations/planner 的卡片语言派生 |

## 2. 首页（HomePage）现状

**组件树（简化，依据源码结构）**

```text
Scroll
└─ Column
   ├─ TopBar（标题「今日光线」+ 副标题 + 状态徽标）
   ├─ hero 卡（eyebrow / H2 / 说明 / 双按钮：反向寻光、完整日轨）
   ├─ 机位卡（机位名 + 阶段徽标 / 日期·时刻·UTC 偏移 / 三列 KPI：方位·高度·阶段）
   ├─ 曲线卡（Canvas 太阳高度曲线 + 当前时刻标记）
   ├─ 时段卡（日出/日落/黄金/蓝调 文本行）
   ├─ 权限门（showPermissionGate）与定位按钮
   └─ ErrorCard / SkeletonCard（错误与加载）
```

**状态（选取关键项）**：`ready`、`errorText`、`showPermissionGate`、`locating`、`nowUtc`、`selectedUtc`、
`sliderProgress`、`placeName`、`tzId`、`posAz`、`posAlt`、`phaseLabel`、`sunriseText`、`sunsetText`、
`goldenAmText`…（`@State` 共 20+ 项）；`@Prop refreshToken` + `@Watch('onRefreshToken')` 接收外壳刷新信号。

**布局约束**：单 `Scroll` + 竖排 `Column`；卡片间距 `Spacing.M`；KPI 三列等宽；曲线 Canvas 高度固定区间。
**可保留**：信息层级（eyebrow→标题→hero→KPI→曲线）、三列 KPI、阶段双通道徽标、权限降级门。
**必须重排**：hero 文案过长时的行数控制；曲线卡与时段卡的合并/折叠；宽窗口下的左右分栏（见响应式矩阵）。

## 3. 太阳轨迹（SunPathPage）现状

```text
Scroll
└─ Column
   ├─ TopBar
   ├─ 曲线卡（SunPathChart：日轨 + 地平线 + 当前点）
   ├─ 时刻卡（selectedLabel、方位/高度、阶段、合法性 azValid）
   ├─ 滑块（0..1000 进度 ↔ UTC 映射；DST 时显示偏移）
   ├─ 罗盘（方向视觉 + 校正 ±15°）
   ├─ 事件行（日出/日落/黄金/蓝调）
   └─ 保存计划入口（GAP/OVERLAP 校验）
```

**状态**：`ready`、`hasPlace`、`tzId`、`dayStartUtc/dayEndUtc`、`selectedUtc`、`sliderProgress`、
`selectedLabel`、`azText/altText`、`azValid`、`sunAz/sunAlt`、`sunriseText/sunsetText` 等。

**可保留**：滑块↔UTC 的唯一映射（含 DST）、真实日界曲线、校验后的保存路径。
**必须重排**：曲线与控件在宽屏的主从布局；时刻卡的层级（时间为主、误差为辅）；
罗盘与曲线并存时的视觉竞争；原稿的十字准星画布语言未实现，需视觉稿确认是否采纳。

## 4. 反向寻光（ReversePage）现状

```text
Scroll
└─ Column
   ├─ initError → ErrorCard（唯一整页错误）
   ├─ !ready → Skeleton；!hasPlace → EmptyState（去机位库）
   └─ 表单区
      ├─ 警示条（搜索失败原因）/ 部分结果提示
      ├─ 机位名
      ├─ 5 个参数（目标方位/高度、两轴容差、天数）+ 白昼开关
      ├─ 搜索按钮（id: reverse_search_btn）
      └─ 结果区
         ├─ 摘要 NoticeBar（id: reverse_summary）
         ├─ 空态文案（仅 DONE_EMPTY）
         └─ 窗口卡列表（时间/误差/窗口起止+偏移+时长/加入计划按钮，partial 时禁用）
```

**状态（27+ 项）**：表单输入 `azInput/altInput/azTolInput/altTolInput/daysInput/daylightOnly`；
运行态 `searching`、`sheetVisible/sheetPercent/sheetDetail`；结果 `candidates/windows/windowNotes/searched`；
终态 `errorText/partialResults/initErrorText/lastDecision`。

**事件接口**：`runSearch()`（会话分片推进 + 终态分派）、`cancelSearch()`、`addToPlan(candidate)`、
`initPage()`、`onNavigate(route)`、`nextFrame()`。

**可保留**：窗口语义（起止/时长/单点命中）、门禁（仅完整 DONE_OK 可加入计划）、
终态分派的纯逻辑（`SearchRunPolicy` + `ReverseViewState`）、搜索分片与取消。
**必须重排**：结果卡三行结构（时间 / 误差 / 范围）与按钮位置；参数区折叠（Compact 下单列过长）；
进度浮层的可取消性与遮挡关系；空态/失败态/取消态在同一区域的共存方式。

## 5. 仍未确认的问题（不得当作已解决）

「搜索结果终态不在自动化可见文本中」的**根因仍未完全确认**。已知证据：

- hilog 证明业务链路真实完成：`runSearch start → job created → session state=DONE(windows=4) →
  decision DONE_OK → job updated DONE`，内部 elapsed=1624ms；
- 同一时刻 `uitest dumpLayout` 可见文本仍为 31 条、摘要不在其中；
- 但**日志只能证明计算与状态写入，不能证明视觉渲染一定正确**。

可能原因（未验证，按优先级）：结果区位于当前视口之外且注入滚动无法到达；进度浮层/键盘遮挡；
渲染被布局约束裁切；组件树未因状态更新重建。UI-1B 开始前需要一次**结构化的渲染确认**
（例如先在结果区顶部放一条固定可见的摘要条，或改用 ArkUI 测试驱动 scrollTo），再谈端到端耗时。

## 6. UI-1B 的输入清单（缺一不可）

1. 正式视觉稿（含深色主题与 Compact 至少两档）；
2. 首页/太阳轨迹/反向寻光的 before 截图（当前构建重拍）；
3. 结果区「渲染确认」方案（见 §5）；
4. 视觉稿中的导航壳定义（底部 Tab 还是侧栏，何时切换）；
5. Token 裁决表（见 `UI0_DESIGN_SYSTEM.md` §3）确认后再动手改样式。
