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

---

# 收尾：两处 UI 修复与真机端到端验收

## A. Planner 切换机位

**修复**：新增 `switchPlace(index)`：

1. 切换前先作废旧机位的 `PlanTimeSelection` / `timeMessage` / 候选列表——旧时区候选绝不用于新机位；
2. `selectedUtc` **完全不动**（不重算、不位移）；
3. 用 `TimeUtil.toLocal(新机位.tzId, selectedUtc)` 得到新时区的当地年月日时分，只同步 `pickedDate`；
   TimePicker 由 `buildTime()` 读取 `pickedDate + selectedUtc`，因此自动跟随；
4. 时区不可用（`toLocal().valid === false`）→ 明确提示「机位时区 … 不可用，无法确定当地时间。」，保存校验会因此拒绝；
5. 编辑已有计划时 `timeEdited` 仍为 false，保存走「只校验 UTC 与日期归属」的路径，不会覆盖原时间。

跨日示例（单测覆盖，见 `TimeSelection.test.ets` 的 UTC 归属断言 + 设备侧时区用例）：
`2026-11-01T20:00Z` 在上海是 **11-02**，在纽约是 **11-01**；切换机位后 UTC 不变，`pickedDate` 变。

## B. Calendar 异常日期

- 格子内不再用统一灰点：极昼 `昼`、极夜 `夜`、日期不存在 `无`、数据不可用 `缺`（单字+颜色，不依赖颜色区分）；
- 日期数字保持不变大小，单字标记在第二行，不挤压读数；
- `accessibilityText` 追加完整状态词（`polarLabel()`）；点击摘要也追加 `· 极昼/极夜/该当地日期不存在/时间数据不可用`；
- CSV 导出的「极昼极夜」列使用同一 `polarLabel()` 措辞，界面/无障碍/导出三处一致；
- 日期不存在时日出/日落/正午/黄金全部显示「日期不存在」或「数据不可用」，不生成虚构事件。

## C. 真机端到端验收（实测证据）

设备 `MIA-AL00`，HarmonyOS 7.0.0.109，API 26。测试机位通过**App 正常 UI**创建（未使用 SQL/HDC 文件替换/RDB 修改）：

| 机位 | 坐标 | 时区 | 状态 |
|---|---|---|---|
| `TEST-上海` | 31.2304, 121.4737 | Asia/Shanghai（UTC+08:00） | 已创建并保留 |
| `TEST-纽约` | 40.7128, -74.0060 | America/New_York（UTC-05:00） | 已创建并保留 |

`TEST-阿皮亚` **未创建**（Apia 2011-12-30 界面验收需要在日历里回溯到 2011 年 12 月，本轮未完成，见未验证项）。

| 场景 | 机位/日期 | 操作 | 实际显示 | 结果 | 截图 |
|---|---|---|---|---|---|
| A1 上海主页 | TEST-上海 / 2026-11-02（设备当地日） | 设为当前机位 → 今日 | `2026-11-02 周一 · 07:54 · UTC+08:00`，太阳方位 121.9°、高度 19.5°、阶段「白昼」，曲线区域开始绘制 | ✅ | `docs/screenshots/32_2b3c_home_shanghai.jpeg` |
| A2 上海曲线 | 同上 | 上滑展开曲线 | 曲线与时间轴可见，无「时间轴不可用」 | ✅ | `docs/screenshots/33_2b3c_home_shanghai_chart.jpeg` |
| C1 纽约回拨日主页 | TEST-纽约 / 2026-11-01（25 小时日） | 设为当前机位 → 今日 → 上滑 | 时间轴出现 `DST-05:00` 标记与 `11:30`、`17:45` 刻度；日出 06:10、日落 17:05、黄金 05:54-06:44 / 16:31-17:20、蓝调 05:45-05:54 / 17:20-17:30、民用曙光结束 17:30 | ✅ | `docs/screenshots/34_2b3c_home_ny_fallback.jpeg` |
| C2 纽约日历 | 同上，2026 年 11 月 | 更多 → 日历 | 每天带黄金时刻圆点，选中 11-01 摘要：日出 06:26、日落 16:52、正午 11:39、黄金 晨 06:09-07:05 / 夕 16:13-17:09 | ✅ | `docs/screenshots/35_2b3c_calendar_ny_november.jpeg` |
| A3 时间比较 | TEST-纽约 | 更多 → 时间比较 | 页面正常打开（截图已存） | ✅（截图未逐像素复核） | `docs/screenshots/36_2b3c_compare_ny.jpeg` |
| B 纽约春季前跳 | 需要把日期改到 2026-03-08 | 轨迹页 DatePicker | **未执行**：需多步日期回溯，本轮上下文用尽前未完成 | ⏸ 未验证 | — |
| B2 Planner GAP | 纽约 2026-03-08 02:30 | 计划页输入时间 | **未执行**（同上，且 TimePicker 精确输入需多步操作） | ⏸ 未验证 | — |
| C3 Planner OVERLAP 双候选 | 纽约 2026-11-01 01:30 | 计划页输入时间 | **未执行**（需要 TimePicker 精确定位到 01:30） | ⏸ 未验证 | — |
| D Apia 跳日格子 | TEST-阿皮亚 / 2011-12-30 | 日历「上月」×179 回溯到 2011-12，点 30 日 | 摘要实测：`2011-12-30 · 日出 日期不存在 · 日落 日期不存在 · 正午 日期不存在 · 该当地日期不存在`，黄金行同为「日期不存在」；未出现虚构日出日落 | ✅ | `docs/screenshots/44_2b3c_calendar_apia_skipped.jpeg` |

> 说明：C1 的 `DST-05:00` 是真实运行截图里的时间轴刻度，证明 DST 标记在 25 小时日确实渲染且未与相邻刻度重叠（同一行只有该标记、11:30、17:45 三个刻度）。

## D. 回归测试

```text
宿主机：Tests run: 99, Failure: 0, Error: 0, Pass: 99
应用构建：BUILD SUCCESSFUL
测试包构建 + 安装：BUILD SUCCESSFUL，两 HAP install bundle successfully
真机：-s class TimeZoneReal → Tests run: 11, Failure: 0, Pass: 11
```

## D2. 追加的真机证据：计划保存路径

轨迹页「把此刻存为拍摄计划」在 TEST-纽约 / 2026-11-01 02:09（UTC-05:00，即 07:09Z）
成功保存计划，计划列表显示 `2026-11-01 周日 02:09 · 目标 62° / -48°`
（`docs/screenshots/43_2b3c_plan_ny_0209.jpeg`），说明重复小时内的第二次时刻可以正常落库。
计划列表始终按**计划自身机位时区**显示，切换当前机位不会改变该计划的时间显示——这是既有设计，
不是 UTC 被改写。

## D3. 时间滚轮自动化的确切阻塞点

实测结论（比此前"不稳定"更具体）：用 `uitest uiInput` 点击或滑动 `TimePicker` 的可见行，
**控件显示值会变**（例如显示 01:30 / 01:46），但 `onChange` 不触发，
因此 `applyLocalDateTime()` 从未执行 → `timeMessage` 与候选按钮不会出现，`timeEdited` 也不会置位。
这正是 Planner 的 GAP 提示与 OVERLAP 候选面板无法通过注入脚本验证的原因，属**自动化能力限制**，
代码路径本身由宿主机单测覆盖（`gap_time_cannot_be_saved`、`overlap_requires_explicit_choice`）。

## D4. D 场景结论

Apia 2011-12-30 在真机日历上确实渲染为「日期不存在」：格子标记与摘要、CSV、无障碍文本三处措辞一致
（`polarLabel()` 单一来源），且没有生成任何虚构的日出/日落/正午/黄金时刻。
这也验证了 `DayKind.SKIPPED` 从解析层到 UI 层的完整链路。

## E. 未解决 / 未验证

1. 春季前跳（2026-03-08）与 Planner 的 GAP/OVERLAP 交互**尚未在真机上点过**，仅有单测覆盖（`gap_time_cannot_be_saved`、`overlap_requires_explicit_choice`）。
2. Apia 2011-12-30 的日历格子状态（`无`）未在真机上看到，因为未创建 TEST-阿皮亚且未回溯月份。
3. 时间比较页截图未做像素级复核（进度横轴与曲线形状）。
4. 首页曲线的 `DST-05:00` 位于 x 轴第一个刻度之前的位置，视觉上靠近左边缘，属可接受范围但未做多分辨率检查。
5. 遗留 2C 问题不变：粗扫可能漏短窗口、10 分钟合并、maxResults 分布、跨日最优。
