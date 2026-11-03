# 02C-3 · 反向寻光全局搜索、取消调度与性能验收

> 基准 `ab35074`，工作分支 `fix/core-quality-audit`。本轮只整合 2C-2 的内核：上下文隔离、可恢复分片、
> 全局窗口层、页面接入与性能验收。未改太阳公式、时区解析、数据库 Schema 与 main。

## 1. 新旧算法正确性对比（36 目标网格，上海 2026-10-30 本地日）

同一批目标（每 40 分钟取一点、偏移 2.5 分钟，共 36 个），1 秒参考扫描给出的窗口数量与两种实现的对比：

| 容差 | 参考窗口数 | 旧算法命中目标 | 新内核命中目标 | 新内核窗口数 |
|---|---|---|---|---|
| 0.05° | 36 | 0/36 | **36/36** | 36 |
| 0.1° | 36 | 0/36 | **36/36** | 36 |
| 0.2° | 36 | 0/36 | **36/36** | 36 |
| 0.5° | 36 | 5/36 | **36/36** | 36 |
| 1.0° | 36 | 32/36 | **36/36** | 36 |
| 2.0° | 37 | 36/36 | **36/36** | 37 |
| 3.0° | 37 | 36/36 | **36/36** | 37 |

结论：容差 ≤ 1° 时旧算法漏报 4–36 个目标，新内核全部找到；**窗口数在每一档都与 1 秒参考完全一致**
（36/36/36/36/36/37/37）。这是「数量级一致」的证据，**不是**一对一区间匹配（见 §2）。

## 2. 参考窗口一对一匹配的现状（诚实说明）

- 新内核的上述数字来自 ArkTS 侧临时探针（统计每个目标找到的窗口数，已移除），
  与 2C-1 的 1 秒参考窗口数按档位对比；
- **尚未实现严格的「一对一区间匹配」**：`tools/reverse-check/scan.mjs` 仍只评测**旧算法镜像**，
  因为 Node 侧没有新内核镜像；若在 Node 侧另写一个内核镜像，就有与生产实现漂移的风险；
- 因此以下指标本轮**未产出**：边界误差、bestUtc 误差、被拆分/被错误合并窗口数、一对一召回率；
- 已有的替代证据（ArkTS 测试，非 Node）：候选数 == 窗口数、窗口两两不重叠、两个隔 10 秒的独立窗口保持 2 个、
  相邻日窗口合并后重新校验 best。

下一阶段计划把内核镜像同步到 Node 并做一对一匹配（见 §12）。

## 3. 变化率包络的适用范围与风险

`KernelRunner` 的剪枝依据是**经验性**变化率上界，不是形式化证明，统计字段已改名为
`empiricalValidChunks` / `empiricalInvalidChunks`，并新增 `resolutionLeaves` 与 `unresolvedIntervals`。

| 参数 | 值 | 适用条件 | 风险 |
|---|---|---|---|
| `ALT_RATE_DEG_PER_SEC` | 0.0045 | 全天 | 极区、极昼夜边缘未做误差界推导 |
| `AZ_RATE_DEG_PER_SEC` | 0.05 | 相邻采样 \|Δaz\| ≤ 30° 且高度 < 80° | 近天顶方位突变时**不使用**该上界（强制细分），但无形式化保证 |
| `AZ_CONTINUITY_LIMIT_DEG` | 30 | 超过即视为不连续 | 采样点之间的突发变化可能未被识别 → 只会更保守（继续细分），不会错误剪枝 |
| `ZENITH_LIMIT_DEG` | 80 | 超过即放弃方位上界 | 同上 |

`unresolvedIntervals = 0` 只说明「本轮样本没有撞到最大深度」，**不代表数学完备**。
在宿主机与真机的 1/14/365 天样本中该值均为 0，最大深度 17/18。

## 4. 增量式搜索状态机

`services/SearchSession.ets`：

```text
SearchSession(goal, thresholds, ranges, evaluator?, stats?)
  ├─ 私有 KernelContext（目标 / 求值器 / 采样缓存 / 统计，全部会话私有）
  ├─ 显式区间栈：[a, b, depth] 展平存放，可随时中断
  ├─ step(budgetMs) → 是否结束；预算内推进，超出即返回 false
  ├─ getProgressPercent()：按已处理的真实 UTC 毫秒 / 区间总毫秒
  ├─ getCurrentRangeStartUtc()：用于显示正在搜索的当地日期
  ├─ getWindows()：已完整处理区间产出的窗口（部分结果时也返回）
  └─ cancel() / getState()：RUNNING → DONE / CANCELLED / INVALID
```

关键点：窗口只在**一个区间完全处理完**之后聚合，所以分片不会把跨分片的连续窗口拆开；
跨区间衔接由 `finalizeWindows` 统一处理（只合并真正相接的窗口）。

## 5. 取消响应语义

| 要求 | 实现 | 证据 |
|---|---|---|
| 取消后新分片不再开始 | 循环每次 step 前检查 `cancelRequested`，置位后调用 `session.cancel()` | `cancel_marks_incomplete_not_done` |
| 当前分片及时结束 | 分片预算 12ms，实测单分片 ≤ 11ms | 真机 `maxSlice` 6/8/11ms |
| Job：RUNNING → CANCELLED | 页面用 `SessionState.CANCELLED` 决定job状态 | 设备用例 `cancelLatencyMs=0 state=2` |
| 部分结果不标为完整 | 摘要前缀「已取消（未完成）」；不写历史 | 页面代码 + 用例 |
| 失败用 FAILED | 参数非法/异常走 catch → FAILED | `invalid_parameters_rejected_not_no_hit` |
| 反复搜索不混入旧结果 | 每次 `runSearch` 先清空 candidates/windows/notes；机位切换丢弃结果 | 页面 stale guard |

**取消延迟真机实测 0 ms**（只置状态位）；页面层面从点击到下一分片结束 ≤ 一个分片（≤11ms）+ 一帧。

## 6. 搜索上下文隔离

内核不再有进程级静态可变状态：`cachedT` / `cachedPos` 属于 `KernelContext`，目标与 evaluator 也在上下文内。
静态门面 `ReverseSearchKernel.setEvaluator()` 仅用于 2C-2 的兼容测试路径，页面走 `SearchSession`（显式上下文）。

用例 `interleaved_sessions_do_not_pollute_each_other`：两个会话（不同目标、同一 evaluator）交替 `step(1)` 推进，
各自结果与单独运行一致（1 个窗口 vs 0 个窗口），证明采样缓存与目标不会互相污染。

## 7. 跨日窗口合并规则

`ReverseSearch.finalizeWindows(goal, thresholds, raw, mode, maxResults, evaluator?, stats?, ranges?)`：

1. 按 `startUtc` 排序；
2. 只有 `next.startUtc <= last.endUtc + 1`（真正相接/重叠）才合并；被跳过或不可用的日期形成真实缺口，**不会跨空白合并**；
3. 合并后边界变化的窗口用同一套内核重新求 best，并再次校验双容差、`daylightOnly`、有限性、窗口范围；
4. 未合并的窗口也校验 `bestUtc ∈ [startUtc, endUtc)`，不满足则重算或丢弃；
5. 不使用 24 小时常量，23/25/23.5/24.5 小时日由调用方传入的真实区间决定。

用例：`adjacent_ranges_merge_but_real_gap_does_not`（相接 → 1 个窗口；缺一天 → 2 个窗口）；
`various_local_day_lengths_are_respected`（23/25/23.5/24.5 小时各自 1 个窗口且时长精确）。

## 8. Top-K 与排序评分

统一评分：**归一化相对误差**

```text
score(window) = bestAzError / max(azTolerance, 1) + bestAltError / max(altTolerance, 1)
```

- 零容差按 1 处理，避免除零；有效性仍由「两轴独立容差 + daylightOnly」决定，评分只用于**有效窗口之间**排序；
- 同分按 `bestUtc` 升序，保证可复现；
- `Candidate` 兼容包装仍保留原始 `azError`/`altError`，便于界面展示；兼容接口 `searchInRanges` 仍按
  `azError+altError` 升序（**明确标注为旧语义兼容**，页面不再使用它排序）；
- 模式 A（`WindowSortMode.BEST`，默认）：有界插入 Top-K，严格按 score，不按日期分摊；
- 模式 B（`DISTRIBUTION`）：按所属区间（本地日）分组，组内按 score 排序后轮流取，保证多日都有机会；
  只在纯逻辑层实现并测试，UI 未加切换控件（避免无功能控件）。

用例覆盖 K=1/2/30、`totalBeforeCut`、可复现性、非对称容差（azTol 0.5 / altTol 5 时 0.4/0.4 优于 0.1/4.8）、
非法 K（0 / 1001）返回 `errorText` 而不是「0 个命中」。

## 9. ReversePage UI 调整

| 项 | 变化 |
|---|---|
| 进度 | 按「已处理真实 UTC 时间 / 总时间」计算，而不是完成几天 |
| 当前日期 | 浮层显示正在搜索的当地日期（来自 Session 当前区间起点） |
| 取消 | 分片之间即可生效（真机 0ms 置位，≤11ms 分片收尾） |
| 结果 | 每个窗口显示 `窗口 HH:mm（UTC±偏移）– HH:mm · 约 N 分钟`，单点命中/不足 1 分钟单独标注 |
| 计划 | 「加入拍摄计划」使用窗口的 bestUtc（与展示的最优时刻一致） |
| 陈旧结果 | 搜索期间切换机位 → 结果清空并提示重新搜索 |
| 文案 | 删除「按 5 分钟粗扫并逐级细化」，改为「自适应区间搜索（1 秒边界）」 |
| 未判定区间 | `unresolvedIntervals > 0` 时在摘要里明确提示 |

## 10. 真机性能数据（MIA-AL00，2026-11-03）

设备 `MIA-AL00 / HarmonyOS 7.0.0.109 / API 26`，上海 31.2304/121.4737，容差 3°，分片预算 8ms：

| 天数 | 墙钟耗时 | position 调用 | 窗口数 | 分片数 | 单分片最大 |
|---|---|---|---|---|---|
| 1 | 6 ms | 1 342 | 1 | 1 | 6 ms |
| 14 | 65 ms | 15 838 | 11 | 9 | 8 ms |
| 365 | 3 511 ms | 653 975 | 40 | 439 | 11 ms |

- `unresolvedIntervals = 0`；最大深度 17/18；
- 取消延迟：**0 ms**（`state=2 CANCELLED`，已保留 11 个窗口作为部分结果）；
- 注：以上为补丁前版本设备数据；补丁后版本设备回归见文末。
- 宿主机（x86，2C-2 单次全跑）对比：1 天 14ms、365 天 7 181ms —— 真机 365 天反而更快，
  因为宿主机数字包含逐日循环与探针开销，两者不可直接比较，**本文以真机数据为准**；
- 设备侧用例 `KernelPerfReal` 2/2 通过（阈值：1 天 ≤200ms、14 天 ≤1s、365 天 ≤20s、单分片 ≤40ms、
  取消 ≤100ms），`TimeZoneReal` 12/12 通过。

## 11. 失败与未验证项目

1. **一对一窗口匹配评估未实现**（§2）：无边界误差、bestUtc 误差、拆分/误合并计数；
2. 36 目标网格只做了**窗口数量级对比**，不是逐窗口匹配；纽约 / Tromsø / 非对称容差 / 0–360 包裹 /
   日界窗口这些 2C-1 场景本轮**未在真机或宿主机重跑新内核**，仅在单测里覆盖了代表用例；
3. 变化率上界是经验值：近天顶、极区、极昼/极夜边缘没有形式化误差界；
4. 短于 1 秒的窗口仍可能漏；`unresolvedIntervals=0` 不代表完备；
5. 模式 B 只在逻辑层测试，没有 UI；
6. 设备性能只测了 3 个天数档、容差 3°；窄/宽容差、高纬度、无命中的设备耗时未测；
7. UI 视觉（窗口行排版、浮层进度）未做真机截图核验；
8. 2B 遗留的「原生 DatePicker/TimePicker 真实手指操作」仍未验证。

## 12. 发布前需继续完成

1. 把内核镜像同步到 `tools/reverse-check/scan.mjs` 并实现**一对一区间匹配**，补齐 §2 缺失指标；
2. 在真机补测窄容差（0.05°）、宽容差（6°）、高纬（Tromsø）、近天顶、无命中的耗时与窗口数；
3. 评估变化率上界的正式误差界（至少给出近天顶的保守处理证明或明确标注为近似）；
4. 若需要模式 B，再增加有语义的 UI 切换（配额规则先定）；
5. 把「保存到计划」与窗口模型统一（当前仍用 bestUtc 落库，窗口区间未持久化）。

---

# 复审补丁（2026-11-03）

## A. 已修复缺陷与红灯证据

修复前（保留的红灯证据）：`Tests run: 129, Failure: 7` ——
`single_range_without_hits_terminates`、`first_range_empty_then_second_range_has_hits`、
`three_ranges_all_empty_terminate`、`many_empty_ranges_terminate_within_step_cap`、
`merge_only_when_truly_touching`、`non_finite_positions_are_not_reported_as_no_hit`、
`finalize_rejects_window_whose_best_does_not_match_reported_errors`。

修复后：`Tests run: 129, Failure: 0, Error: 0, Pass: 129`。

| # | 缺陷 | 根因 | 修复 |
|---|---|---|---|
| 1 | 无命中的第一个区间不推进，导致反复重扫同一天 | `if (rangeIndex > 0 \|\| spanList.length > 0) finishRange()` 用「是否第一天/有没有命中」判断收尾 | 新增显式 `rangeActive` 状态：进入区间置 true，`stack` 空且 `rangeActive` 时必定 `finishRange()`；与命中与否无关 |
| 2 | 合并边界 `+1` 会跨过 1ms 真实无效间隔 | `w.startUtc <= last.endUtc + 1` | 改为 `w.startUtc <= last.endUtc`：只有真正相接（半开区间首尾重合）或重叠才合并；1ms / 10ms / 1s 间隔都保持两个窗口 |
| 3 | 太阳方位角 NaN/Infinity 被当成「比较失败 → 无效」 | `classify()` 只检查 `altitudeDeg` 有限性 | 任意关键采样（含 `azimuthDeg`）非有限 → 一律「继续细分」（保守）；`KernelStats.nonFiniteSamples` 计数；**区间内无有效跨度但出现过非有限位置** → 会话置 `FAILED` 并给出明确错误，不再伪装成「没有拍摄机会」 |
| 4 | `finalizeWindows` 只检查 `bestUtc` 是否在区间内 | 未复核声明的误差 | 在 `bestUtc` 用同一求值器复算实际位置，校验双容差 / `daylightOnly` / 有限性，并用真实值覆盖声明误差；复算不通过则重算窗口，仍不通过计入 `SearchOutcome.droppedInvalid` |

## B. 新增测试（9 条）

无命中单区间终止、首区间无命中后区间有命中、三区间全无命中、首命中后无命中、
365 个全无命中区间（步数上限保护）、合并边界（相接 / 1ms / 10ms / 1s）、
非有限位置的显式失败、finalize 拒绝不一致窗口，以及原有会话/评分用例迁移到「按时刻映射误差」的求值器。

## C. 取消与性能指标的措辞更正

之前报告中「取消延迟 0ms」**只是会话状态设置的耗时**，不等于用户感知的响应延迟。区分如下：

| 指标 | 状态 | 数值 |
|---|---|---|
| 会话取消状态设置（`session.cancel()`） | 已测（真机） | 0 ms |
| 单分片最大计算耗时（`step(8)`） | 已测（真机） | 6 / 8 / 11 ms（1 / 14 / 365 天） |
| 搜索会话自身推进总耗时（不含页面） | 已测（真机） | 6 ms / 65 ms / 3 511 ms |
| **UI 点击「取消」→ 搜索真正停止** | **未测** | 需要真机点击 + 观察，而未做，不得用 0ms 代替 |
| **含让帧（`nextFrame`）与 `AppDb.updateJob` 的端到端搜索耗时** | **未测** | 页面循环每片都写 Job + 让帧，真实总耗时必然大于会话耗时 |

真机 `KernelPerfReal` 的门槛断言只覆盖「会话推进 + 状态设置」，不能当作 UI 交互性能证据。

补记（设备解锁后执行，补丁版本 `b08601f` 安装包）：

```text
aa test -s class KernelPerfReal → Tests run: 2, Failure: 0, Error: 0, Pass: 2
aa test -s class TimeZoneReal  → Tests run: 12, Failure: 0, Error: 0, Pass: 12
```

即补丁后的真机回归已通过；但 **UI 点击取消的端到端延迟** 与 **含让帧/Job 写入的整段搜索耗时**
依然只有页面代码里的 `用时 N ms` 自述，未做独立的端到端测量，仍列为未验证。

## D. 提交清理

`perf.log`（设备锁屏导致 `aa test` 启动失败的信息）已 `git rm --cached` 并加入 `.gitignore`
（同时忽略 `*.log`，`docs/**/*.log` 例外）；失败记录已整理进本文档，根目录不再积累临时日志。

---

# 最终状态（2C 收尾）

## 搜索异常状态端到端传播（本轮修复）

### P0：页面忽略 SessionState.FAILED

新增纯逻辑模块 `services/SearchRunPolicy.ets`：把「会话状态 + 后处理统计 + 机位是否切换」
映射成页面可执行的动作（`RunKind` / `RunDecision`：`jobStatus`、`writeSuccessHistory`、
`showResults`、`errorText`、`incomplete`）。`ReversePage` 只按该结果执行，不再自己判断状态。

| 会话终态 | 行为 |
|---|---|
| `DONE` + 有窗口 | `DONE_OK`：展示窗口，Job `DONE`，写成功历史 |
| `DONE` + 零窗口 | `DONE_EMPTY`：显示「完成，没有符合条件的时段（可放宽容差或增加天数）」，Job `DONE`，写历史 |
| `CANCELLED` | `CANCELLED`：保留部分窗口并标「已取消（未完成）」，Job `CANCELLED`，**不写历史** |
| `FAILED` / `INVALID` | `FAILED`：展示 `session.getError()` 的具体原因，**不置 `searched=true` 展示成功结果**，Job `FAILED`，**不写历史**；若有部分窗口则标注「结果不完整」 |
| 机位已切换 | `STALE`：清空结果；Job 终态保留原语义（FAILED→FAILED、CANCELLED→CANCELLED、否则 DONE），**不得覆盖成 DONE 成功** |
| `DONE` 但 `droppedInvalid > 0` | `FAILED`：提示「有 N 个窗口在后处理阶段被拒绝（位置与容差不一致），结果不完整」，Job `FAILED`，**不写历史**；只展示通过校验的窗口 |

关键点：`finalizeWindows` 只在 `DONE`/`CANCELLED` 时执行；`FAILED`/`INVALID` 直接使用会话已收集的
部分窗口，避免用不可信数据继续后处理。

### 红绿证据

```text
修复前：Tests run: 138, Failure: 7   （9 条终态用例中 7 条失败）
        失败：failed_without_windows_propagates_reason_and_job_failed / failed_with_partial_windows_is_not_complete /
             cancelled_keeps_incomplete_semantics / dropped_invalid_windows_block_complete_success /
             place_changed_never_overwrites_failed_with_done / invalid_session_state_is_failure_not_empty_result /
             previous_failure_does_not_pollute_next_run
修复后：Tests run: 138, Failure: 0, Error: 0, Pass: 138
```

### 最终测试与构建状态

| 项目 | 结果 |
|---|---|
| 宿主机回归 | `Tests run: 138, Failure: 0, Error: 0, Pass: 138`（原 129 条全部保留 + 9 条终态用例） |
| 外部太阳参考 | `node tools/solar-check/check.mjs` → 全部通过 |
| 应用 HAP | BUILD SUCCESSFUL |
| 真机 `KernelPerfReal` | 2/2（补丁前版本 b08601f 上执行；本轮未重跑） |
| 真机 `TimeZoneReal` | 12/12（同上） |

## 指标口径（避免混用）

| 指标 | 数值 | 状态 |
|---|---|---|
| 会话 `session.cancel()` 状态设置 | 0 ms | 已测（真机） |
| 单分片最大计算耗时 | 6 / 8 / 11 ms（1 / 14 / 365 天） | 已测（真机） |
| 搜索会话推进总耗时（不含页面） | 6 ms / 65 ms / 3 511 ms | 已测（真机，补丁前版本） |
| **UI 点击「取消」→ 搜索停止的端到端延迟** | 无数值 | **未测**（自动化定位不到「搜索候选时段」按钮，未取得可信数据） |
| **含让帧与 `AppDb.updateJob` 的整段搜索耗时** | 只有页面自述的 `用时 N ms` | **未独立测量** |
| 一对一窗口参考匹配（边界误差/bestUtc 误差/拆分与误合并计数） | 无 | **未实现**（Node 侧无内核镜像） |
