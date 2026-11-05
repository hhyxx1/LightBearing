# UI-1B-R2-FIX · 视觉验收报告

> 起点 `fc43f8b` → 本轮提交见汇报。分支 `fix/core-quality-audit`。
> 本轮只改原型、fixture 生成器、自检工具与设计文档；**未改任何生产 ArkTS**，
> 因此未重新构建/安装 HAP（不冒充设备通过）。`main` 未动。

## 1. P0 样式丢失的根因

`design/ui1b-r2/final-home.html` 引用了同目录的 `tokens.css`，但 UI-1B-R2 轮**只创建了**
`design/ui1b-r/ tokens.css`，`design/ui1b-r2/tokens.css` 从未入库 → 浏览器 404 →
全部 `var(--*)` 失效 → 回落到浏览器默认：深色底 + 默认黑字（几乎不可读）、按钮白底黑框。

**修复**：新增完整 `design/ui1b-r2/tokens.css`（147 行），并把「基础重置」写进同一文件：
`body` 背景/前景/字体、`button/select/input` 统一 `font:inherit` + 去默认外观、
`button` 最小高度 34、`.btn` 48、`select` 深色面、`:focus-visible` 琥珀描边、
`body.light` 全套暖纸浅色变量（含图表派生色 `--chart-*`）。

## 2. 修复前后

| | 修复前（P0） | 修复后 |
|---|---|---|
| 正文 | 默认黑字落在深蓝底（不可读） | `#F9FAF3` on `#0B1622`，对比度 **17.36:1** |
| 主按钮 | 白底黑框（浏览器默认） | `#FFBC6B` 底 + `#0B1622` 字，对比度 **10.99:1**，高 **48.0px** |
| 下拉框 | 系统默认白 | `rgb(21,40,54)` 深色面 + 浅字 |
| 图表刻度/图例 | 继承失效变量 | 通过 `--chart-*` 独立定义，深浅色各自可读 |

修复前的坏图已被覆盖，不再作为交付物；坏图状态可由「tokens.css 404」直接复现（删掉该文件重渲即可）。

## 3. CSS 加载与 computed style 检查

自检页 `design/ui1b-r2/shots/_selfcheck.html`（渲染结果 `final-selfcheck.png`，全部来自
`getComputedStyle` 实测，不是人工声明）：

```text
tokens.css      HTTP OK（同目录加载成功）
body bg         rgb(11, 22, 34)        = #0B1622
body fg         rgb(249, 250, 243)     = #F9FAF3
主按钮高度       48.0px（目标 ≥48）
主按钮底色       rgb(255, 188, 107)    = #FFBC6B
主按钮字色       rgb(11, 22, 34)
select 底色     rgb(21, 40, 54)        = #152836
正文对比度       17.36:1（AA 目标 4.5:1）
主按钮对比度     10.99:1
--amber         #FFBC6B   --touch 48px
结果            PASS（无 FAIL）
```

> 以 WCAG AA 4.5:1 作为**设计目标**，未声称其为 HarmonyOS 上架强制标准。

## 4. 深浅色对比度

- 深色：正文 17.36:1、主按钮 10.99:1、次要文字 `#93A9B6` on `#0B1622` ≈ 7.5:1；
- 浅色：正文 `#141F2A` on `#F4F1EA` ≈ 13:1，主色改 `#9A5A0C`（琥珀在浅底不达标，已换深琥珀）、
  青改 `#116C69`；图表曲线/地平线/网格/刻度/黄金蓝调色带**各自单独定义**，不只换曲线主色；
- 并排证据：`final-light-dark-pair.png`。

## 5. 360 / 390 / 430 视觉验收

- 三档均单列完整：上下文（机位/日期/时区）→ 仪表（34px 读数 + 阶段）→ 曲线（186px，0° 地平线 + 20° 刻度）
  → 全天分段带（26px，真实比例 + 图例）→ 下一窗口 → 明细折叠 → 三操作 → 底栏；
- 已修复：360 下的日期/长机位名截断（ellipsis）、分段带标题截断、底栏第 5 项被挤出、按钮第三列被切；
- **Compact 已隐藏右侧检查器**（信息已内联，避免长页尾重复）；
- 采集口径：固定 iframe 精确视口（无头浏览器最小窗口 496px 会造成假裁切，已在采集中修正）。

## 6. Expanded / Large 真实布局

| 宽度 | 结构 | 状态 |
|---|---|---|
| 600–899 | 加宽单列（仅图表更高），**不是双栏**（文档与实现一致，无虚假声明） | 已渲染 |
| 900–1199（Expanded） | 左侧曲线主区 + 右侧 320 参数检查器：机位/时区/所选时刻+偏移/方位/高度/阶段/当前窗口/计算出的窗口列表 | `final-expanded.png`，**DESIGN_PREVIEW** |
| ≥1200（Large） | 232 原生导航 + 中央观测 + 340 检查器（内容同上） | `final-large.png` + `final-inspector-zoom.png`，**DESIGN_PREVIEW** |

检查器不再是空 `aside`：内容由 `renderInspector()` 用同一份 fixture 渲染，实测可见（见局部放大图）。

## 7. DST 25h 与重复本地时刻

- fixture 增加 `tzId`（`America/New_York` 等），每个 5 分钟样本携带**该绝对时刻的真实偏移** `s[4]`；
- 渲染改为 `offsetAt(utc)`，不再用固定 `-300`；
- 自测：`01:30 EDT = -240`、`01:30 EST = -300` → **PASS**；
- 25 小时的 `dayHours` 由真实 `dayEndUtc - dayStartUtc` 得出（`nyDst` 显示 25h）；
- 25h 日的时刻与「下一窗口」文案会附带 UTC 偏移，消除重复 01:00 的歧义；
- 1969 fixture（负 UTC）仍正常出图（now alt 31.79°）。
- **与 API 26 的差异**：原型用浏览器 `Intl.DateTimeFormat`；生产用已验证的 `TimeUtil.resolveLocal`
  （GAP/OVERLAP/UNAVAILABLE 有显式状态）。两者在已测用例上一致，但未做全量时区交叉验证。

## 8. 分段日界修正与自动测试

- 采样循环改为 `for (t = start; t < end; t += STEP)`（**半开区间**），尾段 `min(t+STEP, end)` 裁剪；
- 生成后强制「首段从 start、末段到 end」，并输出 `segmentCoveredMs` 供断言；
- 自测（`gen-fixtures.js` 末尾，`node` 直接跑）：

```text
selftest 23h   covered=23.00h PASS
selftest 23.5h covered=23.50h PASS
selftest 24h   covered=24.00h PASS
selftest 24.5h covered=24.50h PASS
selftest 25h   covered=25.00h PASS
selftest DST 01:30 EDT=-240 01:30 EST=-300 PASS
SELFTEST ALL PASS
```

- 精度限制（如实说明）：fixture 为 5 分钟采样，窗口边界是**近似值**（±5 分钟）；
  生产 `SolarCalc.lightWindows` 为更细的求解边界，两者不可混用；原型仅做视觉与层级评审。

## 9. 仍未验证的设备与系统能力

折叠屏（外/内屏）、双/三折叠、平板横竖屏、2-in-1 自由窗口与键鼠、设备接续/跨端协同、
`animateTo`/`sharedTransition` 在 API 26 的实际表现、系统「减少动态效果」读取 API、
`Intl` 与 `TimeUtil` 的全时区一致性。上述均为 DESIGN_PREVIEW 或 NOT_RUN。

## 10. 是否具备交付用户最终确认的条件

**具备（Compact 为主）**：深色/浅色均可读且自检 PASS，360/390/430 完整，DST/1969/极昼/极夜
四类场景的时间语义正确，分段带按真实比例且有图例，下一窗口只出现一处并支持键盘。

**仍需用户确认的两点**：(a) 是否接受 Large/Expanded 仅为设计预览（无真机）；
(b) 是否接受极短窗口在 24h 比例下偏窄、需靠「下一窗口」与图例补偿（不放大失真）。

确认后再进入 ArkTS 实现（`ObservationPanel` 拆分 + `DayBand` + 下一窗口纯函数），本轮不动生产代码。
