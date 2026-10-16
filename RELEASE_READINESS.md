# 原生内测发布就绪度（证据版）

最后核验：2026-08-08（本机 Command Line Tools 环境；已完成首页/日历/每日详情计划一致性审计）。这不是“可安装”的声明；只记录当前可复核的工程证据与仍需真机完成的事项。

需求逐项映射见 [MVP_REQUIREMENTS_AUDIT.md](MVP_REQUIREMENTS_AUDIT.md)。

| 范围 | 当前证据 | 结论 |
| --- | --- | --- |
| 56 天自炊日卡 | `swift run YouyeHealthCoachRuleCheck` 通过，校验克数、前置分装、分钟步骤、保存/加热与 20 分钟上限 | 规则与数据已通过命令行校验；仍需 iPhone 逐卡视觉验收 |
| 计划入口一致性 | 首页、8 周日历和每日详情均按“基础计划 → 已确认食材替换 → 已保存恢复保护”重放；同一日索引与同一日期只读边界 | 命令行与静态审计通过；仍需 iPhone 真机点击验收 |
| 恢复优先与状态调整 | 同一规则检查覆盖疼痛、病症、用药、经期不适、短睡眠、皮肤等状态与确认边界 | 自动保护性退阶有审计；目标/热量/加量/周结构仍需本人确认 |
| HealthKit | `scripts/verify_ios_project.sh` 与规则检查覆盖摘要最小读取、跨来源保守汇总、异常值隐藏，以及训练仅本机保存、不回写 Apple 健康 | 仅为源码/配置证据；尚未在 iPhone 授权或读取 |
| 实时姿态提示 | iOS 静态检查确认 Vision、前摄、约 0.25 秒提示、系统音量语音、每次新会话重置播报去重、无录制/缓存与 iPad 降级路径 | 尚未在 iPhone 真机验证相机、语音、后台中断或姿态效果 |
| 私有数据 | 规则检查覆盖 owner 私有照片、导出排除、删除/中断恢复、异步 owner 隔离 | 仍需真机验证 iOS 完整文件保护与实际删除行为 |
| 首次启动与恢复保护 | 规则检查确认首次输入保留 owner 身份、不会静默启用提醒/优惠/热量框架；静态检查确认首次保存前不可关闭设置、HealthKit/相机/通知/附近服务均不自动请求 | 仍需在真机模拟存储失败、无法读取旧资料与全量删除后重建 |
| iPhone/iPad/Mac/Watch 工程 | iOS 静态检查确认 target、privacy manifest、Watch 最小日卡及 Mac 能力边界 | 尚未由完整 Xcode 编译、Archive 或设备运行 |
| Android | `scripts/verify_android_project.sh` 通过 starter 结构与隐私边界 | 不是 APK，不能作为可下载 Android App |
| 安装产物 | 当前无 `.ipa`、`.xcarchive`；`xcode-select -p` 指向 `/Library/Developer/CommandLineTools` | **不可安装**：需完整 Xcode、Apple 签名与连接真机 |

## 真正可安装前的顺序

1. 安装完整 Xcode，并在 Xcode 的 Settings/Locations 选择它，而不是 Command Line Tools。
2. 打开 `YouyeHealthCoach.xcodeproj`，为 iPhone/iPad、Watch、Mac target 选定个人 Team 和唯一 Bundle ID；同步 Watch companion ID。
3. 连接 iPhone，用 Debug **Run** 实际安装并完成 [DEVICE_ACCEPTANCE.md](DEVICE_ACCEPTANCE.md)。
4. 验收通过后才能 Archive；若邀请朋友，再按 TestFlight 流程分发免费内测版。没有 Archive/签名/真机证据时，不生成或宣称存在下载链接。

## 每次变更后的最小命令行门槛

```sh
swift build
swift run YouyeHealthCoachRuleCheck
zsh scripts/verify_ios_project.sh
zsh scripts/verify_android_project.sh
```

这些命令不能取代完整 Xcode、Simulator 或真机测试；尤其不能证明 HealthKit 权限、相机、通知、Apple Watch 配对、签名或安装成功。
