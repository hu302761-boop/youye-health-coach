# iPhone/iPad App Target 配置与真机验收

本仓库的 Swift Package 是可独立校验的业务层，且已包含可直接打开的 **`YouyeHealthCoach.xcodeproj`** 和 iOS App target。仍需要完整 Xcode 才能编译、签名、安装与真机验证。

## 已有 target 的核对

1. 用完整 Xcode 打开 `YouyeHealthCoach.xcodeproj`，选择 `YouyeHealthCoachApp` target（iOS/iPadOS 17+、SwiftUI、Universal）。
2. target 已链接本地 package `YouyeHealthCoach`，首屏为 `CoachAppShell()`；不要以网页 `health-coach-app/index.html` 代替原生界面。
3. 在 Signing 中选择自己的 Team；如 Bundle ID 已被占用，改为仅供内测的唯一标识。
4. 不配置广告、支付、第三方分析或数据上传 SDK。

## 必需能力与隐私声明

在 target 的 **Signing & Capabilities** 添加：

- `HealthKit`（最小读取；仅在用户逐次确认实际训练后写入 workout）。

在 target 的 `Info.plist` 添加：

- `NSHealthShareUsageDescription`：`用于读取你允许的健康摘要（体重、睡眠、步数、运动等），供你查看当天状态；仅正式计划日的恢复信号可保护性切换当天训练。数据默认仅在本机使用。`
- `NSHealthUpdateUsageDescription`：`仅在你逐次确认运动类型和实际开始、结束时间后，写入一条训练记录到 Apple 健康；不会写入估算热量、距离、心率、睡眠、体重或体脂。`
- `NSPhotoLibraryUsageDescription`：`仅在你主动记录计划外餐食或确认家中食材时，选择一张照片作本机估算或重排参考。照片不会上传或分享。`
- `NSCameraUsageDescription`：`仅在你主动开启训练取景提醒或拍摄家中食材时使用相机。训练画面仅在本机实时分析人体姿态；食材照片仅在你确认当天重排后保存到 App 私有目录。不录像、不缓存、不上传。`

“计划外餐食照片”和“食材不匹配”均走 PhotosPicker，照片只进入 App 私有目录；食材照片不等于自动识别，用户必须确认文字食材与克数后才可重排。训练卡中的“实时本机动作提醒”仅在用户主动点击后才会请求相机权限。它使用本机 Vision 姿态请求约每 0.25 秒刷新基础画面提示，不录像、不落盘、不上传，也不声称动作计数、精确角度、医疗诊断或动作纠正完成。

## HealthKit 最小化权限

`NativeHealthKitProvider` 只请求读取：体重、体脂、步数、睡眠、静息心率、活动能量、运动记录。游泳时长从用户授权的运动记录中汇总，**不读取游泳距离**。它只返回用于界面的摘要，不保存 HealthKit 原始样本或分享。唯一的写入路径是：用户在训练页以实际开始—停止时间结束计时、核对运动类型、再点“确认同步”后创建一条 `HKWorkout`；不会附带热量、距离、路线、心率、睡眠、视频或姿态数据。

用户拒绝/取消授权时，App 应显示“未能读取”，继续允许手动健康状态打卡，不能伪造任何健康数据。

## 真机验收（必须在 iPhone 与 iPad 上执行）

1. 安装到真机，进入“健康 → 授权并读取摘要”。
2. 在 iOS 授权弹窗中按自己的意愿允许或拒绝；验证拒绝后没有崩溃、没有虚构数值。
3. 允许至少一项后，核对显示的值是摘要。开始并停止一段实际训练，核对类型与秒数后再点同步；确认只出现一条对应 workout，未确认或写入失败时不应有新记录。
4. 在“吃什么 → 计划外餐食”选择一张照片、添加描述并记录；验证显示“估算区间”，而不是精准热量。
5. 在“我的”导出资料，确认 JSON 不含图片二进制、`local-photo://` 图片引用、HealthKit 原始样本或精确位置。
6. 在“我的”确认删除，验证 App 内记录和本地计划外餐食照片被清除；系统照片图库与 Apple 健康数据仍存在。
7. 在“健康 → 本周复盘”手动保存体重/腰围/备注，强制关闭 App 后重新打开，确认趋势点仍在；确认复盘只提示一个重点变量、不会自动改目标/热量/训练，且朋友精简周报预览不含趋势点。

当前开发环境只有 Command Line Tools，无法在此处编译、签名、运行或真机验证已有 Xcode target；以上是下一步所需的实际验收门槛。
