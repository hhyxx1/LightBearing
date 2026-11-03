import { describe, it, expect } from '@ohos/hypium';
import { ReverseSearch, DayRange } from '../main/ets/services/ReverseSearch';
import { ShootWindow, KernelStats } from '../main/ets/model/ShootWindow';
import { SolarCalc, LightThresholds, SunPosition } from '../main/ets/services/SolarCalc';
import { SearchGoal } from '../main/ets/model/Models';

/**
 * QA-2B / QA-07：窗口一对一参考匹配。
 *
 * 生产侧：直接调用真实 `ReverseSearch.searchWindowsInRanges()`（不是 Node 镜像，避免漂移）。
 * 参考侧：本文件内用 SolarCalc.position 以 **1 秒** 步长独立扫描（不调用搜索内核），
 *        把相邻有效时刻聚成参考窗口，双容差分别判定。
 *
 * 匹配规则（一对一，贪心）：按参考窗口起点顺序，为每个参考窗口找**尚未被占用**且时间区间有重叠的
 * 生产窗口；一个生产窗口只能匹配一个参考窗口，避免重复计分。
 * 诊断关系（拆分/合并）额外统计，但不重复计入召回。
 *
 * 限制：参考扫描受 1 秒分辨率限制（更短窗口可能同样漏），且每个用例只在给定区间内扫描，
 * 不能据此宣称连续时间上的全局完备。
 */

const SEC: number = 1000;

function goalOf(lat: number, lon: number, az: number, alt: number, tolAz: number,
  tolAlt: number): SearchGoal {
  const g = new SearchGoal();
  g.latWgs84 = lat;
  g.lonWgs84 = lon;
  g.azimuthTarget = az;
  g.altitudeTarget = alt;
  g.azTolerance = tolAz;
  g.altTolerance = tolAlt;
  g.daylightOnly = false;
  g.maxResults = 30;
  return g;
}

/** 参考扫描：1 秒步长，双容差分别判定，相邻有效点聚合为窗口 */
function referenceWindows(goal: SearchGoal, startUtc: number, endUtc: number): ShootWindow[] {
  const out: ShootWindow[] = [];
  let cur: ShootWindow | undefined = undefined;
  for (let t = startUtc; t < endUtc; t += SEC) {
    const p: SunPosition = SolarCalc.position(t, goal.latWgs84, goal.lonWgs84);
    const azErr = SolarCalc.angularDistance(p.azimuthDeg, goal.azimuthTarget);
    const altErr = Math.abs(p.altitudeDeg - goal.altitudeTarget);
    const valid = azErr <= goal.azTolerance && altErr <= goal.altTolerance;
    if (valid) {
      if (cur === undefined) {
        cur = new ShootWindow();
        cur.startUtc = t;
        cur.endUtc = t + SEC;
        cur.bestUtc = t;
        cur.bestAzError = azErr;
        cur.bestAltError = altErr;
        cur.valid = true;
      } else if (t <= cur.endUtc) {
        cur.endUtc = t + SEC;
        if (azErr + altErr < cur.bestAzError + cur.bestAltError) {
          cur.bestUtc = t;
          cur.bestAzError = azErr;
          cur.bestAltError = altErr;
        }
      } else {
        out.push(cur);
        cur = new ShootWindow();
        cur.startUtc = t;
        cur.endUtc = t + SEC;
        cur.bestUtc = t;
        cur.bestAzError = azErr;
        cur.bestAltError = altErr;
        cur.valid = true;
      }
    } else if (cur !== undefined) {
      out.push(cur);
      cur = undefined;
    }
  }
  if (cur !== undefined) {
    out.push(cur);
  }
  return out;
}

/** 一对一匹配结果 */
class MatchReport {
  refCount: number = 0;
  prodCount: number = 0;
  matched: number = 0;
  missed: number = 0;
  unmatchedProd: number = 0;
  splitRefs: number = 0;
  mergedRefs: number = 0;
  maxStartErrorMs: number = 0;
  maxEndErrorMs: number = 0;
  maxBestErrorMs: number = 0;
  invalidProd: number = 0;
  prodOverlap: number = 0;
  refBestGap: number = 0;
}

function overlapMs(a: ShootWindow, b: ShootWindow): number {
  const s = Math.max(a.startUtc, b.startUtc);
  const e = Math.min(a.endUtc, b.endUtc);
  return e > s ? e - s : 0;
}

function analyse(refs: ShootWindow[], prods: ShootWindow[]): MatchReport {
  const r = new MatchReport();
  r.refCount = refs.length;
  r.prodCount = prods.length;
  const usedProd: boolean[] = [];
  for (let i = 0; i < prods.length; i++) {
    usedProd.push(false);
  }
  const assignedProd: number[] = [];
  for (const ref of refs) {
    let bestIdx = -1;
    let bestOverlap = 0;
    for (let i = 0; i < prods.length; i++) {
      if (usedProd[i]) {
        continue;
      }
      const ov = overlapMs(ref, prods[i]);
      if (ov > bestOverlap) {
        bestOverlap = ov;
        bestIdx = i;
      }
    }
    if (bestIdx < 0) {
      // 没有重叠窗口：可能是完全漏报；若某生产窗口与它「相邻」则在诊断里体现
      let adjacent = false;
      for (const p0 of prods) {
        if (Math.abs(p0.startUtc - ref.endUtc) <= 2 * SEC ||
          Math.abs(ref.startUtc - p0.endUtc) <= 2 * SEC) {
          adjacent = true;
          break;
        }
      }
      if (!adjacent) {
        r.missed++;
      }
      continue;
    }
    usedProd[bestIdx] = true;
    assignedProd.push(bestIdx);
    r.matched++;
    r.maxStartErrorMs = Math.max(r.maxStartErrorMs, Math.abs(prods[bestIdx].startUtc - ref.startUtc));
    r.maxEndErrorMs = Math.max(r.maxEndErrorMs, Math.abs(prods[bestIdx].endUtc - ref.endUtc));
    r.maxBestErrorMs = Math.max(r.maxBestErrorMs, Math.abs(prods[bestIdx].bestUtc - ref.bestUtc));
    r.refBestGap = Math.max(r.refBestGap,
      (prods[bestIdx].bestAzError + prods[bestIdx].bestAltError) -
      (ref.bestAzError + ref.bestAltError));
  }
  for (let i = 0; i < prods.length; i++) {
    if (!usedProd[i]) {
      r.unmatchedProd++;
    }
  }
  // 诊断用多对多关系
  for (const ref of refs) {
    let n = 0;
    for (const p of prods) {
      if (overlapMs(ref, p) > 0 || Math.abs(p.startUtc - ref.endUtc) <= SEC ||
        Math.abs(ref.startUtc - p.endUtc) <= SEC) {
        n++;
      }
    }
    if (n > 1) {
      r.splitRefs++;
    }
  }
  for (const p of prods) {
    let n = 0;
    for (const ref of refs) {
      if (overlapMs(ref, p) > 0) {
        n++;
      }
    }
    if (n > 1) {
      r.mergedRefs++;
    }
  }
  for (let i = 1; i < prods.length; i++) {
    if (prods[i].startUtc < prods[i - 1].endUtc) {
      r.prodOverlap++;
    }
  }
  for (const p of prods) {
    if (!Number.isFinite(p.bestAzError) || !Number.isFinite(p.bestAltError) ||
      p.bestAzError < 0 || p.bestAltError < 0) {
      r.invalidProd++;
    }
  }
  return r;
}

export default function windowMatchingTest() {
  describe('WindowMatching', () => {
    const SH_LAT: number = 31.2304;
    const SH_LON: number = 121.4737;
    const T0: number = Date.UTC(2026, 9, 30, 6, 0, 0);   // 上海当天下午（UTC）
    const TWO_H: number = 2 * 3600 * 1000;

    it('symmetric_tolerance_matches_one_to_one', 0, () => {
      const noon = SolarCalc.position(T0 + 3600 * 1000, SH_LAT, SH_LON);
      const goal = goalOf(SH_LAT, SH_LON, noon.azimuthDeg, noon.altitudeDeg, 3, 3);
      const refs = referenceWindows(goal, T0, T0 + TWO_H);
      const prods = ReverseSearch.searchWindowsInRanges(goal, LightThresholds.defaults(),
        [DayRange.of(T0, T0 + TWO_H)], new KernelStats());
      const r = analyse(refs, prods);
      expect(r.refCount).assertEqual(1);
      expect(r.prodCount).assertEqual(1);
      expect(r.matched).assertEqual(1);
      expect(r.missed).assertEqual(0);
      expect(r.unmatchedProd).assertEqual(0);
      expect(r.maxStartErrorMs <= 2 * SEC).assertTrue();
      expect(r.maxEndErrorMs <= 2 * SEC).assertTrue();
      expect(r.maxBestErrorMs <= 2 * SEC).assertTrue();
      expect(r.splitRefs).assertEqual(0);
      expect(r.mergedRefs).assertEqual(0);
    });

    it('short_window_is_found_and_matched', 0, () => {
      const t0: number = Date.UTC(2026, 9, 30, 7, 2, 30);
      const p = SolarCalc.position(t0, SH_LAT, SH_LON);
      const goal = goalOf(SH_LAT, SH_LON, p.azimuthDeg, p.altitudeDeg, 0.1, 0.1);
      const refs = referenceWindows(goal, T0, T0 + TWO_H);
      const prods = ReverseSearch.searchWindowsInRanges(goal, LightThresholds.defaults(),
        [DayRange.of(T0, T0 + TWO_H)], new KernelStats());
      const r = analyse(refs, prods);
      expect(r.refCount).assertEqual(1);
      expect(r.matched).assertEqual(1);
      expect(r.maxStartErrorMs <= 2 * SEC).assertTrue();
      expect(r.maxBestErrorMs <= 2 * SEC).assertTrue();
    });

    it('asymmetric_tolerance_matches_one_to_one', 0, () => {
      const noon = SolarCalc.position(T0 + 3600 * 1000, SH_LAT, SH_LON);
      const goal = goalOf(SH_LAT, SH_LON, noon.azimuthDeg, noon.altitudeDeg, 3, 0.5);
      const refs = referenceWindows(goal, T0, T0 + TWO_H);
      const prods = ReverseSearch.searchWindowsInRanges(goal, LightThresholds.defaults(),
        [DayRange.of(T0, T0 + TWO_H)], new KernelStats());
      const r = analyse(refs, prods);
      expect(r.matched).assertEqual(r.refCount);
      expect(r.missed).assertEqual(0);
      expect(r.maxEndErrorMs <= 2 * SEC).assertTrue();
    });

    it('wide_tolerance_single_window_no_duplicates', 0, () => {
      const noon = SolarCalc.position(T0 + 3600 * 1000, SH_LAT, SH_LON);
      const goal = goalOf(SH_LAT, SH_LON, noon.azimuthDeg, noon.altitudeDeg, 8, 8);
      const refs = referenceWindows(goal, T0, T0 + TWO_H);
      const prods = ReverseSearch.searchWindowsInRanges(goal, LightThresholds.defaults(),
        [DayRange.of(T0, T0 + TWO_H)], new KernelStats());
      const r = analyse(refs, prods);
      expect(r.prodOverlap).assertEqual(0);
      expect(r.matched).assertEqual(r.refCount);
      expect(r.unmatchedProd).assertEqual(0);
    });

    it('no_hit_case_has_no_spurious_windows', 0, () => {
      const goal = goalOf(SH_LAT, SH_LON, 180, 89, 0.5, 0.5);
      const refs = referenceWindows(goal, T0, T0 + TWO_H);
      const prods = ReverseSearch.searchWindowsInRanges(goal, LightThresholds.defaults(),
        [DayRange.of(T0, T0 + TWO_H)], new KernelStats());
      expect(refs.length).assertEqual(0);
      expect(prods.length).assertEqual(0);
    });

    it('high_latitude_matches_one_to_one', 0, () => {
      const noon = SolarCalc.position(T0 + 3600 * 1000, 69.6492, 18.9553);
      const goal = goalOf(69.6492, 18.9553, noon.azimuthDeg, noon.altitudeDeg, 3, 3);
      const refs = referenceWindows(goal, T0, T0 + TWO_H);
      const prods = ReverseSearch.searchWindowsInRanges(goal, LightThresholds.defaults(),
        [DayRange.of(T0, T0 + TWO_H)], new KernelStats());
      const r = analyse(refs, prods);
      expect(r.matched).assertEqual(r.refCount);
      expect(r.missed).assertEqual(0);
      expect(r.maxStartErrorMs <= 2 * SEC).assertTrue();
    });

    it('north_wrap_target_matches', 0, () => {
      // 目标方位接近正北：验证 0/360 包裹下仍能一对一匹配
      let target: number = -1;
      for (let t = T0; t < T0 + 24 * 3600 * 1000; t += 60 * 1000) {
        const p = SolarCalc.position(t, SH_LAT, SH_LON);
        if (SolarCalc.angularDistance(p.azimuthDeg, 0) <= 0.5) {
          target = t;
          break;
        }
      }
      expect(target > 0).assertTrue();
      const p = SolarCalc.position(target, SH_LAT, SH_LON);
      const goal = goalOf(SH_LAT, SH_LON, p.azimuthDeg, p.altitudeDeg, 1, 3);
      const start = target - 3600 * 1000;
      const end = target + 3600 * 1000;
      const refs = referenceWindows(goal, start, end);
      const prods = ReverseSearch.searchWindowsInRanges(goal, LightThresholds.defaults(),
        [DayRange.of(start, end)], new KernelStats());
      const r = analyse(refs, prods);
      expect(r.matched).assertEqual(r.refCount);
      expect(r.maxStartErrorMs <= 2 * SEC).assertTrue();
    });
  });
}

