# 02B-3C · 真实时间选择、夏令时交互与日期状态

> 基准 `bfa5d83`，工作分支 `fix/core-quality-audit`。本轮只做时间交互层（滑块、计划时间选择、日期状态、事件文案）
> 与保存校验；未改时区候选解析、NOAA/Meeus 公式、反向寻光搜索算法、数据库 Schema、Bundle Name 与签名。

## 1. 旧 Slider 的 DST 错误

首页与太阳轨迹页原先把滑块当作 `0..1439` 分钟，再 `fromLocal(tz, y, m, d, hour, minute)`：

- **春季前跳**：滑块能停在 02:00–02:59，而该当地时间不存在 → `fromLocal` 静默给出跳变后的时刻；
- **秋季回拨**：01:00–01:59 出现两次，但滑块只有一个位置 → 第二次永远选不到，两个 01:30 无法区分；
- **23/25 小时日**：`0..1439` 线性映射与实际日长不符，最后/最前一小时落错位置。

## 2. 新的 UTC Slider 映射

新增纯逻辑 `services/TimeSelection.ets`：

```ts
class SliderMapping {
  static readonly MAX = 1000;
  static toUtc(model, value): TimelinePoint       // 夹到 0..1000 → ratio → 真实 UTC
  static toSlider(model, utcMs): SliderValue      // 区间内 → 0..1000；区间外 valid=false
}
```

- 滑块操作的是**真实时间轴上的归一化位置**，不再是当地钟点；
- 边界一律 `[startUtc, endUtc)`：`toSlider(endUtc)` 无效，`toUtc(1000)` 落到 `endUtc - 1`；
- `toSlider` 用 `valid` 而不是负数表达失败 → 1970 年前的负时间戳正常可用；
- 首页 `onSliderChange()` 与太阳轨迹页 `applyProgress()` 都只通过 `Timeline.fromBounds(dayStart, dayEnd)` 取模型，
  不存在 24 小时常量；
- 日期切换（前一天/后一天/今天/DatePicker）后统一按**相同的 progress** 重新定位，不保留旧日期的 `selectedUtc`。

## 3. GAP / OVERLAP 的 UI 决策

`PlannerPage` 的时间输入统一走一个入口 `applyLocalDateTime(y, m, d, hh, mm)` → `TimeUtil.resolveLocal()`：

| 状态 | 决策 |
|---|---|
| `UNIQUE` | 直接采用唯一候选，清空提示 |
| `GAP` | **不修改 selectedUtc**，提示「该当地时间因夏令时切换而不存在，请重新选择。」，禁止保存 |
| `OVERLAP` | **不静默选择**；列出 `resolveLocal().candidatesUtc` 的两个候选按钮，标签含本地时刻与偏移，用户点选后才更新 selectedUtc |
| `UNAVAILABLE` | 提示「机位时区数据不可用，无法确定该当地时间。」，不改时间，禁止保存 |
| `INVALID` | 提示「日期或时间无效…」，不改时间，禁止保存 |

候选全部来自 `candidatesUtc`，没有用「±1 小时」伪造，因此 30 分钟跳变（豪勋爵）也能正确处理。
候选标签格式：`第 1 次 01:30（UTC-04:00）` / `第 2 次 01:30（UTC-05:00）`。

## 4. 编辑已有计划的 UTC 保留

- `startEdit(plan)` 直接 `this.selectedUtc = plan.selectedUtc`，**不经过任何 fromLocal 重算**，
  因此秋季「第二次 01:30（06:30Z）」进入编辑后仍是 06:30Z，不会被改成第一次；
- 新增 `timeEdited` 标记：用户未动时间时，保存校验传 `selection = null`（只校验 UTC 有效性与日期归属），
  不会因为「没有候选列表」而误判；
- 只有用户主动改时间（DatePicker/TimePicker/候选选择）才会重新解析并更新 `selectedUtc`。

## 5. 最终保存校验

`PlannerPage.savePlan()` 在写库前调用 `TimeSelection.validateForSave()`，逐项检查：

1. `selectedUtc` 是有限数字；
2. 机位存在且经纬度有限、`|lat| ≤ 90`、`|lon| ≤ 180`；
3. 机位时区通过 `TimeUtil.isValidTimeZoneId()`；
4. 目标当地日边界有效（`localDayBounds(pickedDate)`）且 `selectedUtc ∈ [start, end)`；
5. 若本次改过时间：`GAP / INVALID / UNAVAILABLE` 直接拒绝；`OVERLAP` 必须已选定候选且与 `selectedUtc` 一致；
6. 任一失败 → 设置提示 + toast，**不调用 `AppDb.savePlan()`，不显示保存成功**。

## 6. CalendarPage 状态呈现

- 无效日期不再显示虚构的日出日落：整行改为 `日期不存在`（`DayKind.SKIPPED`）或 `数据不可用`（`DayKind.UNAVAILABLE`/其他）；
- 与极昼/极夜区分：极昼极夜仍显示各自的 `polarState` 文案与真实事件时间；
- CSV 导出与无障碍文本沿用同一套 `polarState` 语义（3=日期不存在、4=数据不可用），保证导出与界面一致。

## 7. OUTSIDE_DAY 文案迁移

新增 `EventText.describe(state, formatted)`：

| 状态 | 文案 |
|---|---|
| `AVAILABLE` | 格式化后的当地时间 |
| `OUTSIDE_DAY` | 事件位于所选当地日期之外 |
| `NO_CROSSING` | 当日未穿越该高度阈值 |
| `DAY_INVALID` | 日期或时区数据不可用 |

已迁移 `HomePage`（日出/日落/民用暮光）、`SunPathPage`（日出/日落）、`PlaceDetailPage`（日出/日落）、
`CalendarPage`（日出/日落）。**不再把「事件不在当前民用日」写成极夜/极昼**（有单测断言文案不含「极夜/极昼」）。

## 8. DST 标签避让修正

`TimelineLabels.dropOverlaps()` 原实现按 UTC 升序单向判断，排在 DST 标记**之前**的常规刻度不会被移除。
现在改为：

1. 先收集所有 DST 标记；
2. 常规刻度与**任一**标记的距离（`|Δratio| × 可用宽度`）小于阈值即让位——**双向**生效；
3. 阈值由标记文本宽度估算（`markerGapPx(label) = max(46, 10 + len×7.4)`），
   保证 `DST+05:45` 这类长文本不会被裁切或与相邻刻度重叠。

## 9. 宿主机测试与真机构建结果

```text
宿主机：Tests run: 99, Failure: 0, Error: 0, Pass: 99      （原 90 + 新增 9 条 TimeSelection 用例）
应用构建：BUILD SUCCESSFUL，entry-default-signed.hap  2,179,725 bytes
测试包构建：BUILD SUCCESSFUL；两 HAP 安装成功（install bundle successfully ×2）
真机：-s class TimeZoneReal → Tests run: 11, Failure: 0, Pass: 11
```

新增 9 条宿主机用例：

| 用例 | 覆盖点 |
|---|---|
| `slider_covers_full_23h_day` | 23 小时日全区间、`toSlider(end)` 无效、`toUtc(1000)=end-1` |
| `slider_distinguishes_two_0130_on_25h_day` | 25 小时日两个 01:30 的滑块位置不同且都能还原 |
| `slider_handles_half_hour_days` | 23.5 / 24.5 小时日中点映射 |
| `slider_rejects_invalid_timeline` | 无效模型 / 区间外 / NaN |
| `gap_time_cannot_be_saved` | GAP 未解决时保存被拒 |
| `overlap_requires_explicit_choice` | 未选禁止保存、选第一/第二个候选均可保存、越界索引不改选择 |
| `editing_existing_plan_keeps_original_utc` | 未改时间（selection=null）时原 UTC 通过校验 |
| `invalid_place_or_zone_or_out_of_range_is_rejected` | 纬度/经度/时区/边界/NaN 一律拒绝；1969 负时间戳合法 |
| `event_text_differs_by_state` | 四种状态文案互不相同且 OUTSIDE_DAY 不含「极夜/极昼」 |

## 10. 真实截图与人工交互验收

**未完成**，如实记录：

- 设备 `MIA-AL00`（API 26）当前数据库中没有已保存机位，主页停在「先确定一个机位」空状态
  （见 `docs/screenshots/31_2b3b_home.jpeg`），无法在真实页面上观察曲线、滑块与 GAP/OVERLAP 面板；
- 按本轮约束，我**没有**在用户设备上自行创建/删除机位或改动数据库；
- 因此以下项目仍待人工确认：上海普通日滑块、纽约春季缺口跳过、纽约秋季两个 01:30 的可选性、
  Planner 的候选按钮与提示、日历 3/4 状态呈现、四条曲线的视觉正确性。

需要你做的：在设备上用正常 App UI 创建一个测试机位（或允许我创建），我随后抓取真实截图逐项核验。
不得以「编译通过」代替这部分验收。

## 11. 留给 2C 的反向寻光问题

1. 5 分钟粗扫 + 仅命中后细化：真实命中窗口短于 5 分钟仍可能整段漏报。
2. 10 分钟合并规则可能把相邻两个真实窗口误合并。
3. `maxResults` 按误差截断，不保证时间分布。
4. 跨多日的全局最优未做证明，仅逐日独立搜索后合并。

**本轮未改动上述任何策略**，仅沿用 2B-2 的 `searchInRanges()` 区间语义。
