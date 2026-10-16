# Apple 端首次运行｜醒来后最短步骤

当前工程已通过静态检查，但这台 Mac 只有 Command Line Tools，尚未具备 iPhone/iPad/Mac 原生 App 的编译、签名或安装条件。以下步骤需要由你本人完成；不会上传健康资料或公开发布 App。

## 先准备一次（约 15–30 分钟，取决于 Xcode 是否已下载）

1. 从 Mac App Store 安装完整 **Xcode**，首次打开并接受协议、完成组件安装。iPhone 模拟器可稍后再装；它有助于布局检查，但不是连接真机安装的前置条件。
2. 打开终端，在项目目录运行：

        cd "/path/to/youye-health-coach"
        zsh scripts/check_iphone_build_environment.sh
        zsh scripts/preflight_ios_build.sh
        zsh scripts/preflight_watchos_build.sh
        zsh scripts/preflight_macos_build.sh

   环境检查和对应 target 的无签名预检通过前，不要把 App 称为“已安装”。
3. 双击打开 `YouyeHealthCoach.xcodeproj`。在 Xcode 的 **Settings → Accounts** 登录自己的 Apple ID。

## 先跑 iPhone / iPad

1. 在 Xcode 左上选择 Scheme：`YouyeHealthCoachApp`。
2. 连接已信任、运行 iOS/iPadOS 17+ 的设备；如系统要求，开启开发者模式。
3. 打开 Target → **Signing & Capabilities**：
   - Team 选择自己的 Personal Team；
   - 保持 HealthKit capability；
   - 如 Bundle ID 与已有 App 冲突，改成自己唯一的 ID；若要使用 Watch，同时在 `YouyeHealthCoachWatchApp` target 把 `WK_COMPANION_APP_BUNDLE_IDENTIFIER` 改成**完全相同的 iPhone Bundle ID**。
4. 点击 Run。成功在真机打开后才算“已安装”。
5. 按 [DEVICE_ACCEPTANCE.md](DEVICE_ACCEPTANCE.md) 依次验证 HealthKit 授权/拒绝、相机、照片、日历、晚起时间表、逐项本机提醒、导出/删除及 56 天阶段边界。通知只在“我的 → 我的时间表 → 允许通知并更新提醒”这一主动操作时请求，拒绝后仍可手动执行日卡。

若 App 显示“本地资料需要恢复”，先不要删除或卸载 App。它会锁住新建和保存以保护旧资料；只点“重试读取本地资料”，持续失败时保留设备上的现状，待恢复后再继续。

## 最后跑 Apple Watch 配套端（可选）

1. 确认 Watch 已与刚才的 iPhone 配对，并先核对 Watch target 的 `WK_COMPANION_APP_BUNDLE_IDENTIFIER` 与 iPhone target 的 `PRODUCT_BUNDLE_IDENTIFIER` 完全一致；在 Xcode 选择 `YouyeHealthCoachWatchApp` Scheme 和配对 Watch。
2. 点击 Run。Watch 只显示 iPhone 同步的第 1–56 天当天日卡、最低训练版与本地计时；准备日、阶段评估日或跨午夜的旧卡会隐藏。它不读取或写入 Apple 健康，也不录像、缓存、播放视频或做姿态分析。
3. 回到 iPhone 的“今天”页，确认 Watch 只接到三餐名称、训练最低版、恢复标志与安全边界。真实训练在 iPhone 核对后仅保存为本机草稿，不写入 Apple 健康。

## 再跑 Mac

1. Scheme 切换为 `YouyeHealthCoachMacApp`，Destination 选择 **My Mac**。
2. 点击 Run，验证侧栏、当天日卡、本机资料保存、导出和删除。
3. Mac 版没有 Apple 健康读写、前摄姿态分析或自动跨设备同步；这是能力边界，不是错误。

## 当前绝不会做的事

- 不自动读取位置、查询价格、推送优惠、领券、下单或购买。
- 不上传 HealthKit 原始样本、餐食照片或训练视频。
- 不创建 TestFlight、App Store Connect、公开下载链接或邀请朋友。真机验收完成并由你明确决定后，才讨论下一步分发。
