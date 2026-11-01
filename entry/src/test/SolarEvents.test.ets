import { describe, it, expect } from '@ohos/hypium';
import { SolarCalc, SolarEvents, LightWindow, LightThresholds } from '../main/ets/services/SolarCalc';

/**
 * 太阳事件与光线窗口的边界行为测试（2A）。
 *
 * 参考值来源：https://api.sunrise-sunset.org/ 在 2026-10-29 抓取的原始响应，
 * 保存于 tools/solar-check/raw.txt（tromso_winter / tromso_summer），
 * 与生产算法相互独立；这里直接以该外部数据作为期望值，容差 ±3 分钟。
 *
 * 说明：本地日 00:00 的 UTC 时刻按机位时区换算得到（特罗姆瑟 12 月为 UTC+1、6 月为 UTC+2）。
 */

/** 特罗姆瑟坐标 */
const TROMSO_LAT: number = 69.6492;
const TROMSO_LON: number = 18.9553;

/** 2026-12-21 特罗姆瑟本地日 00:00 对应的 UTC 毫秒（UTC+1） */
const TROMSO_WINTER_DAY_START: number = Date.UTC(2026, 11, 20, 23, 0, 0);
/** 2026-06-21 特罗姆瑟本地日 00:00 对应的 UTC 毫秒（UTC+2） */
const TROMSO_SUMMER_DAY_START: number = Date.UTC(2026, 5, 20, 22, 0, 0);

const MINUTE: number = 60000.0;
const TOLERANCE_MS: number = 3 * MINUTE;

/** 断言两个时刻之差在容差内；任一为 -1 时直接失败 */
function assertNear(actual: number, expectedUtc: number, label: string): void {
  expect(actual >= 0).assertTrue();
  const diff = Math.abs(actual - expectedUtc);
  expect(diff <= TOLERANCE_MS).assertTrue();
}

/** 断言某时刻太阳高度落在 [lower, upper) 带内（±0.05° 数值容差） */
function assertInBand(utcMs: number, lat: number, lon: number, lower: number, upper: number): void {
  const alt = SolarCalc.position(utcMs, lat, lon).altitudeDeg;
  expect(alt >= lower - 0.05).assertTrue();
  expect(alt < upper + 0.05).assertTrue();
}

/** 断言某时刻太阳高度低于带下边界 */
function assertBelowBand(utcMs: number, lat: number, lon: number, lower: number): void {
  const alt = SolarCalc.position(utcMs, lat, lon).altitudeDeg;
  expect(alt < lower + 0.05).assertTrue();
}

/** 断言某时刻太阳高度不低于带上边界 */
function assertAboveBand(utcMs: number, lat: number, lon: number, upper: number): void {
  const alt = SolarCalc.position(utcMs, lat, lon).altitudeDeg;
  expect(alt >= upper - 0.05).assertTrue();
}

export default function solarEventsTest() {
  describe('SolarEventsEdge', () => {
    it('polar_night_still_has_twilight', 0, () => {
      // 现象：此前 events() 在日出无解时直接 return，导致极夜当天仍存在的
      // 民用/航海/天文曙暮光全部被漏算（外部参考明确给出了这三组时间）。
      const ev: SolarEvents = SolarCalc.events(TROMSO_WINTER_DAY_START, TROMSO_LAT, TROMSO_LON);
      // 无日出日落
      expect(ev.sunriseUtc).assertEqual(-1);
      expect(ev.sunsetUtc).assertEqual(-1);
      expect(ev.polarState).assertEqual(2);
      // 但曙暮光存在，且与外部参考一致
      assertNear(ev.civilDawnUtc, Date.parse('2026-12-21T08:31:12Z'), 'civilDawn');
      assertNear(ev.civilDuskUtc, Date.parse('2026-12-21T12:53:13Z'), 'civilDusk');
      assertNear(ev.nauticalDawnUtc, Date.parse('2026-12-21T06:46:45Z'), 'nauticalDawn');
      assertNear(ev.nauticalDuskUtc, Date.parse('2026-12-21T14:37:41Z'), 'nauticalDusk');
      assertNear(ev.astronomicalDawnUtc, Date.parse('2026-12-21T05:28:24Z'), 'astroDawn');
      assertNear(ev.astronomicalDuskUtc, Date.parse('2026-12-21T15:56:01Z'), 'astroDusk');
    });

    it('polar_day_has_no_events_at_any_threshold', 0, () => {
      // 极昼：太阳全天高于 0°/-6°/-12°/-18° 所有阈值，因此四组事件都不存在
      const ev: SolarEvents = SolarCalc.events(TROMSO_SUMMER_DAY_START, TROMSO_LAT, TROMSO_LON);
      expect(ev.polarState).assertEqual(1);
      expect(ev.sunriseUtc).assertEqual(-1);
      expect(ev.civilDawnUtc).assertEqual(-1);
      expect(ev.nauticalDawnUtc).assertEqual(-1);
      expect(ev.astronomicalDawnUtc).assertEqual(-1);
    });

    it('arctic_circle_critical_latitudes', 0, () => {
      // 纬度略低（65°N）时夏至仍有短暂日出；纬度略高（66.6°N）时太阳不再落到 -0.833° 以下。
      // 期望来自几何关系：最小高度 ≈ δ + φ - 90，夏至 δ≈23.44°。
      const dayStart65: number = Date.UTC(2026, 5, 20, 22, 0, 0);
      const ev65 = SolarCalc.events(dayStart65, 65.0, TROMSO_LON);
      expect(ev65.sunriseUtc >= 0).assertTrue();
      expect(ev65.sunsetUtc > ev65.sunriseUtc).assertTrue();

      const ev666 = SolarCalc.events(dayStart65, 66.6, TROMSO_LON);
      expect(ev666.sunriseUtc).assertEqual(-1);
      // 太阳全天高于 -6°，因此民用曙暮光同样不存在
      expect(ev666.civilDawnUtc).assertEqual(-1);
    });

    it('southern_high_latitude_polar_night_with_twilight', 0, () => {
      // 南纬 70° 的 6 月 21 日（南半球冬至）：正午高度 ≈ 90 - (70 + 23.44) ≈ -3.44°，
      // 低于地平但高于 -6°，因此无日出、但民用曙暮光存在。
      const dayStart: number = Date.UTC(2026, 5, 21, 12, 0, 0); // 该坐标无夏令时，取 UTC 正午前后作本地零点
      const ev = SolarCalc.events(dayStart, -70.0, 0.0);
      expect(ev.sunriseUtc).assertEqual(-1);
      expect(ev.civilDawnUtc >= 0).assertTrue();
      expect(ev.civilDuskUtc > ev.civilDawnUtc).assertTrue();
    });

    it('golden_window_absent_when_sun_always_above_upper_threshold', 0, () => {
      // 纬度 75° 夏至：最小高度 ≈ 23.44 + 75 - 90 ≈ 8.44° > +6°，
      // 太阳全天不进入黄金时刻区间 [-4, +6]，窗口必须不存在。
      const dayStart: number = Date.UTC(2026, 5, 20, 22, 0, 0);
      const w: LightWindow = SolarCalc.lightWindows(dayStart, 75.0, TROMSO_LON, LightThresholds.defaults());
      expect(w.goldenMorningStartUtc).assertEqual(-1);
      expect(w.goldenMorningEndUtc).assertEqual(-1);
      expect(w.goldenEveningStartUtc).assertEqual(-1);
      expect(w.goldenEveningEndUtc).assertEqual(-1);
    });

    it('blue_window_exists_near_midnight_when_sun_stays_above_minus6', 0, () => {
      // 原断言错误：把「太阳不穿过 -6°」等同于「没有蓝调」。
      // 蓝调带是 [-6°, -4°)，61.5°N 夏至最小高度 ≈ -5.06°，午夜前后太阳正处在该带内，
      // 因此蓝调存在，窗口从当地零点开始、到太阳升过 -4° 结束。
      const dayStart: number = Date.UTC(2026, 5, 20, 22, 0, 0);
      const dayEnd = dayStart + 86400000.0;
      const w: LightWindow = SolarCalc.lightWindows(dayStart, 61.5, TROMSO_LON, LightThresholds.defaults());
      // 蓝调必须存在
      expect(w.blueMorningStartUtc).assertEqual(dayStart);
      expect(w.blueMorningEndUtc > w.blueMorningStartUtc).assertTrue();
      expect(w.blueEveningStartUtc < w.blueEveningEndUtc).assertTrue();
      expect(w.blueEveningEndUtc).assertEqual(dayEnd);
      // 代表时刻在带内：零点刚过仍在 [-6,-4)，升过 -4 之后就在带外
      assertInBand(dayStart + 60000.0, 61.5, TROMSO_LON, -6.0, -4.0);
      assertInBand(dayEnd - 60000.0, 61.5, TROMSO_LON, -6.0, -4.0);
      assertAboveBand(w.blueMorningEndUtc + 300000.0, 61.5, TROMSO_LON, -4.0);
      // 黄金时段仍然存在且顺序正确
      expect(w.goldenMorningStartUtc >= 0).assertTrue();
      expect(w.goldenMorningStartUtc < w.goldenMorningEndUtc).assertTrue();
      expect(w.goldenEveningStartUtc < w.goldenEveningEndUtc).assertTrue();
    });

    it('blue_window_exists_in_polar_night_when_minus4_never_reached', 0, () => {
      // 反例：72°N 冬至正午高度 ≈ 90 - (72 + 23.44) ≈ -5.44°，
      // 太阳穿越 -6° 但到不了 -4°，正午附近落在蓝调带 [-6,-4) 内，蓝调必须存在。
      const dayStart: number = Date.UTC(2026, 11, 20, 23, 0, 0); // 该坐标无夏令时，UTC 一路可用
      const w: LightWindow = SolarCalc.lightWindows(dayStart, 72.0, TROMSO_LON, LightThresholds.defaults());
      expect(w.goldenMorningStartUtc).assertEqual(-1); // 到不了 -4°，黄金带不存在
      expect(w.blueMorningStartUtc >= 0).assertTrue();
      expect(w.blueMorningStartUtc < w.blueMorningEndUtc).assertTrue();
      expect(w.blueEveningStartUtc < w.blueEveningEndUtc).assertTrue();
      // 窗口代表时刻在带内；午夜远离该带
      const noon = SolarCalc.events(dayStart, 72.0, TROMSO_LON).solarNoonUtc;
      assertInBand(noon, 72.0, TROMSO_LON, -6.0, -4.0);
      assertBelowBand(dayStart + 3600000.0, 72.0, TROMSO_LON, -6.0);
    });

    it('golden_window_exists_in_polar_night', 0, () => {
      // 特罗姆瑟冬至：正午高度 ≈ -3.09°，仍高于 -4°，因此太阳会短暂进入 [-4,+6] 带。
      const w: LightWindow = SolarCalc.lightWindows(TROMSO_WINTER_DAY_START, TROMSO_LAT, TROMSO_LON,
        LightThresholds.defaults());
      expect(w.goldenMorningStartUtc >= 0).assertTrue();
      expect(w.goldenMorningStartUtc < w.goldenMorningEndUtc).assertTrue();
      // 冬至特罗姆瑟太阳会落到 -6° 以下，因此蓝调时段存在
      expect(w.blueMorningStartUtc >= 0).assertTrue();
      expect(w.blueMorningStartUtc < w.blueMorningEndUtc).assertTrue();
    });

    it('shanghai_normal_day_windows_ordered_and_bounded', 0, () => {
      // 上海 2026-10-30 本地日（UTC+8）：常规 24 小时日，窗口必须有序且落在当日区间内
      const dayStart: number = Date.UTC(2026, 9, 29, 16, 0, 0);
      const ev = SolarCalc.events(dayStart, 31.2304, 121.4737);
      expect(ev.sunriseUtc >= 0).assertTrue();
      expect(ev.sunsetUtc > ev.sunriseUtc).assertTrue();
      const w: LightWindow = SolarCalc.lightWindows(dayStart, 31.2304, 121.4737, LightThresholds.defaults());
      const dayEnd = dayStart + 86400000.0;
      expect(w.goldenMorningStartUtc >= dayStart).assertTrue();
      expect(w.goldenMorningStartUtc < w.goldenMorningEndUtc).assertTrue();
      expect(w.goldenEveningStartUtc < w.goldenEveningEndUtc).assertTrue();
      expect(w.goldenEveningEndUtc <= dayEnd).assertTrue();
      expect(w.blueMorningStartUtc >= dayStart).assertTrue();
      expect(w.blueMorningStartUtc < w.blueMorningEndUtc).assertTrue();
      expect(w.blueEveningStartUtc < w.blueEveningEndUtc).assertTrue();
      expect(w.blueEveningEndUtc <= dayEnd).assertTrue();
      // 代表时刻必须真的落在对应高度带内，邻近时刻必须落在带外
      const goldenMidMorning = (w.goldenMorningStartUtc + w.goldenMorningEndUtc) / 2;
      assertInBand(goldenMidMorning, 31.2304, 121.4737, -4.0, 6.0);
      const goldenMidEvening = (w.goldenEveningStartUtc + w.goldenEveningEndUtc) / 2;
      assertInBand(goldenMidEvening, 31.2304, 121.4737, -4.0, 6.0);
      const blueMidMorning = (w.blueMorningStartUtc + w.blueMorningEndUtc) / 2;
      assertInBand(blueMidMorning, 31.2304, 121.4737, -6.0, -4.0);
      const blueMidEvening = (w.blueEveningStartUtc + w.blueEveningEndUtc) / 2;
      assertInBand(blueMidEvening, 31.2304, 121.4737, -6.0, -4.0);
      // 黄金晨窗开始前 5 分钟应低于 -4°；结束 5 分钟后应不低于 +6°
      assertBelowBand(w.goldenMorningStartUtc - 300000.0, 31.2304, 121.4737, -4.0);
      assertAboveBand(w.goldenMorningEndUtc + 300000.0, 31.2304, 121.4737, 6.0);
    });

    it('accepts_real_local_day_length_not_assumed_24h', 0, () => {
      // 2B 将传入夏令时切换日的真实本地日边界；这里用一个 23 小时的本地日
      // （纽约 2026-03-08，本地 00:00 = 05:00Z，DST 开始后当日只有 23 小时）验证入口可用，
      // 且所有窗口都被裁切在 [dayStart, dayEnd) 内。
      const dayStart: number = Date.UTC(2026, 2, 8, 5, 0, 0);
      const dayEnd: number = dayStart + 23 * 3600000.0;
      const lat = 40.7128;
      const lon = -74.006;
      const w: LightWindow = SolarCalc.lightWindows(dayStart, lat, lon, LightThresholds.defaults(), dayEnd);
      const ev = SolarCalc.events(dayStart, lat, lon, dayEnd);
      // 太阳事件必须落在该 23 小时区间内
      expect(ev.sunriseUtc >= dayStart).assertTrue();
      expect(ev.sunsetUtc <= dayEnd).assertTrue();
      // 黄金窗口存在且被裁切在区间内
      expect(w.goldenMorningStartUtc >= dayStart).assertTrue();
      expect(w.goldenMorningStartUtc < w.goldenMorningEndUtc).assertTrue();
      expect(w.goldenEveningEndUtc <= dayEnd).assertTrue();
      // 蓝调窗口同样不得越界
      if (w.blueMorningStartUtc >= 0) {
        expect(w.blueMorningStartUtc >= dayStart).assertTrue();
        expect(w.blueMorningEndUtc <= dayEnd).assertTrue();
      }
    });
  });
}
