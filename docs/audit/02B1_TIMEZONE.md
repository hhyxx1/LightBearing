# 02B-1 · 时区核心工具与本地日期边界

> 本轮只做时区核心工具与边界测试；未触碰反向寻光算法、太阳高度公式、页面布局、Charts、数据库与签名配置。
> 基准 `df436e4`，工作分支 `fix/core-quality-audit`。

## 1. 原始问题（已在真机复现）

| # | 代码事实 | 实际后果 |
|---|---|---|
| 1 | `fromLocal()` 只做两次偏移试探（`naive - off1`，若 `off2 !== off1` 再试 `naive - off2`） | 无法区分「唯一 / 缺口 / 重复」三种情况，缺口内的时间被静默映射到邻近时刻 |
| 2 | `offsetMs()` 捕获异常后 `return 0` | 非法时区被静默当成 UTC（`+00:00`），用户看到的是错误的本地时间 |
| 3 | `startOfLocalDay()` 依赖 `fromLocal()` 的午夜转换 | 午夜发生跳变时（本地 00:00 不存在或被重复）起点可能落到错误时刻 |
| 4 | `addLocalDays()` 用日历字段 + 00:00 转换 | 继承同一歧义；且按 24 小时推进，跨夏令时日后可能偏移 |
| 5 | 没有统一的真实本地日边界结构 | 全项目默认「一天 = 86400000 ms」，DST 日必然出错 |

**真机证据（修复前，`entry/src/ohosTest/ets/test/TimeZoneProbe.test.ets`，已在修复后删除）**：

```text
Error in invalid_zone_must_not_be_silently_utc, expect 0 equals NaN
   → TimeUtil.offsetMs('Not/AZone', …) 返回 0（静默 UTC）
Error in nonexistent_local_time_roundtrip, expect true, actualValue is false
   → 纽约 2026-03-08 02:30 不存在，旧 fromLocal 仍返回一个具体时刻
（对照组 shanghai_day_bounds_control 通过）
```

## 2. 架构：纯算法层 + i18n 适配层

**为什么拆分**：实测宿主机单测环境里 `@kit.LocalizationKit` 是空实现——`getTimeZone('Asia/Shanghai').getID()`
返回空串、`getOffset()` 返回 0、`getZoneRules().nextTransition()` 返回 0 时刻。真实 IANA 数据只能在设备上取。

- `services/LocalTimeResolver.ets`（新增，**零 Kit 依赖**）：解析状态机、候选枚举与反向校验、日边界推导。
  通过 `ZoneProbe` 接口注入时区能力。
- `services/TimeUtil.ets`：实现 `I18nZoneProbe`（`getOffset` / `getZoneRules().nextTransition()` /
  `getOffsetBefore` / `getOffsetAfter` / `getMilliseconds`，均为 API 20+ 公开接口），对外暴露安全 API，并保留旧签名。

## 3. 新接口定义

```ts
enum LocalResolveStatus { UNIQUE, GAP, OVERLAP, INVALID }

class LocalResolveResult {
  status: LocalResolveStatus;
  candidatesUtc: number[];      // 升序；UNIQUE 1 个，OVERLAP 2 个，GAP/INVALID 空
  candidateOffsets: number[];   // 与 candidatesUtc 一一对应（ms，东为正）
  reason: string;
}

class LocalDayBounds {
  startUtc: number; endUtc: number; durationMs: number;   // 真实区间 [startUtc, endUtc)
  year: number; month: number; day: number;
  valid: boolean; kind: DayKind; reason: string;
}
enum DayKind { NORMAL, SHORT, LONG, SKIPPED, INVALID }

// TimeUtil 对外
TimeUtil.resolveLocal(tzId, y, m, d, hh, mm): LocalResolveResult
TimeUtil.localDayBounds(tzId, y, m, d): LocalDayBounds
TimeUtil.isValidTimeZoneId(tzId): boolean
TimeUtil.offsetMs(tzId, utcMs): number        // 非法时区返回 NaN，不再返回 0
```

## 4. GAP / OVERLAP 的处理语义

不做「试探两次偏移」，而是**候选枚举 + 反向校验**：

1. 收集候选偏移：本地时刻前后 36 小时的偏移 + 邻近跳变（`nextTransition`）的前后偏移；
2. 每个偏移给候选 `utc = naive − offset`；
3. **反向校验**：`offsetAt(utc)` 必须等于该 offset，且 `utc + offset` 换算回本地年月日时分必须与输入完全一致；
4. 去重后按 UTC 升序：0 个 → `GAP`，1 个 → `UNIQUE`，2 个 → `OVERLAP`（两个候选都保留）。

日边界 `localDayBounds`：

- 起点 = 该本地日**实际存在的第一个时刻**（00:00 被跳变吃掉时逐分钟找第一个存在时刻）；
- 终点 = **下一个存在的**本地日的第一个时刻（跨过被整日跳过的日期）；
- 时长由两端相减得出，不写死 24 小时；整日被跳过返回 `valid=false, kind=SKIPPED`，不映射到相邻日期。

## 5. 23 / 25 / 23.5 / 24.5 小时验证结果

合成时区（宿主机，期望值手算）：

| 场景 | 期望 start | 期望 end | 期望时长 | 结果 |
|---|---|---|---|---|
| 纽约式春季（2026-03-08） | 2026-03-08T05:00Z | 2026-03-09T04:00Z | 23h `SHORT` | ✅ |
| 纽约式秋季（2026-11-01） | 2026-11-01T04:00Z | 2026-11-02T05:00Z | 25h `LONG` | ✅ |
| 豪勋爵式回拨（2026-04-05） | — | — | 24.5h `LONG` | ✅ |
| 豪勋爵式跳表（2026-10-04） | — | — | 23.5h `SHORT` | ✅ |
| 阿皮亚式跳日（2011-12-30） | — | — | `SKIPPED` | ✅ |
| 跳日的前一天（2011-12-29） | 2011-12-29T10:00Z | 2011-12-30T10:00Z | 24h | ✅ |

真实 IANA 时区的设备侧用例（`entry/src/ohosTest/ets/test/TimeZoneReal.test.ets`）覆盖同样的场景，
期望值全部是手算固定常量（纽约 05:00Z/04:00Z、05:30Z/06:30Z，上海 16:00Z，加德满都 +05:45=20 700 000 ms，
基里蒂马蒂 +14h，阿皮亚跳日）。**本轮未能执行**，原因见 §8。

## 6. 独立参考数据来源

- 时区规则：IANA tzdata，经 HarmonyOS `i18n.TimeZone.getZoneRules()` 读取；
- 夏令时日期规则（公开常识，非程序生成）：美国「3 月第二个周日 / 11 月第一个周日」、
  澳大利亚「4 月第一个周日 / 10 月第一个周日」、豪勋爵岛半小时偏移；
- 所有期望 UTC 值均为手算常量写死在测试里，未调用被测函数生成。

## 7. 旧接口兼容与调用方清单

`fromLocal()` 保留原签名，兼容策略写入代码注释：

| 解析结果 | `fromLocal()` 返回 |
|---|---|
| `UNIQUE` | 唯一候选 |
| `OVERLAP` | 较早的一次（UTC 较小） |
| `GAP` | 跳变后的第一个真实时刻（缺口结束瞬间），不静默平移到别的本地时间 |
| `INVALID` | `NaN` |

`startOfLocalDay()` / `addLocalDays()` 改为基于 `localDayBounds()`；时区非法时返回 `NaN`，
格式化函数遇到非法时区显示 `--:--` / `----` / `UTC?`，不再显示错误的 UTC 时间。

调用方清单（全部未改动，仅受益）：

| 方法 | 外部调用点 |
|---|---|
| `fromLocal` | `Charts.ets:187`、`CalendarPage:93,107`、`ComparePage:120,143`、`HomePage:139`、`PlannerPage:361,377`、`SunPathPage:80,189` |
| `startOfLocalDay` | `HomePage:75,81`、`PlaceDetailPage:48`、`ReversePage:122`、`SunPathPage:58,165` |
| `addLocalDays` | `ReversePage:125`、`SunPathPage:101` |
| `toLocal` | `Charts.ets:187,188`、`CalendarPage:76,122,153`、`ComparePage:60`、`HomePage:83,136`、`PlannerPage:115,140,360,519`、`SunPathPage:70,79` |
| `offsetMs` | 无页面直接调用（仅 TimeUtil 内部与 `offsetLabel`） |

本次未改任何页面；`LocalParts` 新增 `valid` 字段（默认 true），不影响既有读取。

## 8. 实际执行结果

```text
# 宿主机单元测试（含新增时区用例）
> hvigor BUILD SUCCESSFUL in 8 s 106 ms
Tests run: 46, Failure: 0, Error: 0, Pass: 46, Ignore: 0
（新增 13 条：LocalTimeResolver 全套边界）

# 应用构建
> hvigor BUILD SUCCESSFUL in 11 s 768 ms
entry-default-signed.hap  2,083,543 bytes

# 测试包构建
> hvigor BUILD SUCCESSFUL in 9 s 465 ms
```

**设备侧真实时区测试未执行**。真机（MIA-AL00）当前处于锁屏状态，`aa test` 启动测试 Ability 被系统拒绝：

```text
error: failed to start ability.
Error Code:10106102  Error message:The device screen is locked during the application launch,
unlock screen failed.
Error cause: The current mode is developer mode, and the screen cannot be unlocked automatically
TestFinished-ResultCode: -3
```

两 HAP 安装本身成功（`install bundle successfully` ×2）。解锁屏幕后可直接复现：

```bash
hvigorw assembleHap --mode module -p module=entry@ohosTest -p product=default -p buildMode=debug
hdc -t 4EE9K25515007252 install -r entry-default-signed.hap entry-ohosTest-signed.hap
hdc -t 4EE9K25515007252 shell "aa test -b com.hhyxx.LightBearing -m entry_test -s unittest OpenHarmonyTestRunner -s timeout 90000"
```

已知限制：同一命令在解锁状态下还会跑 3 条 UI 用例，它们因 `16000001`（后台启动限制）失败，
与本轮改动无关；时区用例（`class=TimeZoneReal`）不依赖 UI，预期全绿但**尚无实际执行记录**。

## 9. 下一轮（2B-2）必须修改的文件

1. `entry/src/main/ets/services/ReverseSearch.ets`：`dayStart + 86400000` 改成 `[startUtc, endUtc)` 真实边界。
2. `entry/src/main/ets/pages/ReversePage.ets`：构造 `dayStarts` 逐日推进时改用 `localDayBounds()`（当前用 `addLocalDays` 拼日列表，需改成成对边界）。
3. `entry/src/main/ets/services/SolarCalc.ets`：`events()` / `lightWindows()` 的 `dayEndLocalUtc` 参数由调用方传入真实边界（接口已就绪）。
4. `entry/src/main/ets/components/Charts.ets`：采样横轴按真实日长归一（当前 `(t - dayStart) / 86400000`）。
5. 各页面把 `fromLocal()` 替换为 `resolveLocal()`，对 `GAP` / `OVERLAP` 给出 UI 提示（本轮只提供 API）。

## 10. 遗留风险

1. 设备侧真实时区用例未执行，`i18n` 在真机上的 `nextTransition` 行为（尤其 `getMilliseconds() === 0` 语义、历史规则如 Apia 2011）尚未实测。
2. 午夜跳变日（本地 00:00 被吃掉）走的是逐分钟扫描，单日最坏 1440 次解析；日历页跨大量此类日期时有性能风险，2B-2 需评估缓存。
3. `bandWindows()`/`events()` 的日长参数默认仍是 24 小时，未传 `dayEndLocalUtc` 的旧调用点行为不变——这属于刻意兼容，2B-2 要逐个改为真实边界。
4. `isValidTimeZoneId` 依赖 `getAvailableIDs()` 全量列表（首次调用建立缓存），列表含历史别名；若设备 tzdata 缺少某个 ID，会被判为非法（宁可拒绝也不静默 UTC）。
5. `fromLocal()` 对 `GAP` 返回缺口结束时刻，属于兼容行为，界面若需明确提示应改用 `resolveLocal()`。

---

# 补充修复（复审后追加）

复审要求补两项异常处理验证、单独跑真机 IANA 套件、并复核历史日期与日界极端。以下逐项对应。

## S1. 数据不可用不再被误判为 GAP

**原问题**：`resolve()` 在候选 UTC 为空时直接返回 `GAP`。但候选为空也可能是探针拿不到数据
（`offsetAt()` 返回 NaN、跳变表不可用、候选校验阶段查询失败），此时向用户报「该时间不存在」是错的。

**修复**：

| 场景 | 判定 | 说明 |
|---|---|---|
| 探针 `isValid() === false` | `INVALID` | 非法时区 |
| 日期/时间越界 | `INVALID` | 严格校验，不允许 `Date.UTC` 规范化 |
| 偏移查询返回 NaN（采集或校验阶段） | **`UNAVAILABLE`（新增状态）** | 明确表示「数据不可用，无法判断」，绝不报 GAP |
| 候选全部校验通过 0 个、且无故障 | `GAP` | 真实缺口 |
| 偏移值恰为 0（UTC+00:00） | 正常参与候选 | 用 `Number.isNaN` 判断失败，不用真假值 |

`dayBounds()` 同样区分：起点/终点算不出来且原因是数据不可用时返回 `kind = INVALID`，
而不是 `SKIPPED`——「整日被跳过」必须是真的被跳过。

**新增测试（宿主机，合成探针）**：

| 用例 | 预期 | 实际 |
|---|---|---|
| `zero_offset_is_valid_not_failure`（偏移 0 的时区正午） | `UNIQUE`、偏移 0、日 24h | ✅ |
| `probe_data_unavailable_is_not_gap`（有效探针 + 全部 NaN） | `UNAVAILABLE`，且 `dayBounds` 为 `INVALID` 而非 `SKIPPED` | ✅ |
| `candidate_verification_failure_is_unavailable`（仅候选时刻返回 NaN） | `UNAVAILABLE` | ✅ |
| `real_gap_and_overlap_still_reported` | 纽约春 02:30 → `GAP`；秋 01:30 → `OVERLAP` | ✅ |

## S2. `fromLocal()` 缺口回退改为「必须匹配对应跳变」

**原问题**：拿到 `GAP` 后用 `transitionAfter(naive − 36h)` 取到的那次跳变直接当缺口结束，
没有验证这次跳变是否真的造成了输入时刻的缺口——可能返回一个不相关跳变的时间。

**修复**（`LocalTimeResolver.toUtcCompat()`）：

```text
缺口区间（本地）= [atUtc + offsetBefore, atUtc + offsetAfter)
仅当 offsetAfter > offsetBefore 且 naive ∈ 该区间时，才返回 atUtc（缺口结束的第一个真实时刻）
否则返回 NaN
```

`offsetAfter <= offsetBefore`（回拨）被显式排除；跳变表里没有覆盖该时刻的跳变时一律 NaN，不猜。

**新增测试**：

| 用例 | 预期 | 实际 |
|---|---|---|
| `compat_fromLocal_gap_returns_gap_end`（纽约春 02:30） | 返回 07:00Z，换算回本地 = 03:00 | ✅ |
| `compat_fromLocal_half_hour_gap`（豪勋爵 02:15） | 返回 2026-10-03T15:30Z，本地 = 02:30 | ✅ |
| `compat_fromLocal_skipped_day`（阿皮亚 12-30 12:00） | 返回 2011-12-30T10:00Z，本地 = 12-31 00:00 | ✅ |
| `compat_fromLocal_normal_and_overlap` | 普通时间唯一候选；重复时间取较早 | ✅ |
| `compat_fromLocal_never_guesses_without_matching_transition` | 探针故障 / 跳变不匹配 / 非法日期 → `NaN` | ✅ |

文档与代码注释均已标注：`fromLocal()` 是**兼容接口**，不适合处理需要用户确认的时间输入；
UI 迁移必须用 `resolveLocal()`。

## S3. 历史日期与日界极端

| 风险 | 结论与处理 |
|---|---|
| `transitionAfter()` 把 `ms <= 0` 视为无跳变 | 按官方文档，`getMilliseconds()` 在「raw offset 不变且不使用夏令时」时返回 0；真实跳变时间戳为 0 只会发生在 1970-01-01T00:00Z 这一刻，属于极端历史边界。**不影响解析正确性**：`resolve()` 只把跳变当作候选偏移的补充来源，主来源是前后 36 小时的偏移采样。新增 `resolver_works_without_transition_info` 证明「完全没有跳变表」时 `UNIQUE` / `OVERLAP` 仍然正确。 |
| `firstExistingInstant()` 抽样判断整日跳过 | **原实现有真实风险**：抽样 6/12/18/23 点可能全部落在相邻日期。已删除抽样快捷判断，改为 00:00 不可用时**逐分钟扫描整日**；新增 `short_valid_window_day_is_not_marked_skipped`（构造本地日仅 01:00–04:00 存在，3 小时）验证不再误判 SKIPPED。代价：仅当 00:00 落在缺口里才会有最多 1440 次解析（罕见日）。 |
| `addLocalDays()` 遇到被跳过日期返回 NaN | 改为沿推进方向寻找最近的存在的日期（前进向后找、后退向前找，最多 4 天），找不到才 NaN。新增 `add_local_days_skips_skipped_calendar_day`：阿皮亚 12-29 `+1` → 12-31 起点；12-31 `−1` → 12-29 起点；普通时区 `+1` 正确。 |
| 历史日期（1970 前） | 无实际可触发问题，未做大规模改写；在 §10 保留为未验证边界。 |

## S4. 本轮实际执行结果

```text
# 宿主机全部单元测试（保留原 46 条 + 新增 12 条）
> hvigor BUILD SUCCESSFUL in 8 s 193 ms
Tests run: 58, Failure: 0, Error: 0, Pass: 58, Ignore: 0

# 应用构建
> hvigor BUILD SUCCESSFUL in 11 s 761 ms
entry-default-signed.hap  2,084,444 bytes

# 测试包构建
> hvigor BUILD SUCCESSFUL in 9 s 458 ms
两 HAP 安装成功（install bundle successfully ×2）
```

**真机 IANA 套件：0 条执行，未验证。** 使用任务书给的命令单独跑 `TimeZoneReal`：

```bash
hdc shell "aa test -b com.hhyxx.LightBearing -m entry_test -s unittest OpenHarmonyTestRunner -s class TimeZoneReal -s timeout 90000"
```

设备仍处锁屏，测试 Ability 无法启动：

```text
error: failed to start ability.
Error Code:10106102  The device screen is locked during the application launch, unlock screen failed.
TestFinished-ResultCode: -3
```

按要求未尝试绕过锁屏、未修改测试。因此 **New York / Shanghai / Kathmandu / Lord Howe / Kiritimati / Apia
六个真实时区用例本轮全部未执行**。本轮新增的设备侧用例
`zone_rules_transition_values_are_real`（直接核验 `getMilliseconds()` = 2026-03-08T07:00Z、
前后偏移 −5h/−4h、豪勋爵前后差 30 分钟）同样未执行。

解锁后可单独复跑上述命令；`-s class TimeZoneReal` 只跑该套件，不会混入 UI 用例。

## S5. 补充后的遗留

1. 真机 IANA 数据（含 `getMilliseconds()`/`getOffsetBefore/After` 的真实返回值）**仍未经设备验证**，这是本轮最大的未验证项。
2. 1970 年前的跳变（`getMilliseconds() <= 0`）语义未实测；当前实现不依赖跳变表，但历史边界仍属未验证。
3. 逐分钟扫描整日的最坏代价 1440 次解析，日历页跨大量「00:00 落在缺口」的日期时需要缓存，属 2B-2 评估项。
4. `UNAVAILABLE` 目前只在 `resolveLocal` / 内部使用；页面尚未展示该状态（2B-2 迁移时补 UI 提示）。
