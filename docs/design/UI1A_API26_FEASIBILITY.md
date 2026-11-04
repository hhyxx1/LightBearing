# UI-1A · API 26 可行性与 OHPM 调研

> 基准 `7e8cf8b`，设备 MIA-AL00 / HarmonyOS 7 / API 26。
> 原则：**只记录已核实的能力**；未验证项一律标 `UNVERIFIED`，不得据自研现状否定三方库价值。

## 1. 项目内已核实可用的 ArkUI 能力

来源：`entry/src/main/ets` 全仓扫描 + 实际构建/真机运行。

| 能力 | 证据（文件/行） | 状态 |
|---|---|---|
| `Navigation` + `NavDestination` 页面栈 | `pages/Index.ets:614`（`Navigation(this.pathStack)`）、`:194`（`NavDestination()`） | **VERIFIED**（构建 + 真机运行） |
| `Canvas` / `CanvasRenderingContext2D` 自绘图表 | `components/Charts.ets`、`pages/HomePage.ets`、`services/Timeline.ets` | **VERIFIED** |
| `Scroll` / `List` / `ForEach` / `Column` / `Row` / `Stack` | 各页面与 `components/Widgets.ets` | **VERIFIED** |
| `Button` / `Text` / `TextInput` / `Image` / `LoadingProgress` | 各页面 | **VERIFIED** |
| `DatePicker` / `TimePicker`（含 `onChange`） | `PlannerPage.ets`、`CalendarPage.ets` | **VERIFIED（程序触发）**；真人手指操作 **NOT_VERIFIED** |
| `Slider`（0..1000 ↔ UTC 映射） | `HomePage.ets`、`SunPathPage.ets`、`TimeSelection.ets` | **VERIFIED** |
| `@ohos/hypium` 单元测试（宿主机 + ohosTest） | `entry/src/test`、`entry/src/ohosTest` | **VERIFIED**（197 host + 设备两套） |
| `hilog` 结构化日志（domain + tag） | `pages/ReversePage.ets`（`LBSearch`）等 | **VERIFIED** |
| Kit：AbilityKit / PerformanceAnalysisKit / BasicServicesKit / LocalizationKit / CoreFileKit / ArkUI / ImageKit / SensorServiceKit / LocationKit / InputKit / ArkData | 全仓 import 统计（次数 20/11/6/3/3/3/2/1/1/1/1） | **VERIFIED**（编译与运行） |

## 2. 项目内**未使用**、因此未核实的能力

以下能力在仓库中**零引用**（grep 无命中），UI-1B 若要用必须先做最小能力探针：

| 能力 | 用途 | 状态 |
|---|---|---|
| `animateTo` | 显式属性动画 | **未使用 / UNVERIFIED** |
| `sharedTransition` | 卡片共享元素转场 | **未使用 / UNVERIFIED** |
| `PanGesture` / `Gesture` / `TransitionEffect` | 手势与转场效果 | **未使用 / UNVERIFIED** |
| 窗口尺寸变化监听（`WindowSizeChange` 等） | 响应式断点实时重算 | **未核实**：现状 `Index.ets:672` 只有 `width >= 600` 的比较，宽度来源未在本轮确认 |
| 无障碍「减少动态效果」读取 | 动效降级 | **未使用 / UNVERIFIED** |
| 系统分享 / 接续 / 分布式 | 多端协同 | **未使用 / UNVERIFIED** |

## 3. 自适应导航 / 双栏 / 图表 / 转场 / 共享元素 / 动效的技术约束

| 需求 | 已核实的约束 | UI-1B 必须补的探针 |
|---|---|---|
| 自适应导航（底部 Tab ↔ 侧栏 ↔ 多栏） | 现有外壳是单一 `Navigation` + 路径栈，页面切换集中在一处；宽度判断是硬编码 600 | 宽高实时变化的重建是否保留页面状态（尤其 Planner 编辑态） |
| 双栏工作区 | 现无任何双栏实现；`Column/Row` 布局能力已可用 | 窄屏回退、折痕区域是否可安全跨越 |
| 图表 | Canvas 自绘已验证；自研 `Charts.ets` 已有 SunPathChart/CompareChart | 高 DPI 下的清晰度、长列表中的重绘稳定性 |
| 页面转场 | `Navigation`/`NavDestination` 可用，但项目未定制转场 | 自定义转场是否与栈返回手势冲突 |
| 共享元素 | 完全未使用 | `sharedTransition` 在 API 26 与当前 Navigation 结构的可用性 |
| 动效 | 无 `animateTo` 使用记录 | `animateTo` + 手势跟随 + 减动效读取 |

> 结论：**导航/双栏/图表**已有可核实基础；**转场/共享元素/动效/响应式**属于未验证区，必须先探针再进设计实现。

## 4. OHPM 中心仓调研（本轮实际检索）

> 方法：公开检索（Gitee/GitHub/ohpm 镜像与社区索引）。**未安装任何依赖、未在 API 26 实机运行**。
> 版本号在不同来源存在分歧，落地前必须用 `ohpm info <package>` 在本机复核。

| 包 | 声称许可 | 版本证据（来源） | API 26 兼容 | 状态 |
|---|---|---|---|---|
| `@ohos/mpchart` | **Apache-2.0**（多来源一致） | Gitee `OpenHarmony-TPC/ohos_mpchart` releases 至 **3.0.21**；社区索引列 **3.0.31**；另有博客称 **4.0.0-rc.2**（gitcode 仓库） | 未验证 | **许可 VERIFIED / 版本有分歧 / 兼容 UNVERIFIED** |
| `@ohos/lottie` | **MIT**（`ohpm info` 输出样例显示 `@ohos/lottie@2.0.10 | MIT`） | 存在 **2.0.16** 的 ohpm tarball（`harmony-utils` 锁文件 `ohpm.openharmony.cn/ohpm/@ohos/lottie/-/lottie-2.0.16.har`） | 未验证 | **许可 VERIFIED（单来源）/ 版本 VERIFIED（2.0.16 存在）** |
| `@pura/harmony-utils` | **Apache-2.0** | GitHub `787107497/harmony-utils`（homepage 指向 ohpm 详情页，122 stars） | 未验证 | **许可 VERIFIED** |
| `@pura/harmony-dialog` | **Apache-2.0** | 社区索引：`@pura/harmony-dialog` v**1.1.8** | 未验证 | **许可 VERIFIED / 版本单来源** |
| `@ohos/lottie-turbo` | — | 本轮未检索到可查证条目 | 未验证 | **UNVERIFIED** |
| `@ohos/rebound` | — | 本轮未检索到可查证条目 | 未验证 | **UNVERIFIED** |
| `@ohos/svg` | — | 本轮未检索到可查证条目 | 未验证 | **UNVERIFIED** |

### 4.1 来源与可复核路径

- `@ohos/mpchart`：Gitee `openharmony-tpc/ohos_mpchart`（releases 列表）；社区索引 `ohpm-awesome`；
  51CTO 文章（含「包名/版本/协议」字段）。
- `@ohos/lottie`：社区问答给出的 `ohpm info` 输出样例；GitHub `787107497/harmony-utils` 的
  `oh-package-lock.json5`（含 ohpm tarball URL 与版本）。
- `@pura/harmony-utils` / `@pura/harmony-dialog`：GitHub 仓库 README 的 License 段与社区索引版本号。

### 4.2 复核命令（下一步必做，本轮未执行安装）

```bash
ohpm info @ohos/mpchart
ohpm info @ohos/lottie
ohpm info @pura/harmony-utils
ohpm info @pura/harmony-dialog
# 对未查证项
ohpm info @ohos/lottie-turbo
ohpm info @ohos/rebound
ohpm info @ohos/svg
```

### 4.3 初步建议（在复核之前不落地）

1. **不批量安装**：本轮 0 依赖，`oh-package.json5` 未改动；
2. `mpchart`：现有自研图表已覆盖太阳曲线与对照曲线，引入前需证明「原生 Canvas 做不到」的具体缺口
   （例如交互式缩放/大数据量标记），并测 HAP 增量；
3. `lottie`/`lottie-turbo`：只在视觉稿出现复杂矢量动效时才评估，且两者择一；
4. `pura/*`：与现有 `Widgets.Dialogs`、`TimeUtil` 功能重叠，除非视觉稿要求其特定弹窗形态；
5. 任何引入都必须附：版本、许可原文链接、API 26 实机 demo、HAP 增量、回滚方案。

## 5. 本轮状态

- 代码改动：**0**（未改业务组件、Token、导航、数据库、搜索内核）；
- 依赖安装：**0**；
- 文档交付：`UI1A_SCREENSHOT_INDEX.md`、`UI1A_IMPLEMENTATION_HANDOFF.md`、`UI1A_API26_FEASIBILITY.md`。
