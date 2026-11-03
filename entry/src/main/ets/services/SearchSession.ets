import { LightThresholds } from './SolarCalc';
import { SearchGoal } from '../model/Models';
import { ShootWindow, KernelStats } from '../model/ShootWindow';
import { KernelContext, KernelRunner, SolarPositionEvaluator } from './ReverseSearchKernel';
import { DayRange } from './ReverseSearch';

/** 搜索会话状态 */
export class SessionState {
  static readonly RUNNING: number = 0;
  static readonly DONE: number = 1;
  static readonly CANCELLED: number = 2;
  static readonly FAILED: number = 3;
  static readonly INVALID: number = 4;
}

/**
 * 可恢复的分片搜索会话（2C-3）。
 *
 * 为什么需要它：旧页面「一天一次同步调用」，一天内部的搜索无法被取消，365 天期间
 * 取消最坏要等一整天算完。这里用**显式区间栈**保存搜索进度，`step(budgetMs)` 在预算内推进，
 * 随时可以停下、让出一帧或响应取消；窗口在**每个区间完整处理完后**才聚合，
 * 因此不会把跨分片的一个连续窗口错误拆开。
 *
 * 上下文（目标、求值器、采样缓存、统计）全部是本会话私有的，多个会话交错推进互不影响。
 */
export class SearchSession {
  private ctx: KernelContext;
  private runner: KernelRunner;
  private ranges: DayRange[] = [];
  private stack: number[] = [];      // 展平的 [a, b, depth] 三元组
  private spanList: number[] = [];   // 当前区间的有效跨度
  private rangeIndex: number = 0;
  private windowsList: ShootWindow[] = [];
  private state: number = SessionState.RUNNING;
  private error: string = '';
  private processedMs: number = 0;
  private totalMs: number = 0;
  private currentRangeStartUtc: number = 0;
  private currentRangeEndUtc: number = 0;
  /** 当前区间是否处于运行状态（不能靠「有没有命中」判断） */
  private rangeActive: boolean = false;
  /** 当前区间开始时的非有限采样计数（用于识别不可靠区间） */
  private rangeNonFiniteStart: number = 0;
  private unreliableRanges: number = 0;
  /** 本次会话是否出现过无法可靠判断的区间（任何非有限太阳位置） */
  private unreliableData: boolean = false;

  constructor(goal: SearchGoal, thresholds: LightThresholds, ranges: DayRange[],
    evaluator?: SolarPositionEvaluator, stats?: KernelStats) {
    this.ctx = new KernelContext(goal, thresholds, evaluator, stats);
    this.runner = new KernelRunner(this.ctx);
    this.ranges = ranges;
    for (const r of ranges) {
      if (r.endUtc > r.startUtc) {
        this.totalMs += r.endUtc - r.startUtc;
      }
    }
    if (!Number.isFinite(goal.latWgs84) || !Number.isFinite(goal.lonWgs84) ||
      Math.abs(goal.latWgs84) > 90 || Math.abs(goal.lonWgs84) > 180) {
      this.state = SessionState.INVALID;
      this.error = '机位经纬度非法';
      return;
    }
    if (!Number.isFinite(goal.azTolerance) || !Number.isFinite(goal.altTolerance) ||
      goal.azTolerance < 0 || goal.altTolerance < 0) {
      this.state = SessionState.INVALID;
      this.error = '容差非法（必须为有限的非负数）';
      return;
    }
    if (!Number.isFinite(goal.azimuthTarget) || !Number.isFinite(goal.altitudeTarget) ||
      Math.abs(goal.altitudeTarget) > 90) {
      this.state = SessionState.INVALID;
      this.error = '目标角度非法';
      return;
    }
    if (ranges.length === 0 || this.totalMs <= 0) {
      this.state = SessionState.INVALID;
      this.error = '没有可搜索的时间区间';
    }
  }

  /** 当前状态（SessionState） */
  getState(): number {
    return this.state;
  }

  getError(): string {
    return this.error;
  }

  /** 因太阳位置非有限而无法判定的区间数量 */
  getUnreliableRanges(): number {
    return this.unreliableRanges;
  }

  /** 已完成的窗口（可能只是部分结果，配合 getState() 使用） */
  getWindows(): ShootWindow[] {
    return this.windowsList;
  }

  getStats(): KernelStats {
    return this.ctx.stats;
  }

  /** 进度 0–100：按已处理的真实 UTC 时间计算，而不是「完成几天」 */
  getProgressPercent(): number {
    if (this.totalMs <= 0) {
      return 100;
    }
    const p = Math.floor((this.processedMs * 100) / this.totalMs);
    return p < 0 ? 0 : (p > 100 ? 100 : p);
  }

  /** 当前正在搜索的区间（用于显示当地日期） */
  getCurrentRangeStartUtc(): number {
    return this.currentRangeStartUtc;
  }

  getCurrentRangeEndUtc(): number {
    return this.currentRangeEndUtc;
  }

  getRangeCount(): number {
    return this.ranges.length;
  }

  getRangeIndex(): number {
    return this.rangeIndex;
  }

  /** 取消：新的分片不再开始；当前已收集的窗口保留但标记为未完成 */
  cancel(): void {
    if (this.state === SessionState.RUNNING) {
      this.state = SessionState.CANCELLED;
    }
  }

  isFinished(): boolean {
    return this.state !== SessionState.RUNNING;
  }

  /** 结束当前区间：把跨度聚合成窗口并入结果 */
  private finishRange(): void {
    // 只要该区间出现过非有限太阳位置，本区间就不能被视为「可靠」
    // —— 与是否有有效跨度无关（修复：先前只在完全没有命中时才判失败）
    if (this.ctx.stats.nonFiniteSamples > this.rangeNonFiniteStart) {
      this.unreliableRanges++;
      this.unreliableData = true;
    }
    this.rangeActive = false;
    if (this.spanList.length > 0) {
      const part = this.runner.buildWindows(this.spanList);
      for (const w of part) {
        this.windowsList.push(w);
      }
      this.spanList = [];
    }
    this.rangeIndex++;
    this.stack = [];
  }

  /**
   * 推进搜索。
   * @param budgetMs 本次调用的时间预算（毫秒）；用完即返回，可安全重复调用
   * @returns 是否已经结束（完成 / 取消 / 失败）
   */
  step(budgetMs: number): boolean {
    if (this.state !== SessionState.RUNNING) {
      return true;
    }
    const started = Date.now();
    while (this.state === SessionState.RUNNING) {
      if (Date.now() - started >= budgetMs) {
        return false;
      }
      if (this.stack.length === 0) {
        // 上一段处理完 → 收尾并推进到下一段（依据区间运行状态，而不是有没有命中）
        if (this.rangeActive) {
          this.finishRange();
          if (this.state !== SessionState.RUNNING) {
            return true;
          }
        }
        if (this.rangeIndex >= this.ranges.length) {
          // 有不可靠区间 → 不能宣称完整完成；用户主动取消仍保持 CANCELLED
          if (this.unreliableData) {
            this.state = SessionState.FAILED;
            this.error = `有 ${this.unreliableRanges} 个搜索区间的太阳位置出现非有限值（NaN/Infinity），` +
              '结果不完整，不能判定为「没有拍摄机会」；请重新搜索或检查机位数据';
          } else {
            this.state = SessionState.DONE;
          }
          return true;
        }
        const r = this.ranges[this.rangeIndex];
        if (!(r.endUtc > r.startUtc)) {
          this.rangeIndex++;
          continue;
        }
        this.currentRangeStartUtc = r.startUtc;
        this.currentRangeEndUtc = r.endUtc;
        this.rangeActive = true;
        this.rangeNonFiniteStart = this.ctx.stats.nonFiniteSamples;
        this.stack.push(r.startUtc);
        this.stack.push(r.endUtc);
        this.stack.push(0);
        continue;
      }
      const depth = this.stack.pop() as number;
      const b = this.stack.pop() as number;
      const a = this.stack.pop() as number;
      if (!(b > a)) {
        continue;
      }
      const w = b - a;
      if (w <= KernelRunner.RESOLUTION_MS) {
        this.ctx.stats.resolutionLeaves++;
        if (this.runner.validAt(a)) {
          this.spanList.push(a);
          this.spanList.push(b);
        }
        this.processedMs += w;
        continue;
      }
      const cls = this.runner.classify(a, b);
      if (cls === 0) {
        this.processedMs += w;
        continue;
      }
      if (cls === 1) {
        this.spanList.push(a);
        this.spanList.push(b);
        this.processedMs += w;
        continue;
      }
      if (depth >= KernelRunner.MAX_DEPTH) {
        this.ctx.stats.unresolvedIntervals++;
        for (let t = a; t < b; t += KernelRunner.RESOLUTION_MS) {
          if (this.runner.validAt(t)) {
            this.spanList.push(t);
            this.spanList.push(Math.min(t + KernelRunner.RESOLUTION_MS, b));
          }
        }
        this.processedMs += w;
        continue;
      }
      const mid = a + Math.floor((b - a) / 2 / 1000) * 1000;
      if (!(mid > a && mid < b)) {
        this.stack.push(a);
        this.stack.push(b);
        this.stack.push(depth + 1);
        continue;
      }
      this.stack.push(mid);
      this.stack.push(b);
      this.stack.push(depth + 1);
      this.stack.push(a);
      this.stack.push(mid);
      this.stack.push(depth + 1);
    }
    return true;
  }

  /** 一次跑完（内部循环，仍受分片语义保护） */
  runToCompletion(budgetMs: number): void {
    let guard = 0;
    while (!this.step(budgetMs)) {
      guard++;
      if (guard > 100000) {
        this.state = SessionState.FAILED;
        this.error = '搜索未能在预算内收敛';
        break;
      }
    }
  }
}
