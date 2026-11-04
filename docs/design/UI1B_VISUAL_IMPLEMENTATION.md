# UI-1B · 首页视觉重构与高保真原型实现报告

> 起点 `bc837aa` → 本轮提交见汇报。分支 `fix/core-quality-audit`，未改 main。
> 设计方向：**Solar Observatory / Professional Photography Workbench**（深色专业工作台）。
> 本轮**未**改动太阳算法、搜索内核、DST、数据库 Schema、签名材料与 TEST 机位数据。

## 1. 设计选择与理由

| 决策 | 理由 |
|---|---|
| 深色为首要方向（`#0D1A29` / `#182C3D` / `#213B4E`） | 摄影场景多在弱光下使用；深色底能突出琥珀色太阳数据与青色参考值 |
| 首页首屏 = 机位条 + 当前光线仪表（方位/高度大数字） | 摄影师的第一判断是「此刻方位/高度是否可用」，而不是看欢迎语 |
| 移除大 hero 欢迎卡 | 旧版首屏被营销文案占据；新版首屏直接给出可判断的数据 |
| 关键时段改 2×2 仪表格 | 旧版是 7 行文本列表，密度低；2×2 网格让日出/日落/黄金随时可扫读 |
| 表格数字与标签分离（24–36vp 数字 + 11–12vp 标签） | 建立「仪表读数」层级，避免所有文字同等竞争 |
| 圆角 18 / 控件 12 / 触控 48 | 与 UI-0 裁决一致；44 为保底、48 为新基线 |
| 浅色主题同步调整为暖纸基底（`#F4F1EA` / `#9A5A0C` / `#116C69`） | 深色不是唯一用户；浅色需保持可读对比而不是简单反色 |

## 2. 高保真原型（可渲染，非文档）

| 文件 | 内容 |
|---|---|
| `design/ui1b/index.html` | 原型索引 + **Token 精确表** + 排版与数字规则 |
| `design/ui1b/tokens.css` | 颜色/间距/圆角/字级/触控/动效变量（即 ArkTS 落地目标值） |
| `design/ui1b/home.html` | 今日光线：**Compact 390×844 / Expanded 1024×768 / Large 1440×900** |
| `design/ui1b/sunpath.html` | 太阳轨迹：Compact + Expanded（含高度刻度、地平线、黄金/蓝调带、DST 提示） |
| `design/ui1b/reverse.html` | 反向寻光：Compact 五状态（RUNNING/DONE_OK/DONE_EMPTY/FAILED/CANCELLED）+ Expanded |
| `design/ui1b/shots/*.png` | 原型渲染图（Edge 无头，按档位单独出图）：`home_compact.png`(390×844)、`home_expanded.png`(1024×768)、`home_large.png`(1440×900)、`sunpath_compact.png`、`sunpath_expanded.png`、`reverse_states.png`（五状态合并）、`home.png`（三档对照）、`sunpath.png`（两档对照）、`tokens.png`（Token 表） |

原型渲染方式：Edge 无头模式本地渲染（`--headless=new --screenshot`），**不是** WebView 方案，
也不参与构建。所有数值均标注为设计数据。

## 3. ArkTS 实现范围

| 文件 | 改动 |
|---|---|
| `entry/src/main/ets/pages/HomePage.ets` | **构建器重写**：新增 `slimHeader / stationHeader / instrumentPanel / eventsGrid / eventTile / quickActions`；`build()` 重组为 Compact → 双栏（≥600vp）→ 三区工作台（≥1200vp）；新增 `isWide` 状态 |
| `entry/src/main/ets/common/Theme.ets` | 新增 `FontSize.DISPLAY=36`、`Radius.SHEET=24`、`Motion`（120/200/280ms） |
| `entry/src/main/resources/base/element/color.json` | 浅色改为暖纸基底：`#F4F1EA / #FFFFFF / #EBE6DB / #9A5A0C / #116C69 / #141F2A / #52646F / #DCD5C6` |
| `entry/src/main/resources/dark/element/color.json` | 深色对齐品牌：`#0D1A29 / #182C3D / #213B4E / #FFBC6B / #73D9D5 / #F9FAF3 / #A2B9C5` |

**保留未动**：`SolarCalc` / `TimeUtil` / `Timeline` / `Charts.SunPathChart` / 搜索内核 /
`AppDb` / 计划与机位业务逻辑。首页图表仍由真实日界、真实太阳位置驱动，滑块仍是 0..1000 ↔ UTC 映射。

## 4. 与旧首页的实质改变

| 维度 | 旧版 | 新版 |
|---|---|---|
| 首屏内容 | 大 hero 欢迎卡 + 说明文案 | 机位条 + 当前光线仪表（方位/高度为主数字） |
| 信息层级 | 卡片等权堆叠 | 仪表 → 轨迹 → 时段 → 计划 → 操作，单一主信息流 |
| 时段展示 | 6 行文本 + 1 行民用曙光 | 2×2 仪表格（日出/日落/黄金晨/黄金夕）+ 算法说明降为脚注 |
| 快捷操作 | 隐藏在 hero 卡两个按钮 | 表单底部固定两个主/次按钮 |
| 宽屏 | 仅 600vp 双栏 | 600vp 双栏 + 1200vp 三区（中央观测 + 右侧检查器 320vp） |
| 视觉语言 | 浅色通用 Dashboard | 深色观测仪表（琥珀=太阳、青=参考、纸=文本） |

## 5. 多设备布局预览状态

| 档位 | 原型 | ArkTS 实现 | 真机验证 |
|---|---|---|---|
| Compact（手机） | 已设计（home/sunpath/reverse） | 已实现（单列） | **BLOCKED**（见 §7） |
| Medium（600–839） | 复用 Expanded 结构 | 已实现（双栏） | **NOT_RUN** |
| Expanded（840–1199） | `shots/home.png` 右幅 | 已实现（双栏） | **DESIGN_PREVIEW**（无平板/折叠设备） |
| Large（≥1200） | `shots/home.png` 第三幅 | 已实现（三区） | **DESIGN_PREVIEW** |

> 大屏一律为 DESIGN_PREVIEW，不得写成已通过折叠屏/平板真机验证。

## 6. 动效与 API 26 兼容

- 本轮**未启用**新动效：`animateTo` / `sharedTransition` / `PanGesture` 在仓库中仍为零引用
  （与 UI-1A 的核实一致），因此只落地了时长常量（`Motion`），没有引入未经探针验证的动画 API；
- 设计侧已定义：Tab 切换 160–200ms、页面进入 240–280ms、结果出现 180ms、进度步进 120ms，
  并明确「动画不得改写 UTC/进度/表单状态」；
- 减少动态效果（系统设置）读取**仍未验证**，保持 NOT_RUN。

## 7. 真机截图与验收状态（重要，如实记录）

| 项目 | 文件 | 状态 |
|---|---|---|
| 改版前首页 | `docs/screenshots/ui1b_before_home.jpeg` | ✅ 已存在（QA-2C 期间在 728b9cf 构建采集的真实设备首页） |
| 改版后深色 | `docs/screenshots/ui1b_after_home_dark.jpeg` | **NOT_RUN** |
| 改版后浅色 | `docs/screenshots/ui1b_after_home_light.jpeg` | **无效**：采集时设备已锁屏，截图内容是锁屏/桌面壁纸（非应用界面），不得作为验收证据 |
| 空机位 / 权限拒绝 | — | **NOT_RUN**（需要改变机位/权限状态，本轮不做破坏性操作） |
| 原型与真机并排对照 | — | **NOT_RUN**（缺有效真机截图） |

阻断原因（多次重复取证）：本轮新 HAP 已成功构建并安装（`install bundle successfully`），但设备处于
**锁屏状态且无法通过注入解锁**：

```text
aa start → Error 10106102 The device screen is locked during the application launch
power-shell wakeup + dircFling 2 ×3  → 仍在桌面（11月4日 / 应用市场 / 中国电信）
power-shell wakeup + swipe 540,2300→540,500 ×1 → 锁屏提示「未识别成功，点击此处重试」（人脸解锁失败）
```

即：**需要用户解锁一次设备**才能继续采集。设备解锁后需补：浅色/深色首页、空机位态、权限拒绝态、
原型与真机并排对照，以及 `KernelPerfReal` / `TimeZoneReal` 两套真机用例。
因此：

- **没有**任何「改版后」的真实截图，也**没有**并排对照图；不得用锁屏截图冒充；
- 首页新代码在真机上的**运行时表现（是否白屏/崩溃）本轮未验证**，只完成了编译通过与 HAP 构建；
- 需要设备解锁后补做：浅色/深色首页截图、空机位态、权限拒绝态、并排对照。

## 8. 兼容性与回归（本轮实际执行）

```text
宿主机：Tests run: 197, Failure: 0, Error: 0, Pass: 197      （基线保留，未新增/未删减）
外部太阳参考：node tools/solar-check/check.mjs → 全部通过
应用 HAP：BUILD SUCCESSFUL，2,344,893 字节
真机安装：install bundle successfully（新首页已装入设备）
真机单元测试：aa test → Error 10106102（设备锁屏，无法启动），本轮未取得结果
```

真机视觉验收因此为 **BLOCKED**：设备锁屏且无法通过注入解锁（见 §7），
不得用锁屏截图或模拟图替代，也不得把 HAP 构建通过当作视觉验收。

## 9. 未完成的视觉问题

1. 首页图表仍复用旧 `SunPathChart`（160–200vp 高度），尚未按原型实现「地平线 + 高度刻度 + 黄金/蓝调色带」的完整观测图；
2. 仪表盘未实现原型中的迷你日轨弧线（当前用大数字 + 时段网格替代，信息完整但视觉密度低于原型）；
3. Large 三区未含左侧导航栏（导航仍在 `Index` 外壳，跨页改造属于 UI-2 范围）；
4. 深色主题下 `Charts` 的 Canvas 配色是否与新 Token 协调，未经真机确认。

## 10. SunPath / Reverse 的下一轮交接点

- **SunPath**：把 `timeSection()` 拆为 `ObservationCanvas`（曲线 + 地平线 + 高度刻度 + 时段带）
  与 `TimeScrubber`（滑块 + 读数）两个组件；数据源保持不变（`Timeline` + `SolarCalc`）；
  原型见 `design/ui1b/sunpath.html`，DST 状态需用 `TimeUtil.resolveLocal` 的结果驱动文案。
- **Reverse**：新增粘性状态条（`RUNNING/DONE_OK/DONE_EMPTY/FAILED/CANCELLED` 五态，
  图标+标题+说明+操作），搜索结束必须让终态进入可视区（固定状态条或自动滚动到状态条），
  部分结果禁用「加入计划」保持不变；原型见 `design/ui1b/reverse.html`。
- 两页都先做「渲染确认」（状态条可见性）再谈端到端耗时。
