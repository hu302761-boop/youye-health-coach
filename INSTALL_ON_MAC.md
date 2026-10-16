# 在 Mac 上运行「私人健康教练」

项目现已包含原生 macOS 14+ target：`YouyeHealthCoachMacApp`。它与 iPhone target 复用同一套本地计划、日卡、餐食重排、身体状态、周复盘、导出和删除规则；不会伪装成 iPhone App，也不会在 Mac 上伪造 HealthKit 或前置摄像头数据。

## 今晚可完成的方式

1. 完整 Xcode 安装完成后，双击或运行：

   ```bash
   open YouyeHealthCoach.xcodeproj
   ```

2. 在 Scheme 下拉框选择 **YouyeHealthCoachMacApp**，运行目的地选择 **My Mac**。
3. 点击 Run。Debug 本机运行通常可由 Xcode 处理本机签名；若提示签名，选择自己的 Team。不要把 Debug 运行说成“对外可下载的 Mac App”。

## 先做无签名编译预检

```bash
zsh scripts/preflight_macos_build.sh
```

这项检查不登录 Apple ID、不创建证书、不安装 App，也不生成签名的 `.app` / `.dmg`。成功只证明 macOS target 在当前 Xcode SDK 下可编译。

## 当前平台差异（诚实边界）

- **iPhone/iPad**：HealthKit 最小读取、前置摄像头姿态提醒、PhotosPicker 的最终授权与实际数据，必须在移动端真机验证。实际训练计时仅保存于 App 本机，不写入 Apple 健康。
- **Mac**：可看计划、记录打卡/状态、进行餐食重排、周复盘、导出和删除；健康页会明确显示 Mac 端不能读取 HealthKit，而非显示虚构数值。
- 同一设备内的数据会本地保存；跨 Mac/iPhone 自动同步尚未接入 CloudKit，不能承诺两端数据实时同步。

## Mac 使用验收（首次打开后）

1. 用侧栏依次打开“今天 / 吃什么 / 练什么 / 健康 / 我的”；确认窗口调整为最小宽度、放大、深色模式和中文显示时，主按钮仍可点击。
2. 在“健康”看到“Mac 本地健康入口”说明，而非 HealthKit 授权按钮或健康数值；在“练什么”停止计时后，确认说明为“不会写入 Apple 健康”。
3. 在“我的”生成一次导出预览并取消保存；确认资料仍在。全量删除只在你明确点击后执行，并只清除当前 App 私有资料和关联私有照片。

当前环境没有完整 Xcode，因此以上 Mac 运行验收仍待实际完成；`swiftc` 类型检查和静态工程检查不等于启动成功。
