# Android 手机/平板原生端（工程骨架）

这是 Kotlin + Jetpack Compose 的原生 Android 工程，不是网页包装。它先提供在 Health Connect、Samsung Health、华为 Health Kit、相机或网络均不可用时仍能使用的五个入口和“今天三件事”日卡层级。

## 已有与尚未完成

- 已有：手机底栏 / 平板导航栏自适应、五个一级入口、示例“今天”卡与无健康数据时的诚实手动状态说明；健康页只显示本机 Health Connect 的可用/需更新/未安装/不支持状态。Health Connect 最小权限、授权检查与“确认训练才能写入”目前仅是未执行的规则契约，Manifest 不声明健康读写权限。
- 计划接入：Health Connect 的最小聚合读取、用户确认后的 `ExerciseSessionRecord` 写入与去重；CameraX + MediaPipe 的本机逐帧提示；华为 Health Kit 的可选 adapter。
- 未实现：真实 Health Connect 授权与读写、Samsung/华为数据接入、相机/语音、照片保存、56 天资料和食谱卡的 Kotlin 数据层、打卡/替换/导出删除、本地持久化、安装包/真机验证。

## 构建前置

需要 Android Studio、JDK 17、Android SDK 35 和 Android 设备或模拟器。当前开发机未安装 JDK/Gradle/Android Studio，因此没有执行构建，也不能声称 APK 可安装。

在具备环境后，用 Android Studio 打开此 `AndroidApp` 文件夹，然后运行：

```bash
./gradlew :app:assembleDebug
```

首次构建需要从 Google/Maven 仓库下载 Gradle 与依赖；这不是本仓库自动执行的步骤。完成后，按项目根目录的 `CROSS_PLATFORM_ARCHITECTURE.md` 在 Samsung、华为 Android/EMUI、其他 Android 手机和平板分别做真机验收。
