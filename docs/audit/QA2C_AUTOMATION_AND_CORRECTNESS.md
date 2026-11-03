# QA-2C · 最后正确性与真机自动化专项验收

> 基准 `d0917a7`，分支 `fix/core-quality-audit`，设备 MIA-AL00 / HarmonyOS 7 / API 26。
> 本轮修复「搜索异常被 UI 隐藏」「窗口匹配统计口径」「CSV 跨行与非标量 Unicode」，
> 并重新尝试无人工参与的真机 UI 自动化。未改 Schema、未删数据/机位、未动 main、无新增用户功能。

## 1. 搜索异常不再被 UI 隐藏（P1）

**改动**：`services/ReverseViewState.ets`、`pages/ReversePage.ets`

根因：`ReverseViewState.of()` 在 `hasCompleted=false` 时提前返回 `IDLE`，而 `runSearch()` 在
开头把 `searched=false`，异常路径又只写 `errorText/lastDecision` → 失败警示被 IDLE 分支吞掉。

修复：

1. 终态判定增加「执行痕迹」条件：`decision.kind === FAILED` 或 `errorText` 非空时，即使
   `hasCompleted` 尚未置位也进入 `FINAL`（失败终态）；
2. `runSearch()` 的 `catch` 里补 `this.searched = true`（表示「已经执行过」）；
3. 表单保持可用；失败不显示「没有符合条件的时段」；`Job` 走 `FAILED`；不写成功历史；
4. 新搜索开始时 `searched=false` + `lastDecision` 重置，旧警示立即消失。

**红绿证据**

```text
红灯（生产代码未改，仅加用例）：Tests run: 184, Failure: 2
  exception_run_shows_warning_even_before_completion_flag
  exception_with_partial_windows_marks_partial_and_blocks_plan
绿灯（修复后）：Tests run: 184, Failure: 0
```

## 2. 窗口匹配统计口径修正（P1）

**改动**：`entry/src/test/WindowMatching.test.ets`

旧实现的问题：参考窗口找不到重叠生产窗口时，只要「时间相邻 ≤2s」就**不计漏报**，导致召回虚高。

新统计口径：

| 规则 | 实现 |
|---|---|
| 一对一分配 | 所有「真正重叠」的 (参考, 生产) 对按**重叠时长降序**全局贪心分配，双方各只占一次 |
| 漏报 | 参考窗口没有分配到任何重叠生产窗口 → **一律计入 missed** |
| 邻近 | 仅记录 `adjacentOnly`（诊断），不减漏报 |
| 拆分 | 一个参考窗口与 **>1** 个生产窗口真正重叠 |
| 合并 | 一个生产窗口与 **>1** 个参考窗口真正重叠 |
| 质量 | 参考与生产统一用 `azErr + altErr`，统计生产相对参考的差值（`refBestGap`） |

移除了原先 `if (adjacent) 不计 missed` 的分支；`start/end/best` 误差仍逐匹配对统计。

**合成用例（7 条，全部通过）**

| 用例 | 断言 |
|---|---|
| 两窗口相隔 1 秒无重叠 | matched=0、missed=1、adjacentOnly=1、unmatchedProd=1 |
| 一个参考窗口 ↔ 两个生产窗口 | matched=1、unmatchedProd=1、split=1 |
| 两个参考窗口 → 一个生产窗口 | matched=1、missed=1、merged=1 |
| 生产窗口跨两个参考窗口 | matched=1、missed=1、merged=1 |
| 生产侧完全缺失 | missed=2、adjacentOnly=0 |
| 边界偏移但仍有重叠 | matched=1、maxStartError=9000ms |
| 完美一对一 | matched=2、split=merge=0、误差 0 |

**七个太阳场景用新口径重算**（仍全部一对一、无漏报、无拆分/合并；起点/终点/best 误差 ≤2 秒）。
统计未沿用旧值，全部由新实现重新产出。

## 3. CSV 跨行字段与非标量 Unicode（P2）

**改动**：`utils/CsvCodec.ets`、`services/ExportService.ets`

- `parse()` 改为**整篇状态机**：引号内的换行属于字段内容，不再先 `split('\n')`；
- 支持 CRLF 与孤立 CR/LF；支持双引号转义、逗号、空字段、开头 UTF-8 BOM；
- `Checksum.encodeUtf8()` 对**孤立代理项**输出 `U+FFFD`（`EF BF BD`），绝不产生非法 UTF-8；
- 合法代理对（emoji）仍按 4 字节编码；导出格式（CRLF + BOM）保持不变。

新增/更新用例（`ExportBytes.test.ets`）：

```text
csv_multiline_quoted_field_roundtrip       引号内 '\n' 保持为同一字段，行数不膨胀
csv_parses_lf_crlf_and_bom                LF / CRLF / BOM 三种输入
csv_keeps_empty_fields_and_quotes         空字段与引号往返
utf8_replaces_lone_surrogates_with_fffd   'a'+U+D800+'b' → 5 字节，中间 EF BF BD
utf8_bytes_for_chinese_and_emoji          中文🙂 = 10 字节
checksum_matches_independent_fnv1a        Math.imul 版 FNV-1a == 独立 BigInt 实现
```

## 4. 真机 UI 自动化方案与执行证据（P1）

### 4.1 能力核对（真机执行）

```text
hdc shell uitest uiInput help
支持：click / doubleClick / longClick / swipe / drag / fling / dircFling / keyEvent / inputText
（swipe/fling 参数：[velocity] 200–40000；dircFling <direction 0-3> [velocity] [stepLength]）
```

### 4.2 本轮实际执行到的步骤

| 步骤 | 结果 |
|---|---|
| 确认 LightBearing 前台 | ✅（`FOREGROUND True`） |
| 从首页进入「反向寻光」 | ✅（`ENTRY_FOUND True`、`ON_REVERSE_PAGE True`） |
| 用 `dircFling 2` 在滚动区上滑 | ✅（此前失败的「按钮滚出可视区」已解决） |
| 按可见文本定位「搜索候选时段」 | ✅（`Button @ (612, 2345)`） |
| 点击搜索按钮 | ✅（点击事件已注入） |
| 等待摘要文本出现 | ❌ **未出现**（15 秒 6 次采样、最长 180 秒轮询，页面可见文本数恒为 31） |

### 4.3 阻断结论

**QA-08 维持 BLOCKED**，但与上一轮相比阻断点前移且更具体：

- 已不再是「定位不到按钮」（滑动 + 文本可见性已解决）；
- 现在的问题是：**点击搜索后页面没有任何终态文案可见**（既不出现「用时/窗口」，也不出现
  「失败/已取消/没有符合条件」），可见文本集合完全不变。
- 可能原因（未验证，不伪装为结论）：按钮被软键盘/浮层遮挡导致点击被吞；或摘要渲染在
  视口之外、`dumpLayout` 只返回可见节点；或搜索在参数校验处直接返回（toast 瞬时消失）。
- 因此 **1/14/365 天 UI 搜索耗时、点击取消→Job CANCELLED 延迟、进度正确性仍然没有数值**，
  会话层 `cancel()` 的 0ms 仍是状态置位时间，不作为 UI 延迟。

### 4.4 不用 `runSearch()` 直调替代

没有绕过 UI 调用 `ReversePage.runSearch()` 来伪造端到端数据——那无法验证真实交互。

## 5. 真机截图与视觉审查（P2）

- 本轮**未新增**截图（自动化未能稳定走到「有结果」的界面状态）；沿用 QA-2B 的 5 张真实设备截图：
  `qa2b_01_home` / `qa2b_02_reverse` / `qa2b_03_planner` / `qa2b_04_sunpath` / `qa2b_05_more`；
- 本轮新增 2 张：`qa2c_01_home.jpeg`（首页）、`qa2c_02_planner.jpeg`（计划）；
- 逐页视觉审查进度（真实截图逐一确认）：
  - **首页：已审查（浅色主题，默认字体缩放）** —— 标题/副标题换行正常、卡片与 KPI 三列无截断、
    底部 Tab 5 项均完整可见、无遮挡；未见布局缺陷；
  - 其余页面（太阳轨迹、反向寻光结果区、进度浮层、计划编辑、日历、对比、罗盘、设置、机位库）：
    **NOT_RUN**（本轮未逐页确认）；
- 原生 DatePicker/TimePicker 的**模拟滑动手势**未执行（未进入可验证状态的表单），
  **真人手指验证**继续保持未验证；不得用注入改显示值当作通过。

## 6. 测试与构建

```text
宿主机：Tests run: 195, Failure: 0, Error: 0, Pass: 195
        （181 → 195：异常终态 3 条、匹配器合成 7 条、CSV 跨行/代理项 4 条）
外围太阳参考：全部通过
应用 HAP：BUILD SUCCESSFUL
真机：本轮未重跑 KernelPerfReal / TimeZoneReal（无相关生产改动），不作为本轮执行证据
```

## 7. 本轮真正修复的缺陷

| 编号 | 缺陷 | 证据 |
|---|---|---|
| Q2C-01 | 搜索抛异常时页面停在 IDLE，失败原因不可见 | 红灯 2 条 → 绿灯 |
| Q2C-02 | 匹配器用「相邻 ≤2s」免除漏报，召回虚高 | 7 条合成用例 + 新口径重算 7 个太阳场景 |
| Q2C-03 | `CsvCodec.parse` 无法回读引号内换行；孤立代理项会输出非法 UTF-8 | CSV 跨行/CRLF/BOM/代理项用例 |

## 8. 仍然 BLOCKED / NOT_RUN

- **BLOCKED**：UI 端到端搜索耗时、UI 取消延迟、365 天 UI 搜索、进度正确性（阻断点见 §4.3）；
- **NOT_RUN**：逐页视觉审查、原生滚轮的模拟手势与真人手指验证、数据库迁移/异常导入/异常退出恢复、
  全天/全年一对一召回率（当前只有 2 小时区间、1 秒分辨率）、真机文件选择器保存链路（取消/磁盘满）。

## 9. 是否具备进入 QA-3 的条件

**建议：暂不进入 QA-3（功能扩展/性能专项）**，先补齐一项能力即可大幅降低风险：

1. 打通 UI 自动化的「点击后终态可见」一环（三个候选手段：给搜索按钮所在的滚动容器一个可 dump 的
   结构属性；点击前先 `keyEvent Back` 收键盘并确认节点 `clickable=true`；或改用 ArkTS `ohosTest`
   的 UI 驱动接口做最小能力探针）；
2. 补一次逐页截图审查（本轮已有采集脚本，缺的是逐页确认）；
3. 其它未验证项（迁移、异常恢复、真机导出链路）可在 QA-3 并行安排。

在 UI 端到端与视觉审查仍为空的情况下，已知缺陷面很小（Q2C-01～03 已修复且回归），
但**发布信心主要缺在「未验证」而不是「已知缺陷」**。
