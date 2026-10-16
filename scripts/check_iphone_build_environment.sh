#!/bin/zsh
set -u

# 只检查本机是否具备“可以开始编译/签名/安装”的条件；不下载 Xcode、不修改签名、不连接或安装到设备。
has_blocker=0

developer_path="$(xcode-select -p 2>/dev/null || true)"
if [[ "$developer_path" == *"CommandLineTools" || -z "$developer_path" ]]; then
  print "BLOCKED: 未选中完整 Xcode；当前开发目录：${developer_path:-未设置}"
  has_blocker=1
elif [[ -x "$developer_path/usr/bin/xcodebuild" ]]; then
  print "READY: 已选中完整 Xcode：$developer_path"
  xcodebuild -version
else
  print "BLOCKED: 当前开发目录没有可用 xcodebuild：$developer_path"
  has_blocker=1
fi

if xcrun simctl list devices available >/dev/null 2>&1; then
    simulator_count="$(xcrun simctl list devices available | rg -c '^    iPhone' || true)"
    print "OPTIONAL: 可用 iPhone 模拟器条目：$simulator_count"
else
    # A simulator is useful for layout checks, but it is not a prerequisite for compiling or
    # running this app on a connected physical iPhone.  Treating it as a hard blocker would
    # incorrectly stop the owner's primary installation path.
    print "OPTIONAL: 模拟器运行时暂不可用；不影响连接 iPhone 的真机编译、签名和安装。"
fi

identity_output="$(security find-identity -v -p codesigning 2>/dev/null || true)"
if print -r -- "$identity_output" | rg -q '[1-9][0-9]* valid identities found'; then
  print "READY: 检测到可用代码签名身份。"
else
  print "ACTION NEEDED: 暂未检测到代码签名身份。请在 Xcode → Settings → Accounts 登录 Apple ID；连接真机调试可使用个人 Team。"
fi

if (( has_blocker )); then
  print "\n结果：尚不能编译、签名或安装 App。完成完整 Xcode 安装和首次启动后重新运行本脚本。"
  exit 2
fi

print "\n结果：编译环境就绪；仍需在 Xcode 中选择 Team、连接 iPhone 并完成 DEVICE_ACCEPTANCE.md。"
