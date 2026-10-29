import { SolarCalc, SunPosition, LightThresholds } from './SolarCalc';
import { Candidate, SearchGoal } from '../model/Models';

/** 粗扫粒度（毫秒）：5 分钟 */
const COARSE_STEP_MS = 5 * 60 * 1000;
/** 细化层级：从粗到细的步长 */
const REFINE_STEPS: number[] = [30 * 1000, 5 * 1000, 1000];

/**
 * 反向寻光：在日期区间内寻找满足「目标方位/高度 ± 容差」的时刻。
 *
 * 算法（与 PRD 第 5 节一致）：
 * 1. 逐日按 5 分钟粒度粗扫，用环形距离计算方位误差；
 * 2. 命中后在其邻域按 30s / 5s / 1s 逐级细化，取误差最小点；
 * 3. 相邻命中合并为同一时间窗口，仅保留该窗口内的最优解；
 * 4. 按总误差升序输出，附带误差、当地时间与阶段。
 */
export class ReverseSearch {
  /** 综合误差度量：方位误差 + 高度误差（度） */
  private static cost(pos: SunPosition, goal: SearchGoal): number {
    const azErr = SolarCalc.angularDistance(pos.azimuthDeg, goal.azimuthTarget);
    const altErr = Math.abs(pos.altitudeDeg - goal.altitudeTarget);
    return azErr + altErr;
  }

  private static inTolerance(pos: SunPosition, goal: SearchGoal): boolean {
    const azErr = SolarCalc.angularDistance(pos.azimuthDeg, goal.azimuthTarget);
    const altErr = Math.abs(pos.altitudeDeg - goal.altitudeTarget);
    return azErr <= goal.azTolerance && altErr <= goal.altTolerance;
  }

  /** 局部细化：在 centerMs 附近 ±windowMs 内按 stepMs 找最优 */
  private static refineAt(goal: SearchGoal, centerMs: number, windowMs: number, stepMs: number): number {
    let bestT = centerMs;
    let bestCost = Number.MAX_VALUE;
    let t = centerMs - windowMs;
    const end = centerMs + windowMs;
    while (t <= end) {
      const pos = SolarCalc.position(t, goal.latWgs84, goal.lonWgs84);
      const c = ReverseSearch.cost(pos, goal);
      if (c < bestCost) {
        bestCost = c;
        bestT = t;
      }
      t += stepMs;
    }
    return bestT;
  }

  /**
   * 执行搜索。
   * @param dayStartsUtc 每一天的本地 00:00 对应 UTC 毫秒（由调用方按地点时区生成）
   */
  static search(goal: SearchGoal, thresholds: LightThresholds, dayStartsUtc: number[]): Candidate[] {
    const raw: Candidate[] = [];
    for (const dayStart of dayStartsUtc) {
      const dayEnd = dayStart + 86400000;
      let t = dayStart;
      while (t < dayEnd) {
        const pos = SolarCalc.position(t, goal.latWgs84, goal.lonWgs84);
        if (ReverseSearch.inTolerance(pos, goal)) {
          let bestT = t;
          let windowMs = COARSE_STEP_MS;
          for (const step of REFINE_STEPS) {
            bestT = ReverseSearch.refineAt(goal, bestT, windowMs, step);
            windowMs = step * 2;
          }
          const bestPos = SolarCalc.position(bestT, goal.latWgs84, goal.lonWgs84);
          const azErr = SolarCalc.angularDistance(bestPos.azimuthDeg, goal.azimuthTarget);
          const altErr = Math.abs(bestPos.altitudeDeg - goal.altitudeTarget);
          if (azErr <= goal.azTolerance && altErr <= goal.altTolerance) {
            if (!goal.daylightOnly || bestPos.altitudeDeg > -0.833) {
              raw.push(Candidate.of(bestT, bestPos.azimuthDeg, bestPos.altitudeDeg, azErr, altErr,
                SolarCalc.phaseOf(bestPos.altitudeDeg, thresholds)));
            }
          }
          // 跳过已细化窗口，避免同一窗口重复命中
          t += COARSE_STEP_MS * 2;
        } else {
          t += COARSE_STEP_MS;
        }
      }
    }

    // 合并 10 分钟内的重复命中，保留误差最小者
    raw.sort((a: Candidate, b: Candidate) => a.utcMs - b.utcMs);
    const merged: Candidate[] = [];
    for (const c of raw) {
      if (merged.length === 0) {
        merged.push(c);
        continue;
      }
      const last = merged[merged.length - 1];
      if (c.utcMs - last.utcMs <= 10 * 60 * 1000) {
        const lastCost = last.azError + last.altError;
        const cCost = c.azError + c.altError;
        if (cCost < lastCost) {
          merged[merged.length - 1] = c;
        }
      } else {
        merged.push(c);
      }
    }

    merged.sort((a: Candidate, b: Candidate) => (a.azError + a.altError) - (b.azError + b.altError));
    if (merged.length > goal.maxResults) {
      return merged.slice(0, goal.maxResults);
    }
    return merged;
  }
}
