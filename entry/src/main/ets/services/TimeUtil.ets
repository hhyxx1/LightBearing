import { i18n } from '@kit.LocalizationKit';

/** 本地时间字段 */
export class LocalParts {
  year: number = 1970;
  month: number = 1;
  day: number = 1;
  hour: number = 0;
  minute: number = 0;
  second: number = 0;
}

function pad2(v: number): string {
  return v < 10 ? `0${v}` : `${v}`;
}

/**
 * 时区工具：内部一律以 UTC 毫秒存储，展示/输入时按 IANA 时区字段换算。
 * 使用 i18n.TimeZone.getOffset(date)（含夏令时），避免自算时区表。
 */
export class TimeUtil {
  /** 系统当前时区 ID，如 Asia/Shanghai */
  static deviceTimeZoneId(): string {
    try {
      return i18n.getTimeZone().getID();
    } catch (err) {
      return 'Asia/Shanghai';
    }
  }

  /** 时区列表（用于设置页选择） */
  static availableTimeZones(): string[] {
    try {
      return i18n.TimeZone.getAvailableIDs();
    } catch (err) {
      const fallback: string[] = ['Asia/Shanghai', 'UTC', 'Asia/Tokyo', 'Europe/London', 'America/New_York'];
      return fallback;
    }
  }

  /** 指定时刻的时区偏移（毫秒，东为正） */
  static offsetMs(tzId: string, utcMs: number): number {
    try {
      return i18n.getTimeZone(tzId).getOffset(utcMs);
    } catch (err) {
      return 0;
    }
  }

  /** UTC 毫秒 → 本地时间字段 */
  static toLocal(tzId: string, utcMs: number): LocalParts {
    const shifted = new Date(utcMs + TimeUtil.offsetMs(tzId, utcMs));
    const p = new LocalParts();
    p.year = shifted.getUTCFullYear();
    p.month = shifted.getUTCMonth() + 1;
    p.day = shifted.getUTCDate();
    p.hour = shifted.getUTCHours();
    p.minute = shifted.getUTCMinutes();
    p.second = shifted.getUTCSeconds();
    return p;
  }

  /** 本地时间字段 → UTC 毫秒（两次试探解决夏令时切换点） */
  static fromLocal(tzId: string, year: number, month: number, day: number, hour: number, minute: number): number {
    const naive = Date.UTC(year, month - 1, day, hour, minute, 0);
    const off1 = TimeUtil.offsetMs(tzId, naive);
    let utc = naive - off1;
    const off2 = TimeUtil.offsetMs(tzId, utc);
    if (off2 !== off1) {
      utc = naive - off2;
    }
    return utc;
  }

  /** 本地日期 00:00 对应的 UTC 毫秒 */
  static startOfLocalDay(tzId: string, utcMs: number): number {
    const p = TimeUtil.toLocal(tzId, utcMs);
    return TimeUtil.fromLocal(tzId, p.year, p.month, p.day, 0, 0);
  }

  /** 本地日期 +1 天 00:00 对应的 UTC 毫秒 */
  static addLocalDays(tzId: string, utcMs: number, days: number): number {
    const p = TimeUtil.toLocal(tzId, utcMs);
    const naiveNoon = Date.UTC(p.year, p.month - 1, p.day, 12, 0, 0);
    const next = new Date(naiveNoon + days * 86400000.0);
    return TimeUtil.fromLocal(tzId, next.getUTCFullYear(), next.getUTCMonth() + 1, next.getUTCDate(), 0, 0);
  }

  /** HH:mm */
  static formatTime(tzId: string, utcMs: number): string {
    if (utcMs < 0) {
      return '--:--';
    }
    const p = TimeUtil.toLocal(tzId, utcMs);
    return `${pad2(p.hour)}:${pad2(p.minute)}`;
  }

  /** MM-DD */
  static formatDateShort(tzId: string, utcMs: number): string {
    const p = TimeUtil.toLocal(tzId, utcMs);
    return `${pad2(p.month)}-${pad2(p.day)}`;
  }

  /** YYYY-MM-DD */
  static formatDate(tzId: string, utcMs: number): string {
    const p = TimeUtil.toLocal(tzId, utcMs);
    return `${p.year}-${pad2(p.month)}-${pad2(p.day)}`;
  }

  /** YYYY-MM-DD HH:mm */
  static formatDateTime(tzId: string, utcMs: number): string {
    return `${TimeUtil.formatDate(tzId, utcMs)} ${TimeUtil.formatTime(tzId, utcMs)}`;
  }

  /** 本地星期（0=周日） */
  static weekday(tzId: string, utcMs: number): number {
    const p = TimeUtil.toLocal(tzId, utcMs);
    return new Date(Date.UTC(p.year, p.month - 1, p.day)).getUTCDay();
  }

  /** 星期中文名 */
  static weekdayLabel(weekday: number): string {
    const names: string[] = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];
    const idx = ((weekday % 7) + 7) % 7;
    return names[idx];
  }

  /** 时区偏移展示，如 UTC+08:00 */
  static offsetLabel(tzId: string, utcMs: number): string {
    const offset = TimeUtil.offsetMs(tzId, utcMs);
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
