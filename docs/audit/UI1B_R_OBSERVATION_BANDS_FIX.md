# UI-1B-R · ObservationBands 负时间戳缺陷修复

## 1. 缺陷

`services/ObservationBands.ets` 原实现：

```ts
if (startUtc < 0 || endUtc < 0 || endUtc <= startUtc) {
  return;   // ← 把「负时间戳」当成缺失值
}
```

负 Unix 毫秒是 **1970 年以前合法的 UTC 时间**（项目本身支持 1969 等历史日搜索，
`SolarCalc`/`TimeUtil` 也明确「不要用时间戳正负判断可用性」）。
该守卫会把 1970 年前的黄金/蓝调窗口静默丢弃，导致历史日期页面缺少时段带。

## 2. 根因确认

`LightWindow` 已提供**显式状态**：

```ts
export enum WindowState { AVAILABLE = 0, ABSENT = 1, DAY_INVALID = 2 }
class LightWindow {
  goldenMorningState / goldenEveningState / blueMorningState / blueEveningState: number
  dayValid: boolean
}
```

因此可用状态判定窗口是否存在，无需借助时间戳符号。

## 3. 修复

```ts
private static pushRange(out: number[], state: number, startUtc: number, endUtc: number): void {
  if (state !== WindowState.AVAILABLE) { return; }          // 只信显式状态
  if (!Number.isFinite(startUtc) || !Number.isFinite(endUtc)) { return; }
  if (!(endUtc > startUtc)) { return; }                     // 逆序/零长度
  out.push(startUtc); out.push(endUtc);                     // 负值合法，照常收录
}
```

`goldenPairs()` / `bluePairs()` 改为传入各自的 `*State`。
保留原有的 `dayValid` 检查与裁剪逻辑（`clippedPairs` 仍按 `[dayStart, dayEnd)` 裁剪）。

## 4. 测试证据（entry/src/test/ObservationBands.test.ets，8 条）

| 用例 | 断言 |
|---|---|
| `golden_and_blue_ranges_come_from_real_windows` | AVAILABLE 下晨/夕窗口按 UTC 对输出 |
| `pre_epoch_windows_are_legal_and_kept` | **负时间戳窗口被保留**（-30000…-500） |
| `cross_epoch_window_is_kept` | 跨 Epoch（-6000 → 6000）被保留 |
| `absent_state_is_rejected_even_with_plausible_timestamps` | 状态 ABSENT 时即使时间戳正常也拒绝 |
| `day_invalid_state_yields_no_bands` | DAY_INVALID → 空 |
| `reversed_or_zero_length_ranges_are_dropped` | 逆序/零长度丢弃，合法的黄昏窗口保留 |
| `clipping_uses_real_day_bounds` | 按真实日界裁剪 |
| `clipping_handles_pre_epoch_ranges` | 负区间裁剪正确（-8000,-3000） |

## 5. 回归

```text
宿主机：Tests run: 205, Failure: 0, Error: 0, Pass: 205（原 202 + 更新的 8 条中净增 3 条）
```

未改动 SolarCalc / TimeUtil / SearchSession / 数据库；`clippedPairs` 语义未变（仍拒绝非法日界）。

## 6. 残留说明

- 若未来 `LightWindow` 引入新的状态值（例如「窗口被目标日完全截断」），需同步扩展本模块的判定；
- 当前守卫**不再**以时间戳符号判断，历史日期与未来日期走同一条路径。
