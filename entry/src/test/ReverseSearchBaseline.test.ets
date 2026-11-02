import { describe, it, expect } from '@ohos/hypium';
import { ReverseSearch, DayRange } from '../main/ets/services/ReverseSearch';
import { SolarCalc, LightThresholds, SunPosition } from '../main/ets/services/SolarCalc';
import { ReverseSearchKernel, SolarPositionEvaluator } from '../main/ets/services/ReverseSearchKernel';
import { ShootWindow, KernelStats } from '../main/ets/model/ShootWindow';
import { SearchGoal, Candidate } from '../main/ets/model/Models';

/**
 * 2C-1 反向寻光基线：把审计发现固化为「绿色」回归用例。
 *
 * 这些用例断言的是**当前实现的真实行为**（其中多条是已知缺陷），
 * 目的是让后续 2C-2 修改算法时能立刻看到行为变化，而不是把缺陷当成“通过”。
 * 每条缺陷在注释里写明：现象、最小复现输入、独立参考结果。
 */

const MIN = 60000.0;
const HOUR = 3600000.0;

/** 上海 2026-10-30 本地日 */
const SH_START: number = Date.UTC(2026, 9, 29, 16, 0, 0);
const SH_END: number = Date.UTC(2026, 9, 30, 16, 0, 0);
const SH_LAT: number = 31.2304;
const SH_LON: number = 121.4737;

/** 纽约 2026-03-08（23h）与 2026-11-01（25h） */
const NY_SPRING: number = Date.UTC(2026, 2, 8, 5, 0, 0);
const NY_SPRING_END: number = Date.UTC(2026, 2, 9, 4, 0, 0);
const NY_FALL: number = Date.UTC(2026, 10, 1, 4, 0, 0);
const NY_FALL_END: number = Date.UTC(2026, 10, 2, 5, 0, 0);

/** 1969-12-31 上海本地日（负时间戳） */
const PRE_START: number = Date.UTC(1969, 11, 30, 16, 0, 0);
const PRE_END: number = Date.UTC(1969, 11, 31, 16, 0, 0);

function goalFromInstant(lat: number, lon: number, utcMs: number, azTol: number, altTol: number,
  daylightOnly: boolean = false): SearchGoal {
  const p: SunPosition = SolarCalc.position(utcMs, lat, lon);
  const g = new SearchGoal();
  g.latWgs84 = lat;
  g.lonWgs84 = lon;
  g.azimuthTarget = p.azimuthDeg;
  g.altitudeTarget = p.altitudeDeg;
  g.azTolerance = azTol;
  g.altTolerance = altTol;
  g.daylightOnly = daylightOnly;
  g.maxResults = 30;
  return g;
}

/** 独立参考判定：两个容差分别检查（不使用搜索器内部逻辑） */
function refInTolerance(goal: SearchGoal, utcMs: number): boolean {
  const p: SunPosition = SolarCalc.position(utcMs, goal.latWgs84, goal.lonWgs84);
  const azErr = SolarCalc.angularDistance(p.azimuthDeg, goal.azimuthTarget);
  const altErr = Math.abs(p.altitudeDeg - goal.altitudeTarget);
  return azErr <= goal.azTolerance && altErr <= goal.altTolerance;
}


/** 合成轨迹：高度为抛物线，方位恒定（用于验证极短窗口被发现） */
class ParabolaAltEvaluator implements SolarPositionEvaluator {
  private tBase: number = 0;

  constructor(tBase: number) {
    this.tBase = tBase;
  }

  positionAt(utcMs: number, latDeg: number, lonDeg: number): SunPosition {
    const p = new SunPosition();
    const u = (utcMs - this.tBase) / 1000;
    p.azimuthDeg = 200;
    p.altitudeDeg = 10 - u * u;
    return p;
  }
}

/** 合成轨迹：两个独立的有效凸瓣（间隔可调） */
class TwoLobesEvaluator implements SolarPositionEvaluator {
  private t1: number = 0;
  private t2: number = 0;

  constructor(t1: number, t2: number) {
    this.t1 = t1;
    this.t2 = t2;
  }

  positionAt(utcMs: number, latDeg: number, lonDeg: number): SunPosition {
    const p = new SunPosition();
    const d1 = Math.abs(utcMs - this.t1);
    const d2 = Math.abs(utcMs - this.t2);
    const d = Math.min(d1, d2) / 1000;
    p.azimuthDeg = 200;
    p.altitudeDeg = 10 - d * 0.01;
    return p;
  }
}

/** 合成轨迹：方位误差随时间增大、高度误差随时间减小（D2 的 trade-off 场景） */
class TradeoffEvaluator implements SolarPositionEvaluator {
  private tBase: number = 0;

  constructor(tBase: number) {
    this.tBase = tBase;
  }

  positionAt(utcMs: number, latDeg: number, lonDeg: number): SunPosition {
    const p = new SunPosition();
    const u = (utcMs - this.tBase) / 1000;
    p.azimuthDeg = 180 + 0.4 + 0.2 * (u / 60);
    p.altitudeDeg = 10 + 4.5 * (1 - u / 60);
    return p;
  }
}

export default function reverseSearchBaselineTest() {
  describe('ReverseSearchBaseline', () => {
    it('finds_32s_window_between_old_coarse_samples', 0, () => {
      // 2C-1 的漏报反例：窗口只有 32 秒且落在旧版两个 5 分钟采样点之间。
      // 旧实现返回空；新内核必须找到，且窗口必须真的包含目标瞬间。
      const t0: number = SH_START + 2.5 * MIN;
      const goal = goalFromInstant(SH_LAT, SH_LON, t0, 0.05, 0.05);
      const stats = new KernelStats();
      const windows: ShootWindow[] = ReverseSearch.searchWindowsInRanges(goal, LightThresholds.defaults(),
        [DayRange.of(SH_START, SH_END)], stats);
      expect(windows.length).assertEqual(1);
      const w = windows[0];
      expect(w.valid).assertTrue();
      expect(w.startUtc <= t0 && t0 < w.endUtc).assertTrue();
      // 窗口两端都必须是真实有效时刻（1 秒分辨率内的近似）
      expect(refInTolerance(goal, w.startUtc)).assertTrue();
      expect(refInTolerance(goal, w.bestUtc)).assertTrue();
      // 旧版会在 16:00:00 / 16:05:00 两个采样点上失败（这就是它漏报的原因）
      expect(refInTolerance(goal, t0 - 2.5 * MIN)).assertFalse();
      expect(refInTolerance(goal, t0 + 2.5 * MIN)).assertFalse();
      // 窗口长度应在几十秒量级，而不是被粗采样拉长
      expect(w.durationMs() <= 200 * 1000).assertTrue();
    });

    it('wide_tolerance_returns_one_window_not_duplicates', 0, () => {
      // 旧版在宽容差下会把同一连续窗口切成多条候选（10 分钟合并失效）。
      // 新内核按窗口身份去重：候选数必须等于窗口数。
      const t0: number = SH_START + 12 * HOUR;
      const goal = goalFromInstant(SH_LAT, SH_LON, t0, 6, 6);
      const stats = new KernelStats();
      const windows = ReverseSearch.searchWindowsInRanges(goal, LightThresholds.defaults(),
        [DayRange.of(SH_START, SH_END)], stats);
      const candidates: Candidate[] = ReverseSearch.searchInRanges(goal, LightThresholds.defaults(),
        [DayRange.of(SH_START, SH_END)]);
      expect(windows.length >= 1).assertTrue();
      expect(candidates.length).assertEqual(windows.length);
      // 每个候选的唯一来源窗口互不相同（窗口之间互不包含）
      for (let i = 0; i < windows.length; i++) {
        for (let j = i + 1; j < windows.length; j++) {
          const overlap = windows[i].startUtc < windows[j].endUtc && windows[j].startUtc < windows[i].endUtc;
          expect(overlap).assertFalse();
        }
      }
    });

    it('defect_cost_minimum_can_fall_outside_one_tolerance', 0, () => {
      // 缺陷 B（细化风险，算术证明）：细化最小化 azErr+altErr，但有效性要求两个容差分别成立。
      // 设 azTol=0.5、altTol=5：点 P(az=0.40, alt=4.50) 有效（cost 4.90），
      // 点 Q(az=0.60, alt=0.10) 无效（az 超容差）但 cost 仅 0.70。
      // 细化会选 Q，随后因 azErr>azTol 被整体丢弃 —— 原本有效的 P 也一起消失。
      const azTol = 0.5;
      const altTol = 5.0;
      const pCost = 0.40 + 4.50;
      const qCost = 0.60 + 0.10;
      const pValid = 0.40 <= azTol && 4.50 <= altTol;
      const qValid = 0.60 <= azTol && 0.10 <= altTol;
      expect(pValid).assertTrue();
      expect(qValid).assertFalse();
      expect(qCost < pCost).assertTrue();
      // 即：最小 cost 点无效，而有效点被丢弃 —— 生产代码在细化后直接 continue
      expect(qCost).assertEqual(0.7);
    });

    it('pre_epoch_search_returns_negative_valid_candidates', 0, () => {
      // 负时间戳：1969-12-31 上海本地日，搜索必须正常工作且结果都在区间内
      const t0: number = PRE_START + 12 * HOUR;
      const goal = goalFromInstant(SH_LAT, SH_LON, t0, 3, 3);
      const found: Candidate[] = ReverseSearch.searchInRanges(goal, LightThresholds.defaults(),
        [DayRange.of(PRE_START, PRE_END)]);
      expect(found.length > 0).assertTrue();
      for (const c of found) {
        expect(c.utcMs < 0).assertTrue();
        expect(c.utcMs >= PRE_START && c.utcMs < PRE_END).assertTrue();
        expect(refInTolerance(goal, c.utcMs)).assertTrue();
      }
    });

    it('candidates_stay_inside_23h_and_25h_ranges', 0, () => {
      const springGoal = goalFromInstant(40.7128, -74.006, NY_SPRING + 10 * HOUR, 3, 3);
      const spring = ReverseSearch.searchInRanges(springGoal, LightThresholds.defaults(),
        [DayRange.of(NY_SPRING, NY_SPRING_END)]);
      for (const c of spring) {
        expect(c.utcMs >= NY_SPRING && c.utcMs < NY_SPRING_END).assertTrue();
      }
      const fallGoal = goalFromInstant(40.7128, -74.006, NY_FALL + 10 * HOUR, 3, 3);
      const fall = ReverseSearch.searchInRanges(fallGoal, LightThresholds.defaults(),
        [DayRange.of(NY_FALL, NY_FALL_END)]);
      for (const c of fall) {
        expect(c.utcMs >= NY_FALL && c.utcMs < NY_FALL_END).assertTrue();
      }
    });

    it('never_returns_candidate_at_or_after_range_end', 0, () => {
      // 目标取自区间末尾前 30 秒：结果必须严格小于 endUtc（半开区间）
      const t0: number = SH_END - 30 * 1000;
      const goal = goalFromInstant(SH_LAT, SH_LON, t0, 0.05, 0.05);
      const found: Candidate[] = ReverseSearch.searchInRanges(goal, LightThresholds.defaults(),
        [DayRange.of(SH_START, SH_END)]);
      for (const c of found) {
        expect(c.utcMs < SH_END).assertTrue();
      }
    });

    it('invalid_inputs_yield_empty_result', 0, () => {
      const bad1 = goalFromInstant(SH_LAT, SH_LON, SH_START + 12 * HOUR, 3, 3);
      bad1.latWgs84 = NaN;
      expect(ReverseSearch.searchInRanges(bad1, LightThresholds.defaults(),
        [DayRange.of(SH_START, SH_END)]).length).assertEqual(0);
      const bad2 = goalFromInstant(SH_LAT, SH_LON, SH_START + 12 * HOUR, 3, 3);
      bad2.azTolerance = -1;
      expect(ReverseSearch.searchInRanges(bad2, LightThresholds.defaults(),
        [DayRange.of(SH_START, SH_END)]).length).assertEqual(0);
      const bad3 = goalFromInstant(SH_LAT, SH_LON, SH_START + 12 * HOUR, 3, 3);
      expect(ReverseSearch.searchInRanges(bad3, LightThresholds.defaults(),
        [DayRange.of(SH_START, SH_START)]).length).assertEqual(0);
    });

    it('daylight_filter_excludes_night_only', 0, () => {
      // 夜间目标：daylightOnly=true 时必须为空，false 时应有结果
      const nightT0: number = SH_START + 3 * HOUR;
      const night = goalFromInstant(SH_LAT, SH_LON, nightT0, 3, 3, false);
      const nightFiltered = goalFromInstant(SH_LAT, SH_LON, nightT0, 3, 3, true);
      expect(ReverseSearch.searchInRanges(night, LightThresholds.defaults(),
        [DayRange.of(SH_START, SH_END)]).length > 0).assertTrue();
      expect(ReverseSearch.searchInRanges(nightFiltered, LightThresholds.defaults(),
        [DayRange.of(SH_START, SH_END)]).length).assertEqual(0);
    });

    it('azimuth_wrap_at_north_is_handled', 0, () => {
      // 0°/360° 跨越：先确认角度差本身按环形计算（359.5 与 0.5 相差 1°，不是 359°）
      expect(SolarCalc.angularDistance(359.5, 0.5)).assertEqual(1);
      expect(SolarCalc.angularDistance(0.5, 359.5)).assertEqual(1);
      // 找一个方位角经过正北的时刻（1 分钟分辨率，避免 10 分钟采样漏掉 1° 窗口）
      let target = -1;
      for (let t = SH_START; t < SH_END; t += MIN) {
        const p: SunPosition = SolarCalc.position(t, SH_LAT, SH_LON);
        if (SolarCalc.angularDistance(p.azimuthDeg, 0) <= 0.5) {
          target = t;
          break;
        }
      }
      expect(target >= 0).assertTrue();
      const azAtTarget: number = SolarCalc.position(target, SH_LAT, SH_LON).azimuthDeg;
      // 无论记录值是 0.x 还是 359.x，与正北的环形距离都应 <= 0.5
      expect(SolarCalc.angularDistance(azAtTarget, 0) <= 0.5).assertTrue();
      // 用 3° 容差搜索：返回的每个候选都必须真的靠近正北（有效性优先于数量）
      const goal = goalFromInstant(SH_LAT, SH_LON, target, 3, 3);
      const found: Candidate[] = ReverseSearch.searchInRanges(goal, LightThresholds.defaults(),
        [DayRange.of(SH_START, SH_END)]);
      for (const c of found) {
        const p: SunPosition = SolarCalc.position(c.utcMs, SH_LAT, SH_LON);
        expect(SolarCalc.angularDistance(p.azimuthDeg, 0) <= 3).assertTrue();
      }
    });

    it('synthetic_5s_10s_20s_windows_are_found', 0, () => {
      // 合成轨迹：alt = 10 - (秒差)^2，方位恒定 → 有效窗口宽度由 altTol 精确决定
      const base = Date.UTC(2026, 9, 29, 18, 0, 0);
      for (const widthSec of [5, 10, 20]) {
        const half = widthSec / 2;
        ReverseSearchKernel.setEvaluator(new ParabolaAltEvaluator(base));
        try {
          const goal = new SearchGoal();
          goal.latWgs84 = 0;
          goal.lonWgs84 = 0;
          goal.azimuthTarget = 200;
          goal.altitudeTarget = 10;
          goal.azTolerance = 1;
          goal.altTolerance = half * half;
          goal.daylightOnly = false;
          goal.maxResults = 30;
          const stats = new KernelStats();
          const windows = ReverseSearch.searchWindowsInRanges(goal, LightThresholds.defaults(),
            [DayRange.of(base - 10 * MIN, base + 10 * MIN)], stats);
          expect(windows.length).assertEqual(1);
          const w = windows[0];
          expect(w.valid).assertTrue();
          // 1 秒分辨率下窗口宽度误差不超过 2 秒
          expect(Math.abs(w.durationMs() / 1000 - widthSec) <= 2).assertTrue();
          expect(w.startUtc <= base && base < w.endUtc).assertTrue();
        } finally {
          ReverseSearchKernel.setEvaluator(undefined);
        }
      }
    });

    it('synthetic_two_windows_10s_apart_stay_separate', 0, () => {
      // 两个独立凸瓣：各自 ±5 秒有效，中间 10 秒无效 → 必须返回两个窗口，不能合并
      const t1 = Date.UTC(2026, 9, 29, 18, 0, 0);
      const t2 = t1 + 20 * 1000;
      ReverseSearchKernel.setEvaluator(new TwoLobesEvaluator(t1, t2));
      try {
        const goal = new SearchGoal();
        goal.latWgs84 = 0;
        goal.lonWgs84 = 0;
        goal.azimuthTarget = 200;
        goal.altitudeTarget = 10;
        goal.azTolerance = 1;
        goal.altTolerance = 0.05;
        goal.daylightOnly = false;
        goal.maxResults = 30;
        const stats = new KernelStats();
        const windows = ReverseSearch.searchWindowsInRanges(goal, LightThresholds.defaults(),
          [DayRange.of(t1 - 10 * MIN, t2 + 10 * MIN)], stats);
        expect(windows.length).assertEqual(2);
        const gapMs = windows[1].startUtc - windows[0].endUtc;
        expect(gapMs >= 8000 && gapMs <= 12000).assertTrue();
        expect(windows[0].endUtc <= windows[1].startUtc).assertTrue();
      } finally {
        ReverseSearchKernel.setEvaluator(undefined);
      }
    });

    it('synthetic_tangent_hit_is_degenerate_window', 0, () => {
      // 只在一瞬间刚好等于目标（切点）：必须得到一个退化窗口，而不是零长度被丢弃
      const base = Date.UTC(2026, 9, 29, 18, 0, 0);
      ReverseSearchKernel.setEvaluator(new ParabolaAltEvaluator(base));
      try {
        const goal = new SearchGoal();
        goal.latWgs84 = 0;
        goal.lonWgs84 = 0;
        goal.azimuthTarget = 200;
        goal.altitudeTarget = 10;
        goal.azTolerance = 1;
        goal.altTolerance = 0;
        goal.daylightOnly = false;
        goal.maxResults = 30;
        const windows = ReverseSearch.searchWindowsInRanges(goal, LightThresholds.defaults(),
          [DayRange.of(base - 2 * MIN, base + 2 * MIN)], new KernelStats());
        expect(windows.length).assertEqual(1);
        expect(windows[0].degenerate).assertTrue();
        expect(windows[0].durationMs() <= 2000).assertTrue();
      } finally {
        ReverseSearchKernel.setEvaluator(undefined);
      }
    });

    it('synthetic_invalid_lower_cost_point_does_not_remove_valid_window', 0, () => {
      // D2：u=0 处 (azErr 0.40, altErr 4.50) 有效但 cost 4.90；
      // u=60 处 (azErr 0.60, altErr 0.10) 无效却 cost 0.70。
      // 新内核只在有效集合内部选最优点，因此窗口必须存在且最优点满足双容差。
      const tBase = Date.UTC(2026, 9, 29, 18, 0, 0);
      ReverseSearchKernel.setEvaluator(new TradeoffEvaluator(tBase));
      try {
        const goal = new SearchGoal();
        goal.latWgs84 = 0;
        goal.lonWgs84 = 0;
        goal.azimuthTarget = 180;
        goal.altitudeTarget = 10;
        goal.azTolerance = 0.5;
        goal.altTolerance = 5;
        goal.daylightOnly = false;
        goal.maxResults = 30;
        const windows = ReverseSearch.searchWindowsInRanges(goal, LightThresholds.defaults(),
          [DayRange.of(tBase - 60 * 1000, tBase + 120 * 1000)], new KernelStats());
        expect(windows.length >= 1).assertTrue();
        for (const w of windows) {
          // 最优点必须真的满足两个独立容差
          const azAtBest = Math.abs(Math.abs(w.bestAzimuth - 180));
          expect(azAtBest <= 0.5).assertTrue();
          expect(Math.abs(w.bestAltitude - 10) <= 5).assertTrue();
          // 且不能落在 u=60 那个「cost 更低但无效」的点上
          expect(Math.abs(w.bestUtc - (tBase + 60000)) > 1000).assertTrue();
        }
      } finally {
        ReverseSearchKernel.setEvaluator(undefined);
      }
    });
  });
}
