# 逐光 / LightBearing

> 好光线，值得提前抵达 —— 摄影太阳方位与机位规划应用

HarmonyOS 7 / **API 26 only** 原生应用，使用 **ArkTS + ArkUI** 与官方开放 Kit 实现，
全部数据保存在本机，不联网、无埋点、无第三方 SDK。

| 项目 | 值 |
|---|---|
| 中文名 / 英文名 | 逐光 / LightBearing |
| Bundle Name | `com.hhyxx.LightBearing`（与 AGC 已注册应用记录、调试签名 profile 一致；PRD 原文为全小写 `com.hhyxx.lightbearing`，因 AGC 记录与签名证书已绑定大写形式，经确认以注册名称为准） |
| 版本 | 1.0.0（versionCode 1） |
| 编译 / 目标 SDK | 26.0.0（API 26，`compileSdkVersion=26`、`compatibleSdkVersion=26`、`targetSdkVersion=26`） |
| 支持设备 | phone、tablet（不含 2in1） |
| UI | Navigation + NavDestination，手机底部 4 个一级入口 +「更多」，平板左侧导航栏 |
| 存储 | ArkData RDB（`lightbearing.db`，schema 版本化迁移） |
| 算法 | NOAA / Meeus 太阳位置级数（自研模块，含单元测试） |

## 1. 开发与验证环境（实测）

| 项 | 版本 / 值 |
|---|---|
| DevEco Studio | 26.0.0.851（build 261.23567.138.36.2600851） |
| HarmonyOS SDK | 26.0.0.105（API 26） |
| hvigor | 6.26.8（`DevEco Studio/tools/hvigor/bin/hvigorw.js`） |
| Node.js | v22.20.0（`DevEco Studio/tools/node/node.exe`） |
| 模拟器 | `127.0.0.1:5555`，emulator，OpenHarmony 7.0.0.107，API 26，1280×2832 |
| 真机（已连接） | `4EE9K25515007252`，MIA-AL00，HarmonyOS 7.0.0.105，API 26 |

## 2. 构建

工程使用 DevEco Studio 自带的 hvigor（骨架未附带 `hvigorw` 包装脚本）：

```bash
# Windows Git Bash
export DEVECO_SDK_HOME="/c/Program Files/Huawei/DevEco Studio/sdk"
export NODE_HOME="/c/Program Files/Huawei/DevEco Studio/tools/node"

"/c/Program Files/Huawei/DevEco Studio/tools/node/node.exe" \
  "/c/Program Files/Huawei/DevEco Studio/tools/hvigor/bin/hvigorw.js" \
  assembleHap --mode module -p product=default -p buildMode=debug --no-daemon
```

产物：
- 已签名（`signingConfigs` 已配置）：`entry/build/default/outputs/default/entry-default-signed.hap`（实测 1,622,711 字节）
- 未签名：`entry-default-unsigned.hap`（实测 1,561,660 字节）

也可以用 DevEco Studio 打开工程后执行 **Build → Build Hap(s)/APP(s)**。

### 2.1 签名与安装（重要）

工程已配置 DevEco Studio 自动生成的调试签名（`build-profile.json5 → signingConfigs`），
证书/Profile/密钥库位于 `C:\Users\Remote\.ohos\config\default_LightBearing_*`，
**私钥材料不在仓库内**；仓库中只保留证书路径与 IDE 加密后的口令字段。

- 构建签名 HAP：

  ```bash
  hvigorw assembleHap --mode module -p product=default -p buildMode=debug --no-daemon
  ```

- 真机安装（MIA-AL00，`4EE9K25515007252`）实测：

  ```bash
  hdc -t 4EE9K25515007252 install -r entry-default-signed.hap    # msg:install bundle successfully.
  hdc -t 4EE9K25515007252 shell aa start -a EntryAbility -b com.hhyxx.LightBearing
  ```

  **注意**：真机处于开发者模式时，系统不会自动解锁屏幕，启动会返回
  `10106102 The device screen is locked during the application launch`。
  需要先手动点亮并解锁手机屏幕，再执行启动命令。

- 模拟器接受未签名 HAP，可直接安装验证：

  ```bash
  hdc -t 127.0.0.1:5555 install -r entry-default-unsigned.hap
  hdc -t 127.0.0.1:5555 shell aa start -a EntryAbility -b com.hhyxx.LightBearing
  ```

- 若包名与签名 profile 不一致（DevEco 自动签名会写死当时的 bundleName），
  构建会报 `The bundleName in app.json5 ... does not match the bundleName in the generated SigningConfigs`，
  此时需在 Project Structure → Signing Configs 重新生成签名，或让两侧包名对齐。

## 3. 运行与功能入口

| 路由 | 页面 | 能力 |
|---|---|---|
| home | 今日光线 | 当前机位、今日时段、太阳方位/高度、光线阶段、全天高度曲线与时刻拖动 |
| sunpath | 太阳轨迹 | 任意日期日轨、日出日落/正午、方向辅助罗盘、把此刻存为计划 |
| reverse | 反向寻光 | 目标方位+高度±容差、日期范围批量搜索（5 分钟粗扫 + 30s/5s/1s 细化） |
| locations | 机位库 | 手动经纬度/时区/标签/备注、前台一次定位填入、搜索、编辑、删除、设为当前 |
| compass | 现场罗盘 | 方向传感器参考、手动校正量、实时太阳方位、传感器不可用降级 |
| map | 地图方位 | 离线方位图（真实经纬度换算相对方位）+ 手动新增机位；Map Kit 未接入 |
| planner | 拍摄计划 | 计划 CRUD、候选窗口、行前清单、备注、天气备忘（手写）、CSV 导出 |
| calendar | 日历 | 月历逐日阳光窗口、当日计划筛选、计划卡片 PNG 导出、本月 CSV 导出 |
| compare | 时间比较 | 最多 5 个日期同时段方位/高度对照与同日曲线 |
| settings | 设置 | 深浅/跟随系统主题、角度单位、时区、黄金/蓝调定义、权限状态、本地数据统计、历史与隐私说明 |

首次启动有可跳过的引导；无定位/无网络时全部计算功能可用（手动坐标）。

### 3.1 权限

仅申请两个 `user_grant` 权限，均带 `reason` 与 `usedScene`：

- `ohos.permission.APPROXIMATELY_LOCATION`
- `ohos.permission.LOCATION`

只在用户点「使用当前位置 / 用当前位置」时**前台一次定位**；不申请后台定位、相机、媒体库写入；
**不使用任何受限 ACL**。权限被拒后页面展示权限教育卡并提供手动坐标降级路径。

### 3.1.1 交互保护

- **未保存编辑**：编辑机位/计划时置 `AppState.dirtyForm`，系统返回与导航切换都会被
  `NavDestination.onBackPressed` / `go()` 拦下并提示「放弃未保存的编辑？」，不会静默丢弃输入。
- **危险动作可撤销**：删除机位或计划后，页面内出现撤销条（「已删除 X」+ 撤销 / 关闭），
  撤销会把对象重新写回 RDB。不采用「删完再弹第二个对话框」的做法——连续弹窗会被系统吞掉。
- **加载骨架屏**：加载态用 `SkeletonCard` 占位，而不是只有一个转圈。
- **列表 → 详情**：计划与机位列表点标题进入 `planDetail` / `placeDetail` 独立路由，
  详情页复核实际太阳位置、支持导出单条与删除，而不是在列表里就地展开。
- **长任务进度**：反向寻光逐日推进并写入 `jobs` 进度，界面用 `ProgressSheet` 显示
  「第 n/N 天 · 已命中 x」，可随时取消；不再整段阻塞 UI 线程。
- **导出可追溯**：每次导出记录为 `FileAsset`（URI/mime/字节数/校验和），设置页可查看与清理记录。

### 3.2 视觉系统与图标

视觉严格对齐 `lightbearing_ui.html` 的设计语言（数值取自其 CSS）：

| 设计稿 | 实现 |
|---|---|
| `:root` 色板 `#0D1A29 / #182C3D / #213B4E / #FFBC6B / #73D9D5 / #F9FAF3 / #A2B9C5` | `resources/dark/element/color.json` 一一对应；浅色为同语义浅底等价物（AA 对比度） |
| `.card` 19 / `.hero` 24 / 按钮 12 / `.chip` 40 / `.stat` 15 / `.appicon` 17 | `common/Theme.ets → Radius` |
| `.eyebrow` 12 字距 1.1 / `.pagetitle` / `.subtitle` 14 / `.card h3` 14 / `.small` 12 / `.stat b` 24 | `common/Theme.ets → FontSize` + `components/Widgets.ets` |
| `.hero` 125° 渐变 + 右上 35px 装饰环 | `HeroCard`（`linearGradient` + `Circle.strokeWidth(35)` 溢出裁切） |
| `.chip` 主色 35% 描边 + 10% 底 | `StatusBadge` |
| `.iconbox` 40×40 主色 15% 底 + 12 圆角 | `IconBox` |
| `.helpmeta` 左侧 2px 主色条 | `NoticeBar` |
| `.navbtn` 未选中 muted / 选中主色 13% 底 + 42% 描边 | 平板 `rail()` 与手机 `bottomBar()` |
| `.navcaption` 10px 大写 字距 2 | 侧栏「PAGES / 页面」 |

**图标**：不使用 emoji 或字体符号。`tools/icon-gen/make_icons.py` 直接复用设计稿 `PATHS` 里的
24×24 线性 path（stroke 1.8、round 端点），按需要的语义色生成 SVG 到
`resources/base/media/ic_*.svg` 与 `resources/dark/media/ic_*.svg`（深浅各一套，共 120 个文件）。
之所以烘色进 SVG 而不用 `Image.fillColor`：该属性对 `fill="none"` 的描边图标不生效
（见 `@ohos.arkui` image.d.ts 说明），用 `dark` 资源限定目录切换主题反而更可靠。

**主题三态**：默认「跟随系统」，深色只表示深色、浅色只表示浅色——
`Theme.apply()` 分别调用 `setColorMode(COLOR_MODE_NOT_SET / DARK / LIGHT)`，
资源通过 `resources/base` 与 `resources/dark` 限定目录切换。

真机（系统为浅色）逐态实测亮度（页面中部背景平均亮度）：跟随系统 244.3、深色 45.1、
浅色 244.3、切回跟随系统 244.3（证明强制深色后仍能恢复为跟随系统）。

**页面转场**：一级入口（今日/轨迹/计划/设置/更多）之间用
`replacePathByName(route, '', false)` / `pushPathByName(route, '', false)` **原地切换、无动画**，
不再出现「先退一屏再进一屏」的双段转场；二级页面（反向寻光、机位库、罗盘、地图、日历、比较）
保留一次正常的推入转场，返回用 `pop(true)`。

## 4. 数据模型与持久化

- 业务表：`places`（机位）、`plans`（拍摄计划，含 `project_id`）、`settings`（键值设置）、`history`（操作历史）。
- 基础模型（schema **v2**）：`projects`（项目，首个自动创建为「默认项目」）、
  `file_assets`（导出文件资产：URI/mime/字节数/校验和）、`jobs`（后台任务：状态/进度/错误码）。
- 迁移：`PRAGMA user_version` 驱动，v1→v2 建表并 `ALTER TABLE plans ADD COLUMN project_id`，
  迁移与写入均包在事务中，失败回滚。
- 坐标一律 WGS84；时区只用于展示与输入换算（`i18n.TimeZone.getOffset`，含夏令时）。
- 计划与历史的写入在同一事务内完成，保证一致性；删除项目只解除计划归属，不动计划本身。
- 导出文件校验和为 FNV-1a 32 位（`fnv1a:xxxxxxxx`），写入 `file_assets` 供事后核对。

## 5. 测试

### 5.1 单元测试（宿主机执行，实测 23/23 通过）

```bash
export DEVECO_SDK_HOME="/c/Program Files/Huawei/DevEco Studio/sdk"
"/c/Program Files/Huawei/DevEco Studio/tools/node/node.exe" \
  "/c/Program Files/Huawei/DevEco Studio/tools/hvigor/bin/hvigorw.js" \
  test --mode module -p module=entry@default -p product=default -p buildMode=debug --no-daemon
```

覆盖：`SolarCalc`（春分赤道正午≈90°、日出方位≈90°、夏至正午高度、黄金窗口顺序、
极昼极夜、环形角差、阶段阈值、赤纬极值）、`ReverseSearch`（命中结果代回公式复核、
不可达目标返回空、白昼过滤、结果上限、误差排序）、`CsvCodec`（转义与往返）。
结果明细：`entry/.test/default/intermediates/test/coverage_data/test_result.txt`
（`Tests run: 23, Failure: 0, Error: 0, Pass: 23`），覆盖率报告：`entry/.test/default/outputs/test/reports/index.html`（行覆盖 74.93%）。

> 环境注意：本机 `@ohos/hypium@1.0.25` 的 ohpm 包内缺少 `src_static/testAbility` 模板，
> 首次 `test` 会报 `TestAbility.ets does not exist`。已从 SDK 自带的 hypium 副本补齐该目录
> （仅本机 `oh_modules` 内操作，未提交）。`oh_modules` 已 gitignore。

### 5.2 端到端测试（模拟器执行，实测 4/4 通过）

```bash
# 1) 构建测试包
hvigorw assembleHap --mode module -p module=entry@ohosTest -p product=default -p buildMode=debug
# 2) 同时安装主包与测试包
hdc -t 127.0.0.1:5555 install -r entry-default-unsigned.hap entry-ohosTest-unsigned.hap
# 3) 执行
hdc -t 127.0.0.1:5555 shell "aa test -b com.hhyxx.lightbearing -m entry_test -s unittest OpenHarmonyTestRunner -s timeout 60000"
```

结果：`Tests run: 4, Failure: 0, Error: 0, Pass: 4`。UI 用例通过 `AbilityDelegator` 拉起
`EntryAbility` 后，用 `@kit.TestKit` 的 Driver 断言首页标题、底部导航切换到太阳轨迹、进入「更多工具」。

### 5.2.1 稳定性（真机 30 轮页面往返）

用系统输入注入在真机（MIA-AL00）上循环「一级 ↔ 二级」页面 30 轮，每轮检查进程：

| 指标 | 结果 |
|---|---|
| 进程存活 | **30/30**，PID 始终为同一值（无重启） |
| `jscrash` / `JSERROR` / `CPP_CRASH` | **0 命中** |
| 日志脚本 | 见提交说明中的临时脚本逻辑（`uitest uiInput click` + `pidof` + `hilog` 扫描） |

### 5.3 算法外部交叉验证

```bash
node tools/solar-check/check.mjs
```

与独立实现 `api.sunrise-sunset.org`（官方声明 ±30 秒）就 12 组用例（上海夏/冬/春分、悉尼、
特罗姆瑟极昼/极夜、纽约夏令时结束与均时差极值、加德满都非整点时区、乌斯怀亚、
跨日期线 ±179°＋萨摩亚）比对日出、
日落、太阳正午、三层曙暮光：**最大误差 27.4 秒，容差 120 秒，失败 0**；物理不变量
（春分赤道正午高度 89.96°、日出方位 90.14°、日落方位 270.06°、均时差极值 16.49/−14.23 分钟、
夏至赤纬 23.438°、极昼极夜判定）全部通过。

## 6. 导出验证

- CSV / PNG 均通过系统 `DocumentViewPicker` 由用户选择保存位置后写入真实字节，
  返回的 URI 由系统签发，可用文件管理器独立打开核对；不使用 toast 替代写文件。
- 计划页导出字段：`计划ID,机位,纬度,经度,时区,本地时间,UTC时间,目标方位,目标高度,方位容差,高度容差,状态,备注,天气备忘`。
- 日历页导出的 PNG 来自可见「分享卡片」组件的 `componentSnapshot` 快照，再用
  `image.createImagePacker().packToData(pixelMap, {format:'image/png'})` 编码。

## 7. 已知限制（如实说明）

1. **真机首次启动需手动解锁**：真机处于开发者模式时系统不允许自动解锁，
   `aa start` 会返回 `10106102 The device screen is locked`；解锁后启动正常，安装与运行均已实测通过。
2. **权限撤销未实测**：系统 `acm` 在 shell 下不可执行，权限弹窗是独立系统窗口、UI 自动化抓不到，
   因此「运行时撤销定位权限」的路径只有代码分支，没有实机证据。
3. **平板布局未实测**：≥600vp 的双栏与侧栏逻辑已实现，但手头只有手机设备。
4. **「减少动态效果」是应用内开关**：API 26 未提供读取系统该设置的公开接口。
5. **Map Kit 未接入**：`@hms.core.map` 需要 AGC 开通地图服务并配置 Client ID/签名指纹。
   按任务书要求实现了真实可用的降级路径（离线方位图 + 手动坐标），未显示在线底图。
6. **无系统分享面板**：本 SDK 未提供 ShareKit（`@kit.ShareKit` 不存在），
   分享改为「导出文件到用户选择的位置」，可被外部工具验证。
7. **坐标转换**：内部一律 WGS84；未实现未经核实的 GCJ-02 偏移，界面中已明确提示。
8. **阳光窗口依赖可配置阈值**：黄金/蓝调为高度角区间（默认 +6/−4、−4/−6），
   在设置页可改；不同摄影流派定义不同，故不做硬编码定论。
9. **天气**：只有用户手写的「天气备忘」，不接入任何天气服务，界面已标注不是预报。

## 8. 目录结构

```text
AppScope/                             应用级配置与 layered 图标资源
entry/src/main/ets/
  entryability/EntryAbility.ets       入口（初始化 RDB、加载首页）
  common/AppState.ets                 跨页面共享状态（真实数据，不含演示数组）
  common/Theme.ets                    设计 token、主题应用、Canvas 取色
  common/InputDevices.ets             物理键盘探测（决定是否显示快捷键提示）
  model/Models.ets                    业务模型（机位/计划/设置/历史）
  model/BaseModels.ets                基础模型（项目/文件资产/后台任务）
  repository/AppDb.ets                RDB 仓储：迁移(v2)、事务、CRUD
  services/SolarCalc.ets              太阳位置、日出日落、曙暮光、黄金/蓝调
  services/TimeUtil.ets               i18n 时区换算（含夏令时）
  services/ReverseSearch.ets          反向寻光（粗扫 + 逐级细化）
  services/LocationService.ets        前台一次定位 + 权限降级
  services/SensorService.ets          方向传感器订阅与能力检测
  services/ExportService.ets          CSV/PNG 真实写文件 + 校验和 + 资产登记
  components/Widgets.ets              顶栏/hero/卡片/空态/错误卡/权限门/骨架屏/
                                      磁贴/工具按钮/分段选择器/进度浮层/快捷键提示/对话框
  components/Charts.ets               Canvas 日轨、罗盘、方位图、对照曲线
  pages/*.ets                         10 个业务页面 + 计划/机位详情 + Index（Navigation 外壳）
entry/src/test/                       宿主机单元测试
entry/src/ohosTest/                   端到端 / UI 自动化测试
tools/solar-check/                    算法外部交叉验证（Node）
tools/icon-gen/make_icons.py          线性图标生成（复用设计稿 path，输深浅两套 SVG）
tools/icon-gen/make_icon.py           应用图标生成（PIL，输出 SVG + PNG）
docs/icon/                            1024×1024 图标与 SVG 矢量源
docs/screenshots/                     模拟器实拍截图
```

## 9. 文档

- [`API_AUDIT.md`](API_AUDIT.md) —— 逐项 API 名称、官方文档、能力/权限、验证结论
- [`ACCEPTANCE.md`](ACCEPTANCE.md) —— 逐条功能验收结果与失败/未完成证据
- `lightbearing_dev_prd.md` —— 开发任务书（需求依据）
- `lightbearing_ui.html` —— UI 设计稿（视觉参考）
