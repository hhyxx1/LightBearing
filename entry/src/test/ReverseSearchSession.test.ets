import { describe, it, expect } from '@ohos/hypium';
import { ReverseSearch, DayRange, WindowSortMode, SearchOutcome } from '../main/ets/services/ReverseSearch';
import { SearchSession, SessionState } from '../main/ets/services/SearchSession';
import { SolarPositionEvaluator } from '../main/ets/services/ReverseSearchKernel';
import { ShootWindow, KernelStats } from '../main/ets/model/ShootWindow';
import { SolarCalc, LightThresholds, SunPosition } from '../main/ets/services/SolarCalc';
import { SearchGoal } from '../main/ets/model/Models';

const HOUR: number = 3600000.0;
const SH_START: number = Date.UTC(2026, 9, 29, 16, 0, 0);
const SH_END: number = Date.UTC(2026, 9, 30, 16, 0, 0);

/** 恒有效轨迹：任何时刻都满足条件（用于窗口/跨日/top-K 逻辑） */
class AlwaysValidEvaluator implements SolarPositionEvaluator {
  positionAt(utcMs: number, latDeg: number, lonDeg: number): SunPosition {
    const p = new SunPosition();
    p.azimuthDeg = 180;
    p.altitudeDeg = 10;
    return p;
  }
}

function perfectGoal(): SearchGoal {
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

export default function reverseSearchSessionTest() {
  describe('ReverseSearchSession', () => {
    it('session_chunks_match_full_range_search', 0, () => {
      const goal = perfectGoal();
      const ranges: DayRange[] = [DayRange.of(SH_START, SH_END)];
      const session = new SearchSession(goal, LightThresholds.defaults(), ranges,
        new AlwaysValidEvaluator());
      session.runToCompletion(2);
      expect(session.getState()).assertEqual(SessionState.DONE);
      expect(session.getProgressPercent()).assertEqual(100);
      expect(session.getWindows().length).assertEqual(1);
      expect(session.getWindows()[0].startUtc).assertEqual(SH_START);
      expect(session.getWindows()[0].endUtc).assertEqual(SH_END);
    });

    it('interleaved_sessions_do_not_pollute_each_other', 0, () => {
      const validSession = new SearchSession(perfectGoal(), LightThresholds.defaults(),
        [DayRange.of(SH_START, SH_END)], new AlwaysValidEvaluator());
      const emptyGoal = perfectGoal();
      emptyGoal.altitudeTarget = 89;
      const emptySession = new SearchSession(emptyGoal, LightThresholds.defaults(),
        [DayRange.of(SH_START, SH_END)], new AlwaysValidEvaluator());
      let guard = 0;
      while ((!validSession.isFinished() || !emptySession.isFinished()) && guard < 20000) {
        if (!validSession.isFinished()) {
          validSession.step(1);
        }
        if (!emptySession.isFinished()) {
          emptySession.step(1);
        }
        guard++;
      }
      expect(validSession.getWindows().length).assertEqual(1);
      expect(emptySession.getWindows().length).assertEqual(0);
    });

    it('cancel_marks_incomplete_not_done', 0, () => {
      const ranges: DayRange[] = [DayRange.of(SH_START, SH_START + 6 * HOUR),
        DayRange.of(SH_START + 6 * HOUR, SH_START + 12 * HOUR)];
      const session = new SearchSession(perfectGoal(), LightThresholds.defaults(), ranges,
        new AlwaysValidEvaluator());
      session.step(0);
      session.cancel();
      expect(session.isFinished()).assertTrue();
      expect(session.getState()).assertEqual(SessionState.CANCELLED);
      expect(session.getState() === SessionState.DONE).assertFalse();
    });

    it('adjacent_ranges_merge_but_real_gap_does_not', 0, () => {
      const goal = perfectGoal();
      const a: ShootWindow[] = [fakeWindow(SH_START, SH_END, SH_START + HOUR, 0.1, 0.1)];
      const b: ShootWindow[] = [fakeWindow(SH_END, SH_END + 24 * HOUR, SH_END + HOUR, 0.1, 0.1)];
      // 合并后边界变化会用同一套内核重算 best，因此这里注入恒有效轨迹
      const merged: SearchOutcome = ReverseSearch.finalizeWindows(goal, LightThresholds.defaults(),
        a.concat(b), WindowSortMode.BEST, 30, new AlwaysValidEvaluator(), new KernelStats(),
        [DayRange.of(SH_START, SH_END), DayRange.of(SH_END, SH_END + 24 * HOUR)]);
      expect(merged.windows.length).assertEqual(1);
      expect(merged.windows[0].startUtc).assertEqual(SH_START);
      expect(merged.windows[0].endUtc).assertEqual(SH_END + 24 * HOUR);

      const gapWindow: ShootWindow[] = [fakeWindow(SH_END + 24 * HOUR, SH_END + 48 * HOUR,
        SH_END + 25 * HOUR, 0.1, 0.1)];
      const gapped: SearchOutcome = ReverseSearch.finalizeWindows(goal, LightThresholds.defaults(),
        a.concat(gapWindow), WindowSortMode.BEST, 30, new AlwaysValidEvaluator(), new KernelStats(),
        [DayRange.of(SH_START, SH_END), DayRange.of(SH_END + 24 * HOUR, SH_END + 48 * HOUR)]);
      expect(gapped.windows.length).assertEqual(2);
    });

    it('negative_timestamps_work_in_session', 0, () => {
      const start = Date.UTC(1969, 11, 30, 16, 0, 0);
      const end = Date.UTC(1969, 11, 31, 16, 0, 0);
      const session = new SearchSession(perfectGoal(), LightThresholds.defaults(),
        [DayRange.of(start, end)], new AlwaysValidEvaluator());
      session.runToCompletion(50);
      expect(session.getState()).assertEqual(SessionState.DONE);
      expect(session.getWindows().length).assertEqual(1);
      expect(session.getWindows()[0].startUtc < 0).assertTrue();
      expect(session.getWindows()[0].bestUtc < 0).assertTrue();
    });

    it('topk_modes_are_deterministic', 0, () => {
      const goal = perfectGoal();
      const raw: ShootWindow[] = [
        fakeWindow(SH_START, SH_START + HOUR, SH_START + 60000, 0.5, 0.5),
        fakeWindow(SH_START + 2 * HOUR, SH_START + 3 * HOUR, SH_START + 2 * HOUR + 60000, 0.1, 0.1),
        fakeWindow(SH_START + 4 * HOUR, SH_START + 5 * HOUR, SH_START + 4 * HOUR + 60000, 0.3, 0.3)
      ];
      const ranges: DayRange[] = [DayRange.of(SH_START, SH_END)];
      const a1 = ReverseSearch.finalizeWindows(goal, LightThresholds.defaults(), raw,
        WindowSortMode.BEST, 2, undefined, new KernelStats(), ranges);
      const a2 = ReverseSearch.finalizeWindows(goal, LightThresholds.defaults(), raw,
        WindowSortMode.BEST, 2, undefined, new KernelStats(), ranges);
      expect(a1.windows.length).assertEqual(2);
      expect(a1.windows[0].bestAzError).assertEqual(0.1);
      expect(a1.windows[0].bestUtc).assertEqual(a2.windows[0].bestUtc);
      expect(a1.windows[1].bestUtc).assertEqual(a2.windows[1].bestUtc);
      const k1 = ReverseSearch.finalizeWindows(goal, LightThresholds.defaults(), raw,
        WindowSortMode.BEST, 1, undefined, new KernelStats(), ranges);
      expect(k1.windows.length).assertEqual(1);
      expect(k1.windows[0].bestAzError).assertEqual(0.1);
      expect(k1.totalBeforeCut).assertEqual(3);
      const k30 = ReverseSearch.finalizeWindows(goal, LightThresholds.defaults(), raw,
        WindowSortMode.BEST, 30, undefined, new KernelStats(), ranges);
      expect(k30.windows.length).assertEqual(3);
    });

    it('asymmetric_tolerances_use_normalized_score', 0, () => {
      const goal = perfectGoal();
      goal.azTolerance = 0.5;
      goal.altTolerance = 5;
      const raw: ShootWindow[] = [
        fakeWindow(SH_START, SH_START + HOUR, SH_START + 60000, 0.1, 4.8),
        fakeWindow(SH_START + 2 * HOUR, SH_START + 3 * HOUR, SH_START + 2 * HOUR + 60000, 0.4, 0.4)
      ];
      const out = ReverseSearch.finalizeWindows(goal, LightThresholds.defaults(), raw,
        WindowSortMode.BEST, 2, undefined, new KernelStats(), [DayRange.of(SH_START, SH_END)]);
      expect(out.windows[0].bestAzError).assertEqual(0.4);
      expect(out.windows[0].bestAltError).assertEqual(0.4);
    });

    it('invalid_parameters_rejected_not_no_hit', 0, () => {
      const goal = perfectGoal();
      const ranges: DayRange[] = [DayRange.of(SH_START, SH_END)];
      expect(ReverseSearch.finalizeWindows(goal, LightThresholds.defaults(), [],
        WindowSortMode.BEST, 0, undefined, new KernelStats(), ranges).errorText.length > 0).assertTrue();
      expect(ReverseSearch.finalizeWindows(goal, LightThresholds.defaults(), [],
        WindowSortMode.BEST, 1001, undefined, new KernelStats(), ranges).errorText.length > 0).assertTrue();
      const badGoal = perfectGoal();
      badGoal.latWgs84 = NaN;
      expect(new SearchSession(badGoal, LightThresholds.defaults(), ranges).getState())
        .assertEqual(SessionState.INVALID);
      const negGoal = perfectGoal();
      negGoal.azTolerance = -1;
      expect(new SearchSession(negGoal, LightThresholds.defaults(), ranges).getState())
        .assertEqual(SessionState.INVALID);
      expect(new SearchSession(perfectGoal(), LightThresholds.defaults(), []).getState())
        .assertEqual(SessionState.INVALID);
    });

    it('various_local_day_lengths_are_respected', 0, () => {
      const durations: number[] = [23 * HOUR, 25 * HOUR, 23.5 * HOUR, 24.5 * HOUR];
      for (const d of durations) {
        const start = SH_START;
        const end = start + d;
        const session = new SearchSession(perfectGoal(), LightThresholds.defaults(),
          [DayRange.of(start, end)], new AlwaysValidEvaluator());
        session.runToCompletion(50);
        expect(session.getWindows().length).assertEqual(1);
        expect(session.getWindows()[0].durationMs()).assertEqual(d);
        expect(session.getWindows()[0].endUtc <= end).assertTrue();
      }
    });
  });
}
