# Apple 优先与后续跨端实施规范

> 当前正式交付路径是 **iPhone → iPad → Mac**。Swift 工程是唯一正在推进的产品工程；Android 工程仅保留未来独立 Kotlin 实现的骨架和可迁移数据契约，直到 Apple 端完成真实安装与核心真机验收前，不推进 Android 功能。任何端都不会使用网页套壳，也不会把 Apple API 假装成全平台能力。

## 覆盖承诺与诚实边界

| 平台 | 第一方应用 | 健康数据入口 | 实时姿态/语音 | 当前工程状态 |
| --- | --- | --- | --- | --- |
| iPhone / iPad（iOS 17+） | SwiftUI 通用 iOS target | Apple HealthKit：最小只读；实际训练仅保存于 App 本机 | Vision + 前摄，本机逐帧丢弃 | 已有工程；已改为 iPhone+iPad target，待 Xcode/真机验证 |
| Mac（macOS 14+） | SwiftUI 桌面端，侧栏 + 日卡详情 | 不读取或写入 Apple 健康；HealthKit provider 不编入 Mac target，提供手动状态与本机资料管理 | 不提供摄像头姿态提示 | 已有工程，待完整 Xcode 下构建/桌面验收 |
| Android 手机 / 平板（Android 8+） | Kotlin + Jetpack Compose 自适应界面 | Health Connect 优先；仅已授权聚合摘要 | CameraX + MediaPipe Tasks，本机逐帧丢弃 | **后续范围，当前冻结**；原生 Compose 日卡骨架已创建，待 Apple 端验收后再构建与真机验证 |
| Samsung 手机 / 平板 | 同一 Android APK，不另做网页 | 用户自行在 Samsung Health/Health Connect 中开启同步后，App 只从 Health Connect 读取已授权项 | 同 Android | 不直接抓取 Samsung 帐号或伪造 Samsung 数据 |
| 华为 Android / EMUI 手机 / 平板 | 同一 Android APK，按设备能力降级 | 先检测 Health Connect；不可用时提供手动状态。Health Kit 是后续可选、逐次授权的 provider | 同 Android；需设备实际支持相机/推理 | 不承诺所有地区、机型或无 GMS 的设备都有 Health Connect |
| HarmonyOS NEXT | 独立 HarmonyOS 工程，不能由 Android APK 自动覆盖 | 后续接 HarmonyOS/Huawei 可用健康能力 | 后续原生实现 | 尚未实现，不能宣称已支持 |
| Apple Watch | 与 iPhone 配对的 companion | 不读写 Apple 健康；真实训练仅由 iPhone 本机保存 | 只显示第 1–56 天当天日卡/本地计时；没有相机、录像或姿态分析 | watchOS target 与最小日卡桥接已配置；待完整 Xcode 与配对真机验收 |

“华为、安卓、三星都能用”是后续产品方向，不是当前可交付承诺：Android 原生版本将以每日计划、餐卡、打卡、状态调整、私有照片引用和手动计时为目标；目前只存在原生导航与健康服务可用性骨架，未实现这些数据与操作。健康数据是否可接入还取决于手机系统、地区、帐户和授权结果，不能因品牌名称而虚构可读数据。

Mac 是同等可用的个人主端：它不是手机镜像，也不是网页包装。它适合阅读日卡、安排采购、记录状态、完成复盘、导出/删除本机资料；健康读取/写入和实时取景始终留在具备对应系统能力、且已授权的移动端。

## 不重复造轮子：已核查的实现方向

2026-08-08 已通过 GitHub API 审查以下公开实现/示例的适用范围：

- [Android Health Connect Codelab](https://github.com/android/android-health-connect-codelab)：Android 官方组织的 Health Connect 入门示例，作为权限和记录读写流程的参考。
- [MediaPipe Samples](https://github.com/google-ai-edge/mediapipe-samples)：Google 官方边缘 AI 示例，作为 Android 本机 Pose Landmarker/CameraX 的参考。
- [HealthKMP](https://github.com/vitoksmile/HealthKMP) 与 [KHealth](https://github.com/shubhamsinghshubham777/KHealth)：跨端健康包装层的公开实践。当前不直接引入：健康写入、许可语义和隐私删除需要由本产品明确审计，不能被第三方抽象掩盖。

因此选型是 Apple 的 HealthKit / Vision / AVFoundation 与 Android 的 Health Connect / CameraX / MediaPipe Tasks。不会接入广告、行为分析、视频托管或不透明健康 SDK。

## 共享核心与端侧适配

```text
可迁移领域规则与数据契约
  56天餐卡 · 训练卡 · 状态保护退阶 · 跳过/完成语义 · 替换预览 · 私有导出/删除 · 已确认训练
                                  │
               ┌──────────────────┴──────────────────┐
               │                                     │
Apple app (SwiftUI)                       Android app (Kotlin/Compose)
HealthKit / Vision / WatchConnectivity    Health Connect / CameraX / MediaPipe
               │                                     │
      只读聚合摘要；训练仅本机保存           只读聚合摘要；训练仅本机保存
```

1. **领域规则不依赖设备 SDK。** 餐卡、训练安全条件、保护性退阶、今日是否可打卡、明确跳过与周复盘口径、导出剔除规则以跨端契约表示；两端各自有可测试的实现，不能在 UI 内复制 56 天业务判断。明确跳过与遗漏不同：跳过保留为主动状态，已完成项照实计入，未完成项按 0 项计；分母只含已发生的正式计划日。
2. **健康 provider 是可选项。** `unavailable`、`notAuthorized`、`noReadableData` 都是正常状态，界面提供手动状态入口，绝不显示 0 或猜测值。
3. **训练本机保存原则。** 仅保存用户明确确认的运动种类与实际开始/结束时间；不写计划时长、估算热量、距离、路线、心率、睡眠、相机帧或姿态结论到 Apple 健康。每次计时仅由本机随机标识区分草稿；读取睡眠/运动时，对多个来源重叠时间取并集，不能把 phone、Watch 或其他已授权应用的同一时段重复相加。
4. **本机视频原则。** 开始取景必须由用户点按；相机帧进入本机推理后立即丢弃，无录像、缓存、回放、下载、导出或上传。语音跟随系统音量，不单独改变音量。
5. **跨设备同步不是默认上传。** 当前资料保持端侧私有。以后若用户明确选择同一账号跨设备同步，需单独设计端到端加密、冲突规则、删除传播与可撤销授权；未完成前各端独立使用，不声称自动同步。
6. **恢复记录不是撤销按钮。** 疼痛、生病、用药限制、经期明显不适、睡眠不足或已确认的高静息心率触发的保护性退阶，是解释风险信号与恢复方案的审计历史。用户须先更新当天身体状态，才可重新评估；重大目标/热量/加量/周结构调整始终新建确认记录，不覆盖旧记录。

## 健康数据最小契约

| 业务字段 | Apple | Android | 写入规则 |
| --- | --- | --- | --- |
| 体重、体脂、步数、睡眠、静息心率、活动能量、运动时长 | HealthKit 授权的聚合摘要 | Health Connect 已授权记录的聚合摘要 | 只读；不进本地导出原始样本 |
| 已确认训练 | App 私有训练草稿 | App 私有训练草稿（未来） | 用户核对类型、真实开始/结束后仅保存于本机；不回写系统健康记录 |
| 游泳距离、路线、录像、姿态数据 | 不读/不写 | 不读/不写 | 永远不作为计划调整或写入内容 |

华为 Health Kit 只能作为 Android 端的**可选 provider**：需在真实设备、帐户、地区、SDK 条款和用户逐次授权都满足时才出现；不可用就显示“当前设备未提供可连接健康数据”，并保留手动状态，而不是偷偷收集或改用别的帐号数据。

## 平板与多尺寸规则

- 所有手机与平板保持五个一级任务（今天、吃什么、练什么、健康、我的），不做长网页式连续堆叠。
- 紧凑宽度使用底部栏；中/扩展宽度使用侧栏 + 详情区。日卡始终是一日一张，56 天总览用可点按日历。
- Android 使用 `WindowSizeClass`，iPad 使用 size class / `NavigationSplitView`；主操作触达不低于约 44pt/48dp，动态字体或字体缩放下允许卡片纵向扩展，不横向截断。
- 每个平台至少覆盖：窄手机、标准手机、大屏手机、约 8–11 英寸平板、深色模式、中文、最大字体/字体缩放、横竖屏。

## 后续 Android 落地顺序（不在当前 Apple 交付周期执行）

1. 建立 Kotlin/Compose Android 工程、日卡 UI 和本地加密/删除边界；先不依赖任何健康服务。
2. 落地 Health Connect provider：当前只保留最小读取与本机训练草稿的规则契约及可用性检测，**未声明健康读写权限**；下一步才实现显式读取权限与聚合读取。绝不声明后台/历史权限或写入步数、热量、心率、体重或训练；在无服务、拒绝、数据空三条路径均可手动执行。
3. 接入 CameraX + MediaPipe Tasks 的本机实时提示，并按 Apple 端相同禁止项做隐私与安全验收。
4. 在 Samsung、华为 Android/EMUI、其他 Android 与平板真机分别验证；把“设备/地区/数据源不可用”记录为能力状态，不把失败归因于用户。
5. 在已确认的华为设备条件下评估 Health Kit adapter；HarmonyOS NEXT 另起原生目标和验收，不能混入 Android APK 发布声明。
