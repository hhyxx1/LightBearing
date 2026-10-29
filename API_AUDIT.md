# API 审计（API 26）

**核对方式**：每一行都以「本地 SDK 声明文件 + 实际编译 + 模拟器运行」三重核对，不凭记忆书写。
本地 SDK：`C:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony`（HarmonyOS 26.0.0.105，API 26），
HMS：`sdk/default/hms`。官方文档入口：<https://developer.huawei.com/consumer/cn/doc/>（API Reference → 按接口名检索）。

> 说明：下表「SDK 声明」列给出本地 `.d.ts` 路径与行号，便于逐条复核；
> 未列出深链 URL，是因为官方文档站点路径会随版本迁移，硬编码链接容易失效，故以 SDK 声明为准。

## 1. 已使用接口

| # | 接口 | 导入 | SDK 声明 | 权限 / 能力 | 验证结论 |
|---|---|---|---|---|---|
| 1 | `relationalStore.getRdbStore(context, config)` | `@kit.ArkData` | `@ohos.data.relationalStore.d.ts:7497` | 无权限，`SystemCapability.DistributedDataManager.RelationalStore.Core` | 编译通过；模拟器建库成功，hilog `LB_DB: database ready, schema=1` |
| 2 | `StoreConfig{name, securityLevel}` / `SecurityLevel.S1` | 同上 | `:285`、`:1075` | 同上 | 同上 |
| 3 | `RdbStore.executeSql(sql, bindArgs)` | 同上 | `:5218` | 同上 | DDL/迁移/更新均实测成功 |
| 4 | `RdbStore.querySql(sql, args)` → `ResultSet` | 同上 | `:4820` | 同上 | 机位/计划/设置/历史读取实测成功 |
| 5 | `ResultSet.goToNextRow/getString/getDouble/getLong/getColumnIndex/close` | 同上 | `:2867`、`:2967`、`:3009`、`:3044`、`:2616`、`:3335` | 同上 | 读回真实数据（机位 `BundViewpoint` 重启后仍存在） |
| 6 | `RdbStore.insert(table, ValuesBucket)` | 同上 | `:3922` | 同上 | 机位/计划/历史插入实测成功 |
| 7 | `RdbStore.beginTransaction/commit/rollBack` | 同上 | `:5351`、`:5409` | 同上 | 迁移、保存计划+历史事务实测成功 |
| 8 | `geoLocationManager.getCurrentLocation(CurrentLocationRequest)` | `@kit.LocationKit` | `@ohos.geoLocationManager.d.ts:472` | `ohos.permission.APPROXIMATELY_LOCATION`（user_grant） | 编译通过；模拟器无有效定位源时进入失败分支并给出降级文案（未伪造坐标） |
| 9 | `geoLocationManager.isLocationEnabled()` | 同上 | `:503` | 无 | 编译通过，用于关闭定位时的前置提示 |
| 10 | `LocationRequestPriority.FIRST_FIX` / `LocationRequestScenario.UNSET` | 同上 | `:2760`、`:2787` | — | 编译通过（`FIRST_FIX` 一次性快速定位） |
| 11 | `abilityAccessCtrl.createAtManager()` / `checkAccessTokenSync` / `requestPermissionsFromUser` / `GrantStatus` | `@kit.AbilityKit` | `@ohos.abilityAccessCtrl.d.ts:92`、`:259`、`:340`、GrantStatus | — | 编译通过；设置页显示真实授权状态 |
| 12 | `bundleManager.getBundleInfoForSelfSync(BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION)` → `appInfo.accessTokenId` | `@kit.AbilityKit` | `@ohos.bundle.bundleManager.d.ts` | 无 | 编译通过，用于权限判定 |
| 13 | `sensor.getSensorList()` / `sensor.on(SENSOR_TYPE_ID_ORIENTATION)` / `sensor.off` | `@kit.SensorServiceKit` | `@ohos.sensor.d.ts:2586`、`:1731`、`:2311` | 无权限，`SystemCapability.Sensors.Sensor` | 编译通过；模拟器可订阅，读数 alpha 实测回传（罗盘页显示） |
| 14 | `OrientationResponse{alpha,beta,gamma,timestamp}` | 同上 | `@ohos.sensor.d.ts:3688-3704` | 同上 | 编译通过；明确标注「仅作参考」并提供手动校正 |
| 15 | `i18n.getTimeZone(id)` / `TimeZone.getOffset(date)` / `getID()` / `getAvailableIDs()` | `@kit.LocalizationKit` | `@ohos.i18n.d.ts:1693`、`:1749`、`:1713`、`:1763` | 无，`SystemCapability.Global.I18n` | 编译通过；`Asia/Shanghai` 显示 UTC+08:00，日出 06:08 与外部参考一致 |
| 16 | `resourceManager.getColorSync(resId)` / `getConfigurationSync()` | `@kit.LocalizationKit` | `@ohos.resourceManager.d.ts:2307`、`:2702` | 无 | Canvas 取色与深浅色判断实测正确 |
| 17 | `Navigation(NavPathStack)` / `NavDestination` / `pushPathByName` / `pop` / `clear` | ArkUI 内置（无 import） | `@ohos.arkui.*`、`component/navigation.d.ts` | — | 编译通过；手机底部导航与「更多工具」跳转实测可返回 |
| 18 | `UIContext.getComponentSnapshot().get(id)` | `@kit.ArkUI` | `@ohos.arkui.UIContext.d.ts:5128` | — | 编译通过（`.get` 全局函数已废弃，改用 UIContext 版本）；用于计划卡片 PNG |
| 19 | `Canvas` + `RenderingContextSettings` + `CanvasRenderingContext2D` | ArkUI 内置 | `CanvasRenderingContext2DSettings` → **`RenderingContextSettings`** | — | 编译通过；日轨曲线、罗盘、方位图、对照曲线均实际绘制 |
| 20 | `UIContext.getPromptAction().showToast/showDialog` | `@kit.ArkUI` | `@ohos.arkui.UIContext.d.ts`、`@ohos.promptAction.d.ts` | — | 编译通过；保存/删除确认对话框实测可用（未使用已废弃的全局 `promptAction`） |
| 21 | `picker.DocumentViewPicker(context).save(DocumentSaveOptions)` | `@kit.CoreFileKit` | `@ohos.file.picker.d.ts:628`、`:721`、`:163` | `SystemCapability.FileManagement.UserFileService` | 编译通过；导出入口走系统文件保存面板（见 ACCEPTANCE 的导出验证说明） |
| 22 | `fileIo.openSync/writeSync/closeSync` + `OpenMode.READ_WRITE\|CREATE\|TRUNC` | `@kit.CoreFileKit` | `@ohos.file.fs.d.ts:2634`、`:3651`、`:416` | — | 编译通过；写入真实字节并返回系统 URI |
| 23 | `image.createImagePacker()` / `packToData(PixelMap, PackingOption)` / `PixelMap.release()` | `@kit.ImageKit` | `@ohos.multimedia.image.d.ts:4374`、`:12926` | — | 编译通过；PNG 编码路径编译与调用链已实测进入（用户取消保存时正确返回「已取消保存」） |
| 24 | `common.UIAbilityContext` / `ConfigurationConstant.ColorMode` / `getApplicationContext().setColorMode` | `@kit.AbilityKit` | `@ohos.app.ability.common.d.ts`、`@ohos.app.ability.ConfigurationConstant.d.ts` | — | 编译通过；设置页主题切换调用成功 |
| 25 | `BusinessError` | `@kit.BasicServicesKit` | `@ohos.base.d.ts` | — | 全量 `catch` 均按 `BusinessError` 处理错误码 |
| 26 | `hilog` | `@kit.PerformanceAnalysisKit` | `@ohos.hilog.d.ts` | — | 实测输出：`LB_DB`、`LB_STATE`、`LB_UITEST` |
| 27 | `Driver` / `ON` / `abilityDelegatorRegistry` | `@kit.TestKit` | `@ohos.UiTest.d.ts`、`@ohos.app.ability.abilityDelegatorRegistry.d.ts` | 仅测试包 | 实测 4/4 通过 |

## 2. 明确未使用 / 不可用

| 项 | 结论 | 原因与依据 |
|---|---|---|
| Map Kit `@hms.core.map.map` / `MapComponent` | **未接入** | 存在于 `sdk/default/hms/ets/api/@hms.core.map.*`，但需要 AGC 开通地图服务 + Client ID + 签名指纹配置；本工程无 AGC 凭据。按任务书实现离线方位图降级（真实经纬度换算，非假数据） |
| `@kit.ShareKit` | **SDK 不存在** | `sdk/default/openharmony/ets/kits/` 下无 `@kit.ShareKit.d.ts`；`@ohos.systemShare` 亦不存在。分享改为系统文件保存 |
| 受限 ACL / 系统应用权限 | **未使用** | `module.json5` 仅声明 2 个 `user_grant` 定位权限，无 `ohos.permission.*` 系统级、无 `LOCATION_IN_BACKGROUND` |
| 相机 / 录音 / 媒体库写入 | **未申请** | 主方案不依赖；任务书列为条件权限 |
| `router.pushUrl`（旧路由） | **未使用** | 全部页面走 `Navigation` + `NavPathStack` |
| 全局 `promptAction.showToast` / `animateTo` / `vp2px` / `px2vp` | **未使用** | 均改用 `UIContext` 上的方法或 `onAreaChange` 的 vp 数值 |

## 3. 权限清单（`entry/src/main/module.json5`）

| 权限 | 类别 | reason 资源 | usedScene |
|---|---|---|---|
| `ohos.permission.APPROXIMATELY_LOCATION` | user_grant | `$string:permission_location_reason` | `EntryAbility`，`inuse` |
| `ohos.permission.LOCATION` | user_grant | `$string:permission_location_reason` | `EntryAbility`，`inuse` |

未声明 `INTERNET`：全部计算在本地完成，应用完全离线可用。

## 4. 设备与能力矩阵

| 能力 | phone | tablet | 不可用时的表现 |
|---|---|---|---|
| 太阳计算 / 日出日落 / 反向搜索 | ✅ | ✅ | — |
| RDB 持久化 | ✅ | ✅ | 启动失败时展示错误卡 + 重试 |
| 前台一次定位 | ✅（需授权） | ✅（需授权） | 权限教育卡 + 手动坐标；不影响任何计算 |
| 方向传感器 | ✅（视设备） | ⚠️ 部分平板无 | `getSensorList` 判定后显示「不可用」卡片并引导到方位图 |
| 在线地图 | ❌ 未接入 AGC | ❌ 未接入 AGC | 离线方位图 + 手动坐标 |
| 文件导出 | ✅ | ✅ | 取消/失败均回显系统返回的真实结果 |
