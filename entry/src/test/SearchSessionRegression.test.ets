import { describe, it, expect } from '@ohos/hypium';
import { ReverseSearch, DayRange, WindowSortMode } from '../main/ets/services/ReverseSearch';
import { SearchSession, SessionState } from '../main/ets/services/SearchSession';
import { SolarPositionEvaluator } from '../main/ets/services/ReverseSearchKernel';
import { ShootWindow, KernelStats } from '../main/ets/model/ShootWindow';
import { LightThresholds, SunPosition } from '../main/ets/services/SolarCalc';
import { SearchGoal } from '../main/ets/model/Models';

/**
 * 2C-3 验收补丁的回归用例。
 * 这些用例针对复审确认的缺陷：无命中区间不推进、合并边界跨过真实间隔、
 * 非有限太阳位置被当成「没有拍摄机会」、finalize 只检查 bestUtc 而不复验位置。
 */

const SECOND: number = 1000;
const T0: number = Date.UTC(2026, 9, 29, 20, 0, 0);

/** 永不满足：高度固定在 89°，与目标 10° 相差 79° */
class NeverValidEvaluator implements SolarPositionEvaluator {
  positionAt(utcMs: number, latDeg: number, lonDeg: number): SunPosition {
    const p = new SunPosition();
    p.azimuthDeg = 180;
    p.altitudeDeg = 89;
    return p;
  }
}

/** 只在 [fromUtc, toUtc) 内有效 */
class ValidInRangeEvaluator implements SolarPositionEvaluator {
  private fromUtc: number = 0;
  private toUtc: number = 0;

  constructor(fromUtc: number, toUtc: number) {
    this.fromUtc = fromUtc;
    this.toUtc = toUtc;
  }

  positionAt(utcMs: number, latDeg: number, lonDeg: number): SunPosition {
    const p = new SunPosition();
    p.azimuthDeg = 180;
    p.altitudeDeg = (utcMs >= this.fromUtc && utcMs < this.toUtc) ? 10 : 89;
    return p;
  }
}

/** 高度为 NaN：太阳位置不可用 */
class NaNEvaluator implements SolarPositionEvaluator {
  positionAt(utcMs: number, latDeg: number, lonDeg: number): SunPosition {
    const p = new SunPosition();
    p.azimuthDeg = NaN;
    p.altitudeDeg = NaN;
    return p;
  }
}

/** 恒定有效 */
class ValidEvaluator implements SolarPositionEvaluator {
  positionAt(utcMs: number, latDeg: number, lonDeg: number): SunPosition {
    const p = new SunPosition();
    p.azimuthDeg = 180;
    p.altitudeDeg = 10;
    return p;
  }
}

function goalOf(): SearchGoal {
  const g = new SearchGoal();
  g.latWgs84 = 31.2304;
  g.lonWgs84 = 121.4737;
  g.azimuthTarget = 180;
  g.altitudeTarget = 10;
  g.azTolerance = 1;
  g.altTolerance = 1;
  g.daylightOnly = false;
  g.maxResults = 30;
  return g;
}

function fakeWindow(start: number, end: number, best: number, azErr: number, altErr: number): ShootWindow {
  const w = new ShootWindow();
  w.startUtc = start;
  w.endUtc = end;
  w.bestUtc = best;
  w.bestAzimuth = 180;
  w.bestAltitude = 10;
  w.bestAzError = azErr;
  w.bestAltError = altErr;
  w.phase = 0;
  w.valid = true;
  return w;
}

export default function searchSessionRegressionTest() {
  describe('SearchSessionRegression', () => {
    it('single_range_without_hits_terminates', 0, () => {
      const session = new SearchSession(goalOf(), LightThresholds.defaults(),
        [DayRange.of(T0, T0 + 10 * SECOND)], new NeverValidEvaluator());
      for (let i = 0; i < 200 && !session.isFinished(); i++) {
        session.step(2);
      }
      expect(session.getState()).assertEqual(SessionState.DONE);
      expect(session.getWindows().length).assertEqual(0);
      expect(session.getProgressPercent()).assertEqual(100);
      expect(session.getRangeIndex()).assertEqual(1);
    });

    it('first_range_empty_then_second_range_has_hits', 0, () => {
      const a0 = T0;
      const a1 = T0 + 10 * SECOND;
      const b0 = a1;
      const b1 = b0 + 10 * SECOND;
      const session = new SearchSession(goalOf(), LightThresholds.defaults(),
        [DayRange.of(a0, a1), DayRange.of(b0, b1)], new ValidInRangeEvaluator(b0, b1));
      for (let i = 0; i < 400 && !session.isFinished(); i++) {
        session.step(2);
      }
      expect(session.getState()).assertEqual(SessionState.DONE);
      expect(session.getWindows().length).assertEqual(1);
      expect(session.getWindows()[0].startUtc).assertEqual(b0);
      expect(session.getRangeIndex()).assertEqual(2);
    });

    it('three_ranges_all_empty_terminate', 0, () => {
      const ranges: DayRange[] = [];
      for (let i = 0; i < 3; i++) {
        ranges.push(DayRange.of(T0 + i * 10 * SECOND, T0 + (i + 1) * 10 * SECOND));
      }
      const session = new SearchSession(goalOf(), LightThresholds.defaults(), ranges,
        new NeverValidEvaluator());
      for (let i = 0; i < 200 && !session.isFinished(); i++) {
        session.step(2);
      }
      expect(session.getState()).assertEqual(SessionState.DONE);
      expect(session.getWindows().length).assertEqual(0);
      expect(session.getRangeIndex()).assertEqual(3);
      expect(session.getProgressPercent()).assertEqual(100);
    });

    it('first_range_hit_then_empty_terminates', 0, () => {
      const a0 = T0;
      const a1 = T0 + 10 * SECOND;
      const b0 = a1;
      const b1 = b0 + 10 * SECOND;
      const session = new SearchSession(goalOf(), LightThresholds.defaults(),
        [DayRange.of(a0, a1), DayRange.of(b0, b1)], new ValidInRangeEvaluator(a0, a1));
      for (let i = 0; i < 400 && !session.isFinished(); i++) {
        session.step(2);
      }
      expect(session.getState()).assertEqual(SessionState.DONE);
      expect(session.getWindows().length).assertEqual(1);
      expect(session.getRangeIndex()).assertEqual(2);
    });

    it('many_empty_ranges_terminate_within_step_cap', 0, () => {
      const ranges: DayRange[] = [];
      for (let i = 0; i < 365; i++) {
        ranges.push(DayRange.of(T0 + i * 60 * SECOND, T0 + (i + 1) * 60 * SECOND));
      }
      const session = new SearchSession(goalOf(), LightThresholds.defaults(), ranges,
        new NeverValidEvaluator());
      let steps = 0;
      for (; steps < 400 && !session.isFinished(); steps++) {
        session.step(2);
      }
      expect(session.getState()).assertEqual(SessionState.DONE);
      expect(session.getWindows().length).assertEqual(0);
      expect(session.getRangeIndex()).assertEqual(365);
      expect(steps < 400).assertTrue();
    });

    it('merge_only_when_truly_touching', 0, () => {
      const goal = goalOf();
      const ranges: DayRange[] = [DayRange.of(T0 - 60 * SECOND, T0 + 120 * SECOND)];
      const touch: ShootWindow[] = [
        fakeWindow(T0, T0 + 10 * SECOND, T0 + SECOND, 0.1, 0.1),
        fakeWindow(T0 + 10 * SECOND, T0 + 20 * SECOND, T0 + 11 * SECOND, 0.1, 0.1)
      ];
      const touchOut = ReverseSearch.finalizeWindows(goal, LightThresholds.defaults(), touch,
        WindowSortMode.BEST, 30, new ValidEvaluator(), new KernelStats(), ranges);
      expect(touchOut.windows.length).assertEqual(1);

      const gap1ms: ShootWindow[] = [
        fakeWindow(T0, T0 + 10 * SECOND, T0 + SECOND, 0.1, 0.1),
        fakeWindow(T0 + 10 * SECOND + 1, T0 + 20 * SECOND, T0 + 11 * SECOND, 0.1, 0.1)
      ];
      const gap1msOut = ReverseSearch.finalizeWindows(goal, LightThresholds.defaults(), gap1ms,
        WindowSortMode.BEST, 30, new ValidEvaluator(), new KernelStats(), ranges);
      expect(gap1msOut.windows.length).assertEqual(2);

      const gap10ms: ShootWindow[] = [
        fakeWindow(T0, T0 + 10 * SECOND, T0 + SECOND, 0.1, 0.1),
        fakeWindow(T0 + 10 * SECOND + 10, T0 + 20 * SECOND, T0 + 11 * SECOND, 0.1, 0.1)
      ];
      const gap10msOut = ReverseSearch.finalizeWindows(goal, LightThresholds.defaults(), gap10ms,
        WindowSortMode.BEST, 30, new ValidEvaluator(), new KernelStats(), ranges);
      expect(gap10msOut.windows.length).assertEqual(2);

      const gap1s: ShootWindow[] = [
        fakeWindow(T0, T0 + 10 * SECOND, T0 + SECOND, 0.1, 0.1),
        fakeWindow(T0 + 11 * SECOND, T0 + 20 * SECOND, T0 + 12 * SECOND, 0.1, 0.1)
      ];
      const gap1sOut = ReverseSearch.finalizeWindows(goal, LightThresholds.defaults(), gap1s,
        WindowSortMode.BEST, 30, new ValidEvaluator(), new KernelStats(), ranges);
      expect(gap1sOut.windows.length).assertEqual(2);
    });

    it('non_finite_positions_are_not_reported_as_no_hit', 0, () => {
      const session = new SearchSession(goalOf(), LightThresholds.defaults(),
        [DayRange.of(T0, T0 + 10 * SECOND)], new NaNEvaluator());
      for (let i = 0; i < 200 && !session.isFinished(); i++) {
        session.step(2);
      }
      // 位置不可用不能被当作「没有拍摄机会」：必须是显式失败状态
      expect(session.getState()).assertEqual(SessionState.FAILED);
      expect(session.getError().length > 0).assertTrue();
    });

    it('finalize_rejects_window_whose_best_does_not_match_reported_errors', 0, () => {
      // 伪造一个「宣称误差很小」的窗口，但求值器在该时刻给出完全不同的位置
      const goal = goalOf();
      const bogus: ShootWindow[] = [
        fakeWindow(T0, T0 + 10 * SECOND, T0 + SECOND, 0.1, 0.1)
      ];
      const out = ReverseSearch.finalizeWindows(goal, LightThresholds.defaults(), bogus,
        WindowSortMode.BEST, 30, new NeverValidEvaluator(), new KernelStats(),
        [DayRange.of(T0 - 60 * SECOND, T0 + 120 * SECOND)]);
      expect(out.windows.length).assertEqual(0);
      expect(out.droppedInvalid > 0).assertTrue();
    });
  });
}
