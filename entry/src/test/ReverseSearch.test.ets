import { describe, it, expect } from '@ohos/hypium';
import { DayRange, ReverseSearch, SearchPlan } from '../main/ets/services/ReverseSearch';
import { SolarCalc, LightThresholds, SunPosition } from '../main/ets/services/SolarCalc';
import { SearchGoal, Candidate } from '../main/ets/model/Models';
import { DayKind, LocalDayBounds } from '../main/ets/services/LocalTimeResolver';

/** 构造一个指定状态的日界对象 */
function boundsOf(kind: number, valid: boolean): LocalDayBounds {
  const b = new LocalDayBounds();
  b.kind = kind;
  b.valid = valid;
  b.startUtc = valid ? 1735689600000 : -1;
  b.endUtc = valid ? 1735776000000 : -1;
  return b;
}

/** 用某已知时刻的太阳位置构造目标 */
function goalAt(lat: number, lon: number, instantUtc: number, tolerance: number): SearchGoal {
  const known: SunPosition = SolarCalc.position(instantUtc, lat, lon);
  const goal = new SearchGoal();
  goal.latWgs84 = lat;
  goal.lonWgs84 = lon;
  goal.azimuthTarget = known.azimuthDeg;
  goal.altitudeTarget = known.altitudeDeg;
  goal.azTolerance = tolerance;
  goal.altTolerance = tolerance;
  goal.maxResults = 10;
  return goal;
}

/**
 * 反向寻光算法测试：核心验收点是「结果代回太阳位置公式后仍然满足容差」。
 */
export default function reverseSearchTest() {
  describe('ReverseSearch', () => {
    it('finds_window_matching_target_and_revalidates', 0, () => {
      const lat = 31.2304;
      const lon = 121.4737;
      const dayStart = Date.UTC(2026, 9, 29, 16, 0, 0); // 上海 10/30 00:00
      // 取一个已知时刻的太阳位置作为目标
      const known: SunPosition = SolarCalc.position(dayStart + 16 * 3600000.0, lat, lon);

      const goal = new SearchGoal();
      goal.latWgs84 = lat;
      goal.lonWgs84 = lon;
      goal.azimuthTarget = known.azimuthDeg;
      goal.altitudeTarget = known.altitudeDeg;
      goal.azTolerance = 2.0;
      goal.altTolerance = 2.0;
      goal.maxResults = 10;

      const days: number[] = [dayStart];
      const found: Candidate[] = ReverseSearch.search(goal, LightThresholds.defaults(), days);
      expect(found.length > 0).assertTrue();

      // 把最优结果代回公式复算，误差必须落在容差内
      const best = found[0];
      const recheck: SunPosition = SolarCalc.position(best.utcMs, lat, lon);
      const azErr = SolarCalc.angularDistance(recheck.azimuthDeg, goal.azimuthTarget);
      const altErr = Math.abs(recheck.altitudeDeg - goal.altitudeTarget);
      expect(azErr <= goal.azTolerance + 0.001).assertTrue();
      expect(altErr <= goal.altTolerance + 0.001).assertTrue();
      // 候选自带误差应与复算一致
      expect(Math.abs(best.azError - azErr) < 0.01).assertTrue();
      expect(Math.abs(best.altError - altErr) < 0.01).assertTrue();
    });

    it('returns_empty_for_impossible_target', 0, () => {
      const goal = new SearchGoal();
      goal.latWgs84 = 31.2304;
      goal.lonWgs84 = 121.4737;
      // 上海永远不可能出现 89° 高度角（正午最高约 82°）
      goal.azimuthTarget = 180;
      goal.altitudeTarget = 89;
      goal.azTolerance = 1;
      goal.altTolerance = 1;
      const days: number[] = [Date.UTC(2026, 9, 29, 16, 0, 0)];
      const found = ReverseSearch.search(goal, LightThresholds.defaults(), days);
      expect(found.length).assertEqual(0);
    });

    it('daylight_filter_removes_night_results', 0, () => {
      const goal = new SearchGoal();
      goal.latWgs84 = 31.2304;
      goal.lonWgs84 = 121.4737;
      // 夜间目标（-20°）在开启白昼过滤时必须被剔除
      goal.azimuthTarget = 0;
      goal.altitudeTarget = -20;
      goal.azTolerance = 5;
      goal.altTolerance = 5;
      goal.daylightOnly = true;
      const days: number[] = [Date.UTC(2026, 9, 29, 16, 0, 0)];
      const found = ReverseSearch.search(goal, LightThresholds.defaults(), days);
      for (const c of found) {
        const pos = SolarCalc.position(c.utcMs, goal.latWgs84, goal.lonWgs84);
        expect(pos.altitudeDeg > -0.833).assertTrue();
      }
    });

    it('respects_max_results', 0, () => {
      const goal = new SearchGoal();
      goal.latWgs84 = 31.2304;
      goal.lonWgs84 = 121.4737;
      goal.azimuthTarget = 180;
      goal.altitudeTarget = 30;
      goal.azTolerance = 30;
      goal.altTolerance = 30;
      goal.maxResults = 3;
      const days: number[] = [];
      for (let i = 0; i < 5; i++) {
        days.push(Date.UTC(2026, 9, 29 + i, 16, 0, 0));
      }
      const found = ReverseSearch.search(goal, LightThresholds.defaults(), days);
      expect(found.length <= 3).assertTrue();
    });

    it('results_sorted_by_total_error', 0, () => {
      const goal = new SearchGoal();
      goal.latWgs84 = 31.2304;
      goal.lonWgs84 = 121.4737;
      goal.azimuthTarget = 250;
      goal.altitudeTarget = 15;
      goal.azTolerance = 20;
      goal.altTolerance = 20;
      goal.maxResults = 20;
      const days: number[] = [];
      for (let i = 0; i < 7; i++) {
        days.push(Date.UTC(2026, 9, 29 + i, 16, 0, 0));
      }
      const found = ReverseSearch.search(goal, LightThresholds.defaults(), days);
      for (let i = 1; i < found.length; i++) {
        const prev = found[i - 1].azError + found[i - 1].altError;
        const cur = found[i].azError + found[i].altError;
        expect(prev <= cur + 0.0001).assertTrue();
      }
    });

    it('range_search_respects_23h_bounds', 0, () => {
      // 纽约 2026-03-08 真实本地日：05:00Z → 次日 04:00Z（23 小时）
      const lat = 40.7128;
      const lon = -74.006;
      const start = Date.UTC(2026, 2, 8, 5, 0, 0);
      const end = Date.UTC(2026, 2, 9, 4, 0, 0);
      const goal = goalAt(lat, lon, start + 10 * 3600000.0, 2.0);
      const found: Candidate[] = ReverseSearch.searchInRanges(goal, LightThresholds.defaults(),
        [DayRange.of(start, end)]);
      expect(found.length > 0).assertTrue();
      for (const c of found) {
        expect(c.utcMs >= start).assertTrue();
        expect(c.utcMs < end).assertTrue();
      }
    });

    it('range_search_does_not_scan_next_local_day', 0, () => {
      // 唯一匹配时刻落在 23h 区间结束之后 25 分钟：区间内必须搜不到，
      // 把区间延长到 25 小时后才能命中，且命中的时刻仍在区间内。
      const lat = 40.7128;
      const lon = -74.006;
      const start = Date.UTC(2026, 2, 8, 5, 0, 0);
      const end23 = start + 23 * 3600000.0;
      const matchAt = end23 + 25 * 60000.0;
      const goal = goalAt(lat, lon, matchAt, 0.5);

      const inside = ReverseSearch.searchInRanges(goal, LightThresholds.defaults(),
        [DayRange.of(start, end23)]);
      expect(inside.length).assertEqual(0);

      const widerEnd = start + 25 * 3600000.0;
      const wider = ReverseSearch.searchInRanges(goal, LightThresholds.defaults(),
        [DayRange.of(start, widerEnd)]);
      expect(wider.length > 0).assertTrue();
      for (const c of wider) {
        expect(c.utcMs >= start).assertTrue();
        expect(c.utcMs < widerEnd).assertTrue();
      }
    });

    it('range_search_25h_covers_last_hour', 0, () => {
      // 纽约 2026-11-01 真实本地日：04:00Z → 次日 05:00Z（25 小时）
      const lat = 40.7128;
      const lon = -74.006;
      const start = Date.UTC(2026, 10, 1, 4, 0, 0);
      const end = Date.UTC(2026, 10, 2, 5, 0, 0);
      expect(end - start).assertEqual(25 * 3600000.0);
      // 目标时刻在「最后半小时」——旧实现按 24 小时扫描会漏掉这一段
      const goal = goalAt(lat, lon, end - 20 * 60000.0, 1.0);
      const found = ReverseSearch.searchInRanges(goal, LightThresholds.defaults(),
        [DayRange.of(start, end)]);
      expect(found.length > 0).assertTrue();
      for (const c of found) {
        expect(c.utcMs >= start).assertTrue();
        expect(c.utcMs < end).assertTrue();
      }
    });

    it('search_plan_distinguishes_skipped_and_unavailable', 0, () => {
      // 全部有效
      const allValid = SearchPlan.plan([boundsOf(DayKind.NORMAL, true), boundsOf(DayKind.NORMAL, true)]);
      expect(allValid.ranges.length).assertEqual(2);
      expect(allValid.requestedDays).assertEqual(2);
      expect(allValid.skippedDays).assertEqual(0);
      expect(allValid.errorText.length).assertEqual(0);

      // 中间夹真正被跳过的日期：可跳过并计数，不算错误
      const withSkipped = SearchPlan.plan([boundsOf(DayKind.NORMAL, true), boundsOf(DayKind.SKIPPED, false),
        boundsOf(DayKind.NORMAL, true)]);
      expect(withSkipped.ranges.length).assertEqual(2);
      expect(withSkipped.skippedDays).assertEqual(1);
      expect(withSkipped.errorText.length).assertEqual(0);

      // 时区数据不可用：必须报错，不能静默跳过
      const withUnavailable = SearchPlan.plan([boundsOf(DayKind.NORMAL, true), boundsOf(DayKind.UNAVAILABLE, false)]);
      expect(withUnavailable.unavailableDays).assertEqual(1);
      expect(withUnavailable.errorText.length > 0).assertTrue();

      // 日期非法：同样报错
      const withInvalid = SearchPlan.plan([boundsOf(DayKind.INVALID, false)]);
      expect(withInvalid.invalidDays).assertEqual(1);
      expect(withInvalid.errorText.length > 0).assertTrue();

      // 全部被跳过：没有可搜索日，报错而不是「成功 0 条」
      const allSkipped = SearchPlan.plan([boundsOf(DayKind.SKIPPED, false), boundsOf(DayKind.SKIPPED, false)]);
      expect(allSkipped.ranges.length).assertEqual(0);
      expect(allSkipped.skippedDays).assertEqual(2);
      expect(allSkipped.errorText.length > 0).assertTrue();

      // 空输入同样报错
      const empty = SearchPlan.plan([]);
      expect(empty.requestedDays).assertEqual(0);
      expect(empty.errorText.length > 0).assertTrue();
    });

    it('range_search_skips_only_really_skipped_days', 0, () => {
      // 规划出的区间数量决定进度分母：跳过日不占进度
      const plan = SearchPlan.plan([boundsOf(DayKind.NORMAL, true), boundsOf(DayKind.SKIPPED, false),
        boundsOf(DayKind.NORMAL, true), boundsOf(DayKind.SKIPPED, false)]);
      expect(plan.requestedDays).assertEqual(4);
      expect(plan.ranges.length).assertEqual(2);
      const goal = goalAt(31.2304, 121.4737, plan.ranges[0].startUtc + 6 * 3600000.0, 2.0);
      const found: Candidate[] = ReverseSearch.searchInRanges(goal, LightThresholds.defaults(), plan.ranges);
      for (const c of found) {
        const inAny = plan.ranges.some((r: DayRange) => c.utcMs >= r.startUtc && c.utcMs < r.endUtc);
        expect(inAny).assertTrue();
      }
    });

    it('range_search_half_hour_days', 0, () => {
      // 豪勋爵岛式区间：23.5 小时与 24.5 小时都必须按真实长度搜索
      const lat = -31.55;
      const lon = 159.08;
      const shortStart = Date.UTC(2026, 9, 3, 13, 30, 0);
      const shortEnd = shortStart + 23.5 * 3600000.0;
      const shortGoal = goalAt(lat, lon, shortEnd - 20 * 60000.0, 1.0);
      const shortFound = ReverseSearch.searchInRanges(shortGoal, LightThresholds.defaults(),
        [DayRange.of(shortStart, shortEnd)]);
      expect(shortFound.length > 0).assertTrue();
      for (const c of shortFound) {
        expect(c.utcMs >= shortStart && c.utcMs < shortEnd).assertTrue();
      }

      const longStart = Date.UTC(2026, 3, 4, 13, 0, 0);
      const longEnd = longStart + 24.5 * 3600000.0;
      const longGoal = goalAt(lat, lon, longEnd - 20 * 60000.0, 1.0);
      const longFound = ReverseSearch.searchInRanges(longGoal, LightThresholds.defaults(),
        [DayRange.of(longStart, longEnd)]);
      expect(longFound.length > 0).assertTrue();
      for (const c of longFound) {
        expect(c.utcMs >= longStart && c.utcMs < longEnd).assertTrue();
      }
    });
  });
}
