#!/bin/zsh
set -euo pipefail

# 在完整 Xcode 安装后执行的只读/不签名构建预检。
# 它不会登录 Apple ID、修改 Team、安装 App 或上传任何资料；只验证工程可以被 Xcode 解析和编译。
root_dir="${0:A:h:h}"
cd "$root_dir"

developer_path="$(xcode-select -p 2>/dev/null || true)"
if [[ -z "$developer_path" || "$developer_path" == *"CommandLineTools" || ! -x "$developer_path/usr/bin/xcodebuild" ]]; then
  print -u2 "BLOCKED: 需要完整 Xcode；当前开发目录：${developer_path:-未设置}"
  print -u2 "下一步：安装并首次启动 Xcode，然后重跑 scripts/check_iphone_build_environment.sh。"
  exit 2
fi

project="YouyeHealthCoach.xcodeproj"
scheme="YouyeHealthCoachApp"
# Keep the unsigned preflight entirely separate from Xcode's normal DerivedData. Otherwise the
# `CODE_SIGNING_ALLOWED=NO` build can remove the provisioning profile and code signature from a
# freshly built device package before the next safe overwrite-install.
preflight_derived_data="$(mktemp -d /tmp/youye-health-coach-ios-preflight.XXXXXX)"
trap 'rm -rf "$preflight_derived_data"' EXIT

print "CHECK: Xcode"
xcodebuild -version

print "CHECK: shared scheme"
xcodebuild -list -project "$project"

print "CHECK: iPhone SDK"
xcodebuild -showsdks | rg -q 'iphoneos' || {
  print -u2 "BLOCKED: 完整 Xcode 中未发现 iPhoneOS SDK；请完成 Xcode 首次启动和组件安装。"
  exit 2
}

print "CHECK: unsigned generic iPhone build"
xcodebuild \
  -project "$project" \
  -scheme "$scheme" \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$preflight_derived_data" \
  CODE_SIGNING_ALLOWED=NO \
  build

print "PASS: Xcode 已能解析并无签名编译 iPhone target。"
print "NOTE: Watch target 暂不嵌入本轮 iPhone 构建；安装 watchOS 组件后单独验收并在发布前恢复嵌入。"
print "NEXT: 在 Xcode 选择 YouyeHealthCoachApp → Signing & Capabilities → Team，然后连接 iPhone 点击 Run。"
