import { LightWindow, WindowState } from './SolarCalc';

/**
 * 观测仪表的真实时段区间（纯逻辑，便于宿主机测试）。
 *
 * 只把**真实计算出的窗口**转成 UTC 对（start, end），绝不生成装饰性比例条：
 * 窗口不可用（ABSENT / NO_CROSSING / 区间非法）时直接跳过，不猜测时间。
 */
export class ObservationBands {
  /** 黄金时段（晨 + 夕）→ 扁平 [start0,end0,start1,end1,...] */
  static goldenPairs(w: LightWindow): number[] {
    const out: number[] = [];
    if (!w.dayValid) {
      return out;
    }
    ObservationBands.pushRange(out, w.goldenMorningState, w.goldenMorningStartUtc, w.goldenMorningEndUtc);
    ObservationBands.pushRange(out, w.goldenEveningState, w.goldenEveningStartUtc, w.goldenEveningEndUtc);
    return out;
  }

  /** 蓝调时段（晨 + 夕） */
  static bluePairs(w: LightWindow): number[] {
    const out: number[] = [];
    if (!w.dayValid) {
      return out;
    }
    ObservationBands.pushRange(out, w.blueMorningState, w.blueMorningStartUtc, w.blueMorningEndUtc);
    ObservationBands.pushRange(out, w.blueEveningState, w.blueEveningStartUtc, w.blueEveningEndUtc);
    return out;
  }

  /**
   * 收录规则（UI-1B-R 修正）：
   * - 只凭 **WindowState 显式状态** 判断窗口是否存在，不再用时间戳正负号；
   * - 负 Unix 毫秒是 1970 年以前的合法 UTC（含跨 Epoch 的窗口），必须允许；
   * - 仍拒绝：状态非 AVAILABLE、非有限值、逆序或零长度。
   */
  private static pushRange(out: number[], state: number, startUtc: number, endUtc: number): void {
    if (state !== WindowState.AVAILABLE) {
      return;
    }
    if (!Number.isFinite(startUtc) || !Number.isFinite(endUtc)) {
      return;
    }
    if (!(endUtc > startUtc)) {
      return;
    }
    out.push(startUtc);
    out.push(endUtc);
  }

  /**
   * 把 UTC 区间裁剪进当地日 [dayStart, dayEnd)，并返回可绘制比例对。
   * 返回空数组表示没有任何可绘制区间（而不是回退到固定比例）。
   */
  static clippedPairs(pairs: number[], dayStartUtc: number, dayEndUtc: number): number[] {
    const out: number[] = [];
    if (!(dayEndUtc > dayStartUtc)) {
      return out;
    }
    for (let i = 0; i + 1 < pairs.length; i += 2) {
      const s = Math.max(pairs[i], dayStartUtc);
      const e = Math.min(pairs[i + 1], dayEndUtc);
      if (e > s) {
        out.push(s);
        out.push(e);
      }
    }
    return out;
  }
}
