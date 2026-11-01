# 02B-3B · 真实时间轴、太阳曲线与多日期对照

> 基准 `a751637`，工作分支 `fix/core-quality-audit`。本轮只改时间轴、图表采样/坐标/刻度与两处入口防护；
> 未动 NOAA/Meeus 公式、时区候选解析、首页 Slider、计划编辑 TimePicker、粗扫算法、数据库与视觉体系。

## 1. 原来的 24 小时时间轴错误

| 位置 | 原代码 | 后果 |
|---|---|---|
| `Charts.sampleDay()` | `const end = dayStartUtc + 86400000` | 23 小时日多扫 1 小时（采到次日）、25 小时日少扫 1 小时 |
| `SunPathChart.xOf()` | `ratio = (utcMs - dayStartUtc) / 86400000` | 23/25 小时日曲线被压扁或留白，x 坐标与真实时间不符 |
| `SunPathChart` 选中标记 | `selectedUtc <= dayStartUtc + 86400000` | 25 小时日最后一小时内的选中标记丢失 |
| `SunPathChart` 刻度 | `0/6/12/18/24` 经 `fromLocal()` 生成 | 24:00 不是合法输入小时；春季 02:xx 不存在、秋季同一小时有两个 UTC，都可能标错或漏标 |
| `CompareChart` | 每系列只用 `dayStartUtc`，按 86400000 归一 | 不同日长的曲线横向错位，且 25%/50% 被标成 06h/12h |

## 2. 修复后的区间模型

新增 `entry/src/main/ets/services/Timeline.ets`（**零 Kit 依赖**）：

```ts
class TimelineModel { startUtc; endUtc; durationMs; valid; reason
  ratioOf(utcMs): number      // 区间内 [0,1)；区间外/NaN/Infinity → -1
}
class Timeline {
  static fromBounds(startUtc, endUtc): TimelineModel     // 非有限值或 end<=start → 无效，绝不回退 24h
  static sampleTimes(model, stepMs): number[]            // 升序、含起点、严格 < endUtc、末端补一点
  static tickRatios(width): number[]                     // 8 或 4 个比例
  static utcAtRatio(model, ratio): number                // 终点取 end-1（半开区间）
  static progressLabel(ratio): string                    // '25%'
}
```

要点：区间一律 `[startUtc, endUtc)`；不写死 24 小时；负 UTC 时间戳（1969 年等）完全合法；
无效输入返回无效模型，调用方看到 `-1` 必须放弃绘制。

## 3. SunPathChart 横轴映射

- 组件新增 `dayEndUtc` 属性；`draw()` 每次用 `Timeline.fromBounds(dayStart, dayEnd)` 重建时间轴；
- 采样改为 `sampleRange(start, end, lat, lon, 10)`，10 分钟步长、不越过 `endUtc`；
- `xOf()` 使用 `tm.ratioOf(utcMs)`，`-1` 直接不画；
- 选中标记只在 `tm.ratioOf(selectedUtc) >= 0` 时绘制，区间外不画错误标记；
- 时间轴无效时画「当日时间轴不可用」，不再用 24 小时兜底（也修掉了 `dayStartUtc <= 0` 误伤 1969 年的判断）。

## 4. 多日期对照的横轴语义

统一为 **「当地日期进度」**：`(sampleUtc - startUtc) / (endUtc - startUtc)`，每条曲线用自己所在日期的真实区间。

- `CompareSeries` 新增 `dayEndUtc`；
- 横轴刻度标签改为 `0% / 25% / 50% / 75% / 100%`，**不再把 25% 标成 06:00**；
- 无有效系列时画「没有可用的对照日期」；
- 数值对照表仍保留 06:00/09:00/12:00/15:00/18:00 五行，但每格改由 `resolveLocal()` + `localDayBounds()` 判定：
  缺口显示「该时刻不存在（夏令时跳变）」、不可用显示「时间不可用」、跳过日显示「该当地日期不存在」、
  重复小时标注「（重复小时取较早）」，不再出现 NaN。

两种横轴语义没有混用：曲线看进度比例，表格看当地钟点，各表其义。

## 5. DST 重复/缺失小时的显示策略

新增 `entry/src/main/ets/services/TimelineLabels.ets`：

- 横轴内部始终是 **UTC 连续时间**，刻度标签只做 `UTC → local` 转换（不用 `fromLocal` 反推）；
- **缺失小时**：因为标签来自真实存在的 UTC 时刻，春季不会出现 02:xx 刻度，曲线也不断裂；
- **重复小时**：同一本地时刻出现两次时（如秋季 01:30），标签追加偏移后缀（`01:30(-4)` / `01:30(-5)`），
  两个候选对应不同 UTC、不同 x 坐标；
- 刻度密度按画布宽度调整（≥340vp 8 个、260–340vp 4 个、更窄 4 个），窄图不丢关键两端。

## 6. 新增单元测试与失败复现

新增宿主机 8 条（`entry/src/test/Timeline.test.ets`，已注册）：

| 用例 | 断言 |
|---|---|
| `regular_24h_day_covers_whole_day` | 24h、49 点（48 + 末端补点）、升序、全部 `< end`、12:00 本地 = 0.5 |
| `spring_forward_23h_never_samples_next_day` | 23h、47 点、不采到次日、缺口内的 UTC 仍连续可采样 |
| `fall_back_25h_covers_extra_hour` | 25h、51 点、两个 01:30 的 UTC 比例相差 1/25 |
| `half_hour_days_have_correct_duration` | 23.5h / 24.5h 时长与 0.5 中点比例 |
| `pre_epoch_negative_timestamps_are_valid` | 1969-12-31 起止均为负、模型有效、采样点全为负 |
| `invalid_inputs_do_not_produce_models_or_coordinates` | NaN/Infinity/倒置区间 → 无效；`ratioOf` 返回 −1；步长 0/NaN → 空 |
| `tick_ratios_and_progress_labels` | 8/4 刻度、`utcAtRatio(1) = end-1`、进度标签 |
| `selected_time_outside_range_is_not_drawable` | 区间外选中返回 −1 |

失败复现说明（如实）：旧的 24 小时错误在**纯函数层不存在**（旧代码里没有可测试的纯函数），
因此本轮无法先写「对旧实现红、对新实现绿」的纯函数测试。旧缺陷的证据是代码事实（§1 的五处 `86400000`/固定刻度）
与随后修复的对比；测试是随新模块一起新增的回归保护，不是先红后绿的复现测试。

## 7. 构建结果

```text
宿主机：Tests run: 88, Failure: 0, Error: 0, Pass: 88   （原 80 条 + 新增 8 条）
外部对照：node tools/solar-check/check.mjs → 全部通过
应用构建：BUILD SUCCESSFUL，entry-default-signed.hap  2,149,337 bytes
测试包构建：BUILD SUCCESSFUL；两 HAP 安装成功（install bundle successfully ×2）
```

## 8. 真机图表验证结果

设备 `MIA-AL00 7.0.0.109`，`-s class TimeZoneReal` 单独执行：

```text
Tests run: 11, Failure: 0, Error: 0, Pass: 11
新增：timeline_labels_handle_dst_gap_and_overlap
```

该用例在真机上确认：

- 纽约春季刻度的标签中不存在 `02:xx`（缺失小时不显示）；`07:00Z → 03:00`、`06:59Z → 01:59`；
- 秋季两个本地 `01:30`（05:30Z / 06:30Z）经 `disambiguate()` 后标签不同；
- 豪勋爵 `+10:30` 的短偏移输出 `+10.5`。

**Canvas 像素级效果本轮未截图核验**：曲线与刻度的数值正确性由上述纯函数 + 设备标签用例覆盖，
像素呈现需要人工在真机页面观察，属未自动化的验收项（下面 §9 记录）。

## 9. 入口无效时间防护结果

| 入口 | 防护 |
|---|---|
| `SunPathPage.applyTime()` | `selectedUtc` 非有限 → 显示 `--`，不调 `position()` |
| `SunPathPage.saveAsPlan()` | 保存前校验：时刻有限、在 `[dayStart, dayEnd)` 内、经纬度有限且在 ±90/±180 内；不满足时 toast 提示并且**不创建 ShootPlan、不写库、不提示成功** |
| `ComparePage.rebuild()` | 每条曲线用 `localDayBounds()`；无效日不建系列；表格用 `resolveLocal()` 状态分支，杜绝 NaN |
| `SunPathChart` | 时间轴无效 → 空状态；`ratioOf < 0` 不画线不画标记 |

## 10. 2B-3C 剩余的时间选择器工作

1. 首页 Slider 仍按 1440 分钟线性映射，DST 日需要按真实日长映射并处理缺口/重复。
2. 计划编辑的 DatePicker/TimePicker 仍用 `fromLocal`，歧义时刻需要 `resolveLocal()` 交互（UNIQUE/OVERLAP 选择、GAP 提示）。
3. `CalendarPage` 格子的 3/4 无效状态仍只有 CSV/a11y 呈现，需要独立样式。
4. `OUTSIDE_DAY` 事件目前显示「无」，需要「事件在相邻日期」的提示文案。
5. Canvas 像素级效果与长文本刻度的实际观感需要人工真机核验。
