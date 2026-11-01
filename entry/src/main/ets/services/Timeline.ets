/**
 * 真实时间轴（纯逻辑，不依赖任何 Kit）。
 *
 * 图表横轴必须建立在「真实本地日区间 [startUtc, endUtc)」上，
 * 而不是 24 小时常量：夏令时切换日可能是 23 / 25 / 23.5 / 24.5 小时。
 * 采样与坐标映射全部做成可在宿主机测试的纯函数，避免必须跑 Canvas 才能验证数值。
 */

/** 时间轴模型 */
export class TimelineModel {
  startUtc: number = 0;
  endUtc: number = 0;
  durationMs: number = 0;
  valid: boolean = false;
  reason: string = '';

  /**
   * 归一化比例：区间内返回 [0, 1)；区间外（含 NaN / Infinity）返回 -1，
   * 调用方看到 -1 必须放弃绘制，不能拿它算坐标。
   */
  ratioOf(utcMs: number): number {
    if (!this.valid || !Number.isFinite(utcMs)) {
      return -1;
    }
    if (utcMs < this.startUtc || utcMs >= this.endUtc) {
      return -1;
    }
    return (utcMs - this.startUtc) / this.durationMs;
  }
}

export class Timeline {
  /** 由真实日界构造时间轴；非有限值或 end <= start 判为无效，绝不回退成 24 小时 */
  static fromBounds(startUtc: number, endUtc: number): TimelineModel {
    const m = new TimelineModel();
    if (!Number.isFinite(startUtc) || !Number.isFinite(endUtc)) {
      m.reason = '时间边界不是有限数值';
      return m;
    }
    if (!(endUtc > startUtc)) {
      m.reason = '时间区间为空或倒置';
      return m;
    }
    m.startUtc = startUtc;
    m.endUtc = endUtc;
    m.durationMs = endUtc - startUtc;
    m.valid = true;
    return m;
  }

  /**
   * 采样时刻：UTC 升序、包含起点、严格小于终点，绝不越过 endUtc。
   * 1970 年前的负时间戳是合法值，不做任何正负过滤。
   */
  static sampleTimes(model: TimelineModel, stepMs: number): number[] {
    const out: number[] = [];
    if (!model.valid || !Number.isFinite(stepMs) || stepMs <= 0) {
      return out;
    }
    for (let t = model.startUtc; t < model.endUtc; t += stepMs) {
      out.push(t);
    }
    if (out.length === 0) {
      out.push(model.startUtc);
    }
    // 末端留白过大时补一个点，保证曲线覆盖到接近 endUtc 的位置
    const last = out[out.length - 1];
    if (model.endUtc - 1 - last > stepMs * 0.5) {
      out.push(model.endUtc - 1);
    }
    return out;
  }

  /** 刻度比例：横轴语义是「本日已过去的真实时间比例」，按画布宽度决定密度 */
  static tickRatios(width: number): number[] {
    if (!Number.isFinite(width) || width < 260) {
      return [0, 0.25, 0.5, 0.75];
    }
    if (width >= 340) {
      return [0, 0.125, 0.25, 0.375, 0.5, 0.625, 0.75, 0.875];
    }
    return [0, 0.25, 0.5, 0.75];
  }

  /** 比例 → UTC 时刻；越界返回 -1（半开区间，末端取 endUtc - 1） */
  static utcAtRatio(model: TimelineModel, ratio: number): number {
    if (!model.valid || !Number.isFinite(ratio) || ratio < 0 || ratio > 1) {
      return -1;
    }
    const t = model.startUtc + Math.round(ratio * model.durationMs);
    return t < model.endUtc ? t : model.endUtc - 1;
  }

  /** 多日期对照的横轴标签（统一为「当地日期进度」，不冒充钟点） */
  static progressLabel(ratio: number): string {
    return `${Math.round(ratio * 100)}%`;
  }
}
