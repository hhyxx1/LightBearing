import { Timeline, TimelineModel, TimelinePoint } from './Timeline';
import { LocalResolveResult, LocalResolveStatus } from './LocalTimeResolver';
import { EventState } from './SolarCalc';

/**
 * 时间选择与保存校验的纯逻辑层（零 Kit 依赖）。
 *
 * 设计要点：
 * 1. Slider 操作的是「真实 UTC 时间轴上的归一化位置」，不再把 0..1439 直接当地钟点；
 * 2. 是否有有效值一律用显式 valid 表达，负数时间戳（1970 年前）完全合法；
 * 3. GAP / OVERLAP / INVALID / UNAVAILABLE 的 UI 决策与保存校验都在这里，便于宿主机单测。
 */

/** Slider 值结果：valid=false 表示当前时间轴不可用或时刻不在区间内 */
export class SliderValue {
  valid: boolean = false;
  value: number = 0;
}

/** Slider ↔ UTC 映射（区间 [startUtc, endUtc)，绝不包含 endUtc 本身） */
export class SliderMapping {
  /** Slider 的最大刻度（0..1000 对应 0..100%） */
  static readonly MAX: number = 1000;

  /** Slider 值 → UTC 时刻 */
  static toUtc(model: TimelineModel, value: number): TimelinePoint {
    const p = new TimelinePoint();
    if (!model.valid || !Number.isFinite(value)) {
      return p;
    }
    const clamped = Math.max(0, Math.min(SliderMapping.MAX, value));
    return Timeline.pointAtRatio(model, clamped / SliderMapping.MAX);
  }

  /** UTC 时刻 → Slider 值；不在区间内返回 valid=false */
  static toSlider(model: TimelineModel, utcMs: number): SliderValue {
    const v = new SliderValue();
    const ratio = model.ratioOf(utcMs);
    if (ratio < 0) {
      return v;
    }
    v.valid = true;
    v.value = Math.round(ratio * SliderMapping.MAX);
    return v;
  }
}

/** 计划时间选择状态（UI 决策用） */
export class PlanTimeSelection {
  /** LocalResolveStatus 之一 */
  status: number = LocalResolveStatus.UNIQUE;
  /** 候选 UTC（OVERLAP 时两个，按时间升序） */
  candidatesUtc: number[] = [];
  /** 与候选一一对应的偏移（毫秒，东为正） */
  candidateOffsets: number[] = [];
  /** 用户在 OVERLAP 中选定的候选下标；-1 表示尚未选择 */
  chosenIndex: number = -1;
  /** 面向用户的提示 */
  message: string = '';

  /** 当前是否已确定出唯一的 UTC 时刻 */
  isResolved(): boolean {
    if (this.status === LocalResolveStatus.UNIQUE) {
      return this.candidatesUtc.length === 1;
    }
    if (this.status === LocalResolveStatus.OVERLAP) {
      return this.chosenIndex >= 0 && this.chosenIndex < this.candidatesUtc.length;
    }
    return false;
  }

  /** 已确定的 UTC；未确定返回 NaN */
  utcMs(): number {
    if (!this.isResolved()) {
      return NaN;
    }
    return this.candidatesUtc[this.status === LocalResolveStatus.UNIQUE ? 0 : this.chosenIndex];
  }
}

/** 保存前校验结果 */
export class SaveCheck {
  ok: boolean = false;
  errorText: string = '';
}

export class TimeSelection {
  /** 把 resolveLocal() 的结果转成 UI 决策 */
  static fromResolve(result: LocalResolveResult): PlanTimeSelection {
    const sel = new PlanTimeSelection();
    sel.status = result.status;
    sel.candidatesUtc = result.candidatesUtc;
    sel.candidateOffsets = result.candidateOffsets;
    if (result.status === LocalResolveStatus.UNIQUE) {
      sel.chosenIndex = 0;
      sel.message = '';
    } else if (result.status === LocalResolveStatus.OVERLAP) {
      sel.chosenIndex = -1;
      sel.message = '该当地时间因夏令时回拨出现两次，请选择其中一个。';
    } else if (result.status === LocalResolveStatus.GAP) {
      // 缺口：不允许自动顺延到 03:00
      sel.chosenIndex = -1;
      sel.message = '该当地时间因夏令时切换而不存在，请重新选择。';
    } else if (result.status === LocalResolveStatus.UNAVAILABLE) {
      sel.chosenIndex = -1;
      sel.message = '机位时区数据不可用，无法确定该当地时间。';
    } else {
      sel.chosenIndex = -1;
      sel.message = '日期或时间无效，无法确定该当地时间。';
    }
    return sel;
  }

  /** 选择第 index 个候选（仅 OVERLAP 有意义）；返回该候选 UTC，越界返回 NaN */
  static choose(sel: PlanTimeSelection, index: number): number {
    if (sel.status !== LocalResolveStatus.OVERLAP) {
      return sel.utcMs();
    }
    if (index < 0 || index >= sel.candidatesUtc.length) {
      return NaN;
    }
    sel.chosenIndex = index;
    sel.message = '';
    return sel.candidatesUtc[index];
  }

  /**
   * 保存前最终校验：所有条件都满足才允许写入数据库。
   * @param selection 当前时间选择状态；编辑已有计划且未改时间时可传 null 表示沿用原 UTC
   */
  static validateForSave(selectedUtc: number, dayStartUtc: number, dayEndUtc: number,
    lat: number, lon: number, tzValid: boolean, selection: PlanTimeSelection | null): SaveCheck {
    const out = new SaveCheck();
    if (!Number.isFinite(selectedUtc)) {
      out.errorText = '所选时间无效，未保存。';
      return out;
    }
    if (!Number.isFinite(lat) || !Number.isFinite(lon) || Math.abs(lat) > 90 || Math.abs(lon) > 180) {
      out.errorText = '机位经纬度非法，未保存。';
      return out;
    }
    if (!tzValid) {
      out.errorText = '机位时区无效，未保存。';
      return out;
    }
    const model: TimelineModel = Timeline.fromBounds(dayStartUtc, dayEndUtc);
    if (!model.valid) {
      out.errorText = '当地日期边界不可用，未保存。';
      return out;
    }
    if (model.ratioOf(selectedUtc) < 0) {
      out.errorText = '所选时间不属于该当地日期，未保存。';
      return out;
    }
    if (selection !== null) {
      if (selection.status === LocalResolveStatus.GAP) {
        out.errorText = selection.message;
        return out;
      }
      if (selection.status === LocalResolveStatus.UNAVAILABLE || selection.status === LocalResolveStatus.INVALID) {
        out.errorText = selection.message;
        return out;
      }
      if (!selection.isResolved()) {
        out.errorText = '该当地时间对应两个时刻，请先选择其中一个再保存。';
        return out;
      }
      if (selection.utcMs() !== selectedUtc) {
        out.errorText = '当前时间与选择结果不一致，请重新确认时间。';
        return out;
      }
    }
    out.ok = true;
    return out;
  }
}

/**
 * 事件文案：把 EventState 翻译成用户可读的说明。
 * 关键点：OUTSIDE_DAY（事件在所选当地日之外）绝不写成「极夜/极昼」。
 */
export class EventText {
  /** @param formatted 已格式化的当地时间（AVAILABLE 时使用） */
  static describe(state: number, formatted: string): string {
    if (state === EventState.AVAILABLE) {
      return formatted;
    }
    if (state === EventState.OUTSIDE_DAY) {
      return '事件位于所选当地日期之外';
    }
    if (state === EventState.NO_CROSSING) {
      return '当日未穿越该高度阈值';
    }
    if (state === EventState.DAY_INVALID) {
      return '日期或时区数据不可用';
    }
    return formatted;
  }

  /** 窗口文案：有效返回区间文本，否则给原因 */
  static windowText(available: boolean, startText: string, endText: string): string {
    return available ? `${startText}-${endText}` : '无';
  }
}
