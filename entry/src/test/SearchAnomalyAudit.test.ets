import { describe, it, expect } from '@ohos/hypium';
import { SearchSession, SessionState } from '../main/ets/services/SearchSession';
import { SearchRunPolicy, RunDecision, RunKind } from '../main/ets/services/SearchRunPolicy';
import { SolarPositionEvaluator } from '../main/ets/services/ReverseSearchKernel';
import { DayRange } from '../main/ets/services/ReverseSearch';
import { LightThresholds, SunPosition } from '../main/ets/services/SolarCalc';
import { SearchGoal } from '../main/ets/model/Models';
import { JobStatus } from '../main/ets/model/BaseModels';

/**
 * QA-1 审计用「行为固化」测试：断言的是**当前实现的实际行为**，用于把审计结论变成可执行证据。
 * 其中多条属于已知缺陷（注释里标注 QA-1-xx），修复后这些断言应当改为新的正确期望。
 */

const MIN: number = 60000.0;
const HOUR: number = 3600000.0;
const T0: number = Date.UTC(2026, 9, 29, 20, 0, 0);

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

/** 在 [validFrom, validTo) 有效，[badFrom, badTo) 返回 NaN，其余无效 */
class MixedEvaluator implements SolarPositionEvaluator {
  private validFrom: number = 0;
  private validTo: number = 0;
  private badFrom: number = 0;
  private badTo: number = 0;

  constructor(validFrom: number, validTo: number, badFrom: number, badTo: number) {
    this.validFrom = validFrom;
    this.validTo = validTo;
    this.badFrom = badFrom;
    this.badTo = badTo;
  }

  positionAt(utcMs: number, latDeg: number, lonDeg: number): SunPosition {
    const p = new SunPosition();
    const bad = utcMs >= this.badFrom && utcMs < this.badTo;
    if (bad) {
      p.azimuthDeg = Infinity;
      p.altitudeDeg = NaN;
      return p;
    }
    p.azimuthDeg = 180;
    p.altitudeDeg = (utcMs >= this.validFrom && utcMs < this.validTo) ? 10 : 89;
    return p;
  }
}

function runSession(ev: SolarPositionEvaluator, ranges: DayRange[]): SearchSession {
  const session = new SearchSession(goalOf(), LightThresholds.defaults(), ranges, ev);
  for (let i = 0; i < 5000 && !session.isFinished(); i++) {
    session.step(5);
  }
  return session;
}

export default function searchAnomalyAuditTest() {
  describe('SearchAnomalyAudit', () => {
    it('QA1-A1_valid_then_nan_same_range_still_reports_done', 0, () => {
      // 同一天：前半段有有效窗口，后半段求值器返回 NaN/Infinity
      // 现状：只有「无有效跨度且出现非有限」才判 FAILED，因此这里仍是 DONE
      const a0 = T0;
      const a1 = T0 + 10 * MIN;
      const session = runSession(new MixedEvaluator(a0 + 2 * MIN, a0 + 3 * MIN,
        a0 + 6 * MIN, a1), [DayRange.of(a0, a1)]);
      expect(session.getState()).assertEqual(SessionState.DONE);
      expect(session.getWindows().length).assertEqual(1);
      // 异常确实发生过，但没有改变终态（缺陷证据）
      expect(session.getStats().nonFiniteSamples > 0).assertTrue();
      expect(session.getUnreliableRanges()).assertEqual(0);
    });

    it('QA1-A2_nan_then_valid_same_range_reports_done', 0, () => {
      // 同一天：先 NaN 后出现有效窗口
      const a0 = T0;
      const a1 = T0 + 10 * MIN;
      const session = runSession(new MixedEvaluator(a0 + 7 * MIN, a0 + 8 * MIN,
        a0, a0 + 3 * MIN), [DayRange.of(a0, a1)]);
      expect(session.getState()).assertEqual(SessionState.DONE);
      expect(session.getWindows().length).assertEqual(1);
      expect(session.getUnreliableRanges()).assertEqual(0);
    });

    it('QA1-A3_full_nan_day_fails_the_session', 0, () => {
      // 某一天整段 NaN 且没有有效跨度 → 会话 FAILED（这是修好的那条路径）
      const a0 = T0;
      const a1 = T0 + 10 * MIN;
      const session = runSession(new MixedEvaluator(a0, a0 + MIN, a0, a1), [DayRange.of(a0, a1)]);
      expect(session.getState()).assertEqual(SessionState.FAILED);
      expect(session.getUnreliableRanges()).assertEqual(1);
      expect(session.getError().indexOf('非有限') >= 0).assertTrue();
    });

    it('QA1-A4_first_day_ok_second_day_partial_nan_is_done', 0, () => {
      // 第一天正常有窗口，第二天前半 NaN 后半有窗口 → 仍判 DONE（异常被吞）
      const d1s = T0;
      const d1e = T0 + 10 * MIN;
      const d2s = d1e;
      const d2e = d2s + 10 * MIN;
      const session = runSession(new MixedEvaluator(d2s + 7 * MIN, d2s + 8 * MIN, d2s, d2s + 3 * MIN),
        [DayRange.of(d1s, d1e), DayRange.of(d2s, d2e)]);
      expect(session.getState()).assertEqual(SessionState.DONE);
      expect(session.getWindows().length).assertEqual(1);
    });

    it('QA1-A5_infinity_after_windows_is_ignored', 0, () => {
      // 已有窗口之后出现 Infinity：统计计数会增长，但终态不变
      const a0 = T0;
      const a1 = T0 + 10 * MIN;
      const session = runSession(new MixedEvaluator(a0 + 2 * MIN, a0 + 3 * MIN,
        a0 + 8 * MIN, a1), [DayRange.of(a0, a1)]);
      expect(session.getState()).assertEqual(SessionState.DONE);
      expect(session.getStats().nonFiniteSamples > 0).assertTrue();
    });

    it('QA1-A6_normal_search_then_cancel_keeps_cancelled', 0, () => {
      const session = new SearchSession(goalOf(), LightThresholds.defaults(),
        [DayRange.of(T0, T0 + 6 * HOUR)], new MixedEvaluator(T0, T0 + HOUR, T0 + 5 * HOUR, T0 + 6 * HOUR));
      session.step(1);
      session.cancel();
      expect(session.getState()).assertEqual(SessionState.CANCELLED);
    });

    it('QA1-B1_unreliable_ranges_parameter_does_not_affect_decision', 0, () => {
      // 纯逻辑：unreliableRanges 传入但未参与决策 → 不同取值得到完全相同的决定（死参数证据）
      const none = SearchRunPolicy.decide(SessionState.DONE, 2, 2, 0, 0, '', false, 'scope');
      const some = SearchRunPolicy.decide(SessionState.DONE, 2, 2, 0, 5, '', false, 'scope');
      expect(none.kind).assertEqual(some.kind);
      expect(none.jobStatus).assertEqual(some.jobStatus);
      expect(none.summary).assertEqual(some.summary);
      expect(none.writeSuccessHistory).assertEqual(some.writeSuccessHistory);
    });

    it('QA1-B2_failed_with_partial_windows_wants_results_and_error', 0, () => {
      // 纯逻辑：FAILED 且有部分窗口时 showResults=true 且 errorText 非空 —— 页面必须两者都渲染
      const d: RunDecision = SearchRunPolicy.decide(SessionState.FAILED, 2, 2, 0, 1, '太阳位置出现非有限值',
        false, 'scope');
      expect(d.kind).assertEqual(RunKind.FAILED);
      expect(d.showResults).assertTrue();
      expect(d.errorText.length > 0).assertTrue();
      expect(d.jobStatus).assertEqual(JobStatus.FAILED);
      expect(d.writeSuccessHistory).assertFalse();
    });
  });
}
