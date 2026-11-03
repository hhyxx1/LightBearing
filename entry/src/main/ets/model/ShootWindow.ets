/**
 * 连续拍摄窗口模型（2C-2）。
 *
 * 与旧 `Candidate` 的区别：窗口表达「一段连续满足双容差的真实 UTC 时间」，
 * 而 candidate 只是其中一个最优点。所有时间均为 UTC 毫秒；
 * 1970 年前的负时间戳是合法值，**不使用负数哨兵表示失败**，是否有效看 `valid`。
 */
export class ShootWindow {
  /** 半开区间 [startUtc, endUtc) */
  startUtc: number = 0;
  endUtc: number = 0;
  /** 窗口内综合误差最小的时刻 */
  bestUtc: number = 0;
  bestAzimuth: number = 0;
  bestAltitude: number = 0;
  bestAzError: number = 0;
  bestAltError: number = 0;
  /** LightPhase 值 */
  phase: number = 0;
  /** 窗口是否有效（false 表示该对象不承载有效窗口，例如构造失败） */
  valid: boolean = false;
  /**
   * 退化命中：只在某一瞬间刚好满足等号（切点）。
   * 此时 endUtc = startUtc + 1，避免零长度区间被当成无效。
   */
  degenerate: boolean = false;

  durationMs(): number {
    return this.endUtc - this.startUtc;
  }
}

/** 内核统计（只读，用于性能与可解释性） */
export class KernelStats {
  positionCalls: number = 0;
  maxDepth: number = 0;
  /** 细分到最大深度仍无法判定的区间数（诚实记录近似性） */
  unresolvedIntervals: number = 0;
  /** 经验判定为「整段有效」的区间数（依据变化率上界，不是形式化证明） */
  empiricalValidChunks: number = 0;
  /** 经验判定为「整段无效」被剪枝的区间数（依据变化率上界，不是形式化证明） */
  empiricalInvalidChunks: number = 0;
  /** 落到 1 秒分辨率叶子的数量（数值近似边界） */
  resolutionLeaves: number = 0;
  windowCount: number = 0;
}
