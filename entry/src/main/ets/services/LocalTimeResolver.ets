/**
 * 本地时间解析核心（纯算法，不依赖任何 Kit）。
 *
 * 为什么抽出来：宿主机单测环境里的 `@kit.LocalizationKit` 是空实现
 * （实测 `getTimeZone().getID()` 返回空串、`getOffset()` 返回 0），
 * 真实 IANA 数据只能在设备上验证。因此把「候选枚举 + 反向校验 + 日边界推导」
 * 做成不依赖时区实现的纯逻辑，由调用方注入 ZoneProbe：
 * - 宿主机单测注入合成时区，验证 GAP / OVERLAP / 23h / 25h / 整日跳过 等逻辑；
 * - 设备侧由 TimeUtil 用 i18n 实现真实探针，验证真实时区数据。
 */

/** 一次时区跳变 */
export class ZoneTransitionInfo {
  /** 跳变发生的 UTC 时刻（毫秒） */
  atUtc: number = 0;
  /** 跳变前偏移（毫秒，东为正） */
  offsetBefore: number = 0;
  /** 跳变后偏移（毫秒，东为正） */
  offsetAfter: number = 0;

  static of(atUtc: number, offsetBefore: number, offsetAfter: number): ZoneTransitionInfo {
    const t = new ZoneTransitionInfo();
    t.atUtc = atUtc;
    t.offsetBefore = offsetBefore;
    t.offsetAfter = offsetAfter;
    return t;
  }
}

/** 时区探针：由适配层注入（真实实现见 TimeUtil 的 i18n 适配器） */
export interface ZoneProbe {
  /** 该 UTC 时刻的偏移（毫秒，东为正）；非法时返回 NaN */
  offsetAt(utcMs: number): number;

  /** utcMs 之后的下一次跳变；没有跳变返回 undefined */
  transitionAfter(utcMs: number): ZoneTransitionInfo | undefined;

  /** 时区是否可用（非法 ID 必须为 false，不能被当作 UTC） */
  isValid(): boolean;
}

/** 本地时间解析状态 */
export enum LocalResolveStatus {
  /** 唯一对应一个真实 UTC 时刻 */
  UNIQUE = 0,
  /** 本地时间不存在（夏令时前跳） */
  GAP = 1,
  /** 本地时间对应两个 UTC 时刻（夏令时回拨） */
  OVERLAP = 2,
  /** 日期/时间/时区非法 */
  INVALID = 3
}

/** 本地时间解析结果 */
export class LocalResolveResult {
  status: number = LocalResolveStatus.INVALID;
  /** UTC 候选，按时间升序；UNIQUE 一个，OVERLAP 两个，GAP/INVALID 为空 */
  candidatesUtc: number[] = [];
  /** 与 candidatesUtc 一一对应的偏移（毫秒，东为正） */
  candidateOffsets: number[] = [];
  /** 面向 UI 的说明 */
  reason: string = '';
}

/** 本地日类型 */
export class DayKind {
  static readonly NORMAL: number = 0;
  static readonly SHORT: number = 1;
  static readonly LONG: number = 2;
  /** 整日被时区跳变跳过（如 2011-12-30 Pacific/Apia） */
  static readonly SKIPPED: number = 3;
  static readonly INVALID: number = 4;
}

/** 真实本地日边界 [startUtc, endUtc) */
export class LocalDayBounds {
  startUtc: number = -1;
  endUtc: number = -1;
  durationMs: number = 0;
  year: number = 0;
  month: number = 0;
  day: number = 0;
  valid: boolean = false;
  /** 见 DayKind */
  kind: number = DayKind.INVALID;
  reason: string = '';

  /** 时长（小时），便于展示与断言 */
  hours(): number {
    return this.durationMs / 3600000.0;
  }
}

const MS_PER_MINUTE: number = 60000.0;
const MS_PER_HOUR: number = 3600000.0;
const MS_PER_DAY: number = 86400000.0;

export class LocalTimeResolver {
  /** 公历闰年 */
  static isLeapYear(year: number): boolean {
    return (year % 4 === 0 && year % 100 !== 0) || year % 400 === 0;
  }

  /** 该年该月的天数；月份越界返回 0 */
  static daysInMonth(year: number, month: number): number {
    if (month < 1 || month > 12) {
      return 0;
    }
    const table: number[] = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    if (month === 2 && LocalTimeResolver.isLeapYear(year)) {
      return 29;
    }
    return table[month - 1];
  }

  /** 严格校验年月日（不允许 Date.UTC 把 2026-02-30 规范化成 03-02） */
  static isValidDate(year: number, month: number, day: number): boolean {
    if (!Number.isInteger(year) || !Number.isInteger(month) || !Number.isInteger(day)) {
      return false;
    }
    if (year < 1900 || year > 2200) {
      return false;
    }
    if (month < 1 || month > 12) {
      return false;
    }
    return day >= 1 && day <= LocalTimeResolver.daysInMonth(year, month);
  }

  /** 公历加一天 */
  static plusOneDay(year: number, month: number, day: number): number[] {
    const base = new Date(Date.UTC(year, month - 1, day));
    base.setUTCDate(base.getUTCDate() + 1);
    return [base.getUTCFullYear(), base.getUTCMonth() + 1, base.getUTCDate()];
  }

  /**
   * 解析本地时间：枚举候选偏移并反向校验。
   *
   * 不用「试探两次偏移」的做法，而是：
   * 1. 收集所有可能偏移（本地时刻前后 36 小时的偏移 + 邻近跳变的前后偏移）；
   * 2. 每个偏移给出候选 UTC = naive − offset；
   * 3. 反向校验：该 UTC 时刻的真实偏移必须等于该 offset，且换算回本地字段与输入完全一致；
   * 4. 按 UTC 升序去重，0 个 → GAP，1 个 → UNIQUE，2 个 → OVERLAP。
   */
  static resolve(probe: ZoneProbe, year: number, month: number, day: number,
    hour: number, minute: number): LocalResolveResult {
    const r = new LocalResolveResult();
    if (!probe.isValid()) {
      r.status = LocalResolveStatus.INVALID;
      r.reason = '时区不可用';
      return r;
    }
    if (!LocalTimeResolver.isValidDate(year, month, day)) {
      r.status = LocalResolveStatus.INVALID;
      r.reason = '日期非法';
      return r;
    }
    if (!Number.isInteger(hour) || !Number.isInteger(minute) || hour < 0 || hour > 23 || minute < 0 || minute > 59) {
      r.status = LocalResolveStatus.INVALID;
      r.reason = '时间非法';
      return r;
    }
    const naive = Date.UTC(year, month - 1, day, hour, minute, 0);
    const offsets: number[] = [];
    LocalTimeResolver.pushOffset(offsets, probe.offsetAt(naive - 36 * MS_PER_HOUR));
    LocalTimeResolver.pushOffset(offsets, probe.offsetAt(naive));
    LocalTimeResolver.pushOffset(offsets, probe.offsetAt(naive + 36 * MS_PER_HOUR));
    const near = probe.transitionAfter(naive - 3 * MS_PER_DAY);
    if (near !== undefined && near.atUtc <= naive + 3 * MS_PER_DAY) {
      LocalTimeResolver.pushOffset(offsets, near.offsetBefore);
      LocalTimeResolver.pushOffset(offsets, near.offsetAfter);
    }
    const later = probe.transitionAfter(naive);
    if (later !== undefined && later.atUtc <= naive + 3 * MS_PER_DAY) {
      LocalTimeResolver.pushOffset(offsets, later.offsetBefore);
      LocalTimeResolver.pushOffset(offsets, later.offsetAfter);
    }

    for (const offset of offsets) {
      const utc = naive - offset;
      if (probe.offsetAt(utc) !== offset) {
        continue;
      }
      if (!LocalTimeResolver.matchesLocalFields(utc, offset, year, month, day, hour, minute)) {
        continue;
      }
      r.candidatesUtc.push(utc);
      r.candidateOffsets.push(offset);
    }
    LocalTimeResolver.sortCandidates(r);

    if (r.candidatesUtc.length === 0) {
      r.status = LocalResolveStatus.GAP;
      r.reason = '该本地时间处于夏令时前跳的缺口内，不存在';
    } else if (r.candidatesUtc.length === 1) {
      r.status = LocalResolveStatus.UNIQUE;
      r.reason = '唯一对应';
    } else {
      r.status = LocalResolveStatus.OVERLAP;
      r.reason = '夏令时回拨导致该本地时间出现两次，已按 UTC 升序给出两个候选';
    }
    return r;
  }

  /**
   * 求本地日期的真实 UTC 边界 [startUtc, endUtc)。
   *
   * - 起点：该本地日实际存在的第一个时刻（00:00 可能被跳变吃掉，或被重复）；
   * - 终点：下一个存在的本地日的第一个时刻（跨过被整日跳过的日期）；
   * - 时长可能是 23 / 24 / 25 / 23.5 / 24.5 小时，绝不假设 24 小时；
   * - 整日被跳过时返回 valid=false, kind=SKIPPED，不映射到相邻日期。
   */
  static dayBounds(probe: ZoneProbe, year: number, month: number, day: number): LocalDayBounds {
    const b = new LocalDayBounds();
    b.year = year;
    b.month = month;
    b.day = day;
    if (!probe.isValid()) {
      b.valid = false;
      b.kind = DayKind.INVALID;
      b.reason = '时区不可用';
      return b;
    }
    if (!LocalTimeResolver.isValidDate(year, month, day)) {
      b.valid = false;
      b.kind = DayKind.INVALID;
      b.reason = '日期非法';
      return b;
    }
    const start = LocalTimeResolver.firstExistingInstant(probe, year, month, day);
    if (start < 0) {
      b.valid = false;
      b.kind = DayKind.SKIPPED;
      b.reason = '该本地日期被时区跳变整日跳过';
      return b;
    }
    let ny = year;
    let nm = month;
    let nd = day;
    let end = -1;
    for (let i = 0; i < 4 && end < 0; i++) {
      const nextDate: number[] = LocalTimeResolver.plusOneDay(ny, nm, nd);
      ny = nextDate[0];
      nm = nextDate[1];
      nd = nextDate[2];
      end = LocalTimeResolver.firstExistingInstant(probe, ny, nm, nd);
    }
    if (end < 0) {
      b.valid = false;
      b.kind = DayKind.INVALID;
      b.reason = '无法确定本地日结束边界';
      return b;
    }
    b.startUtc = start;
    b.endUtc = end;
    b.durationMs = end - start;
    b.valid = b.durationMs > 0;
    if (!b.valid) {
      b.kind = DayKind.INVALID;
      b.reason = '本地日边界不满足 start < end';
      return b;
    }
    if (b.durationMs < MS_PER_DAY) {
      b.kind = DayKind.SHORT;
      b.reason = `短日：${b.hours().toFixed(1)} 小时`;
    } else if (b.durationMs > MS_PER_DAY) {
      b.kind = DayKind.LONG;
      b.reason = `长日：${b.hours().toFixed(1)} 小时`;
    } else {
      b.kind = DayKind.NORMAL;
      b.reason = '常规 24 小时日';
    }
    return b;
  }

  /** 该本地日在真实时间上存在的第一个时刻；整日不存在返回 -1 */
  static firstExistingInstant(probe: ZoneProbe, year: number, month: number, day: number): number {
    const direct = LocalTimeResolver.resolve(probe, year, month, day, 0, 0);
    if (direct.status === LocalResolveStatus.UNIQUE || direct.status === LocalResolveStatus.OVERLAP) {
      return direct.candidatesUtc[0];
    }
    // 00:00 落在缺口里：先粗查几个时刻，全部缺失则说明整日被跳过
    const hourProbes: number[] = [6, 12, 18, 23];
    let anyValid = false;
    for (const h of hourProbes) {
      const r = LocalTimeResolver.resolve(probe, year, month, day, h, 0);
      if (r.status === LocalResolveStatus.UNIQUE || r.status === LocalResolveStatus.OVERLAP) {
        anyValid = true;
      }
    }
    if (!anyValid) {
      // 再确认 23:59 也不存在（避免遗漏只存在于最后几分钟的情形）
      const last = LocalTimeResolver.resolve(probe, year, month, day, 23, 59);
      if (last.status !== LocalResolveStatus.UNIQUE && last.status !== LocalResolveStatus.OVERLAP) {
        return -1;
      }
    }
    // 逐分钟找到第一个存在的时刻（只在罕见的午夜跳变日执行）
    for (let minutes = 1; minutes < 1440; minutes++) {
      const h = Math.floor(minutes / 60);
      const m = minutes % 60;
      const r = LocalTimeResolver.resolve(probe, year, month, day, h, m);
      if (r.status === LocalResolveStatus.UNIQUE || r.status === LocalResolveStatus.OVERLAP) {
        return r.candidatesUtc[0];
      }
    }
    return -1;
  }

  private static pushOffset(list: number[], value: number): void {
    if (!Number.isFinite(value)) {
      return;
    }
    if (list.indexOf(value) < 0) {
      list.push(value);
    }
  }

  /** 反向校验：utc + offset 的本地年月日时分是否与输入完全一致 */
  private static matchesLocalFields(utcMs: number, offsetMs: number, year: number, month: number,
    day: number, hour: number, minute: number): boolean {
    const local = new Date(utcMs + offsetMs);
    return local.getUTCFullYear() === year && local.getUTCMonth() + 1 === month &&
      local.getUTCDate() === day && local.getUTCHours() === hour && local.getUTCMinutes() === minute;
  }

  /** 候选按 UTC 升序，偏移同步换位 */
  private static sortCandidates(r: LocalResolveResult): void {
    for (let i = 1; i < r.candidatesUtc.length; i++) {
      let j = i;
      while (j > 0 && r.candidatesUtc[j - 1] > r.candidatesUtc[j]) {
        const tmpUtc = r.candidatesUtc[j - 1];
        r.candidatesUtc[j - 1] = r.candidatesUtc[j];
        r.candidatesUtc[j] = tmpUtc;
        const tmpOff = r.candidateOffsets[j - 1];
        r.candidateOffsets[j - 1] = r.candidateOffsets[j];
        r.candidateOffsets[j] = tmpOff;
        j--;
      }
    }
  }
}
