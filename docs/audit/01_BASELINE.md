# 01 · 安全配置与工程基线（第一轮）

> 本轮只做安全配置与工程基线，未改动业务算法、数据库逻辑与 UI。
> 所有命令均在 `C:/Project/LightBearing` 执行；敏感值一律脱敏，本文不含任何口令或证书文件名片段以外的路径信息。

## 1. Git 基线

```text
$ git rev-parse HEAD
5468b4d9b34a4be97da8320285297bf9fadfabc5

$ git branch -avv
* main                5468b4d [origin/main] feat: 落实任务书剩余遗漏项（…）
  remotes/origin/main 5468b4d feat: 落实任务书剩余遗漏项（…）
```

- 起始工作区干净（`git status --short` 无输出），HEAD 与任务书给定的审计基准 `5468b4d` 一致。
- 起始没有其它未合并分支，也没有领先/落后远程的提交。
- 已创建并切换到工作分支：`fix/core-quality-audit`（基于 `5468b4d`）。

近 8 条提交：

```text
5468b4d feat: 落实任务书剩余遗漏项（基础模型/组件/详情路由/无障碍/稳定性）
08696ef fix: 补齐任务书复审遗漏（骨架屏/等宽数字/返回拦截/撤销/跨日期线）
a69b94a feat(ui): 按设计稿重做视觉与图标，修正主题三态与页面转场
526fce4 test: 真机安装启动与功能实测通过，补验收证据
f2db738 chore: 对齐签名与包名，补充真机安装结果
24aa92b feat: 实现逐光全功能（API 26 / ArkTS）
4971d9c docs: 记录项目开发约定（主动使用 skill、查阅官方文档）
b0367d7 chore: 初始化 LightBearing 鸿蒙项目骨架
```

## 2. 签名配置审计与处理

### 2.1 现状（脱敏）

`build-profile.json5` 的 `app.signingConfigs[0]` 存在完整调试签名材料引用：

| 字段 | 是否存在 | 说明 |
|---|---|---|
| `name` / `type` | 是 | `default` / `HarmonyOS` |
| `material.certpath` | 是 | `~/.ohos/config/default_LightBearing_*.cer`（仓库外） |
| `material.profile` | 是 | `~/.ohos/config/default_LightBearing_*.p7b`（仓库外） |
| `material.storeFile` | 是 | `~/.ohos/config/default_LightBearing_*.p12`（仓库外） |
| `material.keyAlias` | 是 | `debugKey` |
| `material.keyPassword` | 是 | 已脱敏，不在任何文档/提交中复制 |
| `material.storePassword` | 是 | 已脱敏，同上 |

### 2.2 历史暴露范围（只计数，不输出值）

| 提交 | `build-profile.json5` 中敏感字段数量 | 结论 |
|---|---|---|
| `b0367d7`（骨架） | 0 | 未包含签名材料 |
| `f2db738`（对齐签名与包名） | 2 | `keyPassword` / `storePassword` 首次进入版本库 |

补充事实（用于界定风险，不下「私钥泄露」结论）：

- **证书与密钥库文件本身从未进入仓库**：`git ls-files | grep -iE '\.(p12|cer|p7b|csr|keystore|jks)$'` 为空。
- `local.properties` 未被跟踪（数量 0）。
- 仓库中暴露的是**证书路径 + IDE 加密后的口令字符串**；这些口令由 DevEco 生成，配合仓库外的 `.p12` 才能完成签名。

### 2.3 处理方案（已实施）

采用与官方工程模板一致的做法（模板中即为 `"signingConfigs": []`，真实签名由本地 IDE 注入）：

1. 新增 **`build-profile.template.json5`**（入库）：与真实文件同构，但 `signingConfigs` 为空数组，
   经脚本校验不含 `keyPassword` / `storePassword` / `certpath` / `storeFile` 任何一项。
2. `.gitignore` 新增 `/build-profile.json5`，并执行 `git rm --cached build-profile.json5`：
   - 文件仍保留在磁盘（1607 字节），本地签名能力不受影响；
   - 后续提交不再跟踪该文件，避免签名口令继续进入历史。
3. **未重写历史**：`f2db738` 及之后的提交保持原样，风险以本文档记录。
4. **未替换签名身份**：所用证书/Profile 与之前完全一致，没有改用其它证书。

### 2.4 验证：本地签名构建仍然可用

```text
$ hvigorw assembleHap --mode module -p product=default -p buildMode=debug --no-daemon
> hvigor BUILD SUCCESSFUL in 2 s 489 ms

entry/build/default/outputs/default/entry-default-signed.hap    2,041,232 bytes
entry/build/default/outputs/default/entry-default-unsigned.hap  1,987,947 bytes
```

产物包含 `entry-default-signed.hap`，说明脱敏后本地仍能完成签名打包。

### 2.5 遗留风险与建议（需人工决策）

- 已公开的历史提交 `f2db738` 仍含加密口令字段。**处置建议由你决定**：若该调试证书会继续用于上架相关流程，
  建议在 AGC 后台吊销该调试证书并重新签发（属于改签名身份，本轮未擅自执行）。
- 本文档不含任何口令值；后续提交也禁止再次写入。

## 3. 工程基线核对

| 检查项 | 期望 | 实际 | 结论 |
|---|---|---|---|
| `targetSdkVersion` | 26.0.0 | 26.0.0 | ✅ |
| `compatibleSdkVersion` | 26.0.0 | 26.0.0 | ✅ |
| `runtimeOS` | HarmonyOS | HarmonyOS | ✅ |
| 模型 | Stage | `entry/build-profile.json5` → `"apiType": "stageMode"` | ✅ |
| `deviceTypes` | phone + tablet | `phone`, `tablet` | ✅ |
| 受限 ACL / 多余权限 | 无 | 仅 `ohos.permission.APPROXIMATELY_LOCATION`、`ohos.permission.LOCATION` | ✅ |
| Bundle Name | 不得修改 | `com.hhyxx.LightBearing` | ✅ 未改动 |
| 依赖可解析 | 是 | `@ohos/hypium@1.0.25`、`@ohos/hamock@1.0.0`，已安装于 `oh_modules/.ohpm` | ✅ |
| 构建脚本 | appTasks / hapTasks | 根 `hvigorfile.ts`=appTasks，`entry/hvigorfile.ts`=hapTasks | ✅ |
| 本地 SDK | API 26 | `sdk-pkg.json` → apiVersion 26，version 26.0.0.105 | ✅ |
| 测试目录 | 存在 | `entry/src/test`（5 个文件）、`entry/src/ohosTest/ets/test`（3 个文件） | ✅ |
| 构建产物 | 真实存在 | `entry-default-signed.hap` 2,041,232 B；`entry-ohosTest-signed.hap` 1,629,286 B | ✅ |

环境：DevEco Studio 26.0.0.851，hvigor 6.26.8，Node v22.20.0；真机 `4EE9K25515007252`（MIA-AL00，API 26，HarmonyOS 7.0.0.109）。

## 4. 测试实际运行情况

### 4.1 单元测试（宿主机）

```text
$ hvigorw test --mode module -p module=entry@default -p product=default -p buildMode=debug
> hvigor BUILD SUCCESSFUL in 9 s 246 ms

entry/.test/default/intermediates/test/coverage_data/test_result.txt
Tests run: 23, Failure: 0, Error: 0, Pass: 23, Ignore: 0
```

结果文件 mtime 由 `2026-10-30 06:19` 更新为 `2026-11-01 13:38`，确认是本次运行产生，而非旧结果。

### 4.2 端到端测试（真机）

```text
$ hdc -t 4EE9K25515007252 install -r entry-default-signed.hap entry-ohosTest-signed.hap
msg:install bundle successfully.   （两个 HAP 均安装成功）

$ hdc shell "aa test -b com.hhyxx.LightBearing -m entry_test -s unittest OpenHarmonyTestRunner -s timeout 90000"
OHOS_REPORT_RESULT: stream=Tests run: 4, Failure: 3, Error: 0, Pass: 1, Ignore: 0
```

失败原因（设备侧日志，非断言逻辑错误）：

```text
LB_UITEST: startAbility failed: {"code":16000001}
LB_UITEST: home assertions failed: {"code":17000003}
LB_UITEST: nav failed: {}
LB_UITEST: more page failed: {}
```

即：`aa test` 启动测试进程后，测试内 `abilityDelegator.startAbility` 被真机系统拒绝（16000001），
被测应用未进入前台，后续 UI 断言自然失败。该现象在历史轮次已记录，属于**真机后台启动限制**，
不是本轮改动引入，也不是应用崩溃。

### 4.3 未执行的测试及原因

| 测试 | 原因 |
|---|---|
| 模拟器端到端（4/4 曾通过） | 模拟器实例当前未运行；尝试启动时报磁盘空间不足（需 12.00G），未清理磁盘 |
| 真机 UI 自动化断言 | 受上述 16000001 限制，无法在真机前台断言；替代手段（系统输入注入）在第四轮回归时执行 |
| `code-linter` 独立静态检查 | 本轮以 ArkTS 编译（`@CompileArkTS`）作为静态检查；未额外跑 codelinter |

## 5. 本轮变更清单

| 文件 | 变更 |
|---|---|
| `.gitignore` | 新增 `/build-profile.json5`、`/unit-test.log` |
| `build-profile.json5` | 从 Git 索引移除（`git rm --cached`），磁盘文件保留 |
| `build-profile.template.json5` | 新增：不含任何签名材料的构建配置模板 |
| `docs/audit/01_BASELINE.md` | 新增：本文档 |

## 6. 下一轮是否具备执行条件

**具备。** 构建链路可用（签名 HAP 可产出）、单元测试可跑（23/23）、真机可安装与启动。
需要注意两点依赖：

1. 第二轮会改 `SolarCalc.events()` 的返回语义 —— 现有调用方（Home、SunPath、Calendar、Compass、PlanDetail、PlaceDetail、Reverse）都需要一起核对，避免破坏 UI。
2. 真机端到端断言受 16000001 限制，第二轮的算法回归应主要依赖单元测试与 `tools/solar-check`，不要把真机 UI 自动化当作唯一证据。

**本轮已结束，等待确认后再进入下一轮。**
