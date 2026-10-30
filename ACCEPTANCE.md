# 验收报告（Acceptance）

**验收环境**：模拟器 `127.0.0.1:5555`（emulator，OpenHarmony 7.0.0.107，API 26，1280×2832）
**构建**：`assembleHap` BUILD SUCCESSFUL，签名 HAP 1,622,711 字节（未签名 1,561,660 字节）
**测试**：单元测试 `Tests run: 23, Failure: 0`；端到端 `Tests run: 4, Failure: 0`（模拟器）
**截图**：`docs/screenshots/`（模拟器与真机实拍，非设计稿）
**真机**：`4EE9K25515007252`（MIA-AL00，API 26）签名 HAP 安装成功、启动成功，实机录入机位并跑通计算与页面切换；
hypium UI 套件在真机被系统后台启动限制拦截（`16000001`），已在模拟器跑通 4/4（见 §3、§4）

> 本文件只记录**实际执行过**的验证。未执行或未通过的项目明确标注，不用全勾选代替验证。

## 1. 功能清单（F01–F12）

| 编号 | 要求 | 实现位置 | 验收结果 | 证据 |
|---|---|---|---|---|
| F01 | 手动经纬度+时区地点选择、可选前台定位、收藏与编辑 | `pages/LocationsPage.ets`、`services/LocationService.ets` | ✅ 通过（手动/时区/标签/备注/搜索/编辑/删除/设为当前全部可用；定位走前台一次定位，失败时有降级文案） | `docs/screenshots/03_locations.jpeg`、`04_locations_saved.jpeg`；重启后 hilog `bootstrap ok places=1` 证明持久化 |
| F02 | 标准太阳位置算法、日出日落、民用/航海/天文曙暮光 | `services/SolarCalc.ets` | ✅ 通过 | 与 `api.sunrise-sunset.org` 10 组用例最大误差 **27.4s**（容差 120s）；单测 12 项；`tools/solar-check/check.mjs` |
| F03 | 黄金/蓝调可配置定义并展示算法与折射假设 | `SolarCalc.lightWindows`、`pages/SettingsPage.ets` | ✅ 通过（阈值可在设置页改并落库；页面文案说明 −0.833° 折射假设） | `docs/screenshots/09_settings.jpeg`、`13_calendar.jpeg`；单测 `shanghai_golden_window_ordering` |
| F04 | 任意日期日轨、全天时间滑块、方向辅助 | `pages/SunPathPage.ets`、`components/Charts.ets` | ✅ 通过 | `docs/screenshots/07_sunpath.jpeg` |
| F05 | 反向搜索方位/高度容差、跨日期批量 | `services/ReverseSearch.ets`、`pages/ReversePage.ets` | ✅ 通过（5 分钟粗扫 + 30s/5s/1s 细化） | 单测 `finds_window_matching_target_and_revalidates`（结果代回公式复核）；`docs/screenshots/10_reverse.jpeg` |
| F06 | 候选按误差/时段/日出日落过滤排序 | 同上 | ✅ 通过（白昼过滤开关 + 按总误差升序） | 单测 `daylight_filter_removes_night_results`、`results_sorted_by_total_error`、`respects_max_results` |
| F07 | 保存计划与机位说明、天气备忘（不冒充预报） | `pages/PlannerPage.ets`、`repository/AppDb.ets` | ✅ 通过（含行前清单；写入与历史同事务） | `docs/screenshots/08_planner.jpeg`；`savePlan` 事务实现 |
| F08 | 可选 Map Kit + 方向射线；无地图服务时手动坐标与简易方位图 | `pages/MapPage.ets`、`components/Charts.BearingDiagram` | ✅ 通过（**降级路径**）：离线方位图按真实经纬度换算相对方位，可手动新增机位 | `docs/screenshots/12_map.jpeg`；Map Kit 未接入原因见 §2 |
| F09 | 传感器仅作参考，标注磁偏角/金属干扰 | `pages/CompassPage.ets`、`services/SensorService.ets` | ✅ 通过（含手动校正 ±15°、偏差读数、不可用时的能力卡） | `docs/screenshots/11_compass.jpeg`；页面明确提示磁偏角与干扰 |
| F10 | 导出可分享 PNG 计划卡与 CSV | `services/ExportService.ets`、`pages/CalendarPage.ets`、`pages/PlannerPage.ets` | ⚠️ 部分验证：写文件链路编译并运行到系统保存面板；返回的 URI/字节数来自系统回调。**未能在模拟器上完成一次「选目录→落盘→外部打开」的完整点击流程**（自动化无法点击系统文件面板） | 代码路径 + `Result` 结构如实回显；见 §3「未完成的验证」 |
| F11 | 多地点时间对照、日期收藏、历史与离线计算 | `pages/ComparePage.ets`、`AppDb.history` | ✅ 通过（最多 5 日期对照、曲线与时刻表、历史写入 RDB；全部离线） | `docs/screenshots/14_compare.jpeg`；单测 `utc_equinox...` 等全离线运行 |
| F12 | 深浅主题、国际日期/时区、极昼极夜异常处理 | `common/Theme.ets`、`services/TimeUtil.ets`、`SolarCalc.events` | ✅ 通过（主题三态切换生效；时区经 i18n 取偏移含夏令时；极昼/极夜返回 `polarState` 并在页面提示） | `docs/screenshots/02_onboarding.jpeg`（浅色）与首轮深色截图；单测 `polar_night_tromso_winter`、`polar_day_tromso_summer` |

## 2. 页面级验收（S01–S10）

| 路由 | 首屏无闪退 | 按钮/输入有实际结果 | 空态/错误/权限态 | 截图 |
|---|---|---|---|---|
| /home 今日光线 | ✅ | ✅（时刻滑块改变方位/高度与阶段；CTA 跳转） | ✅ 无机位→空态引导；定位失败→文案 + 权限门 | `06_home_data.jpeg` |
| /sunpath 太阳轨迹 | ✅ | ✅（前/后一天、今天、日期选择、滑块、存计划） | ✅ 无机位→空态 | `07_sunpath.jpeg` |
| /reverse 反向寻光 | ✅ | ✅（参数输入 + 搜索 + 加入计划） | ✅ 无命中→说明文案 | `10_reverse.jpeg` |
| /locations 机位库 | ✅ | ✅（新增/编辑/删除/搜索/设当前/用当前位置） | ✅ 空库→空态；非法坐标→校验提示 | `03`、`04` |
| /compass 现场罗盘 | ✅ | ✅（订阅/暂停、校正 ±15°） | ✅ 传感器不可用→能力卡 + 引导 | `11_compass.jpeg` |
| /map 地图方位 | ✅ | ✅（目标方位/半径、新增机位、设为中心） | ✅ 无中心机位→空态；明确写出 Map Kit 未接入原因 | `12_map.jpeg` |
| /planner 拍摄计划 | ✅ | ✅（新建/编辑/删除/清单增删勾选/导出） | ✅ 无计划→空态 | `08_planner.jpeg` |
| /calendar 日历 | ✅ | ✅（翻月、选日、导出 PNG/CSV） | ✅ 无数据日显示「当日没有计划」 | `13_calendar.jpeg` |
| /compare 时间比较 | ✅ | ✅（加/移日期、曲线与时刻表、记录历史） | ✅ 无日期时提示上限与重复 | `14_compare.jpeg` |
| /settings 设置 | ✅ | ✅（主题、角度单位、时区、阈值、权限申请、历史查看/清空） | ✅ 权限状态真实展示 | `09_settings.jpeg` |

通用状态：加载中（LoadingProgress + 文案）、空态（EmptyState 带 CTA）、错误（ErrorCard 带重试/返回）、
权限（PermissionGate 带降级入口）均已实现并被实际触发过；**未发现无响应按钮**。

## 3. 未完成的验证 / 已知问题（如实记录）

1. **真机 hypium UI 套件未能跑通（应用本身实测正常）**：签名 HAP 在 MIA-AL00 上安装、启动、
   页面切换与数据录入均实测正常（见 §4 真机证据）。但 `aa test` 启动测试进程后应用被切到后台，
   测试内 `abilityDelegator.startAbility` 被系统拒绝：
   `startAbility failed: {"code":16000001}`
   （已尝试显式补 `moduleName: 'entry'`，仍被拒；同代码在模拟器上 4/4 通过）。
   真机侧改用系统输入注入（`uitest uiInput`）驱动完成等价验证：
   跳过引导 → 进入机位库 → 新增机位 `BundReal` (31.2372, 121.4900, Asia/Shanghai) → 保存并标记当前 →
   首页显示真实计算结果 → 切换到太阳轨迹/设置页。
2. **真机首次启动受锁屏限制**：开发者模式下系统不会自动解锁，`aa start` 返回
   `10106102 The device screen is locked during the application launch`；
   手动解锁屏幕后启动正常（本条已解决，仅作为复现说明保留）。
3. **导出的一次完整人机流程未走完**：自动化无法点击系统文件保存面板，因此
   「选目录→写入→用外部工具打开校验」的最后一跳由人工完成；代码侧已确保
   返回的是系统签发的 URI 与真实字节数，且失败/取消会如实回显，不会假报成功。
4. **Map Kit 未接入**：无 AGC 凭据；已实现离线方位图降级（真实坐标计算）。
5. **系统分享面板不存在**：SDK 无 `@kit.ShareKit`，改为导出文件。
6. **平板上未做实测**：平板自适应逻辑（宽度 ≥600vp 显示左侧导航栏）已实现，
   但当前仅有 phone 尺寸模拟器与手机真机，**平板布局未经真机/平板模拟器验证**。
7. **长时稳定性测试未做满时长**：仅做了多次冷启动、前后台切换与页面往返；
   未执行 24h 级别压测。已有的数据恢复路径（RDB 事务 + schema 迁移 + 错误卡重试）已实现。
8. **`hvigorw test` 的环境依赖**：本机 `@ohos/hypium@1.0.25` 缺 `src_static/testAbility` 模板，
   需从 SDK 副本补齐后才能跑单测（未提交，属本机环境修补）。README §5.1 已写明。

## 4. 构建与测试原始结果

```
# 构建
> hvigor BUILD SUCCESSFUL
entry/build/default/outputs/default/entry-default-signed.hap     1,622,711 bytes
entry/build/default/outputs/default/entry-default-unsigned.hap   1,561,660 bytes
entry/build/default/outputs/ohosTest/entry-ohosTest-signed.hap   1,573,657 bytes

# 单元测试（宿主机）
Tests run: 23, Failure: 0, Error: 0, Pass: 23, Ignore: 0
覆盖率：行 74.93%（269/359）、函数 58.97%、分支 64.84%
明细：entry/.test/default/intermediates/test/coverage_data/test_result.txt

# 端到端（模拟器：127.0.0.1:5555）
OHOS_REPORT_RESULT: stream=Tests run: 4, Failure: 0, Error: 0, Pass: 4, Ignore: 0

# 算法外部交叉验证
最大误差 27.4s，容差 120s，失败项 0；物理不变量 9/9 通过

# 真机安装（成功，已签名 HAP）
[Info]App install path:...entry-default-signed.hap msg:install bundle successfully.
[Info]App install path:...entry-ohosTest-signed.hap msg:install bundle successfully.

# 真机启动（成功，手动解锁屏幕后）
start ability successfully.
pidof com.hhyxx.LightBearing -> 49092

# 真机 end-to-end（hypium）——失败，原因非应用缺陷
OHOS_REPORT_RESULT: stream=Tests run: 4, Failure: 3, Error: 0, Pass: 1, Ignore: 0
LB_UITEST: startAbility failed: {"code":16000001}
LB_UITEST: home assertions failed: {"code":17000003}

# 真机等价验证（系统输入注入，成功）
跳过引导 -> 机位库 -> 新增机位 BundReal(31.2372,121.4900,Asia/Shanghai) -> 保存并标记当前
首页实测：太阳方位 259.5°（正西）、高度 -9.5°、航海曙暮光、日出 06:08 / 日落 17:07
截图：15_real_device_home / 17_real_device_locations / 18_real_device_sunpath / 19_real_device_settings

# 真机早期启动阻碍（已解决，保留作复现说明）
error: failed to start ability.
Error Code:10106102  The device screen is locked during the application launch, unlock screen failed.

# 真机安装（更早：未签名时失败，已消除）
[Info]App install path:...entry-default-unsigned.hap msg:error: failed to install bundle.
code:9568320 error: no signature file.
```

## 5. 关闭 GPS / 断网场景

应用未声明 `INTERNET` 权限，全部计算与存储在本地完成；「关闭定位」时：
机位库与首页的定位入口返回失败原因并引导手动输入，太阳计算、日轨、反向搜索、
计划、日历、比较、导出（本地文件）全部照常工作。该路径通过「不授权定位 + 手动坐标」
组合实测覆盖。
