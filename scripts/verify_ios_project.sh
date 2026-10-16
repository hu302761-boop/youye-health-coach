#!/bin/zsh
set -euo pipefail

# 完整 Xcode/签名/真机之前的可重复静态验收；不把通过本脚本表述为已安装或已真机验证。
root_dir="${0:A:h:h}"
cd "$root_dir"

project="YouyeHealthCoach.xcodeproj/project.pbxproj"
plist="iOSApp/Info.plist"
entitlements="iOSApp/YouyeHealthCoach.entitlements"
scheme="YouyeHealthCoach.xcodeproj/xcshareddata/xcschemes/YouyeHealthCoachApp.xcscheme"
icon="iOSApp/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
pose_source="Sources/YouyeHealthCoach/LocalPoseCoach.swift"
follow_along_source="Sources/YouyeHealthCoach/BilibiliFollowAlong.swift"
health_source="Sources/YouyeHealthCoach/HealthKitIntegration.swift"
health_export_source="Sources/YouyeHealthCoach/AppleHealthExportImport.swift"
profile_async_ownership_source="Sources/YouyeHealthCoach/PrivateProfileAsyncOwnership.swift"
app_shell="Sources/YouyeHealthCoach/SwiftUIAppShell.swift"
ios_entry="iOSApp/YouyeHealthCoachApp.swift"
ios_assets="iOSApp/Assets.xcassets"
meal_composition_source="Sources/YouyeHealthCoach/MealCompositionEstimate.swift"
meal_quantity_note_source="Sources/YouyeHealthCoach/MealQuantityNote.swift"
budget_import_source="Sources/YouyeHealthCoach/QianJiBudgetImport.swift"
meal_prep_source="Sources/YouyeHealthCoach/MealPrepSession.swift"
weekly_review_source="Sources/YouyeHealthCoach/WeeklyReview.swift"
calendar_status_source="Sources/YouyeHealthCoach/CalendarDayStatus.swift"
personalization_source="Sources/YouyeHealthCoach/PersonalizationAdvisor.swift"
reminder_source="Sources/YouyeHealthCoach/LocalReminderCoordinator.swift"
today_next_step_source="Sources/YouyeHealthCoach/TodayNextStep.swift"
program_completion_source="Sources/YouyeHealthCoach/ProgramCompletionReview.swift"
nearby_offer_policy_source="Sources/YouyeHealthCoach/NearbyOfferPolicy.swift"
preflight_script="scripts/preflight_ios_build.sh"
watch_preflight_script="scripts/preflight_watchos_build.sh"
mac_preflight_script="scripts/preflight_macos_build.sh"
mac_entry="macOSApp/YouyeHealthCoachMacApp.swift"
mac_plist="macOSApp/Info.plist"
mac_scheme="YouyeHealthCoach.xcodeproj/xcshareddata/xcschemes/YouyeHealthCoachMacApp.xcscheme"
ios_privacy_manifest="iOSApp/PrivacyInfo.xcprivacy"
mac_privacy_manifest="macOSApp/PrivacyInfo.xcprivacy"
watch_entry="WatchApp/YouyeHealthCoachWatchApp.swift"
watch_plist="WatchApp/Info.plist"
watch_scheme="YouyeHealthCoach.xcodeproj/xcshareddata/xcschemes/YouyeHealthCoachWatchApp.xcscheme"
watch_icon="WatchApp/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
watch_privacy_manifest="WatchApp/PrivacyInfo.xcprivacy"
dependency_review="DEPENDENCY_REVIEW.md"

for file in "$project" "$plist" "$entitlements" "$scheme" "$icon" "$ios_entry" "$weekly_review_source" "$calendar_status_source" "$today_next_step_source" "$program_completion_source" "$nearby_offer_policy_source" "$preflight_script" "$watch_preflight_script"; do
  [[ -f "$file" ]] || { print -u2 "FAIL: missing $file"; exit 1; }
done
[[ -f "$profile_async_ownership_source" ]] || { print -u2 "FAIL: missing $profile_async_ownership_source"; exit 1; }
for file in "$mac_preflight_script" "$mac_entry" "$mac_plist" "$mac_scheme" "$ios_privacy_manifest" "$mac_privacy_manifest"; do
  [[ -f "$file" ]] || { print -u2 "FAIL: missing macOS companion file $file"; exit 1; }
done
for file in "$watch_entry" "$watch_plist" "$watch_scheme" "$watch_icon" "$watch_privacy_manifest"; do
  [[ -f "$file" ]] || { print -u2 "FAIL: missing Apple Watch companion file $file"; exit 1; }
done
[[ -f "$dependency_review" ]] || { print -u2 "FAIL: missing Apple dependency review $dependency_review"; exit 1; }
[[ -f "$pose_source" ]] || { print -u2 "FAIL: missing $pose_source"; exit 1; }
[[ -f "$follow_along_source" ]] || { print -u2 "FAIL: missing $follow_along_source"; exit 1; }
[[ -f "$health_source" ]] || { print -u2 "FAIL: missing $health_source"; exit 1; }
[[ -f "$health_export_source" ]] || { print -u2 "FAIL: missing $health_export_source"; exit 1; }
[[ -f "$app_shell" ]] || { print -u2 "FAIL: missing $app_shell"; exit 1; }
[[ -f "$meal_quantity_note_source" ]] || { print -u2 "FAIL: missing $meal_quantity_note_source"; exit 1; }
[[ -f "$personalization_source" ]] || { print -u2 "FAIL: missing $personalization_source"; exit 1; }
[[ -f "$reminder_source" ]] || { print -u2 "FAIL: missing $reminder_source"; exit 1; }
[[ -f "$today_next_step_source" ]] || { print -u2 "FAIL: missing $today_next_step_source"; exit 1; }

# A simulator helps later visual regression work, but cannot be a prerequisite for the actual
# wired-iPhone installation route. Keep that promise mechanically checked in the local guide.
rg -q 'OPTIONAL: 模拟器运行时暂不可用' scripts/check_iphone_build_environment.sh || { print -u2 'FAIL: iPhone environment check must label a missing simulator optional'; exit 1; }
if rg -A4 '模拟器运行时暂不可用' scripts/check_iphone_build_environment.sh | rg -q 'has_blocker=1'; then
  print -u2 'FAIL: missing simulator runtime must not block a physical iPhone installation'
  exit 1
fi
rg -q '模拟器.*不是连接 iPhone 真机安装的前置条件' INSTALL_ON_IPHONE.md || { print -u2 'FAIL: iPhone installation guide must state that simulator availability is optional'; exit 1; }

plutil -lint "$plist" >/dev/null
plutil -lint "$entitlements" >/dev/null
plutil -lint "$ios_privacy_manifest" >/dev/null
plutil -lint "$mac_privacy_manifest" >/dev/null
for manifest in "$ios_privacy_manifest" "$mac_privacy_manifest"; do
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :NSPrivacyTracking' "$manifest")" == "false" ]] || { print -u2 'FAIL: privacy manifest must declare no tracking'; exit 1; }
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :NSPrivacyCollectedDataTypes' "$manifest" | tr -d '[:space:]')" == "Array{}" ]] || { print -u2 'FAIL: privacy manifest must not claim collected data for this local-only MVP'; exit 1; }
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :NSPrivacyAccessedAPITypes:0:NSPrivacyAccessedAPIType' "$manifest")" == "NSPrivacyAccessedAPICategoryUserDefaults" ]] || { print -u2 'FAIL: privacy manifest must disclose local UserDefaults use'; exit 1; }
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :NSPrivacyAccessedAPITypes:0:NSPrivacyAccessedAPITypeReasons:0' "$manifest")" == "CA92.1" ]] || { print -u2 'FAIL: privacy manifest must use the app-local UserDefaults reason'; exit 1; }
done
[[ "$(/usr/libexec/PlistBuddy -c 'Print :NSHealthShareUsageDescription' "$plist")" == *"读取"* && "$(/usr/libexec/PlistBuddy -c 'Print :NSHealthShareUsageDescription' "$plist")" == *"正式计划日"* ]] || { print -u2 'FAIL: Health read usage text must state its formal-plan boundary'; exit 1; }
[[ "$(/usr/libexec/PlistBuddy -c 'Print :NSPhotoLibraryUsageDescription' "$plist")" == *"本机"* && "$(/usr/libexec/PlistBuddy -c 'Print :NSPhotoLibraryUsageDescription' "$plist")" == *"食材"* ]] || { print -u2 'FAIL: photo privacy text must cover local meal and ingredient confirmation'; exit 1; }
[[ "$(/usr/libexec/PlistBuddy -c 'Print :NSCameraUsageDescription' "$plist")" == *"不录像"* ]] || { print -u2 'FAIL: missing local-only camera privacy text'; exit 1; }
# System authorization calls must remain at an intentional owner action.  A future refactor
# that moves them to app launch/onAppear would turn optional health, camera or reminder features
# into unsolicited prompts, even though their plist strings still look correct.
rg -A8 'private func requestAndLoad' "$app_shell" | rg -Fq 'guard !isWorking else { return }' || { print -u2 'FAIL: HealthKit read authorization must stay behind the explicit working-state action gate'; exit 1; }
rg -A14 'public func start()' "$pose_source" | rg -Fq 'guard !isRunning, !isStarting, startGate.begin() else { return }' || { print -u2 'FAIL: camera authorization must stay behind a single explicit live-pose start action'; exit 1; }
rg -A35 'public func start()' "$pose_source" | rg -Fq 'UIDevice.current.userInterfaceIdiom == .phone' || { print -u2 'FAIL: camera authorization path must reject iPad before asking for access'; exit 1; }
rg -A45 'public func start()' "$pose_source" | rg -Fq 'AVCaptureDevice.requestAccess' || { print -u2 'FAIL: live-pose start action must own the camera permission request'; exit 1; }
rg -Fq 'defer { self.session.commitConfiguration() }' "$pose_source" || { print -u2 'FAIL: camera setup must commit configuration on every setup path'; exit 1; }
commit_line="$(rg -n -F 'defer { self.session.commitConfiguration() }' "$pose_source" | head -1 | cut -d: -f1)"
start_line="$(rg -n -F 'self.session.startRunning()' "$pose_source" | head -1 | cut -d: -f1)"
[[ -n "$commit_line" && -n "$start_line" && "$commit_line" -lt "$start_line" ]] || { print -u2 'FAIL: AVCaptureSession configuration must commit before startRunning'; exit 1; }
rg -Fq '未取得相机权限；仍可按最低版训练。可在系统设置中改权限。' "$pose_source" || { print -u2 'FAIL: denied camera access must expose a manual minimum-training fallback'; exit 1; }
# Keep system access declarations deliberately narrow. PhotosPicker uses the owner-selected
# picker and does not need broad photo-library add access; notifications are requested only from
# the explicit reminder button, so neither permission should silently grow at plist level.
for unexpected_usage_key in NSPhotoLibraryAddUsageDescription NSLocationAlwaysAndWhenInUseUsageDescription NSMicrophoneUsageDescription NSMotionUsageDescription NSSpeechRecognitionUsageDescription; do
  if /usr/libexec/PlistBuddy -c "Print :$unexpected_usage_key" "$plist" >/dev/null 2>&1; then
    print -u2 "FAIL: local-only MVP must not declare unused permission $unexpected_usage_key"
    exit 1
  fi
done
[[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.developer.healthkit' "$entitlements")" == "true" ]] || { print -u2 'FAIL: HealthKit entitlement is missing'; exit 1; }
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist")" == '$(PRODUCT_BUNDLE_IDENTIFIER)' ]] || { print -u2 'FAIL: iOS Info.plist must resolve its bundle identifier from build settings'; exit 1; }
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")" == '$(MARKETING_VERSION)' ]] || { print -u2 'FAIL: iOS Info.plist must resolve its marketing version from build settings'; exit 1; }

rg -q 'IPHONEOS_DEPLOYMENT_TARGET = 17\.0;' "$project" || { print -u2 'FAIL: iOS 17 deployment target missing'; exit 1; }
rg -q 'TARGETED_DEVICE_FAMILY = "1,2";' "$project" || { print -u2 'FAIL: universal iPhone/iPad device family missing'; exit 1; }
rg -q 'MACOSX_DEPLOYMENT_TARGET = 14\.0;' "$project" || { print -u2 'FAIL: macOS 14 deployment target missing'; exit 1; }
rg -q 'WATCHOS_DEPLOYMENT_TARGET = 10\.0;' "$project" || { print -u2 'FAIL: watchOS 10 deployment target missing'; exit 1; }
[[ "$(rg -c 'MARKETING_VERSION = 0\.1\.0;' "$project")" -eq 6 ]] || { print -u2 'FAIL: iPhone/iPad, Mac and Watch Debug/Release targets must share the marketing version'; exit 1; }
[[ "$(rg -c 'CURRENT_PROJECT_VERSION = 1;' "$project")" -eq 6 ]] || { print -u2 'FAIL: iPhone/iPad, Mac and Watch Debug/Release targets must share the build number'; exit 1; }
[[ "$(rg -c 'PRODUCT_BUNDLE_IDENTIFIER = com\.youye\.privatehealthcoach;' "$project")" -eq 2 ]] || { print -u2 'FAIL: iPhone/iPad bundle identifier must be stable across Debug and Release'; exit 1; }
[[ "$(rg -c 'PRODUCT_BUNDLE_IDENTIFIER = com\.youye\.privatehealthcoach\.mac;' "$project")" -eq 2 ]] || { print -u2 'FAIL: Mac bundle identifier must be stable across Debug and Release'; exit 1; }
[[ "$(rg -c 'PRODUCT_BUNDLE_IDENTIFIER = com\.youye\.privatehealthcoach\.watchkitapp;' "$project")" -eq 2 ]] || { print -u2 'FAIL: Watch bundle identifier must be stable across Debug and Release'; exit 1; }
[[ "$(rg -c 'WK_COMPANION_APP_BUNDLE_IDENTIFIER = com\.youye\.privatehealthcoach;' "$project")" -eq 2 ]] || { print -u2 'FAIL: Watch companion identifier must match the iPhone/iPad app identifier'; exit 1; }
if rg -q 'Embed Watch Content' "$project"; then
  print -u2 'FAIL: iPhone-first build must remain independent of the currently unavailable watchOS platform component'
  exit 1
fi
swift package dump-package >/dev/null || { print -u2 'FAIL: local Swift package manifest cannot be resolved'; exit 1; }
rg -q 'XCLocalSwiftPackageReference "YouyeHealthCoach"' "$project" || { print -u2 'FAIL: Xcode project must retain the local shared Swift package reference'; exit 1; }
[[ "$(rg -c 'YouyeHealthCoach in Frameworks' "$project")" -eq 4 ]] || { print -u2 'FAIL: both iPhone/iPad and Mac targets must link the shared coach module'; exit 1; }
[[ "$(rg -F -c 'packageProductDependencies = (A10000000000000000000021 /* YouyeHealthCoach */,);' "$project")" -eq 1 && "$(rg -F -c 'packageProductDependencies = (B20000000000000000000021 /* YouyeHealthCoach */,);' "$project")" -eq 1 ]] || { print -u2 'FAIL: both iPhone/iPad and Mac targets must retain the shared package product dependency'; exit 1; }
[[ "$(rg -c 'ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;' "$project")" -ge 2 ]] || { print -u2 'FAIL: both iOS build configurations must select the AppIcon catalog'; exit 1; }
[[ "$(rg -c 'CODE_SIGN_ENTITLEMENTS = iOSApp/YouyeHealthCoach\.entitlements;' "$project")" -ge 2 ]] || { print -u2 'FAIL: both iOS Debug and Release must reference HealthKit entitlements'; exit 1; }
rg -q 'PrivacyInfo\.xcprivacy in Resources' "$project" || { print -u2 'FAIL: privacy manifests must be included in Apple app resources'; exit 1; }
rg -q 'com\.apple\.HealthKit = \{ enabled = 1; \};' "$project" || { print -u2 'FAIL: Xcode HealthKit capability missing'; exit 1; }
rg -q 'YouyeHealthCoachApp' "$scheme" || { print -u2 'FAIL: shared app scheme missing target'; exit 1; }
rg -q 'BlueprintIdentifier="A10000000000000000000050"' "$scheme" || { print -u2 'FAIL: shared iPhone/iPad scheme must point to the iPhone/iPad app target'; exit 1; }
rg -q 'BuildableName="YouyeHealthCoachApp.app"' "$scheme" || { print -u2 'FAIL: shared iPhone/iPad scheme must launch the iPhone/iPad app product'; exit 1; }
rg -q 'allowLocationSimulation="NO"' "$scheme" || { print -u2 'FAIL: iPhone scheme must not enable unused location simulation'; exit 1; }
if rg -q '8 月 7 日.*启动准备日\|8 月 8 日.*第 1 天' INSTALL_ON_IPHONE.md; then
  print -u2 'FAIL: iPhone installation guide must describe the date-driven preparation/start boundary rather than stale fixed calendar dates'
  exit 1
fi
if rg -q '8 月 8 日才开始第 1 天\|8 月 8 日开始第 1 天' "$app_shell"; then
  print -u2 'FAIL: preparation empty states must render the configured local start date instead of a stale fixed calendar date'
  exit 1
fi
rg -q 'CODE_SIGNING_ALLOWED=NO' "$preflight_script" || { print -u2 'FAIL: installation preflight must be non-signing'; exit 1; }
rg -q "generic/platform=iOS" "$preflight_script" || { print -u2 'FAIL: installation preflight must target generic iPhoneOS'; exit 1; }
rg -q 'mktemp -d /tmp/youye-health-coach-ios-preflight' "$preflight_script" || { print -u2 'FAIL: unsigned iPhone preflight must isolate its DerivedData from signed device builds'; exit 1; }
rg -q -- '-derivedDataPath "\$preflight_derived_data"' "$preflight_script" || { print -u2 'FAIL: unsigned iPhone preflight must use its isolated DerivedData directory'; exit 1; }
rg -q 'watchos' "$watch_preflight_script" || { print -u2 'FAIL: Watch preflight must require the watchOS SDK'; exit 1; }
rg -q 'CODE_SIGNING_ALLOWED=NO' "$watch_preflight_script" || { print -u2 'FAIL: Watch preflight must be non-signing'; exit 1; }
rg -q 'YouyeHealthCoachMacApp' "$project" || { print -u2 'FAIL: macOS app target missing'; exit 1; }
rg -q 'BlueprintIdentifier="B20000000000000000000050"' "$mac_scheme" || { print -u2 'FAIL: macOS shared scheme must point to the macOS app target'; exit 1; }
rg -q 'BuildableName="YouyeHealthCoachMacApp.app"' "$mac_scheme" || { print -u2 'FAIL: macOS shared scheme must launch the macOS app product'; exit 1; }
rg -q 'MACOSX_DEPLOYMENT_TARGET = 14\.0;' "$project" || { print -u2 'FAIL: macOS 14 deployment target missing'; exit 1; }
[[ -f macOSApp/YouyeHealthCoachMacApp.entitlements ]] || { print -u2 'FAIL: macOS app sandbox entitlements are missing'; exit 1; }
[[ "$(rg -c 'CODE_SIGN_ENTITLEMENTS = macOSApp/YouyeHealthCoachMacApp\.entitlements;' "$project")" -ge 2 ]] || { print -u2 'FAIL: both macOS build configurations must use sandbox entitlements'; exit 1; }
rg -q 'com\.apple\.security\.app-sandbox' macOSApp/YouyeHealthCoachMacApp.entitlements || { print -u2 'FAIL: macOS app must enable App Sandbox'; exit 1; }
rg -q 'com\.apple\.security\.files\.user-selected\.read-write' macOSApp/YouyeHealthCoachMacApp.entitlements || { print -u2 'FAIL: macOS export must use explicit user-selected file access'; exit 1; }
rg -Fq 'B20000000000000000000003 /* PrivacyInfo.xcprivacy in Resources */' "$project" || { print -u2 'FAIL: macOS privacy manifest must be included in the macOS target resources'; exit 1; }
rg -q 'NavigationSplitView' "$app_shell" || { print -u2 'FAIL: macOS companion must use a desktop navigation split view'; exit 1; }
rg -q 'Mac 本地版' "$app_shell" || { print -u2 'FAIL: macOS companion must identify its local-only capability boundary'; exit 1; }
rg -q 'UIDevice\.current\.userInterfaceIdiom == \.pad' "$app_shell" || { print -u2 'FAIL: iPad shell selection must use device idiom so large iPhones do not unexpectedly switch to a sidebar'; exit 1; }
rg -q 'TabView' "$app_shell" || { print -u2 'FAIL: iPhone primary experience must remain a native bottom TabView'; exit 1; }
for tab_label in 'Label("今天"' 'Label("跟练"' 'Label("备餐"' 'Label("健康"' 'Label("我的"'; do
  rg -Fq "$tab_label" "$app_shell" || { print -u2 "FAIL: iPhone primary TabView is missing required tab $tab_label"; exit 1; }
done
compact_tabs="$(sed -n '/private struct CompactCoachTabs/,/^}/p' "$app_shell")"
[[ "$compact_tabs" == *'TodayView('*'Label("今天"'*'TrainingHomeView'*'Label("跟练"'*'FoodHomeView'*'Label("备餐"'*'HealthHomeView'*'Label("健康"'*'MyView('*'Label("我的"'* ]] || { print -u2 'FAIL: iPhone navigation must expose today, training, prep, health, and profile as primary destinations'; exit 1; }
desktop_shell="$(sed -n '/private struct DesktopCoachShell/,/^#endif/p' "$app_shell")"
[[ "$desktop_shell" == *'selection: DesktopDestination? = .today'* && "$desktop_shell" == *'case training, today, food, health, profile'* && "$desktop_shell" == *'case .training: "跟练"'* && "$desktop_shell" == *'case .food: "备餐"'* && "$desktop_shell" == *'switch selection ?? .today'* ]] || { print -u2 'FAIL: macOS sidebar must open on the daily decision card and keep training and meal prep as first-class destinations'; exit 1; }
tablet_shell="$(sed -n '/private struct TabletCoachShell/,/^#endif/p' "$app_shell")"
[[ "$tablet_shell" == *'selection: TabletDestination? = .today'* && "$tablet_shell" == *'case training, today, food, health, profile'* && "$tablet_shell" == *'case .training: "跟练"'* && "$tablet_shell" == *'case .food: "备餐"'* && "$tablet_shell" == *'switch selection ?? .today'* ]] || { print -u2 'FAIL: iPad sidebar must open on the daily decision card and keep training and meal prep as first-class destinations'; exit 1; }
training_home="$(sed -n '/private struct TrainingHomeView/,/^private struct PendingWorkoutDraftSection/p' "$app_shell")"
[[ "$training_home" == *'TrainingHeroCard('*'"开始跟练"'* ]] || { print -u2 'FAIL: training home must render a single prominent follow-along hero action'; exit 1; }
[[ "$training_home" == *'只记录真实开始到停止的时长。'* ]] || { print -u2 'FAIL: training hero must retain the honest real-timing boundary'; exit 1; }
[[ "$training_home" == *'context: trainingHeroContext'* && "$training_home" == *'private var trainingHeroContext'* ]] || { print -u2 'FAIL: training hero must show the owner schedule and goal before its primary action'; exit 1; }
[[ "$training_home" == *'Section("计划设置")'* && "$training_home" == *'Label("调整目标与体重", systemImage: "scope")'* && "$training_home" == *'GoalSettingsView('* && "$training_home" == *'Label("调整训练时间", systemImage: "clock")'* && "$training_home" == *'RoutineSettingsView('* ]] || { print -u2 'FAIL: training home must expose direct goal/weight and training-time adjustments rather than hiding them in the calendar'; exit 1; }
rg -Fq 'HealthStatusHistoryAggregation.dailyAggregates(from: entries)' "$app_shell" || { print -u2 'FAIL: flexible training recommendation must use the day safety aggregate, not only the latest status'; exit 1; }
rg -Fq 'Text("建议 \(option.durationText) · 以舒服呼吸和动作质量为准")' "$app_shell" || { print -u2 'FAIL: flexible session must render its duration instead of a literal placeholder'; exit 1; }
rg -Fq '已达建议上限 20 分钟' "$app_shell" || { print -u2 'FAIL: flexible session must disclose the 20-minute suggested upper limit'; exit 1; }
rg -Fq 'private struct TrainingHeroCard' "$app_shell" || { print -u2 'FAIL: training home must use the dedicated hero card rather than a settings-style row'; exit 1; }
# The default sea-glass theme must retain the original deep-sea teal brand token.  The
# selected action colour is intentionally dynamic so the owner can choose one of the
# local visual themes without changing plan or health semantics.
rg -Fq 'case .seaGlass: Color(red: 0.043, green: 0.431, blue: 0.384)' Sources/YouyeHealthCoach/AppTheme.swift || { print -u2 'FAIL: sea-glass theme must retain the deep-sea teal brand token'; exit 1; }
rg -Fq 'static var action: Color' "$app_shell" || { print -u2 'FAIL: shared UI must expose a dynamic theme action colour'; exit 1; }
rg -Fq 'Color("AccentColor")' "$ios_entry" || { print -u2 'FAIL: iOS root tint must use the adaptive AccentColor asset'; exit 1; }
rg -Fq '"value" : "dark"' "$ios_assets/AccentColor.colorset/Contents.json" || { print -u2 'FAIL: AccentColor must provide a dark appearance variant'; exit 1; }
rg -q 'private struct TodayView' "$app_shell" || { print -u2 'FAIL: iPhone app must retain a dedicated compact today daily-card view'; exit 1; }
rg -Fq 'Label("健康详情与趋势", systemImage: "chart.line.uptrend.xyaxis")' "$app_shell" || { print -u2 'FAIL: health detail must remain available from Today and the primary tab bar'; exit 1; }
rg -Fq 'Label("上传训练截图并补录", systemImage: "photo.on.rectangle")' "$app_shell" || { print -u2 'FAIL: health screen must retain an explicit screenshot workout import entry'; exit 1; }
rg -Fq '正在同步 Apple 健康' "$app_shell" && rg -Fq 'requestAndLoad(requestAuthorization: true)' "$app_shell" || { print -u2 'FAIL: health screen must retain an explicit Apple Health sync action'; exit 1; }
rg -Fq 'public var importedWorkoutRecords: [ImportedWorkoutRecord]' Sources/YouyeHealthCoach/Privacy.swift || { print -u2 'FAIL: owner-local confirmed workout records must remain persistable'; exit 1; }
rg -Fq 'public var recentWorkouts: [HealthWorkoutSummary]' Sources/YouyeHealthCoach/HealthKitIntegration.swift || { print -u2 'FAIL: transient recent Apple Health workouts must remain available for review'; exit 1; }
rg -Fq 'HealthWorkoutImportPolicy.eligible' "$app_shell" || { print -u2 'FAIL: health screen must filter Apple Health workouts through the shared minimum-duration and de-duplication policy'; exit 1; }
rg -Fq '一键采用 ' "$app_shell" && rg -Fq 'showingWorkoutBatchConfirmation' "$app_shell" || { print -u2 'FAIL: health screen must provide a single confirmation action for all eligible Apple Health workouts'; exit 1; }
rg -Fq 'belowMinimumCount' "$app_shell" || { print -u2 'FAIL: health screen must explain why workouts below the minimum duration are not in automatic progress'; exit 1; }
rg -Fq 'public enum HealthWorkoutImportPolicy' Sources/YouyeHealthCoach/HealthKitIntegration.swift || { print -u2 'FAIL: Apple Health workout import policy must be centralized and testable'; exit 1; }
rg -Fq '健康 → 共享 → App → YouyeHealthCoach' "$app_shell" || { print -u2 'FAIL: missing Apple Health workout permission recovery guidance'; exit 1; }
rg -Fq 'HealthSyncHeroCard(' "$app_shell" || { print -u2 'FAIL: Apple Health sync must be promoted into the unified hero card'; exit 1; }
rg -Fq '.tint(AppTheme(rawValue: selectedTheme)?.tint ?? CoachPalette.action)' "$app_shell" || { print -u2 'FAIL: primary iPhone tabs must follow the selected app theme'; exit 1; }
rg -Fq 'private var pendingWorkoutCandidates' "$app_shell" || { print -u2 'FAIL: adopted Apple Health workouts must be separated from pending candidates'; exit 1; }
if rg -Fq '一键采用 (eligibleWorkouts.count)' "$app_shell" \
  || rg -Fq '已发现 (eligibleWorkouts.count)' "$app_shell" \
  || rg -Fq '确认采用 (pendingEligibleWorkouts.count)' "$app_shell" \
  || rg -Fq '有 (belowMinimumCount)' "$app_shell" \
  || rg -Fq '已记录 (workout.kind.displayName)' "$app_shell"; then
  print -u2 'FAIL: workout import UI must render live values instead of literal interpolation tokens'
  exit 1
fi
rg -Fq '.disabled(location.status == .locating)' "$app_shell" || { print -u2 'FAIL: nearby map entries must be disabled while location refresh is in progress'; exit 1; }
rg -Fq '定位完成前不会使用旧地点' "$app_shell" || { print -u2 'FAIL: nearby screen must disclose stale-location guard'; exit 1; }
rg -Fq '查看下一餐餐卡' "$app_shell" || { print -u2 'FAIL: Today must keep the next meal card reachable as an on-demand supporting flow'; exit 1; }
rg -Fq 'Label("查看下一餐餐卡", systemImage: "fork.knife")' "$app_shell" || { print -u2 'FAIL: Today must clearly name the read-only next-meal card entry'; exit 1; }
rg -Fq 'FoodHomeView(' "$app_shell" || { print -u2 'FAIL: the full meal-prep home must remain available as a primary destination'; exit 1; }
if rg -q 'TodayQuickLogGrid\|QuickLogTileLabel' "$app_shell"; then
  print -u2 'FAIL: Today must not restore five peer quick-log tiles that obscure the primary action'
  exit 1
fi
global_quick_log_menu="$(sed -n '/private struct GlobalQuickLogMenu/,/private struct TodayNextMealLogActions/p' "$app_shell")"
[[ "$global_quick_log_menu" == *'Image(systemName: "plus.circle")'* ]] || { print -u2 'FAIL: toolbar quick logging must use a distinct add affordance'; exit 1; }
[[ "$global_quick_log_menu" == *'accessibilityLabel("快速记录")'* ]] || { print -u2 'FAIL: toolbar quick logging must expose a clear accessibility label'; exit 1; }
[[ "$global_quick_log_menu" != *'onRecordMeal'* && "$global_quick_log_menu" != *'onPhotoMeal'* ]] || { print -u2 'FAIL: toolbar must not duplicate Today next-meal primary actions'; exit 1; }
rg -Fq 'photoSectionIsActive ? "本机照片" : "拍照或相册（可选）"' "$app_shell" || { print -u2 'FAIL: a manually opened meal form must keep optional photo controls compact'; exit 1; }
rg -Fq 'get: { photoSectionIsActive || showsPhotoOptions }' "$app_shell" || { print -u2 'FAIL: active photo evidence must expand itself rather than become hidden behind the compact control'; exit 1; }
[[ "$(rg -F -c 'photoSectionIsActive ? "本机照片" : "拍照或相册（可选）"' "$app_shell")" -eq 2 ]] || { print -u2 'FAIL: both planned and extra-meal forms must keep idle photo controls compact'; exit 1; }
rg -Fq 'if !usesPhotoFastDefaults {' "$app_shell" || { print -u2 'FAIL: a confirmed photo candidate must expose only one clear save action'; exit 1; }
rg -Fq '"份量、油或甜饮（可选）"' "$app_shell" || { print -u2 'FAIL: text-only extra meals must keep optional portion corrections compact'; exit 1; }
rg -Fq 'get: { composition.hasAnyOwnerSelection || showsTextMealPortionOptions }' "$app_shell" || { print -u2 'FAIL: saved extra-meal portion confirmations must remain visible when reopening the form'; exit 1; }
rg -Fq 'Section("估算范围")' "$app_shell" || { print -u2 'FAIL: extra-meal energy must be presented as an estimate range, not a precise result'; exit 1; }
rg -Fq 'if hasFoodDescription {' "$app_shell" || { print -u2 'FAIL: extra-meal estimates must wait until there is a usable food description'; exit 1; }
rg -Fq 'Section("按计划吃了")' "$app_shell" || { print -u2 'FAIL: the ordinary planned-meal path must present one compact confirmation card'; exit 1; }
rg -Fq 'DisclosureGroup("改数量或食物（可选）")' "$app_shell" || { print -u2 'FAIL: planned-meal corrections must remain available without crowding the default path'; exit 1; }
rg -Fq '项记录 · 估算范围' "$app_shell" || { print -u2 'FAIL: optional meal estimate detail must name both its record count and estimate-range boundary'; exit 1; }
rg -Fq 'value: summary.recordedRange.map(rangeValue) ?? "—"' "$app_shell" || { print -u2 'FAIL: Today calorie card must foreground the full recorded range rather than a midpoint'; exit 1; }
rg -Fq 'Text("进度按估算上限")' "$app_shell" || { print -u2 'FAIL: Today calorie progress must disclose its conservative upper-bound rendering'; exit 1; }
rg -Fq 'Label("来自 \(summary.recordedEntries.count) 项本机记录", systemImage: "list.bullet")' "$app_shell" || { print -u2 'FAIL: calorie card must visibly name the count of local records behind a daily total'; exit 1; }
rg -Fq '范围是估算，不是称重。' "$app_shell" || { print -u2 'FAIL: calorie source rows must retain the estimate-not-weighing boundary'; exit 1; }
rg -q 'public let recordedEntries: \[DailyCalorieRecordedEntry\]' "Sources/YouyeHealthCoach/DailyCalorieIntake.swift" || { print -u2 'FAIL: daily calorie summary must retain traceable source entries'; exit 1; }
rg -A55 'public static func recommend' "Sources/YouyeHealthCoach/TodayNextStep.swift" | rg -q 'if trainingPending' || { print -u2 'FAIL: the Today recommendation must prioritise unfinished training before meal selection'; exit 1; }
! rg -q 'let foodCompleted = completion\?\.foodCompleted' "Sources/YouyeHealthCoach/TodayNextStep.swift" || { print -u2 'FAIL: retired meal logging must not gate Today completion'; exit 1; }
! rg -q 'private static func mealStep' "Sources/YouyeHealthCoach/TodayNextStep.swift" || { print -u2 'FAIL: meal cards must not be returned as the Today primary action after meal tracking is retired'; exit 1; }
today_view="$(sed -n '/private struct TodayView/,/^private struct /p' "$app_shell")"
[[ "$today_view" == *'TodayFocusCard(focus: todayFocus)'* ]] || { print -u2 'FAIL: Today must keep one prominent training/recovery action at the top'; exit 1; }
[[ "$today_view" == *'private var trainingNeedsAttention'*'TrainingCardDetail'* ]] || { print -u2 'FAIL: Today must route unfinished normal training to the training detail before food'; exit 1; }
[[ "$today_view" == *'context: todayTrainingContext'* && "$today_view" == *'private var todayTrainingContext'* ]] || { print -u2 'FAIL: Today follow-along focus must identify schedule and goal instead of repeating a generic video prompt'; exit 1; }
[[ "$today_view" == *'Section("需要调整时")'* && "$today_view" == *'主任务仍是上方今日跟练'* ]] || { print -u2 'FAIL: flexible training must be a clearly secondary adjustment path below the canonical Today training action'; exit 1; }
[[ "$today_view" == *'查看下一餐餐卡'* && "$today_view" == *'MealCardView('* ]] || { print -u2 'FAIL: Today next-meal action must open the meal card directly instead of nesting the full prep home'; exit 1; }
[[ "$today_view" != *'showingFood'* && "$today_view" != *'.sheet(isPresented: $showingFood)'* ]] || { print -u2 'FAIL: Today must not retain a duplicate sheet-based prep-home route'; exit 1; }
[[ "$today_view" != *'DailyCalorieOverviewCard('* ]] || { print -u2 'FAIL: Today must not show an unexplained calorie total beside the training flow'; exit 1; }
food_home="$(sed -n '/private struct FoodHomeView/,/^private struct /p' "$app_shell")"
[[ "$food_home" != *'餐食记录与估算'* && "$food_home" != *'ActualMealLogForm('* && "$food_home" != *'UnplannedMealForm('* ]] || { print -u2 'FAIL: meal-prep home must expose suggestions only, without meal logging or calorie history'; exit 1; }
[[ "$food_home" == *'FoodNextMealCard('* && "$food_home" == *'FoodTodayMenuView('* && "$food_home" != *'Section("今天三餐")'* ]] || { print -u2 'FAIL: meal-prep home must prioritize one next-meal card and defer the full day menu'; exit 1; }
rg -q 'private struct FoodTodayMenuView' "$app_shell" || { print -u2 'FAIL: the full daily meal menu must remain available behind its compact entry'; exit 1; }
rg -Fq 'log.historyEstimateLabel' "$app_shell" || { print -u2 'FAIL: historical extra-meal rows must retain their estimate source instead of showing a bare calorie range'; exit 1; }
! rg -Fq 'let midpoint = Int((Double(range.lowerBound + range.upperBound) / 10).rounded()) * 5' "$app_shell" || { print -u2 'FAIL: compact extra-meal rows must not replace uncertain calorie ranges with midpoint-looking values'; exit 1; }
rg -Fq 'Section("今日状态")' "$app_shell" || { print -u2 'FAIL: current Today view must expose same-day health actions, not only a status summary'; exit 1; }
rg -Fq 'Section("目标与时间")' "$app_shell" || { print -u2 'FAIL: current Today view must expose direct goal and routine controls'; exit 1; }
rg -q 'private struct PlanEffectSummary' "$app_shell" || { print -u2 'FAIL: goal and routine settings must share an explicit effect-scope summary'; exit 1; }
rg -Fq 'title: "目标保存后"' "$app_shell" || { print -u2 'FAIL: goal settings must disclose what updates immediately'; exit 1; }
rg -Fq 'title: "时间保存后"' "$app_shell" || { print -u2 'FAIL: routine settings must disclose what updates immediately'; exit 1; }
rg -Fq 'kind: .routineSchedule' "$app_shell" || { print -u2 'FAIL: confirmed routine changes must be retained in the local plan-change audit'; exit 1; }
rg -Fq 'kind: .goal' "$app_shell" || { print -u2 'FAIL: confirmed goal, target-weight, or sustainable-goal changes must be retained in the local plan-change audit'; exit 1; }
rg -Fq 'HealthStatusHistoryAggregation.dailyAggregates(from: entries)' "$app_shell" || { print -u2 'FAIL: flexible training recommendation must use the day safety aggregate, not only the latest status'; exit 1; }
rg -Fq 'DailyGuidance.initiallyVisible(guidance)' "$app_shell" || { print -u2 'FAIL: Today health actions must start compactly from the shared guidance policy'; exit 1; }
rg -Fq '查看另外 \(guidance.count - visibleGuidance.count) 条建议' "$app_shell" || { print -u2 'FAIL: Today health actions must keep additional guidance owner-accessible'; exit 1; }
rg -q 'private struct DailyPlanCardView' "$app_shell" || { print -u2 'FAIL: calendar must retain a single-day detail destination rather than a long plan page'; exit 1; }
rg -q '8 周训练日历' "$app_shell" || { print -u2 'FAIL: training flow must retain its 8-week calendar entry'; exit 1; }
training_library="$(sed -n '/private struct TrainingLibraryView/,/^private struct /p' "$app_shell")"
[[ "$training_library" == *'Button("调整训练时间", systemImage: "clock")'* && "$training_library" == *'Button("调整目标", systemImage: "scope")'* && "$training_library" == *'RoutineSettingsView('* && "$training_library" == *'GoalSettingsView('* ]] || { print -u2 'FAIL: training calendar must expose direct, owner-confirmed time and goal adjustments'; exit 1; }
daily_plan_card="$(sed -n '/private struct DailyPlanCardView/,/^private struct /p' "$app_shell")"
[[ "$daily_plan_card" != *'TodayFeature.mealActions(plan: scheduledPlan'* && "$daily_plan_card" != *'UnplannedMealForm('* && "$daily_plan_card" != *'ActualMealLogService.log('* ]] || { print -u2 'FAIL: calendar day cards must not restore meal logging, calorie estimates, or historical meal rows after meal tracking is retired'; exit 1; }
rg -q '8 周饮食日历' "$app_shell" || { print -u2 'FAIL: food flow must retain its 8-week calendar entry'; exit 1; }
for forbidden_mac_framework in HealthKit AVFoundation Vision CoreLocation WatchConnectivity; do
  if rg -q "import $forbidden_mac_framework" "$mac_entry"; then
    print -u2 "FAIL: Mac companion must not import $forbidden_mac_framework; those mobile/device capabilities need their own reviewed implementation"
    exit 1
  fi
done
rg -q 'Mac 不读取或写入 Apple 健康' "$app_shell" || { print -u2 'FAIL: Mac health surface must explicitly disclose its manual-only boundary'; exit 1; }
[[ "$(rg -c 'onPersistImmediately: persistBeforeSystemSideEffect' "$app_shell")" -ge 2 ]] || { print -u2 'FAIL: every phone-sized shell path must receive the durable-before-system-side-effect callback'; exit 1; }
rg -q 'platform=macOS' "$mac_preflight_script" || { print -u2 'FAIL: macOS preflight must target macOS'; exit 1; }
rg -q 'CODE_SIGNING_ALLOWED=NO' "$mac_preflight_script" || { print -u2 'FAIL: macOS preflight must be non-signing'; exit 1; }
plutil -lint "$mac_plist" >/dev/null
plutil -lint "$watch_plist" >/dev/null
plutil -lint "$watch_privacy_manifest" >/dev/null
[[ "$(/usr/libexec/PlistBuddy -c 'Print :NSPrivacyTracking' "$watch_privacy_manifest")" == "false" ]] || { print -u2 'FAIL: Watch privacy manifest must declare no tracking'; exit 1; }
[[ "$(/usr/libexec/PlistBuddy -c 'Print :NSPrivacyCollectedDataTypes' "$watch_privacy_manifest" | tr -d '[:space:]')" == "Array{}" ]] || { print -u2 'FAIL: Watch privacy manifest must not claim collected data for this minimal companion'; exit 1; }
[[ "$(/usr/libexec/PlistBuddy -c 'Print :NSPrivacyAccessedAPITypes' "$watch_privacy_manifest" | tr -d '[:space:]')" == "Array{}" ]] || { print -u2 'FAIL: Watch privacy manifest must not declare an unused required-reason API'; exit 1; }
rg -Fq 'C30000000000000000000004 /* PrivacyInfo.xcprivacy in Resources */' "$project" || { print -u2 'FAIL: Watch privacy manifest must be included in Watch resources'; exit 1; }
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$mac_plist")" == '$(PRODUCT_BUNDLE_IDENTIFIER)' ]] || { print -u2 'FAIL: macOS Info.plist must resolve its bundle identifier from build settings'; exit 1; }
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$mac_plist")" == '$(MARKETING_VERSION)' ]] || { print -u2 'FAIL: macOS Info.plist must resolve its marketing version from build settings'; exit 1; }
[[ "$(/usr/libexec/PlistBuddy -c 'Print :WKCompanionAppBundleIdentifier' "$watch_plist")" == '$(WK_COMPANION_APP_BUNDLE_IDENTIFIER)' ]] || { print -u2 'FAIL: Watch companion plist must resolve its paired iPhone bundle identifier from build settings'; exit 1; }
# Compare the actual Debug/Release values for the two targets rather than hard-coding the current
# default identifier. This remains useful after the owner changes an identifier for Personal Team
# signing: Xcode must see an exactly matching paired-iPhone value in both Watch configurations.
iphone_bundle_ids="$(awk '
  /A10000000000000000000082 .*XCBuildConfiguration/ || /A10000000000000000000083 .*XCBuildConfiguration/ {
    if (match($0, /PRODUCT_BUNDLE_IDENTIFIER = [^;]+;/)) {
      value = substr($0, RSTART, RLENGTH)
      sub(/^PRODUCT_BUNDLE_IDENTIFIER = /, "", value)
      sub(/;$/, "", value)
      print value
    }
  }
' "$project" | sort -u)"
watch_companion_ids="$(awk '
  /C30000000000000000000082 .*XCBuildConfiguration/ || /C30000000000000000000083 .*XCBuildConfiguration/ {
    if (match($0, /WK_COMPANION_APP_BUNDLE_IDENTIFIER = [^;]+;/)) {
      value = substr($0, RSTART, RLENGTH)
      sub(/^WK_COMPANION_APP_BUNDLE_IDENTIFIER = /, "", value)
      sub(/;$/, "", value)
      print value
    }
  }
' "$project" | sort -u)"
[[ -n "$iphone_bundle_ids" && "$iphone_bundle_ids" == "$watch_companion_ids" ]] || { print -u2 'FAIL: Watch companion bundle setting must equal the iPhone target bundle identifier'; exit 1; }
[[ "$(awk '/C30000000000000000000082 .*XCBuildConfiguration/ || /C30000000000000000000083 .*XCBuildConfiguration/ { print }' "$project" | rg -c 'WK_COMPANION_APP_BUNDLE_IDENTIFIER = [^;]+;')" -eq 2 ]] || { print -u2 'FAIL: both Watch build configurations must define the paired iPhone bundle identifier'; exit 1; }
rg -q 'YouyeHealthCoachWatchApp' "$project" || { print -u2 'FAIL: watchOS companion target missing'; exit 1; }
rg -Fq 'C30000000000000000000003 /* Assets.xcassets in Resources */' "$project" || { print -u2 'FAIL: Watch companion asset catalog must be included in its own target resources'; exit 1; }
[[ "$(rg -c 'ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;' "$project")" -ge 4 ]] || { print -u2 'FAIL: both Watch build configurations must select the Watch AppIcon catalog'; exit 1; }
rg -q 'SDKROOT = watchos;' "$project" || { print -u2 'FAIL: watch target must use watchOS SDK'; exit 1; }
rg -q 'WATCHOS_DEPLOYMENT_TARGET = 10\.0;' "$project" || { print -u2 'FAIL: watchOS 10 deployment target missing'; exit 1; }
rg -q 'TARGETED_DEVICE_FAMILY = 4;' "$project" || { print -u2 'FAIL: watch target must retain watch device family'; exit 1; }
rg -q 'com.apple.product-type.application.watchapp2' "$project" || { print -u2 'FAIL: Watch companion must use the watchOS app product type'; exit 1; }
[[ "$(/usr/libexec/PlistBuddy -c 'Print :WKApplication' "$watch_plist")" == "true" ]] || { print -u2 'FAIL: Watch companion Info.plist must declare WKApplication'; exit 1; }
if rg -q 'Embed Watch Content' "$project"; then
  print -u2 'FAIL: Watch companion must remain a separate later-phase target until its platform component is installed and verified'
  exit 1
fi
rg -q 'YouyeHealthCoachWatchApp' "$watch_scheme" || { print -u2 'FAIL: shared Watch scheme missing target'; exit 1; }
rg -q 'BlueprintIdentifier="C30000000000000000000050"' "$watch_scheme" || { print -u2 'FAIL: shared Watch scheme must point to the Watch app target'; exit 1; }
rg -q 'BuildableName="YouyeHealthCoachWatchApp.app"' "$watch_scheme" || { print -u2 'FAIL: shared Watch scheme must launch the Watch app product'; exit 1; }
rg -q 'WCSessionDelegate' "$watch_entry" || { print -u2 'FAIL: Watch companion must receive its minimal daily-card context through WatchConnectivity'; exit 1; }
for forbidden_watch_framework in HealthKit AVFoundation Vision PhotosUI CoreLocation UserNotifications; do
  if rg -q "import $forbidden_watch_framework" "$watch_entry"; then
    print -u2 "FAIL: Watch companion must not import $forbidden_watch_framework; it only renders the paired iPhone daily card"
    exit 1
  fi
done
for forbidden_watch_capability in HKHealthStore AVCaptureSession PhotosPicker CLLocationManager UNUserNotificationCenter; do
  if rg -q "$forbidden_watch_capability" "$watch_entry"; then
    print -u2 "FAIL: Watch companion must not access $forbidden_watch_capability; it only renders the paired iPhone daily card"
    exit 1
  fi
done
rg -q '没有录像、缓存、回放或姿态分析' "$watch_entry" || { print -u2 'FAIL: Watch companion must state its no-camera/no-pose boundary'; exit 1; }
rg -q 'hasTodayPlan' "$watch_entry" || { print -u2 'FAIL: Watch companion must distinguish a current iPhone daily card from stale context'; exit 1; }
rg -q '收到的 iPhone 日卡不完整，已清空旧内容' "$watch_entry" || { print -u2 'FAIL: Watch companion must clear rather than retain an incomplete incoming day card'; exit 1; }
rg -q 'let breakfast = context\["breakfast"\] as\? String' "$watch_entry" || { print -u2 'FAIL: Watch companion must validate the complete whitelist before showing an incoming day card'; exit 1; }
rg -q 'shouldResetLocalTimer' "$watch_entry" || { print -u2 'FAIL: Watch must retain local timing across same-day iPhone card refreshes and reset only on an actual day change'; exit 1; }
rg -q 'Watch target deliberately does not link the iPhone/Mac coach module' "$watch_entry" || { print -u2 'FAIL: Watch companion source must remain independently compilable rather than assuming an unlinked shared module'; exit 1; }
rg -q 'public enum WatchLocalTimerResetPolicy' "Sources/YouyeHealthCoach/WatchDailyCardPayload.swift" || { print -u2 'FAIL: Watch timer reset semantics need a shared testable policy'; exit 1; }
rg -q 'same-day iPhone Watch-card refresh' "Sources/YouyeHealthCoachRuleCheck/main.swift" || { print -u2 'FAIL: rule checks must cover same-day Watch refresh timer retention'; exit 1; }
rg -q 'if !isCurrentDay \{ startedAt = nil \}' "$watch_entry" || { print -u2 'FAIL: an expired iPhone day card must reset Watch-local timing state'; exit 1; }
rg -Fq 'calendar.isDate(plan.date, inSameDayAs: now)' "Sources/YouyeHealthCoach/WatchDailyCardPayload.swift" || { print -u2 'FAIL: iPhone must not publish an old formal plan as today’s Watch card'; exit 1; }
rg -q 'invalidateDailyCard' "Sources/YouyeHealthCoach/WatchCompanionBridge.swift" || { print -u2 'FAIL: Watch bridge must be able to invalidate a stale card during iPhone data recovery'; exit 1; }
rg -q '不当作今天计划显示' "$watch_entry" || { print -u2 'FAIL: Watch companion must not present a prior-day iPhone card as today'; exit 1; }
rg -Fq 'TimelineView(.periodic(from: .now, by: 1))' "$watch_entry" || { print -u2 'FAIL: an open Watch screen must promptly re-evaluate stale daily context across midnight'; exit 1; }
rg -q 'publishedAt' "Sources/YouyeHealthCoach/WatchDailyCardPayload.swift" || { print -u2 'FAIL: paired iPhone must timestamp the minimal Watch daily-card context'; exit 1; }
rg -q 'transportRevision' "Sources/YouyeHealthCoach/WatchDailyCardPayload.swift" || { print -u2 'FAIL: minimal Watch contexts need a transport-only same-second ordering token'; exit 1; }
rg -q 'nextTransportRevision' "Sources/YouyeHealthCoach/WatchCompanionBridge.swift" || { print -u2 'FAIL: iPhone Watch bridge must generate a monotonic transport revision'; exit 1; }
rg -q 'lastTransportRevision' "$watch_entry" || { print -u2 'FAIL: Watch companion must retain the latest transport revision for same-second ordering'; exit 1; }
rg -q 'shouldApplyIncomingCard' "$watch_entry" || { print -u2 'FAIL: Watch companion must reject an out-of-order daily-card context'; exit 1; }
rg -q 'WatchDailyCardFreshnessPolicy' "Sources/YouyeHealthCoach/WatchDailyCardPayload.swift" || { print -u2 'FAIL: Watch payload ordering needs a shared testable policy'; exit 1; }
rg -q 'delayed Watch context' "Sources/YouyeHealthCoachRuleCheck/main.swift" || { print -u2 'FAIL: rule checks must cover stale Watch-context rejection'; exit 1; }
rg -q 'public struct WatchDailyCardPayload' "Sources/YouyeHealthCoach/WatchDailyCardPayload.swift" || { print -u2 'FAIL: Watch bridge needs a testable minimal payload contract'; exit 1; }
rg -q 'iPhone 当天日卡字段不完整；Watch 已清除旧日卡。' "Sources/YouyeHealthCoach/WatchDailyCardPayload.swift" || { print -u2 'FAIL: malformed formal Watch payloads must fail closed by invalidating the old card'; exit 1; }
if rg -q 'date!\|breakfast!\|lunch!\|dinner!\|training!\|trainingMinimum!\|isRecovery!\|cameraBoundary!' "Sources/YouyeHealthCoach/WatchDailyCardPayload.swift"; then
  print -u2 'FAIL: Watch payload serialization must not force-unwrap display fields'
  exit 1
fi
rg -q 'WatchDailyCardPayload.make' "Sources/YouyeHealthCoach/WatchCompanionBridge.swift" || { print -u2 'FAIL: iPhone Watch bridge must publish only the shared payload contract'; exit 1; }
rg -q 'WatchDailyCardPayload.make' "Sources/YouyeHealthCoachRuleCheck/main.swift" || { print -u2 'FAIL: Watch payload privacy boundary must be exercised by rule checks'; exit 1; }
rg -q '不引入第三方桥接库' "$dependency_review" || { print -u2 'FAIL: Watch dependency review must record the no-wrapper decision'; exit 1; }
rg -q 'updateApplicationContext' "$dependency_review" || { print -u2 'FAIL: Watch dependency review must document the selected native API'; exit 1; }
rg -q '健康与动作能力复核' "$dependency_review" || { print -u2 'FAIL: dependency review must cover HealthKit and pose-library alternatives'; exit 1; }
rg -q '健康与姿态能力继续零第三方 SDK' "$dependency_review" || { print -u2 'FAIL: dependency review must record the current no-wrapper/no-pose-SDK decision without falsely claiming zero local-parser packages'; exit 1; }

# Nearby-offer preferences are intentionally only a future-provider policy in this local MVP.
# Keep the project honest: no scraping/network client, coupon claim,
# order, payment, or background price-notification path may appear before an explicit product and
# privacy review adds the required user controls and evidence contract.
rg -q '附近优惠服务尚未连接；不查实时价格、不发送通知。' "$nearby_offer_policy_source" || { print -u2 'FAIL: nearby offer policy must disclose that no provider is connected'; exit 1; }
if rg -q 'URLSession|NWPathMonitor|CLLocationManager|MKLocalSearch|BGAppRefreshTask|BGTaskScheduler|UNUserNotificationCenter' "$nearby_offer_policy_source"; then
  print -u2 'FAIL: local MVP nearby-offer policy must not add network, location, background refresh, or notification delivery'
  exit 1
fi
[[ "$(/usr/libexec/PlistBuddy -c 'Print :NSLocationWhenInUseUsageDescription' "$plist")" == *"主动"* && "$(/usr/libexec/PlistBuddy -c 'Print :NSLocationWhenInUseUsageDescription' "$plist")" == *"不保存"* ]] || { print -u2 'FAIL: nearby current-location permission must be explicit-action and non-persistent'; exit 1; }
rg -Fq 'manager.requestWhenInUseAuthorization()' "$app_shell" || { print -u2 'FAIL: nearby current location must use while-in-use permission only'; exit 1; }
rg -Fq 'Button { location.refresh() }' "$app_shell" || { print -u2 'FAIL: nearby location permission must have a visible owner action'; exit 1; }
rg -Fq 'manager.requestLocation()' "$app_shell" || { print -u2 'FAIL: nearby location must be a one-off request, not continuous tracking'; exit 1; }
rg -Fq 'manager.stopUpdatingLocation()' "$app_shell" || { print -u2 'FAIL: nearby location must stop after its one-off map centre'; exit 1; }
rg -Fq 'currentLocation == nil && safeArea?.isEmpty == false' "$nearby_offer_policy_source" || { print -u2 'FAIL: a fresh nearby location must take precedence over a stale fuzzy-area query'; exit 1; }

dimensions="$(sips -g pixelWidth -g pixelHeight -g hasAlpha "$icon")"
print -r -- "$dimensions" | rg -q 'pixelWidth: 1024' || { print -u2 'FAIL: App Icon width is not 1024'; exit 1; }
print -r -- "$dimensions" | rg -q 'pixelHeight: 1024' || { print -u2 'FAIL: App Icon height is not 1024'; exit 1; }
print -r -- "$dimensions" | rg -q 'hasAlpha: no' || { print -u2 'FAIL: App Icon must not have alpha'; exit 1; }
watch_dimensions="$(sips -g pixelWidth -g pixelHeight -g hasAlpha "$watch_icon")"
print -r -- "$watch_dimensions" | rg -q 'pixelWidth: 1024' || { print -u2 'FAIL: Watch App Icon width is not 1024'; exit 1; }
print -r -- "$watch_dimensions" | rg -q 'pixelHeight: 1024' || { print -u2 'FAIL: Watch App Icon height is not 1024'; exit 1; }
print -r -- "$watch_dimensions" | rg -q 'hasAlpha: no' || { print -u2 'FAIL: Watch App Icon must not have alpha'; exit 1; }

rg -q 'VNDetectHumanBodyPoseRequest' "$pose_source" || { print -u2 'FAIL: local pose source lacks Vision body-pose request'; exit 1; }
rg -q 'nonisolated let focus: LivePoseFocus' "$pose_source" || { print -u2 'FAIL: capture-queue Vision analysis must use an immutable nonisolated focus under Swift 6 concurrency'; exit 1; }
rg -q 'alwaysDiscardsLateVideoFrames = true' "$pose_source" || { print -u2 'FAIL: local pose source must discard capture frames'; exit 1; }
rg -q 'timeIntervalSince\(lastAnalysis\) >= 0\.25' "$pose_source" || { print -u2 'FAIL: local pose source must perform continuous near-real-time analysis at roughly four updates per second'; exit 1; }
rg -q '实时提示' "$pose_source" || { print -u2 'FAIL: local pose source must surface live cues'; exit 1; }
rg -q 'AVSpeechSynthesizer' "$pose_source" || { print -u2 'FAIL: local pose source must support optional system speech cues'; exit 1; }
rg -Fq 'LocalDataDeletion.voiceCuePreferenceKey(for: ownerID)' "$pose_source" || { print -u2 'FAIL: local pose source must persist the voluntary voice-cue setting under the active owner'; exit 1; }
rg -q 'cue\.text != lastSpokenText' "$pose_source" || { print -u2 'FAIL: local pose source must deduplicate spoken live cues'; exit 1; }
rg -q 'lastSpokenText = nil' "$pose_source" || { print -u2 'FAIL: stopping voice cues must reset the prior-session speech de-duplication state'; exit 1; }
rg -q 'safeSetupConfirmed' "$pose_source" || { print -u2 'FAIL: local pose source must require a user-confirmed safe fixed-phone setup'; exit 1; }
rg -q 'UIDevice.current.userInterfaceIdiom == \.phone' "$pose_source" || { print -u2 'FAIL: local pose source must restrict camera coaching to iPhone rather than iPad'; exit 1; }
rg -q '此 iPad 仅保留跟练提示与计时' "$pose_source" || { print -u2 'FAIL: iPad live-pose downgrade must be visible to the owner'; exit 1; }
rg -q '仅跟练/仅计时' "$pose_source" || { print -u2 'FAIL: local pose source must visibly downgrade when monitoring is unavailable'; exit 1; }
rg -q '分析已中断' "$pose_source" || { print -u2 'FAIL: stale pose analysis must be disclosed instead of appearing live'; exit 1; }
rg -Fq 'ViewThatFits(in: .horizontal)' "$pose_source" || { print -u2 'FAIL: live pose monitoring status must offer a narrow-width fallback layout'; exit 1; }
rg -q '实时状态应由横向行切换为纵向布局' "DEVICE_ACCEPTANCE.md" || { print -u2 'FAIL: device acceptance must cover live-pose narrow-width and Dynamic Type layout'; exit 1; }
if rg -q 'AVAudioSession\.sharedInstance\|outputVolume\|utterance\.volume' "$pose_source"; then
  print -u2 'FAIL: local pose source must not override or independently scale system volume'
  exit 1
fi
for private_file in "Sources/YouyeHealthCoach/LocalStore.swift" "Sources/YouyeHealthCoach/PrivateMealPhotoStore.swift"; do
  rg -q 'options.insert\(\.completeFileProtection\)' "$private_file" || { print -u2 "FAIL: $private_file must apply complete file protection on iOS"; exit 1; }
  rg -q '#if os\(iOS\)' "$private_file" || { print -u2 "FAIL: $private_file must scope iOS file protection away from macOS atomic writes"; exit 1; }
done
rg -q '\.interactiveDismissDisabled\(awaitingInitialProfileSetup\)' "$app_shell" || { print -u2 'FAIL: first-run setup must not be dismissible before its initial private profile is durable'; exit 1; }
rg -q 'case \.malformed:' "Sources/YouyeHealthCoach/LocalStore.swift" || { print -u2 'FAIL: a damaged last-owner pointer must fail closed into recovery rather than looking like first run'; exit 1; }
rg -q 'malformedLastOwnerPointer' "Sources/YouyeHealthCoachRuleCheck/main.swift" || { print -u2 'FAIL: rule checks must cover malformed last-owner pointer recovery'; exit 1; }
rg -q 'discarding a local confirmation draft must not write, delete, or imply any Apple Health workout' "Sources/YouyeHealthCoachRuleCheck/main.swift" || { print -u2 'FAIL: rule checks must cover the local-only workout-draft boundary'; exit 1; }
rg -q 'a failed migrated-record save must remove only the copied owner photo and preserve the original legacy photo' "Sources/YouyeHealthCoachRuleCheck/main.swift" || { print -u2 'FAIL: rule checks must cover rollback of a failed private-photo migration save'; exit 1; }
rg -q '@Environment\(\\\.dynamicTypeSize\) private var dynamicTypeSize' "$app_shell" || { print -u2 'FAIL: recipe cards must adapt their compact summary for accessibility text sizes'; exit 1; }
rg -q 'if dynamicTypeSize\.isAccessibilitySize' "$app_shell" || { print -u2 'FAIL: recipe-card badges must switch to a vertical layout for accessibility text sizes'; exit 1; }
rg -q 'private var accessibilityStatusLabels' "Sources/YouyeHealthCoach/TodayDailyCardHeader.swift" || { print -u2 'FAIL: daily-card status labels must have an accessibility-size vertical layout'; exit 1; }
rg -q 'if dynamicTypeSize\.isAccessibilitySize' "Sources/YouyeHealthCoach/TodayDailyCardHeader.swift" || { print -u2 'FAIL: daily card must explicitly avoid compressed title/status rows at accessibility text sizes'; exit 1; }
[[ "$(rg -c 'applyPrivateDirectoryProtection\(\)' "Sources/YouyeHealthCoach/LocalStore.swift")" -ge 2 ]] || { print -u2 'FAIL: private JSON directory must apply complete file protection on iOS'; exit 1; }
[[ "$(rg -c 'applyPrivateDirectoryProtection\(\)' "Sources/YouyeHealthCoach/PrivateMealPhotoStore.swift")" -ge 3 ]] || { print -u2 'FAIL: private photo directory must apply complete file protection on iOS'; exit 1; }
rg -q 'FileProtectionType\.complete' "Sources/YouyeHealthCoach/LocalStore.swift" || { print -u2 'FAIL: private JSON directory must use complete data protection'; exit 1; }
rg -q 'FileProtectionType\.complete' "Sources/YouyeHealthCoach/PrivateMealPhotoStore.swift" || { print -u2 'FAIL: private photo directory must use complete data protection'; exit 1; }
rg -q '不计数、不测精确角度、不诊断' "$pose_source" || { print -u2 'FAIL: local pose source must state its safety boundary'; exit 1; }
rg -q '没有录像、缓存、回放或上传' "$pose_source" || { print -u2 'FAIL: pose coach must state the live-only no-recording boundary'; exit 1; }
rg -q '不要边走、骑车、游泳或手持手机边训练' "$pose_source" || { print -u2 'FAIL: pose coach must prohibit unsafe moving or water-based camera use'; exit 1; }
rg -q 'public enum TrainingExecutionAudit' "Sources/YouyeHealthCoach/TrainingCatalog.swift" || { print -u2 'FAIL: training catalog needs beginner-execution auditing'; exit 1; }
rg -q '含移动/水中环节时必须禁止同步取景' "Sources/YouyeHealthCoach/TrainingCatalog.swift" || { print -u2 'FAIL: every moving or water-based card, including recovery-priority cards, must be guarded from unsafe live capture'; exit 1; }
rg -q 'containsMovingOrWaterSegment' "Sources/YouyeHealthCoach/TrainingCatalog.swift" || { print -u2 'FAIL: live-camera safety must not rely only on a card’s recovery/endurance label'; exit 1; }
rg -q '实时姿态分析不可用；已停止取景并降级为仅跟练/仅计时' "$pose_source" || { print -u2 'FAIL: Vision analysis failures must stop camera capture rather than leave a stale monitor running'; exit 1; }
rg -q 'public func stopIfAnalysisIsStale' "$pose_source" || { print -u2 'FAIL: a stalled Vision pipeline needs an explicit hardware-stop watchdog'; exit 1; }
rg -q 'coach\.stopIfAnalysisIsStale' "$pose_source" || { print -u2 'FAIL: the visible live-coach surface must run the stalled-analysis watchdog'; exit 1; }
rg -q 'no automatic restart' "$pose_source" || { print -u2 'FAIL: failed local pose analysis must not auto-restart camera capture'; exit 1; }
rg -q 'card.livePoseSafetyNote' "$app_shell" || { print -u2 'FAIL: training detail must show live-pose safety boundary'; exit 1; }
rg -q '安全确认时会明确降级为仅跟练/仅计时' "$app_shell" || { print -u2 'FAIL: training detail must disclose live-pose fallback conditions'; exit 1; }
rg -A8 'if phase != \.active' "$pose_source" | rg -q 'coach\.stop\(\)' || { print -u2 'FAIL: local pose source must stop capture for ordinary app inactivity'; exit 1; }
rg -q 'isRunning = false' "$pose_source" || { print -u2 'FAIL: local pose stop must immediately clear the user-facing monitoring state'; exit 1; }
rg -q 'lastUpdatedAt = nil' "$pose_source" || { print -u2 'FAIL: local pose stop must clear stale analysis timestamps immediately'; exit 1; }
rg -q 'private final class CaptureStartGate' "$pose_source" || { print -u2 'FAIL: local pose source must use a thread-safe gate to cancel a pending camera start'; exit 1; }
rg -Fq 'guard !isRunning, !isStarting, startGate.begin() else { return }' "$pose_source" || { print -u2 'FAIL: a second pose-start request must be rejected while camera configuration is in flight'; exit 1; }
rg -Fq 'guard self.startGate.isRequested else { return }' "$pose_source" || { print -u2 'FAIL: delayed camera permission callbacks must respect a withdrawn start request'; exit 1; }
rg -q 'startGate\.withdraw()' "$pose_source" || { print -u2 'FAIL: stopping local pose must withdraw any pending start request'; exit 1; }
rg -Fq 'guard UIDevice.current.userInterfaceIdiom == .phone else {' "$pose_source" || { print -u2 'FAIL: live pose must reject non-iPhone devices at both UI and capture setup boundaries'; exit 1; }
rg -q '实时取景与语音提示仅在 iPhone 开启' "$pose_source" || { print -u2 'FAIL: iPad fallback must truthfully omit iPhone-only live pose controls'; exit 1; }
rg -q 'AVCaptureSession\.wasInterruptedNotification' "$pose_source" || { print -u2 'FAIL: local pose source must stop on system camera interruption'; exit 1; }
rg -q 'AVCaptureSession\.runtimeErrorNotification' "$pose_source" || { print -u2 'FAIL: local pose source must stop on camera runtime errors'; exit 1; }
rg -q 'stopForSystemInterruption' "$pose_source" || { print -u2 'FAIL: camera interruptions must visibly downgrade local monitoring rather than restart it'; exit 1; }
rg -q 'ScrollView' "$pose_source" || { print -u2 'FAIL: live-pose controls must remain reachable on compact screens and large Dynamic Type'; exit 1; }
rg -Fq 'safeAreaInset(edge: .bottom' "$pose_source" || { print -u2 'FAIL: live-pose start/stop control must stay visible above the bottom safe area'; exit 1; }
rg -Fq 'cameraSurface(compact: true)' "$pose_source" || { print -u2 'FAIL: in-App follow-along must keep a compact local camera surface visible with the lesson'; exit 1; }
rg -Fq 'verticalSizeClass == .compact ? 190 : 340' "$pose_source" || { print -u2 'FAIL: synchronized video and camera-only surfaces must use a compact-height layout in landscape'; exit 1; }
rg -q 'frame\(maxWidth: \.infinity, minHeight: 44\)' "$pose_source" || { print -u2 'FAIL: live-pose start/stop control must keep a full-width minimum touch target'; exit 1; }
if rg -qi 'AVAssetWriter|AVCaptureMovieFileOutput|AVAssetExportSession|URLSession|https?://|Data\(contentsOf:|\.write\(' "$pose_source"; then
  print -u2 'FAIL: local pose source must not contain recording, file-write, or network upload paths'
  exit 1
fi

# The camera, photo, and notification prompts must remain owner-initiated and cannot share a
# hidden onboarding/network path.  These checks are intentionally source-level: final prompts
# still require a real iPhone acceptance pass.
rg -Fq 'AVCaptureDevice.requestAccess(for: .video)' "$pose_source" || { print -u2 'FAIL: camera access must be requested only through the local capture path'; exit 1; }
rg -q 'safeSetupConfirmed' "$pose_source" || { print -u2 'FAIL: camera access must retain the confirmed fixed-phone safety gate'; exit 1; }
# Food photos may use the system camera only after a separate owner tap. They remain a pending
# in-memory value until a user has supplied grams and confirmed a same-day replacement.
rg -q 'private struct PrivateFoodCameraPicker' "$app_shell" || { print -u2 'FAIL: food-photo camera bridge must be explicit and local'; exit 1; }
rg -Fq 'Label("拍摄家中食材"' "$app_shell" || { print -u2 'FAIL: food-photo camera must have a named owner action'; exit 1; }
rg -q '确认重排后才会保存到 App 私有目录' "$app_shell" || { print -u2 'FAIL: food-photo UI must disclose confirmation-gated private persistence'; exit 1; }
rg -q 'private enum PrivateFoodPhotoPreparation' "$app_shell" || { print -u2 'FAIL: private food photos need a local size-preparation boundary'; exit 1; }
rg -q 'maximumPixelDimension: CGFloat = 2_048' "$app_shell" || { print -u2 'FAIL: private food photos must cap image dimensions'; exit 1; }
rg -q 'targetMaximumBytes = 2_500_000' "$app_shell" || { print -u2 'FAIL: private food photos must cap retained file size'; exit 1; }
rg -q 'maximumSides: \[CGFloat\] = \[maximumPixelDimension, 1_600, 1_280, 1_024, 768\]' "$app_shell" || { print -u2 'FAIL: food-photo preparation must downscale again if JPEG quality alone is insufficient'; exit 1; }
rg -q 'Validate owner-entered ranges before touching the selected photo' "$app_shell" || { print -u2 'FAIL: plan-external meal range validation must happen before creating a private photo copy'; exit 1; }
rg -Fq 'loadTransferable(type: Data.self)' "$app_shell" || { print -u2 'FAIL: iOS food-photo picker must load source bytes only into task-local scope'; exit 1; }
rg -Fq 'PrivateFoodPhotoPreparation.normalizedJPEG(from:' "$app_shell" || { print -u2 'FAIL: iOS food-photo picker must normalize and compress task-local source bytes before private storage'; exit 1; }
rg -Fq 'format.scale = 1' "$app_shell" || { print -u2 'FAIL: private food-photo maximum must be a real pixel ceiling rather than screen-scaled points'; exit 1; }
rg -q 'func coachKeyboardDismissal' "$app_shell" || { print -u2 'FAIL: iPhone forms need an interactive keyboard-dismissal policy'; exit 1; }
[[ "$(rg -c '\.coachKeyboardDismissal\(\)' "$app_shell")" -ge 4 ]] || { print -u2 'FAIL: setup, food, and health forms must all apply the keyboard-dismissal policy'; exit 1; }
rg -q 'PhotosPicker\(selection:' "$app_shell" || { print -u2 'FAIL: meal photos must use the owner-selected PhotosPicker'; exit 1; }
rg -q 'Label\("拍照", systemImage: "camera.fill"\)' "$app_shell" || { print -u2 'FAIL: unplanned-meal logging must offer an explicit camera action'; exit 1; }
rg -q 'Section\("热量结果"\)' "$app_shell" || { print -u2 'FAIL: unplanned-meal estimate must be visible before confirmation'; exit 1; }
rg -q 'isSaving || isLoadingPhoto' "$app_shell" || { print -u2 'FAIL: an in-flight meal-photo read must block accidental confirmation'; exit 1; }
if rg -q 'PHPhotoLibrary|requestAuthorization\(for: \.readWrite\)|requestAuthorization\(for: \.addOnly\)' "$app_shell"; then
  print -u2 'FAIL: meal photo flow must not request broad Photos library authorization'
  exit 1
fi
rg -q 'requestAuthorizationAndSynchronize' "$app_shell" || { print -u2 'FAIL: notifications need an explicit owner action'; exit 1; }
rg -q '允许通知并更新提醒' "$app_shell" || { print -u2 'FAIL: notification permission button must remain explicit in the UI'; exit 1; }
if rg -q 'MKLocalSearch|URLSession' "$app_shell"; then
  print -u2 'FAIL: nearby UI must not silently start a network/provider lookup'
  exit 1
fi

rg -Fq 'requestAuthorization(toShare: [], read: readTypes)' "$health_source" || { print -u2 'FAIL: HealthKit authorization must be read-only'; exit 1; }
rg -q 'let metrics = permissionPlan\.readMetrics' "$health_source" || { print -u2 'FAIL: HealthKit summary reads must obey the selected minimal metric plan'; exit 1; }
rg -q 'metrics\.contains\(\.workouts\)' "$health_source" || { print -u2 'FAIL: workout summary must be conditional on explicit read permission'; exit 1; }
rg -Fq '#if os(iOS) && canImport(HealthKit)' "$health_source" || { print -u2 'FAIL: HealthKit provider itself must be limited to the iPhone/iPad target'; exit 1; }
rg -q 'public enum HealthIntervalAggregation' "$health_source" || { print -u2 'FAIL: HealthKit aggregates need a shared overlap-safe interval utility'; exit 1; }
rg -q 'HealthIntervalAggregation.unionDuration' "$health_source" || { print -u2 'FAIL: sleep/workout summary must use overlap-safe union duration'; exit 1; }
rg -q 'public enum HealthQuantityWindowPolicy' "$health_source" || { print -u2 'FAIL: quantity HealthKit summaries need a boundary-safe policy'; exit 1; }
rg -q 'strictStartDate, \.strictEndDate' "$health_source" || { print -u2 'FAIL: quantity HealthKit queries must exclude cross-boundary samples rather than count them whole'; exit 1; }
rg -q 'queryScopeDescription' "$health_source" || { print -u2 'FAIL: HealthKit summary must disclose its query-window boundary'; exit 1; }
rg -q 'localRetentionDescription' "$health_source" || { print -u2 'FAIL: HealthKit summary must disclose its transient local-retention boundary'; exit 1; }
rg -q 'showingBilibiliLiveFollowAlong = false' "$app_shell" || { print -u2 'FAIL: a protective recovery downgrade must close the in-App Bilibili and local-pose surface'; exit 1; }
rg -q '已核对运动类型' "$app_shell" || { print -u2 'FAIL: stopped workout confirmation must visibly lock its chosen activity type'; exit 1; }
rg -q 'pendingWorkoutConfirmations' "$app_shell" || { print -u2 'FAIL: leaving a training detail must preserve a stopped real timer as a local confirmation draft'; exit 1; }
rg -q '不会写入 Apple 健康' "$app_shell" || { print -u2 'FAIL: a stopped local workout draft must disclose that it is not written to Apple Health'; exit 1; }
rg -q '跨日草稿不会重新开放旧日训练' "$app_shell" || { print -u2 'FAIL: a cross-day local workout draft must remain reviewable without reopening old-day execution'; exit 1; }
rg -q '日期已切换，旧日训练已停止计时' "$app_shell" || { print -u2 'FAIL: an open old training detail must stop its local timer at the date boundary'; exit 1; }
rg -q 'showingBilibiliLiveFollowAlong = false' "$app_shell" || { print -u2 'FAIL: date changes must close temporary Bilibili follow-along before an old card becomes read-only'; exit 1; }
rg -q 'guard cardMatchesCurrentPlanDay, plan.trainingMode == \.standard else' "$app_shell" || { print -u2 'FAIL: third-party training handoff must recheck the card after an async scheduling boundary'; exit 1; }
rg -q 'private struct PendingWorkoutDraftSection' "$app_shell" || { print -u2 'FAIL: stopped local workout drafts need a reusable review section outside the active-day screen'; exit 1; }
pending_draft_section_count=$(rg -F 'PendingWorkoutDraftSection(plan: $plan, privateData: $privateData)' "$app_shell" | wc -l | tr -d ' ')
[[ "$pending_draft_section_count" -ge 3 ]] || { print -u2 'FAIL: pending workout drafts must remain reachable in preparation, active, and completed plan phases'; exit 1; }
rg -q '阶段完成后同样仍可核对' "$app_shell" || { print -u2 'FAIL: phase-completion UI must preserve the review-only boundary for stopped workout drafts'; exit 1; }
rg -q '第 56 天停止一段实际计时但不立即处理，跨到阶段评估日后' "DEVICE_ACCEPTANCE.md" || { print -u2 'FAIL: device acceptance must cover review of stopped workouts after the programme has completed'; exit 1; }
rg -q '旧日训练详情保持打开至跨过午夜' "DEVICE_ACCEPTANCE.md" || { print -u2 'FAIL: device acceptance must cover closing active pose/video coaching at the date boundary'; exit 1; }
rg -q 'if canStartWorkoutTimer \{' "$app_shell" || { print -u2 'FAIL: restarting a stopped workout must remain unavailable on an old-day confirmation draft'; exit 1; }
rg -A12 '\.onDisappear \{' "$app_shell" | rg -q 'stopWorkoutTimer' || { print -u2 'FAIL: leaving an active training detail must stop the timer before saving its local confirmation draft'; exit 1; }
rg -q '丢弃这段本机训练草稿' "$app_shell" || { print -u2 'FAIL: a person must be able to explicitly discard a local workout-confirmation draft'; exit 1; }
rg -Fq 'guard discardWorkoutConfirmationIfNeeded() else { return }' "$app_shell" || { print -u2 'FAIL: a failed local-workout-draft discard must not hide the draft or start a new session'; exit 1; }
rg -q 'initialWorkoutConfirmationID' "$app_shell" || { print -u2 'FAIL: each stopped workout draft must be openable as its exact session, including multiple drafts on one day'; exit 1; }
rg -q 'public struct PendingWorkoutConfirmation' "Sources/YouyeHealthCoach/Privacy.swift" || { print -u2 'FAIL: local workout confirmation needs an explicit private data contract'; exit 1; }
rg -Fq 'guard PlanAdjuster.authority(for: kind) == .requiresConfirmation else { return nil }' "Sources/YouyeHealthCoach/HealthCheckIn.swift" || { print -u2 'FAIL: invalid major-plan proposal kinds must fail closed instead of crashing'; exit 1; }
rg -q 'recordingConfirmation' "Sources/YouyeHealthCoach/HealthWorkoutSyncSafety.swift" || { print -u2 'FAIL: local timer confirmation must use the local-draft safety state machine'; exit 1; }
if rg -q 'markingAttempt|recordingSuccess|recordingManualReview|hasSuccessReceipt|hasConflictingSuccessReceipt|needsReview' "Sources/YouyeHealthCoach/HealthWorkoutSyncSafety.swift"; then
  print -u2 'FAIL: local workout-draft safety must not retain an executable Apple Health write state machine'
  exit 1
fi
rg -q 'pendingWorkoutConfirmations' "Sources/YouyeHealthCoach/Privacy.swift" || { print -u2 'FAIL: export privacy must explicitly carry and clear workout-confirmation drafts'; exit 1; }
rg -q 'pendingWorkoutConfirmations == after.pendingWorkoutConfirmations' "Sources/YouyeHealthCoach/UnplannedMeal.swift" || { print -u2 'FAIL: unplanned-meal logging must preserve local workout-confirmation drafts'; exit 1; }
rg -q 'older private JSON without local workout-confirmation drafts' "Sources/YouyeHealthCoachRuleCheck/main.swift" || { print -u2 'FAIL: rule checks must preserve backward decoding without workout-confirmation drafts'; exit 1; }
rg -q '训练本机保存' README.md || { print -u2 'FAIL: the product boundary must document that stopped workout drafts are local and not auto-synced'; exit 1; }
rg -q 'crossesCalendarDay' "$app_shell" || { print -u2 'FAIL: cross-midnight workout confirmation must disclose exact-time handling'; exit 1; }
rg -q '保留实际开始和结束时间' "$app_shell" || { print -u2 'FAIL: cross-midnight workout UI must not force a real session into a scheduled plan day'; exit 1; }
rg -q '不能再打开 B 站、开始本机取景、计时或保存反馈' "$app_shell" || { print -u2 'FAIL: an old training detail must lock all new execution entry points after midnight'; exit 1; }
rg -Fq '.onChange(of: plan.trainingMode)' "$app_shell" || { print -u2 'FAIL: an already-open training detail must react when another screen activates protective recovery'; exit 1; }
rg -q '今天已从其他页面记录恢复信号，原训练已停止计时' "$app_shell" || { print -u2 'FAIL: cross-screen recovery must stop an active standard-training timer with an honest elapsed-time boundary'; exit 1; }
rg -Fq '#if os(iOS) && canImport(HealthKit)' "$app_shell" || { print -u2 'FAIL: Apple Health UI must be explicitly limited to the iPhone/iPad target'; exit 1; }
rg -q '数据来源' "$app_shell" || { print -u2 'FAIL: health UI must display the summary source'; exit 1; }
rg -Fq 'guard !isWorking else { return }' "$app_shell" || { print -u2 'FAIL: Health summary reads must reject concurrent owner requests'; exit 1; }
rg -Fq 'try CoachPrivateStorage.saveLastOwnerData(applied.data)' "$app_shell" || { print -u2 'FAIL: automatic HealthKit recovery downgrade must be durable before it becomes visible'; exit 1; }
rg -q 'durablePlan = replayedPlan' "Sources/YouyeHealthCoach/HealthCheckIn.swift" || { print -u2 'FAIL: a stale health-status screen must rebuild the saved recovery plan before creating another audit'; exit 1; }
rg -q 'HealthCheckInService\.replayedPlan' "Sources/YouyeHealthCoach/TrainingFeedback.swift" || { print -u2 'FAIL: stale training feedback must rebuild a saved recovery plan before applying feedback'; exit 1; }
rg -q '最后读取' "$app_shell" || { print -u2 'FAIL: health UI must display the summary fetch time'; exit 1; }
rg -q '上一天的 Apple 健康摘要未保留' "$app_shell" || { print -u2 'FAIL: Health UI must clear transient summary state when the local plan day changes'; exit 1; }
rg -Fq '.onChange(of: plan.date)' "$app_shell" || { print -u2 'FAIL: Health UI must observe the displayed plan date for cross-midnight summary invalidation'; exit 1; }
rg -q 'let requestedPlanDate = plan\.date' "$app_shell" || { print -u2 'FAIL: Health summary requests must bind to the plan date visible when the owner initiated them'; exit 1; }
rg -q '读取期间日期已切换；上一天的 Apple 健康结果未用于今天' "$app_shell" || { print -u2 'FAIL: Health summary results returning after midnight must be discarded rather than applied to a new day'; exit 1; }
rg -q '日期已切换；这条状态尚未保存' "Sources/YouyeHealthCoach/HealthCheckIn.swift" || { print -u2 'FAIL: an open health-status form must reject a stale calendar day rather than writing it under another plan'; exit 1; }
rg -Fq 'HealthStatusForm(planDate: plan.date' "$app_shell" || { print -u2 'FAIL: health-status forms must retain the plan date that was current when opened'; exit 1; }
rg -q 'openedPlanDayIsCurrent' "$app_shell" || { print -u2 'FAIL: health-status form must visibly disable stale-day submission'; exit 1; }
rg -q '这张表单不会保存昨天填写的状态' "$app_shell" || { print -u2 'FAIL: health-status form must explain the cross-midnight discard boundary before save'; exit 1; }
rg -q '在“健康状态”表单保持打开至跨过午夜' "DEVICE_ACCEPTANCE.md" || { print -u2 'FAIL: device acceptance must cover cross-midnight health-status form safety'; exit 1; }
rg -q 'UnplannedMealLoggingPolicy' "Sources/YouyeHealthCoach/UnplannedMeal.swift" || { print -u2 'FAIL: unplanned meal logging needs a formal-date safety contract'; exit 1; }
rg -q '这张表单不会把昨天填写的食材或照片重排到今天' "$app_shell" || { print -u2 'FAIL: meal-substitution UI must visibly block cross-midnight confirmation'; exit 1; }
rg -q '这张表单不会记录昨天填写的餐食或保存照片' "$app_shell" || { print -u2 'FAIL: unplanned-meal UI must visibly block cross-midnight logging'; exit 1; }
rg -Fq 'MealSubstitutionForm(planDate:' "$app_shell" || { print -u2 'FAIL: meal-substitution sheets must retain the opening plan date'; exit 1; }
rg -q '在“食材重排”或“计划外餐食”表单保持打开至跨过午夜' "DEVICE_ACCEPTANCE.md" || { print -u2 'FAIL: device acceptance must cover cross-midnight food-form safety'; exit 1; }
rg -Fq 'at: .now, plan: plan' "$app_shell" || { print -u2 'FAIL: manual health status must retain the actual save time instead of the plan midnight'; exit 1; }
rg -A12 'private func loadWeeklyCheckIn' "$app_shell" | rg -Fq 'weeklyWeightText = ""' || { print -u2 'FAIL: weekly-review form must clear the prior week draft before loading a new week'; exit 1; }
rg -q 'persistsHealthKitSnapshots = false' "Sources/YouyeHealthCoach/Privacy.swift" || { print -u2 'FAIL: private-data schema must explicitly exclude HealthKit snapshots'; exit 1; }
rg -q 'public enum PrivateCoachDataLoadOutcome' "Sources/YouyeHealthCoach/LocalStore.swift" || { print -u2 'FAIL: private store must distinguish absent data from an unreadable private record'; exit 1; }
rg -Fq 'data.profile.id == expectedOwnerID' "Sources/YouyeHealthCoach/LocalStore.swift" || { print -u2 'FAIL: private JSON load must bind the payload profile identity to its requested owner filename'; exit 1; }
rg -Fq 'try Self.validatingOwner(' "Sources/YouyeHealthCoach/LocalStore.swift" || { print -u2 'FAIL: private JSON owner identity validation must run during disk load'; exit 1; }
rg -q 'recoverPendingOwnerPhotoDeletions' "Sources/YouyeHealthCoach/LocalStore.swift" || { print -u2 'FAIL: launch must resolve a pending photo deletion against the owner record before cleanup'; exit 1; }
rg -q 'purgePendingOwnerScopedDeletions' "Sources/YouyeHealthCoach/PrivateMealPhotoStore.swift" || { print -u2 'FAIL: post-delete photo cleanup must remain exact-owner scoped without recreating a profile directory'; exit 1; }
rg -q 'restorePendingOwnerScopedDeletion' "Sources/YouyeHealthCoach/PrivateMealPhotoStore.swift" || { print -u2 'FAIL: interrupted deletion with a still-present profile must restore its owner-scoped private photos'; exit 1; }
rg -q 'localDataRecoveryRequired' "$app_shell" || { print -u2 'FAIL: app shell must lock writes when an existing private record cannot be loaded'; exit 1; }
rg -q '本地资料需要恢复' "$app_shell" || { print -u2 'FAIL: unreadable local data needs a visible recovery surface'; exit 1; }
rg -q '此前本机资料现在未找到，仍保持恢复保护' "$app_shell" || { print -u2 'FAIL: recovery must remain locked if a previously unreadable owner record later appears absent'; exit 1; }
rg -Fq 'guard savePrivateData(privateData) else { return false }' "$app_shell" || { print -u2 'FAIL: first-run setup must not dismiss before its private owner record is durable'; exit 1; }
rg -q '本机资料暂未保存；请勿删除 App，确认设备存储可用后再点' "$app_shell" || { print -u2 'FAIL: first-run save failure must remain actionable on the welcome screen'; exit 1; }
rg -q '本地资料需要恢复' INSTALL_ON_IPHONE.md || { print -u2 'FAIL: iPhone installation guide must explain the local-data recovery boundary'; exit 1; }
for metric in bodyMass bodyFatPercentage stepCount sleepAnalysis restingHeartRate activeEnergyBurned workoutType; do
  rg -q "$metric" "$health_source" || { print -u2 "FAIL: missing approved HealthKit metric $metric"; exit 1; }
done
if rg -qi 'distanceSwimming|distance.*swimming|HKWorkoutRoute|HKQuantitySample\(|HKCategorySample\(' "$health_source"; then
  print -u2 'FAIL: HealthKit source must not read swimming distance/routes or write non-workout health samples'
  exit 1
fi
if rg -q 'HKWorkoutBuilder|HKMetadataKeyWasUserEntered|saveConfirmedWorkout|HealthKitWriteMetric|writeMetrics|confirmedWorkoutWriteAndDedupRead' "$health_source"; then
  print -u2 'FAIL: read-only HealthKit source must not retain a workout write path'
  exit 1
fi
if rg -q 'healthWorkoutSyncs\.append|pendingHealthWorkoutSyncs\.append|recordingManualReview|recordingSuccess|markingAttempt' Sources/YouyeHealthCoach --glob '*.swift'; then
  print -u2 'FAIL: no current product path may create or mutate legacy Apple Health write records'
  exit 1
fi

# This target is universal but layout still needs simulator/device visual acceptance; do not let
# a later project edit silently drop iPad support.
rg -q 'TARGETED_DEVICE_FAMILY: "1,2"' project.yml || { print -u2 'FAIL: project specification must retain iPhone/iPad support'; exit 1; }
rg -q 'NavigationSplitView' "$app_shell" || { print -u2 'FAIL: large-screen Mac/iPad route needs a split-view implementation'; exit 1; }
rg -q 'PhoneWatchCompanionBridge\.shared\.publish' "$app_shell" || { print -u2 'FAIL: iPhone shell must publish its minimal daily card to a paired Watch'; exit 1; }
rg -q 'HealthKit summaries, photos, pose output, video, location' "Sources/YouyeHealthCoach/WatchCompanionBridge.swift" || { print -u2 'FAIL: Watch bridge must document its sensitive-data exclusion boundary'; exit 1; }
if rg -q 'PBXTargetDependency' "$project"; then
  print -u2 'FAIL: iPhone-first target must not depend on the unavailable Watch build'
  exit 1
fi
rg -q 'verifiedCandidateURL' "Sources/YouyeHealthCoach/TrainingCatalog.swift" || { print -u2 'FAIL: every Bilibili route must come from a validated direct-course candidate'; exit 1; }
rg -Fq 'order = [.dinner]' "Sources/YouyeHealthCoach/TodayNextStep.swift" || { print -u2 'FAIL: evening next-step guidance must not prescribe a missed lunch as a make-up meal'; exit 1; }
rg -q 'private static func isWindDownTime' "Sources/YouyeHealthCoach/TodayNextStep.swift" || { print -u2 'FAIL: next-step guidance must have an explicit circular sleep-boundary policy'; exit 1; }
rg -q '优先休息，不补餐或补练' "Sources/YouyeHealthCoach/TodayNextStep.swift" || { print -u2 'FAIL: late-night next-step guidance must clearly avoid compensatory food or exercise'; exit 1; }
rg -q '打开今天的 B 站跟练' "$app_shell" || { print -u2 'FAIL: training detail must provide the verified Bilibili lesson action'; exit 1; }
! rg -q '去 B 站搜索这组关键词' "$app_shell" || { print -u2 'FAIL: training detail must not send the owner back to manual Bilibili search'; exit 1; }
rg -Fq 'confirmingSynchronizedFollowAlong = true' "$app_shell" || { print -u2 'FAIL: static iPhone training must retain the reviewed synchronized follow-along confirmation route'; exit 1; }
rg -Fq 'showingBilibiliLiveFollowAlong = true' "$app_shell" || { print -u2 'FAIL: static iPhone training must retain the reviewed in-App video-plus-local-pose route'; exit 1; }
rg -q 'EphemeralBilibiliFollowAlongView' "Sources/YouyeHealthCoach/BilibiliFollowAlong.swift" || { print -u2 'FAIL: in-app Bilibili follow-along needs its local ephemeral WebKit surface'; exit 1; }
rg -q 'websiteDataStore = \.nonPersistent()' "Sources/YouyeHealthCoach/BilibiliFollowAlong.swift" || { print -u2 'FAIL: in-app Bilibili follow-along must not persist a video/web cache'; exit 1; }
rg -q 'allowsInlineMediaPlayback = true' "$follow_along_source" || { print -u2 'FAIL: synchronized follow-along must keep third-party playback inline beside the local camera tile'; exit 1; }
rg -q 'isElementFullscreenEnabled = false' "$follow_along_source" || { print -u2 'FAIL: synchronized follow-along must not let third-party element fullscreen hide the live-monitor tile'; exit 1; }
rg -Fq 'didFail _: WKNavigation?, withError _: Error' "$follow_along_source" || { print -u2 'FAIL: committed Bilibili navigation failures must use the real WKNavigationDelegate callback'; exit 1; }
rg -q 'decidePolicyFor navigationResponse: WKNavigationResponse' "$follow_along_source" || { print -u2 'FAIL: Bilibili HTTP response failures must lead to the visible local-monitor fallback'; exit 1; }
rg -q 'webViewWebContentProcessDidTerminate' "$follow_along_source" || { print -u2 'FAIL: a terminated WebKit process must lead to the visible local-monitor fallback'; exit 1; }
rg -q 'reloadIgnoringLocalCacheData' "$follow_along_source" || { print -u2 'FAIL: in-app Bilibili follow-along must start each owner-initiated session without reusing a cached request'; exit 1; }
rg -q 'webView\.stopLoading()' "$follow_along_source" || { print -u2 'FAIL: dismissing in-app Bilibili follow-along must stop third-party loading'; exit 1; }
rg -q 'isAwaitingAuthorization = true' "$pose_source" || { print -u2 'FAIL: synchronized camera start must distinguish the iOS permission-sheet inactive phase from ordinary backgrounding'; exit 1; }
rg -q 'guard coach\.isAwaitingAuthorization else' "$pose_source" || { print -u2 'FAIL: the camera permission sheet must not cancel the same explicit synchronized-start request'; exit 1; }
rg -q 'liveMonitoringRequested = false' "$pose_source" || { print -u2 'FAIL: manual stop, ordinary backgrounding and dismissal must clear synchronized monitoring intent'; exit 1; }
rg -q 'firstResultGrace: TimeInterval = 8' "$pose_source" || { print -u2 'FAIL: simultaneous WebKit load must retain a bounded first-Vision-result startup grace'; exit 1; }
rg -q 'BilibiliFollowAlongNavigationPolicy.isAllowed' "$follow_along_source" || { print -u2 'FAIL: in-app Bilibili follow-along must restrict top-level navigation to approved HTTPS hosts'; exit 1; }
rg -q 'guard BilibiliFollowAlongNavigationPolicy\.isAllowed\(url\)' "$follow_along_source" || { print -u2 'FAIL: in-app Bilibili follow-along must validate even its initial restored URL before loading'; exit 1; }
rg -q 'guard BilibiliFollowAlongNavigationPolicy\.isAllowed\(targetURL\)' "$follow_along_source" || { print -u2 'FAIL: in-app Bilibili follow-along must reject untrusted user-initiated navigation inside the temporary page'; exit 1; }
rg -q 'let url, BilibiliFollowAlongNavigationPolicy\.isAllowed\(url\)' "Sources/YouyeHealthCoach/TrainingCatalog.swift" || { print -u2 'FAIL: verified video candidates must reject malformed or non-Bilibili restored URLs'; exit 1; }
rg -q 'didFailProvisionalNavigation' "$follow_along_source" || { print -u2 'FAIL: in-app Bilibili follow-along must surface third-party loading failure'; exit 1; }
rg -q '切换为仅本机监测' "$pose_source" || { print -u2 'FAIL: a failed Bilibili page must offer an explicit local-monitor-only fallback'; exit 1; }
rg -q '重新尝试加载 B 站视频' "$pose_source" || { print -u2 'FAIL: the local-monitor fallback must let the owner deliberately retry third-party playback'; exit 1; }
rg -q 'CaptureFrameOrientationMonitor' "$pose_source" || { print -u2 'FAIL: live Vision analysis must retain a thread-safe gravity-aware frame orientation'; exit 1; }
rg -q 'videoRotationAngleForHorizonLevelCapture' "$pose_source" || { print -u2 'FAIL: live Vision analysis must follow the camera capture orientation'; exit 1; }
rg -q 'orientation: frameOrientationMonitor.current' "$pose_source" || { print -u2 'FAIL: Vision must consume the current capture orientation rather than a fixed upright value'; exit 1; }
rg -q 'videoRotationAngleForHorizonLevelPreview' "$pose_source" || { print -u2 'FAIL: the visible local camera tile must stay horizon-level as the iPhone rotates'; exit 1; }
rg -q 'connection.videoRotationAngle = 0' "$pose_source" || { print -u2 'FAIL: camera data output must be normalized before applying a separate Vision orientation'; exit 1; }
rg -q '开始实际训练计时' "$pose_source" || { print -u2 'FAIL: synchronized follow-along must expose an in-sheet owner-initiated workout timer'; exit 1; }
rg -q '停止并核对' "$pose_source" || { print -u2 'FAIL: synchronized follow-along must let the owner stop and review actual elapsed time without leaving the sheet first'; exit 1; }
rg -q '计时只会在你主动选择“开始跟练并计时”或点“开始实际训练计时”后开始' "$pose_source" || { print -u2 'FAIL: synchronized follow-along must disclose its two owner-initiated timer starts'; exit 1; }
[[ "$(rg -c 'workoutStartedAt: \$workoutStartedAt' "$app_shell")" -eq 2 ]] || { print -u2 'FAIL: both local coaching sheets must bind to the authoritative training-detail timer'; exit 1; }
rg -q 'private func beginWorkoutTimer()' "$app_shell" || { print -u2 'FAIL: every training timer entry must share the final current-day and standard-mode guard'; exit 1; }
rg -q '照片仍在本机处理中，完成后即可保存。' "$app_shell" || { print -u2 'FAIL: a disabled actual-meal save action must explain the pending local photo work'; exit 1; }
rg -q '请先填写这餐实际吃了什么。' "$app_shell" || { print -u2 'FAIL: a disabled actual-meal save action must name its missing required description'; exit 1; }
rg -q '请填写实际金额和用途备注。' "$app_shell" || { print -u2 'FAIL: a disabled expense save action must name both missing required fields'; exit 1; }
rg -q '请填写用途备注，方便之后核对预算。' "$app_shell" || { print -u2 'FAIL: a disabled expense save action must explain why the note is required'; exit 1; }
rg -Fq '数量后请补菜名，例如：鸡蛋 2 个。' "$app_shell" || { print -u2 'FAIL: a count-only meal draft must require a food name before saving'; exit 1; }
rg -q '这张表单已失效；请取消后从今天重新打开。' "$app_shell" || { print -u2 'FAIL: a stale photo-meal form must provide a visible recovery path beside its disabled action'; exit 1; }
today_active_surface="$(sed -n '/private struct TodayView/,/private var legacyBody/p' "$app_shell")"
health_active_surface="$(sed -n '/private struct HealthHomeView/,/private struct HealthMetricTile/p' "$app_shell")"
if printf '%s\n%s\n' "$today_active_surface" "$health_active_surface" | rg -q 'UnplannedMealForm\(|ActualMealLogForm\(|\.sheet\(item: \$actualMealDestination\)'; then
  print -u2 'FAIL: retired meal logging must not be presented from active Today or Health surfaces'
  exit 1
fi
rg -q 'photoSelectionGeneration' "$app_shell" || { print -u2 'FAIL: actual-meal photo selection must reject older asynchronous results after a replacement'; exit 1; }
rg -Fq 'loadPhoto(_ item: PhotosPickerItem, generation: Int, ownerID: UUID)' "$app_shell" || { print -u2 'FAIL: actual-meal photo loading must carry both selection generation and captured owner'; exit 1; }
rg -Fq 'private func mayAcceptPhoto(generation: Int, ownerID: UUID)' "$app_shell" || { print -u2 'FAIL: actual-meal photos must recheck form visibility, generation, owner and day before entering the draft'; exit 1; }
rg -q '本机资料已切换；没有保留旧资料的餐食照片。' "$app_shell" || { print -u2 'FAIL: a captured meal photo must be discarded after an owner change'; exit 1; }
rg -q 'private var hasCompleted = false' "$app_shell" || { print -u2 'FAIL: the camera delegate must resolve each capture/cancel presentation exactly once'; exit 1; }
[[ "$(rg -c 'photoReferenceToDeleteAfterReplacement' "$app_shell")" -ge 2 ]] || { print -u2 'FAIL: retained meal-data migration paths must keep private-photo cleanup'; exit 1; }
rg -q 'data\.actualMealLogs\.contains' "Sources/YouyeHealthCoach/PrivateMealPhotoStore.swift" || { print -u2 'FAIL: shared private-photo checks must include ordinary breakfast/lunch/dinner records'; exit 1; }
rg -q 'PrivateMealPhotoReferenceUsage\.isReferenced' "Sources/YouyeHealthCoach/UnplannedMeal.swift" || { print -u2 'FAIL: deleting an unplanned meal must not remove a photo referenced by another private meal record type'; exit 1; }
if rg -v '^\s*//' "$follow_along_source" | rg -qi 'URLSession|AVAssetWriter|AVCaptureMovieFileOutput|AVAssetExportSession|Data\(contentsOf:|\.write\('; then
  print -u2 'FAIL: in-app Bilibili follow-along must not add a downloader, recorder, or local file-write path'
  exit 1
fi
if rg -v '^\s*//' "$follow_along_source" | rg -q 'WKWebsiteDataStore\.default\|URLCache\.shared'; then
  print -u2 'FAIL: in-app Bilibili follow-along must not opt into persistent WebKit or URL caching'
  exit 1
fi
rg -q 'BilibiliFollowAlongNavigationPolicy' "Sources/YouyeHealthCoachRuleCheck/main.swift" || { print -u2 'FAIL: rule checks must cover in-app Bilibili host restriction'; exit 1; }
rg -q 'openExternalFollowAlong' "$app_shell" || { print -u2 'FAIL: all external Bilibili routes must use one local-camera shutdown path'; exit 1; }
rg -A12 'private func openExternalFollowAlong' "$app_shell" | rg -Fq 'guard BilibiliFollowAlongNavigationPolicy.isAllowed(url)' || { print -u2 'FAIL: external Bilibili handoff must revalidate its host at the final system boundary'; exit 1; }
rg -q '打开今天的 B 站跟练' "$app_shell" || { print -u2 'FAIL: verified Bilibili lessons need an explicit external-launch action'; exit 1; }
rg -q 'showingLocalPoseCoach = false' "$app_shell" || { print -u2 'FAIL: leaving for Bilibili must immediately end any visible live-pose session'; exit 1; }
rg -q '点“打开今天的 B 站跟练”' "DEVICE_ACCEPTANCE.md" || { print -u2 'FAIL: device acceptance must verify pose capture stops before opening an external Bilibili lesson'; exit 1; }
training_detail="$(sed -n '/private struct TrainingCardDetail/,/^private struct HealthStatusForm/p' "$app_shell")"
[[ "$(printf '%s' "$training_detail" | rg -F -c 'confirmingSynchronizedFollowAlong = true')" -eq 1 ]] || { print -u2 'FAIL: training detail must expose the synchronized follow-along start only once'; exit 1; }
[[ "$training_detail" == *'if !supportsIPhoneLivePose, plan.trainingMode == .standard && cardMatchesCurrentPlanDay'* ]] || { print -u2 'FAIL: iPhone must not show a second external video-start action beside synchronized follow-along'; exit 1; }
[[ "$(printf '%s' "$training_detail" | rg -F -c 'beginWorkoutTimer()')" -eq 3 ]] || { print -u2 'FAIL: training detail must retain direct timer, confirmed follow-along timer, and shared implementation'; exit 1; }
[[ "$training_detail" == *'Button("已固定 iPhone，开始跟练并计时") {'*'beginWorkoutTimer()'*'showingBilibiliLiveFollowAlong = true'* ]] || { print -u2 'FAIL: safe synchronized-start confirmation must start the real timer before showing the follow-along surface'; exit 1; }
[[ "$training_detail" != *'Picker("实际运动类型"'* && "$training_detail" == *'开始前不用额外填写'* ]] || { print -u2 'FAIL: training start must not ask for a second pre-timer workout classification'; exit 1; }
[[ "$training_detail" == *'if completedWorkout != nil || adaptationMessage != nil'*'DisclosureGroup("训练后反馈（可选）")'* ]] || { print -u2 'FAIL: training feedback must stay out of the pre-workout start surface'; exit 1; }
[[ "$training_detail" == *'不是逐动作识别、计数、精确角度测量或诊断'* ]] || { print -u2 'FAIL: live guidance must not overclaim per-move correction or diagnosis'; exit 1; }
[[ "$training_detail" == *'DisclosureGroup("训练说明、安全与隐私")'* ]] || { print -u2 'FAIL: course, safety, and privacy detail must stay behind one compact training-information disclosure'; exit 1; }
rg -q 'isFormalPlanDay' "Sources/YouyeHealthCoach/WatchDailyCardPayload.swift" || { print -u2 'FAIL: Watch bridge must explicitly limit its daily card to formal plan days'; exit 1; }
rg -q 'hasFormalPlanDay' "WatchApp/YouyeHealthCoachWatchApp.swift" || { print -u2 'FAIL: Watch app must reject a non-formal iPhone card'; exit 1; }
rg -q 'by: 1' "WatchApp/YouyeHealthCoachWatchApp.swift" || { print -u2 'FAIL: Watch app must promptly revalidate a received card across midnight'; exit 1; }
rg -q '清除旧日卡和本地计时入口' "DEVICE_ACCEPTANCE.md" || { print -u2 'FAIL: device acceptance must cover Watch non-formal-day invalidation'; exit 1; }

# 布局在完整 Xcode 中仍需用不同尺寸的模拟器和真机做视觉验收；这里守住会让 320pt
# 窄屏/动态字体日历退化的关键结构，避免后续把完整日期塞回 7 列单元格。
rg -q '@Environment\(\\.dynamicTypeSize\)' "$app_shell" || { print -u2 'FAIL: app shell lacks Dynamic Type-aware calendar layout'; exit 1; }
[[ "$(rg -F -c 'if dynamicTypeSize.isAccessibilitySize {' "$app_shell")" -ge 3 ]] || { print -u2 'FAIL: weekly review, food calendar, and training calendar must each provide an accessibility-size layout'; exit 1; }
rg -q 'gridCellColumns\(7\)' "$app_shell" || { print -u2 'FAIL: app shell calendar lacks full-width weekly headings'; exit 1; }
rg -q 'accessibilityHint\("点按查看当天完整日卡"\)' "$app_shell" || { print -u2 'FAIL: calendar cells lack an accessible detail hint'; exit 1; }
rg -q 'private struct FoodLibraryView' "$app_shell" || { print -u2 'FAIL: food home lacks the date-based two-month daily-card library'; exit 1; }
rg -Fq 'Label(meal.kitchenSetup, systemImage: "frying.pan")' "$app_shell" || { print -u2 'FAIL: recipe card must visibly state its actual per-meal appliance constraint'; exit 1; }
rg -q 'var visibleTimedSteps' "Sources/YouyeHealthCoach/Domain.swift" || { print -u2 'FAIL: legacy recipe steps need an explicit visible cooking-pot rendering'; exit 1; }
rg -Fq 'ForEach(Array(meal.visibleTimedSteps.enumerated())' "$app_shell" || { print -u2 'FAIL: recipe card must render the unambiguous visible cooking steps'; exit 1; }
rg -q 'every rendered recipe step must avoid an ambiguous unqualified cooking-pot label' "Sources/YouyeHealthCoachRuleCheck/main.swift" || { print -u2 'FAIL: full menu checks must cover rendered cooking-pot ambiguity'; exit 1; }
rg -q '只能使用一个电饭锅和一个电磁炉锅' "Sources/YouyeHealthCoach/RecipeCatalog.swift" || { print -u2 'FAIL: recipe audit must reject a second induction pot'; exit 1; }
rg -q 'public enum DailyMealCatalogAudit' "Sources/YouyeHealthCoach/DailyMealCatalog.swift" || { print -u2 'FAIL: daily menu needs a full blocking audit across breakfast, lunch, and dinner'; exit 1; }
rg -q 'DailyMealCatalogAudit.validate' "Sources/YouyeHealthCoachRuleCheck/main.swift" || { print -u2 'FAIL: rule checks must actually execute the blocking full daily-menu audit'; exit 1; }
rg -q 'restored health status must drop only malformed metrics' "Sources/YouyeHealthCoachRuleCheck/main.swift" || { print -u2 'FAIL: rule checks must cover malformed restored health metrics'; exit 1; }
rg -q 'restored weekly trend must discard impossible measurements' "Sources/YouyeHealthCoachRuleCheck/main.swift" || { print -u2 'FAIL: rule checks must cover malformed restored body-trend metrics'; exit 1; }
rg -q 'restored profile must discard malformed baseline and height values' "Sources/YouyeHealthCoachRuleCheck/main.swift" || { print -u2 'FAIL: rule checks must cover malformed restored profile metrics'; exit 1; }
rg -q 'malformed restored local weekly report must not be rendered' "Sources/YouyeHealthCoachRuleCheck/main.swift" || { print -u2 'FAIL: rule checks must cover malformed restored weekly-report presentation'; exit 1; }
rg -Fq '$0.authority == .automatic' "Sources/YouyeHealthCoach/CalendarDayStatus.swift" || { print -u2 'FAIL: calendar recovery status must require an automatic safety downgrade audit'; exit 1; }
rg -q 'public enum ProgramFoodBudgetPolicy' "Sources/YouyeHealthCoach/ShoppingPlan.swift" || { print -u2 'FAIL: shopping plan must distinguish the two-month food reservation from the monthly total budget'; exit 1; }
rg -q 'eightWeekReservationYuan: Decimal = 1_600' "Sources/YouyeHealthCoach/ShoppingPlan.swift" || { print -u2 'FAIL: eight-week food reservation must preserve room inside two monthly total budgets'; exit 1; }
rg -q 'ProgramFoodBudgetPolicy.guidance' "$app_shell" || { print -u2 'FAIL: shopping UI must disclose the food-reservation versus monthly-budget boundary'; exit 1; }
rg -q 'public enum WeeklyMealIngredientReference' "Sources/YouyeHealthCoach/ShoppingPlan.swift" || { print -u2 'FAIL: shopping needs a real meal-card-derived gram reference, not only grouped ingredient names'; exit 1; }
rg -q '按餐卡逐项核对克数' "$app_shell" || { print -u2 'FAIL: shopping UI must expose the meal-card-derived gram reference on demand'; exit 1; }
rg -Fq 'Label("开始逐步备餐"' "$app_shell" || { print -u2 'FAIL: every full recipe card must expose the guided prep session'; exit 1; }
rg -Fq 'MealPrepSessionView(meal: meal' "$app_shell" || { print -u2 'FAIL: the recipe action must open the guided prep session for the same meal'; exit 1; }
rg -Fq '确认已达到安全熟度？' "$app_shell" || { print -u2 'FAIL: the guided prep session must confirm doneness before completing an animal-protein recipe'; exit 1; }
rg -Fq 'returnFromBackgroundMessage' "$app_shell" || { print -u2 'FAIL: the guided prep session must surface its no-background-supervision boundary when the owner returns'; exit 1; }
rg -Fq 'safeAreaInset(edge: .bottom' "$app_shell" || { print -u2 'FAIL: guided meal-prep controls must remain visible above the safe area'; exit 1; }
rg -Fq '不会自动记录饮食，也不会估算热量' "$app_shell" || { print -u2 'FAIL: a prep timer must not imply that a meal was consumed or logged'; exit 1; }
rg -Fq 'interactiveDismissDisabled(hasStarted && !finished)' "$app_shell" || { print -u2 'FAIL: an active prep session must resist accidental interactive dismissal'; exit 1; }
rg -Fq '先关火并检查熟度' "$meal_prep_source" || { print -u2 'FAIL: the prep hard limit must prioritize turning off heat and checking doneness'; exit 1; }
rg -Fq '不要为追时间开大火' "$meal_prep_source" || { print -u2 'FAIL: a late prep step must not encourage unsafe catch-up heat'; exit 1; }
if rg -q 'URLSession|https?://|FileManager|\.write\(' "$meal_prep_source"; then
  print -u2 'FAIL: the ephemeral prep timer must not network or persist a hidden cooking history'
  exit 1
fi
rg -Fq '开始逐步备餐后，当前步骤、累计时间' "DEVICE_ACCEPTANCE.md" || { print -u2 'FAIL: device acceptance must cover the guided prep session and hard-limit behavior'; exit 1; }
rg -Fq 'Label(meal.kitchenSetup, systemImage: "frying.pan")' "$app_shell" || { print -u2 'FAIL: meal-card header must render its actual per-meal kitchen setup'; exit 1; }
rg -q '按日期查看 61 天日卡' "$app_shell" || { print -u2 'FAIL: food home must enter the 61-day plan through daily cards'; exit 1; }
rg -q 'minHeight: 52' "$app_shell" || { print -u2 'FAIL: today primary actions lack a sufficiently large touch target'; exit 1; }
rg -q 'CalendarDayStatus.resolve' "$app_shell" || { print -u2 'FAIL: meal and training calendars must use the shared day-state resolver'; exit 1; }
rg -q 'DailySkipService.toggle' "$app_shell" || { print -u2 'FAIL: today cards must let the user explicitly and reversibly skip the current day'; exit 1; }
rg -q 'case skipped' "$calendar_status_source" || { print -u2 'FAIL: shared calendar status must distinguish an explicit skip'; exit 1; }
rg -q 'case unrecorded' "$calendar_status_source" || { print -u2 'FAIL: shared calendar status must distinguish a past unrecorded day from a failure'; exit 1; }
rg -q '过去未记录' "$calendar_status_source" || { print -u2 'FAIL: calendar must use neutral past-unrecorded wording'; exit 1; }
rg -q 'skippedAt' "Sources/YouyeHealthCoach/Privacy.swift" || { print -u2 'FAIL: explicit skips must be privately persisted with migration support'; exit 1; }
rg -q 'TodayFeature.canComplete' "$app_shell" || { print -u2 'FAIL: daily card must gate check-ins to the current day'; exit 1; }
rg -Fq 'nextDate(' "$app_shell" || { print -u2 'FAIL: an open iPhone app must refresh its day card at the next local date boundary'; exit 1; }
rg -q 'cardMatchesCurrentPlanDay' "$app_shell" || { print -u2 'FAIL: an old training detail must not write feedback into a refreshed day card'; exit 1; }
rg -Fq 'try CoachPrivateStorage.saveLastOwnerData(result.data)' "$app_shell" || { print -u2 'FAIL: training feedback must persist its resulting private state before the visible card changes'; exit 1; }
rg -q '训练反馈暂未保存；今天的训练卡没有改变' "$app_shell" || { print -u2 'FAIL: failed training-feedback saves must not falsely switch to recovery'; exit 1; }
rg -q '日期已切换：这张旧训练卡不能再开始新计时' "$app_shell" || { print -u2 'FAIL: stale training detail must visibly block a new actual timer after midnight'; exit 1; }
rg -q 'refreshDisplayedPlanAfterPrivateChange' "$app_shell" || { print -u2 'FAIL: app shell must immediately refresh its daily card after private plan-state changes'; exit 1; }
rg -Fq 'MealSubstitutionService.appliedPlan(for: basePlan, in: data)' "$app_shell" || { print -u2 'FAIL: displayed daily card must rebuild confirmed substitutions after calendar-detail changes'; exit 1; }
rg -Fq 'guard canComplete(plan' "Sources/YouyeHealthCoach/TodayFeature.swift" || { print -u2 'FAIL: completion logic must reject historical and future day writes'; exit 1; }
rg -Fq 'TodayFeature.canComplete(plan, at: date' "Sources/YouyeHealthCoach/MealSubstitution.swift" || { print -u2 'FAIL: meal substitution must reject historical and future day writes'; exit 1; }
rg -q 'Section\("今天临时变化"\)' "$app_shell" || { print -u2 'FAIL: daily workflow lacks a clear food/status adjustment entry'; exit 1; }
rg -q 'private struct MealSubstitutionReview' "$app_shell" || { print -u2 'FAIL: meal substitution lacks a pre-confirmation comparison screen'; exit 1; }
rg -q '查看变更预览' "$app_shell" || { print -u2 'FAIL: meal substitution must preview before confirmation'; exit 1; }
rg -q '拍摄家中食材' "$app_shell" || { print -u2 'FAIL: meal substitution must provide an owner-initiated food-camera entry'; exit 1; }
rg -q '从照片中选择家中食材' "$app_shell" || { print -u2 'FAIL: meal substitution must retain a private ingredient-photo entry'; exit 1; }
rg -q '请按照片自己确认并补全食材与克数' "$app_shell" || { print -u2 'FAIL: ingredient photo flow must require user confirmation rather than invent recognition'; exit 1; }
rg -q 'isFormVisible' "$app_shell" || { print -u2 'FAIL: ingredient photo picker must clean a late asynchronous save after cancellation'; exit 1; }
rg -q 'ingredientPhotoLoadGeneration' "$app_shell" || { print -u2 'FAIL: ingredient photo picker must reject an older asynchronous selection finishing after a newer photo'; exit 1; }
rg -q '移除待确认照片' "$app_shell" || { print -u2 'FAIL: ingredient-photo flow must let the owner explicitly continue with measured text only'; exit 1; }
rg -q '移除所选照片，仅记录文字' "$app_shell" || { print -u2 'FAIL: unplanned-meal photo flow must let the owner explicitly continue with text only'; exit 1; }
rg -q 'localIngredientPhotoReference' "Sources/YouyeHealthCoach/MealSubstitution.swift" || { print -u2 'FAIL: confirmed substitution must retain an optional private ingredient-photo reference'; exit 1; }
rg -q 'revokeLatest' "Sources/YouyeHealthCoach/MealSubstitution.swift" || { print -u2 'FAIL: confirmed substitution needs a same-day reversible path'; exit 1; }
rg -q '撤回这次' "$app_shell" || { print -u2 'FAIL: food UI must expose a same-day substitution reversal action'; exit 1; }
rg -q 'stageReferencedPhotosForDeletion' "$app_shell" || { print -u2 'FAIL: substitution reversal must stage its private photo before committing the record change'; exit 1; }
rg -q 'restoreStagedReferencedPhotos' "$app_shell" || { print -u2 'FAIL: substitution reversal must restore a staged private photo when the record save fails'; exit 1; }
rg -q 'photoIsReferencedElsewhere' "Sources/YouyeHealthCoach/MealSubstitution.swift" || { print -u2 'FAIL: substitution reversal must retain photos shared by another private record'; exit 1; }
rg -q '额外加餐后的下一步' "$app_shell" || { print -u2 'FAIL: today screen lacks extra-meal return-to-plan guidance'; exit 1; }
rg -Fq 'Section("当天真实记录")' "$app_shell" || { print -u2 'FAIL: past daily cards must expose saved actual meals and health status'; exit 1; }
rg -Fq 'Section("本月支出流水")' "$app_shell" || { print -u2 'FAIL: the budget screen must expose saved receipt history'; exit 1; }
rg -Fq 'Section("从钱迹导入")' "$app_shell" || { print -u2 'FAIL: the budget screen must expose the owner-initiated QianJi import entry'; exit 1; }
rg -Fq '.fileImporter(' "$app_shell" || { print -u2 'FAIL: QianJi import must use an owner-selected local file'; exit 1; }
rg -Fq 'startAccessingSecurityScopedResource' "$app_shell" || { print -u2 'FAIL: the selected QianJi file must be read inside its security-scoped access window'; exit 1; }
rg -Fq 'BudgetImportPreviewSheet' "$app_shell" || { print -u2 'FAIL: QianJi expenses must be previewed before any budget write'; exit 1; }
rg -Fq '导入保存失败；整批记录已回滚' "$app_shell" || { print -u2 'FAIL: QianJi import must disclose atomic rollback when durable save fails'; exit 1; }
rg -Fq 'QianJiBudgetImport.isDuplicate' "$app_shell" || { print -u2 'FAIL: QianJi import must de-duplicate before saving'; exit 1; }
rg -Fq 'import CoreXLSX' "$budget_import_source" || { print -u2 'FAIL: XLSX import must use the audited read-only parser dependency'; exit 1; }
rg -Fq 'targetMonthKey' "$budget_import_source" || { print -u2 'FAIL: QianJi import must scope preview rows to the selected month'; exit 1; }
if rg -q 'URLSession|https?://' "$budget_import_source"; then
  print -u2 'FAIL: local QianJi import must not upload or fetch budget data'
  exit 1
fi
rg -Fq 'import ZIPFoundation' "$health_export_source" || { print -u2 'FAIL: Apple Health ZIP import must use the audited local archive reader'; exit 1; }
rg -Fq 'maximumArchiveBytes: Int64 = 512' "$health_export_source" || { print -u2 'FAIL: Apple Health ZIP import must cap the selected archive before decompression'; exit 1; }
rg -Fq 'maximumXMLBytes: UInt64 = 1_024' "$health_export_source" || { print -u2 'FAIL: Apple Health ZIP import must cap the uncompressed XML entry'; exit 1; }
rg -Fq 'parser.shouldResolveExternalEntities = false' "$health_export_source" || { print -u2 'FAIL: Apple Health XML import must disable external entities'; exit 1; }
rg -Fq 'defer { try? fileManager.removeItem(at: temporaryDirectory) }' "$health_export_source" || { print -u2 'FAIL: Apple Health XML import must delete temporary raw data on every return path'; exit 1; }
rg -Fq 'FileProtectionType.complete' "$health_export_source" || { print -u2 'FAIL: temporary Apple Health XML must use complete iOS file protection'; exit 1; }
rg -Fq 'AppleHealthWeightAdoption.adopting' "$app_shell" || { print -u2 'FAIL: Apple Health export weight must pass through the explicit idempotent adoption service'; exit 1; }
rg -Fq '确认采用这条体重' "$app_shell" || { print -u2 'FAIL: Apple Health export preview must require a separate weight confirmation'; exit 1; }
rg -Fq '历史导出' "$app_shell" || { print -u2 'FAIL: imported Apple Health summaries must remain visibly historical'; exit 1; }
if rg -q 'URLSession|https?://' "$health_export_source"; then
  print -u2 'FAIL: local Apple Health export import must not upload or fetch health data'
  exit 1
fi
rg -Fq 'CoreXLSX 0.14.2' "$dependency_review" || { print -u2 'FAIL: dependency review must document the XLSX parser version and boundary'; exit 1; }
rg -Fq 'ZIPFoundation 0.9.20' "$dependency_review" || { print -u2 'FAIL: dependency review must document the Apple Health ZIP parser version and boundary'; exit 1; }
rg -Fq 'Calendar.current.isDate(planDate, inSameDayAs: .now)' "$app_shell" || { print -u2 'FAIL: a meal form opened before midnight must not write into a later day'; exit 1; }
rg -q 'PrivatePendingPhotoPreview' "$app_shell" || { print -u2 'FAIL: a pending meal photo must be reviewable before saving'; exit 1; }
rg -q 'mealPhotoSelectionGeneration' "$app_shell" || { print -u2 'FAIL: unplanned-meal photo loading must reject stale selection results'; exit 1; }
rg -q '这不是全天总摄入，也不代表已超标' "$app_shell" || { print -u2 'FAIL: unplanned-meal summary must not be presented as daily total intake or a confirmed overage'; exit 1; }
rg -q 'estimateBasis' "$app_shell" || { print -u2 'FAIL: unplanned-meal UI must disclose the estimate basis'; exit 1; }
if printf '%s\n%s\n' "$today_active_surface" "$health_active_surface" | rg -q 'UnplannedMealDeletionService\.prepareDeletion|删除这条记录'; then
  print -u2 'FAIL: retired unplanned-meal records must not expose deletion actions from active surfaces'
  exit 1
fi
rg -q 'public enum UnplannedMealDeletionService' "Sources/YouyeHealthCoach/UnplannedMeal.swift" || { print -u2 'FAIL: retained legacy unplanned meals need a migration-safe deletion service'; exit 1; }
rg -q 'Prevent an in-flight PhotosPicker transfer' "$app_shell" || { print -u2 'FAIL: unplanned-meal photo selection must not survive a cancelled sheet'; exit 1; }
rg -q 'isSaving' "$app_shell" || { print -u2 'FAIL: unplanned-meal save must lock one visible photo/log submission against double taps'; exit 1; }
rg -q 'isConfirmingSubstitution' "$app_shell" || { print -u2 'FAIL: ingredient substitution confirmation must lock one photo/card submission against double taps'; exit 1; }
rg -q '正在写入…' "$app_shell" || { print -u2 'FAIL: ingredient substitution must visibly acknowledge an in-progress private write'; exit 1; }
rg -q '今天已切换恢复版' "$app_shell" || { print -u2 'FAIL: today screen lacks recovery-day action guidance'; exit 1; }
rg -Fq 'DisclosureGroup("查看恢复边界")' "$app_shell" || { print -u2 'FAIL: recovery detail must keep secondary boundaries available without competing with the recovery action'; exit 1; }
rg -q '恢复日饮食' "$app_shell" || { print -u2 'FAIL: food screen lacks recovery-day meal guidance'; exit 1; }
rg -q 'RecoveryDaySupportService.make' "$app_shell" || { print -u2 'FAIL: food and training screens must use the shared recovery-day guidance'; exit 1; }
rg -q 'PlanChangeAuditService.explanation' "$app_shell" || { print -u2 'FAIL: plan-change UI must explain why safety records are not directly reverted'; exit 1; }
rg -q 'public enum PlanChangeAuditService' "Sources/YouyeHealthCoach/HealthCheckIn.swift" || { print -u2 'FAIL: plan-change audit needs an explicit recovery-reversal safety boundary'; exit 1; }
rg -q '不因恢复日减餐' "Sources/YouyeHealthCoach/HealthCheckIn.swift" || { print -u2 'FAIL: recovery-day support must forbid compensatory food restriction'; exit 1; }
rg -q 'public enum VoluntaryWeeklyReportPeriod' "Sources/YouyeHealthCoach/Privacy.swift" || { print -u2 'FAIL: future external weekly reports must use a minimal relative-period contract'; exit 1; }
rg -q 'rather than an exact calendar date' "Sources/YouyeHealthCoach/Privacy.swift" || { print -u2 'FAIL: future external weekly reports must not add an unnecessary week timestamp'; exit 1; }
rg -q '已记录疼痛或受伤：今天不测试疼痛动作' "Sources/YouyeHealthCoach/HealthCheckIn.swift" || { print -u2 'FAIL: pain state must provide a same-day execution boundary'; exit 1; }
rg -q '已记录生病症状：今天以休息、补液和规律进食为先' "Sources/YouyeHealthCoach/HealthCheckIn.swift" || { print -u2 'FAIL: illness state must provide non-punitive food and rest support'; exit 1; }
rg -Fq 'let onSave: (HealthStatus, UUID, UUID) -> String?' "$app_shell" || { print -u2 'FAIL: health-status form must wait for a durable caller result and carry its captured owner before closing'; exit 1; }
[[ "$(rg -F -c 'try CoachPrivateStorage.saveLastOwnerData(result.data)' "$app_shell")" -ge 4 ]] || { print -u2 'FAIL: every health-status entry path must persist a result before changing the visible day card'; exit 1; }
rg -q '状态暂未保存；今天的训练与餐卡没有改变' "$app_shell" || { print -u2 'FAIL: failed health-status saves must truthfully retain the existing day card'; exit 1; }
rg -q '医生/药品说明优先' "Sources/YouyeHealthCoach/HealthCheckIn.swift" || { print -u2 'FAIL: medication state must defer to clinician guidance'; exit 1; }
rg -q '饥饿/夜宵冲动' "Sources/YouyeHealthCoach/HealthCheckIn.swift" || { print -u2 'FAIL: daily state summary must surface hunger signal'; exit 1; }
rg -q 'private struct WeeklyExecutionDayCard' "$app_shell" || { print -u2 'FAIL: health page lacks weekly execution trajectory cards'; exit 1; }
rg -q 'private struct WeeklyExecutionTrajectory' "$app_shell" || { print -u2 'FAIL: health page needs a Dynamic Type-safe weekly trajectory container'; exit 1; }
rg -q 'dynamicTypeSize\.isAccessibilitySize' "$app_shell" || { print -u2 'FAIL: weekly trajectory must switch away from a seven-cell row at accessibility text sizes'; exit 1; }
rg -q '本周执行轨迹' "$app_shell" || { print -u2 'FAIL: weekly review lacks a visible completion trajectory'; exit 1; }
rg -q '图标、文字与低饱和色共同表达状态' "$app_shell" || { print -u2 'FAIL: Apple calendar legend must not rely on color alone'; exit 1; }
rg -q 'executionDays' "$weekly_review_source" || { print -u2 'FAIL: weekly review model lacks execution trajectory data'; exit 1; }
rg -q 'executionCompletion' "Sources/YouyeHealthCoach/Privacy.swift" || { print -u2 'FAIL: older actual meal logs need a read-only execution reconciliation path'; exit 1; }
rg -q 'executionCompletion' "$calendar_status_source" || { print -u2 'FAIL: calendar status must surface older actual meal evidence when no completion snapshot exists'; exit 1; }
rg -q 'recordedMealEntries' "$weekly_review_source" || { print -u2 'FAIL: weekly review must expose actual meal records separately from the three-pillar score'; exit 1; }
rg -q '餐食记录已关闭' "$app_shell" || { print -u2 'FAIL: weekly review UI must state that retired meal logging is closed'; exit 1; }
rg -q 'completedTrainingFeedbackDays' "$weekly_review_source" || { print -u2 'FAIL: weekly review must expose explicit completed-training feedback evidence separately'; exit 1; }
rg -q '明确完成训练反馈' "$app_shell" || { print -u2 'FAIL: weekly review UI must visibly distinguish explicit completed-training feedback'; exit 1; }
rg -q 'a local elapsed-time draft alone must never be treated as completed training' "Sources/YouyeHealthCoachRuleCheck/main.swift" || { print -u2 'FAIL: rule checks must prevent timer drafts from becoming completed training'; exit 1; }
rg -q '非计划日' "$weekly_review_source" || { print -u2 'FAIL: weekly trajectory must distinguish non-plan days'; exit 1; }
rg -Fq 'PlanSchedule.dayIndex(for: $0.date, calendar: calendar) != nil' "$weekly_review_source" || { print -u2 'FAIL: weekly health-state trends must exclude preparation and post-program days'; exit 1; }
rg -Fq 'PlanSchedule.dayIndex(for: $0.date, calendar: calendar) != nil' "$program_completion_source" || { print -u2 'FAIL: phase assessment health-state trends must explicitly include only formal plan days'; exit 1; }
rg -q 'HealthStatusHistoryAggregation\.dailyAggregates' "$weekly_review_source" || { print -u2 'FAIL: weekly sleep must use one aggregated health point per local day'; exit 1; }
rg -q 'HealthStatusHistoryAggregation\.dailyAggregates' "$program_completion_source" || { print -u2 'FAIL: program sleep trend must not weight repeated same-day check-ins as separate nights'; exit 1; }
rg -q "today's status summary must show the corrected latest sleep" "Sources/YouyeHealthCoachRuleCheck/main.swift" || { print -u2 'FAIL: rule checks must cover corrected same-day health values without erasing safety'; exit 1; }
rg -q '阶段外私有记录不得进入睡眠均值' "DEVICE_ACCEPTANCE.md" || { print -u2 'FAIL: device acceptance must cover weekly and phase-review status scope'; exit 1; }
rg -Fq '&& $0.date < asOfEnd' "$weekly_review_source" || { print -u2 'FAIL: weekly review must exclude future health records from its guidance'; exit 1; }
rg -Fq 'recordedAt < asOfEnd' "$weekly_review_source" || { print -u2 'FAIL: weekly review must exclude future trend records from its guidance'; exit 1; }
rg -Fq 'asOf date: Date?' "$program_completion_source" || { print -u2 'FAIL: phase assessment must take an explicit as-of boundary'; exit 1; }
rg -q '未来日期的完成、睡眠/皮肤状态或体重腰围趋势记录' "DEVICE_ACCEPTANCE.md" || { print -u2 'FAIL: device acceptance must cover future-record filtering in reviews'; exit 1; }
rg -q 'preparationChecklist' "$weekly_review_source" || { print -u2 'FAIL: weekly review lacks a manual next-week preparation checklist'; exit 1; }
rg -q '下周准备清单（仅供你手动执行）' "$app_shell" || { print -u2 'FAIL: health page must label weekly checklist as manual'; exit 1; }
rg -q '不会改你的提醒时间、餐卡、热量、训练或周结构' "$app_shell" || { print -u2 'FAIL: weekly checklist must state its no-auto-change boundary'; exit 1; }
rg -q 'stageReferencedPhotosForDeletion' "Sources/YouyeHealthCoach/LocalDataDeletion.swift" || { print -u2 'FAIL: full deletion must stage only the deleted profile’s referenced photos'; exit 1; }
if rg -q 'import HealthKit|HKHealthStore|HKWorkout' "Sources/YouyeHealthCoach/LocalDataDeletion.swift"; then
  print -u2 'FAIL: local profile deletion must never access, delete, or modify Apple Health records'
  exit 1
fi
rg -q 'weeklyBodyCheckIns' "$app_shell" || { print -u2 'FAIL: local delete explanation must cover weekly trend data'; exit 1; }
rg -q '其他独立资料的照片' "$app_shell" || { print -u2 'FAIL: local delete confirmation must state independent-profile photo isolation'; exit 1; }
rg -q 'explicitlySkippedPlanDays' "Sources/YouyeHealthCoach/WeeklyReview.swift" || { print -u2 'FAIL: weekly review must distinguish explicit skips from missing records'; exit 1; }
rg -q '明确跳过不等于忘记' "$app_shell" || { print -u2 'FAIL: weekly review UI must explain explicit-skip completion semantics'; exit 1; }
rg -q '保存本机个人资料' "$app_shell" || { print -u2 'FAIL: profile UI must provide a private personal-routine save action'; exit 1; }
rg -q 'workSchedule' "Sources/YouyeHealthCoach/Privacy.swift" || { print -u2 'FAIL: private profile must retain work-schedule preference'; exit 1; }
rg -q 'foodPreferences' "Sources/YouyeHealthCoach/Privacy.swift" || { print -u2 'FAIL: private profile must retain dietary preferences'; exit 1; }
rg -q '待确认的个性化方向' "$app_shell" || { print -u2 'FAIL: profile UI must expose reviewable personalization directions'; exit 1; }
rg -q 'PersonalizationAdvisor.proposals' "$app_shell" || { print -u2 'FAIL: profile UI must derive proposals from the private profile'; exit 1; }
rg -q 'never mutates a meal, training load, calorie framework' "$personalization_source" || { print -u2 'FAIL: personalization logic must document its no-silent-change boundary'; exit 1; }
rg -q '不会自动改菜单' "$personalization_source" || { print -u2 'FAIL: kitchen personalization must require confirmation before a meal change'; exit 1; }
rg -q '现在先做这一件' "$app_shell" || { print -u2 'FAIL: today home must surface one immediate next step before the full daily card'; exit 1; }
rg -q 'TodayNextStepAdvisor.recommend' "$app_shell" || { print -u2 'FAIL: today home must derive the next step from completion state'; exit 1; }
rg -q 'neither records completion nor changes meals' "$today_next_step_source" || { print -u2 'FAIL: next-step advisor must preserve the no-silent-change boundary'; exit 1; }
rg -q '不补练、不节食' "$today_next_step_source" || { print -u2 'FAIL: next-step skip guidance must stay non-punitive'; exit 1; }
rg -q 'breakfastWaivedForLateWake' "Sources/YouyeHealthCoach/Privacy.swift" || { print -u2 'FAIL: late wake must preserve a truthful non-breakfast-debt acknowledgement'; exit 1; }
rg -q '早餐｜晚起无需补' "Sources/YouyeHealthCoach/TodayFeature.swift" || { print -u2 'FAIL: today UI must visibly distinguish late-wake breakfast from a completed meal'; exit 1; }
rg -q 'order = \[\.lunch, \.dinner\]' "$today_next_step_source" || { print -u2 'FAIL: late-wake next-step ordering must exclude breakfast debt'; exit 1; }
rg -q 'DailyRoutineSchedule' "Sources/YouyeHealthCoach/Privacy.swift" || { print -u2 'FAIL: private profile must retain an optional user-owned routine schedule'; exit 1; }
rg -Fq 'if let lastPersistedPrivateData {' "$app_shell" || { print -u2 'FAIL: a failed pre-notification private save must restore the last durable profile'; exit 1; }
rg -Fq 'load()' "$app_shell" || { print -u2 'FAIL: routine settings must refresh its visible controls after a failed durable save'; exit 1; }
rg -Fq 'center.removePendingNotificationRequests(withIdentifiers: identifiers)' "$reminder_source" || { print -u2 'FAIL: reminder synchronization must clear partial requests after an add failure'; exit 1; }
rg -Fq 'center.removeDeliveredNotifications(withIdentifiers: identifiers)' "$reminder_source" || { print -u2 'FAIL: reminder cleanup must remove this App delivered reminders as well as pending requests'; exit 1; }
rg -Fq 'let preferences = privateData.profile.dailyReminderPreferences ?? DailyReminderPreferences()' "$app_shell" || { print -u2 'FAIL: routine settings must restore reminder preferences even when its schedule is currently disabled'; exit 1; }
rg -q 'NearbyOfferPreferences' "Sources/YouyeHealthCoach/Privacy.swift" || { print -u2 'FAIL: private profile must retain legacy nearby-offer preferences without mutating existing data'; exit 1; }
rg -q 'schedule: privateData.profile.dailyRoutineSchedule' "$app_shell" || { print -u2 'FAIL: today next-step UI must consume the owner routine schedule'; exit 1; }
rg -q '按我的时间表推荐下一件事' "$app_shell" || { print -u2 'FAIL: Apple profile UI must expose routine scheduling'; exit 1; }
rg -q 'TodayStatusQuickChoice' "$app_shell" || { print -u2 'FAIL: today health status must expose direct selectable state choices'; exit 1; }
rg -q '经期明显不适会让今天切换恢复版' "$app_shell" || { print -u2 'FAIL: menstrual discomfort option must disclose its protective training effect'; exit 1; }
rg -q 'NearbyOptionsView' "$app_shell" || { print -u2 'FAIL: nearby preferences need a usable owner-initiated place-search view'; exit 1; }
nearby_view="$(sed -n '/private struct NearbyOptionsView/,/private struct NearbyPlaceSearch/p' "$app_shell")"
[[ "$nearby_view" != *'你的比价线'* && "$nearby_view" != *'商超至少省'* && "$nearby_view" != *'游泳单次不高于'* ]] || { print -u2 'FAIL: frozen nearby comparison must not expose misleading threshold editors'; exit 1; }
rg -q 'NearbyPriceCompareView' "$app_shell" || { print -u2 'FAIL: nearby preferences must provide a manual two-price comparison'; exit 1; }
rg -q '再加一家' "$app_shell" || { print -u2 'FAIL: manual price comparison must support multiple nearby candidates'; exit 1; }
rg -q '自动排序并比较' "$app_shell" || { print -u2 'FAIL: multiple nearby candidates must be ranked automatically after manual entry'; exit 1; }
rg -Fq 'ForEach(Array(validCandidates.enumerated())' "$app_shell" || { print -u2 'FAIL: automatic nearby comparison must show the complete ranked candidate list'; exit 1; }
rg -q '价格仅用于这次屏幕上的计算：不联网、不保存、不领券或下单。' "$app_shell" || { print -u2 'FAIL: manual price comparison must disclose its local-only boundary'; exit 1; }
rg -q '附近去处' "$app_shell" || { print -u2 'FAIL: nearby place search must have a discoverable settings entry'; exit 1; }
rg -q 'maps.apple.com' "$nearby_offer_policy_source" || { print -u2 'FAIL: nearby preferences must offer an explicit manual Apple Maps handoff'; exit 1; }
rg -q '点按后才交给 Apple 地图搜索' "$app_shell" || { print -u2 'FAIL: nearby map handoff must disclose its explicit-action boundary'; exit 1; }
rg -q '按当前位置更新' "$app_shell" || { print -u2 'FAIL: nearby search must provide a current-location update action'; exit 1; }
rg -q '不保存、不上传、不持续追踪' "$app_shell" || { print -u2 'FAIL: nearby current-location UI must disclose its short-lived local boundary'; exit 1; }
! rg -q '不自动定位' "$app_shell" || { print -u2 'FAIL: discoverable nearby entry must not contradict the current-location feature'; exit 1; }
if rg -q 'NearbyOfferSettingsView|附近优惠偏好|保存优惠偏好|附近服务核验状态' "$app_shell"; then
  print -u2 'FAIL: legacy non-functional nearby-offer UI must remain removed'
  exit 1
fi
rg -q '附近搜索地点（小区/地铁站，可留空）' "$app_shell" || { print -u2 'FAIL: Apple profile UI must request only a coarse nearby-search location'; exit 1; }
rg -q 'public enum NearbyOfferPolicy' "$nearby_offer_policy_source" || { print -u2 'FAIL: nearby offers need an evidence and owner-preference policy gate'; exit 1; }
rg -q 'maximumFreshness' "$nearby_offer_policy_source" || { print -u2 'FAIL: nearby offer policy must expire stale verification'; exit 1; }
rg -q 'public enum NearbyOfferRequestContext' "$nearby_offer_policy_source" || { print -u2 'FAIL: nearby offer policy must carry explicit owner-request context'; exit 1; }
rg -q 'explicitDeliveryRequest' "$nearby_offer_policy_source" || { print -u2 'FAIL: delivery offers must require a separate explicit request'; exit 1; }
rg -Fq 'guard requestContext.authorizes(offer.kind)' "$nearby_offer_policy_source" || { print -u2 'FAIL: nearby offer eligibility must enforce the owner-request context before preferences'; exit 1; }
rg -q 'never performs location lookup' "$nearby_offer_policy_source" || { print -u2 'FAIL: nearby offer policy must document that it has no location or purchase side effects'; exit 1; }
rg -q '作息时间表、模糊地点和优惠偏好' "$app_shell" || { print -u2 'FAIL: private-data deletion must disclose routine, coarse location, and offer-preference removal'; exit 1; }
rg -q 'public struct ProgramCompletionReview' "$program_completion_source" || { print -u2 'FAIL: phase completion needs an auditable read-only assessment model'; exit 1; }
rg -q '未记录不等于失败' "$program_completion_source" || { print -u2 'FAIL: phase assessment must not label missing records as failure'; exit 1; }
rg -q '不新开 56 天计划' "$program_completion_source" || { print -u2 'FAIL: phase assessment must keep the next programme confirmation-gated'; exit 1; }
rg -q '阶段评估｜只读' "$app_shell" || { print -u2 'FAIL: Apple phase-completion UI must visibly distinguish its assessment from a new plan'; exit 1; }
rg -Fq 'if PlanSchedule.hasEnded(on: date) { return ProgramCompletionPlan.make(date: date) }' "$app_shell" || { print -u2 'FAIL: app shell must route post-program dates to completion review instead of fabricating a daily card'; exit 1; }
rg -q 'private struct ProgramCompletionView' "$app_shell" || { print -u2 'FAIL: native apps must retain a dedicated read-only phase-completion view'; exit 1; }
rg -q '下一阶段不自动开始' "$app_shell" || { print -u2 'FAIL: completion UI must explicitly prohibit automatic next-stage creation'; exit 1; }
rg -q 'public struct MealCompletionAction' "Sources/YouyeHealthCoach/TodayFeature.swift" || { print -u2 'FAIL: daily food must model each meal as its own execution action'; exit 1; }
rg -q 'completingMeal' "Sources/YouyeHealthCoach/TodayFeature.swift" || { print -u2 'FAIL: daily food must persist separate meal completion'; exit 1; }
rg -q 'markingCompleted' "Sources/YouyeHealthCoach/TodayFeature.swift" || { print -u2 'FAIL: explicit feedback needs an idempotent daily completion acknowledgement'; exit 1; }
rg -Fq 'TodayFeature.markingCompleted(.move' "Sources/YouyeHealthCoach/TrainingFeedback.swift" || { print -u2 'FAIL: explicit completed training feedback must sync today movement completion'; exit 1; }
rg -q 'feedbackSubmissionID' "$app_shell" || { print -u2 'FAIL: training feedback UI must use a stable per-submission id to prevent accidental duplicate records'; exit 1; }
rg -q '@State private var completed = false' "$app_shell" || { print -u2 'FAIL: training feedback completion must be opt-in rather than preselected'; exit 1; }
rg -q '恢复版已锁住原训练的新计时' "$app_shell" || { print -u2 'FAIL: a recovery downgrade must visibly lock a stale standard-training timer'; exit 1; }
rg -q 'saveTrainingFeedback' "$app_shell" || { print -u2 'FAIL: training feedback needs one recovery-aware submission path'; exit 1; }
rg -Fq 'data.trainingFeedback.first(where: { $0.id == feedback.id })' "Sources/YouyeHealthCoach/TrainingFeedback.swift" || { print -u2 'FAIL: training feedback service must deduplicate an identical submission id'; exit 1; }
rg -Fq 'submissionID: UUID' "Sources/YouyeHealthCoach/HealthCheckIn.swift" || { print -u2 'FAIL: health-status submission needs a stable id for safe retries'; exit 1; }
rg -Fq 'first(where: { $0.id == submissionID })' "Sources/YouyeHealthCoach/HealthCheckIn.swift" || { print -u2 'FAIL: health-status service must deduplicate an identical submission id'; exit 1; }
rg -q '启动准备日与阶段评估日允许保留本人主动记录的状态' "Sources/YouyeHealthCoach/HealthCheckIn.swift" || { print -u2 'FAIL: non-formal days need an explicit health-status audit boundary'; exit 1; }
rg -Fq 'PlanSchedule.dayIndex(for: plan.date, calendar: calendar) != nil' "Sources/YouyeHealthCoach/HealthCheckIn.swift" || { print -u2 'FAIL: HealthKit safety changes must be gated to formal plan days'; exit 1; }
rg -q '当前不是第 1–56 天：摘要仅供查看' "$app_shell" || { print -u2 'FAIL: Health UI must explain its non-formal-day boundary'; exit 1; }
rg -q 'through end: Date' "Sources/YouyeHealthCoach/HealthKitIntegration.swift" || { print -u2 'FAIL: HealthKit quantity reads must use the summary captured end time rather than a later wall-clock call'; exit 1; }
rg -Fq 'let end = min(nominalEnd, now)' "Sources/YouyeHealthCoach/HealthKitIntegration.swift" || { print -u2 'FAIL: morning sleep summary must not include time after the captured read instant'; exit 1; }
rg -q '上午读取 Apple 健康摘要时' "DEVICE_ACCEPTANCE.md" || { print -u2 'FAIL: device acceptance must cover HealthKit captured-time and morning sleep boundaries'; exit 1; }
rg -Fq 'HealthStatusForm(planDate: plan.date, isFormalPlanDay: isFormalPlanDay, ownerID: privateData.profile.id)' "$app_shell" || { print -u2 'FAIL: health-status form must receive the formal-plan-day context, opening date, and captured local owner'; exit 1; }
rg -q '不创建训练打卡、恢复退阶或新计划' "$app_shell" || { print -u2 'FAIL: non-formal health-status UI must disclose its no-plan-change boundary'; exit 1; }
rg -q '启动准备阶段，或第 56 天后的阶段评估日保存疼痛、短睡眠' "DEVICE_ACCEPTANCE.md" || { print -u2 'FAIL: device acceptance must cover non-formal-day HealthKit safety'; exit 1; }
rg -q '启动准备日与阶段评估日不显示可保存的训练反馈' "DEVICE_ACCEPTANCE.md" || { print -u2 'FAIL: device acceptance must cover non-formal-day training feedback safety'; exit 1; }
rg -q '8 周日历只对第 1–56 天使用完成／恢复状态色' "DEVICE_ACCEPTANCE.md" || { print -u2 'FAIL: device acceptance must cover non-formal-day calendar state safety'; exit 1; }
rg -q 'breakfastCompleted' "Sources/YouyeHealthCoach/Privacy.swift" || { print -u2 'FAIL: private completion data must retain breakfast completion'; exit 1; }
rg -q 'MealCompletionRow' "$app_shell" || { print -u2 'FAIL: today UI must render separately tappable meal rows'; exit 1; }
rg -q '已标记完成，不能再重排' "Sources/YouyeHealthCoach/MealSubstitution.swift" || { print -u2 'FAIL: meal substitutions must not retroactively replace completed meals'; exit 1; }
rg -q '已标记完成的餐次不能重排' "$app_shell" || { print -u2 'FAIL: food UI must explain the completed-meal replacement boundary'; exit 1; }
rg -q 'public enum ShoppingPurchaseState' "Sources/YouyeHealthCoach/ShoppingPlan.swift" || { print -u2 'FAIL: shopping completion state must be scoped to its program week'; exit 1; }
rg -Fq 'week-\(weekNumber)' "Sources/YouyeHealthCoach/ShoppingPlan.swift" || { print -u2 'FAIL: shopping keys must include the plan week'; exit 1; }
rg -Fq 'keys.contains(plan.stableKey(for: item))' "Sources/YouyeHealthCoach/ShoppingPlan.swift" || { print -u2 'FAIL: ambiguous legacy shopping marks must not claim a current-week purchase'; exit 1; }
rg -q 'ShoppingPurchaseState.toggled' "$app_shell" || { print -u2 'FAIL: shopping UI must use week-scoped purchase toggles'; exit 1; }
rg -q 'private enum ShoppingListFilter' "$app_shell" || { print -u2 'FAIL: shopping overview must expose explicit status filters'; exit 1; }
rg -q '快速定位周次' "$app_shell" || { print -u2 'FAIL: shopping overview must provide a direct week jump instead of forcing long scrolling'; exit 1; }
rg -Fq 'Picker("显示", selection: Binding(' "$app_shell" || { print -u2 'FAIL: each shopping week must provide a visible status filter'; exit 1; }
rg -q 'setPending\(_ item: ShoppingItem|setAtHome\(_ item: ShoppingItem|setPurchased\(_ item: ShoppingItem' "$app_shell" || { print -u2 'FAIL: shopping items must have explicit state actions'; exit 1; }
rg -Fq 'confirmedSpentYuan(' "$app_shell" || { print -u2 'FAIL: weekly shopping guidance must use date-scoped confirmed ingredient spending'; exit 1; }
rg -Fq 'during: programWeek,' "$app_shell" || { print -u2 'FAIL: weekly shopping guidance must scope confirmed ingredient spending to its program week'; exit 1; }
rg -Fq 'asOf: date' "$app_shell" || { print -u2 'FAIL: weekly shopping guidance must exclude future-dated receipts'; exit 1; }
rg -Fq 'public func confirmedSpentYuan(' "Sources/YouyeHealthCoach/Privacy.swift" || { print -u2 'FAIL: private budget data lacks a cross-month weekly spend reader'; exit 1; }
rg -Fq 'calendar.date(byAdding: .month, value: 1, to: monthCursor)' "Sources/YouyeHealthCoach/Privacy.swift" || { print -u2 'FAIL: weekly shopping totals must traverse every natural month they touch'; exit 1; }
rg -q 'a shopping week crossing months must include confirmed receipts from both monthly ledgers' "Sources/YouyeHealthCoachRuleCheck/main.swift" || { print -u2 'FAIL: rule checks must cover a cross-month shopping week'; exit 1; }
rg -q 'duplicate imported month ledgers must not double-count' "Sources/YouyeHealthCoachRuleCheck/main.swift" || { print -u2 'FAIL: rule checks must reject duplicate-month budget double counts'; exit 1; }
rg -Fq 'var seenEntryIDs = Set<UUID>()' "Sources/YouyeHealthCoach/Privacy.swift" || { print -u2 'FAIL: cross-month shopping totals must deduplicate malformed repeated receipt ids'; exit 1; }
rg -q 'duplicated receipt id across imported month ledgers must count only once' "Sources/YouyeHealthCoachRuleCheck/main.swift" || { print -u2 'FAIL: rule checks must cover repeated receipt ids across month ledgers'; exit 1; }
rg -Fq '$0.amountYuan >= 0' "Sources/YouyeHealthCoach/BudgetLedger.swift" || { print -u2 'FAIL: budget display totals must ignore malformed negative imported expenses'; exit 1; }
rg -q 'malformed imported negative expense must not inflate remaining budget' "Sources/YouyeHealthCoachRuleCheck/main.swift" || { print -u2 'FAIL: rule checks must cover malformed negative imported expenses'; exit 1; }
rg -q '合并当天所有状态的最小标签' "Sources/YouyeHealthCoach/HealthCheckIn.swift" || { print -u2 'FAIL: daily health summary must retain earlier same-day protective signals'; exit 1; }
rg -Fq 'hasProtectiveSignal: aggregate.hasProtectiveSignal' "Sources/YouyeHealthCoach/HealthCheckIn.swift" || { print -u2 'FAIL: daily health summary must use any same-day protective signal'; exit 1; }
rg -q 'purgePendingStagedDeletions' "Sources/YouyeHealthCoach/PrivateMealPhotoStore.swift" || { print -u2 'FAIL: private photo store must clean post-delete staged-photo folders'; exit 1; }
rg -q 'deleteOwnerScopedData' "Sources/YouyeHealthCoach/LocalDataDeletion.swift" || { print -u2 'FAIL: full deletion must clear an owner-scoped photo directory, including unreferenced remnants'; exit 1; }
rg -q 'isOwnerScoped' "Sources/YouyeHealthCoach/PrivateMealPhotoStore.swift" || { print -u2 'FAIL: photo deletion must distinguish owner directories from legacy shared storage'; exit 1; }
rg -q 'public enum PrivateMealPhotoMigration' "Sources/YouyeHealthCoach/PrivateMealPhotoMigration.swift" || { print -u2 'FAIL: old private meal photos need an owner-isolating migration'; exit 1; }
rg -Fq 'PrivateMealPhotoMigration.prepare' "Sources/YouyeHealthCoach/LocalStore.swift" || { print -u2 'FAIL: owner data loading must invoke old-photo migration'; exit 1; }
rg -Fq 'try store.save(migration.data)' "Sources/YouyeHealthCoach/LocalStore.swift" || { print -u2 'FAIL: migrated owner references must persist before legacy photo cleanup'; exit 1; }
rg -q 'commitLegacyCleanup' "Sources/YouyeHealthCoach/LocalStore.swift" || { print -u2 'FAIL: old photos need cleanup only after migrated owner data persists'; exit 1; }
rg -q 'dangling reference' "Sources/YouyeHealthCoach/PrivateMealPhotoMigration.swift" || { print -u2 'FAIL: migration must remove missing legacy-photo references rather than retain an inaccessible shared route'; exit 1; }
rg -q 'If a later import fails' "Sources/YouyeHealthCoach/PrivateMealPhotoMigration.swift" || { print -u2 'FAIL: a failed migration must remove owner-photo copies made before the failure'; exit 1; }
rg -q 'guard let referenceOwner = parsed.ownerID, referenceOwner == ownerID' "Sources/YouyeHealthCoach/PrivateMealPhotoStore.swift" || { print -u2 'FAIL: owner photo reads must reject legacy and cross-owner references'; exit 1; }
rg -q 'PrivateMealPhotoMigration.prepare' "Sources/YouyeHealthCoachRuleCheck/main.swift" || { print -u2 'FAIL: owner migration privacy boundary must be exercised by rule checks'; exit 1; }
rg -Fq 'legacy photo migration must reject a photo store owned by another profile' "Sources/YouyeHealthCoachRuleCheck/main.swift" || { print -u2 'FAIL: rule checks must reject a wrong-owner private photo migration'; exit 1; }
rg -Fq 'try? photoStore.restoreStagedReferencedPhotos(stagedPhotos)' "Sources/YouyeHealthCoach/LocalDataDeletion.swift" || { print -u2 'FAIL: a failed owner-data deletion must restore legacy staged photos'; exit 1; }
rg -Fq 'try? photoStore.restoreStagedDeletion(stagedDirectory)' "Sources/YouyeHealthCoach/LocalDataDeletion.swift" || { print -u2 'FAIL: a failed owner-data deletion must restore an owner-scoped photo directory'; exit 1; }
rg -q 'final removal is a continuation task' "Sources/YouyeHealthCoach/LocalDataDeletion.swift" || { print -u2 'FAIL: post-delete staged-photo cleanup must not be reported as an owner-data deletion failure'; exit 1; }
rg -q 'finish clearing only the App-private transaction folder' "Sources/YouyeHealthCoach/LocalStore.swift" || { print -u2 'FAIL: local startup must safely clean interrupted post-delete photo staging'; exit 1; }
rg -q 'public enum HealthKitAccessMessage' "Sources/YouyeHealthCoach/HealthKitIntegration.swift" || { print -u2 'FAIL: HealthKit must translate distinct access failures into truthful UI states'; exit 1; }
rg -q 'HealthKitAccessMessage.readFailure' "$app_shell" || { print -u2 'FAIL: health read UI must display specific safe failure states'; exit 1; }
rg -q 'private struct FirstRunWelcomeView' "$app_shell" || { print -u2 'FAIL: iPhone first run must explain the local-first setup before showing daily cards'; exit 1; }
rg -q 'FirstRunProfileInput' "Sources/YouyeHealthCoach/Privacy.swift" || { print -u2 'FAIL: first run needs a testable context-only profile input contract'; exit 1; }
rg -q '先认识你一点点' "$app_shell" || { print -u2 'FAIL: first run must collect compact owner execution context'; exit 1; }
rg -q '不会创建通知或把晚起记为失败' "$app_shell" || { print -u2 'FAIL: suggested routine onboarding must retain its notification and late-wake boundary'; exit 1; }
rg -q '通知与附近服务也不会在这里请求' "$app_shell" || { print -u2 'FAIL: first run must not imply automatic notification or location access'; exit 1; }
rg -q 'Apple 健康是可选的：不会在这里自动请求授权' "$app_shell" || { print -u2 'FAIL: first run must state that HealthKit authorization is not requested automatically'; exit 1; }
rg -q '实时动作提示需你之后单独开启相机；不录像、不缓存、不上传' "$app_shell" || { print -u2 'FAIL: first run must state the separate camera consent and no-recording boundary'; exit 1; }
rg -q 'TodayDailyCardHeader' "$app_shell" || { print -u2 'FAIL: today home must use the compact native daily-card summary'; exit 1; }
if rg -q 'fatalError\(' "$today_next_step_source"; then
  print -u2 'FAIL: daily next-step recommendation must not crash on an unexpected presentation enum case'
  exit 1
fi
rg -q 'struct TodayDailyCardHeader' "Sources/YouyeHealthCoach/TodayDailyCardHeader.swift" || { print -u2 'FAIL: compact native daily-card header source missing'; exit 1; }
rg -q 'ViewThatFits' "Sources/YouyeHealthCoach/TodayDailyCardHeader.swift" || { print -u2 'FAIL: daily-card header must adapt rather than clip at constrained text sizes'; exit 1; }
rg -q '今天待视频跟练' "Sources/YouyeHealthCoach/TodayDailyCardHeader.swift" || { print -u2 'FAIL: the Today header must foreground pending video follow-along'; exit 1; }
! rg -q 'private func dailyLine' "Sources/YouyeHealthCoach/TodayDailyCardHeader.swift" || { print -u2 'FAIL: Today header must not restore three meal-detail rows ahead of the training action'; exit 1; }
rg -q 'DailyMealNavigationRow' "$app_shell" || { print -u2 'FAIL: food home must use distinct native daily meal destinations'; exit 1; }
rg -q '照片未能读取；可以先仅用文字记录' "$app_shell" || { print -u2 'FAIL: failed optional meal photo reads must retain the text-only logging path'; exit 1; }
rg -q '只在本机使用 Apple Vision' "$app_shell" || { print -u2 'FAIL: unplanned meal photo UI must disclose its on-device-only candidate analysis'; exit 1; }
rg -q '保存前请核对候选，名称不同就写下你的菜名' "$app_shell" || { print -u2 'FAIL: photo calorie suggestions must keep the owner-written dish name separate from a candidate'; exit 1; }
rg -Fq 'photoSuggestedCaloriesRange: photoSuggestion?.estimatedCaloriesRange' "$app_shell" || { print -u2 'FAIL: a confirmed photo meal must retain its visible broad suggestion without requiring the owner to know calories'; exit 1; }
rg -q 'PrivateFoodPhotoAnalyzer\.analyze' "$app_shell" || { print -u2 'FAIL: meal photo selection and capture must invoke the local analyzer'; exit 1; }
rg -q 'VNClassifyImageRequest' "Sources/YouyeHealthCoach/PrivateFoodPhotoAnalysis.swift" || { print -u2 'FAIL: food photo suggestions must use the on-device Vision classifier rather than a remote upload'; exit 1; }
! rg -q 'URLSession|http://|https://' "Sources/YouyeHealthCoach/PrivateFoodPhotoAnalysis.swift" || { print -u2 'FAIL: private food photo analysis must not contain a network path'; exit 1; }
rg -Fq 'guard !matched.isEmpty else { return nil }' "Sources/YouyeHealthCoach/PrivateFoodPhotoAnalysis.swift" || { print -u2 'FAIL: non-food Vision labels must not create a generic one-tap meal candidate'; exit 1; }
! rg -Fq '餐食（品类不确定）' "Sources/YouyeHealthCoach/PrivateFoodPhotoAnalysis.swift" || { print -u2 'FAIL: an uncertain non-food label must require owner-written food text instead of becoming a candidate'; exit 1; }
rg -Fq 'requiresConservativeCalorieRange: true' "Sources/YouyeHealthCoach/PrivateFoodPhotoAnalysis.swift" || { print -u2 'FAIL: photo drink candidates must retain a broad range while sugar and toppings remain unknown'; exit 1; }
rg -Fq '"甜饮/高能量不确定项"' "Sources/YouyeHealthCoach/PrivateFoodPhotoAnalysis.swift" || { print -u2 'FAIL: photo drink candidates must retain an explicit sugar/toppings uncertainty explanation'; exit 1; }
rg -Fq '本机候选含\($0.conservativeRangeSummary)，保留宽区间' "$app_shell" || { print -u2 'FAIL: photo UI must surface the candidate-specific reason for keeping a conservative range'; exit 1; }
rg -Fq 'let retainedPhotoRange = photoRequiresConservativeRange' "Sources/YouyeHealthCoach/UnplannedMeal.swift" || { print -u2 'FAIL: a high-energy or drink photo must not shrink merely because a small portion was selected'; exit 1; }
rg -Fq 'let hasDrinkAlongsideFood' "Sources/YouyeHealthCoach/PrivateFoodPhotoAnalysis.swift" || { print -u2 'FAIL: a food photo with a visible drink must retain a conservative extra-energy boundary'; exit 1; }
rg -q 'Section\("份量"\)' "$app_shell" || { print -u2 'FAIL: photo meal logging must offer structured household-size confirmation'; exit 1; }
rg -q 'MealCompositionQuickEditor' "$app_shell" || { print -u2 'FAIL: meal logging must expose a concise one-tap portion path'; exit 1; }
rg -Fq '再确认这 3 项，才会收窄范围' "$app_shell" || { print -u2 'FAIL: photo meal logging must make oil, extras, and consumed amount the concise accuracy path'; exit 1; }
rg -Fq '确认后的估算范围' "$app_shell" || { print -u2 'FAIL: confirmed photo estimates must remain labelled as estimates rather than trusted measurements'; exit 1; }
rg -Fq '约 \(composition?.recommendedCalories ?? calories.lowerBound) 千卡' "$app_shell" || { print -u2 'FAIL: calorie result accessibility must interpolate the recommended value rather than read source text'; exit 1; }
! rg -Fq '约 (composition?.recommendedCalories ?? calories.lowerBound) 千卡' "$app_shell" || { print -u2 'FAIL: calorie result accessibility must not expose an unexpanded interpolation expression'; exit 1; }
rg -q 'private struct CountableFoodAmountEntry' "$app_shell" || { print -u2 'FAIL: meal logging must offer an optional count-and-unit entry for countable foods'; exit 1; }
rg -q 'case piece = "个"' "$app_shell" || { print -u2 'FAIL: countable-food entry must include the everyday 个 unit'; exit 1; }
rg -q 'item = "枚"' "$app_shell" || { print -u2 'FAIL: countable-food entry must include the everyday 枚 unit'; exit 1; }
rg -q 'seed = "颗"' "$app_shell" || { print -u2 'FAIL: countable-food entry must include the everyday 颗 unit'; exit 1; }
rg -q 'handful = "把"' "$app_shell" || { print -u2 'FAIL: countable-food entry must include the everyday 把 unit'; exit 1; }
rg -q 'spoonful = "匙"' "$app_shell" || { print -u2 'FAIL: countable-food entry must include the everyday 匙 unit'; exit 1; }
rg -q 'root = "根"' "$app_shell" || { print -u2 'FAIL: countable-food entry must include the everyday 根 unit'; exit 1; }
rg -q 'grain = "粒"' "$app_shell" || { print -u2 'FAIL: countable-food entry must include the everyday 粒 unit'; exit 1; }
rg -q 'bowl = "碗"' "$app_shell" || { print -u2 'FAIL: countable-food entry must include the everyday 碗 unit'; exit 1; }
rg -q 'plate = "盘"' "$app_shell" || { print -u2 'FAIL: countable-food entry must include the everyday 盘 unit'; exit 1; }
rg -q 'spoon = "勺"' "$app_shell" || { print -u2 'FAIL: countable-food entry must include the everyday 勺 unit'; exit 1; }
rg -q 'custom = "自定义"' "$app_shell" || { print -u2 'FAIL: countable-food entry must allow a custom owner-selected unit'; exit 1; }
rg -q 'TextField\("自定义量词"' "$app_shell" || { print -u2 'FAIL: custom countable-food unit must have a text field'; exit 1; }
rg -q 'String\(value\.prefix\(4\)\)' "$app_shell" || { print -u2 'FAIL: custom countable-food unit must stay short enough for the compact meal form'; exit 1; }
! rg -q 'accessibilityLabel\("加入数量 \(amount\)"\)' "$app_shell" || { print -u2 'FAIL: countable-food accessibility label must not expose a literal interpolation placeholder'; exit 1; }
rg -Fq 'MealQuantityNote.replacingQuantity' "$app_shell" || { print -u2 'FAIL: changing a countable-food amount must replace the previous quantity through the tested parsing boundary'; exit 1; }
rg -q '也可先加入“2 个”再补食物名称' "$app_shell" || { print -u2 'FAIL: countable-food entry must allow an amount before the food name'; exit 1; }
[[ "$(rg -U -c 'CountableFoodAmountEntry\(\s*description:' "$app_shell")" -ge 4 ]] || { print -u2 'FAIL: planned, changed, photo-corrected, and extra meal logging must all expose countable-food quantities'; exit 1; }
rg -Fq '让估算更贴近（约 10 秒）' "$app_shell" || { print -u2 'FAIL: photo-candidate quick correction must retain the compact countable-food path'; exit 1; }
rg -Fq 'MealQuantityNote.actualQuantity' "$app_shell" || { print -u2 'FAIL: planned-meal countable quantities must be saved through the tested quantity-note boundary'; exit 1; }
rg -Fq 'MealQuantityNote.hasFoodDescription' "$app_shell" || { print -u2 'FAIL: an extra-meal count-only draft must be blocked before it can become a food record'; exit 1; }
rg -Fq 'selectedCountableQuantity' "$app_shell" || { print -u2 'FAIL: planned meals must retain a quantity chosen before the food name is entered'; exit 1; }
rg -q '实际数量：' "$meal_quantity_note_source" || { print -u2 'FAIL: planned-meal countable quantities must persist as an actual-quantity note'; exit 1; }
rg -q 'storedQuantityPattern' "$meal_quantity_note_source" || { print -u2 'FAIL: editing a planned-meal quantity must replace the previous quantity note'; exit 1; }
rg -q 'compactKnownUnitPattern' "$meal_quantity_note_source" || { print -u2 'FAIL: manual Chinese countable quantities without spaces must be recognised'; exit 1; }
rg -q '手打“鸡蛋2个、两个鸡蛋、俩鸡蛋”也能识别' "$app_shell" || { print -u2 'FAIL: the compact meal form must disclose its natural Chinese count-entry support'; exit 1; }
rg -Fq 'compactChineseNumeralKnownUnitPattern' "$meal_quantity_note_source" || { print -u2 'FAIL: quantity parsing must support everyday Chinese-numeral count words'; exit 1; }
rg -Fq 'trailingQuantityPattern = #"\s\d+\s+[^\s｜]+$"#' "$meal_quantity_note_source" || { print -u2 'FAIL: planned-meal quantity persistence must support custom units without crossing a saved-note boundary'; exit 1; }
rg -Fq 'private static let measuredUnits' "$meal_quantity_note_source" || { print -u2 'FAIL: weights and volumes must not be mislabelled as countable-food quantities'; exit 1; }
rg -Fq 'var historyEstimateLabel: String' "Sources/YouyeHealthCoach/UnplannedMeal.swift" || { print -u2 'FAIL: extra-meal history must expose a compact, source-aware estimate label'; exit 1; }
rg -Fq 'public var historyEstimateLabel: String' "Sources/YouyeHealthCoach/ActualMealLog.swift" || { print -u2 'FAIL: actual-meal history must expose a source-aware estimate label'; exit 1; }
rg -Fq 'portionNote?.contains("照片候选保守区间")' "Sources/YouyeHealthCoach/ActualMealLog.swift" || { print -u2 'FAIL: deleting a private meal photo must not erase its conservative photo-candidate source label'; exit 1; }
rg -Fq '移除现有照片，保留餐食记录' "$app_shell" || { print -u2 'FAIL: actual-meal editing must offer an explicit local-photo removal action'; exit 1; }
rg -q 'portionNote\?\.contains\("照片候选保守区间"\)|displayPortionNote' "Sources/YouyeHealthCoach/ActualMealLog.swift" || { print -u2 'FAIL: retained meal-data model must preserve the photo-removal boundary'; exit 1; }
rg -Fq '非称重' "Sources/YouyeHealthCoach/ActualMealLog.swift" || { print -u2 'FAIL: a confirmed actual-meal estimate must still disclose it is not weighed'; exit 1; }
[[ "$(rg -c 'resetManualRangeForAcceptedNewPhoto\(\)' "$app_shell")" -ge 3 ]] || { print -u2 'FAIL: a newly accepted meal photo must clear stale menu/scale bounds before it can be saved'; exit 1; }
rg -Fq '已清空旧菜单/秤与盘中确认，请按新照片重新核对。' "$app_shell" || { print -u2 'FAIL: replacing a meal photo must visibly disclose that old ranges and plate confirmations were cleared'; exit 1; }
rg -Fq 'initialAmount: selectedCountableQuantity' "$app_shell" || { print -u2 'FAIL: changed and extra meal forms must restore an explicitly chosen quantity in the compact control'; exit 1; }
rg -Fq 'removingStoredActualQuantity' "$meal_quantity_note_source" || { print -u2 'FAIL: extra-meal history must hide its internal quantity marker from the food description'; exit 1; }
rg -q '数量仅作备注；热量仍按餐卡范围估算' "$app_shell" || { print -u2 'FAIL: planned-meal quantity UI must disclose that an item count does not recalculate the recipe energy range'; exit 1; }
rg -Fq 'private func resetPlanSpecificDraftForActualMeal()' "$app_shell" || { print -u2 'FAIL: changing a planned meal into a different-food record must clear plan-specific draft data'; exit 1; }
rg -Fq 'description = ""' "$app_shell" || { print -u2 'FAIL: changing a planned meal into a different-food record must require actual food text instead of retaining the recipe title'; exit 1; }
rg -Fq 'public var displayPortionNote: String?' "Sources/YouyeHealthCoach/ActualMealLog.swift" || { print -u2 'FAIL: retained private meal history must keep a presentation-safe owner portion note even while meal logging is retired'; exit 1; }
rg -Fq 'public var displayPortionNote: String?' "Sources/YouyeHealthCoach/ActualMealLog.swift" || { print -u2 'FAIL: actual-meal history must provide a presentation-safe portion note'; exit 1; }
rg -Fq 'if usesOwnerProvidedEnergyRange {' "Sources/YouyeHealthCoach/ActualMealLog.swift" || { print -u2 'FAIL: actual-meal history must prioritize an owner-provided menu or scale range over retained components'; exit 1; }
rg -Fq 'estimateSource == .ownerConfirmedComposition' "Sources/YouyeHealthCoach/UnplannedMeal.swift" || { print -u2 'FAIL: extra-meal display must show a component diary value only when components are the chosen estimate source'; exit 1; }
rg -Fq 'photoUsesDefaultEstimate || confirmedManualCaloriesRange != nil ? nil : composition' "$app_shell" || { print -u2 'FAIL: a confirmed menu or scale range must not persist a conflicting component estimate'; exit 1; }
rg -Fq 'if photoUsesDefaultEstimate { return descriptionWithQuantity }' "$app_shell" || { print -u2 'FAIL: a default photo candidate must not serialize an unconfirmed plate-composition annotation'; exit 1; }
rg -Fq 'private func resetManualRangesForAcceptedNewPhoto()' "$app_shell" || { print -u2 'FAIL: replacing an extra-meal photo must clear a previous menu or scale range'; exit 1; }
[[ "$(rg -c 'resetManualRangesForAcceptedNewPhoto\(\)' "$app_shell")" -eq 3 ]] || { print -u2 'FAIL: both picker and camera replacement paths must reset old extra-meal ranges'; exit 1; }
[[ "$(rg -c 'let hadCompositionConfirmation = composition.hasAnyOwnerSelection' "$app_shell")" -eq 2 ]] || { print -u2 'FAIL: replacing any photo must clear confirmed plate components from the previous meal'; exit 1; }
rg -q '菜名即可，例如：鸡蛋 2 个' "$app_shell" || { print -u2 'FAIL: extra-meal entry must show a minimum-text countable-food example'; exit 1; }
rg -q '鸡蛋 2 个' "$meal_composition_source" || { print -u2 'FAIL: protein confirmation must support a direct two-egg selection'; exit 1; }
rg -Fq '细调主食、蛋白质和蔬菜' "$app_shell" || { print -u2 'FAIL: detailed photo food factors must remain available without crowding the primary flow'; exit 1; }
for selector in staple protein vegetables addedFat extras consumed; do
  rg -Fq "\$composition.$selector" "$app_shell" || { print -u2 "FAIL: structured photo meal confirmation is missing $selector"; exit 1; }
done
rg -q '不用换算克数或热量' "$app_shell" || { print -u2 'FAIL: the owner must not be asked to calculate calories for a photographed meal'; exit 1; }
rg -Fq 'case .regular: "大致一份"' "$meal_composition_source" || { print -u2 'FAIL: photo portion shortcuts must use a memorable everyday regular-portion label'; exit 1; }
rg -Fq '和你平时比，这份更接近？' "$app_shell" || { print -u2 'FAIL: portion shortcuts must frame choices as a personal comparison rather than an objective serving size'; exit 1; }
! rg -Fq '半碗主食 · 半掌蛋白' "$meal_composition_source" || { print -u2 'FAIL: photo portion shortcuts must not require hand-size mnemonic labels'; exit 1; }
[[ "$(rg -c 'applyRecognizedMealSuggestion' "$app_shell")" -ge 5 ]] || { print -u2 'FAIL: planned and extra-meal photo routes must automatically prefill editable recognition defaults'; exit 1; }
rg -q '已填入识别候选；份量尚未确认，已保留热量范围' "$app_shell" || { print -u2 'FAIL: the photo flow must state that a candidate does not confirm portion size'; exit 1; }
rg -q 'composition = MealQuickPortionPreset\.regular\.composition' "$app_shell" || { print -u2 'FAIL: photo recognition defaults must fill a complete editable portion preset'; exit 1; }
rg -Fq 'addedFat: .uncertain, extras: .uncertain, consumed: .uncertain' "$meal_composition_source" || { print -u2 'FAIL: photo portion shortcuts must not assume the owner ate the entire serving'; exit 1; }
[[ "$(rg -c 'private func discardUnconfirmedPhotoDefaults' "$app_shell")" -eq 2 ]] || { print -u2 'FAIL: both planned and extra-meal photo forms must clear abandoned recognition defaults'; exit 1; }
rg -q 'photoUsesDefaultEstimate = false' "$app_shell" || { print -u2 'FAIL: discarding a photo must clear its unconfirmed auto-filled portion marker'; exit 1; }
rg -q 'composition = MealCompositionConfirmation\(\)' "$app_shell" || { print -u2 'FAIL: discarding an unconfirmed photo must not retain the auto-filled normal-plate portion'; exit 1; }
rg -q '已移除所选照片；将只保存文字和保守估算。' "$app_shell" || { print -u2 'FAIL: photo removal must tell the owner that text-only logging keeps a conservative estimate'; exit 1; }
rg -q 'Button\("确认并记录"\)' "$app_shell" || { print -u2 'FAIL: saving the prefilled photo result must remain one explicit confirmation action'; exit 1; }
rg -q '候选无误，记录宽范围' "$app_shell" || { print -u2 'FAIL: photo quick action must require an owner match and retain the wide-range boundary'; exit 1; }
rg -q '仅在本机候选与实际食物一致时记录' "$app_shell" || { print -u2 'FAIL: photo quick confirmation must require the owner to match the category candidate before saving'; exit 1; }
[[ "$(rg -F -c '候选无误 · 宽范围' "$app_shell")" -eq 2 ]] || { print -u2 'FAIL: both photo meal forms must identify that the candidate needs an owner match before quick recording'; exit 1; }
[[ "$(rg -F -c '按你写的菜名记录 · 照片仅作范围参考' "$app_shell")" -eq 2 ]] || { print -u2 'FAIL: both photo meal forms must state that an edited dish name, not the candidate, will be recorded'; exit 1; }
rg -Fq 'description = suggestion.provisionalDescription' "$app_shell" || { print -u2 'FAIL: photo quick records must retain an explicit candidate-category marker rather than a fabricated dish name'; exit 1; }
rg -Fq 'public var provisionalDescription' "Sources/YouyeHealthCoach/PrivateFoodPhotoAnalysis.swift" || { print -u2 'FAIL: local photo suggestions must expose an explicit provisional description boundary'; exit 1; }
rg -Fq 'public var displayDescription' "Sources/YouyeHealthCoach/UnplannedMeal.swift" || { print -u2 'FAIL: extra-meal history must expose a presentation-safe description separate from serialized estimation metadata'; exit 1; }
rg -Fq 'public var displayDescription' "Sources/YouyeHealthCoach/UnplannedMeal.swift" || { print -u2 'FAIL: retained private extra-meal history must keep a presentation-safe description while meal logging is retired'; exit 1; }
rg -q '照片估算保留宽范围' "$app_shell" || { print -u2 'FAIL: extra-meal result cards must keep the photo-wide-range boundary visible after photo analysis'; exit 1; }
rg -A5 'private var retainedPhotoSuggestedCaloriesRange' "$app_shell" | rg -q 'pendingMealPhotoData == nil' || { print -u2 'FAIL: editing or removing an old photo must retain its saved photo-range boundary until a replacement is selected'; exit 1; }
if rg -A5 'private var retainedPhotoSuggestedCaloriesRange' "$app_shell" | rg -q '!removesExistingPhoto'; then
  print -u2 'FAIL: removing a private photo must not silently discard its conservative calorie boundary'
  exit 1
fi
rg -q '候选无误，记录宽范围' "$app_shell" || { print -u2 'FAIL: extra-meal photo quick action must require an owner match and retain the wide-range boundary'; exit 1; }
rg -q '暂停计划训练与任何加量' "Sources/YouyeHealthCoach/Domain.swift" || { print -u2 'FAIL: medication or clinician restrictions must pause planned training rather than prescribe a generic recovery walk'; exit 1; }
rg -q '暂停计划训练和核心动作' "Sources/YouyeHealthCoach/Domain.swift" || { print -u2 'FAIL: illness symptoms must default to rest rather than a generic recovery workout'; exit 1; }
rg -q '训练已暂停：今天以休息和恢复为主' "Sources/YouyeHealthCoach/HealthCheckIn.swift" || { print -u2 'FAIL: recovery support must not contradict a clinician-restriction training pause'; exit 1; }
rg -Fq 'completed: feedback.completed && !trainingIsPaused' "Sources/YouyeHealthCoach/TrainingFeedback.swift" || { print -u2 'FAIL: paused-training feedback must not persist as completed movement'; exit 1; }
rg -q '反馈只记录状态，不标记训练或恢复完成' "$app_shell" || { print -u2 'FAIL: paused-training feedback UI must disclose its non-completion boundary'; exit 1; }
rg -Fq 'guard kind != .move || !isTrainingPaused(plan) else { return data }' "Sources/YouyeHealthCoach/TodayFeature.swift" || { print -u2 'FAIL: affirmative movement completion must reject a paused-training day'; exit 1; }
rg -q '今天暂停计划训练；不能标记为训练或恢复完成' "$app_shell" || { print -u2 'FAIL: every paused-training today-card action must disclose that it cannot be marked complete'; exit 1; }
rg -q '本页不会把休息写成训练完成' "$app_shell" || { print -u2 'FAIL: recovery detail must not describe a medically paused rest day as completed training'; exit 1; }
rg -q '不把休息、轻走或呼吸标成训练完成' "$app_shell" || { print -u2 'FAIL: training home must distinguish a paused plan from an optional-activity recovery day'; exit 1; }
rg -q '预设不猜油和甜饮' "$app_shell" || { print -u2 'FAIL: photo quick portions must not imply unknown oil or sweet drinks are confirmed'; exit 1; }
rg -Fq 'addedFat: .uncertain, extras: .uncertain' "Sources/YouyeHealthCoach/MealCompositionEstimate.swift" || { print -u2 'FAIL: a quick portion preset must retain unknown oil and extras'; exit 1; }
! rg -q '确认下方 6 项后会明显收紧' "$app_shell" || { print -u2 'FAIL: meal result cards must not promise that photo or text estimates will become precise after structured inputs'; exit 1; }
rg -q 'private struct ActualMealLogDestination: Identifiable' "$app_shell" || { print -u2 'FAIL: meal sheets must carry an immutable selected slot'; exit 1; }
if printf '%s\n%s\n' "$today_active_surface" "$health_active_surface" | rg -q '\.sheet\(item: \$actualMealDestination\)'; then
  print -u2 'FAIL: retired meal logging must not retain active sheet destinations'; exit 1
fi
! rg -q 'showingActualMealLog|actualMealSlot' "$app_shell" || { print -u2 'FAIL: separate presentation and meal-slot state can race and reopen breakfast for a dinner tap'; exit 1; }
rg -q 'private func saveMealLog\(slot: MealSlot' "$app_shell" || { print -u2 'FAIL: saving must receive the sheet-captured meal slot explicitly'; exit 1; }
rg -Fq 'portionChoice: portionChoice' "$app_shell" || { print -u2 'FAIL: the selected portion must affect both preview and saved estimate'; exit 1; }
rg -q 'Button\("修正记录", systemImage: "pencil"' "$app_shell" || { print -u2 'FAIL: today extra-meal records must expose a direct correction action on the food home screen'; exit 1; }
[[ "$food_home" != *'UnplannedMealForm('* ]] || { print -u2 'FAIL: meal-prep home must not reopen a meal-record editor after meal logging is retired'; exit 1; }
rg -Fq 'id: existingLog?.id ?? estimate.id' "$app_shell" || { print -u2 'FAIL: correcting a photographed meal must replace its stable record instead of duplicating daily calories'; exit 1; }
rg -q '这条餐食记录已在其他页面被删除或更改' "$app_shell" || { print -u2 'FAIL: a stale meal correction form must not resurrect a deleted record'; exit 1; }
rg -q 'oldPhotoReferenceToDelete' "$app_shell" || { print -u2 'FAIL: replacing or removing a meal photo must clean the old unreferenced private image after durable save'; exit 1; }
rg -q 'removesExistingPhoto = true[[:space:]]*photoSuggestion = nil' "$app_shell" && print -u2 'FAIL: removing an existing meal photo must also clear the unconfirmed default marker via the shared helper' && exit 1
rg -A4 -B2 -Fq 'Button("移除现有照片，保留文字记录")' "$app_shell" || { print -u2 'FAIL: existing-photo removal action must remain present'; exit 1; }
rg -q 'selectedPhoto = nil' "$app_shell" || { print -u2 'FAIL: failed optional meal photo reads must clear the unusable picker selection'; exit 1; }
rg -Fq '.accessibilityLabel("\(slot.displayName)' "$app_shell" || { print -u2 'FAIL: meal destinations need an explicit accessibility label'; exit 1; }
rg -q 'KitchenCompatibility\.notice' "$app_shell" || { print -u2 'FAIL: meal cards must evaluate the saved kitchen setup before execution'; exit 1; }
rg -q '设备待确认' "$app_shell" || { print -u2 'FAIL: mismatched kitchen setup must have a visible actionable warning'; exit 1; }
rg -q '不要自行延长时间或改用未确认设备' "Sources/YouyeHealthCoach/RecipeCatalog.swift" || { print -u2 'FAIL: kitchen mismatch warning must forbid unsafe timing/device improvisation'; exit 1; }
rg -Fq '两个月计划共 61 天：前 56 天正式餐卡，最后 5 天收尾复盘；默认以“电饭锅 + 一个电磁炉锅”为基准。' "$app_shell" || { print -u2 'FAIL: profile setup must disclose the two-month plan and fixed kitchen basis before saved-device compatibility warnings appear'; exit 1; }
rg -q '正式 UI、易用性与无障碍回归' "DEVICE_ACCEPTANCE.md" || { print -u2 'FAIL: device acceptance must include visual and accessibility regression'; exit 1; }
if rg -q 'try!' "Sources/YouyeHealthCoach/PrivateMealPhotoStore.swift"; then
  print -u2 'FAIL: private photo storage must not force-try filesystem initialization'
  exit 1
fi
rg -q 'MARKETING_VERSION = 0\.1\.0;' "$project" || { print -u2 'FAIL: native targets need an explicit beta version'; exit 1; }
rg -q 'CURRENT_PROJECT_VERSION = 1;' "$project" || { print -u2 'FAIL: native targets need an explicit build number'; exit 1; }
rg -q 'awaitingInitialProfileSetup' "$app_shell" || { print -u2 'FAIL: full local deletion must not silently recreate a new owner profile'; exit 1; }
rg -q '此前本机资料已删除。完成新的首次设置前' "$app_shell" || { print -u2 'FAIL: deletion must visibly explain the no-autorecreate boundary'; exit 1; }
rg -q 'invalidateDailyCard' "$app_shell" || { print -u2 'FAIL: full local deletion must invalidate the paired Watch daily card'; exit 1; }
rg -q 'immediatelyPersistedDataAwaitingObservation = loaded' "$app_shell" || { print -u2 'FAIL: recovery reload must not turn a durable private profile read into a redundant autosave'; exit 1; }
rg -A20 'private func retryLoadingPrivateData' "$app_shell" | rg -q 'publishWatchDailyCard()' || { print -u2 'FAIL: a successfully recovered profile must immediately replace the Watch unavailable card'; exit 1; }
rg -q '不会在这里自动请求授权' "$app_shell" || { print -u2 'FAIL: first run must not imply automatic HealthKit authorization'; exit 1; }
rg -q '不录像、不缓存、不上传' "$app_shell" || { print -u2 'FAIL: first run must explain the live-camera no-recording boundary'; exit 1; }
rg -Fq 'savePrivateData(privateData)' "$app_shell" || { print -u2 'FAIL: first-run dismissal must persist the private profile even with the default name'; exit 1; }
rg -q 'public struct DailyReminderPreferences' "Sources/YouyeHealthCoach/Privacy.swift" || { print -u2 'FAIL: local reminders need explicit per-item opt-in preferences'; exit 1; }
rg -q '当天自炊午餐' "Sources/YouyeHealthCoach/DailyMealCatalog.swift" || { print -u2 'FAIL: ingredient mismatch must offer a self-cooked replan instead of the forbidden outside-meal label'; exit 1; }
rg -q 'public struct DailyCalorieIntakeSummary' "Sources/YouyeHealthCoach/DailyCalorieIntake.swift" || { print -u2 'FAIL: daily meal records need one shared calorie-intake summary'; exit 1; }
rg -q 'entriesMissingCalories' "Sources/YouyeHealthCoach/DailyCalorieIntake.swift" || { print -u2 'FAIL: legacy meals without calories must block a misleading remaining allowance'; exit 1; }
[[ "$(rg -c 'DailyCalorieOverviewCard\(summary: summary\)' "$app_shell")" -eq 1 ]] || { print -u2 'FAIL: calories must appear only in the dedicated meal-estimate detail'; exit 1; }
! rg -q 'Section\("今日热量记录"\)' "$app_shell" || { print -u2 'FAIL: meal prep must not duplicate its optional estimate detail with a verbose summary'; exit 1; }
rg -q '换了食物' "$app_shell" || { print -u2 'FAIL: meal logging must let the owner classify a changed meal'; exit 1; }
rg -q '计划外.*tag\(ActualMealRelationship\.planExternal\)' "$app_shell" || { print -u2 'FAIL: meal logging must let the owner classify a plan-external meal'; exit 1; }
rg -q '现在拍照' "$app_shell" || { print -u2 'FAIL: breakfast/lunch/dinner logging must expose the camera directly'; exit 1; }
rg -q '从相册上传' "$app_shell" || { print -u2 'FAIL: breakfast/lunch/dinner logging must expose the photo library directly'; exit 1; }
rg -Fq '+ data.actualMealLogs.map(\.localPhotoReference)' "Sources/YouyeHealthCoach/LocalDataDeletion.swift" || { print -u2 'FAIL: full local deletion must include direct meal-log photos'; exit 1; }
rg -Fq '+ resolvedData.actualMealLogs.map(\.localPhotoReference)' "Sources/YouyeHealthCoach/LocalStore.swift" || { print -u2 'FAIL: launch cleanup must retain direct meal-log photos still referenced by owner data'; exit 1; }
rg -q 'copy.actualMealLogs = data.actualMealLogs.map' "Sources/YouyeHealthCoach/Privacy.swift" || { print -u2 'FAIL: owner export must strip direct meal-log private photo references'; exit 1; }
rg -U -q 'estimatedCaloriesRange = UnplannedMealLog\.validatedCaloriesRange\([[:space:]]*try values\.decodeIfPresent' "Sources/YouyeHealthCoach/ActualMealLog.swift" || { print -u2 'FAIL: older actual-meal records must remain decodable without fabricated calories'; exit 1; }
rg -q 'public let compositionConfirmation: MealCompositionConfirmation?' "Sources/YouyeHealthCoach/ActualMealLog.swift" || { print -u2 'FAIL: direct meal logs must persist structured plate confirmation'; exit 1; }
rg -q 'public let compositionConfirmation: MealCompositionConfirmation?' "Sources/YouyeHealthCoach/UnplannedMeal.swift" || { print -u2 'FAIL: extra-meal logs must persist structured plate confirmation'; exit 1; }
rg -Fq '_composition = State(initialValue: existingLog?.compositionConfirmation ?? MealCompositionConfirmation())' "$app_shell" || { print -u2 'FAIL: editing a meal must restore its structured confirmation'; exit 1; }
rg -Fq 'compositionConfirmation: estimate.compositionConfirmation' "$app_shell" || { print -u2 'FAIL: the final stable-ID extra-meal record must retain structured confirmation'; exit 1; }
rg -q 'MealEstimateResultCard' "$app_shell" || { print -u2 'FAIL: meal logging must lead with one compact result card'; exit 1; }
rg -q '建议记账' "$app_shell" || { print -u2 'FAIL: a fully confirmed photo meal must expose one usable diary value'; exit 1; }
rg -q '\.accessibilityLabel\(' "$app_shell" || { print -u2 'FAIL: meal estimate result card must expose a VoiceOver label'; exit 1; }
rg -q '这是本机保守估算，不是称重结果' "$app_shell" || { print -u2 'FAIL: VoiceOver must preserve the photo-estimate-not-weighed boundary'; exit 1; }
rg -q 'public enum DailyReminderPlan' "$reminder_source" || { print -u2 'FAIL: local reminder planning contract is missing'; exit 1; }
rg -q 'public enum LocalReminderCoordinator' "$reminder_source" || { print -u2 'FAIL: iPhone local-notification coordinator is missing'; exit 1; }
rg -q '系统未授予通知权限；已清除旧提醒' "$reminder_source" || { print -u2 'FAIL: denied notification authorization must clear stale app reminders'; exit 1; }
rg -q 'requestAuthorizationAndSynchronize' "$app_shell" || { print -u2 'FAIL: reminder permission must be requested only by an explicit owner action'; exit 1; }
rg -q 'isSynchronizingReminders' "$app_shell" || { print -u2 'FAIL: reminder actions must prevent concurrent notification synchronization races'; exit 1; }
rg -q '保存时间表并更新已授权提醒' "$app_shell" || { print -u2 'FAIL: saved routine changes must clearly disclose notification synchronization'; exit 1; }
rg -q '首次创建只在你点“允许通知并更新提醒”后请求系统权限' "$app_shell" || { print -u2 'FAIL: routine settings must distinguish an initial authorization request from later authorized updates'; exit 1; }
rg -q '快速连续点按“允许通知并更新提醒”' "DEVICE_ACCEPTANCE.md" || { print -u2 'FAIL: device acceptance must cover notification synchronization reentrancy'; exit 1; }
rg -q 'removePendingNotificationRequests' "$reminder_source" || { print -u2 'FAIL: reminder synchronization must clear stale disabled reminders'; exit 1; }
rg -q '不包含健康、食材、位置或价格信息' "$app_shell" || { print -u2 'FAIL: reminder UI must disclose its minimal notification payload'; exit 1; }
rg -q '不会用其他提醒代替' "$app_shell" || { print -u2 'FAIL: disabled notification categories must not be replaced by another reminder'; exit 1; }
rg -q '不会被偷偷挪到其他时间' "$app_shell" || { print -u2 'FAIL: quiet-time reminder conflicts must be disclosed'; exit 1; }
rg -Fq 'invalidateAndClear(ownerID: deletedOwnerID)' "$app_shell" || { print -u2 'FAIL: owner deletion must clear only the deleted profile’s App local reminders'; exit 1; }
rg -Fq 'let ownerID = privateData.profile.id' "$app_shell" || { print -u2 'FAIL: an asynchronous reminder task must capture its owner at the owner-action boundary'; exit 1; }
rg -Fq 'ReminderMutationGate' "$reminder_source" || { print -u2 'FAIL: reminder writes and profile deletion must share a serialization gate'; exit 1; }
rg -Fq 'deletedOwnerIDs.insert(ownerID)' "$reminder_source" || { print -u2 'FAIL: profile deletion must permanently block stale reminder writes for that deleted owner'; exit 1; }
rg -Fq 'PrivateProfileAsyncOwnershipGate.beginDeletion' "$app_shell" || { print -u2 'FAIL: full local deletion must freeze stale asynchronous work before deleting the owner record'; exit 1; }
rg -Fq 'PrivateProfileAsyncOwnershipGate.commitDeletion' "$app_shell" || { print -u2 'FAIL: successful local deletion must permanently block an old async task from writing into a new profile'; exit 1; }
rg -Fq 'PrivateProfileAsyncOwnershipGate.mayContinue' "$app_shell" || { print -u2 'FAIL: asynchronous HealthKit reads must recheck ownership after system calls'; exit 1; }
rg -Fq 'let ownerID = privateData.profile.id' "$app_shell" || { print -u2 'FAIL: asynchronous HealthKit reads must capture the owner at the explicit action boundary'; exit 1; }
rg -Fq 'public enum PrivateProfileAsyncOwnershipPolicy' "$profile_async_ownership_source" || { print -u2 'FAIL: private profile async ownership policy must remain independently testable'; exit 1; }
rg -Fq 'formOwnerID' "$app_shell" || { print -u2 'FAIL: photo and meal forms must retain the owner selected at sheet creation'; exit 1; }
rg -Fq 'PrivateProfileAsyncOwnershipGate.mayContinue' "$app_shell" || { print -u2 'FAIL: delayed photo and meal operations must recheck the private profile before saving'; exit 1; }
rg -Fq 'WeeklyReportPreviewForm(privateData: privateData, ownerID: privateData.profile.id)' "$app_shell" || { print -u2 'FAIL: local weekly-report confirmation must retain the preview owner boundary'; exit 1; }
rg -Fq 'exportDocument = nil' "$app_shell" || { print -u2 'FAIL: full local deletion must clear any in-memory owner export document'; exit 1; }
rg -Fq 'voiceCuePreferenceKey(for ownerID: UUID)' "Sources/YouyeHealthCoach/LocalDataDeletion.swift" || { print -u2 'FAIL: live voice preferences must use an owner-scoped key'; exit 1; }
rg -Fq 'clearAppPrivatePreferences(for: ownerID, defaults: defaults)' "Sources/YouyeHealthCoach/LocalDataDeletion.swift" || { print -u2 'FAIL: recovery cleanup must clear only the deleted owner’s scoped live-voice preference'; exit 1; }
rg -Fq 'ownerID: privateData.profile.id' "$app_shell" || { print -u2 'FAIL: live pose coaching must receive the active private profile owner'; exit 1; }
rg -q 'unrelated owner.*scoped live-voice preference' "Sources/YouyeHealthCoachRuleCheck/main.swift" || { print -u2 'FAIL: rule checks must prove pending owner cleanup preserves another profile’s live-voice preference'; exit 1; }
rg -q '清除静息心率基线' "$app_shell" || { print -u2 'FAIL: a user-confirmed heart-rate baseline must have a visible local removal control'; exit 1; }
rg -q 'asOf: now' "Sources/YouyeHealthCoach/Privacy.swift" || { print -u2 'FAIL: voluntary weekly report must avoid treating future plan dates as missed'; exit 1; }
rg -q 'public struct VoluntaryWeeklyReportPayload' "Sources/YouyeHealthCoach/Privacy.swift" || { print -u2 'FAIL: future weekly sharing needs a separate minimal payload type'; exit 1; }
rg -q 'confirmedForThisShare' "Sources/YouyeHealthCoach/Privacy.swift" || { print -u2 'FAIL: future weekly sharing must require a fresh explicit confirmation'; exit 1; }
rg -q 'report.revokedAt == nil' "Sources/YouyeHealthCoach/Privacy.swift" || { print -u2 'FAIL: a locally revoked weekly report must not become a future external payload'; exit 1; }
rg -q 'shouldClearLastOwnerPointer' "Sources/YouyeHealthCoach/LocalStore.swift" || { print -u2 'FAIL: deleting one local profile must not clear an unrelated owner pointer'; exit 1; }
rg -q '一台设备一个本地档案' README.md || { print -u2 'FAIL: documentation must state the one-device-one-local-profile beta boundary'; exit 1; }
rg -q 'separateBySource' "Sources/YouyeHealthCoach/HealthKitIntegration.swift" || { print -u2 'FAIL: HealthKit step query must inspect source count before aggregating'; exit 1; }
rg -q 'HealthStepAggregation.average14Days' "Sources/YouyeHealthCoach/HealthKitIntegration.swift" || { print -u2 'FAIL: HealthKit step aggregation must use the multi-source safety gate'; exit 1; }
rg -q '多来源时保留空值' "Sources/YouyeHealthCoach/HealthKitIntegration.swift" || { print -u2 'FAIL: Health summary must explain why conflicting step sources are not merged'; exit 1; }
rg -q 'HealthActiveEnergyAggregation.total24Hours' "Sources/YouyeHealthCoach/HealthKitIntegration.swift" || { print -u2 'FAIL: HealthKit active energy must use the multi-source safety gate'; exit 1; }
rg -q 'HKCategoryValueSleepAnalysis.awake' "Sources/YouyeHealthCoach/HealthKitIntegration.swift" || { print -u2 'FAIL: Health sleep aggregation must exclude awake samples'; exit 1; }
rg -q 'HealthIntervalAggregation.clipped' "Sources/YouyeHealthCoach/HealthKitIntegration.swift" || { print -u2 'FAIL: Health interval aggregates must be clipped to their query window'; exit 1; }
rg -q 'availabilityNotes' "$health_source" || { print -u2 'FAIL: HealthKit summary must retain an explicit transient note for conservative metric omissions'; exit 1; }
rg -q 'permissionPlan: HealthKitPermissionPlan = \.readOnly' "$health_source" || { print -u2 'FAIL: generic native HealthKit providers must default to the read-only plan'; exit 1; }
rg -Fq 'ForEach(snapshot.availabilityNotes' "$app_shell" || { print -u2 'FAIL: health UI must visibly explain conservative HealthKit metric omissions'; exit 1; }
rg -Fq 'HealthSummaryRow(label: "近 24 小时活动能量"' "$app_shell" || { print -u2 'FAIL: health UI must display the approved bounded active-energy summary when readable'; exit 1; }
rg -q '多个步数来源' "DEVICE_ACCEPTANCE.md" || { print -u2 'FAIL: device acceptance must cover step-source conflict behavior'; exit 1; }
rg -q 'full snapshot and every raw sample stay out' "Sources/YouyeHealthCoach/Privacy.swift" || { print -u2 'FAIL: private storage must document the HealthKit snapshot retention boundary'; exit 1; }
rg -q '完整 HealthKit 摘要不能出现在本地导出或朋友周报' "DEVICE_ACCEPTANCE.md" || { print -u2 'FAIL: device acceptance must verify HealthKit summary retention boundary'; exit 1; }
rg -q '不能在历史记录中直接撤回' "DEVICE_ACCEPTANCE.md" || { print -u2 'FAIL: device acceptance must verify the recovery-audit reversal boundary'; exit 1; }
rg -q '跳过日仅计实际完成项' "DEVICE_ACCEPTANCE.md" || { print -u2 'FAIL: device acceptance must verify explicit-skip review semantics'; exit 1; }
! rg -U -q 'TodayView\(plan: \$plan, privateData: \$privateData, showingHealthStatus: \$showingHealthStatus, showingPlanChanges: \$showingPlanChanges\)[[:space:]]*\n[[:space:]]*TodayView\(plan: \$plan, privateData: \$privateData, showingHealthStatus: \$showingHealthStatus, showingPlanChanges: \$showingPlanChanges\)' "$app_shell" || { print -u2 'FAIL: a native detail must not render the today daily card twice'; exit 1; }
for calendar_state in recovery completed partiallyCompleted today unrecorded upcoming; do
  rg -q "case $calendar_state" "$calendar_status_source" || { print -u2 "FAIL: shared calendar status lacks $calendar_state"; exit 1; }
done
rg -q 'guard dayStart <= todayStart else \{ return \.upcoming \}' "$calendar_status_source" || { print -u2 'FAIL: future calendar dates must remain upcoming even if malformed local records exist'; exit 1; }
if rg -q 'Text\(dateLabel\(for: card\.dayIndex\)\)' "$app_shell"; then
  print -u2 'FAIL: calendar must not force full month/day labels into seven narrow cells'
  exit 1
fi

# 周趋势属于本人手动私有记录，必须和 HealthKit 摘要分开；复盘只建议一个变量，不能暗中改计划。
rg -q 'Section\("本周复盘"\)' "$app_shell" || { print -u2 'FAIL: health page lacks weekly-review entry'; exit 1; }
rg -q '本周只关注一件事' "$app_shell" || { print -u2 'FAIL: weekly review must surface a single-variable focus'; exit 1; }
rg -q 'weeklyBodyCheckIns' "$app_shell" || { print -u2 'FAIL: weekly check-ins are not persisted through the health UI'; exit 1; }
rg -q 'weeklyBodyCheckIns' "Sources/YouyeHealthCoach/Privacy.swift" || { print -u2 'FAIL: weekly check-ins lack private persistence'; exit 1; }
rg -q 'case keepRoutine' "$weekly_review_source" || { print -u2 'FAIL: weekly review lacks explicit single-variable choices'; exit 1; }
rg -q '不会自动改目标、热量框架、训练加量或周结构' "$weekly_review_source" || { print -u2 'FAIL: weekly review safety boundary missing'; exit 1; }
if rg -q 'weeklyBodyCheckIns' "Sources/YouyeHealthCoach/Privacy.swift" && rg -q 'weeklyBodyCheckIns' "$app_shell"; then
  : # Owner-local persistence is expected; friend reports are a distinct codable type without this field.
fi

print 'PASS: iOS static project configuration is ready for Xcode signing and device verification.'
