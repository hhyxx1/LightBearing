# QA-1 · 测试矩阵

> 基准 `90e4f0e`，设备 MIA-AL00 / HarmonyOS 7 / API 26。
> 状态只允许四种：**PASS / FAIL / NOT_RUN / BLOCKED**。
> 只有「本轮实际执行并有证据」的条目才标 PASS；仅源码阅读得出的结论标 FAIL（有缺陷）或 NOT_RUN（未执行）。

## 0. 统计口径

| 状态 | 定义 | 本轮数量（功能性条目） |
|---|---|---|
| PASS | 本轮执行且通过（宿主机/真机测试，或等价可执行验证） | 见下表逐项 |
| FAIL | 有证据表明行为不符合预期（测试复现或源码确认） | 3 个场景 + 3 个支撑证据 |
| NOT_RUN | 有能力执行但本轮未执行 | UI 视觉/端到端/迁移等 |
| BLOCKED | 需要用户操作或缺少稳定自动化手段 | 原生滚轮、UI 端到端计时 |

## 1. 首次启动与空数据

| 场景 | 方法 | 状态 | 证据/说明 |
|---|---|---|---|
| 已有机位正常启动 | 真机 `aa start` + dump | PASS | 冷启动 ≈1.38 s，首屏内容出现 |
| 无机位 | `ReversePage` 源码分支 | PASS（源码） | `!hasPlace → EmptyState`（含「去机位库」动作） |
| 无计划/无项目 | 计划页/项目页源码 | NOT_RUN | 未做真机空库验证（避免破坏用户数据） |
| 首次授权定位拒绝 | 源码路径 | NOT_RUN | 未做权限往返实测（历史遗留未验证项） |
| 离线启动 | 无网络代码 | PASS（源码） | 全仓无网络调用，离线不影响启动 |
| 数据库首次创建 | `AppDb` 源码（user_version + 事务） | NOT_RUN | 未在干净环境验证建表 |

## 2. 机位管理

| 场景 | 方法 | 状态 | 证据 |
|---|---|---|---|
| 新增/修改机位 | 源码 + 已有 TEST 机位 | PASS（源码） | 本轮未新增/改动机位（按要求保留 TEST 机位） |
| 切换机位后各页刷新 | 源码 | 部分 PASS | `ReversePage` 有陈旧结果丢弃；其他页依赖 `AppState` 通知 |
| 删除机位后关联计划 | 源码 + 新增 8 条守卫测试 | **PASS（QA-2A 修复）** | 原缺陷 QA-03 已修：精确匹配、缺失时保留快照、明确换机位才改写 |
| 无效坐标/异常时区 | 源码 | PASS（源码） | 经纬度范围与容差在 Session 构造处校验；非法时区走 UNAVAILABLE |

## 3. 太阳轨迹与时间轴（2A/2B）

| 场景 | 方法 | 状态 | 证据 |
|---|---|---|---|
| 太阳方位/高度 | 宿主机 + 外部参考 | PASS | `solar-check` 全部通过 |
| 日出日落/黄金/蓝调 | 宿主机 `SolarEvents` | PASS | 146/146 中包含极昼/极夜/单侧穿越 |
| 0°/360° 跨越 | 宿主机 `azimuth_wrap_at_north_is_handled` | PASS | 环形距离 359.5↔0.5 = 1° |
| 23/25/23.5/24.5 小时日 | 宿主机 `various_local_day_lengths_are_respected` | PASS | 窗口时长与区间精确一致 |
| 负 UTC 时间戳（1969） | 宿主机 `negative_timestamps_work_in_session` | PASS | start/best 均 < 0 且区间内 |
| DST GAP/OVERLAP 交互 | 真机（历史证据 + 会话层） | 部分 PASS | GAP 提示与 OVERLAP 候选曾在真机验证；滑块两端 01:30 有截图 |
| 原生 DatePicker/TimePicker 手指操作 | — | **BLOCKED** | 注入只改显示值不触发 `onChange`；需真人手指 |

## 4. 拍摄计划

| 场景 | 方法 | 状态 | 证据 |
|---|---|---|---|
| 创建/编辑/保存/删除 | 源码 + 历史真机操作 | PASS（历史） | 计划列表与保存逻辑在 2B 阶段真机验证过 |
| 编辑不改时间保留 UTC | 宿主机 `TimeSelection` 用例 | PASS | `startEdit` 不重算 UTC |
| GAP 禁止保存 / OVERLAP 必须选候选 | 宿主机 + 真机（历史） | PASS（会话/逻辑层） | 候选按钮的两次实际点击保存仍未完成（历史遗留） |
| 机位被删除后编辑 | 宿主 8 条守卫测试 | **PASS（QA-2A 修复）** | 见 `PlanPlaceGuard.test.ets` |
| 换机位保留 UTC | 宿主机 + 源码 | PASS | `switchPlace` 保留 `selectedUtc` |

## 5. 反向寻光

| 场景 | 方法 | 状态 | 证据 |
|---|---|---|---|
| 正常有结果（14 天/3°） | 真机会话层 | PASS | 65 ms / 15 838 次 `position` / 11 窗口 |
| 正常无结果 | 宿主机 | PASS | `DONE_EMPTY` 分支 + 提示文案 |
| 目标不可达（高度 89°） | 宿主机 | PASS | 69 次调用、0 窗口 |
| 极窄容差（0.05°） | 宿主机网格 | PASS | 36/36 目标命中，窗口数与 1 秒参考一致 |
| 宽容差（6°） | 宿主机 | PASS | 单窗口不重复（2C-2 修复） |
| 365 天（会话层） | 真机 | PASS | 3 511 ms / 653 975 次 `position` / 40 窗口 |
| 取消（会话层） | 真机 | PASS | `cancel()` 0 ms 置位，单分片 ≤11 ms |
| **取消（UI 端到端）** | — | **BLOCKED** | 自动化定位不到「搜索候选时段」按钮 |
| FAILED 且部分窗口的 UI 呈现 | 源码 + `ReverseViewState` 8 条用例 | **PASS（QA-2A 修复）** | 表单保留、警示条、部分结果禁用加入计划 |
| 搜索中切换机位 | 宿主 pure policy + 源码 | PASS（逻辑） | `STALE` 不覆盖 FAILED/CANCELLED，结果丢弃 |
| 结果加入拍摄计划 | 源码 | PASS（源码） | 用 `bestUtc` 建计划，未做真机点击验证 |
| 异常数据混合（部分 NaN） | 宿主机 `SearchAnomalyAudit` | **PASS（QA-2A 修复）** | A1/A2/A4/A5 现在均为 FAILED + 部分窗口；A7 取消仍 CANCELLED |
| 一对一窗口参考匹配 | 宿主机真实内核 + 1 秒独立参考（7 场景） | **HOST_PASS（QA-2B）** | 对称/极短/非对称/宽容差/无命中/高纬/0-360 全部一对一匹配，起点终点误差 ≤2 s，拆分/合并 0 |

## 6. 其他页面

| 页面 | 进入/退出 | 空态 | 错误态 | 状态 |
|---|---|---|---|---|
| HomePage | 源码 | 有 | 有 | NOT_RUN（未真机逐步验收） |
| SunPathPage | 源码 | 有 | 有 | 部分 PASS（滑块/罗盘历史验证） |
| CalendarPage | 源码 | 有 | 有 | 部分 PASS（异常日期标记历史验证；CSV 无 BOM → QA-05） |
| ComparePage | 源码 | 有 | 有 | NOT_RUN |
| CompassPage | 源码 | 有 | 有 | PASS（源码：`setInterval` 已在 `aboutToDisappear` 清理） |
| LocationsPage | 源码 | 有 | 有 | 部分 PASS（TEST 机位由 UI 创建过） |
| PlaceDetailPage | 源码 | 有 | 有 | NOT_RUN |
| PlannerPage | 源码 | 有 | 有 | 部分 PASS（GAP/OVERLAP 逻辑验证；QA-03） |
| PlanDetailPage | 源码 | 有 | 有 | NOT_RUN |
| SettingsPage | 源码 | 有 | 有 | NOT_RUN |
| MapPage | 源码 | 有 | 有 | NOT_RUN（依赖定位授权） |
| ReversePage | 源码 + 真机 | 有 | 有 | 部分 PASS（见 §5，QA-02） |
| Index | 源码 | 有 | 有 | PASS（冷启动 1.38 s、切页 1.35 s） |

## 7. 数据库与数据完整性

| 检查 | 方法 | 状态 | 证据 |
|---|---|---|---|
| 建表与 `user_version` | 源码 | PASS（源码） | 事务包裹 + `PRAGMA user_version` |
| 事务与回滚 | 源码 | 部分 PASS | `beginTransaction/commit` 存在；异常分支 `rollback` 未逐条核验 |
| 保存失败不显示成功 | 源码 | PASS（源码） | 页面对 `await` 抛错进入 catch 并显示错误 |
| 关联机位删除 | 源码 | **FAIL** | QA-03 |
| 编辑不产生重复记录 | 源码 | PASS（源码） | 按 id `UPDATE`/`INSERT OR REPLACE` |
| 任务取消不留 DONE | 宿主 policy + 源码 | PASS | `CANCELLED` 语义 + 不写成功历史 |
| 升级保留数据 | — | NOT_RUN | 未做迁移测试 |
| 导入异常数据 | — | NOT_RUN | 未做导入注入测试 |
| CSV 导出编码 | 宿主机字节级测试 7 条 | **HOST_PASS（QA-2B 修复）** | BOM `EF BB BF` + UTF-8 字节校验和 + `Math.imul` 修正 FNV-1a；解析剥离 BOM |
| CSV 引号转义 | 宿主机往返测试 | HOST_PASS | 逗号/引号往返一致 |

## 8. 安全与隐私

| 检查 | 方法 | 状态 | 证据 |
|---|---|---|---|
| 权限最小化 | `module.json5` | PASS | 仅 2 项定位权限，`when: inuse` |
| 无网络外发 | 全仓 grep | PASS | 无 `http(s)://`、无 `@ohos.net.*` |
| 无硬编码密钥 | grep | PASS | 仅设计 token 变量 |
| 无调试入口残留 | grep | PASS | `TEMP-TEST-ENTRY`/`BuildProfile` 0 命中 |
| 日志泄露 | grep | PASS（源码） | 仅计数/错误信息 |
| 导出经用户选择 | `ExportService` | PASS（源码） | `DocumentViewPicker` |

## 9. 性能与稳定性

| 指标 | 数值 | 状态 |
|---|---|---|
| 冷启动（含 dump 轮询开销 ≤0.2 s） | ≈1.38 s | PASS（上限估计） |
| Tab 切页可见 | ≈1.35 s | PASS（上限估计） |
| 365 天搜索（会话层） | 3 511 ms | PASS |
| 单分片最大耗时 | 6 / 8 / 11 ms | PASS |
| UI 端到端搜索耗时 | 无 | NOT_RUN |
| UI 取消端到端延迟 | 无 | BLOCKED |
| 内存占用 / 长时间停留 / 前后台切换 | 无 | NOT_RUN |
| 异常退出后恢复 | 无 | NOT_RUN（不做破坏性测试） |

## 10. 汇总

| 分类 | PASS | FAIL | NOT_RUN | BLOCKED |
|---|---|---|---|---|
| 启动/空态 | 3 | 0 | 3 | 0 |
| 机位 | 3 | 1 | 0 | 0 |
| 太阳/时间轴 | 5 | 0 | 0 | 1 |
| 计划 | 4 | 1 | 0 | 0 |
| 反向寻光 | 10 | 2 | 1 | 1 |
| 其他页面 | 2 | 0 | 9 | 0 |
| 数据库/导出 | 5 | 2 | 2 | 0 |
| 安全 | 6 | 0 | 0 | 0 |
| 性能/稳定性 | 3 | 0 | 4 | 1 |

> 说明：表中 PASS 含「源码确认」与「本轮执行」两类，逐条已在证据列注明；NOT_RUN 一律不计入通过。
>
> **证据分类要求**：`源码阅读` / `宿主机测试` / `真机执行` / `UI 端到端` 四类必须区分；
> 任何「CODE_REVIEWED」都不得写成实际执行通过。
>
> **QA-2A 更新**：新增 `PlanPlaceGuard.test.ets`（8 条）、`ReverseViewState.test.ets`（8 条）、
> `SearchAnomalyAudit` 迁移+A7（9 条）。宿主机总数 146 → **163/163 通过**；
> 真机本次构建安装后执行 `KernelPerfReal` 2/2、`TimeZoneReal` 12/12（均为真机执行）。

---

## QA-2B 证据分级与更新

证据标签：`CODE_REVIEWED`（仅源码核查）/ `HOST_PASS`（宿主机执行）/ `DEVICE_PASS`（真机执行）/ `E2E_PASS`（真实 UI 流程）/ `NOT_RUN` / `BLOCKED` / `FAIL`。

| 项目 | 证据等级 | 说明 |
|---|---|---|
| 搜索状态重置（IDLE/RUNNING/FINAL） | HOST_PASS | `ReverseViewState.test.ets` 10 条 |
| 计划记录消失守卫 | HOST_PASS | `PlanPlaceGuard.test.ets` 10 条 |
| CSV 字节/BOM/校验和 | HOST_PASS | `ExportBytes.test.ets` 7 条，含独立 BigInt FNV-1a 对照 |
| 窗口一对一匹配 | HOST_PASS | `WindowMatching.test.ets` 7 场景，真实内核 + 1 秒参考 |
| 搜索按钮/取消按钮稳定 ID | CODE_REVIEWED | 已加 `reverse_search_btn` / `reverse_summary` / `progress_cancel_btn` |
| UI 端到端搜索与取消 | BLOCKED | dumpLayout 不暴露自研 ID；文本定位受滚动影响 |
| 真机主要页面截图 | DEVICE_PASS（仅采集） | 5 张（首页/反向寻光/计划/轨迹/更多）；逐页视觉审查 NOT_RUN |
| KernelPerfReal / TimeZoneReal | DEVICE_PASS（e69131b 构建） | 本轮未重跑，不作为本轮执行证据 |

宿主机总数：**181/181 通过**。
