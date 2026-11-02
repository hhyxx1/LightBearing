// 反向寻光审计工具（2C-1）
// 目的：用高密度参考扫描独立评测生产算法（五分钟粗扫 + 30s/5s/1s 细化 + 10 分钟合并 + 误差排序）。
// 本文件不参与 App 运行，仅供审计与基准使用。
//
// 限制：参考扫描受步长限制，只能证明「在给定分辨率下被发现/未被发现」，
// 不能宣称连续时间上的全局最优性已被证明。

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

function position(utcMs, latDeg, lonDeg) {
  const t = julianCentury(utcMs);
  const { decl, eotMin } = declinationAndEot(t);
  const utcMinutes = (((utcMs / 60000) % 1440) + 1440) % 1440;
  const tst = (((utcMinutes + eotMin + 4 * lonDeg) % 1440) + 1440) % 1440;
  const H = (tst / 4 - 180) * DEG;
  const latRad = latDeg * DEG;
  const declRad = decl * DEG;
  const sinAlt = Math.sin(latRad) * Math.sin(declRad) + Math.cos(latRad) * Math.cos(declRad) * Math.cos(H);
  const alt = Math.asin(Math.max(-1, Math.min(1, sinAlt))) * RAD;
  const az = norm360(
    Math.atan2(-Math.sin(H) * Math.cos(declRad),
      Math.sin(declRad) * Math.cos(latRad) - Math.cos(declRad) * Math.sin(latRad) * Math.cos(H)) * RAD
  );
  return { azimuth: az, altitude: alt };
}

function angularDistance(a, b) {
  const d = Math.abs(norm360(a) - norm360(b)) % 360;
  return d > 180 ? 360 - d : d;
}

function makeGoal(lat, lon, azTarget, altTarget, azTol, altTol, daylightOnly = false, maxResults = 30) {
  return { lat, lon, azTarget, altTarget, azTol, altTol, daylightOnly, maxResults };
}

function errors(goal, pos) {
  return { az: angularDistance(pos.azimuth, goal.azTarget), alt: Math.abs(pos.altitude - goal.altTarget) };
}

function inTolerance(goal, pos) {
  const e = errors(goal, pos);
  return e.az <= goal.azTol && e.alt <= goal.altTol;
}

/** 参考扫描：按 stepMs 高密度扫描，返回连续有效窗口（相邻有效点间隔 <= stepMs 视为同一窗口） */
function referenceWindows(goal, startUtc, endUtc, stepMs = 1000) {
  const windows = [];
  let cur = null;
  let calls = 0;
  for (let t = startUtc; t < endUtc; t += stepMs) {
    const pos = position(t, goal.lat, goal.lon);
    calls++;
    const ok = inTolerance(goal, pos) && (!goal.daylightOnly || pos.altitude > -0.833);
    if (ok) {
      const e = errors(goal, pos);
      const cost = e.az + e.alt;
      if (!cur) {
        cur = { startUtc: t, endUtc: t, bestUtc: t, bestAz: e.az, bestAlt: e.alt, bestCost: cost };
      } else if (t - cur.endUtc <= stepMs) {
        cur.endUtc = t;
        if (cost < cur.bestCost) {
          cur.bestCost = cost;
          cur.bestUtc = t;
          cur.bestAz = e.az;
          cur.bestAlt = e.alt;
        }
      } else {
        windows.push(cur);
        cur = { startUtc: t, endUtc: t, bestUtc: t, bestAz: e.az, bestAlt: e.alt, bestCost: cost };
      }
    } else if (cur) {
      windows.push(cur);
      cur = null;
    }
  }
  if (cur) windows.push(cur);
  return { windows, calls };
}

const COARSE_STEP_MS = 5 * 60 * 1000;
const REFINE_STEPS = [30000, 5000, 1000];

/** 生产算法镜像（与 ReverseSearch.searchInRanges 同构），用于统计与对比 */
function productionSearch(goal, startUtc, endUtc, opts = {}) {
  const coarse = opts.coarse ?? COARSE_STEP_MS;
  const refineSteps = opts.refineSteps ?? REFINE_STEPS;
  const mergeGap = opts.mergeGap ?? 10 * 60 * 1000;
  const skip = opts.skipAfterHit ?? coarse * 2;
  const stats = { calls: 0, coarseHits: 0, refineDroppedInvalid: 0 };
  const raw = [];

  function pos(t) {
    stats.calls++;
    return position(t, goal.lat, goal.lon);
  }

  function refineAt(centerMs, windowMs, stepMs) {
    let bestT = centerMs;
    let bestCost = Number.MAX_VALUE;
    let t = Math.max(startUtc, centerMs - windowMs);
    const end = Math.min(endUtc - 1, centerMs + windowMs);
    while (t <= end) {
      const p = pos(t);
      const c = errors(goal, p).az + errors(goal, p).alt;
      if (c < bestCost) {
        bestCost = c;
        bestT = t;
      }
      t += stepMs;
    }
    return Math.min(Math.max(bestT, startUtc), endUtc - 1);
  }

  let t = startUtc;
  while (t < endUtc) {
    const p = pos(t);
    if (inTolerance(goal, p)) {
      stats.coarseHits++;
      let bestT = t;
      let windowMs = coarse;
      for (const step of refineSteps) {
        bestT = refineAt(bestT, windowMs, step);
        windowMs = step * 2;
      }
      const bestPos = pos(bestT);
      const e = errors(goal, bestPos);
      if (e.az <= goal.azTol && e.alt <= goal.altTol && (!goal.daylightOnly || bestPos.altitude > -0.833)) {
        raw.push({ utcMs: bestT, azError: e.az, altError: e.alt, cost: e.az + e.alt });
      } else {
        stats.refineDroppedInvalid++;
      }
      t += skip;
    } else {
      t += coarse;
    }
  }

  raw.sort((a, b) => a.utcMs - b.utcMs);
  const merged = [];
  for (const c of raw) {
    if (merged.length === 0) {
      merged.push(c);
      continue;
    }
    const last = merged[merged.length - 1];
    if (c.utcMs - last.utcMs <= mergeGap) {
      if (c.cost < last.cost) merged[merged.length - 1] = c;
    } else {
      merged.push(c);
    }
  }
  merged.sort((a, b) => a.cost - b.cost);
  const out = merged.slice(0, goal.maxResults);
  return { candidates: out, stats, rawCount: raw.length, mergedCount: merged.length };
}

/** 对比：参考窗口 vs 生产候选 */
function compare(goal, startUtc, endUtc, stepMs = 1000) {
  const ref = referenceWindows(goal, startUtc, endUtc, stepMs);
  const prod = productionSearch(goal, startUtc, endUtc);
  const cands = prod.candidates;
  // 召回：参考窗口中至少有一个候选落在其内部（含边界容差）
  let recalled = 0;
  const missed = [];
  for (const w of ref.windows) {
    const hit = cands.some((c) => c.utcMs >= w.startUtc - stepMs && c.utcMs <= w.endUtc + stepMs);
    if (hit) recalled++;
    else missed.push(w);
  }
  // 误合并：两个参考窗口被同一个候选代表
  let wrongMerges = 0;
  for (const c of cands) {
    const covering = ref.windows.filter((w) => c.utcMs >= w.startUtc - stepMs * 2 && c.utcMs <= w.endUtc + stepMs * 2);
    if (covering.length > 1) wrongMerges++;
  }
  // 重复候选：同一参考窗口内产出多个候选（10 分钟合并未覆盖）
  let dupCandidates = 0;
  for (const w of ref.windows) {
    const inside = cands.filter((c) => c.utcMs >= w.startUtc - stepMs * 2 && c.utcMs <= w.endUtc + stepMs * 2);
    if (inside.length > 1) dupCandidates += inside.length - 1;
  }
  // 结果有效性
  let validCands = 0;
  for (const c of cands) {
    const p = position(c.utcMs, goal.lat, goal.lon);
    const e = errors(goal, p);
    if (e.az <= goal.azTol && e.alt <= goal.altTol && (!goal.daylightOnly || p.altitude > -0.833)) validCands++;
  }
  // 最优误差差距
  const refBest = ref.windows.length ? Math.min(...ref.windows.map((w) => w.bestCost)) : null;
  const prodBest = cands.length ? Math.min(...cands.map((c) => c.cost)) : null;
  return {
    refWindowCount: ref.windows.length,
    refCalls: ref.calls,
    refBestCost: refBest,
    probedCount: cands.length,
    prodCalls: prod.stats.calls,
    prodCoarseHits: prod.stats.coarseHits,
    refineDroppedInvalid: prod.stats.refineDroppedInvalid,
    recalled,
    missedWindows: missed.map((w) => ({ startUtc: w.startUtc, endUtc: w.endUtc, lenSec: (w.endUtc - w.startUtc) / 1000, bestUtc: w.bestUtc, bestCost: w.bestCost })),
    wrongMerges,
    dupCandidates,
    validCands,
    invalidCands: cands.length - validCands,
    bestGap: refBest !== null && prodBest !== null ? prodBest - refBest : null,
  };
}

// ------------------------------- CLI -------------------------------
const args = process.argv.slice(2);
const cmd = args[0] || "help";
const SH_LAT = 31.2304;
const SH_LON = 121.4737;
const DAY_START = Date.UTC(2026, 9, 29, 16, 0, 0); // 上海 2026-10-30 本地日
const DAY_END = Date.UTC(2026, 9, 30, 16, 0, 0);

function fmt(ms) {
  return new Date(ms).toISOString();
}

if (cmd === "hunt") {
  // 针对多个容差，统计「参考扫描存在窗口但生产返回空 / 未覆盖」的数量
  const tolerances = [0.05, 0.1, 0.2, 0.5, 1.0, 2.0, 3.0];
  console.log("tolerance°\twindows\tprodCount\tmissed\tmissRate\trefineDropped");
  for (const tol of tolerances) {
    let windows = 0;
    let prodCount = 0;
    let missed = 0;
    let dropped = 0;
    // 在当天 10 分钟网格上取 36 个目标时刻（每小时 3 个，避开整点偏移，便于命中格点之间）
    for (let k = 0; k < 36; k++) {
      const t0 = DAY_START + k * 40 * 60 * 1000 + 2.5 * 60 * 1000;
      const p = position(t0, SH_LAT, SH_LON);
      const goal = makeGoal(SH_LAT, SH_LON, p.azimuth, p.altitude, tol, tol, false, 30);
      const r = compare(goal, DAY_START, DAY_END, 1000);
      windows += r.refWindowCount;
      prodCount += r.probedCount;
      missed += r.missedWindows.length;
      dropped += r.refineDroppedInvalid;
    }
    const rate = windows ? (missed / windows) : 0;
    console.log(`${tol}\t${windows}\t${prodCount}\t${missed}\t${(rate * 100).toFixed(1)}%\t${dropped}`);
  }
} else if (cmd === "cases") {
  // 逐条打印有代表性的用例（漏报 / 细化丢结果 / 误合并）
  const tol = Number(args[1] || 0.2);
  for (let k = 0; k < 36; k++) {
    const t0 = DAY_START + k * 40 * 60 * 1000 + 2.5 * 60 * 1000;
    const p = position(t0, SH_LAT, SH_LON);
    const goal = makeGoal(SH_LAT, SH_LON, p.azimuth, p.altitude, tol, tol, false, 30);
    const r = compare(goal, DAY_START, DAY_END, 1000);
    if (r.missedWindows.length > 0 || r.refineDroppedInvalid > 0 || r.wrongMerges > 0) {
      console.log(JSON.stringify({
        targetUtc: fmt(t0), azTarget: Number(p.azimuth.toFixed(3)), altTarget: Number(p.altitude.toFixed(3)),
        tol, refWindows: r.refWindowCount, prodCandidates: r.probedCount,
        missed: r.missedWindows, wrongMerges: r.wrongMerges,
        refineDroppedInvalid: r.refineDroppedInvalid, bestGap: r.bestGap,
      }));
    }
  }
} else if (cmd === "diag") {
  // 多点位、多容差：统计细化丢结果（粗扫命中但细化落到容差外）与误合并
  const places = [
    { name: "shanghai", lat: 31.2304, lon: 121.4737 },
    { name: "newyork", lat: 40.7128, lon: -74.006 },
    { name: "tromso", lat: 69.6492, lon: 18.9553 },
  ];
  const pairs = [[3, 3], [3, 0.2], [0.2, 3], [1, 1], [0.5, 2], [6, 0.5]];
  console.log("place	tolAz	tolAlt	refWin	prodCand	missed	wrongMerges	refineDropped");
  for (const pl of places) {
    for (const [ta, tb] of pairs) {
      let refWin = 0;
      let prodCand = 0;
      let missed = 0;
      let wrong = 0;
      let dropped = 0;
      for (let k = 0; k < 48; k++) {
        const t0 = DAY_START + k * 30 * 60 * 1000 + 2.5 * 60 * 1000;
        const p = position(t0, pl.lat, pl.lon);
        const goal = makeGoal(pl.lat, pl.lon, p.azimuth, p.altitude, ta, tb, false, 30);
        const r = compare(goal, DAY_START, DAY_END, 1000);
        refWin += r.refWindowCount;
        prodCand += r.probedCount;
        missed += r.missedWindows.length;
        wrong += r.wrongMerges;
        dropped += r.refineDroppedInvalid;
      }
      console.log(`${pl.name}	${ta}	${tb}	${refWin}	${prodCand}	${missed}	${wrong}	${dropped}`);
    }
  }
} else if (cmd === "dup") {
  // 重复候选与跨日界拆分：参考窗口数 vs 生产候选数
  const places = [
    { name: "shanghai", lat: 31.2304, lon: 121.4737 },
    { name: "tromso", lat: 69.6492, lon: 18.9553 },
    { name: "kiritimati", lat: 1.87, lon: -157.43 },
  ];
  console.log("place	tol	refWin	prodCand	dupCand	missed	wrongMerges");
  for (const pl of places) {
    for (const tol of [0.5, 1.0, 2.0, 3.0, 6.0]) {
      let refWin = 0, prodCand = 0, dup = 0, missed = 0, wrong = 0;
      for (let k = 0; k < 48; k++) {
        const t0 = DAY_START + k * 30 * 60 * 1000 + 2.5 * 60 * 1000;
        const p = position(t0, pl.lat, pl.lon);
        const goal = makeGoal(pl.lat, pl.lon, p.azimuth, p.altitude, tol, tol, false, 30);
        const r = compare(goal, DAY_START, DAY_END, 1000);
        refWin += r.refWindowCount; prodCand += r.probedCount; dup += r.dupCandidates;
        missed += r.missedWindows.length; wrong += r.wrongMerges;
      }
      console.log(`${pl.name}	${tol}	${refWin}	${prodCand}	${dup}	${missed}	${wrong}`);
    }
  }
  // 跨日界：目标时刻正好落在本地日边界前 3 分钟（窗口跨越 midnight）
  const pEdge = position(DAY_START - 3 * 60 * 1000, SH_LAT, SH_LON);
  const gEdge = makeGoal(SH_LAT, SH_LON, pEdge.azimuth, pEdge.altitude, 1.0, 1.0, false, 30);
  const prevDay = productionSearch(gEdge, DAY_START - 86400000, DAY_START);
  const thisDay = productionSearch(gEdge, DAY_START, DAY_END);
  const whole = referenceWindows(gEdge, DAY_START - 2 * 3600 * 1000, DAY_START + 2 * 3600 * 1000, 1000);
  console.log("EDGE", JSON.stringify({
    refWindowsAcrossBoundary: whole.windows.length,
    refWindow: whole.windows[0],
    prevDayCandidates: prevDay.candidates.map((c) => new Date(c.utcMs).toISOString()),
    thisDayCandidates: thisDay.candidates.map((c) => new Date(c.utcMs).toISOString()),
  }));
} else if (cmd === "topk") {
  // 模拟 ReversePage：逐日 searchInRanges（每日各自 maxResults），再全局按误差排序截断 30
  const days = Number(args[1] || 14);
  const tol = Number(args[2] || 3.0);
  const p0 = position(DAY_START + 12 * 3600 * 1000, SH_LAT, SH_LON);
  const goal = makeGoal(SH_LAT, SH_LON, p0.azimuth, p0.altitude, tol, tol, false, 30);
  const all = [];
  for (let i = 0; i < days; i++) {
    const s = DAY_START + i * 86400000;
    const r = productionSearch(goal, s, s + 86400000);
    for (const c of r.candidates) all.push({ ...c, day: i });
  }
  all.sort((a, b) => a.cost - b.cost);
  const top = all.slice(0, 30);
  const daySet = new Set(top.map((c) => c.day));
  console.log(JSON.stringify({
    days, tol, perDayCap: 30,
    collected: all.length, kept: top.length,
    distinctDaysInTop30: daySet.size,
    dayHistogram: Array.from(daySet).sort((a, b) => a - b),
    costRange: top.length ? [top[0].cost, top[top.length - 1].cost] : null,
    minGapMinutesInTop: top.length > 1 ? Math.min(...top.slice(1).map((c, i) => (c.utcMs - top[i].utcMs) / 60000)) : null,
  }));
} else if (cmd === "refine") {
  // 针对性检查：窄方位容差 + 宽高度容差，观察细化是否把有效命中移出容差后被丢弃
  const pairs = [[0.5, 5], [0.3, 8], [1, 6], [0.2, 3], [2, 10]];
  console.log("place	tolAz	tolAlt	coarseHits	droppedInvalid	kept");
  for (const [ta, tb] of pairs) {
    let hits = 0, dropped = 0, kept = 0;
    for (let k = 0; k < 96; k++) {
      const t0 = DAY_START + k * 15 * 60 * 1000 + 2.5 * 60 * 1000;
      const p = position(t0, SH_LAT, SH_LON);
      const goal = makeGoal(SH_LAT, SH_LON, p.azimuth, p.altitude, ta, tb, false, 30);
      const r = productionSearch(goal, DAY_START, DAY_END);
      hits += r.stats.coarseHits; dropped += r.stats.refineDroppedInvalid; kept += r.candidates.length;
    }
    console.log(`shanghai	${ta}	${tb}	${hits}	${dropped}	${kept}`);
  }
} else if (cmd === "bench") {
  const days = [1, 7, 14, 30, 365];
  console.log("days\tpositionCalls\twallMs\tmaxDayMs\tcandidates\trefineDropped");
  for (const d of days) {
    const p0 = position(DAY_START + 12 * 3600 * 1000, SH_LAT, SH_LON);
    const goal = makeGoal(SH_LAT, SH_LON, p0.azimuth, p0.altitude, 3.0, 3.0, false, 30);
    let calls = 0;
    let maxDay = 0;
    let cands = 0;
    let dropped = 0;
    const t0 = Date.now();
    for (let i = 0; i < d; i++) {
      const s = DAY_START + i * 86400000;
      const t1 = Date.now();
      const r = productionSearch(goal, s, s + 86400000);
      maxDay = Math.max(maxDay, Date.now() - t1);
      calls += r.stats.calls;
      cands += r.candidates.length;
      dropped += r.stats.refineDroppedInvalid;
    }
    const wall = Date.now() - t0;
    console.log(`${d}\t${calls}\t${wall}\t${maxDay}\t${cands}\t${dropped}`);
  }
} else if (cmd === "cancel") {
  // 单日搜索耗时即取消延迟上界（页面只在每天结束后检查取消标志）
  const p0 = position(DAY_START + 12 * 3600 * 1000, SH_LAT, SH_LON);
  for (const tol of [0.05, 0.5, 3.0]) {
    const goal = makeGoal(SH_LAT, SH_LON, p0.azimuth, p0.altitude, tol, tol, false, 30);
    const t0 = Date.now();
    const r = productionSearch(goal, DAY_START, DAY_END);
    console.log(JSON.stringify({ tol, dayMs: Date.now() - t0, calls: r.stats.calls, cands: r.candidates.length }));
  }
} else {
  console.log(`usage: node scan.mjs <hunt|cases|bench|cancel> [tolerance]`);
  console.log(`day = ${fmt(DAY_START)} .. ${fmt(DAY_END)} @ ${SH_LAT},${SH_LON}`);
}
