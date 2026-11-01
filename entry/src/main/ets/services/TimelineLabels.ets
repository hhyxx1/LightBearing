import { TimeUtil } from './TimeUtil';
import { Timeline, TimelineModel, TimelinePoint } from './Timeline';
import { ZoneTransitionInfo } from './LocalTimeResolver';

/** 一个刻度：UTC 时刻 + 归一化比例 + 本地时钟标签 */
export class TimelineTick {
  utcMs: number = 0;
  ratio: number = 0;
  label: string = '';
  /** 是否为夏令时切换标记（用于占据位置、避免与常规刻度文字重叠） */
  isTransition: boolean = false;
}

/** 常规刻度与 DST 标记之间的最小像素间距 */
const MIN_LABEL_GAP_PX: number = 46.0;

/**
 * 时间轴刻度标签（依赖 i18n，跑在设备侧用例里）。
 *
 * 原则：
 * 1. 横轴内部始终是 UTC 连续时间，标签只做 UTC → 本地 转换；
 * 2. 不从「不存在的本地时间」反推 UTC，因此 DST 缺口不会凭空出现 02:30 之类的刻度；
 * 3. 时间有效性用 TimelinePoint 的显式状态判断，1970 年前的负时间戳（含 -1）完全合法；
 * 4. DST 回拨造成的重复本地时刻用偏移后缀区分；当天确有跳变时额外插入一个切换标记，
 *    并挤掉距离过近的常规刻度，保证用户能感知「今天有重复/缺失的小时」且文字不重叠。
 */
export class TimelineLabels {
  /** 生成刻度；无效时间轴返回空数组 */
  static ticks(model: TimelineModel, tzId: string, width: number): TimelineTick[] {
    const out: TimelineTick[] = [];
    if (!model.valid || !(width > 0)) {
      return out;
    }
    const ratios: number[] = Timeline.tickRatios(width);
    for (const ratio of ratios) {
      const point: TimelinePoint = Timeline.pointAtRatio(model, ratio);
      if (!point.valid) {
        continue;
      }
      const tick = new TimelineTick();
      tick.utcMs = point.utcMs;
      tick.ratio = ratio;
      tick.label = TimelineLabels.formatLocal(point.utcMs, tzId);
      out.push(tick);
    }

    // 当天的时区跳变：插入切换标记（DST→偏移），让重复/缺失小时在图上可感知
    const transitions: ZoneTransitionInfo[] = TimeUtil.transitionsBetween(tzId, model.startUtc, model.endUtc);
    for (const t of transitions) {
      const ratio = model.ratioOf(t.atUtc);
      if (ratio < 0) {
        continue;
      }
      const marker = new TimelineTick();
      marker.utcMs = t.atUtc;
      marker.ratio = ratio;
      marker.isTransition = true;
      marker.label = `DST${TimelineLabels.offsetSigned(t.offsetAfter)}`;
      out.push(marker);
    }

    out.sort((a: TimelineTick, b: TimelineTick) => a.utcMs - b.utcMs);
    const spaced: TimelineTick[] = TimelineLabels.dropOverlaps(out, width);
    return TimelineLabels.disambiguate(spaced, tzId);
  }

  /** 与 DST 标记过近的常规刻度让位：标记前后**双向**避让，并按标记实际宽度估算间距 */
  private static dropOverlaps(ticks: TimelineTick[], width: number): TimelineTick[] {
    const usable = Math.max(1, width - 16);
    const markers: TimelineTick[] = [];
    for (const t of ticks) {
      if (t.isTransition) {
        markers.push(t);
      }
    }
    const keep: TimelineTick[] = [];
    for (const t of ticks) {
      if (t.isTransition) {
        keep.push(t);
        continue;
      }
      let blocked = false;
      for (const m of markers) {
        if (Math.abs(m.ratio - t.ratio) * usable < TimelineLabels.markerGapPx(m.label)) {
          blocked = true;
          break;
        }
      }
      if (!blocked) {
        keep.push(t);
      }
    }
    return keep;
  }

  /** DST 标记的占位宽度（等宽近似估算），保证 DST+05:45 之类的长文本不被裁切 */
  static markerGapPx(label: string): number {
    const estimated = 10.0 + label.length * 7.4;
    return Math.max(MIN_LABEL_GAP_PX, estimated);
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

  /** 本地时刻重复（DST 回拨）时追加偏移后缀，如 01:30(+11:00) 与 01:30(+10:30) */
  static disambiguate(ticks: TimelineTick[], tzId: string): TimelineTick[] {
    const counts: Map<string, number> = new Map<string, number>();
    for (const t of ticks) {
      const n = counts.get(t.label);
      counts.set(t.label, n === undefined ? 1 : n + 1);
    }
    for (const t of ticks) {
      const n = counts.get(t.label);
      if (n !== undefined && n > 1) {
        t.label = `${t.label}(${TimelineLabels.offsetSigned(TimeUtil.offsetMs(tzId, t.utcMs))})`;
      }
    }
    return ticks;
  }

  /**
   * 偏移文本：一律用毫秒计算符号/小时/分钟，支持 45 分钟时区。
   * 例：UTC+08:00、UTC-04:00、UTC+05:45、UTC+12:45、UTC+00:00；非法输入返回 UTC?
   */
  static offsetText(offsetMs: number): string {
    if (!Number.isFinite(offsetMs)) {
      return 'UTC?';
    }
    return `UTC${TimelineLabels.offsetSigned(offsetMs)}`;
  }

  /** 带符号的 HH:MM（+05:45 / -04:00 / +00:00） */
  static offsetSigned(offsetMs: number): string {
    if (!Number.isFinite(offsetMs)) {
      return '?';
    }
    const totalMinutes = Math.round(Math.abs(offsetMs) / 60000.0);
    const sign = offsetMs < 0 ? '-' : '+';
    const hh = Math.floor(totalMinutes / 60);
    const mm = totalMinutes % 60;
    const hhText = hh < 10 ? `0${hh}` : `${hh}`;
    const mmText = mm < 10 ? `0${mm}` : `${mm}`;
    return `${sign}${hhText}:${mmText}`;
  }
}
