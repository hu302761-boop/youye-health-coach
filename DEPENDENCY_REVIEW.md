# Apple 原生依赖审计

最后核查：2026-08-17。此文件只记录选型和边界，不能代替 Xcode 编译、签名或真机验收。

## 2026-08-17：本机文件导入依赖

### CoreXLSX 0.14.2

- 仓库：[CoreOffice/CoreXLSX](https://github.com/CoreOffice/CoreXLSX)，Apache-2.0；当前解析版本锁定修订 `1391f3832ea2eeee5186ea8abb81ea49ed0609cc`。
- 用途只限本人选择的钱迹 XLSX 支出预览；不写回 Excel、不上传、不联网查账。
- 传递依赖 XMLCoder 0.14.0（MIT，修订 `ca932442d7481700f5434a7b138c47dd42d9902b`）与 ZIPFoundation。

### ZIPFoundation 0.9.20

- 仓库：[weichsel/ZIPFoundation](https://github.com/weichsel/ZIPFoundation)，MIT；当前解析版本锁定修订 `22787ffb59de99e5dc1fbfe80b19c97a904ad48d`。
- 用途：CoreXLSX 的 XLSX 容器读取，以及本人选择的 Apple 健康导出 ZIP 读取。健康导入只选取非 CDA 的最大 XML，限制 ZIP 为 512 MB、XML 为 1 GB，不读取路线或心电图条目。
- 导出 XML 只解压到随机 App 临时目录；iOS 文件创建时使用完整文件保护，XMLParser 禁止外部实体，无论成功或失败都在返回前删除临时目录。原始样本不进入 `PrivateCoachData`。
- 只有本人在预览页再次确认时，才能将一条聚合体重保存到对应周趋势；重复确认是幂等的，不保存其他健康原始数据，不改今日恢复判断。
- 代码审计确认这两条本机导入路径不使用 `URLSession`或任何上传 API。

## 本轮：健康与动作能力复核（GitHub 只读）

### 已核查

- GitHub：[brittanyarima/Steps](https://github.com/brittanyarima/Steps)，MIT；为 HealthKit + SwiftUI 的步数 App 示例。2026-08-08 核查时最近代码推送为 2024-02-04，不能作为本产品健康写入、授权分级或隐私边界的依赖基础。
- GitHub：[mrikh/healthkit-swiftui](https://github.com/mrikh/healthkit-swiftui)，未声明许可证，最近代码推送为 2021-03-08；不复制代码、不引入依赖。
- GitHub：[shilpamerlin/FitnessApp](https://github.com/shilpamerlin/FitnessApp)，未声明许可证，最近代码推送为 2024-09-10；不复制代码、不引入依赖。
- 针对 SwiftUI + Vision 姿态的 GitHub 搜索没有检出可作为稳定、许可明确、并符合“逐帧后丢弃、不录像不上传”的轻量依赖。现有 `Vision` / `AVFoundation` 实现只覆盖 iPhone、固定室内、陆上静态姿态提醒，范围更窄也更可审计。

### 当时结论：健康与姿态能力继续零第三方 SDK

- 不引入 HealthKit 封装：目前只需读取最小聚合摘要；实际训练只保存于 App 本机，不写入 `HKWorkout`。原生 API 已能清楚表达只读授权与隐私边界。
- 不引入姿态 SDK：第三方模型、云识别或视频管线会增加二进制体积、许可/模型更新与私密相机数据风险；现有原生路径更符合“无录播、无缓存”的产品承诺。
- 该结论仅指 HealthKit 封装、姿态 SDK 和云端识别。2026-08-17 为本机文件导入加入了上方两个可审计 package；不得再将当前工程描述为“零外部 package”。任何未来依赖仍必须记录许可证、维护状态、数据流、网络行为、体积、删除路径与 Apple 真机验收结果。

## 本轮：Apple Watch 日卡桥接

### 已核查

- Apple 一方能力：`WatchConnectivity` 的 `WCSession` / `updateApplicationContext`。本项目只需把**最新一份、非敏感、当天正式日卡**交给已配对 Watch；不需要聊天、文件传输、队列任务或实时双向消息。
- GitHub：[Communicator](https://github.com/KaneCheshire/Communicator)，MIT，2026-08-08 核查时未归档、最近更新时间为 2026-07-29。它封装了 iPhone/Watch 通信。
- GitHub：[WatchConnectivitySampleForSwiftUI](https://github.com/MilanistaDev/WatchConnectivitySampleForSwiftUI)，2026-08-08 核查时未归档、最近更新时间为 2026-07-29。它演示 SwiftUI 与 `WatchConnectivity` 的基础桥接；仓库元数据未声明许可证，因此不复制其代码或引入依赖。

### 结论：不引入第三方桥接库

继续直接使用 Apple `WCSession.updateApplicationContext`：

- 它符合“只保留最新日卡”的语义；旧卡不需要被排队送达。
- 载荷只含当天三餐名称、训练最低版、恢复标志、时间戳与相机安全说明；不含 HealthKit 摘要、照片、视频、姿态结果、地点或完整私有资料。
- `WatchDailyCardPayload` 是共享规则层的白名单契约，规则检查会验证正式日与非正式日的 keys；桥接层不得绕过它直接序列化 `TodayPlan` 或 `PrivateCoachData`。
- iPhone 会在启动准备日、阶段评估日发布不可执行状态；Watch 在跨午夜、非正式日或无效日卡时隐藏旧卡和本地计时入口。
- 直接平台 API 的授权、重试、隐私和删除语义更容易审计；不引入网络、分析、视频或不透明持久化能力。

### 尚未完成的验证

- 完整 Xcode 下实际 Archive，确认 Watch target、配对 Bundle ID、嵌入关系和签名均通过。
- 在一台已配对 iPhone + Watch 上验证首次同步、跨午夜失效、准备日/阶段评估日清卡，以及 Watch 不会写入 Apple 健康。

## 保持的 Apple 首发依赖边界

- 健康：iPhone/iPad 上直接使用 `HealthKit`；只读取最小聚合摘要，真实训练仅保存在 App 本机。
- 姿态：iPhone 上直接使用 `Vision` 与 `AVFoundation`；逐帧分析后丢弃，不录像、不缓存、不上传。
- UI：`SwiftUI`、`PhotosUI` 与系统文件导出；不接广告、支付、行为分析、视频托管或云端同步 SDK。
- 提交准备：iPhone、Mac 和 Watch target 都各自带最小 `PrivacyInfo.xcprivacy`。iPhone/Mac 声明不跟踪、没有对外收集的数据类型，并仅列出 App 私有 `UserDefaults` 偏好的 required-reason 用途（`CA92.1`）；Watch 不使用该类 API，因此清单明确为空。它们不替代上架前按当时 Xcode / App Store Connect 提示进行的最终核对。
- 本地照片：不引入图片云存储或识别 SDK；`PrivateMealPhotoStore` 以资料 owner 分目录保存，并以 owner 绑定引用防止未来内测资料之间的本机串读/串删。旧无 owner 引用只在加载其原资料时复制并改写为 owner 引用；新版 JSON 成功持久化后才清除旧副本，日常读取/删除不回退共享旧目录。
- 跨设备自动同步尚未实现；Mac 与 iPhone 数据默认独立，不能声称已同步。
