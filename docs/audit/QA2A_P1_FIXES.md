# QA-2A · 发布前 P1 修复记录（QA-01 / QA-02 / QA-03 / QA-04）

> 基准 `1195bb3` → 本轮修复分支 `fix/core-quality-audit`，设备 MIA-AL00 / HarmonyOS 7 / API 26。
> 本轮只修四个 P1/P2：不扩展功能、不改 Schema、不删数据、不碰 TEST 机位、不改 main。

## 1. QA-03 计划数据保护（最先修复）

**改动文件**：`services/PlanPlaceGuard.ets`（新增）、`pages/PlannerPage.ets`

| 规则 | 实现 |
|---|---|
| 编辑必须精确匹配 `placeId` | `PlanPlaceGuard.resolveEdit()`：命中返回 `matchedIndex`；未命中返回 `matchedIndex=-1`、`detached=true` |
| 不再回退索引 0 | `PlannerPage.startEdit()` 直接使用 `ctx.matchedIndex`（可为 -1），不再默认 0 |
| 原机位缺失提示 | 表单内 `NoticeBar` 显示「此计划关联的机位已删除（原机位「X」 lat, lon · tz）」 |
| 快照不丢失 | 守卫把 plan 的 `placeId/placeName/lat/lon/tz` 读入 `PlaceSnapshot` 并在保存时原样保留 |
| 未主动换机位不得改写 | `resolveSave(detached=true, userChanged=false)` → `useSnapshot=true`；`applyPlace()` 在 `useSnapshot` 时**不触碰任何机位字段** |
| 明确换机位才允许改写 | `switchPlace()` 在编辑态置 `placeChangedExplicitly=true`；`resolveSave` 返回新机位并给出「计划所属地点已更改，拍摄时刻（UTC）保持不变」提示 |
| 机位列表为空 | 孤立计划仍可保存（沿用快照）；用户要求换机位但无机位 → 拒绝保存并说明原因 |
| 保存失败不显示成功 | `catch` 分支只写 `hint` + 失败 toast；成功 toast 仅在 `await AppDb.savePlan(...)` 之后触发 |

**数据保护证据**（宿主机，`PlanPlaceGuard.test.ets` 8 条）：

```text
save_without_explicit_change_never_rewrites_place_fields  → placeId/placeName/lat/lon/tz/id/selectedUtc/note 全部保持原值
save_detached_with_empty_places_still_uses_snapshot       → 无机位时仍沿用快照
explicit_change_writes_new_place_and_keeps_utc_and_id     → 换机位后 id 与 UTC 不变
explicit_change_without_available_place_is_blocked        → 拒绝保存且计划对象零改动
matched_plan_without_selection_is_blocked                 → 未选机位拒绝保存
```

## 2. QA-01 异常采样不得形成完整成功

**改动文件**：`services/SearchSession.ets`、`services/SearchRunPolicy.ets`、`pages/ReversePage.ets`

- `finishRange()`：只要该区间内出现过非有限太阳位置就计 `unreliableRanges++` 并置 `unreliableData`，
  **与是否已有有效跨度无关**（原实现要求 `spanList.length === 0`）。
- 全部区间处理完：`unreliableData` 为真 → `SessionState.FAILED` + 明确原因；
  **用户主动取消仍保持 `CANCELLED`**（`cancel()` 先置位，不再被覆盖为 FAILED）。
- 已找到的可信窗口保留为部分结果，但终态是 FAILED，`Job=FAILED`，不写成功历史。
- 没有把 NaN 当作 0°、没有放宽容差来掩盖异常。

## 3. QA-04 策略层双重防线

`SearchRunPolicy.decide()` 现在真正使用 `unreliableRanges`：

```text
unreliableRanges > 0 且 sessionState != CANCELLED → FAILED（Job FAILED、不写历史、标记不完整）
即使会话状态被误传为 DONE，也无法宣称完整成功
```

## 4. QA-02 失败提示不再遮挡表单

**改动文件**：`pages/ReversePage.ets`、`services/ReverseViewState.ets`（新增，页面与测试共用）

| 场景 | 渲染 |
|---|---|
| 初始化失败 | 整页 `ErrorCard`（唯一的整页错误态） |
| 搜索失败、无窗口 | 表单可见 + 表单内警示条；无错误卡 |
| 搜索失败、有部分窗口 | 表单 + 警示条 + 「以下为部分结果（搜索未完整完成）」+ 结果列表；**禁用「加入拍摄计划」**（按钮文案改为「部分结果，暂不可加入计划」） |
| 正常无命中 | 正常空态提示（不是错误卡） |
| 取消 | 显示「已取消（未完成）」，不出现失败警示 |
| 机位切换（STALE） | 清空结果，表单保留 |
| 新搜索开始 | 清空上一轮 `errorText/partialResults/candidates/windows` |

## 5. 红绿证据

| 阶段 | 结果 |
|---|---|
| 修复前（QA-1 固化的旧行为断言） | `Tests run: 146, Failure: 0`（旧行为被当作“正确”） |
| 生产代码修复后、测试尚未迁移（红灯） | `Tests run: 146, Failure: 5` —— A1/A2/A4/A5 与 B1（死参数）与新行为冲突 |
| 迁移旧断言 + 新增用例后（绿灯） | `Tests run: 163, Failure: 0, Error: 0, Pass: 163` |

迁移后的断言（相同输入）：

| 用例 | 修复前 | 修复后 |
|---|---|---|
| A1 先有效后 NaN | `DONE` + 1 窗口 | `FAILED` + `unreliableRanges=1` + 1 个部分窗口 + 错误含「非有限」 |
| A2 先 NaN 后有效 | `DONE` | `FAILED` + 1 个部分窗口 |
| A3 全天 NaN 无窗口 | `FAILED` | `FAILED`（保持） |
| A4 第一天无命中、第二天前 3 分钟 NaN 后段有效 | `DONE` | `FAILED` + 1 个部分窗口 |
| A5 已有窗口后 Infinity | `DONE` | `FAILED` |
| A7（新增）异常期间取消 | — | `CANCELLED`（不被改成 FAILED） |
| B1 `unreliableRanges>0` 且状态 DONE | 判定为 DONE（死参数） | 判定为 FAILED、不写历史 |

## 6. Job 状态与历史一致性

| 终态 | Job | 写成功历史 |
|---|---|---|
| DONE_OK / DONE_EMPTY | DONE | 是 |
| CANCELLED | CANCELLED | 否 |
| FAILED（异常/后处理拒绝/不可靠区间） | FAILED | 否 |
| STALE | 保留会话原语义（FAILED/CANCELLED，否则 DONE） | 否 |

## 7. 本轮测试与构建

```text
宿主机：Tests run: 163, Failure: 0, Error: 0, Pass: 163
外围太阳参考：node tools/solar-check/check.mjs → 全部通过
应用 HAP：BUILD SUCCESSFUL，2,294,685 字节
测试包：BUILD SUCCESSFUL
真机（本次构建安装后执行）：KernelPerfReal 2/2、TimeZoneReal 12/12
```

新增测试文件：`PlanPlaceGuard.test.ets`（8 条）、`ReverseViewState.test.ets`（8 条）；
`SearchAnomalyAudit.test.ets` 迁移为修复后断言并新增 A7。

## 8. 尚未解决（本轮范围外）

QA-05 CSV BOM、QA-06 大组件拆分、QA-07 一对一窗口参考匹配、QA-08 UI 端到端性能、
QA-09 原生滚轮手指操作；另有 QA-1 中列出的真机视觉/迁移/异常恢复等 NOT_RUN 项。
