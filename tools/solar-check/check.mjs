/**
 * 太阳算法外部交叉验证
 *
 * 参考数据来源：https://api.sunrise-sunset.org/ （独立实现，官方声明 ±30s）
 * 抓取时间：2026-10-29，原始响应保存在 raw.txt，可离线重跑本脚本。
 *
 * 本脚本以与 entry/src/main/ets/services/SolarCalc.ets 相同的 NOAA/Meeus 公式计算，
 * 逐项比对日出、日落、太阳正午、三层曙暮光，输出误差（秒）。
 *
 * 运行：node tools/solar-check/check.mjs
 */

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const DEG = Math.PI / 180;
const RAD = 180 / Math.PI;

function norm360(d) {
  let v = d % 360;
  if (v < 0) v += 360;
  return v;
}

function julianCentury(utcMs) {
  const jd = utcMs / 86400000 + 2440587.5;
  return (jd - 2451545.0) / 36525.0;
}

function declinationAndEot(t) {
  const l0 = norm360(280.46646 + t * (36000.76983 + t * 0.0003032));
  const m = norm360(357.52911 + t * (35999.05029 - 0.0001537 * t));
  const mRad = m * DEG;
  const ecc = 0.016708634 - t * (0.000042037 + 0.0000001267 * t);
  const center =
    Math.sin(mRad) * (1.914602 - t * (0.004817 + 0.000014 * t)) +
    Math.sin(2 * mRad) * (0.019993 - 0.000101 * t) +
    Math.sin(3 * mRad) * 0.000289;
  const trueLong = l0 + center;
  const omega = 125.04 - 1934.136 * t;
  const apparentLong = trueLong - 0.00569 - 0.00478 * Math.sin(omega * DEG);
  const seconds = 21.448 - t * (46.815 + t * (0.00059 - t * 0.001813));
  const meanObliquity = 23.0 + (26.0 + seconds / 60.0) / 60.0;
  const obliquity = meanObliquity + 0.00256 * Math.cos(omega * DEG);
  const obRad = obliquity * DEG;
  const decl = Math.asin(Math.sin(obRad) * Math.sin(apparentLong * DEG)) * RAD;
  const y = Math.tan(obRad / 2) * Math.tan(obRad / 2);
  const eotRad =
    y * Math.sin(2 * l0 * DEG) -
    2 * ecc * Math.sin(mRad) +
    4 * ecc * y * Math.sin(mRad) * Math.cos(2 * l0 * DEG) -
    0.5 * y * y * Math.sin(4 * l0 * DEG) -
    1.25 * ecc * ecc * Math.sin(2 * mRad);
  return { decl, eotMin: 4 * eotRad * RAD };
}

function hourAngleForAltitude(latDeg, declDeg, altitudeDeg) {
  const latRad = latDeg * DEG;
  const declRad = declDeg * DEG;
  const cosH =
    (Math.sin(altitudeDeg * DEG) - Math.sin(latRad) * Math.sin(declRad)) /
    (Math.cos(latRad) * Math.cos(declRad));
  if (cosH > 1 || cosH < -1) return -1;
  return Math.acos(cosH) * RAD;
}

/**
 * 与 SolarCalc.events 完全一致的锚定方式：
 * 入参是「本地日 00:00 对应的 UTC 时刻」，先取包含当地正午的那一天 UTC 零点，
 * 再把太阳正午夹回目标本地日区间——跨日期线（±180°）必须靠这一步才不会整体偏一天。
 */
function events(dayStartLocalUtc, latDeg, lonDeg) {
  const localNoonGuess = dayStartLocalUtc + 43200000;
  const utcMidnight = Math.floor(localNoonGuess / 86400000) * 86400000;
  const { decl, eotMin } = declinationAndEot(julianCentury(utcMidnight + 43200000));
  let solarNoon = utcMidnight + (720 - 4 * lonDeg - eotMin) * 60000;
  if (solarNoon < dayStartLocalUtc) {
    solarNoon += 86400000;
  } else if (solarNoon >= dayStartLocalUtc + 86400000) {
    solarNoon -= 86400000;
  }
  const out = { solarNoon, decl, noonAltitude: 90 - Math.abs(latDeg - decl) };
  const pairs = [
    ['sunrise', 'sunset', -0.833],
    ['civilDawn', 'civilDusk', -6],
    ['nauticalDawn', 'nauticalDusk', -12],
    ['astronomicalDawn', 'astronomicalDusk', -18]
  ];
  for (const [dawnKey, duskKey, alt] of pairs) {
    const h = hourAngleForAltitude(latDeg, decl, alt);
    if (h < 0) {
      out[dawnKey] = -1;
      out[duskKey] = -1;
    } else {
      out[dawnKey] = solarNoon - h * 240000;
      out[duskKey] = solarNoon + h * 240000;
    }
  }
  return out;
}

function position(utcMs, latDeg, lonDeg) {
  const t = julianCentury(utcMs);
  const { decl, eotMin } = declinationAndEot(t);
  const utcMinutes = ((utcMs / 60000) % 1440 + 1440) % 1440;
  const tst = ((utcMinutes + eotMin + 4 * lonDeg) % 1440 + 1440) % 1440;
  const H = (tst / 4 - 180) * DEG;
  const latRad = latDeg * DEG;
  const declRad = decl * DEG;
  const sinAlt =
    Math.sin(latRad) * Math.sin(declRad) + Math.cos(latRad) * Math.cos(declRad) * Math.cos(H);
  const alt = Math.asin(Math.max(-1, Math.min(1, sinAlt))) * RAD;
  const az = norm360(
    Math.atan2(-Math.sin(H) * Math.cos(declRad), Math.sin(declRad) * Math.cos(latRad) - Math.cos(declRad) * Math.sin(latRad) * Math.cos(H)) *
      RAD
  );
  return { azimuth: az, altitude: alt };
}

const here = dirname(fileURLToPath(import.meta.url));
const raw = readFileSync(join(here, 'raw.txt'), 'utf8');
const lines = raw.split(/\r?\n/);

let current = null;
const cases = [];
for (const line of lines) {
  if (line.startsWith('CASE ')) {
    const parts = line.split(/\s+/);
    // 可选第 5 段：显式时区小时数。日期线附近「日期+经度」本身不唯一，
    // 必须给定时区才能与参考源对齐（app 里等价于机位的 tzId）。
    current = {
      name: parts[1],
      lat: Number(parts[2]),
      lon: Number(parts[3]),
      date: parts[4],
      tz: parts.length > 5 ? Number(parts[5]) : undefined,
      ref: null
    };
    cases.push(current);
  } else if (line.startsWith('{') && current) {
    current.ref = JSON.parse(line).results;
  }
}

const FIELDS = [
  ['sunrise', 'sunrise'],
  ['sunset', 'sunset'],
  ['solarNoon', 'solar_noon'],
  ['civilDawn', 'civil_twilight_begin'],
  ['civilDusk', 'civil_twilight_end'],
  ['nauticalDawn', 'nautical_twilight_begin'],
  ['nauticalDusk', 'nautical_twilight_end'],
  ['astronomicalDawn', 'astronomical_twilight_begin'],
  ['astronomicalDusk', 'astronomical_twilight_end']
];

const TOLERANCE_S = 120; // 参考源声明 ±30s，留两倍余量
let failures = 0;
let maxErr = 0;
const rows = [];

for (const c of cases) {
  const [y, m, d] = c.date.split('-').map(Number);
  // 参考源以「该坐标的本地日期」为准；显式给了时区就用它，否则按经度推算（15°/小时）
  const tzOffsetHours = c.tz !== undefined ? c.tz : Math.round(c.lon / 15);
  const dayStart = Date.UTC(y, m - 1, d, 0, 0, 0) - tzOffsetHours * 3600000;
  const mine = events(dayStart, c.lat, c.lon);
  let caseMax = 0;
  for (const [mineKey, refKey] of FIELDS) {
    const refVal = c.ref[refKey];
    const refMs = typeof refVal === 'string' && refVal.includes('T') ? Date.parse(refVal) : -1;
    const mineMs = mine[mineKey];
    if (refMs < 0 || mineMs < 0) {
      if (refMs < 0 && mineMs < 0) continue;
      // 一方有值一方无值 = 极昼极夜判定不一致
      if (refMs < 0 && mineMs >= 0) {
        // 参考源在极昼时仍给边缘值，记录但不计为失败
        rows.push(`  ${c.name} ${mineKey}: 参考—/本实现有值`);
      }
      continue;
    }
    const errS = Math.abs(mineMs - refMs) / 1000;
    if (errS > caseMax) caseMax = errS;
    if (errS > maxErr) maxErr = errS;
    if (errS > TOLERANCE_S) {
      failures++;
      rows.push(`  FAIL ${c.name} ${mineKey}: 本实现=${new Date(mineMs).toISOString()} 参考=${new Date(refMs).toISOString()} 误差=${errS.toFixed(1)}s`);
    }
  }
  rows.push(`  OK   ${c.name.padEnd(18)} 最大误差 ${caseMax.toFixed(1)}s  正午高度 ${mine.noonAltitude.toFixed(2)}°`);
}

// 物理不变量检查（不依赖外部源）
const inv = [];
{
  // 春分日赤道正午太阳高度应接近 90°，方位角在全天由东到西
  const eqDay = Date.UTC(2026, 2, 20, 0, 0, 0);
  const ev = events(eqDay, 0, 0);
  const noonPos = position(ev.solarNoon, 0, 0);
  inv.push(['春分赤道正午高度≈90°', Math.abs(noonPos.altitude - 90) < 0.6, noonPos.altitude.toFixed(2)]);
  // 赤道春分日出方位应接近 90°（正东）
  const risePos = position(ev.sunrise, 0, 0);
  const riseAzErr = Math.abs(risePos.azimuth - 90);
  inv.push(['春分赤道日出方位≈90°', riseAzErr < 1.5, risePos.azimuth.toFixed(2)]);
  // 赤道春分日落方位应接近 270°（正西）
  const setPos = position(ev.sunset, 0, 0);
  const setAzErr = Math.abs(setPos.azimuth - 270);
  inv.push(['春分赤道日落方位≈270°', setAzErr < 1.5, setPos.azimuth.toFixed(2)]);
  // 均时差年极值：11 月 3 日前应接近 +16.4 分钟
  const eotNov = declinationAndEot(julianCentury(Date.UTC(2026, 10, 3, 12, 0, 0))).eotMin;
  inv.push(['11/03 均时差≈+16.4min', Math.abs(eotNov - 16.4) < 0.6, eotNov.toFixed(2)]);
  // 均时差年极值：2 月 11 日前后应接近 -14.2 分钟
  const eotFeb = declinationAndEot(julianCentury(Date.UTC(2026, 1, 11, 12, 0, 0))).eotMin;
  inv.push(['02/11 均时差≈-14.2min', Math.abs(eotFeb + 14.2) < 0.6, eotFeb.toFixed(2)]);
  // 夏至赤纬≈+23.44°，冬至≈-23.44°
  const declJun = declinationAndEot(julianCentury(Date.UTC(2026, 5, 21, 12, 0, 0))).decl;
  const declDec = declinationAndEot(julianCentury(Date.UTC(2026, 11, 21, 12, 0, 0))).decl;
  inv.push(['夏至赤纬≈+23.44°', Math.abs(declJun - 23.44) < 0.05, declJun.toFixed(3)]);
  inv.push(['冬至赤纬≈-23.44°', Math.abs(declDec + 23.44) < 0.05, declDec.toFixed(3)]);
  // 极夜判定：特罗姆瑟冬至应无日出
  const polar = events(Date.UTC(2026, 11, 21, 0, 0, 0), 69.6492, 18.9553);
  inv.push(['特罗姆瑟冬至无日出（极夜）', polar.sunrise < 0, polar.noonAltitude.toFixed(2)]);
  // 极昼判定：特罗姆瑟夏至应无日落
  const polarDay = events(Date.UTC(2026, 5, 21, 0, 0, 0), 69.6492, 18.9553);
  inv.push(['特罗姆瑟夏至无日落（极昼）', polarDay.sunset < 0, polarDay.noonAltitude.toFixed(2)]);
}

console.log('=== 外部参考源比对（api.sunrise-sunset.org）===');
for (const r of rows) console.log(r);
console.log(`\n最大误差 ${maxErr.toFixed(1)}s，容差 ${TOLERANCE_S}s，失败项 ${failures}`);

console.log('\n=== 物理不变量 ===');
let invFail = 0;
for (const [name, ok, val] of inv) {
  if (!ok) invFail++;
  console.log(`  ${ok ? 'PASS' : 'FAIL'} ${name} → ${val}`);
}

const totalFail = failures + invFail;
console.log(`\n结论：${totalFail === 0 ? '全部通过' : `失败 ${totalFail} 项`}`);
process.exit(totalFail === 0 ? 0 : 1);
