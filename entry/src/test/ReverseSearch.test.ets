import { describe, it, expect } from '@ohos/hypium';
import { ReverseSearch } from '../main/ets/services/ReverseSearch';
import { SolarCalc, LightThresholds, SunPosition } from '../main/ets/services/SolarCalc';
import { SearchGoal, Candidate } from '../main/ets/model/Models';

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
  });
}
