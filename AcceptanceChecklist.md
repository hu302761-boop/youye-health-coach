# iPhone MVP 验收清单

本清单区分「命令行规则已验证」与「必须在完整 Xcode + iPhone 真机验证」。Swift Package 通过构建不等于 iOS App 已交付。

| 能力 | 当前状态 | 已有证据 | 真机验收门槛 |
| --- | --- | --- | --- |
| 56 天饮食/训练卡 | 规则已验证 | `swift run YouyeHealthCoachRuleCheck` | 56 张晚餐卡、7 张早餐循环卡和 56 天午餐路径均校验克数/毫升、前置、单电饭锅+单电磁炉锅的分钟步骤、份数、食安、复热、替换说明与≤20分钟；56 张训练卡连续覆盖计划、每周含恢复日/耐力替代日、无连续 4 天腰腹/体态高负荷，并写明停止条件；真机检查三餐卡在不同尺寸无截断/重叠。 |
| 当天优先与恢复退阶 | 规则已验证 | `TodayFeature`、`TrainingFeedback`、状态/反馈范围检查、规则检查 | 录入睡眠不足、疼痛、病症等状态，确认当天显示恢复版，并保留原因与审计记录；非数字或不合理睡眠/心率/反馈分值必须留在表单中提示修正，不能保存或改写日卡。 |
| 食材确认后重排餐食 | 规则已验证 | `MealSubstitution`、持久化重载检查 | 拍摄/选择食材后，用户确认替换早餐、午餐或晚餐；确认仅改变对应餐次，不改目标、热量、训练或未来计划。 |
| 计划外餐食 | 规则已验证 | `UnplannedMeal`、`PrivateMealPhotoStore` | 用 PhotosPicker 选图；确认仅显示保守估算范围，并提示下一餐正常回归、不补练、不挨饿。 |
| HealthKit 最小读取 + 确认训练写入 | 待真机 | `NativeHealthKitProvider`、`HealthWorkoutSyncSafety`、摘要异常值过滤条件编译代码 | 配置 HealthKit capability 后，在授权/拒绝两种路径验证：只读体重、体脂、步数、睡眠、静息心率、活动能量和运动记录；不读取游泳距离。明显异常的聚合值必须隐藏并提示到 Apple 健康核对，不能影响恢复判断；只有本人确认实际开始/结束、类型的训练才可写入一条 workout；不写热量、距离、路线、心率、睡眠、体重或体脂。另测“HealthKit 成功但本机回执落盘失败”：保持待核对防重封锁，不能显示成功或盲目重写。 |
| 本机姿态提醒与 B 站跟练 | 静态隐私路径已验证，待真机 | `LocalPoseCoach`、`EphemeralBilibiliFollowAlongView`、静态工程检查 | 用户主动开启才申请前置摄像头；Vision 仅实时分析人体关键点；关闭/离页即停止；无录像、文件写入、网络上传、动作计数或医疗诊断。默认 B 站仅显示待核验搜索词；静态陆上动作可由用户主动打开非持久化、无缓存重用且仅允许 B 站 HTTPS 域名的临时会话，并在同页另行确认本机取景。真机确认第三方播放失败会明确降级到最低版，不能称课程已验证。 |
| 本地导出与删除 | 规则已验证，待真机文件流程 | `PrivateExport`、`LocalDataDeletion`、两阶段删除回滚检查 | 导出文件不含图片二进制、`local-photo://`、HealthKit 原始样本、精确位置；全量删除后 App 私有照片与 JSON 清除，而系统照片和健康记录保留；不得自动新建/保存空白档案，须回到首次设置。 |
| 朋友周报 | 规则已验证 | `WeeklyReportPreview`、确认/撤回检查 | 逐次预览、勾选确认、本地生成、撤回；本地记录不含资料标识。未来系统分享仍须单独确认，且最小载荷仅含完成率和用户主动填写的文字，不会自动发送。 |
| 全设备兼容与易用性 | 待真机 | 已有 iPhone Tab、iPad/Mac 侧栏、动态字体日历降级和 VoiceOver 标签 | 至少在 320pt 宽窄屏、标准 iPhone、Pro Max、iPad 横竖屏、深色模式、最大动态字体、VoiceOver 和中文系统下完成视觉/触达/状态回归；详见 `DEVICE_ACCEPTANCE.md` 的“正式 UI、易用性与无障碍回归”。 |
| Watch 隐私与最小同步 | 静态工程已验证，待配对真机 | 独立 Watch `PrivacyInfo.xcprivacy`、无 HealthKit/相机/照片/定位/通知 API 的自动检查、`WatchCompanionStore` 和白名单日卡载荷检查 | 配对 iPhone/Watch 后确认 Watch 不请求 HealthKit、相机、照片、麦克风、定位或通知权限；只呈现 iPhone 同步的当天日卡，跨午夜立即隐藏旧卡。 |
| 附近优惠与价格真实性 | 本地偏好/证据门槛已验证，实时服务未接入 | `NearbyOfferPolicy`、无位置/联网/后台查价/推送 API、关闭 scheme 位置模拟的自动检查 | 当前只保存提醒偏好与阈值，并明确没有实时数据；未来接入前必须另行完成用户地点授权、来源/时效/条款展示、通知选择和真机/网络验收。 |
| Android 原生端 | 仅静态骨架，冻结 | Compose 五入口、平板导航与 Health Connect 可用性显示；无 Android 健康权限声明的自动检查 | 不能称 APK 可安装或 Android 功能完整。Apple 核心真机验收后，才实现 56 天数据、本地持久化、食材照片、明确授权的 Health Connect 读写、CameraX/MediaPipe 和各品牌真机验证。 |
| Mac 原生桌面端 | 待完整 Xcode 桌面构建 | `YouyeHealthCoachMacApp`、`DesktopCoachShell` | 在 macOS 14+ 下打开后使用侧栏 + 单日详情完成日卡、食谱、训练反馈、状态、复盘、导出与删除；确认不把 iPhone/iPad 的 HealthKit、前摄姿态或自动同步状态伪装成可用。 |

## 运行前置

1. 使用完整 Xcode 打开已有 `YouyeHealthCoach.xcodeproj`，确认 iOS 17+ SwiftUI target 已链接本 Package。
2. 配置唯一 Bundle ID、签名与 HealthKit capability；不接广告、支付、第三方分析或上传 SDK。
3. 使用 `iOSAppSetup.md` 配置隐私文案；只在相机动作提示实际实现后才添加相机权限。
4. 每次改动业务规则后，先运行：

```bash
swift build
swift run YouyeHealthCoachRuleCheck
```

5. 改动 iOS 工程配置后，额外运行：

```bash
zsh scripts/verify_ios_project.sh
```

该脚本只校验 target、iOS 17、HealthKit capability/entitlement、隐私文案、共享 scheme 与 App Icon；它不构建、签名、安装或替代真机验收。

6. 真机验收通过后，才可将对应项目从「待真机」标为「已完成」。

执行时使用 [DEVICE_ACCEPTANCE.md](DEVICE_ACCEPTANCE.md)，逐项记录真实结果。
