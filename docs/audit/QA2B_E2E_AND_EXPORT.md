# QA-2B · 导出、搜索验收与真实 UI 流程

> 基准 `e69131b`，分支 `fix/core-quality-audit`，设备 MIA-AL00 / HarmonyOS 7 / API 26。
> 本轮处理 QA-05 / QA-07 / QA-08 与复审新增的「搜索状态重置」「计划并发保存」。
> QA-06（大组件拆分）按要求继续推迟；未改 Schema、未删数据、未动 TEST 机位、未碰 main。

## 1. 搜索旧状态清理（复审 P1）

**改动**：`services/ReverseViewState.ets`、`pages/ReversePage.ets`

- `ReverseViewState` 新增 `SearchPhase`（`IDLE` / `RUNNING` / `FINAL`）与 `showProgressPanel`；
- `ReverseViewState.of(initError, ready, hasPlace, searching, hasCompleted, decision, windowCount)`：
  - `searching=true` → `RUNNING`：**不展示上一轮**警示、部分结果、结果列表、空态提示，只显示进度面板；
  - 未搜索过 → `IDLE`：无警示、无结果、无空态；
  - 结束后 → `FINAL`：按 decision 展示。
- `runSearch()` 开始时额外重置 `searched=false` 与 `lastDecision=new RunDecision()`（此前只清 candidates/windows/errorText）。

覆盖的状态组合（`ReverseViewState.test.ets`，10 条）：上一轮 DONE_OK/DONE_EMPTY/FAILED 无结果/FAILED 有部分结果/CANCELLED/STALE 之后再搜索、进行中隐藏旧警示、初始化失败与搜索失败分离。

## 2. 计划并发保存风险（复审 P1）

**改动**：`services/PlanPlaceGuard.ets`、`pages/PlannerPage.ets`

```ets
// 编辑已有计划但记录已不存在 → 中止，不再静默重建同 ID 的残缺对象
static requireExistingPlan(editId: string, found: boolean): string
```

页面行为：`hint` + toast 显示「该计划已被删除或不存在，无法保存。请返回列表刷新后重试。」并 **return**，不写库。
新建计划（`editId` 为空）不受影响；原机位缺失但计划记录存在时仍走 QA-2A 的快照保护。

测试（`PlanPlaceGuard.test.ets`，10 条）：记录消失被拒、记录存在允许、新建允许，以及 QA-2A 的 8 条快照/换机位/UTC 保持用例。

## 3. CSV 导出：编码、BOM、字节数与校验和（QA-05）

**改动**：`services/ExportService.ets`、`utils/CsvCodec.ets`

| 项 | 结论 |
|---|---|
| BOM | 已加：文件字节以 `EF BB BF` 开头，满足 Excel 识别中文 |
| 真实字节 | `ExportService.buildUtf8File(content)` 与 `writeText` 共用同一实现，避免两套逻辑漂移 |
| 字节数 | `ExportResult.bytes` = BOM + UTF-8 正文字节数；写入不完整（`written !== expected`）返回失败，不返回成功 |
| 句柄 | 写入与关闭放进 `try/finally`，异常路径也会关闭文件 |
| 校验和 | `Checksum.ofBytes(真实写出字节)`；`ofText` 改为先 UTF-8 编码再哈希（此前按 UTF-16 code unit `&0xFF` 计算，与文件字节不一致） |
| FNV-1a | **修复真实缺陷**：`hash * 0x01000193 >>> 0` 会超出 2^53 精度导致低位错误，改为 `Math.imul(hash, 0x01000193) >>> 0` |
| Parser | `CsvCodec.parse` 先剥离 BOM，避免第一列表头带隐藏字符 |

字节级验证（`ExportBytes.test.ets`，7 条）：

```text
'中文🙂' → 10 字节：E4 B8 AD / E6 96 87 / F0 9F 99 82
CSV 文件：EF BB BF + 正文 UTF-8，逐字节与正文一致
ofText(t) == ofBytes(utf8(t))
ofText 结果 == 独立 BigInt FNV-1a 实现（含 BOM 的文件字节同样一致）
'中中中中'(12 字节) 与 'abcd'(4 字节) 字符数相同但校验和不同 → 证明不是按字符长度
parse('\uFEFF日期,事件') → 首列 '日期'（无 BOM 残留）
CSV 往返保持逗号与引号
```

## 4. 窗口一对一参考匹配（QA-07）

**新增**：`entry/src/test/WindowMatching.test.ets`

- 生产侧直接调用真实 `ReverseSearch.searchWindowsInRanges()`（非 Node 镜像，避免漂移）；
- 参考侧在同一测试内以 **1 秒步长**独立扫描 `SolarCalc.position`，双容差分别判定后聚合窗口；
- 匹配规则：按参考窗口起点有序，为每个参考窗口分配**尚未占用**且区间重叠的生产窗口（一对一，不重复计分）；
- 额外统计拆分（一个参考窗口对应多个生产窗口）与合并（一个生产窗口覆盖多个参考窗口）用于诊断。

| 场景 | 参考窗口 | 生产窗口 | 匹配 | 漏报 | 未匹配生产 | 起点误差 | 终点误差 | best 误差 | 拆分/合并 |
|---|---|---|---|---|---|---|---|---|---|
| 对称 3°（上海 2h 区间） | 1 | 1 | 1 | 0 | 0 | 0 ms | 0 ms | 64 ms | 0 / 0 |
| 极短窗口 0.1° | 1 | 1 | 1 | 0 | 0 | ≤2 s | ≤2 s | ≤2 s | 0 / 0 |
| 非对称 3° / 0.5° | 1 | 1 | 1 | 0 | 0 | ≤2 s | ≤2 s | ≤2 s | 0 / 0 |
| 宽容差 8°/8°（多窗口/长窗口） | 参考数 | 相同 | 全部 | 0 | 0 | ≤2 s | ≤2 s | — | 0 / 0，生产窗口互不重叠 |
| 无命中（高度 89°） | 0 | 0 | — | 0 | 0 | — | — | — | — |
| 高纬 Tromsø 69.65° | 1 | 1 | 1 | 0 | 0 | ≤2 s | ≤2 s | — | 0 / 0 |
| 0°/360° 正北目标 | 1 | 1 | 1 | 0 | 0 | ≤2 s | — | — | 0 / 0 |

限制（必须连同结论一起引用）：参考扫描固定 1 秒分辨率，**短于 1 秒**的窗口同样可能漏；
每个用例只在给定 2 小时区间内扫描，不能据此宣称连续时间上的全局完备或全天一对一召回率 100%。

## 5. 真实 UI 搜索与取消（QA-08）

**改动**：`pages/ReversePage.ets`、`components/Widgets.ets` — 作为正式可访问性设计加入稳定 ID：

```text
reverse_search_btn   搜索按钮
reverse_summary      搜索摘要
progress_cancel_btn  进度面板「取消任务」
```

**实测结论：仍为 BLOCKED**，本次给出了新的、具体的阻断原因：

1. 安装本轮构建后在真机 `uitest dumpLayout` 中，`id` 属性**只出现系统节点**（`StatusBarBox` 等），
   自研组件 ID 未出现在 dump 中（`APP_IDS = []`），因此无法按 ID 定位控件；
2. 退回按文本定位时，编辑「搜索天数」等输入框后**搜索按钮滚出可视区**，`uitest uiInput` 没有
   「滚动到节点」能力，之前的多次失败均源于此；
3. 因此 UI 端到端搜索耗时、UI 点击取消到 Job CANCELLED 的延迟、365 天 UI 搜索耗时**本轮依旧没有数值**，
   继续保持 BLOCKED；会话层 `session.cancel()` 的 0 ms 仍只是状态置位，不冒充 UI 延迟。

## 6. 真机截图

本轮采集（真实设备，验收路径下）：

| 文件 | 页面 |
|---|---|
| `docs/screenshots/qa2b_01_home.jpeg` | 首页（今日光线） |
| `docs/screenshots/qa2b_02_reverse.jpeg` | 反向寻光输入区 |
| `docs/screenshots/qa2b_03_planner.jpeg` | 拍摄计划 |
| `docs/screenshots/qa2b_04_sunpath.jpeg` | 太阳轨迹 |
| `docs/screenshots/qa2b_05_more.jpeg` | 更多/设置入口 |

**逐页视觉审查（暗色主题、小屏、横竖屏、遮挡/截断判定）本轮未完成** → 记 NOT_RUN；
截图仅作为设备实拍证据，不代表布局已通过。

## 7. 测试与构建

```text
宿主机：Tests run: 181, Failure: 0, Error: 0, Pass: 181
        （163 → 181：新增 WindowMatching 7 条、ExportBytes 7 条、ReverseViewState +3 条、PlanPlaceGuard +2 条，
          并修正了此前 encodeUtf8/BOM/FNV 的实现缺陷）
外围太阳参考：全部通过
应用 HAP：BUILD SUCCESSFUL
真机：本轮未重跑 KernelPerfReal / TimeZoneReal（改动仅涉及导出、计划保存守卫、搜索页渲染状态与测试，
      真机两套用例沿用 e69131b 的结果，不作为本轮执行证据）
```

## 8. 修复前后证据

| 项 | 修复前 | 修复后 |
|---|---|---|
| `Checksum.encodeUtf8` | 依赖 `util.TextEncoder().encodeInto()`，在 API 26 宿主机测试返回 **0 字节** | 手写 UTF-8 编码（含代理对），字节级用例通过 |
| FNV-1a | `hash * prime >>> 0` 精度溢出 → 与标准实现不一致（`53e2dbd9` vs `e046cb6f`） | `Math.imul` 修正，与 BigInt 独立实现完全一致 |
| CSV 文件 | 无 BOM；校验和基于 UTF-16 code unit | BOM + UTF-8 字节校验和；解析剥离 BOM |
| 搜索状态 | 上一轮 `lastDecision/searched` 未重置，新搜索可能显示旧警示 | `SearchPhase` + 完全重置，10 条状态组合用例 |
| 计划并发 | 记录消失时静默 `new ShootPlan()` 同 ID 重建 | 明确提示并中止保存 |

## 9. 仍未验证 / 尚未解决

1. **QA-08 全部指标**（UI 搜索耗时、UI 取消延迟、365 天 UI 搜索、进度正确性）— BLOCKED（见 §5）；
2. **QA-06** 大组件拆分（Widgets 990 行、PlannerPage 821+ 行）— 按要求推迟；
3. 真机逐页视觉审查与暗色/小屏/横竖屏 — NOT_RUN；
4. 一对一匹配仅在 2 小时区间、1 秒分辨率下验证；全天/全年召回率与亚秒窗口未验证；
5. CSV 仅在宿主机字节级验证；真机文件选择器保存链路（含用户取消、磁盘写满）未做真机验证；
6. 数据库迁移、异常导入、异常退出恢复 — 仍未验证；
7. QA-09 原生 DatePicker/TimePicker 手指操作 — 仍未验证。

## 10. 剩余风险与是否进入 QA-3

- 数据正确性：QA-01/02/03/04（QA-2A）+ QA-05（本轮）已修复并有宿主机证据；计划并发风险已封闭；
- 剩余风险集中在**未验证面**而非已知缺陷：UI 端到端性能、视觉布局、迁移与恢复、亚秒窗口与全天匹配；
- **建议**：在进入 QA-3 之前，至少补一次真机 UI 端到端测量（需要能滚动到节点的自动化手段或明确的手工计时表）
  与逐页截图审查，否则「UI 可用性」始终只有源码级信心。
