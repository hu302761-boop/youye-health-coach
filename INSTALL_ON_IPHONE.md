# 今晚安装到 iPhone

当前仓库已包含可直接打开的 `YouyeHealthCoach.xcodeproj`、原生 SwiftUI App 入口、HealthKit entitlement 与隐私文案。`project.yml` 仅保留为工程描述备份，不需要安装 XcodeGen。但这台 Mac 当前只有 Command Line Tools，尚未安装完整 Xcode，因此**还不能编译、签名或安装到 iPhone**。没有有效 Apple 签名时，不存在安全、可用的“直接下载 ipa”。

可先运行只读环境检查：

```bash
zsh scripts/check_iphone_build_environment.sh
```

它不会下载软件、修改签名或安装 App；当前机器预期会报告完整 Xcode 缺失。模拟器仅用于后续布局检查，不是连接 iPhone 真机安装的前置条件。

## 前置条件

1. 在 Mac App Store 安装完整 **Xcode**，首次打开完成组件安装。
2. 在 Xcode 的 Settings → Accounts 登录你的 Apple ID。免费个人团队可供自己的连接设备调试安装；朋友分发需要 Apple Developer Program 和 TestFlight。
3. 用数据线连接 iPhone，并在 iPhone 上点“信任此电脑”；如系统提示，前往“设置 → 隐私与安全性”开启开发者模式。iPhone 系统需 iOS 17 或更新版本。

完整 Xcode 可用后，先执行不签名构建预检：

```bash
zsh scripts/preflight_ios_build.sh
```

它只做工程解析与 iPhone SDK 的无签名编译，不登录 Apple ID、不安装 App、不产生 ipa。通过后再继续下面的签名和真机步骤。

> Watch 配套 App 另有自己的图标资源；只有完整 Xcode 的 asset compiler 和 Archive 通过，才可称 Watch 资源可打包。当前 Command Line Tools 环境无法执行这一验证。

## 签名、安装

1. Xcode 安装完成后，在 Finder 双击或终端运行：

```bash
open YouyeHealthCoach.xcodeproj
```

2. Xcode 内选择 `YouyeHealthCoachApp` target → Signing & Capabilities：
   - 勾选 `Automatically manage signing`；
   - 选择你的 Team；
   - 若 Bundle ID 已被占用，改成你的唯一 ID；
   - 如同时安装 Watch companion，在 `YouyeHealthCoachWatchApp` target 的 Build Settings 中把 `WK_COMPANION_APP_BUNDLE_IDENTIFIER` 改为该**完全相同**的 iPhone Bundle ID；
   - 确认 `HealthKit` capability 存在。
3. 选择已连接 iPhone 作为运行设备，点击 Run。首次安装按系统提示确认开发者/健康权限；拒绝权限也必须能正常进入手动打卡。

## 真机验收（安装后）

- 仅计划开始前一晚显示“启动准备日”，不把它记成第 1 天；提前多日打开时不得要求解冻或备好熟饭；配置的本地开始当天才显示第 1 天。
- HealthKit 只读取体重、体脂、步数、睡眠、静息心率、活动能量、运动记录；游泳时长从运动记录汇总，不读取游泳距离。读取结果只在当前健康页显示，不写入本机导出或朋友周报。训练页的实际开始/停止计时和确认记录只保存于本机，绝不写入 Apple 健康；不写热量、距离、路线、心率、睡眠、体重、体脂、视频或姿态结果。
- HealthKit 摘要在启动准备日和阶段评估日仅供查看；你仍可保存本人状态，但不会创建恢复训练日、打卡或下一阶段计划。仅第 1–56 天的保护性恢复信号才会改写当天训练并留下本机审计。
- 照片、导出、本地删除、动态字体、深色模式和不同 iPhone 尺寸按 `DEVICE_ACCEPTANCE.md` 执行。全量删除仅清除当前资料及其关联 App 私有照片，不影响系统照片图库、Apple 健康原始数据或其他独立资料。
- 未核验的训练卡提供“去 B 站搜索这组关键词”按钮，而不是猜测或冒充可播放课程；只有名称、UP 主、链接和核验时间齐全的候选才会出现直接链接。外跳到 B 站/浏览器会立即结束本机取景，外部视频播放期间绝不会声称仍在实时分析。腰腹、体态等固定 iPhone 的静态陆上动作还可由本人点“在 App 内打开 B 站并同步本机提醒”：该页以非持久化 B 站会话显示搜索/候选页面，关闭即销毁，视频不下载、录制或持久缓存；只有再次确认安全条件才会开启本机相机。B 站播放、账号、地区和课程安全性仍需真机现场核验，失败时按最低版完成，不得称“课程已验证”。
- 测试“实时本机动作提醒”时，确认只在主动点击后请求相机权限，约每 0.25 秒刷新基础画面提示，退出页面后前置摄像头停止，且不保存或上传画面。可选语音提醒仅播报变化后的风险/取景提示，并使用 iPhone 当前系统音量；App 不设置独立音量。它不做动作计数、精确角度判断、诊断或“纠正完成”承诺。
- 在“我的 → 我的时间表”先保存作息，再在“本机提醒（可选）”逐项打开需要的提醒并点“允许通知并更新提醒”。系统通知权限只在这次点按时请求；通知只提示查看“第一餐／午餐饭盒／晚餐／训练或恢复／睡前准备”，不显示健康、食材、位置、价格或完整计划。静默时段内的提醒不会自动改到别的时间，关闭某项或关闭时间表会清除本 App 的旧提醒。
- 游泳、骑行和步行时不要开启取景或边运动边看手机；只有耐力结束后做室内静态呼吸、拉伸或腰腹动作，且手机固定稳定时，才测试实时提醒。
- 如同时安装 Apple Watch companion：Watch 只接收 iPhone 同步的第 1–56 天当天三餐名称、最低训练版、恢复标志与本地计时；跨午夜、启动准备日或阶段评估日必须隐藏旧卡和计时入口。真实训练仅留在 iPhone 本机记录，不写入 Apple 健康。
- 测试“食材不匹配”时，先拍摄/选择家中食材，核对文字食材与克数，再查看旧/新餐卡并确认写入；取消时未确认照片应从 App 私有目录移除，导出与全量删除也不能保留照片引用。
- 如果首次启动出现“本地资料需要恢复”，不要点删除、卸载 App 或重新建档：该页面已经锁定保存，原资料不会被覆盖、删除或上传。先点“重试读取本地资料”；若仍失败，保留设备和 App，待后续恢复再处理。
- 安装后逐项勾选 `DEVICE_ACCEPTANCE.md`；未勾选的项目不能声称已真机完成。

## 分发边界

- **本人手机**：Xcode 连接真机 Run 即可，不需要生成或下载 ipa。
- **朋友内测**：待本人真机验收后，使用 TestFlight；这需要 Apple Developer Program、Archive、App Store Connect/TestFlight 配置，不能伪造安装链接。
