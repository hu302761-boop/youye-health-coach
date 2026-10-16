#!/bin/zsh
set -euo pipefail

# 完整 Xcode 安装后执行的 watchOS 无签名构建预检。它不会登录 Apple ID、创建证书、
# 安装 App 或上传资料；只证明 Xcode 可解析 iPhone 内嵌的 Watch companion。
root_dir="${0:A:h:h}"
cd "$root_dir"

developer_path="$(xcode-select -p 2>/dev/null || true)"
if [[ -z "$developer_path" || "$developer_path" == *"CommandLineTools" || ! -x "$developer_path/usr/bin/xcodebuild" ]]; then
  print -u2 "BLOCKED: 需要完整 Xcode；当前开发目录：${developer_path:-未设置}"
  print -u2 "下一步：安装并首次启动 Xcode，然后重跑 scripts/check_iphone_build_environment.sh。"
  exit 2
fi

print "CHECK: watchOS SDK"
xcodebuild -showsdks | rg -q 'watchos' || {
  print -u2 "BLOCKED: 完整 Xcode 中未发现 watchOS SDK；请完成 Xcode 首次启动和组件安装。"
  exit 2
}

print "CHECK: unsigned paired iPhone + Watch build"
xcodebuild \
  -project YouyeHealthCoach.xcodeproj \
  -scheme YouyeHealthCoachApp \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO \
  build

print "PASS: Xcode 已能解析并无签名编译包含 Watch companion 的 iPhone target。"
print "NEXT: 在 Xcode 选择自己的 Team、连接配对 iPhone/Watch，再按 DEVICE_ACCEPTANCE.md 验收。"
