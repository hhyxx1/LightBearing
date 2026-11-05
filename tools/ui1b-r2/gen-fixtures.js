// UI-1B-R2 fixture 生成器：用与 SolarCalc 同一公式族（NOAA/Meeus）的镜像计算真实太阳高度/方位与光线分段。
// 输出 design/ui1b-r2/fixtures/fixtures.js（window.LB_FIXTURES），供原型以 <script> 引入，
// 规避 file:// 下 fetch JSON 被 CORS 阻止的问题。
// 说明：这是设计用 fixture，来源可复现（本文件 + 命令），不是应用运行时数据。

const DEG = Math.PI / 180;
const RAD = 180 / Math.PI;
const norm360 = (d) => ((d % 360) + 360) % 360;

function julianCentury(utcMs) {
  const jd = utcMs / 86400000 + 2440587.5;
  return (jd - 2451545.0) / 36525.0;
}

function declinationAndEot(t) {
  const l0 = norm360(280.46646 + t * (36000.76983 + t * 0.0003032));
  const m = norm360(357.52911 + t * (35999.05029 - 0.0001537 * t));
  const mRad = m * DEG;
  const ecc = 0.016708634 - t * (0.000042037 + 0.0000001267 * t);
  const center = Math.sin(mRad) * (1.914602 - t * (0.004817 + 0.000014 * t)) +
    Math.sin(2 * mRad) * (0.019993 - 0.000101 * t) + Math.sin(3 * mRad) * 0.000289;
  const trueLong = l0 + center;
  const omega = 125.04 - 1934.136 * t;
  const apparentLong = trueLong - 0.00569 - 0.00478 * Math.sin(omega * DEG);
  const seconds = 21.448 - t * (46.815 + t * (0.00059 - t * 0.001813));
  const meanObliquity = 23.0 + (26.0 + seconds / 60.0) / 60.0;
  const obliquity = meanObliquity + 0.00256 * Math.cos(omega * DEG);
  const obRad = obliquity * DEG;
  const decl = Math.asin(Math.sin(obRad) * Math.sin(apparentLong * DEG)) * RAD;
  const y = Math.tan(obRad / 2) * Math.tan(obRad / 2);
  const eotRad = y * Math.sin(2 * l0 * DEG) - 2 * ecc * Math.sin(mRad) +
    4 * ecc * y * Math.sin(mRad) * Math.cos(2 * l0 * DEG) -
    0.5 * y * y * Math.sin(4 * l0 * DEG) - 1.25 * ecc * ecc * Math.sin(2 * mRad);
  return { decl, eotMin: 4 * eotRad * RAD };
}

function position(utcMs, latDeg, lonDeg) {
  const t = julianCentury(utcMs);
  const { decl, eotMin } = declinationAndEot(t);
  const utcMinutes = ((((utcMs / 60000) % 1440) + 1440) % 1440);
  const tst = ((((utcMinutes + eotMin + 4 * lonDeg) % 1440) + 1440) % 1440);
  const H = (tst / 4 - 180) * DEG;
  const latRad = latDeg * DEG;
  const declRad = decl * DEG;
  const sinAlt = Math.sin(latRad) * Math.sin(declRad) +
    Math.cos(latRad) * Math.cos(declRad) * Math.cos(H);
  const alt = Math.asin(Math.max(-1, Math.min(1, sinAlt))) * RAD;
  const az = norm360(Math.atan2(-Math.sin(H) * Math.cos(declRad),
    Math.sin(declRad) * Math.cos(latRad) - Math.cos(declRad) * Math.sin(latRad) * Math.cos(H)) * RAD);
  return { az, alt };
}

// 产品定义：黄金 -4..6°，蓝调 -6..-4°，白昼 >6°，民用曙暮 -6..-12? 采用行业常用分界：
// 夜间 < -18；天文 -18..-12；航海 -12..-6；蓝调 -6..-4；黄金 -4..6；白昼 > 6
function phaseOf(alt) {
  if (alt > 6) return 'day';
  if (alt > -4) return 'golden';
  if (alt > -6) return 'blue';
  if (alt > -12) return 'nautical';
  if (alt > -18) return 'astro';
  return 'night';
}

const STEP = 5 * 60 * 1000; // 5 分钟采样，足够还原曲线且体积可控

function build(name, lat, lon, dayStartUtc, dayEndUtc, tzOffsetMin, extra) {
  const samples = [];
  for (let t = dayStartUtc; t <= dayEndUtc; t += STEP) {
    const p = position(t, lat, lon);
    samples.push([t, Number(p.alt.toFixed(2)), Number(p.az.toFixed(1)), phaseOf(p.alt)]);
  }
  const segments = [];
  for (const s of samples) {
    const ph = s[3];
    const last = segments[segments.length - 1];
    if (last && last[0] === ph && s[0] - last[2] <= STEP) {
      last[2] = s[0] + STEP;
    } else {
      segments.push([ph, s[0], s[0] + STEP]);
    }
  }
  const shot = segments.filter((g) => g[0] === 'golden' || g[0] === 'blue');
  const goldenOnly = segments.filter((g) => g[0] === 'golden');
  const pick = goldenOnly.length > 0 ? goldenOnly[0] : (shot.length > 0 ? shot[0] : null);
  const nowUtc = (extra && extra.nowUtc) || (pick !== null ? Math.round((pick[1] + pick[2]) / 2) : dayStartUtc + 12 * 3600000);
  const nowPos = position(nowUtc, lat, lon);
  return {
    name, lat, lon, tzOffsetMin,
    dayStartUtc, dayEndUtc,
    dayHours: Number(((dayEndUtc - dayStartUtc) / 3600000).toFixed(2)),
    samples, segments, windows: shot,
    nowUtc, nowAlt: Number(nowPos.alt.toFixed(2)), nowAz: Number(nowPos.az.toFixed(1)),
    note: (extra && extra.note) || ''
  };
}

const D = Date.UTC;
const fixtures = {
  shanghaiGolden: build('上海 · 黄金时段进行中', 31.2304, 121.4737,
    D(2026, 10, 4, 16, 0, 0), D(2026, 10, 5, 16, 0, 0), 480, {}),
  shanghaiNight: build('上海 · 夜间', 31.2304, 121.4737,
    D(2026, 10, 4, 16, 0, 0), D(2026, 10, 5, 16, 0, 0), 480,
    { nowUtc: D(2026, 10, 4, 19, 30, 0) }),
  tromsoDay: build('特罗姆瑟 · 极昼', 69.6492, 18.9553,
    D(2026, 5, 20, 22, 0, 0), D(2026, 5, 21, 22, 0, 0), 120, {}),
  tromsoNight: build('特罗姆瑟 · 极夜', 69.6492, 18.9553,
    D(2026, 11, 20, 23, 0, 0), D(2026, 11, 21, 23, 0, 0), 60, {}),
  nyDst: build('纽约 · DST 回拨日（25h）', 40.7128, -74.006,
    D(2026, 10, 1, 4, 0, 0), D(2026, 10, 2, 5, 0, 0), -300, {}),
  shanghai1969: build('上海 · 1970 年前（1969-12-31）', 31.2304, 121.4737,
    D(1969, 11, 30, 16, 0, 0), D(1969, 11, 31, 16, 0, 0), 480, { nowUtc: D(1969, 11, 31, 2, 30, 0) })
};

const out = 'design/ui1b-r2/fixtures/fixtures.js';
const fs = require('fs');
fs.mkdirSync('design/ui1b-r2/fixtures', { recursive: true });
fs.writeFileSync(out, '// 由 tools 镜像计算生成，供 UI-1B-R2 原型使用（DESIGN FIXTURE）\nwindow.LB_FIXTURES = ' +
  JSON.stringify(fixtures) + ';\n', 'utf8');
for (const k of Object.keys(fixtures)) {
  const f = fixtures[k];
  console.log(k, 'hours=', f.dayHours, 'segments=', f.segments.length, 'windows=', f.windows.length,
    'nowAlt=', f.nowAlt, 'nowAz=', f.nowAz);
}
console.log('written', out);
