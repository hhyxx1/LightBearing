import { i18n } from '@kit.LocalizationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  DayKind, LocalDayBounds, LocalResolveResult, LocalResolveStatus, LocalTimeResolver,
  ZoneProbe, ZoneTransitionInfo
} from './LocalTimeResolver';

const DOMAIN = 0x1008;
const TAG = 'LB_TIME';

/** 本地时间字段 */
export class LocalParts {
  year: number = 1970;
  month: number = 1;
  day: number = 1;
  hour: number = 0;
  minute: number = 0;
  second: number = 0;
  /** 时区不可用时为 false，此时其余字段无意义 */
  valid: boolean = true;
}

function pad2(v: number): string {
  return v < 10 ? `0${v}` : `${v}`;
}

/** i18n 时区探针：把 Localization Kit 的接口适配成纯算法需要的 ZoneProbe */
class I18nZoneProbe implements ZoneProbe {
  private tzId: string = '';
  private valid: boolean = false;
  private zone: i18n.TimeZone | undefined = undefined;

  constructor(tzId: string) {
    this.tzId = tzId;
    this.valid = TimeUtil.isValidTimeZoneId(tzId);
    if (this.valid) {
      try {
        this.zone = i18n.getTimeZone(tzId);
      } catch (err) {
        this.valid = false;
      }
    }
  }

  isValid(): boolean {
    return this.valid;
  }

  offsetAt(utcMs: number): number {
    const zone = this.zone;
    if (!this.valid || zone === undefined) {
      return NaN;
    }
    try {
      return zone.getOffset(utcMs);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'getOffset failed tz=%{public}s', this.tzId);
      return NaN;
    }
  }

  transitionAfter(utcMs: number): ZoneTransitionInfo | undefined {
    const zone = this.zone;
    if (!this.valid || zone === undefined) {
      return undefined;
    }
    try {
      const rules = zone.getZoneRules();
      const transition = rules.nextTransition(utcMs);
      const at = transition.getMilliseconds();
      if (!(at > 0)) {
        // 官方文档：无夏令时或 raw offset 不变时返回 0
        return undefined;
      }
      return ZoneTransitionInfo.of(at, transition.getOffsetBefore(), transition.getOffsetAfter());
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'nextTransition failed tz=%{public}s', this.tzId);
      return undefined;
    }
  }
}

/**
 * 时区工具：内部一律以 UTC 毫秒存储，展示/输入时按 IANA 时区换算。
 *
 * 2B-1 起：
 * - `resolveLocal()` 明确区分 UNIQUE / GAP / OVERLAP / INVALID，不再靠两次偏移试探；
 * - `localDayBounds()` 给出真实本地日 [startUtc, endUtc)，时长可能是 23/24/25/23.5/24.5 小时；
 * - 非法时区不再静默当作 UTC（返回 NaN / INVALID，并可先用 isValidTimeZoneId 校验）。
 */
export class TimeUtil {
  private static availableIds: string[] = [];

  /** 系统当前时区 ID */
  static deviceTimeZoneId(): string {
    try {
      const id = i18n.getTimeZone().getID();
      return id.length > 0 ? id : 'UTC';
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'deviceTimeZoneId failed');
      return 'UTC';
    }
  }

  /** 时区列表（设置页选择用） */
  static availableTimeZones(): string[] {
    try {
      return i18n.TimeZone.getAvailableIDs();
    } catch (err) {
      const fallback: string[] = ['UTC', 'Asia/Shanghai', 'Asia/Tokyo', 'Europe/London', 'America/New_York'];
      return fallback;
    }
  }

  /** IANA 时区 ID 是否合法（空串、拼写错误一律 false，不做 UTC 兜底） */
  static isValidTimeZoneId(tzId: string): boolean {
    if (tzId.length === 0) {
      return false;
    }
    if (tzId === 'UTC') {
      return true;
    }
    if (TimeUtil.availableIds.length === 0) {
      try {
        TimeUtil.availableIds = i18n.TimeZone.getAvailableIDs();
      } catch (err) {
        return false;
      }
    }
    return TimeUtil.availableIds.indexOf(tzId) >= 0;
  }

  /** 指定时刻的时区偏移（毫秒，东为正）；时区非法返回 NaN */
  static offsetMs(tzId: string, utcMs: number): number {
    return new I18nZoneProbe(tzId).offsetAt(utcMs);
  }

  /** [startUtc, endUtc) 内的时区跳变（最多 4 次）；时区不可用时返回空数组 */
  static transitionsBetween(tzId: string, startUtc: number, endUtc: number): ZoneTransitionInfo[] {
    const out: ZoneTransitionInfo[] = [];
    const probe = new I18nZoneProbe(tzId);
    if (!probe.isValid() || !Number.isFinite(startUtc) || !Number.isFinite(endUtc) || !(endUtc > startUtc)) {
      return out;
    }
    let cursor = startUtc - 1;
    for (let i = 0; i < 4; i++) {
      const t = probe.transitionAfter(cursor);
      if (t === undefined || t.atUtc >= endUtc) {
        break;
      }
      if (t.atUtc >= startUtc) {
        out.push(t);
      }
      cursor = t.atUtc;
    }
    return out;
  }

  /** 解析本地时间：明确给出唯一/缺口/重复/非法四种结果 */
  static resolveLocal(tzId: string, year: number, month: number, day: number,
    hour: number, minute: number): LocalResolveResult {
    return LocalTimeResolver.resolve(new I18nZoneProbe(tzId), year, month, day, hour, minute);
  }

  /** 真实本地日边界 [startUtc, endUtc) */
  static localDayBounds(tzId: string, year: number, month: number, day: number): LocalDayBounds {
    return LocalTimeResolver.dayBounds(new I18nZoneProbe(tzId), year, month, day);
  }

  /** UTC 毫秒 → 本地时间字段；时区非法时 valid=false */
  static toLocal(tzId: string, utcMs: number): LocalParts {
    const p = new LocalParts();
    const offset = TimeUtil.offsetMs(tzId, utcMs);
    if (!Number.isFinite(offset)) {
      p.valid = false;
      return p;
    }
    const shifted = new Date(utcMs + offset);
    p.year = shifted.getUTCFullYear();
    p.month = shifted.getUTCMonth() + 1;
    p.day = shifted.getUTCDate();
    p.hour = shifted.getUTCHours();
    p.minute = shifted.getUTCMinutes();
    p.second = shifted.getUTCSeconds();
    return p;
  }

  /**
   * 本地时间字段 → UTC 毫秒（兼容旧签名，调用方无需改动）。
   *
   * 兼容策略（需要区分这些情形时请改用 resolveLocal）：
   * - UNIQUE：返回唯一候选；
   * - OVERLAP（回拨重复）：返回较早的一次（UTC 较小）；
   * - GAP（前跳缺失）：返回跳变后的第一个真实时刻（缺口结束瞬间），不静默平移到别的本地时间；
   * - INVALID（日期/时区非法）：返回 NaN。
   */
  static fromLocal(tzId: string, year: number, month: number, day: number, hour: number, minute: number): number {
    return LocalTimeResolver.toUtcCompat(new I18nZoneProbe(tzId), year, month, day, hour, minute);
  }

  /** 本地日期 00:00 对应的 UTC 毫秒（00:00 被跳变吃掉时取该日第一个存在的时刻） */
  static startOfLocalDay(tzId: string, utcMs: number): number {
    const p = TimeUtil.toLocal(tzId, utcMs);
    if (!p.valid) {
      return NaN;
    }
    const b = TimeUtil.localDayBounds(tzId, p.year, p.month, p.day);
    return b.valid ? b.startUtc : NaN;
  }

  /** 本地日期 +N 天的 00:00 对应的 UTC 毫秒 */
  static addLocalDays(tzId: string, utcMs: number, days: number): number {
    const p = TimeUtil.toLocal(tzId, utcMs);
    if (!p.valid) {
      return NaN;
    }
    return LocalTimeResolver.addLocalDayStart(new I18nZoneProbe(tzId), p.year, p.month, p.day, days);
  }

  /** HH:mm */
  static formatTime(tzId: string, utcMs: number): string {
    // 1970 年之前的合法时间戳是负数，不能用 < 0 判断无效
    if (!Number.isFinite(utcMs)) {
      return '--:--';
    }
    const p = TimeUtil.toLocal(tzId, utcMs);
    if (!p.valid) {
      return '--:--';
    }
    return `${pad2(p.hour)}:${pad2(p.minute)}`;
  }

  /** MM-DD */
  static formatDateShort(tzId: string, utcMs: number): string {
    const p = TimeUtil.toLocal(tzId, utcMs);
    if (!p.valid) {
      return '--';
    }
    return `${pad2(p.month)}-${pad2(p.day)}`;
  }

  /** YYYY-MM-DD */
  static formatDate(tzId: string, utcMs: number): string {
    const p = TimeUtil.toLocal(tzId, utcMs);
    if (!p.valid) {
      return '----';
    }
    return `${p.year}-${pad2(p.month)}-${pad2(p.day)}`;
  }

  /** YYYY-MM-DD HH:mm */
  static formatDateTime(tzId: string, utcMs: number): string {
    return `${TimeUtil.formatDate(tzId, utcMs)} ${TimeUtil.formatTime(tzId, utcMs)}`;
  }

  /** 本地星期（0=周日） */
  static weekday(tzId: string, utcMs: number): number {
    const p = TimeUtil.toLocal(tzId, utcMs);
    if (!p.valid) {
      return 0;
    }
    return new Date(Date.UTC(p.year, p.month - 1, p.day)).getUTCDay();
  }

  /** 星期中文名 */
  static weekdayLabel(weekday: number): string {
    const names: string[] = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];
    const idx = ((weekday % 7) + 7) % 7;
    return names[idx];
  }

  /** 时区偏移展示，如 UTC+08:00；非法时区显示 UTC? */
  static offsetLabel(tzId: string, utcMs: number): string {
    const offset = TimeUtil.offsetMs(tzId, utcMs);
    if (!Number.isFinite(offset)) {
      return 'UTC?';
    }
    const sign = offset < 0 ? '-' : '+';
    const abs = Math.abs(offset);
    const hours = Math.floor(abs / 3600000.0);
    const minutes = Math.floor((abs % 3600000.0) / 60000.0);
    return `UTC${sign}${pad2(hours)}:${pad2(minutes)}`;
  }

  /** 现在（可注入以便测试） */
  static now(): number {
    return new Date().getTime();
  }
}
