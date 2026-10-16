# 项目代号｜私人健康教练：MVP 需求证据矩阵

最后核验：2026-08-08。本文区分“源码/命令行可证明”和“必须在 Apple 设备或账号上验证”，不把静态检查写成已安装声明。

## 个人可执行计划

| 需求 | 当前实现 | 证据 | 状态 |
| --- | --- | --- | --- |
| 默认 100% 自炊、三餐按日卡执行 | 56 天晚餐、7 张早餐循环、56 张午餐便当；首页与日历均进入同一日卡 | `DailyMealCatalog.swift`、`RecipeCatalog*.swift`、`swift run YouyeHealthCoachRuleCheck` | 源码/规则通过；真机视觉待验 |
| 克数、解冻/分装、分钟步骤、保存/复热、20 分钟上限 | `MealRecipeCardAudit` 审计每张餐卡；单锅/电饭锅边界和便当安全规则 | `Sources/YouyeHealthCoach/RecipeCatalog.swift`、规则检查餐卡审计 | 源码/规则通过 |
| 食材不匹配后重排 | 先拍照或填写现有食材，用户确认食材和克数后只替换当天未完成餐次 | `MealSubstitution.swift`、`SwiftUIAppShell.swift`、规则检查替换/撤回用例 | 源码/规则通过；照片流程待真机验 |
| 计划外餐食照片/文字估算 | 本机保存可选照片，显示保守热量区间；不能自动断言精准热量或全天超标 | `UnplannedMeal.swift`、`UnplannedMealForm`、规则检查估算上限用例 | 源码/规则通过 |
| 超标提示与下一步 | 仅在用户确认每日热量参考且估算上限足够时提示“可能挤占空间”；下一餐回归计划，不补练/节食 | `UnplannedMealDaySummary`、`TodayNextStep.swift`、规则检查 | 源码/规则通过 |

## 训练与动态调整

| 需求 | 当前实现 | 证据 | 状态 |
| --- | --- | --- | --- |
| 零基础腰腹、体态、恢复优先 | 56 张训练卡含标准版、最低版、退阶、停止条件、睡前准备和 B 站搜索入口 | `TrainingCatalog*.swift`、`BilibiliFollowAlong.swift` | 源码/规则通过 |
| 状态输入 | 睡眠、精力、压力、饥饿冲动、消化、经期、疼痛/受伤、生病、用药限制、皮肤状态 | `HealthCheckIn.swift`、`TrainingFeedback.swift` | 源码/规则通过 |
| 低风险自动保护并留痕 | 同日保护性恢复自动重放并写入审计；目标、热量、加量、周结构必须本人确认 | `HealthCheckIn.swift`、`PersonalizationAdvisor.swift`、规则检查恢复/确认边界 | 源码/规则通过 |
| 实时动作提示与系统音量语音 | iPhone 固定、室内、静态陆上动作使用 Vision；约 0.25 秒刷新，丢弃晚帧，不录像/缓存/上传，语音使用系统音量 | `LocalPoseCoach.swift`、iOS 静态检查 | 源码/静态通过；相机/语音效果待真机验 |

## Apple 平台与数据边界

| 需求 | 当前实现 | 证据 | 状态 |
| --- | --- | --- | --- |
| iPhone/iPad 原生路径 | SwiftUI iOS 17 target，`TARGETED_DEVICE_FAMILY = 1,2` | `YouyeHealthCoach.xcodeproj`、`iOSApp/YouyeHealthCoachApp.swift` | 工程配置通过；未由 Xcode 编译 |
| Apple 健康读取 | 最小摘要：体重、体脂、步数、睡眠、静息心率、活动能量、运动；保守处理多来源/异常值 | `HealthKitIntegration.swift`、HealthKit 规则用例 | 源码通过；授权/读取待 iPhone 验 |
| Apple 健康写入 | 明确不写入；实际训练计时仅保存于 App 本机，旧版兼容字段不触发任何新写入 | `HealthKitIntegration.swift`、`SwiftUIAppShell.swift` | 源码/规则通过；读取授权待 iPhone 验 |
| Apple Watch companion | Watch 仅显示 iPhone 同步的当天三餐、最低版训练和恢复标志；不读写 HealthKit、不做姿态分析 | `WatchDailyCardPayload.swift`、`WatchCompanionBridge.swift`、`WatchApp/` | 工程/规则通过；配对待真机验 |
| Mac companion | SwiftUI 桌面版；不宣称读取 Apple 健康或相机能力 | `macOSApp/`、`SwiftUIAppShell.swift` | 工程配置通过；未由 Xcode 编译 |
| 私有、最小化、可导出/删除 | owner UUID 隔离、本地照片保护、导出排除原始 HealthKit/照片引用、两阶段删除 | `Privacy.swift`、`LocalDataDeletion.swift`、`PrivateMealPhotoStore.swift` | 源码/规则通过；文件保护待真机验 |

## 内测与发布边界

| 需求 | 当前实现/决策 | 状态 |
| --- | --- | --- |
| 免费内测、朋友独立建档 | 首次设置建立本机 owner；周报默认不生成、不发送，分享须逐次勾选精简内容 | 源码/规则通过 |
| 不虚构优惠、不购买下单 | 附近优惠目前仅保留政策/偏好占位，不定位、联网查价、下单或推送 | 明确未连接实时供应商 |
| 可安装 iPhone App | 工程已准备，但当前机器只有 Command Line Tools；无 `.ipa`/`.xcarchive`/签名身份 | **未完成：需完整 Xcode、Apple Team、真机** |

## 已运行命令

```sh
swift build
swift run YouyeHealthCoachRuleCheck
zsh scripts/verify_ios_project.sh
zsh scripts/verify_android_project.sh
```

以上命令均通过，但不能替代完整 Xcode 编译、Archive、真机权限授权、HealthKit 读取、相机/语音、Watch 配对或 TestFlight 分发。

## 当前安装环境证据

本机只检测到 `/Library/Developer/CommandLineTools`；未找到 `/Applications/Xcode.app` 或用户 Applications 下的完整 Xcode。`xcodebuild -version` 因当前开发目录不是 Xcode 而被拒绝，代码签名身份为 `0 valid identities found`，工程目录也没有 `.ipa`、`.xcarchive` 或 `.app` 产物。因此当前不能诚实地提供“直接下载/安装”链接。
