import { describe, it, expect } from '@ohos/hypium';
import { SolarCalc, SunPosition, SolarEvents, LightThresholds, LightWindow, LightPhase } from '../main/ets/services/SolarCalc';

/**
 * 太阳位置算法单元测试。
 *
 * 参考基准：
 * - NOAA Solar Calculator 公式集的物理不变量（春分赤道正午高度≈90°、日出方位≈90°）；
 * - 与 https://api.sunrise-sunset.org/ 的交叉验证结果（见 tools/solar-check，最大误差 27.4s）；
 * - 极昼极夜的行为约定（返回 -1 且 polarState 标记）。
 */
export default function solarCalcTest() {
  describe('SolarCalc', () => {
    it('equator_equinox_noon_altitude_near_90', 0, () => {
      // 2026-03-20 春分，赤道本初子午线
      const dayStart = Date.UTC(2026, 2, 20, 0, 0, 0);
      const ev: SolarEvents = SolarCalc.events(dayStart, 0, 0);
      const noon: SunPosition = SolarCalc.position(ev.solarNoonUtc, 0, 0);
      // 正午高度角应接近 90°
      expect(noon.altitudeDeg > 89.0).assertTrue();
      expect(noon.altitudeDeg <= 90.0).assertTrue();
    });

    it('equator_equinox_sunrise_azimuth_near_east', 0, () => {
      const dayStart = Date.UTC(2026, 2, 20, 0, 0, 0);
      const ev: SolarEvents = SolarCalc.events(dayStart, 0, 0);
      const rise: SunPosition = SolarCalc.position(ev.sunriseUtc, 0, 0);
      const set: SunPosition = SolarCalc.position(ev.sunsetUtc, 0, 0);
      // 春分日赤道日出接近正东（90°），日落接近正西（270°）
      expect(SolarCalc.angularDistance(rise.azimuthDeg, 90) < 2.0).assertTrue();
      expect(SolarCalc.angularDistance(set.azimuthDeg, 270) < 2.0).assertTrue();
    });

    it('utc_equinox_sunrise_time_reasonable', 0, () => {
      // 本初子午线春分日出应在 06:00 UTC 附近（均时差约 -7.5 分钟）
      const dayStart = Date.UTC(2026, 2, 20, 0, 0, 0);
      const ev: SolarEvents = SolarCalc.events(dayStart, 0, 0);
      const minutes = (ev.sunriseUtc - dayStart) / 60000.0;
      expect(minutes > 355 && minutes < 375).assertTrue();
    });

    it('shanghai_summer_noon_altitude', 0, () => {
      // 上海 31.2304N：夏至正午高度 ≈ 90 - |31.2304 - 23.44| = 82.21°
      const dayStartUtc = Date.UTC(2026, 5, 20, 16, 0, 0); // 上海 6/21 00:00 CST
      const ev: SolarEvents = SolarCalc.events(dayStartUtc, 31.2304, 121.4737);
      expect(Math.abs(ev.noonAltitudeDeg - 82.21) < 1.0).assertTrue();
    });

    it('shanghai_golden_window_ordering', 0, () => {
      // 黄金窗口必须满足 晨起 < 晨止 < 夕起 < 夕止，且都落在目标本地日内
      const dayStartUtc = Date.UTC(2026, 9, 29, 16, 0, 0); // 上海 10/30 00:00 CST
      const w: LightWindow = SolarCalc.lightWindows(dayStartUtc, 31.2304, 121.4737, LightThresholds.defaults());
      expect(w.goldenMorningStartUtc < w.goldenMorningEndUtc).assertTrue();
      expect(w.goldenMorningEndUtc < w.goldenEveningStartUtc).assertTrue();
      expect(w.goldenEveningStartUtc < w.goldenEveningEndUtc).assertTrue();
      expect(w.goldenMorningStartUtc >= dayStartUtc).assertTrue();
      expect(w.goldenEveningEndUtc <= dayStartUtc + 86400000.0).assertTrue();
    });

    it('shanghai_sunrise_local_time_reasonable', 0, () => {
      // 上海 10/30 日出约 06:08 CST = 前一日 22:08 UTC
      const dayStartUtc = Date.UTC(2026, 9, 29, 16, 0, 0);
      const ev: SolarEvents = SolarCalc.events(dayStartUtc, 31.2304, 121.4737);
      const localMinutes = (ev.sunriseUtc - dayStartUtc) / 60000.0;
      // 06:08 本地 = 368 分钟
      expect(localMinutes > 350 && localMinutes < 390).assertTrue();
    });

    it('polar_night_tromso_winter', 0, () => {
      const dayStartUtc = Date.UTC(2026, 11, 20, 23, 0, 0); // 特罗姆瑟 12/21 00:00 CET
      const ev: SolarEvents = SolarCalc.events(dayStartUtc, 69.6492, 18.9553);
      expect(ev.polarState).assertEqual(2);
      expect(ev.sunriseUtc).assertEqual(-1);
      expect(ev.sunsetUtc).assertEqual(-1);
    });

    it('polar_day_tromso_summer', 0, () => {
      const dayStartUtc = Date.UTC(2026, 5, 20, 22, 0, 0); // 特罗姆瑟 6/21 00:00 CEST
      const ev: SolarEvents = SolarCalc.events(dayStartUtc, 69.6492, 18.9553);
      expect(ev.polarState).assertEqual(1);
      expect(ev.sunriseUtc).assertEqual(-1);
    });

    it('angular_distance_is_circular', 0, () => {
      expect(SolarCalc.angularDistance(350, 10)).assertEqual(20);
      expect(SolarCalc.angularDistance(10, 350)).assertEqual(20);
      expect(SolarCalc.angularDistance(0, 180)).assertEqual(180);
      expect(SolarCalc.angularDistance(90, 90)).assertEqual(0);
    });

    it('phase_thresholds_map_to_expected_phase', 0, () => {
      const th = LightThresholds.defaults();
      // 默认阈值：黄金 +6°~-4°，蓝调 -4°~-6°，其后依次为民用/航海/天文曙暮光
      expect(SolarCalc.phaseOf(30, th)).assertEqual(LightPhase.DAY);
      expect(SolarCalc.phaseOf(3, th)).assertEqual(LightPhase.GOLDEN);
      expect(SolarCalc.phaseOf(-5, th)).assertEqual(LightPhase.BLUE);
      expect(SolarCalc.phaseOf(-8, th)).assertEqual(LightPhase.NAUTICAL);
      expect(SolarCalc.phaseOf(-15, th)).assertEqual(LightPhase.ASTRONOMICAL);
      expect(SolarCalc.phaseOf(-20, th)).assertEqual(LightPhase.NIGHT);
      // 若把蓝调下限收紧到 -3°，则 -5° 应落入民用曙暮光，说明 CIVIL 分支可达
      const custom = new LightThresholds();
      custom.blueLowerDeg = -3.0;
      expect(SolarCalc.phaseOf(-5, custom)).assertEqual(LightPhase.CIVIL);
    });

    it('azimuth_stays_in_range_all_day', 0, () => {
      const dayStart = Date.UTC(2026, 6, 1, 0, 0, 0);
      let ok = true;
      let t = dayStart;
      while (t < dayStart + 86400000.0) {
        const pos = SolarCalc.position(t, 45.0, -73.0);
        if (pos.azimuthDeg < 0 || pos.azimuthDeg >= 360) {
          ok = false;
        }
        if (pos.altitudeDeg < -90 || pos.altitudeDeg > 90) {
          ok = false;
        }
        t += 3600000;
      }
      expect(ok).assertTrue();
    });

    it('declination_matches_seasonal_extremes', 0, () => {
      // 夏至太阳赤纬应接近 +23.44°，冬至接近 -23.44°
      const jun = SolarCalc.declinationAndEot(SolarCalc.julianCentury(Date.UTC(2026, 5, 21, 12, 0, 0)))[0];
      const dec = SolarCalc.declinationAndEot(SolarCalc.julianCentury(Date.UTC(2026, 11, 21, 12, 0, 0)))[0];
      expect(Math.abs(jun - 23.44) < 0.1).assertTrue();
      expect(Math.abs(dec + 23.44) < 0.1).assertTrue();
    });
  });
}
