#!/bin/zsh
set -euo pipefail

# This is deliberately unsigned: it checks the macOS app target without logging in,
# creating a certificate, installing software, or claiming a distributable app exists.
root_dir="${0:A:h:h}"
cd "$root_dir"

if ! xcode-select -p 2>/dev/null | rg -q '/Applications/Xcode\.app/Contents/Developer'; then
  print -u2 "BLOCKED: 需要完整 Xcode；当前开发目录：$(xcode-select -p 2>/dev/null || print '未设置')"
  print -u2 "下一步：安装并首次启动 Xcode，然后运行：zsh scripts/preflight_macos_build.sh"
  exit 2
fi

mac_arch="$(uname -m)"
case "$mac_arch" in
  arm64|x86_64) ;;
  *)
    print -u2 "BLOCKED: 未识别的 Mac 架构：$mac_arch"
    exit 2
    ;;
esac

# This preflight validates the native app for the Mac it runs on. Building both architectures in
# one Xcode invocation can make a local Swift package's first module artifact race the second
# architecture under current Xcode tooling. Intel remains a separate hardware verification item.
preflight_derived_data="$(mktemp -d /tmp/youye-health-coach-macos-preflight.XXXXXX)"
trap 'rm -rf "$preflight_derived_data"' EXIT
xcodebuild \
  -project YouyeHealthCoach.xcodeproj \
  -scheme YouyeHealthCoachMacApp \
  -configuration Debug \
  -destination "platform=macOS,arch=$mac_arch" \
  -derivedDataPath "$preflight_derived_data" \
  ARCHS="$mac_arch" \
  ONLY_ACTIVE_ARCH=YES \
  CODE_SIGNING_ALLOWED=NO \
  build

print "PASS: macOS target compiled unsigned for $mac_arch. This is not a signed or distributed Mac app."
