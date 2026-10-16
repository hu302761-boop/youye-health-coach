#!/bin/zsh
set -euo pipefail

# Static guard for the Android phone/tablet starter. It intentionally does not pretend that an
# APK was built: Android Studio, a JDK, Gradle and an Android SDK are still required for that.
root_dir="${0:A:h:h}"
cd "$root_dir"

android_root="AndroidApp"
app_gradle="$android_root/app/build.gradle.kts"
manifest="$android_root/app/src/main/AndroidManifest.xml"
entry="$android_root/app/src/main/java/com/youye/privatehealthcoach/MainActivity.kt"
health_contract="$android_root/app/src/main/java/com/youye/privatehealthcoach/HealthConnectContract.kt"
readme="$android_root/README.md"

for file in "$android_root/settings.gradle.kts" "$android_root/build.gradle.kts" "$app_gradle" "$manifest" "$entry" "$health_contract" "$readme"; do
  [[ -f "$file" ]] || { print -u2 "FAIL: missing Android starter file $file"; exit 1; }
done

rg -Fq 'Jetpack Compose' "$readme" || { print -u2 'FAIL: Android starter must identify its native Compose path'; exit 1; }
rg -q 'minSdk = 26' "$app_gradle" || { print -u2 'FAIL: Android minimum SDK needs an explicit supported baseline'; exit 1; }
rg -q 'targetSdk = 35' "$app_gradle" || { print -u2 'FAIL: Android target SDK needs an explicit current baseline'; exit 1; }
rg -q 'connect-client' "$app_gradle" || { print -u2 'FAIL: Android plan must reserve the official Health Connect client'; exit 1; }
rg -q 'HealthConnectAvailabilityChecker' "$health_contract" || { print -u2 'FAIL: Android health adapter needs an explicit availability path'; exit 1; }
rg -q 'AndroidConfirmedExercise' "$health_contract" || { print -u2 'FAIL: Android health adapter needs a user-confirmed exercise contract'; exit 1; }
rg -q 'ExerciseSessionRecord' "$health_contract" || { print -u2 'FAIL: Android exercise contract must restrict future writes to ExerciseSessionRecord'; exit 1; }
rg -q 'AndroidHealthPermissions' "$health_contract" || { print -u2 'FAIL: Android must map its minimal Health Connect permissions explicitly'; exit 1; }
rg -Fq 'getWritePermission(ExerciseSessionRecord::class)' "$health_contract" || { print -u2 'FAIL: Android must request only the exercise write permission'; exit 1; }
rg -q 'HealthConnectConsentGate' "$health_contract" || { print -u2 'FAIL: Android must check granted consent separately from provider availability'; exit 1; }
rg -q 'AndroidConfirmedExerciseWriteGate' "$health_contract" || { print -u2 'FAIL: Android exercise write requires an explicit pure preflight gate'; exit 1; }
rg -q 'userConfirmed' "$health_contract" || { print -u2 'FAIL: Android exercise write gate must require an explicit user confirmation'; exit 1; }
if rg -q 'android\.permission\.health\.' "$manifest"; then
  print -u2 'FAIL: Android starter must not declare Health Connect read/write permissions before its explicit consent and record paths are implemented'
  exit 1
fi
rg -q 'declares no Health Connect read or write permission' "$manifest" || { print -u2 'FAIL: Android manifest must explain its no-health-permission skeleton boundary'; exit 1; }
rg -q 'WindowWidthSizeClass' "$entry" || { print -u2 'FAIL: Android UI must adapt between phone and tablet widths'; exit 1; }
rg -q 'NavigationBar' "$entry" || { print -u2 'FAIL: compact Android UI needs a phone navigation bar'; exit 1; }
rg -q 'NavigationRail' "$entry" || { print -u2 'FAIL: expanded Android UI needs a tablet navigation rail'; exit 1; }
for label in 今天 吃什么 练什么 健康 我的; do
  rg -q "$label" "$entry" || { print -u2 "FAIL: Android native entry lacks $label destination"; exit 1; }
done
rg -q '不会补造健康数据' "$entry" || { print -u2 'FAIL: unavailable Android health data must not be fabricated'; exit 1; }
rg -q '本机 Health Connect 状态' "$entry" || { print -u2 'FAIL: Android health UI must expose the actual local provider state'; exit 1; }
rg -q 'HealthConnectAvailabilityChecker' "$entry" || { print -u2 'FAIL: Android health UI must consult the local availability checker'; exit 1; }
for connection_state in AVAILABLE PROVIDER_UPDATE_REQUIRED NOT_INSTALLED NOT_SUPPORTED; do
  rg -q "AndroidHealthConnectionState\.$connection_state" "$entry" || { print -u2 "FAIL: Android health UI must handle $connection_state"; exit 1; }
done
rg -q '不录像、不上传' "$entry" || { print -u2 'FAIL: Android pose boundary must forbid recording/upload'; exit 1; }
if rg -qi 'WebView|INTERNET|uses-permission.*CAMERA|firebase|analytics|okhttp|retrofit' "$manifest" "$entry"; then
  print -u2 'FAIL: Android starter must not ship a web wrapper, default network client, analytics, or unsolicited camera permission'
  exit 1
fi

print 'PASS: Android native starter structure and privacy boundaries are present. This is not an APK build.'
