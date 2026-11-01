# 02B-2 · 真实本地日期边界业务集成

> 基准 `2e7be0f`，工作分支 `fix/core-quality-audit`。本轮只做集成与必要修复，未重写时区解析器、未改反向寻光粗扫策略、未动 Charts/UI 视觉。

## 1. 修改文件

| 文件 | 改动 |
|---|---|
| `services/SolarCalc.ets` | 新增 `solarNoonNear()`；`events()` / `lightWindows()` 改用「区间内物理正午」，删除按 `dayLength` 平移；新增 `dayValid` 标记；非法 `dayEnd` 不再静默按 24 小时 |
| `services/ReverseSearch.ets` | 新增 `DayRange` 与 `searchInRanges()`；`refineAt()` 增加区间限界；`search()` 保留为 24 小时兼容包装 |
| `pages/HomePage.ets` | 新增 `dayEndUtc` + `applyDayBounds()`，事件/窗口传真实日界 |
| `pages/SunPathPage.ets` | 新增 `dayEndUtc` + `syncDayEnd()`；前后翻日、重置今天、日期选择全部走真实日界；`addLocalDays` 返回 NaN 时不再覆盖起点 |
| `pages/CalendarPage.ets` | 每天改用 `localDayBounds()`；新增 `dayEndUtc`；`polarState` 扩展 3=日期不存在、4=时区数据不可用 |
| `pages/PlaceDetailPage.ets` | 用真实日界；无效时不把 NaN 传给 SolarCalc（传 0，`dayValid=false`） |
| `pages/ReversePage.ets` | 逐日构造 `DayRange`（跳过被整日跳过的日期），进度分母改为实际可搜索日数 |
| `ohosTest/.../TimeZoneReal.test.ets` | 修正豪勋爵跳变方向断言：4 月回拨 −30 分钟、10 月前跳 +30 分钟 |
| `test/SolarEvents.test.ets` | 新增 6 条（23h/25h 平移、真实日界归属、非法 dayEnd、窗口不越界、pre-epoch 事件） |
| `test/ReverseSearch.test.ets` | 新增 4 条（23h/25h/23.5h/24.5h 区间、不扫到次日） |

## 2. 原始缺陷与复现

### 2.1 太阳正午按民用日长平移（SolarCalc）

原实现取 `anchorOf(dayStart)` 得到「包含当地正午的 UTC 日」，算出该日正午后，若不在 `[dayStart, dayEnd)` 内就做：

```ts
noon += dayLength;   // 或 noon -= dayLength
```

`dayLength` 是民用日长度（23/25/23.5/24.5 小时），而相邻两个**太阳正午**的间隔恒为 24 小时。
一旦触发平移，23 小时的日会让正午偏 1 小时，半小时时区偏 30 分钟。

**复现测试（修复前失败）**：

```text
Tests run: 68, Failure: 2
失败：solar_noon_not_shifted_by_23h_civil_day
      events_reject_invalid_day_end_without_assuming_24h
```

判据：23 小时区间 `[2026-03-08T18:00Z, 03-09T17:00Z)` 的中点在 03-09，物理正午约 `03-09T17:06Z`（区间结束后 6 分钟）。
旧实现给出 `03-08T18:06Z`（比物理正午晚 1 小时）；测试断言「与相邻太阳日的日内时刻相差 < 2 分钟」，旧实现差 60 分钟。

### 2.2 非法 dayEnd 被当成 24 小时

`dayEndLocalUtc <= dayStartLocalUtc` 时旧代码退化为 `dayStart + 86400000`，等于把错误区间静默修正成 24 小时。
新实现返回 `dayValid = false` 且所有时间为 −1。

## 3. 正午的正确求解

```ts
static solarNoonNear(dayStartUtc, dayEndUtc, lonDeg): number
```

1. 候选只来自相邻三个 UTC 日的物理正午：`midnight + (720 − 4λ − EoT) 分钟`，间隔恒为 86400000；
2. 优先返回真正落在 `[dayStart, dayEnd)` 内的那个；
3. 若区间内没有（极端时区错配的人造区间），返回距离区间最近的候选，**从不**按民用日长平移；
4. 赤纬与均时差在该正午时刻取值，不再用「UTC 零点 + 12 小时」的近似。

语义：`events()` / `lightWindows()` 描述的是「该民用日内所属太阳日」的事件；
`lightWindows()` 的两段窗口由 `bandWindows()` 裁切到 `[dayStart, dayEnd)`，不会越界。

## 4. 真实日界如何传递

调用链：`TimeUtil.localDayBounds(tzId, y, m, d)` → `LocalDayBounds{startUtc, endUtc, valid, kind}`
→ 页面保存 `dayStartUtc` / `dayEndUtc` → `SolarCalc.events(dayStart, lat, lon, dayEnd)`、
`SolarCalc.lightWindows(dayStart, lat, lon, th, dayEnd)`。

| 页面 | 行为 |
|---|---|
| HomePage | `applyDayBounds()`：本地日期不可用或日界无效 → `dayStart=0, dayEnd=0` → 事件全 −1、界面显示「无」，不出现 NaN |
| SunPathPage | `syncDayEnd()` 挂载在载入/翻日/重置今天/日期选择四处；`addLocalDays` 返回 NaN 时保留原起点 |
| CalendarPage | 每天一次 `localDayBounds`；无效应写 `polarState=3`（整日跳过）或 `4`（数据不可用），CSV 导出同步区分 |
| PlaceDetailPage | 本地日期不可用 → 传 0 与 0（`dayValid=false`），不下发 NaN |
| ReversePage | 逐日 `localDayBounds` 构造 `DayRange`，跳过被整日跳过的日期；全部无效时报错而不是空搜索 |

## 5. ReverseSearch 的真实 UTC 区间

```ts
class DayRange { startUtc; endUtc }
static searchInRanges(goal, thresholds, ranges: DayRange[]): Candidate[]
```

- 每天只扫描 `[startUtc, endUtc)`，绝不再出现 `dayStart + 86400000`；
- `refineAt()` 增加 `minMs/maxMs` 参数，细化过程与最终结果都被夹在区间内（`maxMs − 1` 为上界，保证半开区间语义）；
- 非法/空区间（`endUtc <= startUtc`）直接跳过，不猜测 24 小时；
- 5 分钟粗扫 + 30s/5s/1s 细化 + 10 分钟合并 + 误差排序策略**完全未改**；
- `search(goal, th, dayStarts)` 保留为 24 小时兼容包装，仅为旧调用方与既有测试服务。

## 6. 日长测试结果（宿主机）

| 场景 | 区间 | 断言 | 结果 |
|---|---|---|---|
| 上海常规日 | 24h | 窗口有序、落在区间内、代表时刻在带内 | ✅ |
| 纽约春季 | 23h | 正午不被 −23h 平移；事件与窗口均在区间内 | ✅ |
| 纽约秋季 | 25h | 正午取区间内物理正午；事件与窗口均在区间内 | ✅ |
| 豪勋爵 | 23.5h / 24.5h | 区间搜索命中且结果在区间内 | ✅ |
| UTC+14（基里蒂马蒂） | 24h | 正午与日出日落均在区间内 | ✅ |
| 极昼/极夜 | 24h | 四组阈值全 −1、`polarState` 正确、窗口为空 | ✅ |
| 1969-12-31（上海） | 24h | 事件为负时间戳但 ≠ −1，正午在区间内 | ✅ |

## 7. 新增/修改测试

新增 10 条（62 → 72）：

| 文件 | 用例 |
|---|---|
| `SolarEvents.test.ets` | `solar_noon_not_shifted_by_23h_civil_day`、`solar_noon_not_shifted_by_25h_civil_day`、`events_stay_inside_real_23h_and_25h_bounds`、`events_reject_invalid_day_end_without_assuming_24h`、`windows_stay_inside_real_bounds_23h_and_25h`、`pre_epoch_events_are_negative_but_not_sentinels` |
| `ReverseSearch.test.ets` | `range_search_respects_23h_bounds`、`range_search_does_not_scan_next_local_day`、`range_search_25h_covers_last_hour`、`range_search_half_hour_days` |

修正 1 条测试预期错误（非算法问题）：`zone_rules_transition_values_are_real` 原断言豪勋爵 `offsetAfter − offsetBefore = +30 分钟`，
但 2026-01-01 之后的下一次跳变是 **4 月 5 日回拨**（+11 → +10:30，差值 −30 分钟）。现已分别断言 4 月 −30 分钟与 10 月 +30 分钟。

## 8. 实际执行结果

```text
# 宿主机全部单测
> hvigor BUILD SUCCESSFUL in 8 s 797 ms
Tests run: 72, Failure: 0, Error: 0, Pass: 72, Ignore: 0

# 外部参考对照
node tools/solar-check/check.mjs → 结论：全部通过（最大误差 27.4s，容差 120s）

# 应用构建
> hvigor BUILD SUCCESSFUL in 12 s 235 ms
entry-default-signed.hap  2,096,533 bytes

# 测试包构建 + 安装
BUILD SUCCESSFUL；两 HAP install bundle successfully ×2
```

## 9. 真机 IANA 测试（已执行并通过）

设备解锁后单独执行 `TimeZoneReal` 套件（不混入 UI 用例）：

```bash
hdc -t 4EE9K25515007252 shell "aa test -b com.hhyxx.LightBearing -m entry_test \
  -s unittest OpenHarmonyTestRunner -s class TimeZoneReal -s timeout 90000"
```

```text
OHOS_REPORT_RESULT: stream=Tests run: 10, Failure: 0, Error: 0, Pass: 10, Ignore: 0
```

设备：`MIA-AL00 7.0.0.109(SP8C00E105R5P2)`，API 26。

实际执行的 10 条用例（全部通过）：

| 用例 | 验证内容 |
|---|---|
| `new_york_spring_forward_2026_03_08` | 边界 05:00Z→次日 04:00Z、23 小时、02:30 为 GAP |
| `new_york_fall_back_2026_11_01` | 边界 04:00Z→次日 05:00Z、25 小时、01:30 双候选 05:30Z/06:30Z |
| `shanghai_regular_day_2026_10_30` | 16:00Z 边界、24 小时、当地正午唯一 |
| `kathmandu_non_hour_offset` | UTC+05:45 = 20 700 000 ms、日界 18:15Z |
| `lord_howe_half_hour_dst` | 24.5h / 23.5h 日、02:15 GAP、01:45 双候选相差半小时 |
| `kiritimati_utc_plus_14` | UTC+14、日界 10:00Z |
| `apia_skipped_day_2011_12_30` | 整日 SKIPPED、前一天结束于 2011-12-30T10:00Z |
| `invalid_zone_and_date_are_rejected` | 非法时区返回 NaN/INVALID、2 月 30 日被拒 |
| `start_of_day_and_add_days_follow_real_bounds` | DST 日 `startOfLocalDay`/`addLocalDays` 落在真实边界 |
| `zone_rules_transition_values_are_real` | `nextTransition().getMilliseconds()/getOffsetBefore/After` 真实值：纽约 2026-03-08T07:00Z（−5h→−4h）；豪勋爵 4 月回拨 −30 分钟、10 月前跳 +30 分钟 |

至此，`i18n` 真实时区数据（含跳变对象三个方法）与全部 23/25/23.5/24.5 小时边界
在真机上得到确认，不再是「仅合成时区验证」。

## 10. 留给 2B-3 的 UI/图表工作

1. `Charts.ets` 的日轨横轴仍按 `(t − dayStart) / 86400000` 归一，23/25 小时日会被压扁或留白。
2. 首页时间滑块的取值范围仍按 24 小时处理，DST 日会少/多半小时到一小时。
3. 计划编辑的日期选择 UI 仍用 `TimeUtil.fromLocal()` 处理用户输入，未提示 GAP/OVERLAP。
4. CalendarPage 的 3/4 两种无效状态目前只在 CSV 与 a11y 文本体现，格子内还没有独立样式。
5. 各页面的 `ev.xxxUtc < 0 ? '无'` 判断在 1969 年及更早日期会误显示「无」（见 02B1 §F3 清单）。

## 11. 现有 2C 反向寻光算法遗留

1. 5 分钟粗扫 + 仅命中后细化：真实命中窗口短于 5 分钟时仍可能整段漏报（2C 专项）。
2. 10 分钟合并规则可能把相邻两个真实窗口误合并成一个。
3. `maxResults` 截断在按误差排序之后进行，不保证时间分布，可能连续返回同一时段的多解。
4. 未提供「搜索区间跨多天时的全局最优」证明，仅逐日独立搜索后合并。
