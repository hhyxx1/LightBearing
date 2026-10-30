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

## 6. 设计走查（视觉与图标改版）

初版实现与 `lightbearing_ui.html` 存在两处明确偏差，已修复：

| 问题 | 初版 | 现版 |
|---|---|---|
| 图标 | 使用 emoji/字体符号（☀ ⚙ ▣ ◠ ⋯ ⚠ 等），系统渲染为彩色 emoji，与设计稿的线性图标语言不符 | `tools/icon-gen/make_icons.py` 复用设计稿 `PATHS` 的 24×24 描边 path，生成 60 个图标 × 深浅两套（共 120 个 SVG）；全部 emoji 已清零（`grep` 校验 0 命中） |
| 配色与版式 | 浅底 + 棕色调，圆角/间距未对齐设计稿 | 深底 `#0D1A29` + 琥珀 `#FFBC6B` + 青 `#73D9D5` 为默认主题；`.card` 19 / `.hero` 24 / `.chip` 40 / `.stat` 15 / `.iconbox` 40×40 / 按钮 12；eyebrow 12 字距 1.1；卡片 1px `rgba(226,246,255,.12)` 线框；hero 125° 渐变 + 右上 35px 装饰环；`.navcaption` 与 `.helpmeta` 同样还原 |

改版过程中修掉的自身缺陷：
- 数值卡数值被截断为 `26…`（真机 1224px 宽下三列过窄）→ `.maxFontSize/.minFontSize + MAX_LINES_FIRST`，阶段改用短标签（白昼/黄金/蓝调/民用/航海/天文/夜间）。
- hero 装饰环压到正文 → `translate({x:128, y:-150})` 推到右上角外并裁切。
- 页头 eyebrow 换行 → 收短为 `LIGHTBEARING · API 26` 并单行省略。
- 底部导航「更多」三点过细发黑 → 该图标单独用 stroke-width 3.4。
- 已完成引导会连带把默认 `themeMode` 落库，导致新默认深色不生效 → 引导只写 `onboarded` 单键。

真机（MIA-AL00，API 26）实拍证据：`docs/screenshots/20_redesign_home.jpeg`、
`21_redesign_sunpath.jpeg`、`22_redesign_settings.jpeg`、`23_redesign_more.jpeg`。

仍与设计稿有意的差异（保留并说明）：
1. 手机底部导航比设计稿 `.mobiletabs` 多显示图标（设计稿移动端 `svg{display:none}`）——实测图标更易辨识，属于可读性取舍。
2. hero 装饰环用 `Circle.strokeWidth(35)` 近似 `.hero:after` 的 35px 边框环，颜色取主色 14%，未做逐像素还原。
3. 浅色主题是设计稿之外的补充（PRD 要求），数值为同语义浅底等价物，未遵循设计稿（设计稿仅深色）。

## 7. 主题三态与页面转场（复审修正）

### 7.1 主题三态

初版把默认主题强行设为深色，导致「跟随系统」在浅色系统下仍显示深色，语义被破坏。已修正：

- 默认值回到 `themeMode = 0`（跟随系统）；`深色` 只表示深色，`浅色` 只表示浅色。
- `Theme.apply()` 分别映射到 `COLOR_MODE_NOT_SET / DARK / LIGHT`，资源经 `resources/base` 与 `resources/dark` 切换。
- 引导完成只写 `onboarded` 单键（此前会把内存里的默认 `themeMode` 一并落库，导致默认值改动对老安装无效）。

真机（MIA-AL00，系统为浅色）逐态实测，用页面中部背景平均亮度客观判定：

| 操作 | 截图 | 平均亮度 | 结论 |
|---|---|---|---|
| 跟随系统 | `24_theme_follow.jpeg` | 244.3 | 浅色 ✅ |
| 深色 | `25_theme_dark.jpeg` | 45.1 | 深色 ✅ |
| 浅色 | `26_theme_light.jpeg` | 244.3 | 浅色 ✅ |
| 切回跟随系统 | `27_theme_follow_again.jpeg` | 244.3 | 能恢复跟随系统 ✅ |

### 7.2 页面转场

初版一级导航切换用 `clear()` + `pushPathByName()`，会先播「退回内容区」再播「推入」，表现为双段动画/抖动。已修正：

- 一级入口（今日/轨迹/计划/设置/更多）：`replacePathByName(route, '', false)`（在内容区时用 `pushPathByName(route, '', false)`），**原地切换、无动画**。
- 二级页面（反向寻光/机位库/罗盘/地图/日历/比较）：`clear(false)` 后 `pushPathByName(route, '', true)`，只播一次正常推入转场。
- 返回：`pop(true)`；回到首页：`clear(false)`。

说明：转场是逐帧动画，截图无法作为证据，此处记录的是实现依据（`NavPathStack` 的 `animated` 参数）与实机点按观察结论。

## 8. 任务书复审（第二轮遗漏项对照）

逐条重读 `lightbearing_dev_prd.md` 与 `lightbearing_ui.html` 后发现的遗漏，以及本轮处理情况：

### 8.1 本轮已补齐

| PRD 条目 | 原状态 | 本轮处理 | 验证 |
|---|---|---|---|
| §2「必有骨架屏」 | 只有转圈 LoadingProgress | 新增 `SkeletonCard`/`SkeletonBar`，首页与 8 个页面的加载态改为骨架屏 | 编译通过；骨架屏为瞬时状态，未截到图，代码路径可查 |
| §3「数值使用等宽数字」 | 数值用默认比例数字 | `MetricTile` 数值加 `fontFeature('"tnum" 1')` | 编译通过，真机截图字形为等宽 |
| §2「返回前保存未提交表单或明确提示」 | 系统返回会静默丢弃 | `AppState.dirtyForm` + `NavDestination.onBackPressed` + `go()` 前拦截，弹「放弃未保存的编辑？机位编辑还没有保存…」 | **真机验证通过**（dumpLayout 抓到该对话框文案） |
| §11「可撤销的危险动作」 | 只有确认弹窗 | 机位/计划删除后页面内出现撤销条（「已删除 X」+ 撤销 + 关闭），撤销即重新入库 | 实现并编译通过；**真机复核未完成**（测试用机位在排障过程中已被删除，重建需要输入法或定位权限往返，本轮未走完） |
| §9「跨日期线」验收 | 未覆盖 | 校验集新增 3 组（+179.4°、−179.97° 显式 UTC+12、萨摩亚 −171.76°） | 12 组用例最大误差 27.4s、失败 0；不变量 9/9 |

顺带修掉的实现缺陷：`tools/solar-check/check.mjs` 仍是旧的「UTC 零点锚定」，与 app 已改的「按本地日锚定 + 夹回本地日」不一致，导致日期线用例整组偏一天（86407s）。脚本已同步为新逻辑，并支持用例显式给时区——日期线附近「日期 + 经度」本身不唯一，必须给时区才有唯一解（app 里等价于机位的 `tzId`）。

### 8.2 仍未落实（如实列出）

| PRD 条目 | 现状 | 影响/原因 |
|---|---|---|
| §3 可复用组件清单 | 缺 `ProjectTile`、`ToolButton`、`SegmentedPicker`、`ProgressSheet`、`KeyboardShortcutHint` | 功能被页面内一次性写法覆盖（如设置页角度切换、删除确认），未抽成命名组件；`KeyboardShortcutHint` 对纯触屏应用本就不适用 |
| §7 基本模型 | 缺 `AppProject`、`FileAsset`、`Job` | 当前业务（机位/计划）没有「项目/文件资产」概念；`Job` 任务队列未实现，反向搜索在 UI 线程同步执行，超长区间（如 365 天）会卡住界面 |
| §11 每页「列表选择与详情跳转」 | 无独立详情路由，编辑走页内表单 | 信息架构上是「列表 + 就地编辑」，没有 detail 页 |
| §0「平板图表双栏」 | 平板只有左侧导航，内容仍是单列 | 未做双栏布局 |
| §3「横竖屏与安全区」 | 未做旋屏适配与安全区显式处理 | 未测试 |
| §3「屏幕阅读器 label」 | 仅导航项、滑块、图表等少数控件有 `accessibilityText` | 覆盖不全 |
| §3「减少动态效果」 | 未显式响应系统设置 | 当前几乎没有动画，影响有限 |
| §9/§12 长时稳定性、权限撤销、存储不足 | 未执行 | 仅做了多次冷启动与前后台切换 |
| §10「多尺寸图标资源」 | 只有 1024 分层图标 + 启动图标 | 未输出多档位图 |
| §3「正文 14–16vp」 | 正文 13vp（`.small` 12） | 跟随设计稿字号，与 PRD 该数值冲突，按设计稿执行 |

上述「仍未落实」项不需要猜测即可复现，均已在代码中确认为缺失，而不是标注已完成。



