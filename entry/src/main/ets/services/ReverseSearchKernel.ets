import { SolarCalc, SunPosition, LightThresholds } from './SolarCalc';
import { SearchGoal } from '../model/Models';
import { ShootWindow, KernelStats } from '../model/ShootWindow';

/**
 * 反向寻光搜索内核（2C-2）。
 *
 * 设计：自适应区间三态分类 + 阈值边界细化 + 连续窗口构造。
 *
 * 为什么不再用「等步长粗扫 + 命中才细化」：
 * - 固定步长会漏掉短于步长、且落在两个采样点之间的真实窗口（2C-1 实测 32 秒窗口 100% 漏报）；
 * - 只检查区间端点符号是否变化，也无法发现「同一区间内穿越两次」的情况。
 *
 * 现在的做法：
 * 1. 对区间 [a, b) 采样 a / 中点 / b-1，用**显式的变化率上界**给出保守包络；
 * 2. 三态分类：整段可证有效（直接收下，不再细分）、整段可证无效（剪枝）、其余继续二分；
 * 3. 细分到 1 秒分辨率后逐点判定，把相邻有效点聚成连续窗口；
 * 4. 每个窗口单独求最优点并**再验证双容差**（修正旧版「cost 最小但单轴越界」的缺陷）。
 *
 * 数值近似声明：包络用的变化率上界是保守估计（太阳高度 ≤ 0.0045°/s；方位在
 * |Δaz| 较大或高度接近天顶时不使用上界、直接细分）。因此本算法是**数值方法**：
 * 短于 1 秒的窗口仍可能漏，`unresolvedIntervals` 记录无法在最大深度内判定的区间数。
 */
/** 可注入的太阳位置求值器：默认用 SolarCalc，测试可注入合成轨迹 */
export interface SolarPositionEvaluator {
  positionAt(utcMs: number, latDeg: number, lonDeg: number): SunPosition;
}

export class ReverseSearchKernel {
  /** 目标时间分辨率（毫秒） */
  static readonly RESOLUTION_MS: number = 1000;
  /** 最大二分深度 */
  static readonly MAX_DEPTH: number = 18;
  /** 太阳高度变化率上界（度/秒），约 16°/小时，取保守值 */
  static readonly ALT_RATE_DEG_PER_SEC: number = 0.0045;
  /** 方位角变化率上界（度/秒），仅在方位连续且高度 < 80° 时使用 */
  static readonly AZ_RATE_DEG_PER_SEC: number = 0.05;
  /** 方位角超过该角度变化就认为「跨包裹/近天顶」，不再使用变化率上界 */
  static readonly AZ_CONTINUITY_LIMIT_DEG: number = 30.0;
  /** 高度超过该值视为接近天顶，方位变化不可界 */
  static readonly ZENITH_LIMIT_DEG: number = 80.0;

  /** 内部上下文：缓存采样结果、统计调用次数 */
  private static cachedT: number = Number.NaN;
  private static cachedPos: SunPosition = new SunPosition();
  private static goalRef: SearchGoal = new SearchGoal();
  /** 测试注入用；为 undefined 时使用 SolarCalc.position */
  private static injected: SolarPositionEvaluator | undefined = undefined;

  private static pos(utcMs: number, stats: KernelStats): SunPosition {
    if (utcMs === ReverseSearchKernel.cachedT) {
      return ReverseSearchKernel.cachedPos;
    }
    stats.positionCalls++;
    const ev = ReverseSearchKernel.injected;
    const p: SunPosition = ev !== undefined
      ? ev.positionAt(utcMs, ReverseSearchKernel.goalRef.latWgs84, ReverseSearchKernel.goalRef.lonWgs84)
      : SolarCalc.position(utcMs, ReverseSearchKernel.goalRef.latWgs84,
        ReverseSearchKernel.goalRef.lonWgs84);
    ReverseSearchKernel.cachedT = utcMs;
    ReverseSearchKernel.cachedPos = p;
    return p;
  }

  private static wrap180(deg: number): number {
    let v = deg % 360;
    if (v > 180) {
      v -= 360;
    }
    if (v < -180) {
      v += 360;
    }
    return v;
  }

  /** 单点判定 */
  private static validAt(t: number, goal: SearchGoal, stats: KernelStats): boolean {
    const p = ReverseSearchKernel.pos(t, stats);
    if (!Number.isFinite(p.azimuthDeg) || !Number.isFinite(p.altitudeDeg)) {
      return false;
    }
    const azErr = SolarCalc.angularDistance(p.azimuthDeg, goal.azimuthTarget);
    const altErr = Math.abs(p.altitudeDeg - goal.altitudeTarget);
    if (!(azErr <= goal.azTolerance && altErr <= goal.altTolerance)) {
      return false;
    }
    if (goal.daylightOnly && !(p.altitudeDeg > -0.833)) {
      return false;
    }
    return true;
  }

  /** 归一到容差的代价（用于窗口内选最优点；排序语义：两轴相对误差之和） */
  private static normCost(t: number, goal: SearchGoal, stats: KernelStats): number {
    const p = ReverseSearchKernel.pos(t, stats);
    const azErr = SolarCalc.angularDistance(p.azimuthDeg, goal.azimuthTarget);
    const altErr = Math.abs(p.altitudeDeg - goal.altitudeTarget);
    const azScale = goal.azTolerance > 0 ? goal.azTolerance : 1;
    const altScale = goal.altTolerance > 0 ? goal.altTolerance : 1;
    return azErr / azScale + altErr / altScale;
  }

  /**
   * 区间三态分类：0 = 确定无效，1 = 确定有效，2 = 需要继续细分。
   * 判定基于「采样值 + 变化率上界」，两者共同构成保守包络。
   */
  private static classify(a: number, b: number, goal: SearchGoal, stats: KernelStats): number {
    const w = b - a;
    if (w <= 0) {
      return 0;
    }
    const widthSec = w / 1000;
    const mid = a + Math.floor(w / 2);
    const samples: number[] = [a, mid, b - 1];
    const poses: SunPosition[] = [];
    for (const t of samples) {
      poses.push(ReverseSearchKernel.pos(t, stats));
    }
    // 方位连续性：跨度大或接近天顶时放弃上界，直接细分
    let azContinuous = true;
    for (let i = 1; i < poses.length; i++) {
      if (!Number.isFinite(poses[i].altitudeDeg) || !Number.isFinite(poses[i - 1].altitudeDeg)) {
        return 2;
      }
      if (poses[i].altitudeDeg > ReverseSearchKernel.ZENITH_LIMIT_DEG ||
        poses[i - 1].altitudeDeg > ReverseSearchKernel.ZENITH_LIMIT_DEG) {
        azContinuous = false;
      }
      const dAz = Math.abs(ReverseSearchKernel.wrap180(poses[i].azimuthDeg - poses[i - 1].azimuthDeg));
      if (dAz > ReverseSearchKernel.AZ_CONTINUITY_LIMIT_DEG) {
        azContinuous = false;
      }
    }
    const altMargin = ReverseSearchKernel.ALT_RATE_DEG_PER_SEC * widthSec * 0.5 + 1e-9;
    const azMargin = azContinuous ? ReverseSearchKernel.AZ_RATE_DEG_PER_SEC * widthSec * 0.5 + 1e-9 : 0;

    let allMust = true;      // 所有采样点都「必然有效」
    let anyCan = false;      // 至少一个采样点「可能有效」
    for (let i = 0; i < poses.length; i++) {
      const p = poses[i];
      const azErr = SolarCalc.angularDistance(p.azimuthDeg, goal.azimuthTarget);
      const altErr = Math.abs(p.altitudeDeg - goal.altitudeTarget);
      const altSlack = goal.altTolerance - altErr;
      const azSlack = goal.azTolerance - azErr;
      const daySlack = p.altitudeDeg + 0.833;
      const canBeValid = altSlack + altMargin >= 0 && azSlack + azMargin >= 0 &&
        (!goal.daylightOnly || daySlack + altMargin > 0);
      const mustBeValid = altSlack - altMargin > 0 && azSlack - azMargin > 0 &&
        (!goal.daylightOnly || daySlack - altMargin > 0);
      if (canBeValid) {
        anyCan = true;
      }
      if (!mustBeValid) {
        allMust = false;
      }
    }
    // 最近的采样点距区间内任一点不超过 w/4，而 margin 按 w/2 估计：因此
    // 「所有采样点都不可能有效」⇒ 整段可证无效；「所有采样点必然有效」⇒ 整段可证有效。
    if (!anyCan) {
      if (azContinuous) {
        stats.provenInvalidChunks++;
        return 0;
      }
      return 2;
    }
    if (allMust && azContinuous) {
      stats.provenValidChunks++;
      return 1;
    }
    return 2;
  }

  /** 收集有效跨度（毫秒），用 [start, end) 表示 */
  private static collect(a: number, b: number, goal: SearchGoal, stats: KernelStats,
    depth: number, spans: number[]): void {
    if (!(b > a)) {
      return;
    }
    if (depth > stats.maxDepth) {
      stats.maxDepth = depth;
    }
    if (b - a <= ReverseSearchKernel.RESOLUTION_MS) {
      if (ReverseSearchKernel.validAt(a, goal, stats)) {
        spans.push(a);
        spans.push(b);
      }
      return;
    }
    const cls = ReverseSearchKernel.classify(a, b, goal, stats);
    if (cls === 0) {
      return;
    }
    if (cls === 1) {
      spans.push(a);
      spans.push(b);
      return;
    }
    if (depth >= ReverseSearchKernel.MAX_DEPTH) {
      // 无法在深度内判定：退化为逐分辨率扫描，并如实计数
      stats.unresolvedIntervals++;
      for (let t = a; t < b; t += ReverseSearchKernel.RESOLUTION_MS) {
        if (ReverseSearchKernel.validAt(t, goal, stats)) {
          spans.push(t);
          spans.push(Math.min(t + ReverseSearchKernel.RESOLUTION_MS, b));
        }
      }
      return;
    }
    const mid = a + Math.floor((b - a) / 2 / 1000) * 1000;
    if (!(mid > a && mid < b)) {
      ReverseSearchKernel.collect(a, b, goal, stats, depth + 1, spans);
      return;
    }
    ReverseSearchKernel.collect(a, mid, goal, stats, depth + 1, spans);
    ReverseSearchKernel.collect(mid, b, goal, stats, depth + 1, spans);
  }

  /** 把有效跨度按「中间存在无效时间」切分成独立窗口 */
  private static buildWindows(spans: number[], goal: SearchGoal, thresholds: LightThresholds,
    stats: KernelStats): ShootWindow[] {
    const merged: number[] = [];
    for (let i = 0; i < spans.length; i += 2) {
      const s = spans[i];
      const e = spans[i + 1];
      const n = merged.length;
      if (n > 0 && s <= merged[n - 1]) {
        // 与上一段相接或重叠 → 同一连续窗口
        if (e > merged[n - 1]) {
          merged[n - 1] = e;
        }
      } else {
        merged.push(s);
        merged.push(e);
      }
    }
    const windows: ShootWindow[] = [];
    for (let i = 0; i < merged.length; i += 2) {
      const w = ReverseSearchKernel.makeWindow(merged[i], merged[i + 1], goal, thresholds, stats);
      if (w.valid) {
        windows.push(w);
      }
    }
    stats.windowCount = windows.length;
    return windows;
  }

  /** 在一个有效区间内求最优点：先黄金分割，再用 1 秒网格兜底，最后强校验双容差 */
  private static makeWindow(start: number, end: number, goal: SearchGoal, thresholds: LightThresholds,
    stats: KernelStats): ShootWindow {
    const w = new ShootWindow();
    w.startUtc = start;
    w.endUtc = end;
    w.valid = false;
    let bestT = start;
    let bestCost = Number.MAX_VALUE;
    // 粗选：整段按 ≤200 点取样（最长窗口也只需几十次调用）
    const span = end - start;
    const step = Math.max(ReverseSearchKernel.RESOLUTION_MS, Math.ceil(span / 200 / 1000) * 1000);
    for (let t = start; t < end; t += step) {
      if (!ReverseSearchKernel.validAt(t, goal, stats)) {
        continue;
      }
      const c = ReverseSearchKernel.normCost(t, goal, stats);
      if (c < bestCost) {
        bestCost = c;
        bestT = t;
      }
    }
    if (!Number.isFinite(bestCost)) {
      // 整段没有有效采样点（理论上不应发生）：用区间中点再验证一次
      if (!ReverseSearchKernel.validAt(start, goal, stats)) {
        return w;
      }
      bestCost = ReverseSearchKernel.normCost(start, goal, stats);
      bestT = start;
    }
    // 黄金分割细化（在有效区间内部；结论仍要过双容差）
    let lo = start;
    let hi = end - 1;
    const phi = 0.6180339887498949;
    for (let i = 0; i < 40 && hi - lo > ReverseSearchKernel.RESOLUTION_MS; i++) {
      const m1 = lo + Math.floor((hi - lo) * (1 - phi));
      const m2 = lo + Math.floor((hi - lo) * phi);
      const c1 = ReverseSearchKernel.validAt(m1, goal, stats)
        ? ReverseSearchKernel.normCost(m1, goal, stats) : Number.MAX_VALUE;
      const c2 = ReverseSearchKernel.validAt(m2, goal, stats)
        ? ReverseSearchKernel.normCost(m2, goal, stats) : Number.MAX_VALUE;
      if (c1 < c2) {
        hi = m2;
      } else {
        lo = m1;
      }
    }
    const cand = Math.max(start, Math.min(end - 1, Math.floor((lo + hi) / 2)));
    if (ReverseSearchKernel.validAt(cand, goal, stats)) {
      const c = ReverseSearchKernel.normCost(cand, goal, stats);
      if (c <= bestCost) {
        bestCost = c;
        bestT = cand;
      }
    }
    const p = ReverseSearchKernel.pos(bestT, stats);
    const azErr = SolarCalc.angularDistance(p.azimuthDeg, goal.azimuthTarget);
    const altErr = Math.abs(p.altitudeDeg - goal.altitudeTarget);
    if (!(azErr <= goal.azTolerance && altErr <= goal.altTolerance)) {
      return w; // 双容差强校验失败：不输出该窗口
    }
    if (goal.daylightOnly && !(p.altitudeDeg > -0.833)) {
      return w;
    }
    w.bestUtc = bestT;
    w.bestAzimuth = p.azimuthDeg;
    w.bestAltitude = p.altitudeDeg;
    w.bestAzError = azErr;
    w.bestAltError = altErr;
    w.phase = SolarCalc.phaseOf(p.altitudeDeg, thresholds);
    w.valid = true;
    w.degenerate = end - start <= ReverseSearchKernel.RESOLUTION_MS;
    return w;
  }

  /** 注入合成轨迹（仅测试用）；传 undefined 恢复真实太阳 */
  static setEvaluator(evaluator: SolarPositionEvaluator | undefined): void {
    ReverseSearchKernel.injected = evaluator;
    ReverseSearchKernel.cachedT = Number.NaN;
  }

  /**
   * 在单个 UTC 区间内搜索所有连续有效窗口。
   * 返回按 startUtc 升序排列的窗口数组。
   */
  static searchWindows(goal: SearchGoal, lat: number, lon: number, thresholds: LightThresholds,
    startUtc: number, endUtc: number, stats: KernelStats): ShootWindow[] {
    ReverseSearchKernel.goalRef = goal;
    ReverseSearchKernel.cachedT = Number.NaN;
    if (!Number.isFinite(startUtc) || !Number.isFinite(endUtc) || !(endUtc > startUtc)) {
      return [];
    }
    if (!Number.isFinite(lat) || !Number.isFinite(lon) || Math.abs(lat) > 90 || Math.abs(lon) > 180) {
      return [];
    }
    if (!Number.isFinite(goal.azTolerance) || !Number.isFinite(goal.altTolerance) ||
      goal.azTolerance < 0 || goal.altTolerance < 0) {
      return [];
    }
    const spans: number[] = [];
    ReverseSearchKernel.collect(startUtc, endUtc, goal, stats, 0, spans);
    const windows = ReverseSearchKernel.buildWindows(spans, goal, thresholds, stats);
    windows.sort((a: ShootWindow, b: ShootWindow) => a.startUtc - b.startUtc);
    return windows;
  }
}
