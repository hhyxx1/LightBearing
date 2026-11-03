# UI-0 第一部分 · 搜索交互门禁

> 基准 `728b9cf` → 本轮改动；设备 MIA-AL00 / HarmonyOS 7 / API 26。
> 本轮只改搜索交互门禁相关代码，设计系统部分仅出文档（见 `docs/design/`）。

## 1. 加入拍摄计划的门禁（已改）

**问题**：`ReverseViewState.allowAddToPlan` 原来只排除 FAILED，`CANCELLED`（`showResults=true`、
`incomplete=true`）与 `STALE` 仍可能允许把**未完整校验**的窗口写进拍摄计划。

**修复**（`services/ReverseViewState.ets`）：

```ts
v.allowAddToPlan = v.showResults && decision.kind === RunKind.DONE_OK && !decision.incomplete;
```

| 终态 | showResults | allowAddToPlan |
|---|---|---|
| DONE_OK 且完整 | true | **允许** |
| DONE_OK 但 incomplete（异常上游） | true | 禁止 |
| DONE_EMPTY | false | 禁止 |
| FAILED（含部分结果） | true（部分） | 禁止 |
| CANCELLED（含部分结果） | true（部分） | 禁止 |
| STALE | false | 禁止 |

页面的**第二层校验**保留：按钮 `enabled(this.viewState().allowAddToPlan)`，`onClick` 内再次判断
`allowAddToPlan`，即使按钮状态被绕过也不会落库。

回归：`ReverseViewState.test.ets` 新增/改写 3 条（CANCELLED 有窗口、CANCELLED 无窗口、
「只有完整 DONE_OK 才允许」含 DONE_EMPTY/FAILED/STALE/DONE_OK-but-incomplete 分支）。
宿主机共 **197/197 通过**。

## 2. 空结果文案的归属（已改）

`ReversePage` 原来直接用 `candidates.length === 0` 判断「没有拍摄机会」，会把失败或取消也
渲染成正常空态。现在改为：

| 终态 | 文案 |
|---|---|
| DONE_EMPTY | 「在该容差与日期范围内没有满足条件的时刻…」（`showEmptyHint`） |
| FAILED | 失败原因警示条（`showSearchWarning`），不出现空态文案 |
| CANCELLED | 「已取消（未完成）：保留 N 个已找到窗口」+ 未完成提示 |
| STALE | 清空结果，仅提示机位已切换、请重新搜索 |

表单在所有终态下都保留，可修改条件后重新搜索；新搜索开始时清空上一轮的 `errorText/partialResults/
candidates/windows/searched/lastDecision`。

## 3. UI 搜索终态「不可见」的定位（已取证）

### 3.1 新增的稳定诊断日志（不含坐标与敏感信息）

`pages/ReversePage.ets` 使用 `hilog.info(0x0001, 'LBSearch', ...)` 打 6 个点：

```text
runSearch start
job created id=<jobId>
session state=<SessionState> windows=<n> dropped=<n> unres=<n>
decision kind=<RunKind> job=<JobStatus> showResults=<Y/N> elapsed=<ms>
job updated status=<JobStatus> searched=<Y/N>
runSearch failed: <message>      （错误路径）
```

### 3.2 真机 1 天搜索的实测日志

```text
11-04 01:44:43.070 LBSearch: runSearch start
11-04 01:44:43.086 LBSearch: job created id=job_1793727883070_1
11-04 01:44:44.712 LBSearch: session state=1 windows=4 dropped=0 unres=0
11-04 01:44:44.712 LBSearch: decision kind=0 job=2 showResults=Y elapsed=1624
11-04 01:44:44.714 LBSearch: job updated status=2 searched=Y
```

结论（有证据、非猜测）：

1. **点击确实进入了 `onClick`**，`runSearch` 真实执行；
2. **Job 真实创建**（`job_1793727883070_1`），并且最终写入 `status=2`（DONE）；
3. **会话推进正常**：`state=1`（DONE）、`windows=4`、`dropped=0`、`unreliable=0`；
4. **决策与页面状态正确**：`kind=0`（DONE_OK）、`showResults=Y`、`searched=Y`；
5. 同一时刻 `uitest dumpLayout` 的可见文本数仍为 31，`用时/窗口` 摘要不在可见节点中。

因此：**不是搜索卡死，也不是数据链路失败**；是「总结与结果区不在 dump 所返回的可见视口内」。
此前 QA-2C 的 BLOCKED 描述据此更新为「终态文本未进入可视区」。

### 3.3 仍然 BLOCKED 的部分

- `dircFling` 上滑可把「搜索候选时段」按钮滚进视口（已验证），但完成搜索后再上滑 2×（最多 12 轮）
  仍取不到摘要文本，说明仅靠注入滚动无法把结果区稳定带入可视区；
- 因此 **用户感知的端到端耗时、UI 取消延迟、365 天 UI 搜索** 仍无数值，保持 BLOCKED；
- 会话层 `elapsed=1624 ms`（1 天）属于「会话推进 + 状态写入」的内部耗时，**不冒充**用户感知延迟。

### 3.4 下一步需要的（不改产品功能）

1. 给结果区/摘要一个可被 `dumpLayout` 稳定带回的定位方式（例如放在固定可见的摘要条，
   或用 ArkUI 测试驱动的 scrollTo 能力）；
2. 或改用 `ohosTest` 的 UI 驱动接口做最小能力探针（`Driver` 查找 + 滚动 + 点击 + 断言摘要文本）。

## 4. 本轮未做的事

- 未添加临时 Debug 页面、未写入隔离测试 Job 之外的数据、未改数据库 Schema、未动 TEST 机位；
- 未伪造任何端到端耗时数字。
