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
