# QA-1 · LightBearing 全项目质量审计

> 基准提交 `90e4f0e`，分支 `fix/core-quality-audit`，设备 MIA-AL00 / HarmonyOS 7 / API 26。
> 本轮只做审计：补充纯测试、取证、写文档；未重构、未改 Schema、未删数据、未动 main。
> 所有结论区分「源码确认 / 测试复现 / 未验证」。

## 1. 版本与审计范围

| 项 | 值 |
|---|---|
| 审计基准 | `90e4f0e`（2026-11-03） |
| 生产源码 | 38 个 `.ets`（pages 13、services 13、model 3、repository 1、utils 1、common 3、entryability/backup 2、components 2） |
| 测试源码 | `entry/src/test` 10 个文件 + `entry/src/ohosTest` 2 个文件 |
| 页面数 | 13 |
| 审计方式 | 源码通读关键路径 + grep 取证 + 宿主机测试固化 + 真机启动/切页计时 |
| 未覆盖 | 真机 UI 全页面截图与暗色/小屏/横竖屏视觉审计（本轮未做） |

## 2. 页面与核心服务清单

| 页面 | 职责 | 数据依赖 |
|---|---|---|
| `Index.ets` | 外壳、Tab 导航、引导状态 | settings、AppState |
| `HomePage.ets` | 今日光线、时段、曲线、快捷入口 | places、SolarCalc、Timeline |
| `SunPathPage.ets` | 太阳轨迹、罗盘、滑块、保存计划 | SolarCalc、TimeSelection |
| `CalendarPage.ets` | 月历、异常日期标记、CSV/PNG 导出 | SolarCalc、ExportService |
| `ComparePage.ets` | 多日期对照 | SolarCalc、Timeline |
| `CompassPage.ets` | 实时罗盘（setInterval） | SensorService |
| `LocationsPage.ets` | 机位列表/新增 | places |
| `PlaceDetailPage.ets` | 机位详情/编辑/删除 | places |
| `PlannerPage.ets` | 拍摄计划编辑、GAP/OVERLAP | plans、TimeSelection |
| `PlanDetailPage.ets` | 计划详情 | plans |
| `ReversePage.ets` | 反向寻光搜索与结果 | SearchSession/Policy、jobs、history |
| `SettingsPage.ets` | 阈值、主题、权限、备份 | settings |
| `MapPage.ets` | 地图选点（定位） | LocationService |

核心服务：`SolarCalc`、`TimeUtil`、`LocalTimeResolver`、`TimeSelection`、`Timeline(+Labels)`、`ReverseSearch`、`ReverseSearchKernel`、`SearchSession`、`SearchRunPolicy`、`ExportService`、`LocationService`、`SensorService`；数据层 `AppDb`；工具 `CsvCodec`。

## 3. 功能覆盖矩阵（摘要）

详见 `QA1_TEST_MATRIX.md`。概要：

| 领域 | 覆盖 | 状态 |
|---|---|---|
| 太阳位置/事件（2A） | 宿主机 99 条基线中约 30 条 | PASS |
| 时区/本地日（2B） | 宿主机 + 真机 `TimeZoneReal` 12/12 | PASS（原生滚轮手指操作 NOT_RUN） |
| 反向寻光内核（2C） | 宿主机 146 条 + 真机 `KernelPerfReal` 2/2 | PASS（部分场景 FAIL，见问题清单） |
| 计划/机位/日历 UI | 源码通读 | 未做真机逐步验收 |
| 数据层 | 源码通读（事务、user_version、CRUD） | 部分 FAIL（QA-03） |
| 安全/权限 | 源码 + manifest | PASS（无高风险） |

## 4. 数据库与数据流审计

- `AppDb` 使用 `RDB`，`PRAGMA user_version` + `beginTransaction/commit`，建表 `places / plans / settings / history / projects / file_assets / jobs`，`schema_version DEFAULT 2`，具备基本版本位。
- 计划表保存 `place_id` **以及** `place_name / lat / lon / tz` 快照 → 机位删除后计划仍可独立展示（这是设计上的缓解）。
- **`deletePlace()` 只删除 `places` 行**，不处理引用它的 `plans`（无外键、无级联、无置空）。
- 计划编辑 `PlannerPage.startEdit()` 通过 `place_id` 在 `places` 里查找，**找不到时 `idx` 保持 0**，静默回退到 `places[0]`（见 QA-03）。
- 保存路径使用 `INSERT OR REPLACE`/`UPDATE`（按 id），编辑不会新建重复记录（源码确认）。
- 导出：`ExportService` 用 `DocumentViewPicker` + `fileIo.writeSync`，CSV 由 `CsvCodec` 负责引号转义；**未写 BOM**（QA-05）。
- 未发现数据库 Schema 迁移脚本缺失以外的结构性问题；本轮未做迁移测试（NOT_RUN）。

## 5. 时区与太阳计算审计

- 2A/2B 结论仍成立：`SolarCalc` 与外部参考脚本 `tools/solar-check/check.mjs` 对照「全部通过」。
- `TimeUtil` / `LocalTimeResolver` 区分 GAP/OVERLAP/UNAVAILABLE、负时间戳合法、23/25/23.5/24.5 小时日由真实区间驱动。
- 真机 `TimeZoneReal` 12/12 通过（上一构建）。
- 未验证：原生 `DatePicker/TimePicker` 的真实手指操作（注入只改显示值、不触发 `onChange`），保持 NOT_RUN。

## 6. 搜索内核审计（P0 重点）

### 6.1 异常数据混合（QA-01，P1）

`SearchSession.finishRange()` 只有在**该区间没有任何有效跨度**且出现过非有限采样时才置 `FAILED`：

```ets
if (this.spanList.length === 0 && this.ctx.stats.nonFiniteSamples > this.rangeNonFiniteStart) {
  this.unreliableRanges++;
  this.state = SessionState.FAILED;
}
```

因此以下场景**全部按 DONE 完整成功**处理（宿主机用例固化，`SearchAnomalyAudit`）：

| 场景 | 用例 | 实测 |
|---|---|---|
| 同一天前半有效、后半 NaN/Infinity | `QA1-A1` | `DONE`，1 窗口，`nonFiniteSamples>0`，`unreliableRanges=0` |
| 同一天先 NaN、后出现有效窗口 | `QA1-A2` | `DONE`，1 窗口 |
| 第一天无命中；第二天前 3 分钟 NaN、7–8 分钟处有有效窗口 | `QA1-A4` | `DONE`，1 窗口 |
| 已有窗口后出现 Infinity | `QA1-A5` | `DONE`，`nonFiniteSamples>0` |
| 全天 NaN 且无窗口 | `QA1-A3` | `FAILED`（唯一被正确处理的路径） |

风险：搜索可能在「部分日期太阳位置不可用」的情况下宣称完整成功，并把结果写入历史。

> **状态更新（QA-2A，提交见 `QA2A_P1_FIXES.md`）**：QA-01 已修复——任何区间出现非有限采样都会使
> 会话终态为 `FAILED`（取消优先保持 `CANCELLED`），窗口作为部分结果保留且禁止加入计划。
> 上述表格保留为**修复前的原始证据**。

### 6.2 终态与 UI 一致性（QA-02，P1）

`SearchRunPolicy` 对「FAILED + 有部分窗口」返回 `showResults=true` 且 `errorText` 非空，
但 `ReversePage` 的渲染是互斥的 `if/else-if` 链：

```ets
if (this.errorText.length > 0) { ErrorCard(...) }
else if (!this.ready) { Skeleton }
else if (!this.hasPlace) { EmptyState }
else { 参数表单 + 结果列表 }
```

因此该组合下 **部分窗口永远不渲染**，连搜索表单也被 ErrorCard 顶掉；同时 `searched=true` 却无结果可见。

### 6.3 窗口正确性与独立参考（QA-07，P2）

36 目标网格只对比了「窗口数量一致」，**没有一对一区间匹配**，因此以下指标仍无数据：
边界误差、`bestUtc` 误差、窗口被拆分/误合并计数。经验变化率剪枝（高度 0.0045°/s、方位 0.05°/s）
与近天顶/高纬/短于 1 秒窗口的风险维持 2C 的结论（未证明完备）。

## 7. 安全与权限审计

| 项 | 结论 | 证据 |
|---|---|---|
| 申请权限 | 仅 `ohos.permission.APPROXIMATELY_LOCATION`、`ohos.permission.LOCATION`，`when: inuse` | `module.json5` |
| 网络请求 | **无**（无 `http(s)://`、无 `@ohos.net.*`） | 全仓 grep |
| 硬编码密钥/令牌 | **无** | grep `secret/token/password/apiKey` 仅命中设计 token 与 `seriesToken` 变量 |
| 调试入口残留 | **无**（`TEMP-TEST-ENTRY`、`BuildProfile` 均 0 命中） | grep |
| 日志 | 仅 hilog 输出计数/错误信息，无坐标明文批量打印 | `AppState`/`Theme`/`EntryAbility` |
| 数据外发 | 无网络代码 → 本地数据不外传 | 同上 |
| 导出 | 用户主动通过系统选择器保存，无静默写盘 | `ExportService` |

结论：安全面未见阻断级问题；定位为「使用中」授权，符合产品需要。

## 8. 性能与稳定性

| 指标 | 数值 | 方法 | 状态 |
|---|---|---|---|
| 冷启动到首屏可交互 | ≈1.38 s | `aa force-stop` → `aa start` → 轮询 dump 出现内容 | 已测（含 dump 轮询开销 ≤0.2s） |
| Tab 切页可见 | ≈1.35 s | 点击 Tab → 轮询 dump | 已测（同上，含注入开销） |
| 纯算法：365 天搜索 | 3 511 ms / 653 975 次 `position` | 会话层（补丁前版本真机） | 已测 |
| 单分片最大耗时 | 6 / 8 / 11 ms | `step(8)` | 已测 |
| **UI 端到端搜索耗时（含让帧 + Job 写入）** | 无 | — | **NOT_RUN**（自动化定位不到「搜索候选时段」按钮） |
| **UI 点击取消 → 搜索停止的端到端延迟** | 无 | — | **NOT_RUN**（同上；不能用会话层 0ms 代替） |
| 365 天 UI 搜索 | 无 | — | NOT_RUN |

稳定性：`CompassPage` 的 `setInterval` 在 `aboutToDisappear` 中 `clearInterval` 释放（源码确认）；
未发现全局未释放监听；异常退出后恢复未做破坏性测试（NOT_RUN，见 §12 限制）。

## 9. UI 与可访问性审计

- 13 个页面均具备空态/骨架/错误卡之一（每页 3–6 处），`ReversePage/CalendarPage/ComparePage` 均有显式错误提示。
- 文案：2C 已移除「5 分钟粗扫」描述；未发现其他过期算法文案。
- 已知不一致：QA-02 的错误卡与结果互斥（P1）。
- 未做：真机全页截图、深色模式、小屏、横竖屏、触控区域与色彩对比度核验（**NOT_RUN**，无截图证据不判定通过）。

## 10. 问题清单

### QA-01（P1，源码 + 测试复现）
- 位置：`SearchSession.finishRange()`（`entry/src/main/ets/services/SearchSession.ets`）
- 触发：同一区间内既有有效跨度又出现 NaN/Infinity
- 实际：`DONE` + 完整成功文案 + 写历史；`nonFiniteSamples>0`、`unreliableRanges=0`
- 预期：标注不完整或直接 `FAILED`，不得声称完整成功
- 证据：`SearchAnomalyAudit` 的 `QA1-A1/A2/A4/A5`（宿主机 146/146 通过，固化当前行为）
- 影响：结果可信度、历史记录正确性
- 建议：把 `nonFiniteSamples` 变化纳入区间可靠性判定（有窗口时标注「部分日期位置不可用」），并在 policy 中让 `unreliableRanges>0` 影响终态；补 4 条红绿用例
- 测试建议：上述 4 场景改为断言「不完整/FAILED」，并验证 Job 与历史不写成功

### QA-02（P1，源码确认；QA-2A 已修复）
- 位置：`ReversePage.ets` 渲染分支 + `SearchRunPolicy` 的 `showResults/errorText` 组合
- 触发：会话 `FAILED` 且已有部分窗口
- 实际：`ErrorCard` 顶掉结果与表单，部分窗口不可见，`searched=true` 却无结果
- 预期：错误提示与部分结果可同时表达（例如结果区顶部警示条），或明确「仅显示已完成部分」
- 建议：把 ErrorCard 从互斥分支改为在结果区上方追加警示；表单始终可达
- 测试建议：页面级渲染条件抽成可测函数（给定 decision → 是否渲染表单/结果/错误）

### QA-03（P1，源码确认；QA-2A 已修复）
- 位置：`PlannerPage.startEdit()`（`idx` 默认 0，无匹配分支） + `AppDb.deletePlace()`（只删 places）
- 触发：删除某机位后编辑引用它的旧计划
- 实际：静默切到 `places[0]`，保存会把计划的机位/坐标改写成另一个机位
- 预期：提示「原机位已删除」并阻止静默替换，或保留计划的坐标快照并标注来源机位缺失
- 建议：`startEdit` 增加「找不到机位」分支（保留快照坐标 + 提示），保存时不要覆盖 place_id；或删除机位时把关联计划的 `place_id` 置空并提示
- 测试建议：纯逻辑测试（给定 plans/places → 编辑上下文），断言不静默改机位

### QA-04（P2，测试复现；QA-2A 已修复）
- 位置：`SearchRunPolicy.decide()` 的 `unreliableRanges` 形参
- 实际：不同取值产生完全相同的决定（死参数）
- 证据：`QA1-B1`
- 建议：随 QA-01 一并接入决策，或删除参数

### QA-05（P2，源码确认）
- 位置：`ExportService`（`fileIo.writeSync` 写字符串，无 BOM）
- 实际：CSV 在 Excel 中可能把中文显示为乱码
- 建议：写文件前加 UTF-8 BOM（`\uFEFF`）并提供测试

### QA-06（P2，源码确认）
- 位置：`components/Widgets.ets` 990 行、`PlannerPage.ets` 821 行、`Index.ets` 675 行
- 建议：按功能拆分组件（非本轮）

### QA-07（P2，未验证）
- 一对一窗口参考匹配缺失：边界误差、bestUtc 误差、拆分/误合并计数无数据
- 建议：Node 侧同步内核镜像后按区间重叠 + 一对一分配统计

### QA-08（P2，未验证）
- UI 端到端搜索耗时与取消延迟未测（自动化无法定位搜索按钮）
- 建议：提供稳定可访问的测试标识（`id`）或手工计时表，避免再引入临时 Debug 入口

### QA-09（P2，未验证，承接 2B）
- 原生 `DatePicker/TimePicker` 真实手指操作未验证；注入只改显示值、不触发 `onChange`

## 11. 已验证与未验证

**已验证（本轮）**：源码清单与权限、搜索异常混合行为（4 个场景测试固化）、死参数（测试）、
ErrorCard 与结果互斥（源码）、删除机位后的编辑回退（源码）、CSV 无 BOM（源码）、冷启动 1.38s、
Tab 切页 1.35s、宿主机 146/146、太阳参考对照通过。

**未验证**：全页真机 UI 截图与深色/小屏/横竖屏；UI 端到端搜索耗时与取消延迟；365 天 UI 搜索；
数据库迁移/导入手动测试；异常退出恢复；原生滚轮手指操作；一对一窗口参考匹配。

## 12. 发布风险评估

| 维度 | 风险 | 说明 |
|---|---|---|
| 数据正确性 | **中高** | QA-01（异常数据仍宣称完整成功）、QA-03（编辑静默换机位）都可能污染用户数据 |
| UI 一致性 | 中 | QA-02 让失败场景的部分结果不可见 |
| 计算正确性 | 中低 | 2A/2B/2C 核心留有 146 条宿主机回归 + 真机时区/性能用例 |
| 安全 | 低 | 仅 2 项定位权限、无网络、无硬编码密钥、无调试残留 |
| 性能 | 中低 | 冷启动 1.38s、切页 1.35s 可接受；365 天搜索 3.5s（会话层）需 UI 层实测 |
| 未验证面 | 中 | UI 视觉与端到端交互指标缺失 |

结论：**不建议在当前状态下直接发布**；QA-01/QA-03 属于用户数据正确性风险，应在发布前修复并回归。

> **QA-2A 后更新**：QA-01/QA-02/QA-03/QA-04 已修复并有 163/163 宿主机回归 + 真机两套用例通过；
> QA-05～QA-09 与 QA-1 的 NOT_RUN 项仍未处理，发布风险评估相应下降一档（仍建议先补 QA-08 的 UI 端到端证据）。

## 13. 推荐修复顺序

1. **QA-01** 异常数据终态（P1，数据正确性）——最小改动：`finishRange` 记录区间可靠性，`policy` 对 `unreliableRanges>0` 输出「不完整」，补 4 条红绿用例。
2. **QA-03** 计划编辑与已删机位（P1，数据正确性）——加「机位缺失」分支，禁止静默替换。
3. **QA-02** FAILED 与部分结果同时可见（P1，UI）——错误卡改为结果区顶部警示。
4. **QA-04** 死参数随 QA-01 处理；**QA-05** CSV BOM（一行修复 + 测试）。
5. **QA-08/QA-07** 补可靠的可测标识与一对一窗口匹配评测，再补 UI 端到端与视觉审计。
6. **QA-06** 组件拆分放到末期（纯结构）。

## 14. 剩余限制（如实声明）

- 本轮未执行真机 UI 截图与视觉审计，因此「布局/暗色/小屏/横竖屏」一律不判定通过。
- 冷启动与切页数字包含 `uitest dumpLayout` 轮询开销（约 0.1–0.2s），为上限估计而非精确首帧时间。
- 未做数据库迁移、导入异常、异常退出恢复的破坏性测试（按要求不使用用户数据）。
- 未新增临时 Debug 入口，也未触碰 TEST 机位与用户数据。
