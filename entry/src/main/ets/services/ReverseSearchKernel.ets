import { SolarCalc, SunPosition, LightThresholds } from './SolarCalc';
import { SearchGoal } from '../model/Models';
import { ShootWindow, KernelStats } from '../model/ShootWindow';

/** 可注入的太阳位置求值器：默认用 SolarCalc，测试可注入合成轨迹 */
export interface SolarPositionEvaluator {
  positionAt(utcMs: number, latDeg: number, lonDeg: number): SunPosition;
}

/**
 * 单次搜索的私有上下文：目标、求值器、采样缓存、统计。
 *
 * 2C-3 起内核不再使用静态可变状态，避免并发/交错搜索互相污染
 * （旧版 cachedT / cachedPos / goalRef / injected 是进程级共享的）。
 */
export class KernelContext {
  goal: SearchGoal;
  latDeg: number;
  lonDeg: number;
  thresholds: LightThresholds;
  evaluator: SolarPositionEvaluator | undefined;
  stats: KernelStats;
  /** 采样缓存（本上下文私有） */
  cachedT: number = Number.NaN;
  cachedPos: SunPosition = new SunPosition();

  constructor(goal: SearchGoal, thresholds: LightThresholds, evaluator?: SolarPositionEvaluator,
    stats?: KernelStats) {
    this.goal = goal;
    this.latDeg = goal.latWgs84;
    this.lonDeg = goal.lonWgs84;
    this.thresholds = thresholds;
    this.evaluator = evaluator;
    this.stats = stats !== undefined ? stats : new KernelStats();
  }

  positionAt(utcMs: number): SunPosition {
    if (utcMs === this.cachedT) {
      return this.cachedPos;
    }
    this.stats.positionCalls++;
    const ev = this.evaluator;
    const p: SunPosition = ev !== undefined
      ? ev.positionAt(utcMs, this.latDeg, this.lonDeg)
      : SolarCalc.position(utcMs, this.latDeg, this.lonDeg);
    if (!Number.isFinite(p.azimuthDeg) || !Number.isFinite(p.altitudeDeg)) {
      this.stats.nonFiniteSamples++;
    }
    this.cachedT = utcMs;
    this.cachedPos = p;
    return p;
  }
}

/**
 * 反向寻光搜索内核（2C-2 实现，2C-3 改为上下文隔离）。
 *
 * 算法：自适应区间三态分类（经验性包络）+ 1 秒叶子判定 + 连续窗口聚合 + 窗口内最优点强校验。
 *
 * 关于「可证明」的措辞：分类依据是**经验性变化率上界**（高度 0.0045°/s、方位 0.05°/s，
 * 且方位仅在 |Δaz| ≤ 30°、高度 < 80° 时适用），不是形式化证明。统计字段因此命名为
 * `empiricalInvalidChunks` / `empiricalValidChunks`，并单独记录 `unresolvedIntervals`。
 */
export class KernelRunner {
  static readonly RESOLUTION_MS: number = 1000;
  static readonly MAX_DEPTH: number = 18;
  static readonly ALT_RATE_DEG_PER_SEC: number = 0.0045;
  static readonly AZ_RATE_DEG_PER_SEC: number = 0.05;
  static readonly AZ_CONTINUITY_LIMIT_DEG: number = 30.0;
  static readonly ZENITH_LIMIT_DEG: number = 80.0;

  ctx: KernelContext;

  constructor(ctx: KernelContext) {
    this.ctx = ctx;
  }

  private wrap180(deg: number): number {
    let v = deg % 360;
    if (v > 180) {
      v -= 360;
    }
    if (v < -180) {
      v += 360;
    }
    return v;
  }

  /** 单点是否满足所有条件（双容差独立 + 可选白昼严格不等式 + 有限性） */
  validAt(t: number): boolean {
    const goal = this.ctx.goal;
    const p = this.ctx.positionAt(t);
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

  /** 归一化代价：两轴各占容差的比例之和（零容差按 1 处理，避免除零） */
  normalizedCost(t: number): number {
    const goal = this.ctx.goal;
    const p = this.ctx.positionAt(t);
    const azErr = SolarCalc.angularDistance(p.azimuthDeg, goal.azimuthTarget);
    const altErr = Math.abs(p.altitudeDeg - goal.altitudeTarget);
    const azScale = goal.azTolerance > 0 ? goal.azTolerance : 1;
    const altScale = goal.altTolerance > 0 ? goal.altTolerance : 1;
    return azErr / azScale + altErr / altScale;
  }

  /** 区间三态分类：0 = 经验判定无效，1 = 经验判定整段有效，2 = 继续细分 */
  classify(a: number, b: number): number {
    const goal = this.ctx.goal;
    const stats = this.ctx.stats;
    const w = b - a;
    if (w <= 0) {
      return 0;
    }
    const widthSec = w / 1000;
    const mid = a + Math.floor(w / 2);
    const samples: number[] = [a, mid, b - 1];
    const poses: SunPosition[] = [];
    for (const t of samples) {
      poses.push(this.ctx.positionAt(t));
    }
    let azContinuous = true;
    for (let i = 1; i < poses.length; i++) {
      // 任意关键采样非有限 → 不能作为经验剪枝依据，一律继续细分（保守）
      if (!Number.isFinite(poses[i].altitudeDeg) || !Number.isFinite(poses[i - 1].altitudeDeg) ||
        !Number.isFinite(poses[i].azimuthDeg) || !Number.isFinite(poses[i - 1].azimuthDeg)) {
        return 2;
      }
      if (poses[i].altitudeDeg > KernelRunner.ZENITH_LIMIT_DEG ||
        poses[i - 1].altitudeDeg > KernelRunner.ZENITH_LIMIT_DEG) {
        azContinuous = false;
      }
      const dAz = Math.abs(this.wrap180(poses[i].azimuthDeg - poses[i - 1].azimuthDeg));
      if (dAz > KernelRunner.AZ_CONTINUITY_LIMIT_DEG) {
        azContinuous = false;
      }
    }
    const altMargin = KernelRunner.ALT_RATE_DEG_PER_SEC * widthSec * 0.5 + 1e-9;
    const azMargin = azContinuous ? KernelRunner.AZ_RATE_DEG_PER_SEC * widthSec * 0.5 + 1e-9 : 0;

    let allMust = true;
    let anyCan = false;
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
    if (!anyCan) {
      if (azContinuous) {
        stats.empiricalInvalidChunks++;
        return 0;
      }
      return 2;
    }
    if (allMust && azContinuous) {
      stats.empiricalValidChunks++;
      return 1;
    }
    return 2;
  }

  /** 收集一个区间内的有效跨度（成对的 [start, end)） */
  collectSpans(a: number, b: number, depth: number, spans: number[]): void {
    if (!(b > a)) {
      return;
    }
    if (depth > this.ctx.stats.maxDepth) {
      this.ctx.stats.maxDepth = depth;
    }
    if (b - a <= KernelRunner.RESOLUTION_MS) {
      this.ctx.stats.resolutionLeaves++;
      if (this.validAt(a)) {
        spans.push(a);
        spans.push(b);
      }
      return;
    }
    const cls = this.classify(a, b);
    if (cls === 0) {
      return;
    }
    if (cls === 1) {
      spans.push(a);
      spans.push(b);
      return;
    }
    if (depth >= KernelRunner.MAX_DEPTH) {
      this.ctx.stats.unresolvedIntervals++;
      for (let t = a; t < b; t += KernelRunner.RESOLUTION_MS) {
        if (this.validAt(t)) {
          spans.push(t);
          spans.push(Math.min(t + KernelRunner.RESOLUTION_MS, b));
        }
      }
      return;
    }
    const mid = a + Math.floor((b - a) / 2 / 1000) * 1000;
    if (!(mid > a && mid < b)) {
      this.collectSpans(a, b, depth + 1, spans);
      return;
    }
    this.collectSpans(a, mid, depth + 1, spans);
    this.collectSpans(mid, b, depth + 1, spans);
  }

  /** 跨度 → 窗口（相接/重叠视为同一窗口；中间有无效时间即分离） */
  buildWindows(spans: number[]): ShootWindow[] {
    const pairs: number[] = [];
    for (let i = 0; i + 1 < spans.length; i += 2) {
      pairs.push(spans[i]);
      pairs.push(spans[i + 1]);
    }
    // 按起点排序后合并（DFS 三分可能乱序）
    const order: number[] = [];
    for (let i = 0; i < pairs.length; i += 2) {
      order.push(i);
    }
    order.sort((x: number, y: number) => pairs[x] - pairs[y]);
    const merged: number[] = [];
    for (const idx of order) {
      const s = pairs[idx];
      const e = pairs[idx + 1];
      const n = merged.length;
      if (n > 0 && s <= merged[n - 1]) {
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
      const w = this.makeWindow(merged[i], merged[i + 1]);
      if (w.valid) {
        windows.push(w);
      }
    }
    return windows;
  }

  /** 窗口内求最优：≤200 点取样 + 黄金分割 + 双容差强校验 */
  makeWindow(start: number, end: number): ShootWindow {
    const goal = this.ctx.goal;
    const thresholds = this.ctx.thresholds;
    const w = new ShootWindow();
    w.startUtc = start;
    w.endUtc = end;
    w.valid = false;
    let bestT = start;
    let bestCost = Number.MAX_VALUE;
    const span = end - start;
    const step = Math.max(KernelRunner.RESOLUTION_MS, Math.ceil(span / 200 / 1000) * 1000);
    for (let t = start; t < end; t += step) {
      if (!this.validAt(t)) {
        continue;
      }
      const c = this.normalizedCost(t);
      if (c < bestCost) {
        bestCost = c;
        bestT = t;
      }
    }
    if (!Number.isFinite(bestCost)) {
      if (!this.validAt(start)) {
        return w;
      }
      bestCost = this.normalizedCost(start);
      bestT = start;
    }
    let lo = start;
    let hi = end - 1;
    const phi = 0.6180339887498949;
    for (let i = 0; i < 40 && hi - lo > KernelRunner.RESOLUTION_MS; i++) {
      const m1 = lo + Math.floor((hi - lo) * (1 - phi));
      const m2 = lo + Math.floor((hi - lo) * phi);
      const c1 = this.validAt(m1) ? this.normalizedCost(m1) : Number.MAX_VALUE;
      const c2 = this.validAt(m2) ? this.normalizedCost(m2) : Number.MAX_VALUE;
      if (c1 < c2) {
        hi = m2;
      } else {
        lo = m1;
      }
    }
    const cand = Math.max(start, Math.min(end - 1, Math.floor((lo + hi) / 2)));
    if (this.validAt(cand)) {
      const c = this.normalizedCost(cand);
      if (c <= bestCost) {
        bestCost = c;
        bestT = cand;
      }
    }
    const p = this.ctx.positionAt(bestT);
    const azErr = SolarCalc.angularDistance(p.azimuthDeg, goal.azimuthTarget);
    const altErr = Math.abs(p.altitudeDeg - goal.altitudeTarget);
    if (!(azErr <= goal.azTolerance && altErr <= goal.altTolerance)) {
      return w;
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
    w.degenerate = end - start <= KernelRunner.RESOLUTION_MS;
    return w;
  }

  /** 整段搜索（不可中断；分片搜索请用 SearchSession） */
  searchRange(startUtc: number, endUtc: number): ShootWindow[] {
    const spans: number[] = [];
    this.collectSpans(startUtc, endUtc, 0, spans);
    return this.buildWindows(spans);
  }
}

/** 兼容门面：保持 2C-2 的静态入口，内部构造独立上下文 */
export class ReverseSearchKernel {
  static readonly RESOLUTION_MS: number = KernelRunner.RESOLUTION_MS;
  static readonly MAX_DEPTH: number = KernelRunner.MAX_DEPTH;
  /** 兼容路径的默认注入求值器（仅测试使用；SearchSession 请显式传入） */
  private static defaultEvaluator: SolarPositionEvaluator | undefined = undefined;

  static setEvaluator(evaluator: SolarPositionEvaluator | undefined): void {
    ReverseSearchKernel.defaultEvaluator = evaluator;
  }

  static searchWindows(goal: SearchGoal, lat: number, lon: number, thresholds: LightThresholds,
    startUtc: number, endUtc: number, stats: KernelStats): ShootWindow[] {
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
    const ctx = new KernelContext(goal, thresholds, ReverseSearchKernel.defaultEvaluator, stats);
    return new KernelRunner(ctx).searchRange(startUtc, endUtc);
  }
}
