# 02B-3A · 日期事件归属与异常状态收敛

> 基准 `55bc08d`，工作分支 `fix/core-quality-audit`。本轮只做事件归属、状态模型、异常日期上报与文案真实性；
> 未改 Charts 横轴、首页滑块、TimePicker 交互（留给 2B-3B/2B-3C），未改 NOAA/Meeus 公式、未改粗扫策略（留给 2C）、未动数据库。

## 1. 原始缺陷与证据

### 1.1 事件日期归属只做到「正午」

`events()` 用 `solarNoonNear()` 选太阳日，但日出/日落/曙暮光只是 `正午 ± 时角`，**逐项没有做区间校验**。
当政治时区与太阳时错配、或民用日不是 24 小时时，事件时刻可能落到相邻本地日期，页面会把它们当成今天的事件显示。

证据（代码事实 + 修复后行为对比）：

- `solarNoonNear()` 在区间内没有物理正午时返回「最接近区间」的正午，此时派生事件必然在区间外；
- 修复后该类事件标记 `OUTSIDE_DAY` 且时间戳回收为 `-1`，不再外泄（见 §2）。

### 1.2 `-1` 哨兵与合法负时间戳冲突

`SolarEvents` / `LightWindow` 用 `-1` 表示「无事件」，而 1970 年前的合法 UTC 时间戳是负数，
`-1` 本身就是合法历史时间戳。页面里 16 处 `eventUtc < 0 ? '无'` 会把 1969 年的真实日出显示成「无」。

证据（修复前代码）：

```text
entry/src/main/ets/pages/HomePage.ets:108-110,120-126
entry/src/main/ets/pages/CalendarPage.ets:112-117
entry/src/main/ets/pages/PlaceDetailPage.ets:50-53
entry/src/main/ets/pages/SunPathPage.ets:87-88
```

### 1.3 ReversePage 静默跳过异常日期

`if (bounds.valid) { ranges.push(...) }` 把「整日被跳过」与「时区数据不可用」一律丢弃，
搜索结果看起来完整、实际少搜了日期，且摘要恒为成功。

### 1.4 极夜文案与事实冲突

`SunPathPage.ets` 原文案「当日极夜：太阳全天不升，无黄金/蓝调窗口。」
与 2A 已修复的事实矛盾——极夜中太阳仍可能进入 −4°/−6° 高度带（特罗姆瑟冬至即有黄金与蓝调窗口）。

**关于「先写失败测试」的如实说明**：任务 A/B 的缺陷是**公共模型缺口**（缺状态字段），
旧代码无法编译断言新状态的测试。因此本轮的失败证据是：改成新语义后，3 条旧断言立即变红
（`southern_high_latitude_polar_night_with_twilight`、`solar_noon_not_shifted_by_23h_civil_day`、
`probe_data_unavailable_is_not_gap`），逐条核对后确认为**语义变更**而非回归，已更新为状态断言。

## 2. 事件所属民用日的判定规则

统一使用半开区间 `[dayStartUtc, dayEndUtc)`：**起点包含、终点不包含**。

```ts
static eventPair(noonUtc, dayStartUtc, dayEndUtc, lat, decl, altitudeDeg): number[]
// → [dawnUtc, duskUtc, dawnState, duskState]
```

| 情形 | 时间戳 | 状态 |
|---|---|---|
| 有穿越且 `dayStartUtc <= t < dayEndUtc` | `t`（可为负数） | `AVAILABLE` |
| 有穿越但 `t < start` 或 `t >= end` | **−1（不外泄）** | `OUTSIDE_DAY` |
| 太阳当日没穿越该高度阈值 | −1 | `NO_CROSSING` |
| 民用日区间非法 | −1 | `DAY_INVALID` |

`solarNoonNear()` 返回的正午同样按此规则处理：不在区间内时 `solarNoonUtc = -1`、`noonState = OUTSIDE_DAY`，
但日内的其它事件仍按其自身时刻独立判定——**某个事件在区间外不代表整天无效**。

## 3. 状态模型与调用方迁移

### 新增枚举与字段

```ts
enum EventState { AVAILABLE, NO_CROSSING, OUTSIDE_DAY, DAY_INVALID }
enum WindowState { AVAILABLE, ABSENT, DAY_INVALID }

// SolarEvents
noonState, sunriseState, sunsetState, civilDawnState, civilDuskState,
nauticalDawnState, nauticalDuskState, astronomicalDawnState, astronomicalDuskState
// LightWindow
goldenMorningState, goldenEveningState, blueMorningState, blueEveningState
```

`bandWindows()` 返回值追加两个「有效性标志」（1/0），窗口有效性与时间戳正负彻底解耦。

### 调用方迁移

| 文件 | 改动 |
|---|---|
| `HomePage.ets` | 3 处事件 + 4 处窗口改为 `state === AVAILABLE`；`recompute()` 增加 NaN 防护（NaN 不进 `position()`） |
| `CalendarPage.ets` | 日出/日落/正午/黄金改为状态判断；首日星期改用日历计算（`Date.UTC(y, m-1, 1).getUTCDay()`），不再受被跳过日期影响 |
| `SunPathPage.ets` | 事件与正午改为状态判断；**极夜文案按实际窗口动态生成**；`syncDayEnd()` 去掉 `dayStartUtc <= 0` 判定；`applyTime()` 增加 NaN 防护 |
| `PlaceDetailPage.ets` | 日出/日落/黄金改为状态判断 |
| `ReversePage.ets` | 改用 `SearchPlan`，区分跳过/不可用/非法并上报计数 |

迁移后全仓 **不再存在 `eventUtc < 0` 形式的存在性判断**（`grep 'Utc < 0'` 为空）。

## 4. 1970 年前时间戳测试

| 用例 | 断言 | 结果 |
|---|---|---|
| `event_states_pre_epoch_are_available` | 1969-12-31 上海：`sunriseState/sunsetState === AVAILABLE`，`sunriseUtc < 0` 但 `>= dayStart`，日落晚于日出 | ✅ |
| `pre_epoch_events_are_negative_but_not_sentinels` | 正午为负且在区间内、日出 ≠ −1 | ✅ |
| `event_states_invalid_day_is_not_polar_night` | 非法区间 → 全 `DAY_INVALID`，`polarState === 0`（不被误判为极夜） | ✅ |
| `formatTime` | `!Number.isFinite(utcMs)` 才显示 `--:--`（负时间戳正常格式化） | ✅（2B-1 已修，本轮无回归） |

## 5. ReversePage 的异常日期处理

```ts
class SearchPlan {
  ranges: DayRange[]; requestedDays; skippedDays; unavailableDays; invalidDays; errorText
  static plan(days: LocalDayBounds[]): SearchPlan
}
```

| 日期状态 | 处理 |
|---|---|
| `SKIPPED`（历史时区确实不存在该民用日） | 跳过并计数，不报错 |
| `UNAVAILABLE`（时区数据不可用） | **中止搜索**：`有 N 天的时区数据不可用，已中止搜索以避免不完整结果` |
| `INVALID`（日期/区间非法） | 中止搜索并报错 |
| 全部被跳过 / 空输入 | 中止，提示「没有可搜索的本地日」 |

`LocalTimeResolver.DayKind` 新增 `UNAVAILABLE = 5`，把「数据不可用」与「日期非法」分开；
`dayBounds()` 的探针故障分支改用它。

进度与摘要显示真实范围：`请求 N 天、实际搜索 M 天，跳过 K 天不存在的日期`；
取消时摘要以「已取消」开头，Job 状态仍区分 `CANCELLED / DONE / FAILED`（错误路径落 `FAILED`）。

## 6. 页面实际状态与文案修正

`SunPathPage` 极夜文案改为按实际窗口生成：

| 实际窗口 | 文案 |
|---|---|
| 有黄金 + 蓝调 | 当日极夜：太阳全天不升，但仍有黄金时刻与蓝调窗口。 |
| 仅黄金 | 当日极夜：太阳全天不升，但仍有黄金时刻窗口。 |
| 仅蓝调 | 当日极夜：太阳全天不升，但仍有蓝调窗口。 |
| 都没有 | 当日极夜：太阳全天低于地平线，今日没有黄金/蓝调窗口。 |
| 日界非法 | 本地日边界不可用，无法判定当日太阳事件。 |

同时区分：无事件（`NO_CROSSING`）、区间外事件（`OUTSIDE_DAY`）、日界非法（`DAY_INVALID`）、
时区不可用（`SunPathPage` 在 `toLocal().valid === false` 时显示「时间不可用」而不再显示「无」）。

## 7. 完整测试结果

```text
# 宿主机全部单测（原 72 条 + 新增 8 条）
> hvigor BUILD SUCCESSFUL in 9 s 344 ms
Tests run: 80, Failure: 0, Error: 0, Pass: 80, Ignore: 0

# 外部太阳参考对照
node tools/solar-check/check.mjs → 结论：全部通过（最大误差 27.4s，容差 120s）

# 模型改动后的真机回归
hdc ... aa test -s class TimeZoneReal
Tests run: 10, Failure: 0, Error: 0, Pass: 10
```

新增 8 条：`event_states_pre_epoch_are_available`、`event_states_polar_day_and_night`、
`event_states_invalid_day_is_not_polar_night`、`event_states_attribute_each_event_by_boundary`、
`event_boundary_is_half_open`、`window_states_reflect_availability`、
`search_plan_distinguishes_skipped_and_unavailable`、`range_search_skips_only_really_skipped_days`。

3 条旧断言按新语义更新（逐条说明）：

| 用例 | 原断言 | 为何更新 | 新断言 |
|---|---|---|---|
| `southern_high_latitude_polar_night_with_twilight` | 用 12:00Z 当「本地零点」，只查 `civilDawnUtc >= 0` | 该区间本身不完整，恒有事件落在区间外；旧断言掩盖了归属问题 | 改用真实本地日 `[21T00:00Z, 22T00:00Z)`，断言 `civilDawnState/civilDuskState === AVAILABLE` 且都在区间内 |
| `solar_noon_not_shifted_by_23h_civil_day` | 断言 `|noon − dayEnd| <= 15min` | 新语义下区间外正午不再返回（`solarNoonUtc = -1`） | 改用含物理正午的 23h 区间，断言 `noonState === AVAILABLE` 且与同日 24h 区间正午相差 < 2 分钟 |
| `probe_data_unavailable_is_not_gap` | `kind === INVALID` | 任务 C 要求把「数据不可用」独立出来 | 断言 `kind === DayKind.UNAVAILABLE`，且不等于 `SKIPPED`/`INVALID` |

## 8. 构建结果

```text
> hvigor BUILD SUCCESSFUL in 12 s 731 ms
entry-default-signed.hap  2,113,091 bytes
测试包构建 BUILD SUCCESSFUL；两 HAP 安装成功（install bundle successfully ×2）
```

## 9. 未解决的边界

1. `OUTSIDE_DAY` 时时间戳统一回收为 −1，页面上只能显示「无」，无法提示「事件在相邻日期」；如需提示要等 2B-3B 的文案层。
2. `solarNoonNear()` 在区间内无物理正午时仍返回最近候选用于计算派生事件，因此这类日期的全部事件都可能落在区间外（表现为全部 `OUTSIDE_DAY`），这是刻意语义。
3. `fromLocal()` 仍可能返回 `NaN`（时区不可用），页面现已防护，但计划编辑 UI 的输入校验留给 2B-3C。
4. 1970 年前跳变语义（`getMilliseconds() <= 0`）仍未实测（设备侧无对应历史用例）。
5. `CalendarPage` 的 3/4 无效状态仍只在 CSV 与 a11y 文本体现，格子样式留给 2B-3B。

## 10. 对 2B-3B / 2B-3C 的兼容影响

- **2B-3B（图表/横轴/滑块）**：`SolarEvents` / `LightWindow` 只做了**字段追加**，既有数值字段与语义未变
  （时间戳仍为 UTC 毫秒，不可用时为 −1），Charts 无需改签名即可工作；新增的状态字段可用于区分「无窗口」与「日界非法」。
  日历格子如需区分 3/4 状态，已有 `polarState` 扩展值可用。
- **2B-3C（时间交互）**：`TimeUtil.resolveLocal()` 已可返回 `GAP/OVERLAP/UNAVAILABLE`，
  时间选择器接入时只需按状态提示；本轮未改 `fromLocal` 签名，旧调用点全部仍可编译。
- **2C（反向寻光算法）**：`searchInRanges()` 与 `SearchPlan` 已就位，粗扫/细化/去重逻辑一行未改，
  2C 可在区间语义不变的前提下替换采样策略。
