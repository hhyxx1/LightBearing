import { SolarCalc, SunPosition, LightThresholds } from './SolarCalc';
import { Candidate, SearchGoal } from '../model/Models';
import { DayKind, LocalDayBounds } from './LocalTimeResolver';
import { ReverseSearchKernel, KernelContext, KernelRunner, SolarPositionEvaluator } from './ReverseSearchKernel';
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

/** 结果排序模式 */
export class WindowSortMode {
  /** 模式 A：全局最精确匹配（默认） */
  static readonly BEST: number = 0;
  /** 模式 B：时间分布优先（可选策略，UI 暂不启用） */
  static readonly DISTRIBUTION: number = 1;
}

/** 全局窗口搜索结果 */
export class SearchOutcome {
  windows: ShootWindow[] = [];
  /** 截断前的窗口总数 */
  totalBeforeCut: number = 0;
  stats: KernelStats = new KernelStats();
  /** 空字符串表示成功；非空为拒绝原因 */
  errorText: string = '';
  /** 是否未跑完（取消/预算耗尽） */
  incomplete: boolean = false;
  /** 后处理阶段被拒绝的窗口数（位置与双容差不一致、best 越界等） */
  droppedInvalid: number = 0;
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

  /**
   * 全局窗口后处理（2C-3）：跨区间衔接 + 去重 + 统一评分 + 有界 Top-K。
   *
   * - 相邻区间的窗口若在 UTC 上真正相接（无真实时间缺口）则合并为同一窗口；
   *   被跳过/不可用的日期会形成真实缺口，因此不会被跨空白合并；
   * - 合并后边界变化，best 点会用同一套内核重新求并**再次校验双容差**；
   * - 评分统一为归一化相对误差 `azErr/azTol + altErr/altTol`（零容差按 1 处理），
   *   同分按 bestUtc 升序，保证可复现；
   * - 截断使用有界插入，不会在排序第二遍之前丢掉可能进入 Top-K 的窗口。
   */
  static finalizeWindows(goal: SearchGoal, thresholds: LightThresholds, raw: ShootWindow[],
    mode: number, maxResults: number, evaluator?: SolarPositionEvaluator,
    stats?: KernelStats, ranges?: DayRange[]): SearchOutcome {
    const out = new SearchOutcome();
    out.stats = stats !== undefined ? stats : new KernelStats();
    if (!Number.isInteger(maxResults) || maxResults < 1 || maxResults > 1000) {
      out.errorText = 'maxResults 必须是 1–1000 的整数';
      return out;
    }
    const sorted = raw.slice();
    sorted.sort((a: ShootWindow, b: ShootWindow) => a.startUtc - b.startUtc);
    // 跨区间衔接：只在真正相接/重叠时合并（缺口绝不跨过）
    const merged: ShootWindow[] = [];
    for (const w of sorted) {
      if (!w.valid) {
        continue;
      }
      const last = merged.length > 0 ? merged[merged.length - 1] : undefined;
      // 只有真正相接（半开区间首尾重合）或重叠才合并；1ms 及以上的间隔是真实无效时间，不合并
      if (last !== undefined && w.startUtc <= last.endUtc) {
        last.endUtc = Math.max(last.endUtc, w.endUtc);
        last.valid = false; // 边界变了，需要重新求 best
      } else {
        const copy = new ShootWindow();
        copy.startUtc = w.startUtc;
        copy.endUtc = w.endUtc;
        copy.bestUtc = w.bestUtc;
        copy.bestAzimuth = w.bestAzimuth;
        copy.bestAltitude = w.bestAltitude;
        copy.bestAzError = w.bestAzError;
        copy.bestAltError = w.bestAltError;
        copy.phase = w.phase;
        copy.valid = true;
        copy.degenerate = w.degenerate;
        merged.push(copy);
      }
    }
    const ctx = new KernelContext(goal, thresholds, evaluator, out.stats);
    const runner = new KernelRunner(ctx);
    const finalWindows: ShootWindow[] = [];
    for (const w of merged) {
      if (!w.valid) {
        const rechecked = runner.makeWindow(w.startUtc, w.endUtc);
        if (rechecked.valid) {
          finalWindows.push(rechecked);
        }
        continue;
      }
      // 未合并的窗口也再校验一次（best 必须在窗口内且双容差成立）
      if (w.bestUtc < w.startUtc || w.bestUtc >= w.endUtc) {
        const rechecked = runner.makeWindow(w.startUtc, w.endUtc);
        if (rechecked.valid) {
          finalWindows.push(rechecked);
        }
        continue;
      }
      finalWindows.push(w);
    }
    // 逐个复验：best 时刻的实际太阳位置必须与声明的误差一致，且满足双容差
    const verified: ShootWindow[] = [];
    for (const w of finalWindows) {
      const p = ctx.positionAt(w.bestUtc);
      let ok = Number.isFinite(p.azimuthDeg) && Number.isFinite(p.altitudeDeg) &&
        w.bestUtc >= w.startUtc && w.bestUtc < w.endUtc;
      if (ok) {
        const azErr = SolarCalc.angularDistance(p.azimuthDeg, goal.azimuthTarget);
        const altErr = Math.abs(p.altitudeDeg - goal.altitudeTarget);
        ok = azErr <= goal.azTolerance && altErr <= goal.altTolerance &&
          (!goal.daylightOnly || p.altitudeDeg > -0.833);
        if (ok) {
          // 用真实位置覆盖声明值，避免上游传入不一致的误差
          w.bestAzimuth = p.azimuthDeg;
          w.bestAltitude = p.altitudeDeg;
          w.bestAzError = azErr;
          w.bestAltError = altErr;
        }
      }
      if (!ok) {
        const rechecked = runner.makeWindow(w.startUtc, w.endUtc);
        if (rechecked.valid) {
          verified.push(rechecked);
        } else {
          out.droppedInvalid++;
        }
        continue;
      }
      verified.push(w);
    }
    finalWindows.length = 0;
    for (const w of verified) {
      finalWindows.push(w);
    }
    out.totalBeforeCut = finalWindows.length;
    const scoreOf = (w: ShootWindow): number => {
      const azScale = goal.azTolerance > 0 ? goal.azTolerance : 1;
      const altScale = goal.altTolerance > 0 ? goal.altTolerance : 1;
      return w.bestAzError / azScale + w.bestAltError / altScale;
    };
    const better = (a: ShootWindow, b: ShootWindow): boolean => {
      const ca = scoreOf(a);
      const cb = scoreOf(b);
      if (ca !== cb) {
        return ca < cb;
      }
      return a.bestUtc < b.bestUtc;
    };
    if (mode === WindowSortMode.DISTRIBUTION) {
      // 模式 B：按所属区间（本地日）分组后轮流取，保证不同日期都有机会
      const groupOf = (w: ShootWindow): number => {
        const rs = ranges;
        if (rs === undefined) {
          return 0;
        }
        for (let i = 0; i < rs.length; i++) {
          if (w.startUtc >= rs[i].startUtc && w.startUtc < rs[i].endUtc) {
            return i;
          }
        }
        return rs.length;
      };
      const map: Map<number, ShootWindow[]> = new Map<number, ShootWindow[]>();
      for (const w of finalWindows) {
        const g = groupOf(w);
        const arr = map.get(g);
        if (arr === undefined) {
          map.set(g, [w]);
        } else {
          arr.push(w);
        }
      }
      const keys: number[] = [];
      map.forEach((value: ShootWindow[], key: number) => {
        keys.push(key);
        value.sort((a: ShootWindow, b: ShootWindow) => (better(a, b) ? -1 : 1));
      });
      keys.sort((a: number, b: number) => a - b);
      const picked: ShootWindow[] = [];
      let round = 0;
      while (picked.length < maxResults) {
        let added = false;
        for (const k of keys) {
          const arr = map.get(k);
          if (arr === undefined || round >= arr.length) {
            continue;
          }
          picked.push(arr[round]);
          added = true;
          if (picked.length >= maxResults) {
            break;
          }
        }
        if (!added) {
          break;
        }
        round++;
      }
      out.windows = picked;
      return out;
    }
    // 模式 A：有界插入 Top-K
    const top: ShootWindow[] = [];
    for (const w of finalWindows) {
      if (top.length >= maxResults && !better(w, top[top.length - 1])) {
        continue;
      }
      let pos = top.length;
      while (pos > 0 && better(w, top[pos - 1])) {
        pos--;
      }
      top.splice(pos, 0, w);
      if (top.length > maxResults) {
        top.pop();
      }
    }
    out.windows = top;
    return out;
  }
}
