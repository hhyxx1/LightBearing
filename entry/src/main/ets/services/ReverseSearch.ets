import { SolarCalc, SunPosition, LightThresholds } from './SolarCalc';
import { Candidate, SearchGoal } from '../model/Models';
import { DayKind, LocalDayBounds } from './LocalTimeResolver';
import { ReverseSearchKernel } from './ReverseSearchKernel';
import { ShootWindow, KernelStats } from '../model/ShootWindow';

/**
 * 反向寻光：在日期区间内寻找满足「目标方位/高度 ± 容差」的时刻。
 *
 * 算法（与 PRD 第 5 节一致）：
 * 1. 逐日按 5 分钟粒度粗扫，用环形距离计算方位误差；
 * 2. 命中后在其邻域按 30s / 5s / 1s 逐级细化，取误差最小点；
 * 3. 相邻命中合并为同一时间窗口，仅保留该窗口内的最优解；
 * 4. 按总误差升序输出，附带误差、当地时间与阶段。
 *
 * 2B-2 起每个搜索日由 `DayRange` 表示真实本地日区间 [startUtc, endUtc)：
 * 夏令时切换日可能是 23/25/23.5/24.5 小时，绝不再假设 86400000。
 */
export class DayRange {
  startUtc: number = 0;
  endUtc: number = 0;

  static of(startUtc: number, endUtc: number): DayRange {
    const r = new DayRange();
    r.startUtc = startUtc;
    r.endUtc = endUtc;
    return r;
  }
}

/**
 * 一次搜索的区间规划结果。
 * 真正被整日跳过的日期可以安全跳过并计数；
 * 时区数据不可用或日期非法时必须报错，不能伪装成「搜索完成」。
 */
export class SearchPlan {
  ranges: DayRange[] = [];
  requestedDays: number = 0;
  /** 历史时区规则中该民用日确实不存在 */
  skippedDays: number = 0;
  /** 时区数据不可用（探针故障） */
  unavailableDays: number = 0;
  /** 日期/区间非法 */
  invalidDays: number = 0;
  /** 非空表示必须中止搜索 */
  errorText: string = '';

  static plan(days: LocalDayBounds[]): SearchPlan {
    const plan = new SearchPlan();
    plan.requestedDays = days.length;
    for (const b of days) {
      if (b.valid && b.endUtc > b.startUtc) {
        plan.ranges.push(DayRange.of(b.startUtc, b.endUtc));
      } else if (b.kind === DayKind.SKIPPED) {
        plan.skippedDays++;
      } else if (b.kind === DayKind.UNAVAILABLE) {
        plan.unavailableDays++;
      } else {
        plan.invalidDays++;
      }
    }
    if (plan.unavailableDays > 0) {
      plan.errorText = `有 ${plan.unavailableDays} 天的时区数据不可用，已中止搜索以避免不完整结果`;
    } else if (plan.invalidDays > 0) {
      plan.errorText = `有 ${plan.invalidDays} 天的日期边界非法，已中止搜索`;
    } else if (plan.ranges.length === 0) {
      plan.errorText = '所选日期范围内没有可搜索的本地日（全部被时区跳变跳过）';
    }
    return plan;
  }
}

export class ReverseSearch {
  /**
   * 按真实本地日区间搜索：每个**连续有效窗口**只返回一个最佳 Candidate。
   *
   * 2C-2 起内部改用 ReverseSearchKernel（自适应区间分类 + 1 秒边界 + 窗口构造），
   * 不再使用「5 分钟粗扫 + 命中才细化 + 10 分钟合并」。
   * 返回顺序保持旧语义：按 azError + altError 升序，并截断到 maxResults。
   */
  static searchInRanges(goal: SearchGoal, thresholds: LightThresholds, ranges: DayRange[]): Candidate[] {
    const windows: ShootWindow[] = ReverseSearch.searchWindowsInRanges(goal, thresholds, ranges,
      new KernelStats());
    const out: Candidate[] = [];
    for (const w of windows) {
      if (!w.valid) {
        continue;
      }
      out.push(Candidate.of(w.bestUtc, w.bestAzimuth, w.bestAltitude, w.bestAzError, w.bestAltError, w.phase));
    }
    out.sort((a: Candidate, b: Candidate) => (a.azError + a.altError) - (b.azError + b.altError));
    if (out.length > goal.maxResults) {
      return out.slice(0, goal.maxResults);
    }
    return out;
  }

  /**
   * 返回连续窗口模型（2C-2 主入口）：每个元素是一段 [startUtc, endUtc) 的真实有效时间。
   * 同一连续窗口只出现一次；窗口之间只要中间存在无效时间就保持独立（哪怕只隔 10 秒）。
   */
  static searchWindowsInRanges(goal: SearchGoal, thresholds: LightThresholds, ranges: DayRange[],
    stats: KernelStats): ShootWindow[] {
    const all: ShootWindow[] = [];
    for (const range of ranges) {
      if (!(range.endUtc > range.startUtc)) {
        continue; // 非法或空区间直接跳过，不猜测 24 小时
      }
      const part = ReverseSearchKernel.searchWindows(goal, goal.latWgs84, goal.lonWgs84, thresholds,
        range.startUtc, range.endUtc, stats);
      for (const w of part) {
        all.push(w);
      }
    }
    all.sort((a: ShootWindow, b: ShootWindow) => a.startUtc - b.startUtc);
    stats.windowCount = all.length;
    return all;
  }

  /**
   * 兼容接口：按「本地日零点列表」搜索。
   * 每个零点按 24 小时展开成区间，仅为旧调用方与既有测试保留；
   * 接入真实本地日的调用方必须用 searchInRanges() 传 [startUtc, endUtc)。
   */
  static search(goal: SearchGoal, thresholds: LightThresholds, dayStartsUtc: number[]): Candidate[] {
    const ranges: DayRange[] = [];
    for (const dayStart of dayStartsUtc) {
      ranges.push(DayRange.of(dayStart, dayStart + 86400000));
    }
    return ReverseSearch.searchInRanges(goal, thresholds, ranges);
  }
}
