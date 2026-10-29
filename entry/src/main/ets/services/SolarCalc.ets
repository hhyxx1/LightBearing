/**
 * 太阳位置计算（NOAA Solar Calculator / Meeus 低精度算法）
 *
 * 参考：NOAA Global Monitoring Laboratory, "Solar Calculator" 公式集（Meeus, Astronomical Algorithms, 2nd ed., ch.25）
 * 用途：给定 UTC 时刻与 WGS84 经纬度，求太阳视位置。
 *
 * 精度说明（必须在 UI 中如实展示）：
 * - 本实现为 NOAA/Meeus 低精度级数，1900-2100 年间方位角残差 < 0.5°；
 * - 未含视差秒级修正、未含海拔高度对地平线俯角的影响；
 * - 日出日落使用上边缘 + 标准折射定义：几何高度 = -0.833°。
 */

const DEG = Math.PI / 180.0;
const RAD = 180.0 / Math.PI;

/** 太阳瞬时位置 */
export class SunPosition {
  /** 方位角，0-360°，正北为 0，顺时针增大 */
  azimuthDeg: number = 0;
  /** 高度角，-90°-90°（几何高度，未加折射） */
  altitudeDeg: number = 0;

  static of(azimuthDeg: number, altitudeDeg: number): SunPosition {
    const p = new SunPosition();
    p.azimuthDeg = azimuthDeg;
    p.altitudeDeg = altitudeDeg;
    return p;
  }
}

/** 某日太阳事件（全部为 UTC 毫秒；不可用时为 -1） */
export class SolarEvents {
  solarNoonUtc: number = -1;
  sunriseUtc: number = -1;
  sunsetUtc: number = -1;
  civilDawnUtc: number = -1;
  civilDuskUtc: number = -1;
  nauticalDawnUtc: number = -1;
  nauticalDuskUtc: number = -1;
  astronomicalDawnUtc: number = -1;
  astronomicalDuskUtc: number = -1;
  /** 极昼/极夜状态：0=正常，1=极昼，2=极夜 */
  polarState: number = 0;
  /** 当日正午太阳高度角 */
  noonAltitudeDeg: number = 0;
}

/** 光线阶段枚举 */
export enum LightPhase {
  NIGHT = 0,
  ASTRONOMICAL = 1,
  NAUTICAL = 2,
  CIVIL = 3,
  BLUE = 4,
  GOLDEN = 5,
  DAY = 6
}

/** 黄金/蓝调定义（可配置） */
export class LightThresholds {
  /** 黄金时刻上限高度角（默认 +6°） */
  goldenUpperDeg: number = 6.0;
  /** 黄金时刻下限高度角（默认 -4°，即太阳刚落到地平线下） */
  goldenLowerDeg: number = -4.0;
  /** 蓝调下限高度角（默认 -6°，民用曙暮光结束） */
  blueLowerDeg: number = -6.0;

  static defaults(): LightThresholds {
    return new LightThresholds();
  }
}

/** 某日的光线时间段（UTC 毫秒，不可用为 -1） */
export class LightWindow {
  goldenMorningStartUtc: number = -1;
  goldenMorningEndUtc: number = -1;
  goldenEveningStartUtc: number = -1;
  goldenEveningEndUtc: number = -1;
  blueMorningStartUtc: number = -1;
  blueMorningEndUtc: number = -1;
  blueEveningStartUtc: number = -1;
  blueEveningEndUtc: number = -1;
}

export class SolarCalc {
  /** Unix 毫秒 → 儒略日 */
  static julianDay(utcMs: number): number {
    return utcMs / 86400000.0 + 2440587.5;
  }

  /** Unix 毫秒 → 儒略世纪 */
  static julianCentury(utcMs: number): number {
    return (SolarCalc.julianDay(utcMs) - 2451545.0) / 36525.0;
  }

  /** 角度归一化到 [0,360) */
  static norm360(deg: number): number {
    let v = deg % 360.0;
    if (v < 0) {
      v += 360.0;
    }
    return v;
  }

  /** 环形角度差，结果 [0,180] */
  static angularDistance(a: number, b: number): number {
    const d = Math.abs(a - b) % 360.0;
    return d > 180.0 ? 360.0 - d : d;
  }

  /** 太阳赤纬（度）与均时差（分钟） */
  static declinationAndEot(t: number): number[] {
    const l0 = SolarCalc.norm360(280.46646 + t * (36000.76983 + t * 0.0003032));
    const m = SolarCalc.norm360(357.52911 + t * (35999.05029 - 0.0001537 * t));
    const mRad = m * DEG;
    const ecc = 0.016708634 - t * (0.000042037 + 0.0000001267 * t);
    const center = Math.sin(mRad) * (1.914602 - t * (0.004817 + 0.000014 * t)) +
      Math.sin(2.0 * mRad) * (0.019993 - 0.000101 * t) +
      Math.sin(3.0 * mRad) * 0.000289;
    const trueLong = l0 + center;
    const omega = 125.04 - 1934.136 * t;
    const apparentLong = trueLong - 0.00569 - 0.00478 * Math.sin(omega * DEG);
    const seconds = 21.448 - t * (46.815 + t * (0.00059 - t * 0.001813));
    const meanObliquity = 23.0 + (26.0 + seconds / 60.0) / 60.0;
    const obliquity = meanObliquity + 0.00256 * Math.cos(omega * DEG);
    const obRad = obliquity * DEG;
    const decl = Math.asin(Math.sin(obRad) * Math.sin(apparentLong * DEG)) * RAD;

    const y = Math.tan(obRad / 2.0) * Math.tan(obRad / 2.0);
    const ySin2L0 = y * Math.sin(2.0 * l0 * DEG);
    const eSinM = 2.0 * ecc * Math.sin(mRad);
    const eotRad = ySin2L0 - eSinM + 4.0 * ecc * y * Math.sin(mRad) * Math.cos(2.0 * l0 * DEG) -
      0.5 * y * y * Math.sin(4.0 * l0 * DEG) - 1.25 * ecc * ecc * Math.sin(2.0 * mRad);
    const eotMin = 4.0 * eotRad * RAD;
    return [decl, eotMin];
  }

  /** 计算指定时刻的太阳位置 */
  static position(utcMs: number, latDeg: number, lonDeg: number): SunPosition {
    const t = SolarCalc.julianCentury(utcMs);
    const dm = SolarCalc.declinationAndEot(t);
    const decl = dm[0];
    const eotMin = dm[1];
    const utcMinutes = (utcMs / 60000.0) % 1440.0;
    let trueSolarTime = utcMinutes + eotMin + 4.0 * lonDeg;
    trueSolarTime = ((trueSolarTime % 1440.0) + 1440.0) % 1440.0;
    const hourAngle = trueSolarTime / 4.0 - 180.0;
    const hRad = hourAngle * DEG;
    const declRad = decl * DEG;
    const latRad = latDeg * DEG;
    const sinAlt = Math.sin(latRad) * Math.sin(declRad) + Math.cos(latRad) * Math.cos(declRad) * Math.cos(hRad);
    const alt = Math.asin(Math.max(-1.0, Math.min(1.0, sinAlt))) * RAD;
    const azNum = -Math.sin(hRad) * Math.cos(declRad);
    const azDen = Math.sin(declRad) * Math.cos(latRad) - Math.cos(declRad) * Math.sin(latRad) * Math.cos(hRad);
    const az = SolarCalc.norm360(Math.atan2(azNum, azDen) * RAD);
    return SunPosition.of(az, alt);
  }

  /** 大气折射修正（NOAA），返回视高度角 */
  static apparentAltitude(geometricAltDeg: number): number {
    if (geometricAltDeg > 85.0) {
      return geometricAltDeg;
    }
    const te = Math.tan(geometricAltDeg * DEG);
    let correction = 0.0;
    if (geometricAltDeg > 5.0) {
      correction = 58.1 / te - 0.07 / Math.pow(te, 3) + 0.000086 / Math.pow(te, 5);
    } else if (geometricAltDeg > -0.575) {
      correction = 1735.0 + geometricAltDeg * (-518.2 + geometricAltDeg * (103.4 + geometricAltDeg * (-12.79 + geometricAltDeg * 0.711)));
    } else {
      correction = -20.774 / te;
    }
    return geometricAltDeg + correction / 3600.0;
  }

  /** 某纬度/赤纬下的时角（度）；返回 -1 表示无解 */
  static hourAngleForAltitude(latDeg: number, declDeg: number, altitudeDeg: number): number {
    const latRad = latDeg * DEG;
    const declRad = declDeg * DEG;
    const cosH = (Math.sin(altitudeDeg * DEG) - Math.sin(latRad) * Math.sin(declRad)) /
      (Math.cos(latRad) * Math.cos(declRad));
    if (cosH > 1.0 || cosH < -1.0) {
      return -1.0;
    }
    return Math.acos(cosH) * RAD;
  }

  /**
   * 取锚点：把「本地日 00:00 对应的 UTC 时刻」换算成包含当地正午的那一天 UTC 零点。
   * 必须这样做：NOAA 公式里的太阳正午是「UTC 零点之后 720-4λ-EoT 分钟」，
   * 若直接用本地日零点，在高时区会整体偏移（例如东八区偏 8 小时）。
   */
  private static anchorOf(dayStartLocalUtc: number): number[] {
    const localNoonGuess = dayStartLocalUtc + 43200000.0;
    const utcMidnight = Math.floor(localNoonGuess / 86400000.0) * 86400000.0;
    const t = SolarCalc.julianCentury(utcMidnight + 43200000.0);
    const dm = SolarCalc.declinationAndEot(t);
    return [utcMidnight, dm[0], dm[1]];
  }

  /**
   * 计算某 UTC 日的事件。
   * @param dayStartLocalUtc 目标本地日 00:00 对应的 UTC 毫秒时间戳
   * @param latDeg 纬度
   * @param lonDeg 经度（东经为正）
   */
  static events(dayStartLocalUtc: number, latDeg: number, lonDeg: number): SolarEvents {
    const e = new SolarEvents();
    const anchor = SolarCalc.anchorOf(dayStartLocalUtc);
    const utcMidnight = anchor[0];
    const decl = anchor[1];
    const eotMin = anchor[2];
    // 太阳正午（UTC 分钟，相对该 UTC 日零点）
    const noonMinutes = 720.0 - 4.0 * lonDeg - eotMin;
    let noon = utcMidnight + noonMinutes * 60000.0;
    // 保证落在目标本地日区间内（跨日期线与极端经度）
    if (noon < dayStartLocalUtc) {
      noon += 86400000.0;
    } else if (noon >= dayStartLocalUtc + 86400000.0) {
      noon -= 86400000.0;
    }
    e.solarNoonUtc = noon;
    e.noonAltitudeDeg = 90.0 - Math.abs(latDeg - decl);

    const sunriseH = SolarCalc.hourAngleForAltitude(latDeg, decl, -0.833);
    const civilH = SolarCalc.hourAngleForAltitude(latDeg, decl, -6.0);
    const nauticalH = SolarCalc.hourAngleForAltitude(latDeg, decl, -12.0);
    const astroH = SolarCalc.hourAngleForAltitude(latDeg, decl, -18.0);

    if (sunriseH < 0) {
      e.polarState = e.noonAltitudeDeg > 0 ? 1 : 2;
      return e;
    }
    e.sunriseUtc = e.solarNoonUtc - sunriseH * 240000.0;
    e.sunsetUtc = e.solarNoonUtc + sunriseH * 240000.0;
    if (civilH >= 0) {
      e.civilDawnUtc = e.solarNoonUtc - civilH * 240000.0;
      e.civilDuskUtc = e.solarNoonUtc + civilH * 240000.0;
    }
    if (nauticalH >= 0) {
      e.nauticalDawnUtc = e.solarNoonUtc - nauticalH * 240000.0;
      e.nauticalDuskUtc = e.solarNoonUtc + nauticalH * 240000.0;
    }
    if (astroH >= 0) {
      e.astronomicalDawnUtc = e.solarNoonUtc - astroH * 240000.0;
      e.astronomicalDuskUtc = e.solarNoonUtc + astroH * 240000.0;
    }
    return e;
  }

  /** 判断某时刻所处的光线阶段 */
  static phaseOf(sunAltDeg: number, thresholds: LightThresholds): LightPhase {
    if (sunAltDeg >= thresholds.goldenUpperDeg) {
      return LightPhase.DAY;
    }
    if (sunAltDeg >= thresholds.goldenLowerDeg) {
      return LightPhase.GOLDEN;
    }
    if (sunAltDeg >= thresholds.blueLowerDeg) {
      return LightPhase.BLUE;
    }
    if (sunAltDeg >= -6.0) {
      return LightPhase.CIVIL;
    }
    if (sunAltDeg >= -12.0) {
      return LightPhase.NAUTICAL;
    }
    if (sunAltDeg >= -18.0) {
      return LightPhase.ASTRONOMICAL;
    }
    return LightPhase.NIGHT;
  }

  /** 阶段的简体中文标签 */
  static phaseLabel(phase: LightPhase): string {
    switch (phase) {
      case LightPhase.DAY:
        return '白昼';
      case LightPhase.GOLDEN:
        return '黄金时刻';
      case LightPhase.BLUE:
        return '蓝调时刻';
      case LightPhase.CIVIL:
        return '民用曙暮光';
      case LightPhase.NAUTICAL:
        return '航海曙暮光';
      case LightPhase.ASTRONOMICAL:
        return '天文曙暮光';
      default:
        return '夜间';
    }
  }

  /** 计算某日黄金/蓝调时间窗（UTC 毫秒）；dayStartLocalUtc 为本地日 00:00 的 UTC 时刻 */
  static lightWindows(dayStartLocalUtc: number, latDeg: number, lonDeg: number, th: LightThresholds): LightWindow {
    const w = new LightWindow();
    const anchor = SolarCalc.anchorOf(dayStartLocalUtc);
    const utcMidnight = anchor[0];
    const decl = anchor[1];
    const eotMin = anchor[2];
    let noonUtc = utcMidnight + (720.0 - 4.0 * lonDeg - eotMin) * 60000.0;
    if (noonUtc < dayStartLocalUtc) {
      noonUtc += 86400000.0;
    } else if (noonUtc >= dayStartLocalUtc + 86400000.0) {
      noonUtc -= 86400000.0;
    }

    const hGoldenUpper = SolarCalc.hourAngleForAltitude(latDeg, decl, th.goldenUpperDeg);
    const hGoldenLower = SolarCalc.hourAngleForAltitude(latDeg, decl, th.goldenLowerDeg);
    const hBlueLower = SolarCalc.hourAngleForAltitude(latDeg, decl, th.blueLowerDeg);

    // 黄金时刻：太阳高度在 [goldenLower, goldenUpper] 区间。
    // 晨间从较低的 goldenLower 升到 goldenUpper，因此起点用 lower、终点用 upper；傍晚相反。
    if (hGoldenUpper >= 0) {
      w.goldenMorningEndUtc = noonUtc - hGoldenUpper * 240000.0;
      w.goldenEveningStartUtc = noonUtc + hGoldenUpper * 240000.0;
    }
    if (hGoldenLower >= 0) {
      w.goldenMorningStartUtc = noonUtc - hGoldenLower * 240000.0;
      w.goldenEveningEndUtc = noonUtc + hGoldenLower * 240000.0;
    } else {
      // 太阳全天高于 goldenLower（高纬夏季）：晨间从当地日零点起算
      if (hGoldenUpper >= 0) {
        w.goldenMorningStartUtc = dayStartLocalUtc;
        w.goldenEveningEndUtc = dayStartLocalUtc + 86400000.0;
      }
    }
    if (hBlueLower >= 0) {
      w.blueMorningStartUtc = noonUtc - hBlueLower * 240000.0;
      w.blueMorningEndUtc = noonUtc - hGoldenLower * 240000.0;
      w.blueEveningStartUtc = noonUtc + hGoldenLower * 240000.0;
      w.blueEveningEndUtc = noonUtc + hBlueLower * 240000.0;
    }
    return w;
  }

  /** 方位角 → 八向中文名 */
  static azimuthLabel(azDeg: number): string {
    const names: string[] = ['正北', '东北', '正东', '东南', '正南', '西南', '正西', '西北'];
    const idx = Math.round(SolarCalc.norm360(azDeg) / 45.0) % 8;
    return names[idx];
  }

  /** 角度 → 度分秒文本（用于精度展示） */
  static formatAngle(deg: number, unit: number): string {
    if (unit === 1) {
      const rad = deg * DEG;
      return `${rad.toFixed(4)} rad`;
    }
    return `${deg.toFixed(2)}°`;
  }
}
