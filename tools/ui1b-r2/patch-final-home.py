import re

P = 'design/ui1b-r2/final-home.html'
s = open(P, encoding='utf-8').read()

# 1) 时区：改为按样本的真实偏移（DST 回拨日会得到 -240 与 -300 两种）
s = s.replace("""function localParts(utcMs, offMin) {""",
"""function offsetAt(utcMs) {
  if (!fx || !fx.samples || fx.samples.length === 0) return fx ? fx.tzOffsetMin : 0;
  let best = fx.samples[0];
  for (const smp of fx.samples) { if (Math.abs(smp[0] - utcMs) < Math.abs(best[0] - utcMs)) best = smp; }
  return best.length > 4 ? best[4] : fx.tzOffsetMin;
}

function localParts(utcMs, offMin) {""")
s = s.replace("function fmtHM(utcMs) { const p = localParts(utcMs, fx.tzOffsetMin); return pad(p.h) + ':' + pad(p.mi); }",
"function fmtHM(utcMs) { const p = localParts(utcMs, offsetAt(utcMs)); return pad(p.h) + ':' + pad(p.mi); }")
s = s.replace("function fmtDate(utcMs) { const p = localParts(utcMs, fx.tzOffsetMin);",
"function fmtDate(utcMs) { const p = localParts(utcMs, offsetAt(utcMs));")

# 2) 时刻 + 偏移：DST 日同时显示偏移以消除重复小时歧义
s = s.replace("""  $('sbTz').textContent = fmtOffset(fx.tzOffsetMin);""",
"""  $('sbTz').textContent = fmtOffset(offsetAt(selUtc));""")
s = s.replace("""  $('selOff').textContent = fmtOffset(fx.tzOffsetMin);""",
"""  $('selOff').textContent = fmtOffset(offsetAt(selUtc));""")
s = s.replace("""  $('placedate').textContent = `${fmtDate(fx.dayStartUtc)} · ${fmtOffset(fx.tzOffsetMin)}`;""",
"""  $('placedate').textContent = `${fmtDate(fx.dayStartUtc)} · ${fx.tzId} · ${fmtOffset(offsetAt(fx.dayStartUtc))}`;""")
s = s.replace("""  $('dayLen').textContent = `当地日 ${fx.dayHours} 小时 · 点击定位`;""",
"""  $('dayLen').textContent = `当地日 ${fx.dayHours} 小时 · 点击定位`;""")

# 3) 右边界：滑动不得越过 [start, end)
s = s.replace("  selUtc = Math.round(fx.dayStartUtc + ratio * (fx.dayEndUtc - fx.dayStartUtc));",
"  selUtc = Math.min(fx.dayEndUtc - 1, Math.round(fx.dayStartUtc + ratio * (fx.dayEndUtc - fx.dayStartUtc)));")

# 4) 下一窗口文案：DST 日附带 UTC 偏移，当前/未来严格区分
s = s.replace("""    return { current: true, phase: cur[0], end: cur[2], mins,
      title: `当前处于${PHASE_CN[cur[0]]}时段`, sub: `预计 ${fmtHM(cur[2])} 结束 · 剩余约 ${mins} 分钟` };""",
"""    const offTxt = fx.dayHours === 24 ? '' : ` · ${fmtOffset(offsetAt(cur[2]))}`;
    return { current: true, phase: cur[0], end: cur[2], mins,
      title: `当前处于${PHASE_CN[cur[0]]}时段`,
      sub: `预计 ${fmtHM(cur[2])}${offTxt} 结束 · 剩余约 ${mins} 分钟` };""")
s = s.replace("""  return { current: false, phase: found[0], start: found[1], end: found[2],
    title: `下一可拍：${PHASE_CN[found[0]]} ${fmtHM(found[1])}–${fmtHM(found[2])}`,
    sub: `距现在约 ${Math.round((found[1] - selUtc) / 60000)} 分钟` };""",
"""  const offTxt2 = fx.dayHours === 24 ? '' : ` · ${fmtOffset(offsetAt(found[1]))}`;
  return { current: false, phase: found[0], start: found[1], end: found[2],
    title: `下一可拍：${PHASE_CN[found[0]]} ${fmtHM(found[1])}–${fmtHM(found[2])}${offTxt2}`,
    sub: `距现在约 ${Math.round((found[1] - selUtc) / 60000)} 分钟` };""")

# 5) 真实大屏检查器内容（不是空 aside）
s = s.replace("""function render() {""",
"""function renderInspector(w) {
  const box = $('inspector');
  if (!box) return;
  const p = phaseAt(selUtc);
  const rows = fx.windows.map((g) =>
    `<div class="kv">${PHASE_CN[g[0]]}<b class="num">${fmtHM(g[1])} – ${fmtHM(g[2])}</b></div>`).join('');
  box.innerHTML = `
    <div class="insp-title">参数检查器</div>
    <div class="kv">机位<b>${fx.name.split('·')[0].trim()}</b></div>
    <div class="kv">时区<b>${fx.tzId}</b></div>
    <div class="kv">所选时刻<b class="num">${fmtHM(selUtc)} ${fmtOffset(offsetAt(selUtc))}</b></div>
    <div class="kv">方位角<b class="num">${p.az.toFixed(1)}°</b></div>
    <div class="kv">高度角<b class="num">${p.alt.toFixed(1)}°</b></div>
    <div class="kv">光线阶段<b>${PHASE_CN[p.ph]}</b></div>
    <div class="insp-sub">${w.title}</div>
    <div class="insp-sub dim">${w.sub}</div>
    <div class="insp-title" style="margin-top:6px">计算出的窗口</div>
    ${rows || '<div class="kv">该日无窗口<b></b></div>'}
    <div class="insp-note">数据来自设计 fixture（SolarCalc 同公式族镜像，5 分钟采样）</div>`;
}

function render() {""")
s = s.replace("""  $('detBody').innerHTML = rows + `<div class="kv">日出前/后曙暮与白昼分段见上方色带（比例真实）<b></b></div>`;""",
"""  $('detBody').innerHTML = rows + `<div class="kv">日出前/后曙暮与白昼分段见上方色带（比例真实）<b></b></div>`;
  renderInspector(w);""")

# 6) 键盘支持：下一窗口卡片 Enter/Space
s = s.replace("""$('next').addEventListener('click', () => {
  const t = $('next').dataset.target;
  if (t) { selUtc = Number(t); render(); }
});""",
"""function activateNext() {
  const t = $('next').dataset.target;
  if (t) { selUtc = Number(t); render(); }
}
$('next').addEventListener('click', activateNext);
$('next').addEventListener('keydown', (e) => {
  if (e.key === 'Enter' || e.key === ' ' || e.key === 'Spacebar') {
    e.preventDefault();
    activateNext();
  }
});""")

# 7) 断点语义与文档一致：≥900 双栏（Expanded），≥1200 三栏（Large）
s = s.replace("/* ≥600：双栏 */\n@media (min-width:600px){",
"/* ≥600：加宽单列（仅放大图表，不切双栏） */\n@media (min-width:600px){")
s = s.replace("/* ≥900：曲线主区 + 右侧检查器 */",
"/* ≥900：Expanded —— 曲线主区 + 右侧检查器（真实内容） */")
s = s.replace(".inspector .instrument{margin:10px 12px 0}",
""".inspector{overflow:auto}
  .inspector > *{margin-left:12px;margin-right:12px}
  .insp-title{font-size:11px;letter-spacing:.12em;color:var(--muted);text-transform:uppercase;margin:14px 0 4px}
  .insp-sub{font-size:12px;color:var(--ink);margin-top:8px;line-height:1.5}
  .insp-sub.dim{color:var(--muted);font-size:11px}
  .insp-note{font-size:10px;color:var(--muted);margin-top:10px;line-height:1.5}
  .inspector .instrument{margin:10px 12px 0}""")
open(P, 'w', encoding='utf-8').write(s)
print('html fixed: offsetAt=', s.count('offsetAt('), 'inspector=', 'renderInspector' in s, 'kbd=', 'activateNext' in s)
