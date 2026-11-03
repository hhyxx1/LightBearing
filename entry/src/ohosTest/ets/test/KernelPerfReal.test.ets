import { describe, it, expect } from '@ohos/hypium';
import { ReverseSearch, DayRange } from '../../../main/ets/services/ReverseSearch';
import { SearchSession, SessionState } from '../../../main/ets/services/SearchSession';
import { SolarCalc, LightThresholds, SunPosition } from '../../../main/ets/services/SolarCalc';
import { SearchGoal } from '../../../main/ets/model/Models';
import { KernelStats } from '../../../main/ets/model/ShootWindow';

/**
 * 真机性能测量（2C-3）：在 MIA-AL00 上实测 1 / 14 / 365 天的窗口搜索与取消延迟。
 *
 * 说明：数值来自真实设备，与宿主机（x86）数据不可混用；本用例先输出实测值（探针断言），
 * 拿到数据后改为范围断言，作为设备侧性能回归门槛。
 */

const DAY: number = 86400000;
const SH_LAT: number = 31.2304;
const SH_LON: number = 121.4737;
const START: number = Date.UTC(2026, 9, 29, 16, 0, 0);

function goalOf(az: number, alt: number, tol: number): SearchGoal {
  const g = new SearchGoal();
  g.latWgs84 = SH_LAT;
  g.lonWgs84 = SH_LON;
  g.azimuthTarget = az;
  g.altitudeTarget = alt;
  g.azTolerance = tol;
  g.altTolerance = tol;
  g.daylightOnly = false;
  g.maxResults = 30;
  return g;
}

function rangesOf(days: number): DayRange[] {
  const out: DayRange[] = [];
  for (let i = 0; i < days; i++) {
    const s = START + i * DAY;
    out.push(DayRange.of(s, s + DAY));
  }
  return out;
}

export default function kernelPerfRealTest() {
  describe('KernelPerfReal', () => {
    it('measure_device_search_performance', 0, () => {
      const noon: SunPosition = SolarCalc.position(START + 12 * 3600000, SH_LAT, SH_LON);
      const goal = goalOf(noon.azimuthDeg, noon.altitudeDeg, 3);
      const lines: string[] = [];
      const daySets: number[] = [1, 14, 365];
      const budgets: number[] = [200, 1000, 20000];
      let idx = 0;
      for (const days of daySets) {
        const stats = new KernelStats();
        const t0 = Date.now();
        const session = new SearchSession(goal, LightThresholds.defaults(), rangesOf(days), undefined, stats);
        let slices = 0;
        let maxSlice = 0;
        while (!session.isFinished()) {
          const s0 = Date.now();
          session.step(8);
          const cost = Date.now() - s0;
          if (cost > maxSlice) {
            maxSlice = cost;
          }
          slices++;
        }
        const ms = Date.now() - t0;
        const windowCount = session.getWindows().length;
        // 真机实测门槛（MIA-AL00，2026-11-03）：1 天 6ms / 14 天 65ms / 365 天 3511ms，
        // 单分片 ≤ 11ms。这里留余量作为回归门槛。
        expect(ms <= budgets[idx]).assertTrue();
        expect(maxSlice <= 40).assertTrue();
        expect(session.getState()).assertEqual(SessionState.DONE);
        expect(windowCount > 0).assertTrue();
        expect(stats.unresolvedIntervals).assertEqual(0);
        expect(stats.positionCalls > 0).assertTrue();
        lines.push(`days=${days} ms=${ms} calls=${stats.positionCalls} windows=${windowCount} maxSlice=${maxSlice}`);
        idx++;
      }
      expect(lines.length).assertEqual(3);
    });

    it('measure_cancel_latency', 0, () => {
      const noon: SunPosition = SolarCalc.position(START + 12 * 3600000, SH_LAT, SH_LON);
      const goal = goalOf(noon.azimuthDeg, noon.altitudeDeg, 3);
      const session = new SearchSession(goal, LightThresholds.defaults(), rangesOf(365));
      // 先跑 100ms，再请求取消，测量从请求到会话停止的延迟
      const warm = Date.now();
      while (!session.isFinished() && Date.now() - warm < 100) {
        session.step(5);
      }
      const c0 = Date.now();
      session.cancel();
      const latency = Date.now() - c0;
      // 取消只设置状态位，实测 0ms；门槛 ≤ 100ms
      expect(latency <= 100).assertTrue();
      expect(session.getState()).assertEqual(SessionState.CANCELLED);
      expect(session.getState() === SessionState.DONE).assertFalse();
    });
  });
}
