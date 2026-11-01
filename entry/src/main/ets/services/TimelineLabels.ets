import { TimeUtil } from './TimeUtil';
import { Timeline, TimelineModel } from './Timeline';

/** 一个刻度：UTC 时刻 + 归一化比例 + 本地时钟标签 */
export class TimelineTick {
  utcMs: number = 0;
  ratio: number = 0;
  label: string = '';
}

/**
 * 时间轴刻度标签（依赖 i18n，不能在宿主机单测里跑，见设备测试）。
 *
 * 原则：
 * 1. 横轴内部始终是 UTC 连续时间，标签只做 UTC → 本地 的转换；
 * 2. 不存在「从一个不存在的本地时间反推 UTC」，因此 DST 缺口不会凭空出现 02:30 之类的刻度；
 * 3. DST 回拨造成的重复本地时刻用偏移后缀区分，两个 01:30 各自对应唯一的 UTC 与唯一 x 坐标。
 */
export class TimelineLabels {
  /** 生成刻度；无效时间轴返回空数组 */
  static ticks(model: TimelineModel, tzId: string, width: number): TimelineTick[] {
    const out: TimelineTick[] = [];
    if (!model.valid) {
      return out;
    }
    const ratios: number[] = Timeline.tickRatios(width);
    for (const ratio of ratios) {
      const utcMs = Timeline.utcAtRatio(model, ratio);
      if (utcMs < 0 && ratio !== 0) {
        continue;
      }
      const tick = new TimelineTick();
      tick.utcMs = utcMs;
      tick.ratio = ratio;
      tick.label = TimelineLabels.formatLocal(utcMs, tzId);
      out.push(tick);
    }
    return TimelineLabels.disambiguate(out, tzId);
  }

  /** UTC → 本地 HH:mm；时区不可用返回「--:--」 */
  static formatLocal(utcMs: number, tzId: string): string {
    const parts = TimeUtil.toLocal(tzId, utcMs);
    if (!parts.valid) {
      return '--:--';
    }
    const hh = parts.hour < 10 ? `0${parts.hour}` : `${parts.hour}`;
    const mm = parts.minute < 10 ? `0${parts.minute}` : `${parts.minute}`;
    return `${hh}:${mm}`;
  }

  /** 本地时刻重复（DST 回拨）时追加偏移后缀，如 01:30(-4) 与 01:30(-5) */
  static disambiguate(ticks: TimelineTick[], tzId: string): TimelineTick[] {
    const counts: Map<string, number> = new Map<string, number>();
    for (const t of ticks) {
      const n = counts.get(t.label);
      counts.set(t.label, n === undefined ? 1 : n + 1);
    }
    for (const t of ticks) {
      const n = counts.get(t.label);
      if (n !== undefined && n > 1) {
        t.label = `${t.label}(${TimelineLabels.offsetShort(t.utcMs, tzId)})`;
      }
    }
    return ticks;
  }

  /** 偏移的短表示：+8 / -4 / +5.5 */
  static offsetShort(utcMs: number, tzId: string): string {
    const offset = TimeUtil.offsetMs(tzId, utcMs);
    if (!Number.isFinite(offset)) {
      return '?';
    }
    const hours = offset / 3600000.0;
    const sign = hours < 0 ? '-' : '+';
    const abs = Math.abs(hours);
    const whole = Math.floor(abs);
    const half = abs - whole > 0.25 ? '.5' : '';
    return `${sign}${whole}${half}`;
  }
}
