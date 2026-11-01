# 02A · 太阳事件与光线窗口正确性

> 本轮（2A）只改 `SolarCalc` 的事件/窗口计算与其测试；未触碰 2B（夏令时/本地日期边界）与 2C（反向寻光）代码，
> 未改 UI、数据库、Bundle Name 与依赖。

## 1. 问题与根因

### 问题 1：日出无解时提前返回，曙暮光被整组漏算

```ts
// 修复前
const sunriseH = SolarCalc.hourAngleForAltitude(latDeg, decl, -0.833);
...
if (sunriseH < 0) {
  e.polarState = e.noonAltitudeDeg > 0 ? 1 : 2;
  return e;            // ← 直接返回
}
```

**根因**：把「日出土 −0.833° 无穿越」当成了「当天没有任何事件」。极夜当天太阳虽然不升出地平线，
仍可能升到 −3°（特罗姆瑟冬至正午约 −3.09°），此时 −6°、−12°、−18° 三个阈值都存在穿越，
民用/航海/天文曙暮光真实存在，却被 `return` 跳过，全部保持 −1。

**可复现证据**：新增测试 `polar_night_still_has_twilight` 在修复前失败（`civilDawn` 期望 08:31:12Z，实际 −1）。

### 问题 2：`lightWindows()` 用无效时角推算窗口端点

```ts
// 修复前
const hGoldenUpper = ...goldenUpperDeg);
const hGoldenLower = ...goldenLowerDeg);
const hBlueLower   = ...blueLowerDeg);

if (hGoldenUpper >= 0) { w.goldenMorningEndUtc = ...; w.goldenEveningStartUtc = ...; }
if (hGoldenLower >= 0) { w.goldenMorningStartUtc = ...; w.goldenEveningEndUtc = ...; }
else if (hGoldenUpper >= 0) { /* 退化到日界 */ }

if (hBlueLower >= 0) {
  w.blueMorningEndUtc = noonUtc - hGoldenLower * 240000;   // ← hGoldenLower 可能是 -1
  w.blueEveningStartUtc = noonUtc + hGoldenLower * 240000; // ← 同上
}
```

**根因**：`hourAngleForAltitude()` 用 −1 表示无解，但调用方只判断了 `hBlueLower >= 0`，
没有校验同一窗口的另一端 `hGoldenLower`。当太阳全天高于 −4°（高纬夏季）时 `hGoldenLower = −1`，
蓝调窗口的「内侧端点」被算成 `noonUtc ± (−1) * 4min`，即正午前后 4 分钟的伪窗口；
同时黄金窗口会出现「起点有值、终点为 −1」的半初始化状态，被界面渲染成无效时段。

**可复现证据**：
- `golden_window_exists_in_polar_night`（特罗姆瑟冬至）修复前失败：`goldenMorningStart` 有值而 `goldenMorningEnd = -1`，顺序断言失败。

## 2. 修复方式

### 2.1 新增阈值状态：区分三种情形

```ts
export enum ThresholdState { CROSSING = 0, ALWAYS_ABOVE = 1, ALWAYS_BELOW = 2 }

static thresholdState(latDeg, declDeg, altitudeDeg): ThresholdState {
  const h = SolarCalc.hourAngleForAltitude(latDeg, declDeg, altitudeDeg);
  if (h >= 0) return ThresholdState.CROSSING;              // 有穿越
  const noonAltitude = 90 - Math.abs(latDeg - declDeg);    // 当日最大高度
  return noonAltitude > altitudeDeg ? ThresholdState.ALWAYS_ABOVE : ThresholdState.ALWAYS_BELOW;
}
```

无穿越时用「当日最大高度是否高于阈值」来判定在上还是在下——因为无穿越意味着全天在同一侧，
正午是最大值，比较一次即可，不再用单一 `-1` 混淆两种原因。

### 2.2 `events()`：四组阈值各自独立判定

- 删除日出无解时的提前返回。
- 日出/民用/航海/天文分别判断 `state === CROSSING` 才写入时间；无穿越时记录 `sunState/civilState/nauticalState/astronomicalState`。
- `polarState` 改为由 `sunState` 推导（`ALWAYS_ABOVE → 1`、`ALWAYS_BELOW → 2`），语义与之前一致（有穿越时为 0）。

### 2.3 `lightWindows()`：不可达阈值不再参与端点计算

- 黄金时段：
  - `goldenUpper` 全天高于 → 太阳从不低于 +6°，黄金带不存在 → 整组窗口不出（保持 −1）。
  - `goldenLower` 全天低于 → 太阳从不升到 −4°，黄金带不存在 → 整组窗口不出。
  - 否则按状态取端点：可穿越的阈值用穿越时刻；`goldenLower` 全天高于时起点取当日零点，
    `goldenUpper` 全天低于时终点取正午（把窗口延续到正午/午后，而不是留半初始化状态）。
  - 写入前校验 `start < end`，不成立则保持 −1。
- 蓝调时段：要求 `blueLower` **与** `goldenLower` 都存在穿越才构成区间；
  极昼（全天高于 −6°）或深极夜（全天低于 −6°）一律不产出蓝调窗口。

## 3. 兼容性核对（是否影响页面）

所有页面对事件的读取面（`grep` 全量统计）：

| 字段 | 读取次数 | 处理方式 |
|---|---|---|
| `sunriseUtc` / `sunsetUtc` | 8 / 8 | `< 0` 显示「无」 |
| `polarState` | 5 | 1→极昼文案、2→极夜文案、0→正常 |
| `solarNoonUtc` | 2 | 直接格式化 |
| `civilDuskUtc` | 2 | `< 0` 显示「无」 |
| `noonAltitudeDeg` | 1 | 数值展示 |

- 新增字段（`sunState` 等）是**纯增量**，没有页面读取，也没有页面依赖「无日出 ⇒ 无曙暮光」。
- 既有字段的取值语义未变：不可达仍为 −1，`polarState` 的 1/2 含义未变。
- 修复带来的可见变化是**正确的**：极夜的曙暮光与黄金/蓝调现在会显示真实时刻，而不是「无」。
- 未改动 UI 代码、数据库 schema、Bundle Name 与第三方依赖；仅新增 1 个测试文件与 1 处测试注册。

## 4. 新增测试（8 条，参考值独立于生产算法）

文件：`entry/src/test/SolarEvents.test.ets`（已注册到 `List.test.ets`）。

| 用例 | 期望来源 | 断言要点 |
|---|---|---|
| `polar_night_still_has_twilight` | **外部参考**：`api.sunrise-sunset.org` 原始响应（`tools/solar-check/raw.txt`，tromso_winter） | 无日出日落；民用 08:31:12–12:53:13、航海 06:46:45–14:37:41、天文 05:28:24–15:56:01（±3 min） |
| `polar_day_has_no_events_at_any_threshold` | 外部参考（tromso_summer 全为哨兵值） | 四组事件全为 −1，`polarState = 1` |
| `arctic_circle_critical_latitudes` | 几何关系：最小高度 ≈ δ+φ−90 | 65°N 有日出；66.6°N 无日出且民用曙暮光也不存在 |
| `southern_high_latitude_polar_night_with_twilight` | 几何关系：正午高度 ≈ 90−\|φ−δ\| = −3.44° | 南纬 70° 无日出但有民用曙暮光 |
| `golden_window_absent_when_sun_always_above_upper_threshold` | 几何关系：75°N 夏至最小高度 ≈ +8.44° > +6° | 黄金窗口整组为 −1 |
| `no_blue_window_when_sun_never_below_minus6` | 几何关系：61.5°N 夏至最小高度 ≈ −5.06° | 蓝调整组为 −1，黄金窗口仍存在且有序 |
| `golden_window_exists_in_polar_night` | 几何关系：正午 −3.09° 高于 −4° | 黄金/蓝调窗口存在且 `start < end` |
| `shanghai_normal_day_windows_ordered_and_bounded` | 常规日 | 晨昏顺序正确，窗口落在本地日区间内 |

参考值的独立性说明：`polar_*` 两条直接使用外部 API 的 UTC 时刻常量；其余用「最小/正午高度」这一几何事实构造期望，
不复制 `SolarCalc` 内部公式来生成期望值。

## 5. 修复前后结果

```text
# 修复前（先写测试）
Tests run: 31, Failure: 3, Error: 0, Pass: 28
失败：polar_night_still_has_twilight
      southern_high_latitude_polar_night_with_twilight
      golden_window_exists_in_polar_night

# 修复后
> hvigor BUILD SUCCESSFUL in 8 s 748 ms
Tests run: 31, Failure: 0, Error: 0, Pass: 31, Ignore: 0
```

原有 23 条测试全部保持通过（未放宽任何既有断言）。

## 6. 外部参考对照

```text
$ node tools/solar-check/check.mjs
最大误差 27.4s，容差 120s，失败项 0
物理不变量 9/9 通过（含「特罗姆瑟冬至无日出」「特罗姆瑟夏至无日落」）
```

12 组用例覆盖上海（夏/冬/春分）、悉尼、特罗姆瑟（极昼/极夜）、纽约（DST 结束、均时差极值）、
加德满都（非整点时区）、乌斯怀亚、跨日期线 ±179° 与萨摩亚。

## 7. 构建

```text
$ hvigorw assembleHap --mode module -p product=default -p buildMode=debug --no-daemon
> hvigor BUILD SUCCESSFUL in 13 s 579 ms
entry/build/default/outputs/default/entry-default-signed.hap   2,055,083 bytes
```

## 8. 性能影响

`events()`：极夜/极昼日过去在计算 1 个时角后就返回，现在固定计算 4 组时角（每组一次 acos + 一次 cos 比较），
开销为常数级三角函数，单次调用仍在微秒量级；`lightWindows()` 最多 3 次状态判定 + 2–4 次时角计算，
与原实现同量级。日历页一次渲染 28–31 天、每天各调用一次，实测构建与页面加载无可感知变化（未做基准压测）。

## 9. 尚未解决的数值边界（交后续子阶段）

1. `lightWindows()` 仍以「24 小时本地日」为前提（`dayStart + 86400000`），夏令时切换日的本地日长度不是 24 小时 —— 属 **2B** 范围。
2. 日出阈值固定为几何高度 −0.833°（上边缘 + 标准折射），未支持海拔俯角修正与自定义折射。
3. `thresholdState()` 在 \|lat\| 接近 90° 时 `cos(lat) → 0`，浮点误差会放大；极点本身未纳入测试。
4. 测试容差取 ±3 分钟（外部参考声明 ±30 s，本算法复算残差约 30 s 内）。

---

# 补充修复（复审后追加）：高纬度蓝调窗口误判

> 复审指出的建模错误成立。上一版把「蓝调需要 −6° 与 −4° 都发生穿越」当成了**必要条件**，
> 这是错的：蓝调带是 `[-6°, -4°)`，只要太阳落在带内就存在蓝调，并不要求两端都穿越。

## S1. 反例

| 反例 | 坐标/日期 | 关键数值 | 上一版行为 | 正确行为 |
|---|---|---|---|---|
| A | 72°N, 18.9553°E, 2026-12-21 | 正午高度 ≈ −5.44°，穿越 −6° 但到不了 −4° | `goldenLower` 未穿越 → 整组蓝调返回 −1 | 正午前后存在蓝调，窗口由 −6° 两次穿越界定 |
| B | 61.5°N, 18.9553°E, 2026-06-21 | 午夜最低 ≈ −5.06°，不低于 −6° 但会落到 −4° 以下 | `blueLower` 未穿越 → 整组蓝调返回 −1 | 午夜前后存在蓝调，窗口贴着当地日界 |

反例 B 还暴露了一个更严重的问题：上一版新增的测试 `no_blue_window_when_sun_never_below_minus6`
把这个错误行为写成了预期结果。**原断言错在前提**：它把「太阳不穿越 −6°」等同于「太阳不进入 [−6,−4) 带」，
而实际上不穿越 −6° 恰恰意味着太阳始终高于 −6°，只要它还会落到 −4° 以下，就必然在带内停留一段时间。
该用例已改名为 `blue_window_exists_near_midnight_when_sun_stays_above_minus6`，断言改为「蓝调必须存在」。

## S2. 修正后的建模

把「光线窗口」当作高度带求解：给定本地日区间，求 `{t | lower ≤ alt(t) < upper}`，
按太阳正午切成「晨/夕」两段。新增私有 `bandWindows()`，按两个边界的状态组合决定结果：

| 下界状态 | 上界状态 | 结果 |
|---|---|---|
| 有穿越 | 有穿越 | 常规两段：`[下界上升, 上界上升)`、`[上界下降, 下界下降)` |
| 有穿越 | 全天低于（到不了上界） | 上界不约束，两段在正午相接（如反例 A） |
| 全天高于 | 有穿越 | 带贴着零点，两段由日界裁切（如反例 B） |
| 全天高于 | 全天低于 | 太阳全天在带内 → 整日属于该带（几何上罕见，公式自洽） |
| 全天低于（到不了下界） | 任意 | 带不存在 |
| 任意 | 全天高于（始终高于上界） | 带不存在 |

统一约束：端点裁切到 `[dayStart, dayEnd)`；`start < end` 不成立时该段判为不存在（不输出颠倒窗口）。
黄金与蓝调用同一套逻辑，因此黄金也没有残留的边界遗漏（75°N 夏至两者皆无、特罗姆瑟冬至两者皆有，均有用例）。

## S3. 为 2B 预留真实本地日边界

`events()` 与 `lightWindows()` 增加可选参数 `dayEndLocalUtc`（默认 −1 = 按 24 小时），
内部不再写死 `+86400000`：日长取 `dayEnd − dayStart`，正午夹取与窗口裁切都使用该区间。
现有 4 处 `events()`、4 处 `lightWindows()` 调用点**不需要改**，2B 接入 DST 真实边界时只需多传一个参数。

新增用例 `accepts_real_local_day_length_not_assumed_24h`：用纽约 2026-03-08（本地日 23 小时）
验证事件与窗口都被裁切在该区间内。

## S4. 表示能力说明（兼容性最小）

`LightWindow` 仍是四字段（晨起/晨止/夕起/夕止），足以表达本日的至多两段窗口：

- 连续带（只有下界穿越）在太阳正午处切成相邻两段，视觉上无缝；
- 跨当地午夜的带（只有上界穿越）按日界裁切，跨日部分不重复计入本日；
- 未新增字段、未改数据库、未改 UI 与 Bundle Name。

## S5. 修复前后结果

```text
# 修复前（先写失败测试）
Tests run: 32, Failure: 2, Error: 0, Pass: 30
失败：blue_window_exists_near_midnight_when_sun_stays_above_minus6
      blue_window_exists_in_polar_night_when_minus4_never_reached

# 修复后
> hvigor BUILD SUCCESSFUL in 8 s 448 ms
Tests run: 33, Failure: 0, Error: 0, Pass: 33, Ignore: 0

# 外部参考对照
node tools/solar-check/check.mjs → 最大误差 27.4s，失败 0，不变量 9/9

# 构建
> hvigor BUILD SUCCESSFUL in 13 s 791 ms
entry-default-signed.hap  2,045,833 bytes
```

新增/修改的用例：

| 用例 | 验证点 |
|---|---|
| `blue_window_exists_near_midnight_when_sun_stays_above_minus6` | 反例 B：蓝调存在、贴日界、代表时刻在带内、升过 −4° 后在带外 |
| `blue_window_exists_in_polar_night_when_minus4_never_reached` | 反例 A：蓝调存在而黄金不存在；正午在带内、午夜在带外 |
| `shanghai_normal_day_windows_ordered_and_bounded`（扩充） | 黄金/蓝调中点均在各自带内；黄金晨窗开始前 5 min 低于 −4°、结束后 5 min 不低于 +6° |
| `accepts_real_local_day_length_not_assumed_24h` | 23 小时本地日：事件与窗口都被裁切在 `[dayStart, dayEnd)` |

## S6. 剩余限制

1. `bandWindows()` 以「太阳高度关于正午对称」为前提（基于赤纬/均时差在一天内近似不变）；极区跨日期的快速变赤纬情形仍属近似。
2. 本地日边界仍由调用方提供，2B 之前默认 24 小时；2A 只保证接口可用与被裁切。
3. 连续带在正午切分属于表示法约定，不代表物理上存在两段。

