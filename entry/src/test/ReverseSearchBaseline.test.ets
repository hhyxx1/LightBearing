import { describe, it, expect } from '@ohos/hypium';
import { ReverseSearch, DayRange } from '../main/ets/services/ReverseSearch';
import { SolarCalc, LightThresholds, SunPosition } from '../main/ets/services/SolarCalc';
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

export default function reverseSearchBaselineTest() {
  describe('ReverseSearchBaseline', () => {
    it('defect_short_window_between_coarse_samples_is_missed', 0, () => {
      // 缺陷 A（漏报）：真实有效窗口只有几十秒，且落在两个五分钟采样点之间。
      // 复现：目标取自 上海 2026-10-30 本地日 + 2.5 分钟（不在 5 分钟格点上），容差 0.05°。
      // 参考结果（1 秒扫描）：窗口约 [t0-16s, t0+16s]，全程有效。
      // 旧实现：t0±150s 的采样点均超出容差 → 不进入细化 → 返回空。
      const t0: number = SH_START + 2.5 * MIN;
      const goal = goalFromInstant(SH_LAT, SH_LON, t0, 0.05, 0.05);
      // 参考扫描：t0 本身有效、两侧 150 秒的采样点无效
      expect(refInTolerance(goal, t0)).assertTrue();
      expect(refInTolerance(goal, t0 - 2.5 * MIN)).assertFalse();
      expect(refInTolerance(goal, t0 + 2.5 * MIN)).assertFalse();
      // 生产实现返回空 —— 这就是漏报
      const found: Candidate[] = ReverseSearch.searchInRanges(goal, LightThresholds.defaults(),
        [DayRange.of(SH_START, SH_END)]);
      expect(found.length).assertEqual(0);
    });

    it('defect_wide_tolerance_produces_duplicate_candidates_for_one_window', 0, () => {
      // 缺陷 C（重复候选）：容差放宽后有效窗口很长，粗扫命中后每次跳 10 分钟，
      // 相邻两次细化的最优点相隔 > 10 分钟，于是 10 分钟合并规则不再生效，
      // 同一个连续窗口被切成多个候选。
      let dupCases = 0;
      let sample = '';
      for (let k = 0; k < 48; k++) {
        const t0: number = SH_START + k * 30 * MIN + 2.5 * MIN;
        const goal = goalFromInstant(SH_LAT, SH_LON, t0, 6, 6);
        const found: Candidate[] = ReverseSearch.searchInRanges(goal, LightThresholds.defaults(),
          [DayRange.of(SH_START, SH_END)]);
        for (let i = 1; i < found.length; i++) {
          const gap = found[i].utcMs - found[i - 1].utcMs;
          if (gap <= 0 || gap <= 10 * MIN) {
            continue;
          }
          // 两点之间逐 10 秒抽样：若持续有效，说明它们属于同一个连续窗口
          let continuous = true;
          const step = 10 * 1000;
          for (let t = found[i - 1].utcMs + step; t < found[i].utcMs; t += step) {
            if (!refInTolerance(goal, t)) {
              continuous = false;
              break;
            }
          }
          if (continuous) {
            dupCases++;
            if (sample.length === 0) {
              sample = `k=${k} gap=${Math.round(gap / MIN)}min`;
            }
            break;
          }
        }
      }
      expect(dupCases > 0).assertTrue();
      expect(sample.length > 0).assertTrue();
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
  });
}
