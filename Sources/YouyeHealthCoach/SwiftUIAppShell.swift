#if canImport(SwiftUI)
import Foundation
import SwiftUI
import UniformTypeIdentifiers
#if canImport(PhotosUI)
import PhotosUI
#endif
#if canImport(UIKit)
import UIKit
#endif
#if os(iOS) && canImport(CoreLocation)
import CoreLocation
#endif

#if os(iOS) && canImport(CoreLocation)
/// The nearby screen asks for location only after its explicit button is pressed.  A granted
/// permission may refresh the current screen when it reopens, but this class never persists raw
/// coordinates, starts continuous updates, or sends a location anywhere except the owner-tapped
/// Apple Maps handoff.
@MainActor
private final class NearbyCurrentLocationProvider: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    enum Status: Equatable {
        case idle
        case locating
        case ready
        case denied
        case unavailable
    }

    @Published private(set) var coordinate: NearbyMapCoordinate?
    @Published private(set) var status: Status = .idle

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        // Nearby discovery needs a rough map centre, not turn-by-turn precision.
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func refreshIfAuthorized() {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            requestOneLocation()
        default:
            break
        }
    }

    func refresh() {
        switch manager.authorizationStatus {
        case .notDetermined:
            status = .locating
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            requestOneLocation()
        case .denied, .restricted:
            coordinate = nil
            status = .denied
        @unknown default:
            coordinate = nil
            status = .unavailable
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse where status == .locating:
            requestOneLocation()
        case .denied, .restricted:
            coordinate = nil
            status = .denied
        default:
            break
        }
    }

    func locationManager(_: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        defer { manager.stopUpdatingLocation() }
        guard let location = locations.last,
              let rounded = NearbyMapCoordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude) else {
            coordinate = nil
            status = .unavailable
            return
        }
        coordinate = rounded
        status = .ready
    }

    func locationManager(_: CLLocationManager, didFailWithError _: Error) {
        manager.stopUpdatingLocation()
        coordinate = nil
        status = .unavailable
    }

    private func requestOneLocation() {
        status = .locating
        manager.requestLocation()
    }
}
#endif

/// The training product has one deliberate visual anchor: deep-sea teal.  It is reserved for
/// the selected destination and the single next action; recovery/completion remain semantic
/// colours and are never used as competing navigation decoration.
enum CoachPalette {
    static var action: Color {
        let raw = UserDefaults.standard.string(forKey: "youye.healthCoach.appTheme") ?? AppTheme.seaGlass.rawValue
        return AppTheme(rawValue: raw)?.tint ?? AppTheme.seaGlass.tint
    }
    static var actionSurface: Color { action.opacity(0.10) }
    static var actionStroke: Color { action.opacity(0.22) }
    static let completed = Color(red: 0.12, green: 0.43, blue: 0.31)
    static let partial = Color(red: 0.08, green: 0.48, blue: 0.50)
    static let recovery = Color(red: 0.68, green: 0.36, blue: 0.10)
    static let skipped = Color(red: 0.39, green: 0.28, blue: 0.55)
}

#if canImport(UIKit)
/// Food-reference photos are local aids, not an original-photo archive. The image retained for
/// a confirmed record is capped before it ever reaches the private photo store; the untouched
/// source stays in Photos.app. This runs entirely on-device and never uploads an image.
private enum PrivateFoodPhotoPreparation {
    static let maximumPixelDimension: CGFloat = 2_048
    static let targetMaximumBytes = 2_500_000

    static func normalizedJPEG(from data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        return normalizedJPEG(from: image)
    }

    static func normalizedJPEG(from image: UIImage) -> Data? {
        let sourceSize = image.size
        guard sourceSize.width > 0, sourceSize.height > 0 else { return nil }
        let largestSide = max(sourceSize.width, sourceSize.height)
        // A quality-only fallback is not a real size limit: detailed photos can remain large
        // even at a low JPEG quality. Step down both dimension and quality until the retained
        // private copy meets its ceiling; failure is safer than keeping an oversized original.
        let maximumSides: [CGFloat] = [maximumPixelDimension, 1_600, 1_280, 1_024, 768]
        for maximumSide in maximumSides {
            let scale = min(1, maximumSide / largestSide)
            let outputSize = CGSize(
                width: max(1, (sourceSize.width * scale).rounded(.down)),
                height: max(1, (sourceSize.height * scale).rounded(.down))
            )
            let format = UIGraphicsImageRendererFormat.default()
            format.opaque = true
            // `UIGraphicsImageRenderer` otherwise adopts the device's 2×/3× screen scale;
            // 2048 points would then quietly become a 4096/6144-pixel retained file. Use a
            // one-pixel-per-unit renderer so the stated maximum is an actual pixel ceiling.
            format.scale = 1
            let reduced = UIGraphicsImageRenderer(size: outputSize, format: format).image { _ in
                image.draw(in: CGRect(origin: .zero, size: outputSize))
            }
            for quality in [0.82, 0.70, 0.58, 0.46] {
                guard let candidate = reduced.jpegData(compressionQuality: quality) else { continue }
                if candidate.count <= targetMaximumBytes { return candidate }
            }
        }
        return nil
    }
}

/// A deliberately small, owner-initiated camera bridge for food photos. The resulting image is
/// kept only in the presenting sheet's memory: it is not written to Photos, the App sandbox, an
/// export, or a network request unless the owner later reviews the food list and confirms the
/// replacement. This is intentionally separate from the iPhone-only live-pose camera pipeline.
private struct PrivateFoodCameraPicker: UIViewControllerRepresentable {
    let onImage: (Data) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onImage: onImage, onCancel: onCancel) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraDevice = .rear
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_: UIImagePickerController, context _: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let onImage: (Data) -> Void
        private let onCancel: () -> Void
        private var hasCompleted = false

        init(onImage: @escaping (Data) -> Void, onCancel: @escaping () -> Void) {
            self.onImage = onImage
            self.onCancel = onCancel
        }

        func imagePickerControllerDidCancel(_: UIImagePickerController) {
            finishWithCancel()
        }

        func imagePickerController(
            _: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            // JPEG is an in-memory interchange value here; private, protected file persistence
            // still happens only inside the confirmation transaction below.
            guard let image = info[.originalImage] as? UIImage,
                  let data = PrivateFoodPhotoPreparation.normalizedJPEG(from: image) else {
                finishWithCancel()
                return
            }
            guard !hasCompleted else { return }
            hasCompleted = true
            onImage(data)
        }

        private func finishWithCancel() {
            guard !hasCompleted else { return }
            hasCompleted = true
            onCancel()
        }
    }
}

private struct PrivatePendingPhotoPreview: View {
    let data: Data

    var body: some View {
        if let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, minHeight: 150, maxHeight: 190)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityLabel("待确认的本机餐食照片")
        } else {
            Label("照片预览不可用；请移除后重拍", systemImage: "photo.badge.exclamationmark")
                .foregroundStyle(CoachPalette.recovery)
        }
    }
}
#endif

/// The setup, check-in and food forms all include multiline or numeric entry. On iPhone, let a
/// person swipe their way out of the keyboard instead of forcing a hidden bottom button or an
/// arbitrary keyboard-specific “done” control. Navigation-bar save/record controls remain
/// visible and are still the only persistence actions.
private extension View {
    @ViewBuilder
    func coachKeyboardDismissal() -> some View {
        #if os(iOS)
        scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") {
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder),
                            to: nil,
                            from: nil,
                            for: nil
                        )
                    }
                }
            }
        #else
        self
        #endif
    }
}

private struct DailyCalorieOverviewCard: View {
    let summary: DailyCalorieIntakeSummary
    @State private var showingRecordedSources = true

    private var sourceSummary: String {
        let labels = summary.recordedEntries.map { entry in
            entry.label.components(separatedBy: " · ").first ?? entry.label
        }
        guard !labels.isEmpty else { return "尚无餐食记录" }
        let visible = labels.prefix(2).joined(separator: "、")
        return labels.count > 2 ? "\(visible) 等 \(labels.count) 项" : visible
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("已记录的餐食估算")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    if let framework = summary.framework, let target = summary.targetEstimate {
                        Text("目标约 \(target) kcal")
                            .font(.subheadline.monospacedDigit().weight(.bold))
                        Text("参考 \(framework.lowerBound)–\(framework.upperBound) kcal")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    } else {
                        Text("先设置每日额度")
                            .font(.subheadline.weight(.semibold))
                    }
                }
                Spacer(minLength: 8)
                if let threshold = summary.threshold {
                    Label(threshold == .within ? "正常" : "注意", systemImage: threshold.needsAttention ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(threshold.needsAttention ? CoachPalette.recovery : CoachPalette.completed)
                }
            }

            HStack(spacing: 12) {
                calorieMetric(
                    title: "已吃",
                    value: summary.recordedRange.map(rangeValue) ?? "—",
                    unit: summary.recordedRange == nil ? nil : "kcal",
                    tint: CoachPalette.action,
                    detail: summary.recordedRange == nil ? nil : "\(summary.recordedEntries.count) 项记录 · 估算范围"
                )
                Divider().frame(height: 56)
                calorieMetric(
                    title: "还可吃",
                    value: remainingText,
                    unit: summary.remainingRange == nil ? nil : "kcal",
                    tint: summary.threshold?.needsAttention == true ? CoachPalette.recovery : CoachPalette.completed,
                    detail: summary.remainingRange == nil ? nil : "估算范围"
                )
            }

            if !summary.recordedEntries.isEmpty {
                Label("来自：\(sourceSummary)", systemImage: "list.bullet")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.primary)
            }

            if let progress = summary.progressRange {
                ProgressView(value: progress.upperBound)
                    .tint(summary.threshold?.needsAttention == true ? CoachPalette.recovery : CoachPalette.completed)
                if progress.lowerBound < progress.upperBound {
                    Text("进度按估算上限")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else if summary.framework == nil {
                Text("到“我的 → 每日热量参考”补齐资料，由 App 计算后确认。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if summary.entriesMissingCalories > 0 {
                Text("有旧餐食缺少热量，补录前不显示虚假的剩余额度。")
                    .font(.footnote)
                    .foregroundStyle(CoachPalette.recovery)
            }

            if let signal = summary.recordedSignal {
                Label(shortGuidance(for: signal), systemImage: "arrow.right.circle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(signal.needsAttention ? CoachPalette.recovery : CoachPalette.completed)
            }

            if !summary.recordedEntries.isEmpty {
                DisclosureGroup(isExpanded: $showingRecordedSources) {
                    ForEach(summary.recordedEntries) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            LabeledContent(entry.label, value: entry.estimatedRange.map(rangeValue) ?? "未估算")
                            Text(entry.estimateSourceLabel ?? "未估算，未计入总范围")
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                    Text("仅汇总这里列出的本机记录；范围是估算，不是称重。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } label: {
                    Label("来自 \(summary.recordedEntries.count) 项本机记录", systemImage: "list.bullet")
                }
                .font(.footnote.weight(.semibold))
            }
        }
        .padding(16)
        .background(CoachPalette.actionSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(CoachPalette.actionStroke, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private var remainingText: String {
        if let remaining = summary.remainingRange { return rangeValue(remaining) }
        if summary.framework == nil { return "待计算" }
        if summary.entriesMissingCalories > 0 { return "需补记录" }
        return "尚未记录"
    }

    private func rangeValue(_ range: ClosedRange<Int>) -> String {
        "\(range.lowerBound)–\(range.upperBound)"
    }

    private func calorieMetric(title: String, value: String, unit: String?, tint: Color, detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.title2.monospacedDigit().weight(.bold)).foregroundStyle(tint)
                if let unit { Text(unit).font(.caption2).foregroundStyle(.secondary) }
            }
            if let detail {
                Text(detail)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func shortGuidance(for signal: DailyRecordedCalorieSignal) -> String {
        switch signal {
        case .notAboveReference:
            "下一餐：按原餐卡吃"
        case .mayExceedReference, .exceedsReference:
            "下一餐照常吃，不跳餐"
        }
    }
}

/// Energy stays auditable, but intentionally lives one layer below meal preparation. A total is
/// useful only when the person can also see the local records that produced it.
private struct MealEstimateHistoryView: View {
    let summary: DailyCalorieIntakeSummary

    var body: some View {
        List {
            Section {
                DailyCalorieOverviewCard(summary: summary)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
            } footer: {
                Text("这里只汇总你主动保存的餐食记录；没有记录就不会显示“已吃”。照片与文字只能给保守区间，不是称重结果。")
            }
        }
        .navigationTitle("餐食记录与估算")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .listStyle(.insetGrouped)
        #endif
    }
}

private extension CalendarDayStatus {
    var foregroundColor: Color {
        switch self {
        case .recovery: CoachPalette.recovery
        case .completed: CoachPalette.completed
        case .partiallyCompleted: CoachPalette.partial
        case .skipped: CoachPalette.skipped
        case .today: CoachPalette.action
        case .unrecorded: .secondary
        case .upcoming: .secondary
        }
    }

    var backgroundColor: Color {
        switch self {
        case .recovery: CoachPalette.recovery.opacity(0.14)
        case .completed: CoachPalette.completed.opacity(0.14)
        case .partiallyCompleted: CoachPalette.partial.opacity(0.14)
        case .skipped: CoachPalette.skipped.opacity(0.13)
        case .today: CoachPalette.action.opacity(0.12)
        case .unrecorded: .gray.opacity(0.10)
        case .upcoming: .gray.opacity(0.14)
        }
    }

    var highlightsToday: Bool { self == .today }
}

private struct WeeklyExecutionDayCard: View {
    let day: WeeklyExecutionDay

    private var label: String {
        day.date.formatted(.dateTime.weekday(.narrow))
    }

    private var foregroundColor: Color {
        guard let status = day.status else { return .secondary }
        return status.foregroundColor
    }

    private var backgroundColor: Color {
        guard let status = day.status else { return .gray.opacity(0.08) }
        return status.backgroundColor
    }

    private var symbol: String {
        guard let status = day.status else { return "minus" }
        return status.symbolName
    }

    private var description: String {
        guard let dayIndex = day.dayIndex else { return "非计划日，不计完成率" }
        guard let status = day.status else { return "第\(dayIndex)天" }
        if day.isObservedPlanDay {
            return "第\(dayIndex)天，\(status.label)，完成 \(day.completedActions ?? 0)/3 项"
        }
        return "第\(dayIndex)天，\(status.label)，尚未计入本周完成率"
    }

    var body: some View {
        VStack(spacing: 3) {
            Text(label).font(.caption.weight(.semibold))
            Image(systemName: symbol)
                .font(.caption.weight(.bold))
                .accessibilityHidden(true)
            Text(day.isObservedPlanDay ? "\(day.completedActions ?? 0)/3" : "—")
                .font(.caption2.monospacedDigit())
        }
        .frame(maxWidth: .infinity, minHeight: 58)
        .foregroundStyle(foregroundColor)
        .background(backgroundColor, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityLabel(description)
    }
}

/// Seven compact cells are readable at ordinary text sizes, but forcing them into one row at an
/// accessibility size makes the health review look like a truncated mini-table. Switch to a
/// vertical status list instead of shrinking text or creating horizontal overflow.
private struct WeeklyExecutionTrajectory: View {
    let days: [WeeklyExecutionDay]
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(days) { day in
                    accessibleRow(day)
                }
            }
        } else {
            HStack(spacing: 5) {
                ForEach(days) { day in
                    WeeklyExecutionDayCard(day: day)
                }
            }
        }
    }

    private func accessibleRow(_ day: WeeklyExecutionDay) -> some View {
        let status = day.status
        let completionText = day.isObservedPlanDay
            ? "完成 \(day.completedActions ?? 0)/3 项"
            : "尚未计入完成率"
        let detail = day.dayIndex == nil
            ? "非计划日，不计完成率"
            : "\(status?.label ?? "待执行")｜\(completionText)"
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: status?.symbolName ?? "minus")
                .foregroundStyle(status?.foregroundColor ?? .secondary)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(day.date.formatted(.dateTime.weekday(.wide)))
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(status?.foregroundColor ?? .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// 应放进未来 iOS App target 的首屏结构。领域规则保留在跨平台模块中，方便独立校验。
public struct CoachAppShell: View {
    @State private var plan: TodayPlan
    @State private var privateData: PrivateCoachData
    /// The last payload that actually reached the App-private store. If an autosave fails, the
    /// UI returns here instead of leaving a visible-but-undurable completion, expense or setting.
    @State private var lastPersistedPrivateData: PrivateCoachData?
    @State private var isRevertingFailedPersistence = false
    /// A settings action that must persist before touching a system side effect (for example,
    /// notifications) already performed a successful write. Skip only the matching next
    /// autosave, then still refresh the plan and paired Watch from that durable value.
    @State private var immediatelyPersistedDataAwaitingObservation: PrivateCoachData?
    @State private var showingHealthStatus = false
    @State private var showingPlanChanges = false
    @State private var showingFirstRun = false
    /// An absent store has no owner profile yet. Keep the temporary in-memory shell read-only
    /// until the person explicitly finishes first-run setup; deleting all data must not silently
    /// recreate a blank owner record on the next state refresh.
    @State private var awaitingInitialProfileSetup = false
    @State private var persistenceStatus: String?
    /// If an existing private profile cannot be read, do not render a fresh writable profile
    /// over it. The recovery surface is intentionally read-only until another load succeeds.
    @State private var localDataRecoveryRequired = false
    @Environment(\.scenePhase) private var scenePhase
    #if os(iOS)
    #endif

    public init(plan: TodayPlan? = nil) {
        let requestedPlan = plan ?? Self.planForCurrentDate()
        switch CoachPrivateStorage.loadLastOwnerDataOutcome() {
        case let .loaded(loaded):
            let substitutedPlan = MealSubstitutionService.appliedPlan(for: requestedPlan, in: loaded)
            _plan = State(initialValue: HealthCheckInService.replayedPlan(for: substitutedPlan.date, plan: substitutedPlan, data: loaded))
            _privateData = State(initialValue: loaded)
            _lastPersistedPrivateData = State(initialValue: loaded)
            _showingFirstRun = State(initialValue: false)
        case .absent:
            _plan = State(initialValue: requestedPlan)
            _privateData = State(initialValue: PrivateCoachData(profile: UserProfile(displayName: "我")))
            _lastPersistedPrivateData = State(initialValue: nil)
            _showingFirstRun = State(initialValue: true)
            _awaitingInitialProfileSetup = State(initialValue: true)
        case .unreadable:
            _plan = State(initialValue: requestedPlan)
            _privateData = State(initialValue: PrivateCoachData(profile: UserProfile(displayName: "我")))
            _lastPersistedPrivateData = State(initialValue: nil)
            _showingFirstRun = State(initialValue: false)
            _localDataRecoveryRequired = State(initialValue: true)
            _persistenceStatus = State(initialValue: "本地资料未能读取：已锁定新建与保存，原资料未被覆盖、删除或上传。")
        }
    }

    public var body: some View {
        Group {
            if localDataRecoveryRequired {
                LocalDataRecoveryView(onRetry: retryLoadingPrivateData)
            } else {
            #if os(macOS)
            DesktopCoachShell(
                plan: $plan,
                privateData: $privateData,
                showingHealthStatus: $showingHealthStatus,
                showingPlanChanges: $showingPlanChanges,
                onDeleteAllLocalData: beginFreshProfileAfterDeletion,
                onPersistImmediately: persistBeforeSystemSideEffect
            )
            #else
            #if os(iOS)
            // Size classes describe the current window, not the device.  Some large iPhones in
            // landscape can report a regular horizontal size class; treating that as an iPad
            // would unexpectedly replace the phone's five-tab task bar with a sidebar.  Use the
            // idiom for the top-level shell, while each screen still adapts its internal layout
            // to the available width and Dynamic Type.
            if UIDevice.current.userInterfaceIdiom == .pad {
                TabletCoachShell(
                    plan: $plan,
                    privateData: $privateData,
                    showingHealthStatus: $showingHealthStatus,
                    showingPlanChanges: $showingPlanChanges,
                    onDeleteAllLocalData: beginFreshProfileAfterDeletion,
                    onPersistImmediately: persistBeforeSystemSideEffect
                )
            } else {
                CompactCoachTabs(
                    plan: $plan,
                    privateData: $privateData,
                    showingHealthStatus: $showingHealthStatus,
                    showingPlanChanges: $showingPlanChanges,
                    onDeleteAllLocalData: beginFreshProfileAfterDeletion,
                    onPersistImmediately: persistBeforeSystemSideEffect
                )
            }
            #else
            CompactCoachTabs(
                plan: $plan,
                privateData: $privateData,
                showingHealthStatus: $showingHealthStatus,
                showingPlanChanges: $showingPlanChanges,
                onDeleteAllLocalData: beginFreshProfileAfterDeletion,
                onPersistImmediately: persistBeforeSystemSideEffect
            )
            #endif
            #endif
            }
        }
        .onAppear {
            if !awaitingInitialProfileSetup { publishWatchDailyCard() }
        }
        .onReceive(NotificationCenter.default.publisher(for: PlanSchedule.didRestartNotification)) { _ in
            refreshPlanForCurrentDate(force: true)
        }
        .onChange(of: privateData) { _, data in
            // A meal substitution can also be confirmed or reverted from a calendar-day detail,
            // where the detail owns a temporary plan binding. Rebuild the shell's displayed day
            // from the saved private state so "今天", "吃什么", and the paired Watch never keep
            // showing an old meal until the App happens to be reopened.
            guard !awaitingInitialProfileSetup else { return }
            if isRevertingFailedPersistence {
                // `privateData` was restored from a known durable snapshot after a failed save.
                // Rebuild and republish from that snapshot, but do not turn the rollback itself
                // into another write attempt.
                isRevertingFailedPersistence = false
                refreshDisplayedPlanAfterPrivateChange(data)
                publishWatchDailyCard()
                return
            }
            if immediatelyPersistedDataAwaitingObservation == data {
                immediatelyPersistedDataAwaitingObservation = nil
                refreshDisplayedPlanAfterPrivateChange(data)
                publishWatchDailyCard()
                return
            }
            refreshDisplayedPlanAfterPrivateChange(data)
            if savePrivateData(data) {
                publishWatchDailyCard()
            } else {
                // Some photo/deletion/HealthKit transactions intentionally make their own
                // durable write before mutating this binding, so their file/photo ordering is
                // atomic. If the following normal autosave happens to fail, reload first: a
                // just-written transaction must not be visually rolled back to an older shell
                // snapshot merely because its redundant second write failed.
                switch CoachPrivateStorage.loadLastOwnerDataOutcome() {
                case let .loaded(durableData):
                    lastPersistedPrivateData = durableData
                    if durableData == data {
                        persistenceStatus = nil
                        publishWatchDailyCard()
                    } else {
                        isRevertingFailedPersistence = true
                        privateData = durableData
                    }
                case .absent, .unreadable:
                    if let lastPersistedPrivateData {
                        isRevertingFailedPersistence = true
                        privateData = lastPersistedPrivateData
                    }
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                refreshPlanForCurrentDate()
                if !awaitingInitialProfileSetup { publishWatchDailyCard() }
            }
        }
        // A foreground iPhone can stay on the same screen across midnight. Refresh its day card
        // at the next local day boundary rather than leaving yesterday's actions interactive.
        // Returning to the app still performs the same refresh above if the process was inactive.
        .task(id: Calendar.current.startOfDay(for: plan.date)) {
            while !Task.isCancelled {
                let now = Date()
                guard let nextDay = Calendar.current.nextDate(
                    after: now,
                    matching: DateComponents(hour: 0, minute: 0, second: 0),
                    matchingPolicy: .nextTime
                ) else { return }
                let wait = max(1, nextDay.timeIntervalSince(now))
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                guard !Task.isCancelled else { return }
                refreshPlanForCurrentDate()
                if !awaitingInitialProfileSetup { publishWatchDailyCard() }
            }
        }
        .sheet(isPresented: $showingFirstRun) {
            FirstRunWelcomeView { input in
                privateData.profile = input.applying(to: privateData.profile)
                // The default name may remain “我”; persist explicitly so a first-run dismissal
                // is not shown again just because the value happened to be unchanged. Do not
                // dismiss the only setup surface until this first private record is actually
                // durable: otherwise an unavailable data-protection/file system could make the
                // person believe an account/profile exists when the App has no saved owner yet.
                guard savePrivateData(privateData) else { return false }
                awaitingInitialProfileSetup = false
                showingFirstRun = false
                // The profile change occurred while autosave was deliberately suspended. Publish
                // only after its explicit durable save succeeds, so a paired Watch never gets a
                // temporary first-run card and does receive the newly confirmed owner day card.
                publishWatchDailyCard()
                return true
            }
            // The main shell contains controls which mutate an in-memory day card.  Until this
            // first owner record has been written, letting the sheet be swiped away would expose
            // those controls while autosave is deliberately suspended. Keep onboarding modal
            // until either its durable save succeeds or the App is closed; this is not a system
            // permission prompt and does not prevent the person from choosing later feature
            // permissions individually.
            .interactiveDismissDisabled(awaitingInitialProfileSetup)
        }
        .overlay(alignment: .bottom) {
            if let persistenceStatus {
                Text(persistenceStatus)
                    .font(.footnote)
                    .padding(10)
                    .background(.regularMaterial, in: Capsule())
                    .padding()
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .top) {
            if PlanSchedule.hasNotStarted() {
                Label(preparationBannerText, systemImage: "calendar.badge.clock")
                    .font(.footnote.weight(.medium))
                    .padding(10)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.top, 8)
                    .accessibilityLabel(preparationBannerText)
                    .allowsHitTesting(false)
            }
        }
    }

    /// Returns a truthful persistence result for the few actions (notably first-run setup) that
    /// cannot safely advance their UI state until a private owner record exists on disk.
    @discardableResult
    private func savePrivateData(_ data: PrivateCoachData) -> Bool {
        guard !localDataRecoveryRequired else {
            persistenceStatus = "本地资料仍在恢复保护中：没有保存、覆盖、删除或上传任何资料。"
            return false
        }
        do {
            try CoachPrivateStorage.saveLastOwnerData(data)
            lastPersistedPrivateData = data
            persistenceStatus = nil
            return true
        } catch {
            persistenceStatus = "本地资料暂未保存；请勿删除 App，稍后重试。"
            return false
        }
    }

    /// For a user action that needs the private JSON to be durable before it requests or changes
    /// a system-owned resource. The corresponding `onChange` only republishes UI/Watch state;
    /// it must not write the identical payload a second time and risk a false failure banner.
    private func persistBeforeSystemSideEffect(_ data: PrivateCoachData) -> Bool {
        guard savePrivateData(data) else {
            // The child setting screen has already changed its binding before it reaches this
            // gate.  Roll that transient value back immediately, otherwise the normal autosave
            // observer could get a later chance to persist a schedule that this action just
            // truthfully reported as not saved.  No system permission or notification work is
            // started on this path.
            if let lastPersistedPrivateData {
                isRevertingFailedPersistence = true
                privateData = lastPersistedPrivateData
            }
            return false
        }
        immediatelyPersistedDataAwaitingObservation = data
        return true
    }

    /// Called only after `LocalDataDeletion` has removed the old owner record and its referenced
    /// private photos. The next profile remains in memory until first-run setup is explicitly
    /// completed, so deletion cannot be immediately undone by the shell's normal autosave.
    private func beginFreshProfileAfterDeletion() {
        awaitingInitialProfileSetup = true
        lastPersistedPrivateData = nil
        privateData = PrivateCoachData(profile: UserProfile(displayName: "我"))
        plan = Self.planForCurrentDate()
        persistenceStatus = "此前本机资料已删除。完成新的首次设置前，不会创建或保存新档案。"
        #if canImport(UIKit) && canImport(WatchConnectivity)
        PhoneWatchCompanionBridge.shared.invalidateDailyCard()
        #endif
        showingFirstRun = true
    }

    private func retryLoadingPrivateData() {
        switch CoachPrivateStorage.loadLastOwnerDataOutcome() {
        case let .loaded(loaded):
            let basePlan = Self.planForDate(Date())
            let substitutedPlan = MealSubstitutionService.appliedPlan(for: basePlan, in: loaded)
            plan = HealthCheckInService.replayedPlan(for: substitutedPlan.date, plan: substitutedPlan, data: loaded)
            // This is a read of the existing durable owner record, not a new edit. Let the
            // observer rebuild the visible day-card and republish it, but never turn recovery
            // itself into a redundant write that could fail and make a recovered profile look
            // unavailable again.
            lastPersistedPrivateData = loaded
            immediatelyPersistedDataAwaitingObservation = loaded
            privateData = loaded
            localDataRecoveryRequired = false
            persistenceStatus = nil
            // Do not wait for SwiftUI's change observation to run before replacing the Watch's
            // unavailable context. The iPhone record is already readable and its exact current
            // plan has been rebuilt above, so the paired Watch can safely receive only this
            // minimal current-day card now.
            publishWatchDailyCard()
        case .absent:
            // This path started in an unreadable-existing-profile state. A later “absent” result
            // can be a transient filesystem/protection problem, not proof that the person chose
            // deletion, so remain fail-closed rather than exposing a new profile that could
            // replace the remembered owner on its first save.
            persistenceStatus = "此前本机资料现在未找到，仍保持恢复保护：没有新建、保存、覆盖、删除或上传任何资料。"
        case .unreadable:
            persistenceStatus = "本地资料仍无法读取，继续保持恢复保护：没有保存、覆盖、删除或上传任何资料。"
        }
    }

    private static func planForCurrentDate(date: Date = .now) -> TodayPlan {
        planForDate(date)
    }

    private static func planForDate(_ date: Date) -> TodayPlan {
        if PlanSchedule.hasNotStarted(on: date) { return LaunchPreparationPlan.make(date: date) }
        if PlanSchedule.hasEnded(on: date) { return ProgramCompletionPlan.make(date: date) }
        return PlanSchedule.makePlan(for: date) ?? LaunchPreparationPlan.make(date: date)
    }

    private var preparationBannerText: String {
        let start = PlanSchedule.startDate()?.formatted(.dateTime.year().month().day()) ?? "计划开始日"
        if PlanSchedule.isFinalPreparationDay() {
            return "计划将于 \(start) 开始；今晚只做食材、饭盒和睡眠准备。"
        }
        return "计划将于 \(start) 开始；开始前一晚再准备食材和饭盒。"
    }

    private func refreshDisplayedPlanAfterPrivateChange(_ data: PrivateCoachData) {
        let basePlan = Self.planForDate(plan.date)
        let substitutedPlan = MealSubstitutionService.appliedPlan(for: basePlan, in: data)
        let restoredPlan = HealthCheckInService.replayedPlan(for: substitutedPlan.date, plan: substitutedPlan, data: data)
        if plan != restoredPlan {
            plan = restoredPlan
        }
    }

    private func refreshPlanForCurrentDate(force: Bool = false) {
        let expected = Self.planForCurrentDate()
        guard force || !Calendar.current.isDate(plan.date, inSameDayAs: expected.date) else { return }
        let substitutedPlan = MealSubstitutionService.appliedPlan(for: expected, in: privateData)
        plan = HealthCheckInService.replayedPlan(for: substitutedPlan.date, plan: substitutedPlan, data: privateData)
    }

    /// Watch receives only the current daily-card labels and the safe camera boundary. It never
    /// receives private health summaries, photos, camera frames, pose output, or full profile data.
    private func publishWatchDailyCard() {
        #if canImport(UIKit) && canImport(WatchConnectivity)
        if localDataRecoveryRequired {
            PhoneWatchCompanionBridge.shared.invalidateDailyCard()
            return
        }
        PhoneWatchCompanionBridge.shared.publish(
            plan: plan,
            training: TrainingCatalog.card(for: plan.date)
        )
        #endif
    }
}

/// Failure-safe launch surface. It intentionally exposes no normal planner controls, because
/// any fresh write could replace the last-owner pointer while a recoverable private file exists.
private struct LocalDataRecoveryView: View {
    let onRetry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("本地资料需要恢复", systemImage: "externaldrive.badge.exclamationmark")
        } description: {
            Text("App 检测到已有本机资料但暂时无法读取。为保护历史打卡、状态和私有照片引用，已锁定新建与保存：不会覆盖、删除或上传原资料。请先重试读取；若持续失败，保留 App 与设备上的资料，待更新或获得恢复帮助后再处理。")
        } actions: {
            Button("重试读取本地资料", action: onRetry)
                .buttonStyle(.borderedProminent)
                .accessibilityHint("仅再次读取本机私有资料，不会删除或上传任何内容")
        }
        .padding()
    }
}

/// 首次打开只收集最少的执行背景；不把 HealthKit、相机、照片、通知或位置权限混进启动流程。
/// 这些系统权限都必须在用户进入相应功能并主动点按时再单独请求。
private struct FirstRunWelcomeView: View {
    @State private var displayName = ""
    @State private var primaryGoal = "腰腹、体态与恢复"
    @State private var trainingExperience = "零基础"
    @State private var availableEquipment = ""
    @State private var kitchenSetup = "电饭锅 + 一个电磁炉锅"
    @State private var usesSuggestedRoutine = false
    @State private var workSchedule = ""
    @State private var saveError: String?
    let onContinue: (FirstRunProfileInput) -> Bool

    var body: some View {
        NavigationStack {
            ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "heart.text.square.fill")
                    .font(.system(size: 42))
                    .foregroundStyle(CoachPalette.action)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 8) {
                    Text("你的健康计划，从今天能做的一件事开始")
                        .font(.title2.bold())
                    Text("先写下最少的执行背景；打开后直接给你一张自炊、训练/恢复和睡前准备日卡。后续重大调整始终由你确认。")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("先认识你一点点")
                        .font(.headline)
                    TextField("怎么称呼你（可留空）", text: $displayName)
                    TextField("当前关注点，例如腰腹、体态、睡眠", text: $primaryGoal, axis: .vertical)
                    TextField("运动基础，例如零基础", text: $trainingExperience)
                    TextField("可用器械（可留空）", text: $availableEquipment)
                    TextField("厨房设备", text: $kitchenSetup)
                    Text("两个月计划共 61 天：前 56 天正式餐卡，最后 5 天收尾复盘；默认以“电饭锅 + 一个电磁炉锅”为基准。设备不同只提示你确认，不会自动改菜谱。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .textFieldStyle(.roundedBorder)

                VStack(alignment: .leading, spacing: 8) {
                    Toggle("用建议时间表推荐下一件事", isOn: $usesSuggestedRoutine)
                    if usesSuggestedRoutine {
                        TextField("工作/作息（可留空），例如 10:00–19:00", text: $workSchedule)
                            .textFieldStyle(.roundedBorder)
                        Text("将使用 12:00 第一餐、13:00 午餐、19:00 晚餐、20:00 训练、23:15 睡前准备；可在“我的 → 我的时间表”逐项修改。不会创建通知或把晚起记为失败。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("不设置也没关系：App 会按当前时间推荐仍可执行的一件事，不催补早餐或补练。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    FirstRunBoundaryRow(icon: "lock.fill", text: "资料默认只保存在本机；可在“我的”导出或删除。")
                    FirstRunBoundaryRow(icon: "heart.circle", text: "Apple 健康是可选的：不会在这里自动请求授权。")
                    FirstRunBoundaryRow(icon: "video.slash", text: "实时动作提示需你之后单独开启相机；不录像、不缓存、不上传。")
                    FirstRunBoundaryRow(icon: "bell.slash", text: "通知与附近服务也不会在这里请求；需要时由你在对应页面主动开启。")
                }
                .padding()
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                if let saveError {
                    Label(saveError, systemImage: "externaldrive.badge.exclamationmark")
                        .font(.footnote)
                        .foregroundStyle(CoachPalette.recovery)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel("首次设置未保存：\(saveError)")
                }

                Spacer(minLength: 0)
            }
            }
            .coachKeyboardDismissal()
            .padding()
            .navigationTitle("欢迎")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("开始使用") {
                        let saved = onContinue(FirstRunProfileInput(
                            displayName: displayName,
                            primaryGoal: primaryGoal,
                            trainingExperience: trainingExperience,
                            availableEquipment: availableEquipment,
                            kitchenSetup: kitchenSetup,
                            workSchedule: usesSuggestedRoutine ? workSchedule : nil,
                            dailyRoutineSchedule: usesSuggestedRoutine ? Self.suggestedRoutine : nil
                        ))
                        saveError = saved ? nil : "本机资料暂未保存；请勿删除 App，确认设备存储可用后再点“开始使用”。"
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private static let suggestedRoutine = DailyRoutineSchedule(
        wakeMinutes: 12 * 60,
        breakfastMinutes: 12 * 60 + 30,
        lunchMinutes: 13 * 60,
        dinnerMinutes: 19 * 60,
        trainingMinutes: 20 * 60,
        bedtimePreparationMinutes: 23 * 60 + 15,
        quietStartMinutes: 23 * 60 + 30,
        quietEndMinutes: 9 * 60
    )!
}

private struct FirstRunBoundaryRow: View {
    let icon: String
    let text: String

    var body: some View {
        Label {
            Text(text)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(CoachPalette.action)
        }
    }
}

/// The phone keeps the complete coach surface discoverable: today, training, prep, health and
/// profile are all first-class destinations.  Daily execution remains the first tab, while
/// prep and health no longer hide behind a secondary sheet.
private struct CompactCoachTabs: View {
    @Binding var plan: TodayPlan
    @Binding var privateData: PrivateCoachData
    @Binding var showingHealthStatus: Bool
    @Binding var showingPlanChanges: Bool
    let onDeleteAllLocalData: () -> Void
    let onPersistImmediately: (PrivateCoachData) -> Bool
    @AppStorage("youye.healthCoach.appTheme") private var selectedTheme = AppTheme.seaGlass.rawValue

    var body: some View {
        TabView {
            NavigationStack {
                if PlanSchedule.hasNotStarted() {
                    PreparationDayView(plan: plan)
                } else if PlanSchedule.hasEnded() {
                    ProgramCompletionView(plan: plan, privateData: $privateData)
                } else {
                    TodayView(
                        plan: $plan,
                        privateData: $privateData,
                        showingHealthStatus: $showingHealthStatus,
                        showingPlanChanges: $showingPlanChanges,
                        onPersistImmediately: onPersistImmediately
                    )
                }
            }
            .tabItem { Label("今天", systemImage: "checklist") }

            TrainingHomeView(
                plan: $plan,
                privateData: $privateData,
                onPersistImmediately: onPersistImmediately
            )
                .tabItem { Label("跟练", systemImage: "play.rectangle.fill") }

            FoodHomeView(
                plan: $plan,
                privateData: $privateData,
                onPersistImmediately: onPersistImmediately
            )
                .tabItem { Label("备餐", systemImage: "fork.knife") }

            HealthHomeView(
                plan: $plan,
                privateData: $privateData,
                onPersistImmediately: onPersistImmediately
            )
                .tabItem { Label("健康", systemImage: "heart.text.square") }

            MyView(privateData: $privateData, onDeleteAllLocalData: onDeleteAllLocalData, onPersistImmediately: onPersistImmediately)
                .tabItem { Label("我的", systemImage: "person.crop.circle") }
        }
        .tint(AppTheme(rawValue: selectedTheme)?.tint ?? CoachPalette.action)
    }
}

#if os(macOS)
/// The desktop app deliberately uses a sidebar instead of stretching the iPhone tab bar into a
/// wide window. Each destination still keeps the same single-decision daily-card hierarchy.
private struct DesktopCoachShell: View {
    @Binding var plan: TodayPlan
    @Binding var privateData: PrivateCoachData
    @Binding var showingHealthStatus: Bool
    @Binding var showingPlanChanges: Bool
    let onDeleteAllLocalData: () -> Void
    let onPersistImmediately: (PrivateCoachData) -> Bool
    // Keep the desktop entry point aligned with iPhone: open on the daily decision card, while
    // retaining the full follow-along surface as a first-class destination in the sidebar.
    @State private var selection: DesktopDestination? = .today

    private enum DesktopDestination: Hashable, CaseIterable, Identifiable {
        case training, today, food, health, profile

        var id: Self { self }
        var title: String {
            switch self {
            case .today: "今天"
            case .food: "备餐"
            case .training: "跟练"
            case .health: "健康"
            case .profile: "我的"
            }
        }
        var symbol: String {
            switch self {
            case .today: "checklist"
            case .food: "fork.knife"
            case .training: "figure.strengthtraining.traditional"
            case .health: "heart.text.square"
            case .profile: "person.crop.circle"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(DesktopDestination.allCases, selection: $selection) { destination in
                Label(destination.title, systemImage: destination.symbol)
                    .tag(destination)
            }
            .navigationTitle("私人健康教练")
            .listStyle(.sidebar)
        } detail: {
            switch selection ?? .today {
            case .today:
                NavigationStack {
                    if PlanSchedule.hasNotStarted() {
                        PreparationDayView(plan: plan)
                    } else if PlanSchedule.hasEnded() {
                        ProgramCompletionView(plan: plan, privateData: $privateData)
                    } else {
                        TodayView(
                            plan: $plan,
                            privateData: $privateData,
                            showingHealthStatus: $showingHealthStatus,
                            showingPlanChanges: $showingPlanChanges,
                            onPersistImmediately: onPersistImmediately
                        )
                    }
                }
            case .food:
                FoodHomeView(
                    plan: $plan,
                    privateData: $privateData,
                    onPersistImmediately: onPersistImmediately
                )
            case .training:
                TrainingHomeView(
                    plan: $plan,
                    privateData: $privateData,
                    onPersistImmediately: onPersistImmediately
                )
            case .health:
                HealthHomeView(
                    plan: $plan,
                    privateData: $privateData,
                    onPersistImmediately: onPersistImmediately
                )
            case .profile:
                MyView(privateData: $privateData, onDeleteAllLocalData: onDeleteAllLocalData, onPersistImmediately: onPersistImmediately)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Text("Mac 本地版")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Mac 本地版；不读取 iPhone HealthKit 或实时姿态数据")
            }
        }
    }
}
#endif

#if os(iOS)
/// Regular-width iPads get the same native sidebar/detail hierarchy as the Mac. This prevents a
/// wide tablet from presenting five phone tabs above a long page, while keeping every action tied
/// to the same date-scoped daily card.
private struct TabletCoachShell: View {
    @Binding var plan: TodayPlan
    @Binding var privateData: PrivateCoachData
    @Binding var showingHealthStatus: Bool
    @Binding var showingPlanChanges: Bool
    let onDeleteAllLocalData: () -> Void
    let onPersistImmediately: (PrivateCoachData) -> Bool
    @State private var selection: TabletDestination? = .today

    private enum TabletDestination: Hashable, CaseIterable, Identifiable {
        case training, today, food, health, profile

        var id: Self { self }
        var title: String {
            switch self {
            case .today: "今天"
            case .food: "备餐"
            case .training: "跟练"
            case .health: "健康"
            case .profile: "我的"
            }
        }
        var symbol: String {
            switch self {
            case .today: "checklist"
            case .food: "fork.knife"
            case .training: "figure.strengthtraining.traditional"
            case .health: "heart.text.square"
            case .profile: "person.crop.circle"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(TabletDestination.allCases, selection: $selection) { destination in
                Label(destination.title, systemImage: destination.symbol)
                    .tag(destination)
            }
            .navigationTitle("私人健康教练")
            .listStyle(.sidebar)
        } detail: {
            switch selection ?? .today {
            case .today:
                NavigationStack {
                    if PlanSchedule.hasNotStarted() {
                        PreparationDayView(plan: plan)
                    } else if PlanSchedule.hasEnded() {
                        ProgramCompletionView(plan: plan, privateData: $privateData)
                    } else {
                        TodayView(
                            plan: $plan,
                            privateData: $privateData,
                            showingHealthStatus: $showingHealthStatus,
                            showingPlanChanges: $showingPlanChanges,
                            onPersistImmediately: onPersistImmediately
                        )
                    }
                }
            case .food:
                FoodHomeView(
                    plan: $plan,
                    privateData: $privateData,
                    onPersistImmediately: onPersistImmediately
                )
            case .training:
                TrainingHomeView(
                    plan: $plan,
                    privateData: $privateData,
                    onPersistImmediately: onPersistImmediately
                )
            case .health:
                HealthHomeView(
                    plan: $plan,
                    privateData: $privateData,
                    onPersistImmediately: onPersistImmediately
                )
            case .profile:
                MyView(privateData: $privateData, onDeleteAllLocalData: onDeleteAllLocalData, onPersistImmediately: onPersistImmediately)
            }
        }
        .navigationSplitViewStyle(.balanced)
    }
}
#endif

private struct PreparationDayView: View {
    let plan: TodayPlan

    private var startDateText: String {
        PlanSchedule.startDate()?.formatted(.dateTime.year().month().day().weekday()) ?? "计划开始日"
    }

    private var isFinalPreparationDay: Bool { PlanSchedule.isFinalPreparationDay(on: plan.date) }

    /// `plan.dinner` deliberately contains the preparation instructions before launch.  The
    /// preview must instead use the actual first formal day, otherwise a person taps “day one
    /// recipe” and sees the thawing checklist again rather than the meal they are preparing for.
    private var firstDayPlan: TodayPlan? {
        guard let start = PlanSchedule.startDate() else { return nil }
        return PlanSchedule.makePlan(for: start)
    }

    var body: some View {
        List {
            Section {
                Text(isFinalPreparationDay ? "启动准备日" : "计划尚未开始")
                    .font(.largeTitle.bold())
                Text(isFinalPreparationDay
                     ? "两个月计划（61 天）于 \(startDateText) 开始。今晚不计饮食或训练完成，只把开始当天变得更容易。"
                     : "两个月计划（61 天）于 \(startDateText) 开始。现在无需解冻、备餐、训练或打卡；开始前一晚再准备即可。")
                    .foregroundStyle(.secondary)
            }
            Section(isFinalPreparationDay ? "今晚 10 分钟" : "开始前一晚") {
                if isFinalPreparationDay {
                    Label("鸡肉 300g 从冷冻转冷藏", systemImage: "snowflake")
                    Label("西兰花 500g 洗切沥干", systemImage: "carrot")
                    Label("准备 2 个饭盒、保温袋和冰袋", systemImage: "takeoutbag.and.cup.and.straw")
                    Label("23:45 前熄灯", systemImage: "bed.double")
                } else {
                    Text("无需提前处理食材。到开始前一晚再将主蛋白转入冷藏、准备饭盒和冰袋。")
                        .foregroundStyle(.secondary)
                }
            }
            Section("第 1 天预览") {
                if let firstDayPlan {
                    NavigationLink("查看第 1 天晚餐食谱卡") { MealCardView(meal: firstDayPlan.dinner) }
                } else {
                    Text("第 1 天食谱暂不可用；没有创建或修改任何餐食记录。")
                        .foregroundStyle(.secondary)
                }
                Text(isFinalPreparationDay
                     ? "开始当天才显示第 1 天三件事和训练打卡。今晚不需要补练或节食。"
                     : "开始当天才显示第 1 天三件事和训练打卡；本页不产生完成记录。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("今天")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        .listStyle(.insetGrouped)
        #endif
    }
}

private struct ProgramCompletionView: View {
    let plan: TodayPlan
    @Binding var privateData: PrivateCoachData

    private var review: ProgramCompletionReview {
        ProgramCompletionReviewService.make(data: privateData, asOf: .now)
    }

    var body: some View {
        List {
            Section {
                Text("8 周阶段完成")
                    .font(.largeTitle.bold())
                Text("下一阶段不自动开始。先复盘完成率、腰围、睡眠和恢复，再由你确认新的目标、热量框架与训练结构。")
                    .foregroundStyle(.secondary)
            }
            Section("阶段评估｜只读") {
                LabeledContent("已保存执行记录", value: "\(review.recordedPlanDays)/\(review.formalPlanDays) 天")
                LabeledContent("记录完成率", value: "\(Int((review.completionRate * 100).rounded()))%（\(review.recordedCompletedActions)/168 项）")
                if review.unrecordedPlanDays > 0 {
                    Text("\(review.unrecordedPlanDays) 天未记录，不把它们称为失败或自动补练。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if review.explicitlySkippedPlanDays > 0 {
                    LabeledContent("明确跳过", value: "\(review.explicitlySkippedPlanDays) 天")
                }
                if let sleep = review.averageSleepHours {
                    LabeledContent("已记录睡眠均值", value: String(format: "%.1f 小时", sleep))
                }
                if let weight = review.latestWeightKg {
                    LabeledContent("最新体重", value: trendValue(weight, change: review.weightChangeKg, unit: "kg"))
                }
                if let waist = review.latestWaistCm {
                    LabeledContent("最新腰围", value: trendValue(waist, change: review.waistChangeCm, unit: "cm"))
                }
                if !review.protectiveSignals.isEmpty {
                    Text("保护性信号：\(review.protectiveSignals.joined(separator: "、"))")
                        .foregroundStyle(CoachPalette.recovery)
                }
                if !review.skinLabels.isEmpty {
                    Text("皮肤记录：\(review.skinLabels.joined(separator: "、"))")
                        .foregroundStyle(.secondary)
                }
            }
            Section("请你确认后再开始下一阶段") {
                ForEach(review.confirmationChecklist, id: \.self) { item in
                    Label(item, systemImage: "checkmark.circle")
                }
            }
            Section("现在可以做") {
                NavigationLink("查看阶段评估卡") { MealCardView(meal: plan.dinner) }
                Label("轻松走动或恢复动作即可", systemImage: "figure.walk")
                Label("不加量、不补练、不自动新开计划", systemImage: "lock.fill")
            }
        }
        .navigationTitle("今天")
    }

    private func trendValue(_ value: Double, change: Double?, unit: String) -> String {
        let current = String(format: "%.1f %@", value, unit)
        guard let change else { return current }
        return current + String(format: "（%+.1f）", change)
    }
}

private struct GlobalQuickLogMenu: View {
    let onHealth: () -> Void
    let onExpense: () -> Void

    var body: some View {
        Menu {
            Button("记录身体状态", systemImage: "heart.text.square", action: onHealth)
            Button("记录实际支出", systemImage: "yensign.circle", action: onExpense)
        } label: {
            Image(systemName: "plus.circle")
        }
        .accessibilityLabel("快速记录")
        .accessibilityHint("添加身体状态或实际支出；不会记录餐食")
    }
}

/// The Today screen gives the next meal a single obvious path. Other daily logs stay available,
/// but deliberately secondary, so the home screen does not compete with itself.
private struct TodayNextMealLogActions: View {
    let nextMealSlot: MealSlot
    let onRecordMeal: (MealSlot) -> Void
    let onPhotoMeal: () -> Void
    let onRecordSnack: () -> Void
    let onHealth: () -> Void
    let onExpense: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Button {
                onPhotoMeal()
            } label: {
                Label("拍照记\(nextMealSlot.displayName)", systemImage: "camera.fill")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(CoachPalette.action)
            .accessibilityLabel("拍照记录\(nextMealSlot.displayName)实际吃了什么")

            HStack(spacing: 10) {
                Button {
                    onRecordMeal(nextMealSlot)
                } label: {
                    Label("手动记录", systemImage: "square.and.pencil")
                        .frame(maxWidth: .infinity, minHeight: 40)
                }

                Menu {
                    Button("加餐 / 零食", systemImage: "takeoutbag.and.cup.and.straw", action: onRecordSnack)
                    Button("身体状态", systemImage: "heart.text.square", action: onHealth)
                    Button("实际支出", systemImage: "yensign.circle", action: onExpense)
                } label: {
                    Label("更多记录", systemImage: "ellipsis.circle")
                        .frame(maxWidth: .infinity, minHeight: 40)
                }
            }
            .buttonStyle(.bordered)
            .tint(CoachPalette.action)
        }
    }
}

/// Carries the selected meal through SwiftUI sheet presentation as one immutable value. Using a
/// separate `Bool` plus a mutable slot can present the sheet before the slot update is rendered,
/// which previously made a dinner tap occasionally open the breakfast form. A fresh identity is
/// also deliberate: reopening the same slot must construct a new sheet rather than reuse stale
/// text or a photo draft from the previous breakfast/lunch/dinner entry.
private struct ActualMealLogDestination: Identifiable {
    let id = UUID()
    let slot: MealSlot
    /// The home-screen photo shortcut must enter the correct meal form first, so a dinner photo
    /// cannot accidentally be stored as an extra snack. Camera opening remains user initiated.
    let startsWithCamera: Bool

    init(slot: MealSlot, startsWithCamera: Bool = false) {
        self.slot = slot
        self.startsWithCamera = startsWithCamera
    }
}

private struct TodayView: View {
    @Binding var plan: TodayPlan
    @Binding var privateData: PrivateCoachData
    @Binding var showingHealthStatus: Bool
    @Binding var showingPlanChanges: Bool
    let onPersistImmediately: (PrivateCoachData) -> Bool
    @State private var showingMealSubstitution = false
    @State private var actualMealDestination: ActualMealLogDestination?
    @State private var showingExpense = false
    @State private var showingAvailableIngredients = false
    @State private var showingAllGuidance = false
    @State private var completionStatus: String?
    private var completion: DailyCompletion? {
        TodayFeature.completion(for: plan, in: privateData)
    }

    private var guidance: [String] {
        HealthCheckInService.guidance(for: plan.date, plan: plan, data: privateData)
    }

    /// Keep the first glance useful without hiding the full, already-recorded care boundary.
    /// The source order is deliberate: recovery and safety instructions precede comfort tips.
    private var visibleGuidance: [String] {
        guard !showingAllGuidance else { return guidance }
        return DailyGuidance.initiallyVisible(guidance)
    }

    private var hasCollapsedGuidance: Bool {
        guidance.count > visibleGuidance.count
    }

    private var healthSummary: DailyHealthStatusSummary? {
        HealthCheckInService.summary(for: plan.date, in: privateData)
    }

    private var todayStatus: HealthStatus? {
        let entries = privateData.datedHealthStatusNotes.filter {
            Calendar.current.isDate($0.date, inSameDayAs: plan.date)
        }
        return HealthStatusHistoryAggregation.dailyAggregates(from: entries).first?.status
    }

    private var sustainableProgress: SustainableGoalProgress {
        SustainableGoalProgress.current(data: privateData, date: plan.date)
    }

    /// Imported exercise is surfaced on Today so a long ride is not hidden in Health. It is
    /// informational only: the coach never silently marks the formal session complete or adds
    /// extra training because an external workout exists.
    private var recentImportedWorkouts: [ImportedWorkoutRecord] {
        let lowerBound = Calendar.current.date(byAdding: .day, value: -2, to: plan.date) ?? plan.date
        return privateData.importedWorkoutRecords
            .filter { $0.startedAt >= lowerBound && $0.startedAt <= Date() }
            .sorted { $0.startedAt > $1.startedAt }
    }

    private var flexibleRecommendation: FlexibleTrainingRecommendation {
        FlexibleTrainingAdvisor.recommendation(
            for: plan,
            status: todayStatus,
            trainingAlreadyCompleted: completion?.trainingOrRecoveryCompleted == true
        )
    }

    private var unplannedMealUpperBound: Int? {
        UnplannedMealDaySummary.estimatedUpperBound(for: plan.date, logs: privateData.unplannedMealLogs)
    }

    private var unplannedMealSignal: UnplannedMealSpaceSignal {
        UnplannedMealDaySummary.spaceSignal(
            for: plan.date,
            logs: privateData.unplannedMealLogs,
            confirmedFramework: privateData.profile.dailyCalorieFramework
        )
    }

    private var recoverySupport: RecoveryDaySupport? {
        RecoveryDaySupportService.make(for: plan)
    }

    private var isSkipped: Bool { completion?.isSkipped == true }

    private var nextStep: TodayNextStep {
        TodayNextStepAdvisor.recommend(plan: plan, completion: completion, schedule: privateData.profile.dailyRoutineSchedule)
    }

    private var nextMealSlot: MealSlot {
        TodayNextStepAdvisor.quickLogMealSlot(
            plan: plan,
            completion: completion,
            schedule: privateData.profile.dailyRoutineSchedule
        )
    }

    private var todayTrainingContext: String {
        let time = (privateData.profile.dailyRoutineSchedule?.trainingMinutes).map {
            String(format: "%02d:%02d", $0 / 60, $0 % 60)
        } ?? "时间未设"
        let goal = privateData.profile.primaryGoal?.trimmingCharacters(in: .whitespacesAndNewlines)
        let weight = privateData.profile.targetWeightKg.map { String(format: "目标 %.1f kg", $0) }
        let goalSummary: String
        switch (goal?.isEmpty == false ? goal : nil, weight) {
        case let (goal?, weight?): goalSummary = "\(goal) · \(weight)"
        case let (goal?, nil): goalSummary = goal
        case let (nil, weight?): goalSummary = weight
        case (nil, nil): goalSummary = "还未设置目标"
        }
        return "\(time) · \(goalSummary)"
    }

    private var todayGoalSummary: String {
        let goal = privateData.profile.primaryGoal?.trimmingCharacters(in: .whitespacesAndNewlines)
        let weight = privateData.profile.targetWeightKg.map { String(format: "目标 %.1f kg", $0) }
        switch (goal?.isEmpty == false ? goal : nil, weight) {
        case let (goal?, weight?): return "\(goal) · \(weight)"
        case let (goal?, nil): return goal
        case let (nil, weight?): return weight
        case (nil, nil): return "还未设置目标"
        }
    }

    /// The Today tab is a post-plan summary, but it must never send someone to food before the
    /// unfinished scheduled training. Recovery and sleep safeguards still route through the
    /// existing advisor once a training action is no longer pending.
    private var trainingNeedsAttention: Bool {
        !isSkipped && completion?.trainingOrRecoveryCompleted != true
    }

    private var todayFocus: TodayFocus {
        if nextStep.kind == .training || nextStep.kind == .recovery {
            if plan.trainingMode == .recovery {
                return TodayFocus(
                    eyebrow: "今天的安排",
                    title: "按恢复版完成即可",
                    detail: "不加量、不补练；按身体状态选择轻走、呼吸或休息。",
                    context: todayTrainingContext,
                    action: "查看恢复安排",
                    symbol: "shield.lefthalf.filled",
                    color: CoachPalette.recovery
                )
            }
            return TodayFocus(
                eyebrow: "今天的主任务",
                title: TrainingCatalog.card(for: plan.date)?.title ?? "开始视频跟练",
                detail: TrainingCatalog.card(for: plan.date)?.video.durationDisplay ?? "先跟练，再按真实开始到停止的时间核对。",
                context: todayTrainingContext,
                action: "开始跟练",
                symbol: "play.fill",
                color: CoachPalette.action
            )
        }
        return TodayFocus(
            eyebrow: nextStep.eyebrow,
            title: nextStep.title,
            detail: nextStep.detail,
            context: nil,
            action: nextStep.actionLabel,
            symbol: "checkmark.circle.fill",
            color: nextStep.kind == .recovery ? CoachPalette.recovery : CoachPalette.action
        )
    }

    var body: some View {
        List {
            Section {
                NavigationLink {
                    todayFocusDestination
                } label: {
                    TodayFocusCard(focus: todayFocus)
                }
                .buttonStyle(.plain)
                .accessibilityHint("点按进入今天唯一的优先动作；不会自动记录完成")
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 10, trailing: 0))
                .listRowBackground(Color.clear)
            }

            // Status is intentionally adjacent to the primary action: it is the only input that
            // can safely change today's recommendation. The full trend view remains secondary.
            Section("今日状态") {
                if let healthSummary {
                    Button { showingHealthStatus = true } label: {
                        HStack(spacing: 12) {
                            Image(systemName: healthSummary.hasProtectiveSignal ? "shield.lefthalf.filled" : "checkmark.circle.fill")
                                .foregroundStyle(healthSummary.hasProtectiveSignal ? CoachPalette.recovery : CoachPalette.completed)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(healthSummary.hasProtectiveSignal ? "今天已切换恢复版" : "今天状态已记录")
                                    .font(.headline)
                                Text(healthSummary.labels.joined(separator: " · "))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                } else {
                    Button { showingHealthStatus = true } label: {
                        Label("先记录睡眠、精力、疼痛或经期状态", systemImage: "heart.text.square")
                    }
                    .buttonStyle(.plain)
                }
                NavigationLink {
                    HealthHomeView(plan: $plan, privateData: $privateData, onPersistImmediately: onPersistImmediately)
                } label: {
                    Label("健康详情与趋势", systemImage: "chart.line.uptrend.xyaxis")
                }
                .font(.footnote)
            }

            Section("本周节奏") {
                VStack(alignment: .leading, spacing: 5) {
                    Label(sustainableProgress.sessionSummary, systemImage: sustainableProgress.completedSessions >= sustainableProgress.targetSessions ? "checkmark.seal.fill" : "target")
                        .font(.headline)
                        .foregroundStyle(sustainableProgress.completedSessions >= sustainableProgress.targetSessions ? CoachPalette.completed : CoachPalette.action)
                    Text(sustainableProgress.detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text(sustainableProgress.isProtectedToday ? "今天有保护信号：以恢复为准，不为达标强行训练。" : "这是你设定的最低节奏，不是满勤考核；漏做不补练。")
                        .font(.caption)
                        .foregroundStyle(sustainableProgress.isProtectedToday ? CoachPalette.recovery : .secondary)
                }
            }

            if !recentImportedWorkouts.isEmpty {
                Section("最近运动") {
                    ForEach(recentImportedWorkouts.prefix(3)) { workout in
                        HStack(spacing: 10) {
                            Image(systemName: workout.kind == .cycling ? "bicycle" : workout.kind == .swimming ? "figure.pool.swim" : "figure.walk")
                                .foregroundStyle(CoachPalette.completed)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("已记录 \(workout.kind.displayName) · \(workout.durationMinutes) 分钟")
                                    .font(.subheadline.weight(.semibold))
                                Text("来自 \(workout.source.displayName) · \(workout.startedAt.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    Text("这条运动已计入本周节奏参考；不会自动替代今天计划、增加训练量或修改后续日卡。需要调整时，请使用下方“改选训练”。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("需要调整时") {
                NavigationLink {
                    FlexibleTrainingView(
                        plan: $plan,
                        privateData: $privateData,
                        onPersistImmediately: onPersistImmediately
                    )
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Label("改选训练：\(flexibleRecommendation.recommended.title)", systemImage: flexibleRecommendation.recommended.symbol)
                                .font(.headline)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary)
                        }
                        Text(flexibleRecommendation.reason)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("次级入口 · 可选 \(flexibleRecommendation.options.count) 种 · 最长 20 分钟")
                            .font(.caption)
                            .foregroundStyle(CoachPalette.action)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityHint("这是调整入口；主任务仍是上方今日跟练。选择后不会自动记为完成或改变后续计划")
            }

            // Meal support is intentionally read-only: this surface opens only suggestions and
            // preparation, never meal logging or calorie estimation.
            Section("下一餐") {
                NavigationLink {
                    MealCardView(
                        meal: meal(for: nextMealSlot),
                        profileKitchenSetup: privateData.profile.kitchenSetup
                    )
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Label("查看下一餐餐卡", systemImage: "fork.knife")
                        Text("下一餐：\(nextMealSlot.displayName)。直接查看食材、步骤和备餐时间。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }

            Section("目标与时间") {
                NavigationLink {
                    PlanStartDateSettingsView(privateData: $privateData, onPersistImmediately: onPersistImmediately)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Label("计划开始日", systemImage: "calendar.badge.clock")
                            .font(.headline)
                        Text(PlanSchedule.startDate()?.formatted(.dateTime.year().month().day()) ?? "未设置")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                NavigationLink {
                    GoalSettingsView(privateData: $privateData, onPersistImmediately: onPersistImmediately)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Label("目标与目标体重", systemImage: "scope")
                            .font(.headline)
                        Text(todayGoalSummary)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                NavigationLink {
                    RoutineSettingsView(privateData: $privateData, onPersistImmediately: { onPersistImmediately(privateData) })
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Label("训练与作息时间", systemImage: "clock")
                            .font(.headline)
                        Text(todayTrainingContext)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }

            if !guidance.isEmpty {
                Section("今天建议") {
                    ForEach(visibleGuidance, id: \.self) { item in
                        Label(item, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if hasCollapsedGuidance {
                        Button { showingAllGuidance = true } label: {
                            Label("查看另外 \(guidance.count - visibleGuidance.count) 条建议", systemImage: "chevron.down")
                        }
                    } else if showingAllGuidance, guidance.count > 2 {
                        Button { showingAllGuidance = false } label: {
                            Label("收起建议", systemImage: "chevron.up")
                        }
                    }
                }
            }

            if let completionStatus {
                Section {
                    Text(completionStatus)
                        .font(.footnote)
                        .foregroundStyle(CoachPalette.recovery)
                }
            }
        }
        .navigationTitle("今天")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        .listStyle(.insetGrouped)
        #endif
        .toolbar {
            ToolbarItem(placement: .automatic) {
                        GlobalQuickLogMenu(
                    onHealth: { showingHealthStatus = true },
                    onExpense: { showingExpense = true }
                )
            }
            ToolbarItem(placement: .automatic) {
                Menu {
                    Button("食材不匹配", systemImage: "arrow.triangle.2.circlepath") { showingMealSubstitution = true }
                    Button("计划变更记录", systemImage: "clock.arrow.circlepath") { showingPlanChanges = true }
                    Divider()
                    Button(isSkipped ? "撤回跳过今天" : "跳过今天", systemImage: isSkipped ? "arrow.uturn.backward" : "forward") { toggleSkip() }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("今天的更多操作")
            }
        }
        .sheet(isPresented: $showingHealthStatus) {
            HealthStatusForm(planDate: plan.date, isFormalPlanDay: true, ownerID: privateData.profile.id) { status, submissionID, formOwnerID in
                let result = HealthCheckInService.submit(status, submissionID: submissionID, formOwnerID: formOwnerID, at: .now, plan: plan, data: privateData)
                if let error = result.validationError { return error }
                guard onPersistImmediately(result.data) else { return "状态暂未保存；今天的训练与餐卡没有改变。" }
                plan = result.plan
                privateData = result.data
                showingHealthStatus = false
                return nil
            }
        }
        .sheet(isPresented: $showingPlanChanges) { PlanChangeList(changes: privateData.planChanges) }
        .sheet(isPresented: $showingMealSubstitution) {
            MealSubstitutionForm(planDate: plan.date, plan: $plan, privateData: $privateData)
        }
        .sheet(isPresented: $showingExpense) {
            QuickExpenseForm(privateData: $privateData, onPersistImmediately: onPersistImmediately)
        }
    }

    private var legacyBody: some View {
        List {
            Section {
                TodayDailyCardHeader(plan: plan, completion: completion, recovery: recoverySupport != nil)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
            }

            Section("现在先做这一件") {
                NavigationLink {
                    nextStepDestination
                } label: {
                    TodayNextStepRow(step: nextStep)
                }
                .accessibilityHint("点按进入对应详情；不会自动标记完成或修改计划")
            }

            Section("今日清单") {
                ForEach(TodayFeature.mealActions(plan: plan, completion: completion)) { action in
                    Button {
                        completeMeal(action)
                    } label: {
                        MealCompletionRow(action: action)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(action.title)：\(action.detail)")
                    .accessibilityHint(action.isWaived ? "晚起不需要补早餐；如实际按早餐吃了，可点按记录，不点不记失败" : action.isCompleted ? "点按取消今天这餐完成状态" : "点按标记今天这餐已完成")
                }
                ForEach(TodayFeature.actions(plan: plan, completion: completion).filter { $0.id != .eat }) { action in
                    if action.id == .move, TodayFeature.isTrainingPaused(plan), !action.isCompleted {
                        TodayActionRow(action: action)
                            .accessibilityLabel("\(action.title)：\(action.detail)")
                            .accessibilityHint("今天暂停计划训练；不能标记为训练或恢复完成")
                    } else {
                        Button {
                            completeAction(action)
                        } label: {
                            TodayActionRow(action: action)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(action.title)：\(action.detail)")
                        .accessibilityHint(action.isCompleted ? "点按取消今天这项完成状态" : "点按标记今天这项已完成")
                    }
                }
            }

            Section("今天调整") {
                Button(isSkipped ? "撤回今天的跳过" : "今天不执行：标记为跳过") {
                    toggleSkip()
                }
                .tint(isSkipped ? CoachPalette.action : CoachPalette.skipped)
                Text(isSkipped
                     ? "已明确标记今天跳过；点按可撤回。重新完成任一项也会自动撤回跳过。"
                     : "仅标记今天整张日卡不执行；不会删掉已有完成记录，也不会自动补练、节食或改后续目标。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let completionStatus {
                    Text(completionStatus)
                        .font(.footnote)
                        .foregroundStyle(CoachPalette.recovery)
                }
            }

            if let healthSummary {
                Section("今天的状态") {
                    HStack(spacing: 10) {
                        Image(systemName: healthSummary.hasProtectiveSignal ? "shield.lefthalf.filled" : "checkmark.circle")
                            .foregroundStyle(healthSummary.hasProtectiveSignal ? CoachPalette.recovery : CoachPalette.completed)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(healthSummary.hasProtectiveSignal ? "已按恢复信号调整" : "已记录，按今天感受执行")
                                .font(.headline)
                            Text("更新于 \(healthSummary.updatedAt.formatted(date: .omitted, time: .shortened))")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    Text(healthSummary.labels.joined(separator: " · "))
                        .font(.footnote).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if healthSummary.hasProtectiveSignal {
                        Text("今天不加量、不补练；恢复版已写入变更记录。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }

            if let recoverySupport {
                Section("今天已切换恢复版") {
                    Label(recoverySupport.trainingAction, systemImage: "figure.walk")
                    Label(recoverySupport.foodAction, systemImage: "fork.knife")
                    Label(recoverySupport.bedtimeAction, systemImage: "bed.double")
                    Text("恢复是今天的完成方式，不是失败；目标、热量框架和后续周计划不会自动变化。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("完整日卡") {
                NavigationLink("查看早餐食谱") { MealCardView(meal: plan.breakfast, profileKitchenSetup: privateData.profile.kitchenSetup) }
                NavigationLink("查看午餐食谱") { MealCardView(meal: plan.lunch, profileKitchenSetup: privateData.profile.kitchenSetup) }
                NavigationLink("查看晚餐食谱") { MealCardView(meal: plan.dinner, profileKitchenSetup: privateData.profile.kitchenSetup) }
                NavigationLink("查看训练说明") { TrainingView(plan: plan) }
                Button("查看计划变更记录") { showingPlanChanges = true }
            }

            Section("临时变化") {
                Button("食材不匹配：确认重排一餐") { showingMealSubstitution = true }
                Button("记录今天身体状态") { showingHealthStatus = true }
                Text("重排必须由你确认后才写入当天餐卡；餐食记录已关闭。身体状态只在需要时保护性退阶。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let unplannedMealUpperBound {
                Section("额外加餐后的下一步") {
                    Text("今天已记录的额外加餐/零食估算上限合计：约 \(unplannedMealUpperBound) kcal")
                        .font(.headline)
                    Text(unplannedMealSignal.displayText)
                        .font(.footnote)
                        .foregroundStyle(unplannedMealSignal == .mayExceedDailyFramework ? CoachPalette.recovery : .secondary)
                    Text("这不是全天总摄入，也不代表已超标。下一餐正常回到今天原餐卡；不补练、不挨饿。若食材不匹配，再拍现有食材并确认重排。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if !guidance.isEmpty {
                Section("今天的调整") {
                    ForEach(guidance, id: \.self) { Text($0).foregroundStyle(.secondary) }
                }
            }
        }
        .navigationTitle("今天")
            .sheet(isPresented: $showingHealthStatus) {
                HealthStatusForm(planDate: plan.date, isFormalPlanDay: true, ownerID: privateData.profile.id) { status, submissionID, formOwnerID in
                    let result = HealthCheckInService.submit(status, submissionID: submissionID, formOwnerID: formOwnerID, at: .now, plan: plan, data: privateData)
                    if let error = result.validationError { return error }
                    // A saved status can immediately turn today's plan into recovery.  Make the
                    // status, its audit record, and the matching day card durable as one owner
                    // action before the sheet disappears or the visible plan changes.
                    do {
                        try CoachPrivateStorage.saveLastOwnerData(result.data)
                    } catch {
                        return "状态暂未保存；今天的训练与餐卡没有改变。请勿删除 App，确认设备存储可用后重试。"
                    }
                    plan = result.plan
                    privateData = result.data
                    showingHealthStatus = false
                    return nil
                }
            }
        .sheet(isPresented: $showingPlanChanges) { PlanChangeList(changes: privateData.planChanges) }
        .sheet(isPresented: $showingMealSubstitution) {
            MealSubstitutionForm(planDate: plan.date, plan: $plan, privateData: $privateData)
        }
    }

    @ViewBuilder
    private var nextStepDestination: some View {
        switch nextStep.kind {
        case .breakfast:
            MealCardView(meal: plan.breakfast, profileKitchenSetup: privateData.profile.kitchenSetup)
        case .lunch:
            MealCardView(meal: plan.lunch, profileKitchenSetup: privateData.profile.kitchenSetup)
        case .dinner:
            MealCardView(meal: plan.dinner, profileKitchenSetup: privateData.profile.kitchenSetup)
        case .training:
            if let card = TrainingCatalog.card(for: plan.date) {
                TrainingCardDetail(card: card, plan: $plan, privateData: $privateData)
            } else {
                TrainingView(plan: plan)
            }
        case .recovery:
            TrainingView(plan: plan)
        case .bedtimePreparation, .windDown, .finished, .skipped:
            TodayDetailView(plan: plan, profileKitchenSetup: privateData.profile.kitchenSetup)
        }
    }

    @ViewBuilder
    private var todayFocusDestination: some View {
        if nextStep.kind == .training || nextStep.kind == .recovery {
            if plan.trainingMode == .recovery {
                TrainingView(plan: plan)
            } else if let card = TrainingCatalog.card(for: plan.date) {
                TrainingCardDetail(card: card, plan: $plan, privateData: $privateData)
            } else {
                TrainingView(plan: plan)
            }
        } else {
            nextStepDestination
        }
    }

    private func meal(for slot: MealSlot) -> MealCard {
        switch slot {
        case .breakfast: plan.breakfast
        case .lunch: plan.lunch
        case .dinner: plan.dinner
        }
    }

    private func actualMealLog(for slot: MealSlot) -> ActualMealLog? {
        ActualMealLogService.log(for: plan.date, slot: slot, in: privateData)
    }

    private func openActualMealLog(_ slot: MealSlot, startsWithCamera: Bool = false) {
        actualMealDestination = ActualMealLogDestination(slot: slot, startsWithCamera: startsWithCamera)
    }

    private func toggleMealAsPlanned(_ action: MealCompletionAction) {
        var updatedData = TodayFeature.completingMeal(
            action.id,
            for: plan,
            in: privateData,
            schedule: privateData.profile.dailyRoutineSchedule
        )
        var photoReferenceToDelete: String?
        if action.isCompleted {
            if let existingLog = actualMealLog(for: action.id), existingLog.relationship == .asPlanned {
                updatedData = ActualMealLogService.removing(date: plan.date, slot: action.id, from: updatedData)
                photoReferenceToDelete = ActualMealLogService.photoReferenceToDeleteAfterReplacement(
                    previousReference: existingLog.localPhotoReference,
                    replacementReference: nil,
                    updatedData: updatedData
                )
            }
        } else if actualMealLog(for: action.id) == nil || actualMealLog(for: action.id)?.relationship == .asPlanned {
            let log = ActualMealLog(
                date: plan.date,
                slot: action.id,
                relationship: .asPlanned,
                description: meal(for: action.id).displayTitle,
                estimatedCaloriesRange: PlannedMealEnergyReference.estimatedRange(for: meal(for: action.id))
            )
            if case let .success(recorded) = ActualMealLogService.recording(log, in: updatedData) {
                updatedData = recorded
            }
        }
        guard onPersistImmediately(updatedData) else {
            completionStatus = "这餐记录暂未保存；今天日卡没有改变。"
            return
        }
        privateData = updatedData
        if let photoReferenceToDelete {
            try? PrivateMealPhotoStore.forOwner(privateData.profile.id).delete(localReference: photoReferenceToDelete)
        }
        completionStatus = nil
    }

    private func saveMealLog(slot: MealSlot, relationship: ActualMealRelationship, description: String, portionNote: String?, calories: ClosedRange<Int>, compositionConfirmation: MealCompositionConfirmation?, photoData: Data?, formOwnerID: UUID) -> String? {
        if let error = ActualMealSubmissionPolicy.validationError(
            for: plan.date,
            formOwnerID: formOwnerID,
            currentOwnerID: privateData.profile.id
        ) { return error }
        let existingReference = actualMealLog(for: slot)?.localPhotoReference
        var createdReference: String?
        if let photoData {
            do { createdReference = try PrivateMealPhotoStore.forOwner(privateData.profile.id).save(data: photoData) }
            catch { return "照片暂未能保存到 App 私有目录；本次餐食记录没有改变。" }
        }
        let removesExistingPhoto = portionNote?.contains("照片已移除，保留候选范围") == true
        let log = ActualMealLog(
            date: plan.date,
            slot: slot,
            relationship: relationship,
            description: description,
            portionNote: portionNote,
            localPhotoReference: createdReference ?? (removesExistingPhoto ? nil : existingReference),
            estimatedCaloriesRange: calories,
            compositionConfirmation: compositionConfirmation
        )
        let recordedResult = ActualMealLogService.recording(log, in: privateData)
        var updatedData: PrivateCoachData
        switch recordedResult {
        case let .success(value): updatedData = value
        case let .failure(error):
            if let createdReference { try? PrivateMealPhotoStore.forOwner(privateData.profile.id).delete(localReference: createdReference) }
            return error.message
        }
        if TodayFeature.mealActions(plan: plan, completion: completion)
            .first(where: { $0.id == slot })?.isCompleted != true {
            updatedData = TodayFeature.completingMeal(
                slot,
                for: plan,
                in: updatedData,
                schedule: privateData.profile.dailyRoutineSchedule
            )
        }
        let previousPhotoReferenceToDelete = ActualMealLogService.photoReferenceToDeleteAfterReplacement(
            previousReference: existingReference,
            replacementReference: log.localPhotoReference,
            updatedData: updatedData
        )
        guard onPersistImmediately(updatedData) else {
            if let createdReference { try? PrivateMealPhotoStore.forOwner(privateData.profile.id).delete(localReference: createdReference) }
            return "这餐记录暂未保存，新照片也未保留；请稍后重试。"
        }
        privateData = updatedData
        if let previousPhotoReferenceToDelete {
            try? PrivateMealPhotoStore.forOwner(privateData.profile.id).delete(localReference: previousPhotoReferenceToDelete)
        }
        actualMealDestination = nil
        completionStatus = nil
        return nil
    }

    private func completeMeal(_ action: MealCompletionAction) {
        let updatedData = TodayFeature.completingMeal(
            action.id,
            for: plan,
            in: privateData,
            schedule: privateData.profile.dailyRoutineSchedule
        )
        guard onPersistImmediately(updatedData) else {
            completionStatus = "这餐完成状态暂未保存；今天日卡没有改变。"
            return
        }
        privateData = updatedData
        completionStatus = nil
    }

    private func completeAction(_ action: TodayAction) {
        let updatedData = TodayFeature.completing(action.id, for: plan, in: privateData)
        guard onPersistImmediately(updatedData) else {
            completionStatus = "这项完成状态暂未保存；今天日卡没有改变。"
            return
        }
        privateData = updatedData
        completionStatus = nil
    }

    private func toggleSkip() {
        let updatedData = DailySkipService.toggle(for: plan, in: privateData)
        guard onPersistImmediately(updatedData) else {
            completionStatus = "跳过状态暂未保存；今天日卡没有改变。"
            return
        }
        privateData = updatedData
        completionStatus = nil
    }
}

private struct TodayFocus {
    let eyebrow: String
    let title: String
    let detail: String
    let context: String?
    let action: String
    let symbol: String
    let color: Color
}

/// One unmistakable destination for the Today tab. Supporting logging stays below the fold and
/// does not need to compete with the action that moves the plan forward.
private struct TodayFocusCard: View {
    let focus: TodayFocus

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label(focus.eyebrow, systemImage: focus.symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.84))
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.78))
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(focus.title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                Text(focus.detail)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.82))
                    .fixedSize(horizontal: false, vertical: true)
                if let context = focus.context {
                    Text(context)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.78))
                        .lineLimit(2)
                }
            }
            HStack(spacing: 7) {
                Text(focus.action)
                    .font(.headline)
                Image(systemName: focus.symbol == "play.fill" ? "play.fill" : "arrow.right")
                    .font(.caption.weight(.bold))
            }
            .foregroundStyle(focus.color)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(.white, in: Capsule())
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(focus.color, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct TodayNextStepRow: View {
    let step: TodayNextStep

    private var icon: String {
        switch step.kind {
        case .breakfast, .lunch, .dinner: "fork.knife"
        case .training: "figure.strengthtraining.traditional"
        case .recovery: "shield.lefthalf.filled"
        case .bedtimePreparation: "bed.double.fill"
        case .windDown: "moon.stars.fill"
        case .finished: "checkmark.seal.fill"
        case .skipped: "pause.circle.fill"
        }
    }

    private var color: Color {
        switch step.kind {
        case .recovery: CoachPalette.recovery
        case .finished: CoachPalette.completed
        case .skipped: CoachPalette.skipped
        case .bedtimePreparation: CoachPalette.action
        case .windDown: CoachPalette.recovery
        default: CoachPalette.action
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(color)
                .frame(width: 38, height: 38)
                .background(color.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(step.eyebrow)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color)
                Text(step.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(step.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(step.actionLabel)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(color)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct TodayDetailView: View {
    let plan: TodayPlan
    let profileKitchenSetup: String?

    var body: some View {
        List {
            Section("今天安排") {
                NavigationLink("早餐｜\(plan.breakfast.displayTitle)") { MealCardView(meal: plan.breakfast, profileKitchenSetup: profileKitchenSetup) }
                NavigationLink("午餐｜\(plan.lunch.displayTitle)") { MealCardView(meal: plan.lunch, profileKitchenSetup: profileKitchenSetup) }
                NavigationLink("晚餐｜\(plan.dinner.displayTitle)") { MealCardView(meal: plan.dinner, profileKitchenSetup: profileKitchenSetup) }
                NavigationLink("训练／恢复说明") { TrainingView(plan: plan) }
            }
            Section("睡前准备") {
                ForEach(plan.bedtimePreparation, id: \.self) { item in
                    Label(item, systemImage: "checklist")
                }
            }
        }
        .navigationTitle("今天日卡")
    }
}

private struct TodayActionRow: View {
    let action: TodayAction

    private var iconName: String { action.isCompleted ? "checkmark.circle.fill" : "circle" }
    private var stateColor: Color { action.isCompleted ? CoachPalette.completed : CoachPalette.action }
    private var stateBackground: Color { action.isCompleted ? CoachPalette.completed.opacity(0.12) : CoachPalette.action.opacity(0.08) }
    private var stateBorder: Color { action.isCompleted ? CoachPalette.completed.opacity(0.35) : CoachPalette.action.opacity(0.22) }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.title3)
                .foregroundStyle(stateColor)
            VStack(alignment: .leading, spacing: 3) {
                Text(action.title).font(.headline)
                Text(action.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .background(stateBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(stateBorder, lineWidth: 1)
                .allowsHitTesting(false)
        }
    }
}

private struct MealCompletionRow: View {
    let action: MealCompletionAction

    private var iconName: String { action.isWaived ? "sunset.fill" : action.isCompleted ? "checkmark.circle.fill" : "circle" }
    private var stateColor: Color { action.isWaived ? .secondary : action.isCompleted ? CoachPalette.completed : CoachPalette.action }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.title3)
                .foregroundStyle(stateColor)
            VStack(alignment: .leading, spacing: 3) {
                Text(action.title).font(.headline)
                Text(action.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .background(stateColor.opacity(action.isCompleted || action.isWaived ? 0.12 : 0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(stateColor.opacity(action.isCompleted || action.isWaived ? 0.35 : 0.22), lineWidth: 1)
                .allowsHitTesting(false)
        }
    }
}

private struct NextMealRecipeRow: View {
    let slot: MealSlot
    let meal: MealCard

    private var timeText: String { meal.totalOperationText ?? "总操作待确认" }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "fork.knife.circle.fill")
                .font(.title2)
                .foregroundStyle(CoachPalette.action)
                .frame(width: 42, height: 42)
                .background(CoachPalette.action.opacity(0.10), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text("下一餐 · \(slot.displayName)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CoachPalette.action)
                Text(meal.displayTitle)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Label(timeText, systemImage: "timer")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let firstExecutionStep = meal.firstExecutionStep {
                    Text("现在：\(firstExecutionStep)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

/// The recipe link and the completion control stay separate: opening cooking steps must never
/// silently claim the meal was eaten, while the one-tap check records the planned meal locally.
private struct MealDiaryRow: View {
    let action: MealCompletionAction
    let meal: MealCard
    let actualLog: ActualMealLog?
    let profileKitchenSetup: String?
    let onToggleAsPlanned: () -> Void
    let onRecordDifferent: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            NavigationLink {
                MealCardView(meal: meal, profileKitchenSetup: profileKitchenSetup)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(action.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(CoachPalette.action)
                    Text(meal.displayTitle)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    if let actualLog {
                        Text(actualLog.relationship == .asPlanned
                             ? "已记录：按计划吃了"
                             : "\(actualLog.relationship.displayName)：\(actualLog.description)")
                            .font(.footnote)
                            .foregroundStyle(actualLog.relationship == .asPlanned ? CoachPalette.completed : .secondary)
                            .lineLimit(2)
                        if let portionNote = actualLog.displayPortionNote {
                            Text(portionNote)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        if let energyText = actualLog.energyText {
                            Text(energyText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else if action.isWaived {
                        Text("晚起无需补；未记成吃过")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else if let firstExecutionStep = meal.firstExecutionStep {
                        Label(meal.totalOperationText ?? "总操作待确认", systemImage: "timer")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.secondary)
                        Text("现在：\(firstExecutionStep)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("点餐名查看克数与步骤")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onToggleAsPlanned) {
                Image(systemName: action.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(action.isCompleted ? CoachPalette.completed : CoachPalette.action)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(completionButtonLabel)

            Button(action: onRecordDifferent) {
                VStack(spacing: 1) {
                    Image(systemName: "square.and.pencil")
                        .font(.subheadline.weight(.semibold))
                    Text("记录")
                        .font(.caption2.weight(.semibold))
                }
                .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(CoachPalette.action)
            .accessibilityLabel("记录\(action.title)实际吃了什么")
        }
        .padding(.vertical, 4)
    }

    private var completionButtonLabel: String {
        if action.isCompleted { return "取消\(action.title)完成标记；保留已写的实际餐食" }
        if actualLog?.relationship == .different { return "将\(action.title)标记完成；保留已写的实际餐食" }
        return "\(action.title)按计划吃了"
    }
}

private struct MealCompositionConfirmationFields: View {
    @Binding var composition: MealCompositionConfirmation
    var showsProgress = true

    var body: some View {
        if showsProgress {
            HStack(spacing: 10) {
                ProgressView(value: Double(composition.confirmationCount), total: 6)
                    .tint(composition.isNarrowedByOwner ? CoachPalette.completed : CoachPalette.action)
                Text("\(composition.confirmationCount)/6 已确认")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(composition.isNarrowedByOwner ? CoachPalette.completed : .secondary)
            }
        }
        Picker("主食", selection: $composition.staple) {
            ForEach(MealStapleAmount.allCases) { Text($0.displayName).tag($0) }
        }
        .pickerStyle(.menu)
        Picker("肉／蛋／豆（鸡蛋可按个）", selection: $composition.protein) {
            ForEach(MealProteinAmount.allCases) { Text($0.displayName).tag($0) }
        }
        .pickerStyle(.menu)
        Picker("蔬菜", selection: $composition.vegetables) {
            ForEach(MealVegetableAmount.allCases) { Text($0.displayName).tag($0) }
        }
        .pickerStyle(.menu)
        Picker("烹调油", selection: $composition.addedFat) {
            ForEach(MealAddedFatAmount.allCases) { Text($0.displayName).tag($0) }
        }
        .pickerStyle(.menu)
        Picker("酱汁／饮料／甜点", selection: $composition.extras) {
            ForEach(MealExtrasAmount.allCases) { Text($0.displayName).tag($0) }
        }
        .pickerStyle(.menu)
        Picker("实际吃掉", selection: $composition.consumed) {
            ForEach(MealConsumedFraction.allCases) { Text($0.displayName).tag($0) }
        }
        .pickerStyle(.menu)
    }
}

private struct MealCompositionQuickEditor: View {
    @Binding var composition: MealCompositionConfirmation
    @State private var showsDetails = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("和你平时比，这份更接近？")
                .font(.headline)
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(MealQuickPortionPreset.allCases) { preset in
                    Button {
                        withAnimation(.easeOut(duration: 0.18)) {
                            composition = preset.composition
                        }
                    } label: {
                        VStack(spacing: 5) {
                            Image(systemName: MealQuickPortionPreset.matching(composition) == preset
                                  ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                            Text(preset.title).font(.subheadline.weight(.semibold))
                            Text(preset.subtitle)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity, minHeight: 88)
                        .padding(.horizontal, 4)
                        .foregroundStyle(MealQuickPortionPreset.matching(composition) == preset ? Color.white : Color.primary)
                        .background(
                            MealQuickPortionPreset.matching(composition) == preset
                                ? CoachPalette.action
                                : CoachPalette.action.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            Text("再确认这 3 项，才会收窄范围")
                .font(.subheadline.weight(.semibold))
            Text("预设不猜油和甜饮；不确定就选未知。")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("烹调油", selection: $composition.addedFat) {
                ForEach(MealAddedFatAmount.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.menu)
            Picker("甜饮／酱汁／甜点", selection: $composition.extras) {
                ForEach(MealExtrasAmount.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.menu)
            Picker("实际吃掉", selection: $composition.consumed) {
                ForEach(MealConsumedFraction.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.menu)
            Text(composition.isNarrowedByOwner
                 ? "已按你确认的份量、油、甜饮和吃掉比例收窄；仍不是称重。"
                 : "不确定就保留“未知”，不会假装照片已经看出来。")
                .font(.caption)
                .foregroundStyle(composition.isNarrowedByOwner ? CoachPalette.completed : .secondary)
            Text("不用换算克数或热量。")
                .font(.caption)
                .foregroundStyle(.secondary)
            DisclosureGroup("细调主食、蛋白质和蔬菜", isExpanded: $showsDetails) {
                Picker("主食", selection: $composition.staple) {
                    ForEach(MealStapleAmount.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.menu)
                Picker("肉／蛋／豆", selection: $composition.protein) {
                    ForEach(MealProteinAmount.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.menu)
                Picker("蔬菜", selection: $composition.vegetables) {
                    ForEach(MealVegetableAmount.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.menu)
            }
            .font(.subheadline.weight(.semibold))
        }
    }
}

/// A small, optional language aid for foods people naturally count (eggs, yoghurt cups, buns).
/// It deliberately records only the owner's words; nutrition still stays conservative until the
/// cooking method and other energy factors are confirmed separately.
private struct CountableFoodAmountEntry: View {
    private enum Unit: String, CaseIterable, Identifiable {
        case piece = "个", seed = "颗", item = "枚", handful = "把", root = "根", pieceBlock = "块", grain = "粒", slice = "片", cup = "杯", bowl = "碗", plate = "盘", spoon = "勺", spoonful = "匙", ball = "团", box = "盒", bag = "袋", bottle = "瓶", skewer = "串", animal = "只", serving = "份", custom = "自定义"

        var id: String { rawValue }
    }

    @Binding var description: String
    var onAmountJoined: (String) -> Void = { _ in }
    @State private var count = 2
    @State private var unit: Unit = .piece
    @State private var customUnit = ""
    @State private var lastJoinedAmount: String?

    init(
        description: Binding<String>,
        initialAmount: String? = nil,
        onAmountJoined: @escaping (String) -> Void = { _ in }
    ) {
        _description = description
        self.onAmountJoined = onAmountJoined
        _lastJoinedAmount = State(initialValue: initialAmount)
        guard let selection = Self.selection(from: initialAmount) else { return }
        _count = State(initialValue: selection.count)
        _unit = State(initialValue: selection.unit)
        _customUnit = State(initialValue: selection.customUnit)
    }

    private static func selection(from savedAmount: String?) -> (count: Int, unit: Unit, customUnit: String)? {
        guard let savedAmount else { return nil }
        let rawAmount = savedAmount
            .replacingOccurrences(of: "实际数量：", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = rawAmount.split(maxSplits: 1, whereSeparator: \.isWhitespace)
        guard parts.count == 2, let count = Int(parts[0]), count > 0 else { return nil }
        let savedUnit = String(parts[1])
        if let knownUnit = Unit(rawValue: savedUnit), knownUnit != .custom {
            return (count, knownUnit, "")
        }
        return (count, .custom, savedUnit)
    }

    private var resolvedUnit: String {
        let trimmed = customUnit.trimmingCharacters(in: .whitespacesAndNewlines)
        return unit == .custom ? trimmed : unit.rawValue
    }

    private var amount: String? {
        guard unit != .custom || MealQuantityNote.isCountableUnit(resolvedUnit) else { return nil }
        return "\(count) \(resolvedUnit)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("按数量记（可选）")
                .font(.subheadline.weight(.semibold))
            HStack(spacing: 8) {
                Text("\(count)")
                    .font(.body.monospacedDigit().weight(.semibold))
                    .frame(minWidth: 20)
                Stepper("调整数量", value: $count, in: 1...99)
                    .labelsHidden()
                    .accessibilityLabel("数量 \(count)")
                Picker("量词", selection: $unit) {
                    ForEach(Unit.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.menu)
                if unit == .custom {
                    TextField("自定义量词", text: $customUnit)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 90)
                        .onChange(of: customUnit) { _, value in
                            // A unit should stay a short word (把、颗、团、匙), not become an
                            // unbounded second description that crowds the compact meal form.
                            customUnit = String(value.prefix(4))
                        }
                }
                Button("加入 \(amount ?? "数量")") {
                    guard let amount else { return }
                    let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
                    description = MealQuantityNote.replacingQuantity(
                        in: trimmed,
                        previouslyConfirmed: lastJoinedAmount,
                        with: amount
                    )
                    lastJoinedAmount = "实际数量：\(amount)"
                    onAmountJoined(amount)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("加入数量 \(amount ?? "自定义量词")")
                .disabled(amount == nil)
            }
            if unit == .custom, !customUnit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, amount == nil {
                Text("自定义请填“小把、颗、团”这类量词；克、毫升和 kcal 不作为数量。")
                    .font(.caption)
                    .foregroundStyle(CoachPalette.recovery)
            } else {
                Text("可先写“鸡蛋”，也可先加入“2 个”再补食物名称；手打“鸡蛋2个、两个鸡蛋、俩鸡蛋”也能识别。自定义量词最多 4 个字。这里只记录你确认的数量；油和做法未知时热量仍保留宽范围。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct MealEstimateResultCard: View {
    let calories: ClosedRange<Int>
    let composition: MealCompositionConfirmation?
    var detailOverride: String? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: composition?.isNarrowedByOwner == true ? "checkmark.seal.fill" : "waveform.path.ecg")
                .font(.title2)
                .foregroundStyle(composition?.isNarrowedByOwner == true ? CoachPalette.completed : CoachPalette.action)
                .frame(width: 42, height: 42)
                .background(CoachPalette.action.opacity(0.09), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(composition?.isNarrowedByOwner == true ? "建议记账" : "当前估算")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if let composition, composition.isNarrowedByOwner {
                    Text("\(composition.recommendedCalories) kcal")
                        .font(.title2.monospacedDigit().weight(.bold))
                } else {
                    Text("\(calories.lowerBound)–\(calories.upperBound) kcal")
                        .font(.title3.monospacedDigit().weight(.bold))
                }
                Text(detailOverride ?? (composition?.isNarrowedByOwner == true
                     ? "确认后的估算范围 \(calories.lowerBound)–\(calories.upperBound) kcal"
                     : "可按已确认的份量调整范围"))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 2)
        .background(
            LinearGradient(
                colors: [CoachPalette.action.opacity(0.12), CoachPalette.completed.opacity(0.07)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            composition?.isNarrowedByOwner == true
                ? "建议记账，约 \(composition?.recommendedCalories ?? calories.lowerBound) 千卡；确认后的估算范围 \(calories.lowerBound) 到 \(calories.upperBound) 千卡；不是称重结果"
                : "当前照片或菜品估算，\(calories.lowerBound) 到 \(calories.upperBound) 千卡，保留宽范围"
        )
        .accessibilityHint("这是本机保守估算，不是称重结果；确认油、份量或菜单信息后再调整范围。")
    }
}

/// A menu listing or scale reading can refine an estimate only when it covers the complete
/// serving. This keeps a partial number from silently excluding oil, sweet drinks, additions, or
/// the amount actually eaten.
private struct WholeServingRangeConfirmation: View {
    @Binding var isConfirmed: Bool
    @Binding var lowerBound: String
    @Binding var upperBound: String
    @State private var labelOrMenuCalories = ""

    private var labelCalories: Int? {
        guard let value = Int(labelOrMenuCalories.trimmingCharacters(in: .whitespacesAndNewlines)),
              (0...5_000).contains(value) else { return nil }
        return value
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("包装/菜单写了一个数？")
                .font(.subheadline.weight(.semibold))
            HStack(spacing: 8) {
                TextField("整份 kcal", text: $labelOrMenuCalories)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                    .multilineTextAlignment(.center)
                    .textFieldStyle(.roundedBorder)
                Button("填入范围") {
                    guard let labelCalories else { return }
                    lowerBound = String(labelCalories)
                    upperBound = String(labelCalories)
                    isConfirmed = false
                }
                .disabled(labelCalories == nil)
            }
            Text("会填入最低和最高；仍需确认它覆盖整份。")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("已核对整份：油、甜饮、配料和实际吃掉量", isOn: $isConfirmed)
                .tint(CoachPalette.action)
            Text(isConfirmed
                 ? "完整范围会作为估算记录，不是营养检测或称重。"
                 : "未核对这些因素时不采用手动范围，继续保留宽区间。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

private struct ActualMealLogForm: View {
    /// Persisted with a high-energy photo's private record so a later edit does not turn the
    /// original wide estimate into a generic normal-plate estimate. It is an internal boundary,
    /// not text the person should need to read or edit.
    private static let conservativePhotoMarker = "照片候选保守区间"
    /// Retains the fact that a saved range came from a menu or scale, rather than making a later
    /// edit quietly fall back to the generic photo/model estimate.
    private static let manualCaloriesMarker = "菜单/秤热量范围"
    /// A one-tap photo record deliberately keeps Vision's wide category range. Persist that fact
    /// so reopening the record cannot present a narrow, unconfirmed default as user-entered data.
    private static let photoDefaultEstimateMarker = "照片默认范围"
    /// An explicit removal keeps an existing conservative range rather than recomputing a
    /// smaller-looking text-only estimate, while making the missing image clear in history.
    private static let removedPhotoRetainsCandidateMarker = "照片已移除，保留候选范围"
    let planDate: Date
    let slot: MealSlot
    let plannedMeal: MealCard
    let startsWithCamera: Bool
    /// The live owner may change while this sheet is presented; the draft owner below remains
    /// fixed from sheet creation so an old meal/photo can never migrate into a replacement profile.
    let currentOwnerID: UUID
    let existingLog: ActualMealLog?
    let onSave: (ActualMealRelationship, String, String?, ClosedRange<Int>, MealCompositionConfirmation?, Data?, UUID) -> String?
    @Environment(\.dismiss) private var dismiss
    @State private var relationship: ActualMealRelationship
    @State private var description: String
    @State private var portionNote: String
    /// This retains a deliberate quantity-control choice when the person starts with `2 个`
    /// and then types the food name after it. Planned meals save their recipe title, so parsing
    /// only the final description would otherwise lose that confirmed count.
    @State private var selectedCountableQuantity: String?
    /// Menu nutrition labels and a scale are useful corrections, but deliberately remain an
    /// optional disclosure: the ordinary photo → confirm path must not ask for extra numbers.
    @State private var manualCalorieLowerBound = ""
    @State private var manualCalorieUpperBound = ""
    @State private var manualRangeConfirmedByOwner = false
    /// Confirmations for an old meal cannot silently apply after the person picks a new photo.
    /// Keep a short visible reminder until the new evidence has been reviewed.
    @State private var clearedManualRangeForNewPhoto = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var pendingPhotoData: Data?
    @State private var removesExistingPhoto = false
    @State private var showingMealCamera = false
    @State private var didRequestInitialCamera = false
    @State private var isLoadingPhoto = false
    @State private var photoStatus: String?
    @State private var photoSuggestion: PrivateFoodPhotoSuggestion?
    @State private var isAnalyzingPhoto = false
    @State private var composition: MealCompositionConfirmation
    @State private var photoUsesDefaultEstimate = false
    /// A manual meal should open on the decision to record it, not on a photo-upload form.
    /// Once a photo exists, is processing, or has a status to review, the same disclosure opens
    /// itself so the evidence and its conservative range never become hidden.
    @State private var showsPhotoOptions = false
    @State private var showsPortionOptions = false
    @State private var showsManualEstimateOptions = false
    /// A recognized photo should end in one explicit confirmation, not a second form full of
    /// choices.  Corrections remain available behind this deliberately quiet disclosure.
    @State private var showsPhotoCorrectionOptions = false
    @State private var showsUnrecognizedPhotoAdjustmentOptions = false
    @State private var validationMessage: String?
    /// Both the toolbar and the photo fast path write the same local record.  Keep a small
    /// in-memory lock so a double tap cannot replace the just-confirmed meal with a second
    /// copy while the sheet is being dismissed.
    @State private var isSaving = false
    @State private var isFormVisible = false
    @State private var photoSelectionGeneration = 0
    @State private var formOwnerID: UUID

    init(
        planDate: Date,
        slot: MealSlot,
        plannedMeal: MealCard,
        startsWithCamera: Bool = false,
        currentOwnerID: UUID,
        existingLog: ActualMealLog?,
        onSave: @escaping (ActualMealRelationship, String, String?, ClosedRange<Int>, MealCompositionConfirmation?, Data?, UUID) -> String?
    ) {
        self.planDate = planDate
        self.slot = slot
        self.plannedMeal = plannedMeal
        self.startsWithCamera = startsWithCamera
        self.currentOwnerID = currentOwnerID
        self.existingLog = existingLog
        self.onSave = onSave
        _formOwnerID = State(initialValue: currentOwnerID)
        let initialRelationship = existingLog?.relationship ?? .asPlanned
        _relationship = State(initialValue: initialRelationship)
        _description = State(initialValue: existingLog?.description ?? plannedMeal.displayTitle)
        _portionNote = State(initialValue: Self.editablePortionNote(existingLog?.portionNote))
        _selectedCountableQuantity = State(initialValue: MealQuantityNote.storedActualQuantity(in: existingLog?.portionNote))
        _composition = State(initialValue: existingLog?.compositionConfirmation ?? MealCompositionConfirmation())
        let retainsManualCalories = existingLog?.portionNote?.contains(Self.manualCaloriesMarker) == true
        _photoUsesDefaultEstimate = State(initialValue: existingLog?.portionNote?.contains(Self.photoDefaultEstimateMarker) == true)
        if retainsManualCalories, let range = existingLog?.estimatedCaloriesRange {
            _manualCalorieLowerBound = State(initialValue: String(range.lowerBound))
            _manualCalorieUpperBound = State(initialValue: String(range.upperBound))
        }
        _manualRangeConfirmedByOwner = State(initialValue: retainsManualCalories)
        _showsManualEstimateOptions = State(initialValue: retainsManualCalories)
    }

    private var saveUnavailableReason: String? {
        if isSaving { return "正在保存这餐记录，请稍候。" }
        if isLoadingPhoto { return "照片仍在本机处理中，完成后即可保存。" }
        if isAnalyzingPhoto { return "正在本机分析照片，完成后即可核对。" }
        if formOwnerID != currentOwnerID { return "本机资料已切换；请取消后从当前资料重新打开。" }
        if !Calendar.current.isDate(planDate, inSameDayAs: .now) {
            return "日期已切换；请取消后从今天重新打开。"
        }
        if relationship != .asPlanned,
           description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "请先填写这餐实际吃了什么。"
        }
        if hasIncompleteManualCalories {
            return "菜单/称重热量需同时填写最低和最高值。"
        }
        if hasManualCaloriesInput, manualCaloriesRange == nil {
            return "请填写合理的热量范围。"
        }
        if hasManualCaloriesInput, !manualRangeConfirmedByOwner {
            return "要采用菜单/秤范围，请先确认它覆盖整份油、甜饮、配料和实际吃掉量。"
        }
        return nil
    }

    private var hasManualCaloriesInput: Bool {
        !manualCalorieLowerBound.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !manualCalorieUpperBound.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasIncompleteManualCalories: Bool {
        let hasLower = !manualCalorieLowerBound.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasUpper = !manualCalorieUpperBound.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasLower != hasUpper
    }

    private var manualCaloriesRange: ClosedRange<Int>? {
        guard let lower = Int(manualCalorieLowerBound.trimmingCharacters(in: .whitespacesAndNewlines)),
              let upper = Int(manualCalorieUpperBound.trimmingCharacters(in: .whitespacesAndNewlines)),
              (0...5_000).contains(lower),
              (0...5_000).contains(upper),
              lower <= upper else { return nil }
        return lower...upper
    }

    private var confirmedManualCaloriesRange: ClosedRange<Int>? {
        manualRangeConfirmedByOwner ? manualCaloriesRange : nil
    }

    private var usesPhotoFastDefaults: Bool {
        photoSuggestion != nil
            && relationship != .asPlanned
            && photoUsesDefaultEstimate
            && descriptionMatchesPhotoCandidate
    }

    /// Editing the prefilled food name means the person is no longer confirming the exact
    /// Vision candidate. Keep the photo only as a conservative range reference and require the
    /// ordinary record action instead of presenting the candidate quick-confirm button.
    private var descriptionMatchesPhotoCandidate: Bool {
        guard let photoSuggestion else { return true }
        return description.trimmingCharacters(in: .whitespacesAndNewlines) == photoSuggestion.provisionalDescription
    }

    /// Vision may have no reliable category for a dim, mixed, or partially covered plate. In
    /// that case, asking for a single food name is both more useful and less error-prone than
    /// presenting a full six-field portion questionnaire before the record can be saved.
    private var hasUnrecognizedPhotoDraft: Bool {
        pendingPhotoData != nil
            && photoSuggestion == nil
            && !isLoadingPhoto
            && !isAnalyzingPhoto
    }

    private var photoSectionIsActive: Bool {
        pendingPhotoData != nil
            || selectedPhoto != nil
            || existingLog?.localPhotoReference != nil
            || isLoadingPhoto
            || isAnalyzingPhoto
            || photoSuggestion != nil
            || photoStatus != nil
    }

    private var photoRequiresConservativeRange: Bool {
        photoSuggestion?.requiresConservativeCalorieRange == true
            || retainedPhotoRequiresConservativeRange
    }

    /// An older saved actual meal does not keep raw Vision labels. Its explicit conservative
    /// marker and saved wide range are therefore the only honest boundary when reopening it.
    private var retainedPhotoRequiresConservativeRange: Bool {
        guard existingLog?.portionNote?.contains(Self.conservativePhotoMarker) == true,
              pendingPhotoData == nil else { return false }
        return true
    }

    private var retainedPhotoDefaultEstimate: Bool {
        guard existingLog?.portionNote?.contains(Self.photoDefaultEstimateMarker) == true,
              pendingPhotoData == nil else { return false }
        return true
    }

    private var photoFastDisplayCalories: Int {
        guard let range = photoSuggestion?.estimatedCaloriesRange else { return composition.recommendedCalories }
        return (range.lowerBound + range.upperBound) / 2
    }

    private var photoFastSaveLabel: String {
        confirmedManualCaloriesRange == nil ? "候选无误，记录宽范围" : "按菜单／秤范围记录"
    }

    private var photoFastSaveHint: String {
        confirmedManualCaloriesRange == nil
            ? "仅在本机候选与实际食物一致时记录；不会把它当作称重结果，按保守热量范围记录到\(slot.displayName)"
            : "仅在菜单或秤覆盖整份油、配料和实际吃掉量时使用；仍不是称重结果"
    }

    private static func editablePortionNote(_ saved: String?) -> String {
        (saved ?? "")
            .replacingOccurrences(of: Self.conservativePhotoMarker, with: "")
            .replacingOccurrences(of: Self.manualCaloriesMarker, with: "")
            .replacingOccurrences(of: Self.photoDefaultEstimateMarker, with: "")
            .replacingOccurrences(of: Self.removedPhotoRetainsCandidateMarker, with: "")
            .replacingOccurrences(of: "｜｜", with: "｜")
            .trimmingCharacters(in: CharacterSet(charactersIn: "｜ "))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DisclosureGroup(
                        isExpanded: Binding(
                            get: { photoSectionIsActive || showsPhotoOptions },
                            set: { showsPhotoOptions = $0 }
                        )
                    ) {
                    HStack(spacing: 10) {
                    #if canImport(UIKit)
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button {
                            // Invalidate a PhotosPicker transfer that is still decoding. Keep an
                            // already reviewed pending image until a new camera result succeeds.
                            photoSelectionGeneration &+= 1
                            isLoadingPhoto = false
                            showingMealCamera = true
                        } label: {
                            Label("拍照", systemImage: "camera.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityLabel("现在拍照")
                    }
                    #endif
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label("相册", systemImage: "photo.on.rectangle")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("从相册上传")
                    }
                    .onChange(of: selectedPhoto) { _, item in
                        photoSelectionGeneration &+= 1
                        let generation = photoSelectionGeneration
                        // A new picker selection starts a fresh draft. Clear the previous
                        // in-memory image and candidate before decoding so a failed transfer
                        // can never save the photo that was selected before it.
                        if item != nil {
                            pendingPhotoData = nil
                            discardUnconfirmedPhotoDefaults()
                            removesExistingPhoto = false
                        }
                        guard let item else {
                            isLoadingPhoto = false
                            photoStatus = pendingPhotoData == nil
                                ? (existingLog?.localPhotoReference == nil ? nil : "保留已有本机照片。")
                                : "保留当前已核对的待保存照片。"
                            return
                        }
                        isLoadingPhoto = true
                        isAnalyzingPhoto = false
                        photoStatus = "正在本机读取并缩小照片…"
                        Task { await loadPhoto(item, generation: generation, ownerID: formOwnerID) }
                    }
                    if isLoadingPhoto || isAnalyzingPhoto {
                        ProgressView(isLoadingPhoto ? "照片处理中" : "本机识别中")
                    } else if pendingPhotoData != nil {
                        #if canImport(UIKit)
                        if let pendingPhotoData {
                            PrivatePendingPhotoPreview(data: pendingPhotoData)
                        }
                        #endif
                        Label("新照片已暂存，点保存后才写入 App 私有目录", systemImage: "lock.fill")
                            .font(.footnote)
                        Button("移除本次新照片") {
                            photoSelectionGeneration &+= 1
                            selectedPhoto = nil
                            isLoadingPhoto = false
                            pendingPhotoData = nil
                            discardUnconfirmedPhotoDefaults()
                            photoStatus = existingLog?.localPhotoReference == nil ? "本次不保存照片。" : "将保留已有本机照片。"
                        }
                    } else if existingLog?.localPhotoReference != nil {
                        if removesExistingPhoto {
                            Label("保存后将移除旧照片；保留当前宽范围", systemImage: "photo.badge.minus")
                                .font(.footnote)
                                .foregroundStyle(CoachPalette.recovery)
                            Button("撤回移除照片") {
                                removesExistingPhoto = false
                                photoStatus = "将继续保留已有本机照片。"
                            }
                            .font(.footnote.weight(.semibold))
                        } else {
                            Label("这条记录已有本机照片；重新拍摄或上传可替换", systemImage: "photo.fill")
                                .font(.footnote)
                            Button("移除现有照片，保留餐食记录") {
                                removesExistingPhoto = true
                                discardUnconfirmedPhotoDefaults()
                                if retainedPhotoDefaultEstimate { photoUsesDefaultEstimate = true }
                                photoStatus = "保存后将移除旧照片；保留当前宽范围。"
                            }
                            .font(.footnote.weight(.semibold))
                        }
                    }
                    if let photoStatus {
                        Text(photoStatus).font(.footnote).foregroundStyle(.secondary)
                    }
                    if let photoSuggestion {
                        Label("本机候选品类：\(photoSuggestion.categorySummary)", systemImage: "sparkles")
                            .font(.footnote.weight(.semibold))
                        Label(
                            descriptionMatchesPhotoCandidate
                                ? "候选无误 · 宽范围"
                                : "按你写的菜名记录 · 照片仅作范围参考",
                            systemImage: descriptionMatchesPhotoCandidate ? "checkmark.circle.fill" : "pencil.circle.fill"
                        )
                            .font(.footnote)
                            .foregroundStyle(descriptionMatchesPhotoCandidate ? CoachPalette.completed : .secondary)
                            .accessibilityHint(
                                descriptionMatchesPhotoCandidate
                                    ? "这是本机照片候选，不是称重结果；确认后仅保留宽热量范围。"
                                    : "菜名由你修改；照片只保留宽范围，不确认菜品或称重。"
                            )
                    }
                    Text("照片不上传、不共享，不作为精准热量证明。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    } label: {
                        Label(
                            photoSectionIsActive ? "本机照片" : "拍照或相册（可选）",
                            systemImage: photoSectionIsActive ? "photo.fill" : "camera"
                        )
                    }
                }
                if usesPhotoFastDefaults {
                    Section("识别结果") {
                        MealEstimateResultCard(
                            calories: automaticCalories,
                            composition: nil,
                            detailOverride: confirmedManualCaloriesRange == nil
                                ? "照片未确认油与份量，已保留范围"
                                : "已采用你确认的整份菜单／秤范围"
                        )
                        DisclosureGroup("有包装／菜单的整份 kcal？优先录入", isExpanded: $showsManualEstimateOptions) {
                            WholeServingRangeConfirmation(
                                isConfirmed: $manualRangeConfirmedByOwner,
                                lowerBound: $manualCalorieLowerBound,
                                upperBound: $manualCalorieUpperBound
                            )
                        }
                        .font(.subheadline.weight(.semibold))
                        DisclosureGroup("让估算更贴近（约 10 秒）", isExpanded: $showsPhotoCorrectionOptions) {
                            TextField("实际吃了什么（可改）", text: $description, axis: .vertical)
                                .lineLimit(2...4)
                            CountableFoodAmountEntry(
                                description: $description,
                                initialAmount: selectedCountableQuantity
                                    ?? MealQuantityNote.actualQuantity(from: description, plannedTitle: ""),
                                onAmountJoined: { amount in
                                    selectedCountableQuantity = "实际数量：\(amount)"
                                }
                            )
                            TextField("份量备注（可选）", text: $portionNote, axis: .vertical)
                                .lineLimit(1...3)
                            MealCompositionQuickEditor(composition: $composition)
                        }
                        .font(.subheadline.weight(.semibold))
                        Button {
                            recordActualMeal()
                        } label: {
                            Label(photoFastSaveLabel, systemImage: "checkmark.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(confirmedManualCaloriesRange == nil ? CoachPalette.completed : CoachPalette.action)
                        .disabled(saveUnavailableReason != nil)
                        .accessibilityHint(photoFastSaveHint)
                        Text("照片只适合给宽范围；想更贴近就展开上面一项，依次确认份量、油/甜饮和吃掉多少。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else if hasUnrecognizedPhotoDraft {
                    Section("这餐是什么？") {
                        TextField("例如：牛肉饭、奶茶", text: $description, axis: .vertical)
                            .lineLimit(1...3)
                        MealEstimateResultCard(
                            calories: automaticCalories,
                            composition: nil,
                            detailOverride: "未识别到菜品，油与份量未知已保留范围"
                        )
                        DisclosureGroup("油、份量有变化？调整", isExpanded: $showsUnrecognizedPhotoAdjustmentOptions) {
                            TextField("份量备注（可选）", text: $portionNote, axis: .vertical)
                                .lineLimit(1...3)
                            MealCompositionQuickEditor(composition: $composition)
                            DisclosureGroup("菜单/秤有数？填热量范围", isExpanded: $showsManualEstimateOptions) {
                                HStack(spacing: 8) {
                                    TextField("最低", text: $manualCalorieLowerBound)
                                        #if os(iOS)
                                        .keyboardType(.numberPad)
                                        #endif
                                        .multilineTextAlignment(.center)
                                    Text("–").foregroundStyle(.secondary)
                                    TextField("最高", text: $manualCalorieUpperBound)
                                        #if os(iOS)
                                        .keyboardType(.numberPad)
                                        #endif
                                        .multilineTextAlignment(.center)
                                    Text("kcal").font(.footnote).foregroundStyle(.secondary)
                                }
                                .textFieldStyle(.roundedBorder)
                                WholeServingRangeConfirmation(
                                    isConfirmed: $manualRangeConfirmedByOwner,
                                    lowerBound: $manualCalorieLowerBound,
                                    upperBound: $manualCalorieUpperBound
                                )
                            }
                            .font(.subheadline.weight(.semibold))
                        }
                        .font(.subheadline.weight(.semibold))
                        Text("只填菜名就能记录；点右上角“确认并记录”。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else {
                if relationship == .asPlanned {
                    Section("按计划吃了") {
                        LabeledContent("计划餐", value: plannedMeal.displayTitle)
                        DisclosureGroup("改数量或食物（可选）") {
                            CountableFoodAmountEntry(
                                description: $description,
                                initialAmount: selectedCountableQuantity,
                                onAmountJoined: { amount in
                                    selectedCountableQuantity = "实际数量：\(amount)"
                                }
                            )
                            TextField("补充备注（可选）", text: $portionNote, axis: .vertical)
                                .lineLimit(1...3)
                            Label("数量仅作备注；热量仍按餐卡范围估算", systemImage: "info.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Picker("餐食类型", selection: $relationship) {
                                Text("按计划").tag(ActualMealRelationship.asPlanned)
                                Text("换了食物").tag(ActualMealRelationship.different)
                                Text("本餐计划外").tag(ActualMealRelationship.planExternal)
                            }
                            .pickerStyle(.segmented)
                        }
                    }
                } else {
                    Section("\(slot.displayName)实际吃了什么") {
                        TextField("例如：鸡肉饭、青菜和无糖豆浆", text: $description, axis: .vertical)
                            .lineLimit(2...5)
                        CountableFoodAmountEntry(
                            description: $description,
                            initialAmount: selectedCountableQuantity
                                ?? MealQuantityNote.actualQuantity(from: description, plannedTitle: ""),
                            onAmountJoined: { amount in
                                selectedCountableQuantity = "实际数量：\(amount)"
                            }
                        )
                        TextField("份量备注（可选）", text: $portionNote, axis: .vertical)
                            .lineLimit(1...3)
                        Picker("餐食类型", selection: $relationship) {
                            Text("按计划").tag(ActualMealRelationship.asPlanned)
                            Text("换了食物").tag(ActualMealRelationship.different)
                            Text("本餐计划外").tag(ActualMealRelationship.planExternal)
                        }
                        .pickerStyle(.segmented)
                        Text(relationship == .planExternal
                             ? "本餐仍归在\(slot.displayName)；额外加餐或零食请用右上角“+”。"
                             : "菜品或份量不同才需要改成“换了食物”。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                if relationship != .asPlanned {
                    Section("份量") {
                        if photoRequiresConservativeRange, confirmedManualCaloriesRange == nil {
                            Label(
                                photoSuggestion.map { "本机候选含\($0.conservativeRangeSummary)，保留宽区间" }
                                    ?? "这条照片记录保留宽区间",
                                systemImage: "exclamationmark.triangle.fill"
                            )
                                .foregroundStyle(CoachPalette.recovery)
                            Text("照片看不出油、糖、夹心和实际份量；这次不强行缩窄。核对菜品后可直接记录，菜单或称重信息再用于修正。")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else if usesPhotoFastDefaults {
                            Label("照片候选；份量未确认，保留宽范围", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(CoachPalette.completed)
                            DisclosureGroup("提高照片估算准确度（约 10 秒）", isExpanded: Binding(
                                get: { showsPortionOptions },
                                set: { expanded in
                                    showsPortionOptions = expanded
                                    if expanded { photoUsesDefaultEstimate = false }
                                }
                            )) {
                                MealCompositionQuickEditor(composition: $composition)
                                    .padding(.top, 6)
                            }
                            Text("只有吃得偏少、偏多，或油、甜饮明显不同，才需要调整。")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            MealCompositionQuickEditor(composition: $composition)
                        }
                        Text(photoUsesDefaultEstimate
                             ? "照片不能看出油和精确份量，当前保留范围。"
                             : composition.isNarrowedByOwner
                             ? "已确认，可以直接使用下方建议记账值。"
                             : MealQuickPortionPreset.matching(composition) != nil
                             ? "份量已选；油和甜饮未知，保留宽范围。"
                             : "请选择最接近的一份；不确定时才需要展开精细调整。")
                        .font(.footnote)
                        .foregroundStyle(photoUsesDefaultEstimate || composition.isNarrowedByOwner ? CoachPalette.completed : .secondary)
                    }
                }
                if relationship != .asPlanned {
                    Section("热量结果") {
                    MealEstimateResultCard(
                        calories: automaticCalories,
                        composition: relationship == .asPlanned || photoRequiresConservativeRange || photoUsesDefaultEstimate || retainedPhotoDefaultEstimate || confirmedManualCaloriesRange != nil ? nil : composition,
                        detailOverride: confirmedManualCaloriesRange == nil
                            ? ((photoUsesDefaultEstimate || retainedPhotoDefaultEstimate)
                                ? (descriptionMatchesPhotoCandidate
                                    ? "照片未确认油与份量，已保留范围"
                                    : "已改菜名；照片仅作宽区间参考")
                                : nil)
                            : "已采用菜单/秤提供的范围（仍为估算）"
                    )
                    Text("依据你确认的盘中内容和实际吃掉比例估算；照片无法替代称重，油酱仍可能造成误差。")
                        .font(.footnote).foregroundStyle(.secondary)
                        DisclosureGroup("菜单/秤有数？填热量范围（可选）", isExpanded: $showsManualEstimateOptions) {
                            HStack(spacing: 8) {
                                TextField("最低", text: $manualCalorieLowerBound)
                                    #if os(iOS)
                                    .keyboardType(.numberPad)
                                    #endif
                                    .multilineTextAlignment(.center)
                                Text("–").foregroundStyle(.secondary)
                                TextField("最高", text: $manualCalorieUpperBound)
                                    #if os(iOS)
                                    .keyboardType(.numberPad)
                                    #endif
                                    .multilineTextAlignment(.center)
                                Text("kcal").font(.footnote).foregroundStyle(.secondary)
                            }
                            .textFieldStyle(.roundedBorder)
                            WholeServingRangeConfirmation(
                                isConfirmed: $manualRangeConfirmedByOwner,
                                lowerBound: $manualCalorieLowerBound,
                                upperBound: $manualCalorieUpperBound
                            )
                        }
                        .font(.subheadline.weight(.semibold))
                }
                }
                }
                if let saveUnavailableReason {
                    Section("保存前还需") {
                        Label(saveUnavailableReason, systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let validationMessage {
                    Section { Text(validationMessage).foregroundStyle(CoachPalette.recovery) }
                }
            }
            .coachKeyboardDismissal()
            .navigationTitle("记录\(slot.displayName)")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                if !usesPhotoFastDefaults {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("确认并记录") { recordActualMeal() }
                        .disabled(saveUnavailableReason != nil)
                    }
                }
            }
            #if canImport(UIKit)
            .fullScreenCover(isPresented: $showingMealCamera) {
                PrivateFoodCameraPicker(
                    onImage: { data in
                        acceptCapturedPhoto(data)
                        showingMealCamera = false
                    },
                    onCancel: {
                        photoStatus = pendingPhotoData == nil
                            ? "未拍摄照片；仍可仅记录文字。"
                            : "未拍摄新照片；保留当前已核对的待保存照片。"
                        showingMealCamera = false
                    }
                )
                .ignoresSafeArea()
            }
            #endif
            .onAppear {
                isFormVisible = true
                guard startsWithCamera, !didRequestInitialCamera else { return }
                didRequestInitialCamera = true
                #if canImport(UIKit)
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    showingMealCamera = true
                } else {
                    photoStatus = "此设备当前无法使用相机；可点“相册”或直接填写餐食。"
                }
                #endif
            }
            .onDisappear {
                isFormVisible = false
                photoSelectionGeneration &+= 1
                isLoadingPhoto = false
                isAnalyzingPhoto = false
                photoSuggestion = nil
                pendingPhotoData = nil
            }
            .onChange(of: composition) { _, _ in
                // The default photo range is only valid until the person starts correcting the
                // plate.  A correction therefore switches calculation back to the selected
                // portions; it never pretends that the original visual guess was confirmed.
                if showsPhotoCorrectionOptions { photoUsesDefaultEstimate = false }
            }
            .onChange(of: relationship) { previous, current in
                if showsPhotoCorrectionOptions { photoUsesDefaultEstimate = false }
                if previous == .asPlanned, current != .asPlanned {
                    resetPlanSpecificDraftForActualMeal()
                }
            }
            .onChange(of: description) { _, newDescription in
                if let selectedCountableQuantity,
                   !MealQuantityNote.isStillPresent(selectedCountableQuantity, in: newDescription) {
                    self.selectedCountableQuantity = nil
                }
            }
        }
    }

    /// The photo fast path and the standard toolbar must persist exactly the same selected meal
    /// slot.  Keeping the write in one function makes the visible `记录晚餐` title, the saved
    /// `slot`, and the automatic completion update travel together rather than relying on a
    /// separate mutable “currently selected meal” state.
    private func recordActualMeal() {
        guard !isSaving else { return }
        guard Calendar.current.isDate(planDate, inSameDayAs: .now) else {
            validationMessage = "日期已切换；这餐尚未保存。请关闭后从今天重新打开记录。"
            return
        }
        guard saveUnavailableReason == nil else { return }
        isSaving = true
        defer { isSaving = false }
        let savedDescription = relationship == .asPlanned ? plannedMeal.displayTitle : description
        let explicitQuantity = selectedCountableQuantity
            ?? MealQuantityNote.actualQuantity(
                from: description,
                plannedTitle: relationship == .asPlanned ? plannedMeal.displayTitle : ""
            )
        let portionBeforeQuantity: String?
        if relationship == .asPlanned {
            portionBeforeQuantity = [portionNote, removesExistingPhoto ? Self.removedPhotoRetainsCandidateMarker : nil]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: "｜")
        } else if photoRequiresConservativeRange {
            // Do not persist the auto-filled “normal portion” wording beside a deliberately
            // broad high-energy photo range; that would make the diary look more certain than
            // the estimate actually is.
            portionBeforeQuantity = [portionNote, Self.conservativePhotoMarker, photoUsesDefaultEstimate || retainedPhotoDefaultEstimate ? Self.photoDefaultEstimateMarker : nil, removesExistingPhoto ? Self.removedPhotoRetainsCandidateMarker : nil, confirmedManualCaloriesRange == nil ? nil : Self.manualCaloriesMarker]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: "｜")
        } else {
            portionBeforeQuantity = [portionNote, composition.summary, photoUsesDefaultEstimate || retainedPhotoDefaultEstimate ? Self.photoDefaultEstimateMarker : nil, removesExistingPhoto ? Self.removedPhotoRetainsCandidateMarker : nil, confirmedManualCaloriesRange == nil ? nil : Self.manualCaloriesMarker]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: "｜")
        }
        let savedPortion = MealQuantityNote.merging(portionBeforeQuantity, with: explicitQuantity)
        validationMessage = onSave(
            relationship,
            savedDescription,
            savedPortion,
            automaticCalories,
            relationship == .asPlanned
                || photoRequiresConservativeRange
                || photoUsesDefaultEstimate
                || retainedPhotoDefaultEstimate
                || confirmedManualCaloriesRange != nil
                ? nil
                : composition,
            pendingPhotoData,
            formOwnerID
        )
        if validationMessage == nil { dismiss() }
    }

    @MainActor private func loadPhoto(_ item: PhotosPickerItem, generation: Int, ownerID: UUID) async {
        do {
            guard let sourceData = try await item.loadTransferable(type: Data.self) else {
                guard isFormVisible, generation == photoSelectionGeneration else { return }
                isLoadingPhoto = false
                photoStatus = "照片未能读取，可重新选择或直接拍照。"
                return
            }
            guard mayAcceptPhoto(generation: generation, ownerID: ownerID) else { return }
            #if canImport(UIKit)
            guard let normalized = PrivateFoodPhotoPreparation.normalizedJPEG(from: sourceData) else {
                guard mayAcceptPhoto(generation: generation, ownerID: ownerID) else { return }
                isLoadingPhoto = false
                photoStatus = "照片格式暂不支持，请重新选择。"
                return
            }
            #else
            let normalized = sourceData
            #endif
            guard mayAcceptPhoto(generation: generation, ownerID: ownerID) else { return }
            pendingPhotoData = normalized
            resetManualRangeForAcceptedNewPhoto()
            isLoadingPhoto = false
            isAnalyzingPhoto = true
            photoStatus = "照片已在本机缩小；正在识别餐食候选…"
            photoSuggestion = await PrivateFoodPhotoAnalyzer.analyze(jpegData: normalized)
            guard mayAcceptPhoto(generation: generation, ownerID: ownerID) else { return }
            if let photoSuggestion {
                applyRecognizedMealSuggestion(photoSuggestion)
            } else {
                prepareUnrecognizedPhotoDraft()
            }
            isAnalyzingPhoto = false
            photoStatus = photoSuggestion == nil
                ? "照片已暂存，但本机未识别出可靠餐食类别；请按盘中内容核对。\(manualRangeResetReminder)"
                : "已填入识别候选；份量尚未确认，已保留热量范围。\(manualRangeResetReminder)"
        } catch {
            guard isFormVisible, generation == photoSelectionGeneration else { return }
            isLoadingPhoto = false
            selectedPhoto = nil
            photoStatus = "照片未能读取，可重新选择或直接拍照。"
        }
    }

    private func mayAcceptPhoto(generation: Int, ownerID: UUID) -> Bool {
        isFormVisible
            && generation == photoSelectionGeneration
            && ownerID == formOwnerID
            && formOwnerID == currentOwnerID
            && Calendar.current.isDate(planDate, inSameDayAs: .now)
    }

    private func acceptCapturedPhoto(_ data: Data) {
        photoSelectionGeneration &+= 1
        guard formOwnerID == currentOwnerID else {
            pendingPhotoData = nil
            photoStatus = "本机资料已切换；没有保留旧资料的餐食照片。"
            return
        }
        guard Calendar.current.isDate(planDate, inSameDayAs: .now) else {
            pendingPhotoData = nil
            photoStatus = "日期已切换；没有保留旧日期的餐食照片。"
            return
        }
        isLoadingPhoto = false
        discardUnconfirmedPhotoDefaults()
        resetManualRangeForAcceptedNewPhoto()
        removesExistingPhoto = false
        pendingPhotoData = data
        isAnalyzingPhoto = true
        photoStatus = "照片已在本机暂存；正在识别餐食候选…"
        Task { @MainActor in
            photoSuggestion = await PrivateFoodPhotoAnalyzer.analyze(jpegData: data)
            guard isFormVisible, formOwnerID == currentOwnerID,
                  Calendar.current.isDate(planDate, inSameDayAs: .now) else { return }
            if let photoSuggestion {
                applyRecognizedMealSuggestion(photoSuggestion)
            } else {
                prepareUnrecognizedPhotoDraft()
            }
            isAnalyzingPhoto = false
            photoStatus = photoSuggestion == nil
                ? "未识别出可靠类别；请按盘中内容核对。\(manualRangeResetReminder)"
                : "已填入识别候选；份量尚未确认，已保留热量范围。\(manualRangeResetReminder)"
        }
    }

    /// Photo candidates become editable defaults. The final save tap remains the explicit
    /// confirmation boundary, so recognition never silently creates a meal record.
    private func applyRecognizedMealSuggestion(_ suggestion: PrivateFoodPhotoSuggestion) {
        if relationship == .asPlanned { relationship = .different }
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        if existingLog == nil || trimmed.isEmpty || trimmed == plannedMeal.displayTitle {
            description = suggestion.provisionalDescription
        }
        if !composition.isNarrowedByOwner {
            composition = MealQuickPortionPreset.regular.composition
            photoUsesDefaultEstimate = true
        }
    }

    private func prepareUnrecognizedPhotoDraft() {
        if relationship == .asPlanned { relationship = .different }
        // A newly photographed, unrecognized meal must not inherit the plan card's name; that
        // would allow a misleading "actual" record with no user-provided food description.
        if existingLog == nil,
           description.trimmingCharacters(in: .whitespacesAndNewlines) == plannedMeal.displayTitle {
            description = ""
        }
        photoUsesDefaultEstimate = false
    }

    /// Removing or replacing a photo must also remove its unconfirmed normal-plate default.
    /// Explicit portion corrections already clear this marker and therefore remain untouched.
    private func discardUnconfirmedPhotoDefaults() {
        photoSuggestion = nil
        guard photoUsesDefaultEstimate else { return }
        photoUsesDefaultEstimate = false
        composition = MealCompositionConfirmation()
    }

    /// A quantity chosen while this was the planned recipe belongs to that recipe, not to a
    /// later "different food" record.  Clear it, and clear the untouched recipe title so the
    /// owner must name the actual food.  Never erase text they have already supplied for the
    /// actual meal or a later switch between two non-plan relationships.
    private func resetPlanSpecificDraftForActualMeal() {
        guard relationship != .asPlanned else { return }
        selectedCountableQuantity = nil
        if description.trimmingCharacters(in: .whitespacesAndNewlines) == plannedMeal.displayTitle {
            description = ""
        }
    }

    private var manualRangeResetReminder: String {
        clearedManualRangeForNewPhoto ? " 已清空旧菜单/秤与盘中确认，请按新照片重新核对。" : ""
    }

    /// Selecting a replacement photo is an evidence change, not a confirmation that a menu,
    /// scale, or plate-component selection for the previous meal still covers this serving.
    /// The former values stay only in the persisted old record until the new record is saved.
    private func resetManualRangeForAcceptedNewPhoto() {
        let hadManualRange = hasManualCaloriesInput || manualRangeConfirmedByOwner
        let hadCompositionConfirmation = composition.hasAnyOwnerSelection
        manualCalorieLowerBound = ""
        manualCalorieUpperBound = ""
        manualRangeConfirmedByOwner = false
        showsManualEstimateOptions = false
        composition = MealCompositionConfirmation()
        clearedManualRangeForNewPhoto = hadManualRange || hadCompositionConfirmation
    }

    private var automaticCalories: ClosedRange<Int> {
        if relationship == .asPlanned {
            return PlannedMealEnergyReference.estimatedRange(for: plannedMeal)
        }
        if let confirmedManualCaloriesRange {
            return confirmedManualCaloriesRange
        }
        if photoUsesDefaultEstimate, let suggestion = photoSuggestion {
            return suggestion.estimatedCaloriesRange
        }
        if retainedPhotoDefaultEstimate, let savedRange = existingLog?.estimatedCaloriesRange {
            return savedRange
        }
        if let photoSuggestion, photoSuggestion.requiresConservativeCalorieRange {
            return photoSuggestion.estimatedCaloriesRange
        }
        if retainedPhotoRequiresConservativeRange,
           let savedRange = existingLog?.estimatedCaloriesRange {
            return savedRange
        }
        if composition.hasAnyOwnerSelection {
            return composition.estimatedCaloriesRange
        }
        return photoSuggestion?.estimatedCaloriesRange
            ?? PlannedMealEnergyReference.fallbackRange(for: slot)
    }
}

private struct QuickExpenseForm: View {
    @Binding var privateData: PrivateCoachData
    let onPersistImmediately: (PrivateCoachData) -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var category: BudgetCategory = .ingredients
    @State private var amount = ""
    @State private var note = ""
    @State private var validationMessage: String?
    @State private var isSaving = false
    /// The owner at sheet creation is part of the draft. If local data is replaced while this
    /// sheet remains open, the old draft must not be attached to the new profile's ledger.
    @State private var formOwnerID: UUID

    init(
        privateData: Binding<PrivateCoachData>,
        onPersistImmediately: @escaping (PrivateCoachData) -> Bool
    ) {
        _privateData = privateData
        self.onPersistImmediately = onPersistImmediately
        _formOwnerID = State(initialValue: privateData.wrappedValue.profile.id)
    }

    private var currentLedger: MonthlyBudgetLedger {
        privateData.ledger(for: .now).snapshot(asOf: .now)
    }

    private var saveUnavailableReason: String? {
        if isSaving { return "正在保存这笔支出，请稍候。" }
        let hasAmount = !amount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasNote = !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if !hasAmount, !hasNote { return "请填写实际金额和用途备注。" }
        if !hasAmount { return "请填写已经发生的实际金额。" }
        if !hasNote { return "请填写用途备注，方便之后核对预算。" }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("本月预算") {
                    LabeledContent("已确认支出", value: "¥\(currentLedger.confirmedSpentYuan.description)")
                    LabeledContent("剩余", value: "¥\(currentLedger.remainingYuan.description)")
                    if let warning = BudgetPolicy.warning(for: currentLedger) {
                        Label(warning, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(CoachPalette.recovery)
                    }
                }
                Section("记录实际支出") {
                    Picker("类别", selection: $category) {
                        ForEach(BudgetCategory.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    TextField("金额（元）", text: $amount)
                    #if os(iOS)
                        .keyboardType(.decimalPad)
                    #endif
                    TextField("备注，例如鸡蛋", text: $note)
                    Text("只记录你已经发生并确认的支出；不会查询价格、下单或付款。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let saveUnavailableReason {
                        Label(saveUnavailableReason, systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let validationMessage {
                    Section { Text(validationMessage).foregroundStyle(CoachPalette.recovery) }
                }
            }
            .coachKeyboardDismissal()
            .navigationTitle("记录支出")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "正在保存…" : "保存", action: save)
                        .disabled(saveUnavailableReason != nil)
                }
            }
        }
    }

    private func save() {
        guard !isSaving else { return }
        let trimmedAmount = amount.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Decimal(string: trimmedAmount) else {
            validationMessage = "请填写大于 0 的有效实际金额；未记录任何支出。"
            return
        }
        if let error = ExpenseSubmissionPolicy.validationError(
            amountYuan: value,
            note: trimmedNote,
            formOwnerID: formOwnerID,
            currentOwnerID: privateData.profile.id
        ) {
            validationMessage = error
            return
        }
        isSaving = true
        var updatedData = privateData
        updatedData.recordExpense(ExpenseEntry(category: category, amountYuan: value, note: trimmedNote))
        guard onPersistImmediately(updatedData) else {
            isSaving = false
            validationMessage = "这笔支出暂未保存，预算没有改变；请稍后重试。"
            return
        }
        privateData = updatedData
        dismiss()
    }
}

private struct DetailCaption: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

private struct MealCardView: View {
    let meal: MealCard
    let profileKitchenSetup: String?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showingPrepSession = false

    init(meal: MealCard, profileKitchenSetup: String? = nil) {
        self.meal = meal
        self.profileKitchenSetup = profileKitchenSetup
    }

    private var totalMinutes: String? {
        meal.totalOperationText
    }

    private var portionLabel: String {
        if meal.portionsAndStorage.contains("做两份") || meal.portionsAndStorage.contains("做 2 份") { return "做 2 份｜留 1 盒" }
        return "做 1 份"
    }

    private var nextStep: String {
        meal.visibleTimedSteps.first ?? "先查看食材与前置准备"
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Group {
                        if dynamicTypeSize.isAccessibilitySize {
                            VStack(alignment: .leading, spacing: 7) {
                                Label(portionLabel, systemImage: "takeoutbag.and.cup.and.straw")
                                HStack(spacing: 8) {
                                    if let totalMinutes { Label(totalMinutes, systemImage: "timer") }
                                    hardLimitBadge
                                }
                            }
                        } else {
                            ViewThatFits(in: .horizontal) {
                            HStack(spacing: 8) {
                                Label(portionLabel, systemImage: "takeoutbag.and.cup.and.straw")
                                if let totalMinutes { Label(totalMinutes, systemImage: "timer") }
                                hardLimitBadge
                            }
                            VStack(alignment: .leading, spacing: 7) {
                                Label(portionLabel, systemImage: "takeoutbag.and.cup.and.straw")
                                HStack(spacing: 8) {
                                    if let totalMinutes { Label(totalMinutes, systemImage: "timer") }
                                    hardLimitBadge
                                }
                            }
                        }
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CoachPalette.action)
                    Label(meal.kitchenSetup, systemImage: "frying.pan")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("现在先做")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(nextStep)
                            .font(.body.weight(.medium))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button {
                        showingPrepSession = true
                    } label: {
                        Label("开始逐步备餐", systemImage: "timer")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .accessibilityHint("打开单步操作、累计计时、熟度终点和饭盒安全提示")
                }
                .padding(.vertical, 3)
                .accessibilityElement(children: .combine)
            }
            if let kitchenNotice = KitchenCompatibility.notice(for: meal, profileKitchenSetup: profileKitchenSetup) {
                Section {
                    Label(kitchenNotice, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(CoachPalette.recovery)
                        .fixedSize(horizontal: false, vertical: true)
                } header: {
                    Label("设备待确认", systemImage: "frying.pan")
                }
            }
            Section {
                DisclosureGroup("查看食材、步骤与保存") {
                    VStack(alignment: .leading, spacing: 14) {
                        DetailCaption("食材")
                        ForEach(meal.ingredients, id: \.self) { ingredient in
                            Label(ingredient, systemImage: "carrot")
                        }
                        DetailCaption("准备")
                        Label(meal.thawAndPortion, systemImage: "snowflake")
                            .fixedSize(horizontal: false, vertical: true)
                        Label(meal.kitchenSetup, systemImage: "frying.pan")
                            .fixedSize(horizontal: false, vertical: true)
                        if let foodSafetyFinish = meal.foodSafetyFinish {
                            DetailCaption("熟度终点")
                            Label(foodSafetyFinish, systemImage: "checkmark.shield")
                                .fixedSize(horizontal: false, vertical: true)
                            Text("分钟仅作流程参考；以食材熟度终点为准。")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        DetailCaption("全部步骤")
                        ForEach(Array(meal.visibleTimedSteps.enumerated()), id: \.offset) { index, step in
                            HStack(alignment: .top, spacing: 10) {
                                Text("\(index + 1)")
                                    .font(.caption.weight(.bold).monospacedDigit())
                                    .foregroundStyle(CoachPalette.action)
                                    .frame(width: 20, height: 20)
                                    .background(CoachPalette.actionSurface, in: Circle())
                                Text(step)
                                    .monospacedDigit()
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        DetailCaption("保存与替换")
                        Label(meal.portionsAndStorage, systemImage: "refrigerator")
                            .fixedSize(horizontal: false, vertical: true)
                        if meal.title.hasPrefix("午餐｜昨晚便当") {
                            Label("出门前放保温袋和冰袋；到岗后立即冷藏。", systemImage: "thermometer.low")
                            Label("午间加热至中心冒热气后一次吃完。", systemImage: "microwave")
                        }
                        Text(meal.substitutions)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .font(.footnote)
            }
        }
        .navigationTitle(meal.displayTitle)
        #if os(iOS)
        .fullScreenCover(isPresented: $showingPrepSession) {
            MealPrepSessionView(meal: meal, profileKitchenSetup: profileKitchenSetup)
        }
        #else
        .sheet(isPresented: $showingPrepSession) {
            MealPrepSessionView(meal: meal, profileKitchenSetup: profileKitchenSetup)
                .frame(minWidth: 560, minHeight: 700)
        }
        #endif
    }

    private var hardLimitBadge: some View {
        Label("20 分钟上限", systemImage: "bolt.fill")
            .font(.caption.weight(.bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .foregroundStyle(CoachPalette.action)
            .background(CoachPalette.action.opacity(0.12), in: Capsule())
            .accessibilityLabel("单餐总操作不超过二十分钟")
    }
}

private struct MealPrepSessionView: View {
    let meal: MealCard
    let profileKitchenSetup: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var setupConfirmed = false
    @State private var hasStarted = false
    @State private var startedAt: Date?
    @State private var accumulatedSeconds = 0
    @State private var currentStepIndex = 0
    @State private var completedStepIndices = Set<Int>()
    @State private var finished = false
    @State private var showingAllSteps = false
    @State private var showingStopConfirmation = false
    @State private var showingFinishConfirmation = false
    @State private var backgroundedAt: Date?
    @State private var backgroundReturnMessage: String?

    private var session: MealPrepSessionPlan { MealPrepSessionPlan(meal: meal) }

    private var currentStep: MealPrepSessionStep? {
        session.steps.indices.contains(currentStepIndex) ? session.steps[currentStepIndex] : nil
    }

    private var isPaused: Bool { hasStarted && !finished && startedAt == nil }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(meal.displayTitle)
                            .font(.title2.bold())
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 12) {
                                Label("\(session.totalSeconds / 60) 分钟内", systemImage: "timer")
                                Label(meal.kitchenSetup, systemImage: "frying.pan")
                                    .lineLimit(1)
                            }
                            VStack(alignment: .leading, spacing: 6) {
                                Label("\(session.totalSeconds / 60) 分钟内", systemImage: "timer")
                                Label(meal.kitchenSetup, systemImage: "frying.pan")
                            }
                        }
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(CoachPalette.action)
                    }
                    .padding(.vertical, 4)
                }

                if !hasStarted {
                    if let kitchenNotice = KitchenCompatibility.notice(for: meal, profileKitchenSetup: profileKitchenSetup) {
                        Section("设备不匹配") {
                            Label(kitchenNotice, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(CoachPalette.recovery)
                        }
                    }
                    Section("开始前称量") {
                        ForEach(meal.ingredients, id: \.self) { ingredient in
                            Label(ingredient, systemImage: "scalemass")
                        }
                    }
                    Section("解冻与分装") {
                        Label(meal.thawAndPortion, systemImage: "snowflake")
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let foodSafetyFinish = meal.foodSafetyFinish {
                        Section("出锅安全终点") {
                            Label(foodSafetyFinish, systemImage: "checkmark.shield")
                                .foregroundStyle(CoachPalette.recovery)
                        }
                    }
                    Section {
                        Toggle(isOn: $setupConfirmed) {
                            Text("食材已按克数备好，需解冻的食材已在冷藏完成解冻，锅具稳定就位")
                        }
                        .tint(CoachPalette.action)
                        Text("不要用室温久放代替冷藏解冻；未完成准备时先退出并按卡片前置说明处理。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if session.steps.isEmpty {
                        Section("无法启动计时") {
                            Label("这张卡没有可执行的分钟步骤。请关闭后重新规划当餐，不要自行加大火力或猜测时长。", systemImage: "exclamationmark.triangle")
                                .foregroundStyle(CoachPalette.recovery)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } else if finished {
                    Section {
                        Label("本次步骤已完成", systemImage: "checkmark.circle.fill")
                            .font(.title3.bold())
                            .foregroundStyle(CoachPalette.completed)
                        Text("备餐步骤完成；按餐卡分装、冷藏并在需要时复热。不会自动记录饮食，也不会估算热量。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Section("分装、冷藏与复热") {
                        Label(meal.portionsAndStorage, systemImage: "refrigerator")
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let foodSafetyFinish = meal.foodSafetyFinish {
                        Section("最后再确认") {
                            Label(foodSafetyFinish, systemImage: "checkmark.shield")
                                .foregroundStyle(CoachPalette.recovery)
                        }
                    }
                } else {
                    Section {
                        TimelineView(.periodic(from: .now, by: 1)) { timeline in
                            let elapsed = elapsedSeconds(at: timeline.date)
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(formatted(seconds: elapsed))
                                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                                        .monospacedDigit()
                                    Spacer()
                                    Text("上限 \(formatted(seconds: session.totalSeconds))")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                ProgressView(value: min(Double(elapsed), Double(session.totalSeconds)), total: Double(session.totalSeconds))
                                    .tint(elapsed >= session.totalSeconds ? CoachPalette.recovery : CoachPalette.action)
                                if let warning = session.hardLimitMessage(elapsedSeconds: elapsed) {
                                    Label(warning, systemImage: "exclamationmark.octagon.fill")
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(CoachPalette.recovery)
                                } else if isPaused {
                                    Label("计时已暂停；炉火和食物仍需你亲自看管。", systemImage: "pause.circle")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    if let currentStep {
                        Section("当前步骤 \(currentStepIndex + 1)/\(session.steps.count)") {
                            Text(currentStep.instruction)
                                .font(.title3.weight(.semibold))
                                .monospacedDigit()
                                .fixedSize(horizontal: false, vertical: true)
                            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                                Text(session.timingMessage(for: currentStepIndex, elapsedSeconds: elapsedSeconds(at: timeline.date)))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if let foodSafetyFinish = meal.foodSafetyFinish {
                        Section("熟度优先于计时") {
                            Label(foodSafetyFinish, systemImage: "checkmark.shield")
                                .foregroundStyle(CoachPalette.recovery)
                        }
                    }

                    Section {
                        DisclosureGroup("查看全部步骤", isExpanded: $showingAllSteps) {
                            ForEach(session.steps) { step in
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: completedStepIndices.contains(step.id) ? "checkmark.circle.fill" : step.id == currentStepIndex ? "play.circle.fill" : "circle")
                                        .foregroundStyle(completedStepIndices.contains(step.id) ? CoachPalette.completed : CoachPalette.action)
                                    Text(step.instruction)
                                        .font(.footnote)
                                        .monospacedDigit()
                                }
                                .padding(.vertical, 3)
                            }
                        }
                    }
                }
            }
            .navigationTitle("逐步备餐")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .safeAreaInset(edge: .bottom, spacing: 0) {
                sessionControls
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        if hasStarted && !finished {
                            showingStopConfirmation = true
                        } else {
                            dismiss()
                        }
                    }
                }
            }
            .interactiveDismissDisabled(hasStarted && !finished)
            .confirmationDialog("结束这次备餐？", isPresented: $showingStopConfirmation, titleVisibility: .visible) {
                Button("结束并清空本次临时进度", role: .destructive) { dismiss() }
                Button("继续备餐", role: .cancel) {}
            } message: {
                Text("只清空本次计时和步骤进度，不删除餐卡、饮食记录或其他数据。")
            }
            .confirmationDialog("确认已达到安全熟度？", isPresented: $showingFinishConfirmation, titleVisibility: .visible) {
                Button("已达到安全终点，完成") { finishLastStep() }
                Button("还没有，继续检查", role: .cancel) {}
            } message: {
                Text(session.foodSafetyFinish ?? "请以食材实际熟度为准，不只看计时。")
            }
            .alert("返回备餐", isPresented: Binding(
                get: { backgroundReturnMessage != nil },
                set: { if !$0 { backgroundReturnMessage = nil } }
            )) {
                Button("已查看锅具") { backgroundReturnMessage = nil }
            } message: {
                Text(backgroundReturnMessage ?? "")
            }
            .onChange(of: scenePhase) { _, phase in
                handleScenePhase(phase)
            }
        }
    }

    @ViewBuilder
    private var sessionControls: some View {
        VStack(spacing: 8) {
            if !hasStarted {
                Button {
                    hasStarted = true
                    startedAt = .now
                } label: {
                    Label("从第 1 步开始计时", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!setupConfirmed || session.steps.isEmpty)
            } else if finished {
                Button {
                    dismiss()
                } label: {
                    Label("完成，返回食谱", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { activeControlButtons }
                    VStack(spacing: 8) { activeControlButtons }
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.regularMaterial)
        .overlay(alignment: .top) { Divider() }
    }

    @ViewBuilder
    private var activeControlButtons: some View {
        Button {
            togglePause()
        } label: {
            Label(isPaused ? "继续计时" : "暂停", systemImage: isPaused ? "play.fill" : "pause.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)

        Button {
            completeCurrentStep()
        } label: {
            Label(currentStepIndex == session.steps.count - 1 ? "完成最后一步" : "完成此步，下一步", systemImage: "checkmark.circle.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    private func elapsedSeconds(at date: Date) -> Int {
        let active = startedAt.map { max(0, date.timeIntervalSince($0)) } ?? 0
        return max(0, accumulatedSeconds + Int(active.rounded(.down)))
    }

    private func formatted(seconds: Int) -> String {
        String(format: "%d:%02d", max(0, seconds) / 60, max(0, seconds) % 60)
    }

    private func togglePause() {
        if startedAt != nil {
            accumulatedSeconds = elapsedSeconds(at: .now)
            self.startedAt = nil
        } else {
            startedAt = .now
        }
    }

    private func completeCurrentStep() {
        guard session.steps.indices.contains(currentStepIndex) else { return }
        if currentStepIndex == session.steps.count - 1 {
            if session.foodSafetyFinish != nil {
                showingFinishConfirmation = true
            } else {
                finishLastStep()
            }
        } else {
            completedStepIndices.insert(currentStepIndex)
            currentStepIndex += 1
        }
    }

    private func finishLastStep() {
        guard session.steps.indices.contains(currentStepIndex) else { return }
        completedStepIndices.insert(currentStepIndex)
        accumulatedSeconds = elapsedSeconds(at: .now)
        startedAt = nil
        finished = true
    }

    private func handleScenePhase(_ phase: ScenePhase) {
        guard hasStarted && !finished else {
            backgroundedAt = nil
            return
        }
        switch phase {
        case .active:
            guard let backgroundedAt else { return }
            let now = Date.now
            self.backgroundedAt = nil
            backgroundReturnMessage = session.returnFromBackgroundMessage(
                awaySeconds: Int(max(0, now.timeIntervalSince(backgroundedAt)).rounded(.down)),
                elapsedSeconds: elapsedSeconds(at: now)
            )
        case .inactive, .background:
            if backgroundedAt == nil { backgroundedAt = .now }
        @unknown default:
            break
        }
    }
}

private struct UnplannedMealCompactRow: View {
    let log: UnplannedMealLog
    let onEdit: () -> Void
    let onDelete: () -> Void

    private var displayDescription: String {
        log.displayDescription
    }

    private var calorieText: String {
        guard let range = log.estimatedCaloriesRange else { return "待估算" }
        return "\(log.historyEstimateLabel) · \(range.lowerBound)–\(range.upperBound) kcal"
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "fork.knife")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(CoachPalette.action)
                .frame(width: 36, height: 36)
                .background(CoachPalette.action.opacity(0.10), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(displayDescription)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(calorieText)
                    .font(.caption.monospacedDigit().weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Menu {
                Button("修正记录", systemImage: "pencil", action: onEdit)
                Button("删除", systemImage: "trash", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("管理这条餐食记录")
        }
    }
}

private struct FoodHomeView: View {
    @Binding var plan: TodayPlan
    @Binding var privateData: PrivateCoachData
    let onPersistImmediately: (PrivateCoachData) -> Bool
    @State private var showingMealSubstitution = false
    @State private var substitutionStatus: String?
    @State private var shoppingStatus: String?
    @State private var showingQuickHealthStatus = false
    @State private var showingExpense = false

    private var completion: DailyCompletion? {
        TodayFeature.completion(for: plan, in: privateData)
    }

    private var nextMealSlot: MealSlot {
        TodayNextStepAdvisor.quickLogMealSlot(
            plan: plan,
            completion: completion,
            schedule: privateData.profile.dailyRoutineSchedule
        )
    }

    private var unplannedMealSignal: UnplannedMealSpaceSignal {
        UnplannedMealDaySummary.spaceSignal(for: plan.date, logs: privateData.unplannedMealLogs, confirmedFramework: privateData.profile.dailyCalorieFramework)
    }

    private var unplannedMealUpperBound: Int? {
        UnplannedMealDaySummary.estimatedUpperBound(for: plan.date, logs: privateData.unplannedMealLogs)
    }

    private var startDateText: String {
        PlanSchedule.startDate()?.formatted(.dateTime.year().month().day()) ?? "计划开始日"
    }

    var body: some View {
        NavigationStack {
            Group {
                switch PlanSchedule.phase(for: plan.date) {
                case .preparation:
                    ContentUnavailableView("今晚只做准备", systemImage: "calendar.badge.clock", description: Text("第 1 天于 \(startDateText) 开始。仅在开始前一晚准备食材、饭盒与睡眠；不显示正式三餐或计划外餐食打卡。"))
                case .completed:
                    ContentUnavailableView("本阶段已完成", systemImage: "checkmark.seal", description: Text("先做阶段评估并确认下一阶段目标；不会自动生成新的餐食计划。"))
                case .active:
                    List {
                        if let recoverySupport = RecoveryDaySupportService.make(for: plan) {
                            Section {
                                Label(recoverySupport.foodAction, systemImage: "fork.knife")
                                    .foregroundStyle(CoachPalette.recovery)
                            } header: {
                                Text("恢复日饮食")
                            }
                        }

                        Section("采购计划") {
                            NavigationLink {
                                AvailableIngredientsView(privateData: $privateData, onPersistImmediately: onPersistImmediately)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Label("我已有的食材", systemImage: "refrigerator")
                                        .font(.headline)
                                    Text(privateData.availableIngredients.isEmpty ? "拍照或输入，确认后用于核对采购" : "已登记 \(privateData.availableIngredients.count) 项，可随时修改")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            NavigationLink {
                                AllWeeksShoppingPlanView(
                                    currentWeekNumber: currentShoppingPlan?.weekNumber,
                                    privateData: $privateData,
                                    onPersistImmediately: onPersistImmediately
                                )
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Label("8 周采购与已购核对", systemImage: "calendar")
                                        .font(.headline)
                                    Text(shoppingProgressSummary)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            NavigationLink {
                                foodPlanningTools
                            } label: {
                                Label("本周备菜与分装细节", systemImage: "basket")
                            }
                        }

                        Section {
                            NavigationLink {
                                MealCardView(
                                    meal: meal(for: nextMealSlot),
                                    profileKitchenSetup: privateData.profile.kitchenSetup
                                )
                            } label: {
                                FoodNextMealCard(slot: nextMealSlot, meal: meal(for: nextMealSlot))
                            }
                        } header: {
                            Text("下一餐建议")
                        }

                        Section {
                            NavigationLink {
                                FoodTodayMenuView(
                                    plan: plan,
                                    profileKitchenSetup: privateData.profile.kitchenSetup
                                )
                            } label: {
                                Label("查看今天餐单", systemImage: "list.bullet.rectangle")
                            }
                        } footer: {
                            Text("早餐、午餐和晚餐都在这里；先做下一餐即可。")
                        }

                        Section("说明") {
                            Text("这里只提供餐卡、下一餐和备餐步骤；不记录吃了什么，也不估算热量。历史数据仍只保留在本机，不展示、不改写。")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("备餐")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            .listStyle(.insetGrouped)
            #endif
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    if PlanSchedule.dayIndex(for: plan.date) != nil {
                        GlobalQuickLogMenu(
                            onHealth: { showingQuickHealthStatus = true },
                            onExpense: { showingExpense = true }
                        )
                    }
                }
            }
            .sheet(isPresented: $showingMealSubstitution) {
                MealSubstitutionForm(planDate: plan.date, plan: $plan, privateData: $privateData)
            }
            .sheet(isPresented: $showingQuickHealthStatus) {
                HealthStatusForm(planDate: plan.date, isFormalPlanDay: true, ownerID: privateData.profile.id) { status, submissionID, formOwnerID in
                    let result = HealthCheckInService.submit(status, submissionID: submissionID, formOwnerID: formOwnerID, at: .now, plan: plan, data: privateData)
                    if let error = result.validationError { return error }
                    guard onPersistImmediately(result.data) else { return "状态暂未保存；今天的训练与餐卡没有改变。" }
                    plan = result.plan
                    privateData = result.data
                    showingQuickHealthStatus = false
                    return nil
                }
            }
            .sheet(isPresented: $showingExpense) {
                QuickExpenseForm(privateData: $privateData, onPersistImmediately: onPersistImmediately)
            }
        }
    }

    private func meal(for slot: MealSlot) -> MealCard {
        switch slot {
        case .breakfast: plan.breakfast
        case .lunch: plan.lunch
        case .dinner: plan.dinner
        }
    }

    private var foodPlanningTools: some View {
        List {
            Section("按现有食材调整") {
                Button("拍食材并确认重排某一餐", systemImage: "camera.viewfinder") {
                    showingMealSubstitution = true
                }
                Text("先拍现有食材，再核对识别结果和克数；只有你确认后才替换当天餐卡。已标记完成的餐次不能重排，避免改写执行记录。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                ForEach(MealSlot.allCases, id: \.self) { slot in
                    if let substitution = MealSubstitutionService.activeSubstitution(
                        for: plan.date,
                        slot: slot,
                        in: privateData
                    ) {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("\(slot.displayName)已使用确认替换", systemImage: "checkmark.seal.fill")
                                .foregroundStyle(CoachPalette.completed)
                            Text(substitution.replacement.title)
                                .font(.subheadline)
                            Text("原餐：\(substitution.originalMealTitle)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Button("撤回这次\(slot.displayName)重排", role: .destructive) {
                                revokeSubstitution(slot)
                            }
                            .font(.footnote.weight(.semibold))
                        }
                    }
                }
                if let substitutionStatus {
                    Text(substitutionStatus)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if let shoppingPlan = currentShoppingPlan {
                Section("本周采购 · 第 \(shoppingPlan.weekNumber) 周") {
                    LabeledContent(
                        "采购进度",
                        value: "待买 \(pendingCount(in: shoppingPlan)) · 家中已有 \(atHomeCount(in: shoppingPlan)) · 已购 \(purchasedCount(in: shoppingPlan))"
                    )
                    LabeledContent("建议上限", value: "¥\(shoppingPlan.budgetCapYuan.description)")
                    Text(shoppingPlan.priceStatus)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text(ProgramFoodBudgetPolicy.guidance(for: shoppingPlan))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text(BudgetPolicy.weeklyShoppingGuidance(
                        plan: shoppingPlan,
                        confirmedIngredientSpent: confirmedIngredientSpend(for: plan.date)
                    ))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    if !matchingInventoryItems(in: shoppingPlan).isEmpty {
                        Button("把匹配项标为家中已有（\(matchingInventoryItems(in: shoppingPlan).count)）", systemImage: "house.fill") {
                            markMatchingAtHome(in: shoppingPlan)
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                    Text("点按圆圈记为已购；向左滑动或长按可切换“家中已有”，原始计划可恢复。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let shoppingStatus {
                        Text(shoppingStatus)
                            .font(.footnote)
                            .foregroundStyle(CoachPalette.recovery)
                    }
                    ForEach(shoppingPlan.requiredItems) { item in
                        Button {
                            togglePurchased(item)
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: itemStateIcon(item))
                                    .foregroundStyle(itemStateColor(item))
                                    .frame(width: 24, height: 24)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("\(item.name) · \(item.quantity)")
                                        .font(.subheadline.weight(.medium))
                                    Text(itemStateLabel(item))
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(itemStateColor(item))
                                    if !item.prepNote.isEmpty {
                                        Text(item.prepNote)
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(isAtHome(item) ? "恢复待买" : "家中已有", systemImage: isAtHome(item) ? "cart" : "house.fill") {
                                toggleAtHome(item)
                            }
                            .tint(CoachPalette.action)
                        }
                        .contextMenu {
                            Button(isAtHome(item) ? "恢复待购买" : "标记家中已有", systemImage: isAtHome(item) ? "cart" : "house.fill") { toggleAtHome(item) }
                            Button(isPurchased(item) ? "取消已购" : "标记已购", systemImage: isPurchased(item) ? "circle" : "checkmark.circle") { togglePurchased(item) }
                        }
                        .accessibilityLabel("\(item.name) \(item.quantity)，\(itemStateLabel(item))")
                        .accessibilityHint("点按切换已购状态；向左滑动或长按可标记家中已有")
                    }
                    DisclosureGroup("按餐卡逐项核对克数（不代表额外购买）") {
                        ForEach(WeeklyMealIngredientReference.days(forWeek: shoppingPlan.weekNumber)) { day in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("第 \(day.dayIndex) 天")
                                    .font(.subheadline.weight(.semibold))
                                Text("早餐：\(day.breakfast.ingredients.joined(separator: " · "))")
                                    .font(.footnote)
                                Text("晚餐：\(day.dinner.ingredients.joined(separator: " · "))")
                                    .font(.footnote)
                            }
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.vertical, 4)
                        }
                    }
                }

                if let nextShoppingPlan {
                    Section("下周采购预览 · 第 \(nextShoppingPlan.weekNumber) 周") {
                        Label("提前备菜，不提前记账", systemImage: "calendar.badge.plus")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(CoachPalette.action)
                        Text("这是下周餐卡对应的购买与分装清单；不计入本周采购进度，不会自动下单、查价或标记已购。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        LabeledContent("下周建议上限", value: "¥\(nextShoppingPlan.budgetCapYuan.description)")
                        Text(nextShoppingPlan.priceStatus)
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        ForEach(nextShoppingPlan.requiredItems) { item in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "basket")
                                    .foregroundStyle(CoachPalette.action)
                                    .frame(width: 24, height: 24)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("\(item.name) · \(item.quantity)")
                                        .font(.subheadline.weight(.medium))
                                    Text(item.prepNote)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("下周采购：\(item.name) \(item.quantity)。\(item.prepNote)")
                        }

                        DisclosureGroup("按下周餐卡核对克数") {
                            ForEach(WeeklyMealIngredientReference.days(forWeek: nextShoppingPlan.weekNumber)) { day in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("第 \(day.dayIndex) 天")
                                        .font(.subheadline.weight(.semibold))
                                    Text("早餐：\(day.breakfast.ingredients.joined(separator: " · "))")
                                        .font(.footnote)
                                    Text("晚餐：\(day.dinner.ingredients.joined(separator: " · "))")
                                        .font(.footnote)
                                }
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.vertical, 4)
                            }
                        }
                    }
                } else {
                    Section("下周采购预览") {
                        Text("这是第 8 周；两个月计划还包含独立收尾 5 天，不再追加采购周。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Section("本周采购") {
                    Text("本周采购清单待补齐；不会生成实时价格或自动下单。")
                        .foregroundStyle(.secondary)
                }
            }

            Section("完整计划") {
                NavigationLink {
                    AllWeeksShoppingPlanView(
                        currentWeekNumber: currentShoppingPlan?.weekNumber,
                        privateData: $privateData,
                        onPersistImmediately: onPersistImmediately
                    )
                } label: {
                    Label("查看全部 8 周采购与备菜", systemImage: "calendar.badge.clock")
                }
                Text("每一周都可查看购买量与冷藏、冷冻和分袋提示，也能逐项核对已购；勾选按周独立保存。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                NavigationLink("按日期查看 61 天日卡") {
                    FoodLibraryView(plan: $plan, privateData: $privateData)
                }
                Text("前 56 天按周执行，最后 5 天用于收尾复盘；每天都可查看餐卡与步骤。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("饮食计划与采购")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var currentShoppingPlan: WeeklyShoppingPlan? {
        guard let dayIndex = PlanSchedule.dayIndex(for: plan.date) else { return nil }
        return ShoppingPlanCatalog.plan(forWeek: ((dayIndex - 1) / 7) + 1)
    }

    private var nextShoppingPlan: WeeklyShoppingPlan? {
        guard let currentShoppingPlan else { return nil }
        return ShoppingPlanCatalog.nextPlan(after: currentShoppingPlan)
    }

    private var shoppingProgressSummary: String {
        guard let currentShoppingPlan else {
            return "第 1–8 周清单均可查看；开始计划后可逐项标记已购。"
        }
        return "第 \(currentShoppingPlan.weekNumber) 周 · 已购 \(purchasedCount(in: currentShoppingPlan))/\(currentShoppingPlan.requiredItems.count) 项；每周独立保存。"
    }

    private func isPurchased(_ item: ShoppingItem) -> Bool {
        guard let currentShoppingPlan else { return false }
        return ShoppingPurchaseState.isMarkedPurchased(item, in: currentShoppingPlan, keys: privateData.purchasedShoppingItemKeys)
    }

    private func isAtHome(_ item: ShoppingItem) -> Bool {
        guard let currentShoppingPlan else { return false }
        return ShoppingPurchaseState.isMarkedAtHome(item, in: currentShoppingPlan, keys: privateData.atHomeShoppingItemKeys)
    }

    private func itemStateLabel(_ item: ShoppingItem) -> String {
        if isPurchased(item) { return "已购" }
        if isAtHome(item) { return "家中已有 · 不需购买" }
        return "待购买"
    }

    private func itemStateIcon(_ item: ShoppingItem) -> String {
        if isPurchased(item) { return "checkmark.circle.fill" }
        if isAtHome(item) { return "house.fill" }
        return "circle"
    }

    private func itemStateColor(_ item: ShoppingItem) -> Color {
        if isPurchased(item) { return CoachPalette.completed }
        if isAtHome(item) { return CoachPalette.action }
        return .secondary
    }

    private func toggleAtHome(_ item: ShoppingItem) {
        guard let currentShoppingPlan else { return }
        var updatedData = privateData
        let wasAtHome = isAtHome(item)
        updatedData.atHomeShoppingItemKeys = ShoppingPurchaseState.toggledAtHome(item, in: currentShoppingPlan, keys: privateData.atHomeShoppingItemKeys)
        // “家中已有”和“已购”是互斥的最终状态。以前从已购直接滑到家中已有时，
        // 两个集合会同时保留，列表因优先显示已购而看起来像切换没有生效。
        if !wasAtHome {
            updatedData.purchasedShoppingItemKeys.remove(currentShoppingPlan.stableKey(for: item))
        }
        guard onPersistImmediately(updatedData) else { shoppingStatus = "家中已有状态暂未保存。"; return }
        privateData = updatedData
    }

    private func matchingInventoryItems(in plan: WeeklyShoppingPlan) -> [ShoppingItem] {
        plan.requiredItems.filter {
            !ShoppingPurchaseState.isMarkedAtHome($0, in: plan, keys: privateData.atHomeShoppingItemKeys)
                && !ShoppingPurchaseState.isMarkedPurchased($0, in: plan, keys: privateData.purchasedShoppingItemKeys)
                && !AvailableIngredientInventory.matchingIngredients(for: $0, in: privateData.availableIngredients).isEmpty
        }
    }

    private func markMatchingAtHome(in plan: WeeklyShoppingPlan) {
        var updated = privateData
        let matches = matchingInventoryItems(in: plan)
        for item in matches {
            updated.atHomeShoppingItemKeys.insert(plan.stableKey(for: item))
            // 库存匹配确认等同于“无需购买”，清掉同周已购标记，避免出现两个状态。
            updated.purchasedShoppingItemKeys.remove(plan.stableKey(for: item))
        }
        guard onPersistImmediately(updated) else { shoppingStatus = "家中已有状态暂未保存。"; return }
        privateData = updated
    }

    private func togglePurchased(_ item: ShoppingItem) {
        guard let currentShoppingPlan else { return }
        var updatedData = privateData
        let wasPurchased = isPurchased(item)
        updatedData.purchasedShoppingItemKeys = ShoppingPurchaseState.toggled(
            item,
            in: currentShoppingPlan,
            keys: privateData.purchasedShoppingItemKeys
        )
        if !wasPurchased {
            updatedData.atHomeShoppingItemKeys.remove(currentShoppingPlan.stableKey(for: item))
        }
        guard onPersistImmediately(updatedData) else {
            shoppingStatus = "采购勾选暂未保存；当前清单没有改变，也不代表已购买。"
            return
        }
        privateData = updatedData
        shoppingStatus = nil
    }

    private func purchasedCount(in plan: WeeklyShoppingPlan) -> Int {
        plan.requiredItems.filter(isPurchased).count
    }

    private func atHomeCount(in plan: WeeklyShoppingPlan) -> Int {
        plan.requiredItems.filter { ShoppingPurchaseState.isMarkedAtHome($0, in: plan, keys: privateData.atHomeShoppingItemKeys) }.count
    }

    private func pendingCount(in plan: WeeklyShoppingPlan) -> Int {
        plan.requiredItems.filter { !ShoppingPurchaseState.isMarkedAtHome($0, in: plan, keys: privateData.atHomeShoppingItemKeys) && !ShoppingPurchaseState.isMarkedPurchased($0, in: plan, keys: privateData.purchasedShoppingItemKeys) }.count
    }

    private func confirmedIngredientSpend(for date: Date) -> Decimal {
        guard let programWeek = PlanSchedule.programWeekInterval(for: date) else { return 0 }
        return privateData.confirmedSpentYuan(
            in: .ingredients,
            during: programWeek,
            asOf: date
        )
    }

    private func revokeSubstitution(_ slot: MealSlot) {
        let result = MealSubstitutionService.revokeLatest(for: plan, slot: slot, in: privateData)
        guard result.wasReverted else {
            substitutionStatus = result.validationErrors.first
            return
        }
        var committedData = result.data
        if let reference = result.photoReferenceToDelete {
            do {
                // Stage the image instead of deleting it outright. Persist the new private
                // record before final disposal; a write failure then restores both the active
                // substitution and the photo rather than leaving a dangling card reference.
                let photoStore = try PrivateMealPhotoStore.forOwner(privateData.profile.id)
                let staged = try photoStore.stageReferencedPhotosForDeletion(references: [reference])
                if let substitutionID = result.revertedSubstitutionID,
                   let index = committedData.mealSubstitutions.firstIndex(where: { $0.id == substitutionID }) {
                    committedData.mealSubstitutions[index].localIngredientPhotoReference = nil
                }
                do {
                    try CoachPrivateStorage.saveLastOwnerData(committedData)
                } catch {
                    try? photoStore.restoreStagedReferencedPhotos(staged)
                    throw error
                }
                // The record is already durable. Never restore a photo reference after this
                // point; a best-effort purge keeps an interrupted final disposal private and
                // launch-time cleanup will finish the same App-private staging transaction.
                do {
                    try photoStore.commitStagedReferencedPhotoDeletion(staged)
                } catch {
                    try? photoStore.purgePendingStagedDeletions()
                }
                plan = result.plan
                privateData = committedData
                substitutionStatus = "已撤回当天\(slot.displayName)重排，并删除这次食材照片；文字变更历史仍保留在本机。"
            } catch {
                substitutionStatus = "重排或照片暂未安全保存；原重排保持不变，可稍后重试。"
            }
        } else {
            do {
                try CoachPrivateStorage.saveLastOwnerData(committedData)
                plan = result.plan
                privateData = committedData
                substitutionStatus = "已撤回当天\(slot.displayName)重排；文字变更历史仍保留在本机。"
            } catch {
                substitutionStatus = "重排记录暂未保存；原重排保持不变，可稍后重试。"
            }
        }
    }

}

private enum ShoppingListFilter: String, CaseIterable, Identifiable {
    case pending
    case atHome
    case purchased
    case all

    var id: Self { self }
    var title: String {
        switch self {
        case .pending: "待买"
        case .atHome: "家中已有"
        case .purchased: "已购"
        case .all: "全部"
        }
    }
}

private struct AllWeeksShoppingPlanView: View {
    let currentWeekNumber: Int?
    @Binding var privateData: PrivateCoachData
    let onPersistImmediately: (PrivateCoachData) -> Bool
    @State private var shoppingStatus: String?
    @State private var filters: [Int: ShoppingListFilter] = [:]
    @State private var jumpWeek = 1

    private var plans: [WeeklyShoppingPlan] {
        (1...8).compactMap(ShoppingPlanCatalog.plan(forWeek:))
    }

    var body: some View {
        ScrollViewReader { proxy in
            List {
            Section {
                Text("每周可逐项核对已购，勾选只保存到对应周次；不会扣减预算、自动查价或下单。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Picker("快速定位周次", selection: $jumpWeek) {
                    ForEach(plans) { plan in
                        Text("第 \(plan.weekNumber) 周" + (currentWeekNumber == plan.weekNumber ? "（本周）" : ""))
                            .tag(plan.weekNumber)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityLabel("快速定位采购周次")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(plans) { week in
                            Button {
                                jumpWeek = week.weekNumber
                            } label: {
                                VStack(spacing: 2) {
                                    Text("第\(week.weekNumber)周")
                                        .font(.caption.weight(.semibold))
                                    Text("\(purchasedCount(in: week))/\(week.requiredItems.count) 已购")
                                        .font(.caption2)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .foregroundStyle(jumpWeek == week.weekNumber ? .white : .primary)
                                .background(jumpWeek == week.weekNumber ? CoachPalette.action : Color.secondary.opacity(0.12), in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("第\(week.weekNumber)周，已购\(purchasedCount(in: week))项，共\(week.requiredItems.count)项")
                        }
                    }
                }
                Text("每次只展开所选周，切换上方周次即可核对下一周；各周的待买、家中已有、已购状态独立保存。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let shoppingStatus {
                    Text(shoppingStatus)
                        .font(.footnote)
                        .foregroundStyle(CoachPalette.recovery)
                }
            }

            // Keep the full 8-week index visible above, but render one week at a time so the
            // actual checklist remains scannable on iPhone instead of becoming a long wall of
            // rows. Switching weeks never resets filters or purchase state.
            ForEach(plans.filter { $0.weekNumber == jumpWeek }) { shoppingPlan in
                Section {
                    LabeledContent("采购进度", value: "待买 \(pendingCount(in: shoppingPlan)) · 家中已有 \(atHomeCount(in: shoppingPlan)) · 已购 \(purchasedCount(in: shoppingPlan))")
                    LabeledContent("建议上限", value: "¥\(shoppingPlan.budgetCapYuan.description)")
                    Text(shoppingPlan.priceStatus)
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Picker("显示", selection: Binding(
                        get: { filters[shoppingPlan.weekNumber] ?? .pending },
                        set: { filters[shoppingPlan.weekNumber] = $0 }
                    )) {
                        ForEach(ShoppingListFilter.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("第 \(shoppingPlan.weekNumber) 周采购筛选")

                    ForEach(filteredItems(in: shoppingPlan, filter: filters[shoppingPlan.weekNumber] ?? .pending)) { item in
                        HStack(alignment: .top, spacing: 10) {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: itemStateIcon(item, in: shoppingPlan))
                                    .foregroundStyle(itemStateColor(item, in: shoppingPlan))
                                    .frame(width: 24, height: 24)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("\(item.name) · \(item.quantity)")
                                        .font(.subheadline.weight(.medium))
                                    Text(itemStateLabel(item, in: shoppingPlan))
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(itemStateColor(item, in: shoppingPlan))
                                    Text(item.prepNote)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            Menu {
                                Button("标记待购买", systemImage: "circle") { setPending(item, in: shoppingPlan) }
                                Button("标记家中已有", systemImage: "house.fill") { setAtHome(item, in: shoppingPlan) }
                                Button("标记已购", systemImage: "checkmark.circle.fill") { setPurchased(item, in: shoppingPlan) }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                                    .font(.title3)
                                    .foregroundStyle(itemStateColor(item, in: shoppingPlan))
                                    .frame(width: 36, height: 36)
                            }
                            .accessibilityLabel("更改\(item.name)状态")
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("第 \(shoppingPlan.weekNumber) 周采购：\(item.name) \(item.quantity)，\(itemStateLabel(item, in: shoppingPlan))。\(item.prepNote)")
                        .accessibilityHint("使用右侧菜单明确选择待购买、家中已有或已购，仅影响第 \(shoppingPlan.weekNumber) 周")
                    }
                } header: {
                    HStack {
                        Text("第 \(shoppingPlan.weekNumber) 周采购与备菜")
                        if currentWeekNumber == shoppingPlan.weekNumber {
                            Text("本周")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(CoachPalette.action)
                        }
                    }
                }
                .id(shoppingPlan.weekNumber)
            }
            }
            .navigationTitle("8 周采购总览")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .onAppear {
                jumpWeek = currentWeekNumber ?? 1
                DispatchQueue.main.async {
                    proxy.scrollTo(jumpWeek, anchor: .top)
                }
            }
            .onChange(of: jumpWeek) { _, week in
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(week, anchor: .top)
                }
            }
        }
    }

    private func isPurchased(_ item: ShoppingItem, in plan: WeeklyShoppingPlan) -> Bool {
        ShoppingPurchaseState.isMarkedPurchased(item, in: plan, keys: privateData.purchasedShoppingItemKeys)
    }

    private func purchasedCount(in plan: WeeklyShoppingPlan) -> Int {
        plan.requiredItems.filter { isPurchased($0, in: plan) }.count
    }

    private func isAtHome(_ item: ShoppingItem, in plan: WeeklyShoppingPlan) -> Bool {
        ShoppingPurchaseState.isMarkedAtHome(item, in: plan, keys: privateData.atHomeShoppingItemKeys)
    }

    private func atHomeCount(in plan: WeeklyShoppingPlan) -> Int {
        plan.requiredItems.filter { isAtHome($0, in: plan) }.count
    }

    private func pendingCount(in plan: WeeklyShoppingPlan) -> Int {
        plan.requiredItems.filter { !isAtHome($0, in: plan) && !isPurchased($0, in: plan) }.count
    }

    private func filteredItems(in plan: WeeklyShoppingPlan, filter: ShoppingListFilter) -> [ShoppingItem] {
        switch filter {
        case .pending:
            return plan.requiredItems.filter { !isAtHome($0, in: plan) && !isPurchased($0, in: plan) }
        case .atHome:
            return plan.requiredItems.filter { isAtHome($0, in: plan) }
        case .purchased:
            return plan.requiredItems.filter { isPurchased($0, in: plan) }
        case .all:
            return plan.requiredItems
        }
    }

    private func setPending(_ item: ShoppingItem, in plan: WeeklyShoppingPlan) {
        var updated = privateData
        updated.purchasedShoppingItemKeys.remove(plan.stableKey(for: item))
        updated.atHomeShoppingItemKeys.remove(plan.stableKey(for: item))
        guard onPersistImmediately(updated) else { shoppingStatus = "采购状态暂未保存。"; return }
        privateData = updated
    }

    private func setAtHome(_ item: ShoppingItem, in plan: WeeklyShoppingPlan) {
        var updated = privateData
        updated.atHomeShoppingItemKeys.insert(plan.stableKey(for: item))
        updated.purchasedShoppingItemKeys.remove(plan.stableKey(for: item))
        guard onPersistImmediately(updated) else { shoppingStatus = "采购状态暂未保存。"; return }
        privateData = updated
    }

    private func setPurchased(_ item: ShoppingItem, in plan: WeeklyShoppingPlan) {
        var updated = privateData
        updated.purchasedShoppingItemKeys.insert(plan.stableKey(for: item))
        updated.atHomeShoppingItemKeys.remove(plan.stableKey(for: item))
        guard onPersistImmediately(updated) else { shoppingStatus = "采购状态暂未保存。"; return }
        privateData = updated
    }

    private func itemStateLabel(_ item: ShoppingItem, in plan: WeeklyShoppingPlan) -> String {
        if isPurchased(item, in: plan) { return "已购" }
        if isAtHome(item, in: plan) { return "家中已有 · 不需购买" }
        return "待购买"
    }

    private func itemStateIcon(_ item: ShoppingItem, in plan: WeeklyShoppingPlan) -> String {
        if isPurchased(item, in: plan) { return "checkmark.circle.fill" }
        if isAtHome(item, in: plan) { return "house.fill" }
        return "circle"
    }

    private func itemStateColor(_ item: ShoppingItem, in plan: WeeklyShoppingPlan) -> Color {
        if isPurchased(item, in: plan) { return CoachPalette.completed }
        if isAtHome(item, in: plan) { return CoachPalette.action }
        return .secondary
    }

    private func toggleAtHome(_ item: ShoppingItem, in plan: WeeklyShoppingPlan) {
        var updated = privateData
        let wasAtHome = isAtHome(item, in: plan)
        updated.atHomeShoppingItemKeys = ShoppingPurchaseState.toggledAtHome(item, in: plan, keys: privateData.atHomeShoppingItemKeys)
        if !wasAtHome {
            updated.purchasedShoppingItemKeys.remove(plan.stableKey(for: item))
        }
        guard onPersistImmediately(updated) else { shoppingStatus = "家中已有状态暂未保存。"; return }
        privateData = updated
    }

    private func togglePurchased(_ item: ShoppingItem, in plan: WeeklyShoppingPlan) {
        var updatedData = privateData
        let wasPurchased = isPurchased(item, in: plan)
        updatedData.purchasedShoppingItemKeys = ShoppingPurchaseState.toggled(
            item,
            in: plan,
            keys: privateData.purchasedShoppingItemKeys
        )
        if !wasPurchased {
            updatedData.atHomeShoppingItemKeys.remove(plan.stableKey(for: item))
        }
        guard onPersistImmediately(updatedData) else {
            shoppingStatus = "第 \(plan.weekNumber) 周的采购勾选暂未保存；当前状态没有改变。"
            return
        }
        privateData = updatedData
        shoppingStatus = nil
    }
}

private struct AvailableIngredientsView: View {
    @Binding var privateData: PrivateCoachData
    let onPersistImmediately: (PrivateCoachData) -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var ingredientText = ""
    @State private var quantityText = ""
    @State private var unit = "g"
    @State private var source: AvailableIngredientSource = .manual
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var pendingPhotoData: Data?
    @State private var status: String?
    @State private var showingCamera = false

    private let units = ["g", "kg", "ml", "个", "盒", "袋", "份"]

    var body: some View {
        List {
            Section("添加家中已有食材") {
                Text("拍照只作本机辅助；请核对名称和数量后保存。不会记录餐食或热量，也不会上传照片。")
                    .font(.footnote).foregroundStyle(.secondary)
                #if canImport(UIKit)
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button { showingCamera = true } label: { Label("拍摄食材照片", systemImage: "camera") }
                }
                #endif
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Label("从相册选择照片", systemImage: "photo.on.rectangle")
                }
                .onChange(of: selectedPhoto) { _, item in
                    guard let item else { return }
                    Task {
                        if let data = try? await item.loadTransferable(type: Data.self) {
                            pendingPhotoData = data
                            source = .photoAssisted
                            status = "照片已暂存；请填写并核对名称、数量后保存。"
                        }
                    }
                }
                TextField("食材名称，如鸡蛋", text: $ingredientText)
                HStack {
                    TextField("数量", text: $quantityText)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                    Picker("单位", selection: $unit) { ForEach(units, id: \.self) { Text($0).tag($0) } }
                        .pickerStyle(.menu)
                }
                Button("保存到已有食材") { addIngredient() }
                    .buttonStyle(.borderedProminent)
                    .disabled(ingredientText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || Decimal(string: quantityText) == nil)
                if let status { Text(status).font(.footnote).foregroundStyle(CoachPalette.recovery) }
            }
            Section("已确认的食材") {
                if privateData.availableIngredients.isEmpty {
                    Text("还没有记录。你可以先输入冰箱里的食材，再回到采购清单核对。")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(privateData.availableIngredients) { ingredient in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(ingredient.name).font(.subheadline.weight(.semibold))
                                Text(ingredient.quantity.description + " " + ingredient.unit + " · " + (ingredient.source == .photoAssisted ? "照片辅助" : "手动输入"))
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(role: .destructive) { remove(ingredient) } label: { Image(systemName: "trash") }
                                .accessibilityLabel("删除\(ingredient.name)")
                        }
                    }
                    .onDelete { offsets in
                        var updated = privateData
                        let ids = offsets.map { privateData.availableIngredients[$0].id }
                        updated.availableIngredients.removeAll { ids.contains($0.id) }
                        _ = persist(updated)
                    }
                }
            }
            Section("采购清单如何使用") {
                Text("打开每周采购清单后，可将匹配项标为“家中已有”。原始计划不会删除，可随时恢复为待购买；每周状态独立保存，家中已有不计入新支出。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("我已有的食材")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        #if canImport(UIKit)
        .fullScreenCover(isPresented: $showingCamera) {
            PrivateFoodCameraPicker(onImage: { data in
                pendingPhotoData = data; source = .photoAssisted; status = "照片已暂存；请填写并核对名称、数量后保存。"; showingCamera = false
            }, onCancel: { showingCamera = false })
                .ignoresSafeArea()
        }
        #endif
    }

    private func addIngredient() {
        guard let quantity = Decimal(string: quantityText), quantity >= 0 else { status = "请输入有效数量。"; return }
        let trimmed = ingredientText.trimmingCharacters(in: .whitespacesAndNewlines)
        var reference: String?
        if let pendingPhotoData, let store = try? PrivateMealPhotoStore.forOwner(privateData.profile.id) {
            reference = try? store.save(data: pendingPhotoData)
        }
        let ingredient = AvailableIngredient(name: trimmed, quantity: quantity, unit: unit, source: source, localPhotoReference: reference)
        var updated = privateData
        updated.availableIngredients.append(ingredient)
        guard persist(updated) else { status = "保存失败，当前清单未改变。"; return }
        ingredientText = ""; quantityText = ""; pendingPhotoData = nil; selectedPhoto = nil; source = .manual
        status = "已保存。现在可在采购清单把匹配项标为“家中已有”。"
    }

    private func remove(_ ingredient: AvailableIngredient) {
        var updated = privateData
        updated.availableIngredients.removeAll { $0.id == ingredient.id }
        _ = persist(updated)
    }

    private func persist(_ data: PrivateCoachData) -> Bool {
        guard onPersistImmediately(data) else { return false }
        privateData = data
        return true
    }
}

private struct FoodNextMealCard: View {
    let slot: MealSlot
    let meal: MealCard

    private var totalMinutes: String { meal.totalOperationText ?? "总操作待确认" }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "fork.knife")
                .font(.title2.weight(.semibold))
                .foregroundStyle(CoachPalette.action)
                .frame(width: 48, height: 48)
                .background(CoachPalette.action.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text("开始\(slot.displayName)备餐")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CoachPalette.action)
                Text(meal.displayTitle)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Label(totalMinutes, systemImage: "timer")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let firstExecutionStep = meal.firstExecutionStep {
                    Text("现在：\(firstExecutionStep)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .frame(minHeight: 94)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("开始\(slot.displayName)备餐，\(meal.displayTitle)，\(totalMinutes)，\(meal.firstExecutionStep ?? "按克数备好食材")，查看完整步骤与饭盒安全")
    }
}

/// The preparation home deliberately names only the next meal.  The full day menu remains one
/// explicit tap away for planning, without making three equally prominent cards compete with the
/// action that can be started now.
private struct FoodTodayMenuView: View {
    let plan: TodayPlan
    let profileKitchenSetup: String?

    private func meal(for slot: MealSlot) -> MealCard {
        switch slot {
        case .breakfast: plan.breakfast
        case .lunch: plan.lunch
        case .dinner: plan.dinner
        }
    }

    var body: some View {
        List {
            Section("今天餐单") {
                ForEach(MealSlot.allCases, id: \.self) { slot in
                    NavigationLink {
                        MealCardView(
                            meal: meal(for: slot),
                            profileKitchenSetup: profileKitchenSetup
                        )
                    } label: {
                        DailyMealNavigationRow(slot: slot, meal: meal(for: slot))
                    }
                }
            }
        }
        .navigationTitle("今天吃什么")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

/// A meal destination looks tappable at a glance while keeping its detailed recipe one tap away.
/// It deliberately uses a system symbol plus text, rather than color alone, for accessibility.
private struct DailyMealNavigationRow: View {
    let slot: MealSlot
    let meal: MealCard
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var symbol: String {
        switch slot {
        case .breakfast: "sun.max.fill"
        case .lunch: "takeoutbag.and.cup.and.straw.fill"
        case .dinner: "fork.knife"
        }
    }

    private var tint: Color {
        switch slot {
        case .breakfast: CoachPalette.partial
        case .lunch: CoachPalette.action
        case .dinner: CoachPalette.completed
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.headline)
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(slot.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                Text(meal.displayTitle)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: dynamicTypeSize.isAccessibilitySize)
                Text(meal.ingredients.prefix(2).joined(separator: " · "))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                Label(meal.totalOperationText ?? "20 分钟内", systemImage: "timer")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .frame(minHeight: 58)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(slot.displayName)，\(meal.displayTitle)。查看食材、步骤与饭盒安全")
    }
}

private struct MealSubstitutionForm: View {
    /// The parent plan refreshes at midnight. Retain the day that was visible when this form
    /// opened so yesterday's typed ingredients can never be confirmed into today's card.
    let planDate: Date
    @Binding var plan: TodayPlan
    @Binding var privateData: PrivateCoachData
    @Environment(\.dismiss) private var dismiss
    @State private var availableFood = ""
    @State private var selectedIngredientPhoto: PhotosPickerItem?
    @State private var showingIngredientCamera = false
    /// An ingredient photo stays only in this sheet's memory until the person explicitly confirms
    /// the replacement. Cancelling or closing the sheet therefore creates no private file to clean.
    @State private var pendingIngredientPhotoData: Data?
    @State private var photoStatus: String?
    @State private var slot: MealSlot = .dinner
    @State private var title = ""
    @State private var ingredients = ""
    @State private var thawAndPortion = ""
    @State private var timedSteps = ""
    @State private var portionsAndStorage = ""
    @State private var substitutions = ""
    @State private var errors: [String] = []
    @State private var replacementForReview: MealCard?
    @State private var showingReview = false
    @State private var didConfirmSubstitution = false
    @State private var isConfirmingSubstitution = false
    /// PhotosPicker can finish loading after this sheet has been dismissed. Keep a local display
    /// lifetime flag so late data is discarded rather than being held by a dismissed form.
    @State private var isFormVisible = false
    /// A previous PhotosPicker load can finish after the person chooses another image. Keep a
    /// generation rather than trusting completion order, so an old photo never overwrites the
    /// currently selected one in the review/confirmation flow.
    @State private var ingredientPhotoLoadGeneration = 0
    @State private var observedNow: Date
    /// A sheet may remain alive for one UI turn while full local-data deletion returns the shell
    /// to first-run setup. Associate all delayed image data and confirmation with the profile
    /// that opened this form; never attach it to the replacement profile.
    @State private var formOwnerID: UUID
    @State private var pendingIngredientPhotoOwnerID: UUID?

    init(planDate: Date, plan: Binding<TodayPlan>, privateData: Binding<PrivateCoachData>) {
        self.planDate = planDate
        _plan = plan
        _privateData = privateData
        _observedNow = State(initialValue: Date())
        _formOwnerID = State(initialValue: privateData.wrappedValue.profile.id)
    }

    private var openedPlanDayIsCurrent: Bool {
        Calendar.current.isDate(planDate, inSameDayAs: observedNow)
            && Calendar.current.isDate(plan.date, inSameDayAs: planDate)
            && PrivateProfileAsyncOwnershipGate.mayContinue(
                capturedOwnerID: formOwnerID,
                currentOwnerID: privateData.profile.id
            )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("现有食材") {
                    #if canImport(UIKit)
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button {
                            // Only this explicit tap presents a camera controller, which in turn
                            // is the sole path that can cause iOS to ask for camera permission.
                            showingIngredientCamera = true
                        } label: {
                            Label("拍摄家中食材", systemImage: "camera")
                        }
                    }
                    #endif
                    PhotosPicker(selection: $selectedIngredientPhoto, matching: .images) {
                        Label("从照片中选择家中食材", systemImage: "photo.on.rectangle")
                    }
                    .onChange(of: selectedIngredientPhoto) { _, item in
                        ingredientPhotoLoadGeneration &+= 1
                        let generation = ingredientPhotoLoadGeneration
                        // Selection is an explicit replacement, not a request to keep using the
                        // last successfully decoded image while the new picker transfer is in
                        // flight. Clear it before awaiting so an immediate “确认重排” can only
                        // save text (or the latest photo after it finishes), never a stale
                        // ingredient picture that is no longer selected.
                        pendingIngredientPhotoData = nil
                        pendingIngredientPhotoOwnerID = nil
                        guard let item else {
                            photoStatus = "已移除待确认照片；将只按你填写的食材和克数重排。"
                            return
                        }
                        photoStatus = "正在读取新选择的食材照片；未完成前可只按文字和克数重排。"
                        Task { await saveIngredientPhoto(item, generation: generation, ownerID: formOwnerID) }
                    }
                    if pendingIngredientPhotoData != nil {
                        Label("照片待确认；确认重排后才保存到此 App 私有目录", systemImage: "lock.fill")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button("移除待确认照片") {
                            selectedIngredientPhoto = nil
                            pendingIngredientPhotoData = nil
                            pendingIngredientPhotoOwnerID = nil
                            photoStatus = "已移除待确认照片；将只按你填写的食材和克数重排。"
                        }
                        .font(.footnote.weight(.semibold))
                    }
                    TextField("例如：北豆腐 250g、鸡蛋 2 个、西兰花 400g、剩饭 90g", text: $availableFood, axis: .vertical)
                    Text("请按照片自己确认并补全食材与克数；当前版本不把照片当作自动识别结果，也不会上传。")
                        .font(.footnote).foregroundStyle(.secondary)
                    if let photoStatus { Text(photoStatus).font(.footnote).foregroundStyle(CoachPalette.recovery) }
                }
                Section("替换哪一餐") {
                    Picker("餐次", selection: $slot) {
                        ForEach(MealSlot.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                }
                Section("替换后的餐卡") {
                    TextField("餐名", text: $title)
                    TextField("食材克数，每行一项", text: $ingredients, axis: .vertical)
                    TextField("前置解冻 / 分装", text: $thawAndPortion, axis: .vertical)
                    TextField("分钟级步骤，每行一项，如 0:00 …", text: $timedSteps, axis: .vertical)
                    TextField("做几份、冷藏与安全复热；含总操作分钟", text: $portionsAndStorage, axis: .vertical)
                    TextField("低风险食材替换（可写无）", text: $substitutions, axis: .vertical)
                }
                Section {
                    Text("只有你的确认会写入选定餐次；原餐卡、训练和后续计划仍保留。")
                        .font(.footnote).foregroundStyle(.secondary)
                    if !openedPlanDayIsCurrent {
                        Label("日期已切换：这张表单不会把昨天填写的食材或照片重排到今天。请取消后从今天日卡重新打开。", systemImage: "calendar.badge.exclamationmark")
                            .font(.footnote)
                            .foregroundStyle(CoachPalette.recovery)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !errors.isEmpty {
                        ForEach(errors, id: \.self) { Text($0).foregroundStyle(CoachPalette.recovery) }
                    }
                }
            }
            .coachKeyboardDismissal()
            .navigationTitle("替换当天餐卡")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("查看变更预览") { review() }
                        .disabled(!openedPlanDayIsCurrent || isConfirmingSubstitution)
                }
            }
            .sheet(isPresented: $showingReview) {
                if let replacementForReview {
                    MealSubstitutionReview(
                        slot: slot,
                        original: currentMeal,
                        replacement: replacementForReview,
                        isConfirming: isConfirmingSubstitution,
                        canConfirm: openedPlanDayIsCurrent,
                        onConfirm: { confirm(replacementForReview) }
                    )
                }
            }
            #if canImport(UIKit)
            .fullScreenCover(isPresented: $showingIngredientCamera) {
                PrivateFoodCameraPicker(
                    onImage: { data in
                        acceptCapturedIngredientPhoto(data)
                        showingIngredientCamera = false
                    },
                    onCancel: {
                        photoStatus = "未拍摄照片；仍可只填写文字和克数。"
                        showingIngredientCamera = false
                    }
                )
                .ignoresSafeArea()
            }
            #endif
            .onAppear { isFormVisible = true }
            .onDisappear { cleanUpUnconfirmedIngredientPhoto() }
        }
        .task(id: Calendar.current.startOfDay(for: planDate)) {
            while !Task.isCancelled {
                let now = Date()
                guard let nextDay = Calendar.current.nextDate(
                    after: now,
                    matching: DateComponents(hour: 0, minute: 0, second: 0),
                    matchingPolicy: .nextTime
                ) else { return }
                try? await Task.sleep(nanoseconds: UInt64(max(1, nextDay.timeIntervalSince(now)) * 1_000_000_000))
                guard !Task.isCancelled else { return }
                observedNow = Date()
            }
        }
    }

    private func lines(_ value: String) -> [String] {
        value.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private var currentMeal: MealCard {
        switch slot {
        case .breakfast: plan.breakfast
        case .lunch: plan.lunch
        case .dinner: plan.dinner
        }
    }

    private func makeReplacement() -> MealCard {
        let replacement = MealCard(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            ingredients: lines(ingredients),
            thawAndPortion: thawAndPortion.trimmingCharacters(in: .whitespacesAndNewlines),
            timedSteps: lines(timedSteps),
            portionsAndStorage: portionsAndStorage.trimmingCharacters(in: .whitespacesAndNewlines),
            substitutions: substitutions.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        return replacement
    }

    private func review() {
        guard openedPlanDayIsCurrent else {
            observedNow = Date()
            errors = ["日期已切换；这张表单尚未写入。请取消后从今天日卡重新打开。"]
            return
        }
        let replacement = makeReplacement()
        errors = MealSubstitutionService.validationErrors(for: replacement)
            + MealSubstitutionService.availableFoodValidationErrors(availableFood)
        guard errors.isEmpty else { return }
        replacementForReview = replacement
        showingReview = true
    }

    private func confirm(_ replacement: MealCard) {
        // Saving an optional private photo and its confirmed meal card is one owner action.
        // Keep this lock until the sheet closes so a rapid double tap cannot create two photos
        // and two substitution audit entries for the same visible confirmation.
        guard !isConfirmingSubstitution else { return }
        guard Calendar.current.isDate(planDate, inSameDayAs: Date()),
              Calendar.current.isDate(plan.date, inSameDayAs: planDate),
              PrivateProfileAsyncOwnershipGate.mayContinue(
                capturedOwnerID: formOwnerID,
                currentOwnerID: privateData.profile.id
              ) else {
            observedNow = Date()
            errors = ["日期已切换；重排尚未写入。请返回并从今天日卡重新打开。"]
            return
        }
        isConfirmingSubstitution = true
        let preliminaryErrors = MealSubstitutionService.validationErrors(for: replacement)
            + MealSubstitutionService.availableFoodValidationErrors(availableFood)
        guard preliminaryErrors.isEmpty else {
            errors = preliminaryErrors
            isConfirmingSubstitution = false
            return
        }

        let localIngredientPhotoReference: String?
        if let pendingIngredientPhotoData {
            guard pendingIngredientPhotoOwnerID == formOwnerID else {
                errors = ["食材照片归属已失效；没有保存或重排。请从当前资料重新打开。"]
                isConfirmingSubstitution = false
                return
            }
            do {
                localIngredientPhotoReference = try PrivateMealPhotoStore.forOwner(formOwnerID).save(data: pendingIngredientPhotoData)
            } catch {
                errors = ["食材照片未能安全保存到本机；可移除照片后仅按文字和克数确认。"]
                isConfirmingSubstitution = false
                return
            }
        } else {
            localIngredientPhotoReference = nil
        }

        let result = MealSubstitutionService.confirm(
            replacement: replacement,
            for: plan,
            slot: slot,
            availableFoodSummary: availableFood,
            localIngredientPhotoReference: localIngredientPhotoReference,
            confirmedByUser: true,
            in: privateData
        )
        errors = result.validationErrors
        guard errors.isEmpty else {
            if let localIngredientPhotoReference {
                do {
                    try PrivateMealPhotoStore.forOwner(privateData.profile.id).delete(localReference: localIngredientPhotoReference)
                } catch {
                    errors.append("照片暂未清理；请在“我的”删除全部本地资料后重试。")
                }
            }
            isConfirmingSubstitution = false
            return
        }
        // Commit the private audit record before the UI observes the replacement. The optional
        // photo was created solely for this record, so a disk failure must leave neither a new
        // card nor an unreachable private image behind.
        do {
            try CoachPrivateStorage.saveLastOwnerData(result.data)
        } catch {
            if let localIngredientPhotoReference {
                do {
                    try PrivateMealPhotoStore.forOwner(privateData.profile.id).delete(localReference: localIngredientPhotoReference)
                } catch {
                    errors = ["重排记录未能保存，且照片暂未清理；请勿卸载 App，可稍后从“我的”删除全部本地资料。"]
                    isConfirmingSubstitution = false
                    return
                }
            }
            errors = ["重排记录暂未保存；今天餐卡没有改变，请稍后重试。"]
            isConfirmingSubstitution = false
            return
        }
        plan = result.plan
        privateData = result.data
        didConfirmSubstitution = true
        showingReview = false
        dismiss()
    }

    @MainActor private func saveIngredientPhoto(_ item: PhotosPickerItem, generation: Int, ownerID: UUID) async {
        do {
            #if canImport(UIKit)
            // PhotosPicker guarantees Data transfer on current iOS SDKs; UIImage itself is not
            // Transferable. The source bytes remain task-local and only the normalized,
            // size-limited JPEG below may survive this task.
            guard let sourceData = try await item.loadTransferable(type: Data.self),
                  let originalImage = UIImage(data: sourceData) else {
                guard isFormVisible, generation == ingredientPhotoLoadGeneration else { return }
                photoStatus = "食材照片未能读取；仍可用文字和克数确认。"
                return
            }
            guard isFormVisible, generation == ingredientPhotoLoadGeneration,
                  PrivateProfileAsyncOwnershipGate.mayContinue(
                    capturedOwnerID: ownerID,
                    currentOwnerID: privateData.profile.id
                  ) else {
                return
            }
            guard let data = PrivateFoodPhotoPreparation.normalizedJPEG(from: originalImage) else {
                photoStatus = "食材照片格式暂不支持；仍可只填写文字和克数。"
                return
            }
            #else
            guard let data = try await item.loadTransferable(type: Data.self) else {
                guard isFormVisible, generation == ingredientPhotoLoadGeneration else { return }
                photoStatus = "食材照片未能读取；仍可用文字和克数确认。"
                return
            }
            guard isFormVisible, generation == ingredientPhotoLoadGeneration,
                  PrivateProfileAsyncOwnershipGate.mayContinue(
                    capturedOwnerID: ownerID,
                    currentOwnerID: privateData.profile.id
                  ) else {
                return
            }
            #endif
            pendingIngredientPhotoData = data
            pendingIngredientPhotoOwnerID = ownerID
            photoStatus = "照片已在本机缩小后暂存于当前页面；请核对下方食材、克数，确认重排后才会保存到 App 私有目录。"
        } catch {
            guard isFormVisible, generation == ingredientPhotoLoadGeneration else { return }
            photoStatus = "食材照片未能读取；仍可只填写文字食材。"
        }
    }

    private func acceptCapturedIngredientPhoto(_ data: Data) {
        // A picker task that started before taking a new photo must not later replace the newest
        // owner-selected image. Incrementing the same generation makes both image sources obey
        // a single “latest choice wins” rule.
        ingredientPhotoLoadGeneration &+= 1
        guard PrivateProfileAsyncOwnershipGate.mayContinue(
            capturedOwnerID: formOwnerID,
            currentOwnerID: privateData.profile.id
        ) else {
            pendingIngredientPhotoData = nil
            pendingIngredientPhotoOwnerID = nil
            photoStatus = "本机资料已删除或切换；没有保留旧资料的食材照片。"
            return
        }
        // Do not clear `selectedIngredientPhoto` here: its `onChange` handler is intentionally
        // a cancellation boundary and would erase this newer camera image on the next UI pass.
        // The increment above already invalidates any older picker transfer; confirmation uses
        // the newest in-memory data rather than the stale picker handle.
        pendingIngredientPhotoData = data
        pendingIngredientPhotoOwnerID = formOwnerID
        photoStatus = "照片已在本机缩小后暂存于当前页面；请核对下方食材、克数，确认重排后才会保存到 App 私有目录。"
    }

    private func cleanUpUnconfirmedIngredientPhoto() {
        isFormVisible = false
        guard !didConfirmSubstitution else { return }
        pendingIngredientPhotoData = nil
        pendingIngredientPhotoOwnerID = nil
    }
}

/// 用户确认之前的对照页：只比较已有的餐卡字段，不捏造热量、营养或价格差异。
private struct MealSubstitutionReview: View {
    let slot: MealSlot
    let original: MealCard
    let replacement: MealCard
    let isConfirming: Bool
    let canConfirm: Bool
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("将替换今天的\(slot.displayName)") {
                    Text("不会改目标、热量框架、训练或后续日期。只有未完成的餐次可确认重排；确认后才写入本机当天餐卡，并保留原餐与变更记录。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("原餐") { MealReplacementComparison(meal: original) }
                Section("新餐") { MealReplacementComparison(meal: replacement) }
                Section("本次差异") {
                    LabeledContent("餐名", value: "\(original.displayTitle) → \(replacement.displayTitle)")
                    Text("可比较的是食材、前置、总操作时间与饭盒安全规则。餐卡未提供营养数值，因此不会伪造热量或蛋白差异。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("确认餐食重排")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("返回修改") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isConfirming ? "正在写入…" : "确认写入") { onConfirm() }
                        .disabled(isConfirming || !canConfirm)
                }
            }
        }
    }
}

private struct MealReplacementComparison: View {
    let meal: MealCard

    var body: some View {
        Text(meal.displayTitle).font(.headline)
        Text("食材：\(meal.ingredients.joined(separator: " · "))")
            .font(.footnote)
            .fixedSize(horizontal: false, vertical: true)
        Text("前置：\(meal.thawAndPortion)")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        Text(meal.portionsAndStorage)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct UnplannedMealForm: View {
    /// These are internal diary annotations. They retain the estimation boundary in the saved
    /// record, but must never be echoed back into the editable food-name field.
    private static let conservativePhotoMarker = "照片候选保守区间"
    private static let compositionMarker = "｜盘中确认："
    @Binding var privateData: PrivateCoachData
    let date: Date
    let existingLog: UnplannedMealLog?
    let existingPortionChoice: MealPortionChoice
    @Environment(\.dismiss) private var dismiss
    @State private var description = ""
    /// A picker-confirmed count is kept separately so a custom unit entered before the food
    /// name (for example `2 小把` → `2 小把坚果`) survives reopening this local-only record.
    @State private var selectedCountableQuantity: String?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showingMealCamera = false
    /// The selected image is normalized and held only in this sheet until the matching meal log
    /// is confirmed. Cancelling the form therefore leaves no orphaned private photo file.
    @State private var pendingMealPhotoData: Data?
    @State private var pendingMealPhotoOwnerID: UUID?
    @State private var removesExistingPhoto = false
    @State private var photoSuggestion: PrivateFoodPhotoSuggestion?
    @State private var photoStatus: String?
    @State private var isLoadingPhoto = false
    @State private var isAnalyzingPhoto = false
    @State private var calorieLowerBound = ""
    @State private var calorieUpperBound = ""
    @State private var proteinLowerBound = ""
    @State private var proteinUpperBound = ""
    /// Manual numbers can replace a wide photo range only after the owner confirms they cover
    /// the whole serving, including hidden energy sources the photo cannot establish.
    @State private var manualRangeConfirmedByOwner = false
    /// A menu or scale range belongs to the serving it was checked against. Keep a short
    /// reminder when accepting a replacement photo clears such a range.
    @State private var clearedManualRangeForNewPhoto = false
    @State private var portionChoice: MealPortionChoice = .uncertain
    @State private var composition: MealCompositionConfirmation
    /// Vision may prefill a normal plate only to reduce typing. Until the person opens the
    /// portion editor, the saved result must keep the photo category's conservative range.
    @State private var photoUsesDefaultEstimate = false
    /// Text-only extra snacks should start with the food field, not a full photo workflow.
    /// Evidence opens this same section automatically once there is anything to review.
    @State private var showsPhotoOptions = false
    @State private var showsPortionOptions = false
    @State private var showsTextMealPortionOptions = false
    @State private var showsManualEstimateOptions = false
    @State private var saveMessage: String?
    @State private var isSaving = false
    /// Prevent an in-flight PhotosPicker transfer from creating a log/photo after this sheet was
    /// cancelled or swiped away. The flag is local UI lifetime only and is never persisted.
    @State private var isFormVisible = false
    /// A PhotosPicker transfer can finish after the person removes or replaces a selection.
    /// Keep a generation token so a stale image can never be attached to a later text-only log.
    @State private var mealPhotoSelectionGeneration = 0
    @State private var observedNow: Date
    /// Capture the private profile at sheet creation. PhotosPicker can complete after a full
    /// local-data deletion; a late image must be discarded rather than saved under a new owner.
    @State private var formOwnerID: UUID

    init(privateData: Binding<PrivateCoachData>, date: Date, existingLog: UnplannedMealLog? = nil) {
        _privateData = privateData
        self.date = date
        self.existingLog = existingLog
        _observedNow = State(initialValue: Date())
        _formOwnerID = State(initialValue: privateData.wrappedValue.profile.id)
        let parsed = Self.parsedDescriptionAndPortion(existingLog?.userDescription)
        self.existingPortionChoice = parsed.portion
        _description = State(initialValue: parsed.description)
        _selectedCountableQuantity = State(initialValue: MealQuantityNote.storedActualQuantity(in: existingLog?.userDescription))
        _portionChoice = State(initialValue: parsed.portion)
        _composition = State(initialValue: existingLog?.compositionConfirmation ?? MealCompositionConfirmation())
        _photoUsesDefaultEstimate = State(initialValue: existingLog?.estimateSource == .onDevicePhotoCandidate)
        if existingLog?.estimateSource == .ownerProvidedRange,
           let calories = existingLog?.estimatedCaloriesRange {
            _calorieLowerBound = State(initialValue: String(calories.lowerBound))
            _calorieUpperBound = State(initialValue: String(calories.upperBound))
        }
        if existingLog?.estimateSource == .ownerProvidedRange,
           let protein = existingLog?.estimatedProteinGramsRange {
            _proteinLowerBound = State(initialValue: String(protein.lowerBound))
            _proteinUpperBound = State(initialValue: String(protein.upperBound))
        }
        _manualRangeConfirmedByOwner = State(initialValue: existingLog?.estimateSource == .ownerProvidedRange)
        _showsManualEstimateOptions = State(initialValue: existingLog?.estimateSource == .ownerProvidedRange)
    }

    private static func parsedDescriptionAndPortion(_ saved: String?) -> (description: String, portion: MealPortionChoice) {
        guard let saved else { return ("", .uncertain) }
        let marker = "｜份量："
        let portion: MealPortionChoice
        let withoutPortion: String
        if let markerRange = saved.range(of: marker, options: .backwards),
           let parsed = MealPortionChoice.fromPersistedDisplayName(String(saved[markerRange.upperBound...])) {
            portion = parsed
            withoutPortion = String(saved[..<markerRange.lowerBound])
        } else {
            portion = .uncertain
            withoutPortion = saved
        }
        let withoutComposition = withoutPortion.components(separatedBy: Self.compositionMarker).first ?? withoutPortion
        let cleanDescription = MealQuantityNote.removingStoredActualQuantity(from: withoutComposition)
            .replacingOccurrences(of: "｜\(Self.conservativePhotoMarker)", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (cleanDescription, portion)
    }

    private var openedPlanDayIsCurrent: Bool {
        UnplannedMealLoggingPolicy.validationError(for: date, at: observedNow) == nil
            && PrivateProfileAsyncOwnershipGate.mayContinue(
                capturedOwnerID: formOwnerID,
                currentOwnerID: privateData.profile.id
            )
    }

    private var trimmedDescription: String {
        description.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasFoodDescription: Bool {
        MealQuantityNote.hasFoodDescription(
            trimmedDescription,
            excluding: selectedCountableQuantity
        )
    }

    private var hasManualRangeInput: Bool {
        !calorieLowerBound.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !calorieUpperBound.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !proteinLowerBound.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !proteinUpperBound.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var confirmedDescription: String {
        let explicitQuantity = selectedCountableQuantity
            ?? MealQuantityNote.actualQuantity(from: trimmedDescription, plannedTitle: "")
        let descriptionWithQuantity = MealQuantityNote.merging(trimmedDescription, with: explicitQuantity) ?? trimmedDescription
        if photoRequiresConservativeRange {
            return "\(descriptionWithQuantity)｜\(Self.conservativePhotoMarker)"
        }
        // The fast photo path only prefilled the editor to reduce typing. Until the owner
        // changes portions, it must not serialize a “盘中确认” annotation that never happened.
        // Its on-device photo-candidate source already retains the intentionally wide range.
        if photoUsesDefaultEstimate { return descriptionWithQuantity }
        return "\(descriptionWithQuantity)\(Self.compositionMarker)\(composition.summary)"
    }

    private var manualRangeResetReminder: String {
        clearedManualRangeForNewPhoto ? " 已清空旧菜单/秤与盘中确认，请按新照片重新核对。" : ""
    }

    /// A replacement image is new evidence. Never carry a confirmed menu/scale range or plate
    /// components from the previous meal into it: oil, extras, and eaten amount may all differ.
    private func resetManualRangesForAcceptedNewPhoto() {
        let hadManualRange = hasManualRangeInput || manualRangeConfirmedByOwner
        let hadCompositionConfirmation = composition.hasAnyOwnerSelection
        calorieLowerBound = ""
        calorieUpperBound = ""
        proteinLowerBound = ""
        proteinUpperBound = ""
        manualRangeConfirmedByOwner = false
        showsManualEstimateOptions = false
        composition = MealCompositionConfirmation()
        clearedManualRangeForNewPhoto = hadManualRange || hadCompositionConfirmation
    }

    private var retainedPhotoSuggestedCaloriesRange: ClosedRange<Int>? {
        guard existingLog?.estimateSource == .onDevicePhotoCandidate,
              pendingMealPhotoData == nil,
              let savedRange = existingLog?.estimatedCaloriesRange else { return nil }
        return existingPortionChoice.restoringApproximateBase(from: savedRange)
    }

    /// Reopening a saved high-energy photo record must retain its conservative boundary. This
    /// prevents a later text correction from silently applying a generic normal-plate preset to
    /// the old photo. The marker is stored in prior versions as part of the private note, so
    /// this is backwards-compatible without mutating existing diary data.
    private var retainedPhotoRequiresConservativeRange: Bool {
        guard existingLog?.estimateSource == .onDevicePhotoCandidate,
              pendingMealPhotoData == nil else { return false }
        return existingLog?.userDescription.contains(Self.conservativePhotoMarker) == true
    }

    private var saveUnavailableReason: String? {
        if isSaving { return "正在保存这条餐食记录，请稍候。" }
        if isLoadingPhoto { return "照片仍在本机处理中，完成后即可记录。" }
        if isAnalyzingPhoto { return "正在本机分析照片，完成后再核对记录。" }
        if !openedPlanDayIsCurrent { return "这张表单已失效；请取消后从今天重新打开。" }
        if !hasFoodDescription { return "数量后请补菜名，例如：鸡蛋 2 个。" }
        if hasManualRangeInput, !manualRangeConfirmedByOwner {
            return "要采用手动范围，请先确认它覆盖整份油、甜饮、配料和实际吃掉量。"
        }
        return nil
    }

    private var usesPhotoFastDefaults: Bool {
        photoSuggestion != nil
            && photoUsesDefaultEstimate
            && descriptionMatchesPhotoCandidate
    }

    /// A changed food name is not a confirmation of the Vision candidate. The photo remains a
    /// local, conservative range input, while the person records through the normal action.
    private var descriptionMatchesPhotoCandidate: Bool {
        guard let photoSuggestion else { return true }
        return trimmedDescription == photoSuggestion.provisionalDescription
    }

    private var photoRequiresConservativeRange: Bool {
        photoSuggestion?.requiresConservativeCalorieRange == true
            || retainedPhotoRequiresConservativeRange
    }

    private var photoSectionIsActive: Bool {
        selectedPhoto != nil
            || pendingMealPhotoData != nil
            || existingLog?.localPhotoReference != nil
            || isLoadingPhoto
            || isAnalyzingPhoto
            || photoSuggestion != nil
            || photoStatus != nil
    }

    /// This is the exact draft that will be persisted after confirmation. Showing it before the
    /// record button is important: the person never has to save a hidden default estimate first.
    private var estimatePreview: UnplannedMealLog? {
        makeMealEstimate(localPhotoReference: nil)
    }

    private var confirmedManualCaloriesRange: ClosedRange<Int>? {
        guard manualRangeConfirmedByOwner else { return nil }
        return validRange(lower: calorieLowerBound, upper: calorieUpperBound)
    }

    private var confirmedManualProteinRange: ClosedRange<Int>? {
        guard manualRangeConfirmedByOwner else { return nil }
        return validRange(lower: proteinLowerBound, upper: proteinUpperBound)
    }

    /// The result card and the saved log must follow one estimate recipe. In particular, a
    /// high-energy photo may be previewed only with a conservative range, and that guard must
    /// not get lost between the preview and the later private-photo write transaction.
    private func makeMealEstimate(localPhotoReference: String?) -> UnplannedMealLog? {
        guard hasFoodDescription else { return nil }
        return UnplannedMealEstimator.estimate(
            description: confirmedDescription,
            localPhotoReference: localPhotoReference,
            photoSuggestedCaloriesRange: photoSuggestion?.estimatedCaloriesRange ?? retainedPhotoSuggestedCaloriesRange,
            photoRequiresConservativeRange: photoRequiresConservativeRange,
            portionChoice: portionChoice,
            manualCaloriesRange: confirmedManualCaloriesRange,
            manualProteinRange: confirmedManualProteinRange,
            manualRangeConfirmedByOwner: manualRangeConfirmedByOwner,
            // The owner-confirmed menu/scale range is the final estimate source. Do not carry
            // an independently calculated component midpoint into the preview or saved record.
            compositionConfirmation: photoRequiresConservativeRange || photoUsesDefaultEstimate || confirmedManualCaloriesRange != nil ? nil : composition,
            at: date
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DisclosureGroup(
                        isExpanded: Binding(
                            get: { photoSectionIsActive || showsPhotoOptions },
                            set: { showsPhotoOptions = $0 }
                        )
                    ) {
                    HStack(spacing: 10) {
                    #if canImport(UIKit)
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button {
                            showingMealCamera = true
                        } label: {
                            Label("拍照", systemImage: "camera.fill")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    #endif
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label("相册", systemImage: "photo.on.rectangle")
                    }
                    .buttonStyle(.bordered)
                    }
                    .onChange(of: selectedPhoto) { _, item in
                        mealPhotoSelectionGeneration &+= 1
                        let generation = mealPhotoSelectionGeneration
                        pendingMealPhotoData = nil
                        pendingMealPhotoOwnerID = nil
                        discardUnconfirmedPhotoDefaults()
                        removesExistingPhoto = false
                        guard let item else {
                            isLoadingPhoto = false
                            isAnalyzingPhoto = false
                            photoStatus = "已移除待确认照片；将只保存文字和保守估算。"
                            return
                        }
                        isLoadingPhoto = true
                        photoStatus = "正在本机读取并缩小照片…"
                        Task { await loadMealPhoto(item, generation: generation, ownerID: formOwnerID) }
                    }
                    DisclosureGroup {
                        Text("照片只在本机使用 Apple Vision 识别和保存，不上传；保存前请核对候选，名称不同就写下你的菜名。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } label: {
                        Label("仅本机 · 不上传 · 非称重", systemImage: "lock.fill")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    if isLoadingPhoto || isAnalyzingPhoto {
                        Label(isLoadingPhoto ? "照片读取中" : "正在本机识别餐食候选", systemImage: "hourglass")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else if pendingMealPhotoData != nil {
                        #if canImport(UIKit)
                        if let pendingMealPhotoData {
                            PrivatePendingPhotoPreview(data: pendingMealPhotoData)
                        }
                        #endif
                        Label("照片已在本机暂存，确认记录后才写入私有目录", systemImage: "lock.fill")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button("移除所选照片，仅记录文字") {
                            removePendingMealPhoto()
                        }
                        .font(.footnote.weight(.semibold))
                    } else if existingLog?.localPhotoReference != nil, !removesExistingPhoto {
                        Label("将保留这条记录的现有本机照片", systemImage: "photo.fill")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button("移除现有照片，保留文字记录") {
                            removesExistingPhoto = true
                            discardUnconfirmedPhotoDefaults()
                            photoStatus = "保存修改后将移除这条记录的旧照片。"
                        }
                        .font(.footnote.weight(.semibold))
                    } else if existingLog?.localPhotoReference != nil, removesExistingPhoto {
                        Label("保存后将移除旧照片", systemImage: "photo.badge.minus")
                            .font(.footnote)
                            .foregroundStyle(CoachPalette.recovery)
                        Button("撤回移除照片") {
                            removesExistingPhoto = false
                            photoStatus = "将继续保留原有本机照片。"
                        }
                        .font(.footnote.weight(.semibold))
                    }
                    if let photoSuggestion {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("本机候选品类：\(photoSuggestion.categorySummary)", systemImage: "sparkles")
                                .font(.footnote.weight(.semibold))
                            Text("照片默认宽区间：约 \(photoSuggestion.estimatedCaloriesRange.lowerBound)–\(photoSuggestion.estimatedCaloriesRange.upperBound) kcal。这不能识别克重、烹调油或被遮挡食物，你的文字和菜单信息优先。")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Label(
                                descriptionMatchesPhotoCandidate
                                    ? "候选无误 · 宽范围"
                                    : "按你写的菜名记录 · 照片仅作范围参考",
                                systemImage: descriptionMatchesPhotoCandidate ? "checkmark.circle.fill" : "pencil.circle.fill"
                            )
                                .font(.footnote)
                                .foregroundStyle(descriptionMatchesPhotoCandidate ? CoachPalette.completed : .secondary)
                                .accessibilityHint(
                                    descriptionMatchesPhotoCandidate
                                        ? "这是本机照片候选，不是称重结果；确认后仅保留宽热量范围。"
                                        : "菜名由你修改；照片只保留宽范围，不确认菜品或称重。"
                                )
                            if usesPhotoFastDefaults, hasFoodDescription {
                                Button {
                                    Task { await save() }
                                } label: {
                                    Label("候选无误，记录宽范围", systemImage: "checkmark.circle.fill")
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(CoachPalette.completed)
                                .disabled(saveUnavailableReason != nil)
                                .padding(.top, 4)
                                .accessibilityHint("仅在本机候选与实际食物一致时记录；不会把它当作称重结果，按保守热量范围记录这条额外餐食")
                            }
                        }
                    }
                    if let photoStatus {
                        Text(photoStatus).font(.footnote).foregroundStyle(CoachPalette.recovery)
                    }
                    } label: {
                        Label(
                            photoSectionIsActive ? "本机照片" : "拍照或相册（可选）",
                            systemImage: photoSectionIsActive ? "photo.fill" : "camera"
                        )
                    }
                }
                Section("你吃了什么") {
                    TextField("菜名即可，例如：鸡蛋 2 个", text: $description, axis: .vertical)
                    CountableFoodAmountEntry(
                        description: $description,
                        initialAmount: selectedCountableQuantity
                            ?? MealQuantityNote.actualQuantity(from: description, plannedTitle: ""),
                        onAmountJoined: { amount in
                            selectedCountableQuantity = "实际数量：\(amount)"
                        }
                    )
                }
                Section("份量") {
                    if photoRequiresConservativeRange {
                        Label(
                            photoSuggestion.map { "本机候选含\($0.conservativeRangeSummary)，保留宽区间" }
                                ?? "这条照片记录保留宽区间",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                            .foregroundStyle(CoachPalette.recovery)
                        Text("照片看不出油、糖、夹心和实际份量；不强行套用‘正常一份’。核对菜品后可直接记录，菜单或称重信息再用于修正。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else if usesPhotoFastDefaults {
                        Label("照片候选；份量未确认，保留宽范围", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(CoachPalette.completed)
                        DisclosureGroup("提高照片估算准确度（约 10 秒）", isExpanded: Binding(
                            get: { showsPortionOptions },
                            set: { expanded in
                                showsPortionOptions = expanded
                                if expanded { photoUsesDefaultEstimate = false }
                            }
                        )) {
                            MealCompositionQuickEditor(composition: $composition)
                                .padding(.top, 6)
                        }
                        Text("只有吃得偏少、偏多，或油、甜饮明显不同，才需要调整。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        DisclosureGroup(
                            "份量、油或甜饮（可选）",
                            isExpanded: Binding(
                                get: { composition.hasAnyOwnerSelection || showsTextMealPortionOptions },
                                set: { showsTextMealPortionOptions = $0 }
                            )
                        ) {
                            MealCompositionQuickEditor(composition: $composition)
                                .padding(.top, 6)
                        }
                    }
                    Text(photoUsesDefaultEstimate
                         ? "照片不能看出油和精确份量，当前保留范围。"
                         : composition.isNarrowedByOwner
                         ? "已确认，可以直接使用下方建议记账值。"
                         : MealQuickPortionPreset.matching(composition) != nil
                         ? "份量已选；油和甜饮未知，保留宽范围。"
                         : "不确定时不用填，记录会保留宽范围。")
                        .font(.footnote)
                        .foregroundStyle(photoUsesDefaultEstimate || composition.isNarrowedByOwner ? CoachPalette.completed : .secondary)
                }
                if hasFoodDescription {
                    Section("估算范围") {
                    if let estimatePreview,
                       let calories = estimatePreview.estimatedCaloriesRange {
                        MealEstimateResultCard(
                            calories: calories,
                            composition: estimatePreview.compositionConfirmation,
                            detailOverride: estimatePreview.estimateSource == .onDevicePhotoCandidate
                                ? "照片估算保留宽范围"
                                : nil
                        )
                        if let protein = estimatePreview.estimatedProteinGramsRange {
                            LabeledContent("蛋白质区间", value: "约 \(protein.lowerBound)–\(protein.upperBound) g")
                        }
                        Text(estimatePreview.estimateBasis)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Label(estimatePreview.nextMealGuidance, systemImage: "arrow.forward.circle")
                            .font(.footnote)
                            .foregroundStyle(CoachPalette.completed)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("暂不能生成估算范围；请检查食物名称。")
                            .font(.footnote)
                            .foregroundStyle(CoachPalette.recovery)
                    }
                    DisclosureGroup("有菜单或称重？补充热量范围（可选）", isExpanded: $showsManualEstimateOptions) {
                        HStack(spacing: 8) {
                            TextField("最低", text: $calorieLowerBound)
                                #if os(iOS)
                                .keyboardType(.numberPad)
                                #endif
                                .multilineTextAlignment(.center)
                            Text("–").foregroundStyle(.secondary)
                            TextField("最高", text: $calorieUpperBound)
                                #if os(iOS)
                                .keyboardType(.numberPad)
                                #endif
                                .multilineTextAlignment(.center)
                            Text("kcal").font(.footnote).foregroundStyle(.secondary)
                        }
                        .textFieldStyle(.roundedBorder)
                        WholeServingRangeConfirmation(
                            isConfirmed: $manualRangeConfirmedByOwner,
                            lowerBound: $calorieLowerBound,
                            upperBound: $calorieUpperBound
                        )
                    }
                    .font(.subheadline.weight(.semibold))
                }
                }
                Section {
                    Text("没有餐厅菜单、准确分量和烹调方式时，只能给出宽区间估算；不作为精准热量。")
                        .font(.footnote).foregroundStyle(.secondary)
                    if !openedPlanDayIsCurrent {
                        Label("日期已切换：这张表单不会记录昨天填写的餐食或保存照片。请取消后从今天日卡重新打开。", systemImage: "calendar.badge.exclamationmark")
                            .font(.footnote)
                            .foregroundStyle(CoachPalette.recovery)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if openedPlanDayIsCurrent, let saveUnavailableReason {
                        Label(saveUnavailableReason, systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let saveMessage { Text(saveMessage).font(.footnote).foregroundStyle(CoachPalette.recovery) }
                }
            }
            .coachKeyboardDismissal()
            .navigationTitle(existingLog == nil ? "额外加餐/零食" : "修正额外餐食")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "正在保存…" : (existingLog == nil ? "确认并记录" : "保存修改")) { Task { await save() } }
                        .disabled(saveUnavailableReason != nil)
                }
            }
            #if canImport(UIKit)
            .fullScreenCover(isPresented: $showingMealCamera) {
                PrivateFoodCameraPicker(
                    onImage: { data in
                        acceptCapturedMealPhoto(data)
                        showingMealCamera = false
                    },
                    onCancel: {
                        photoStatus = "未拍摄照片；仍可用文字获得保守区间。"
                        showingMealCamera = false
                    }
                )
                .ignoresSafeArea()
            }
            #endif
            .onAppear { isFormVisible = true }
            .onChange(of: description) { _, newDescription in
                if let selectedCountableQuantity,
                   !MealQuantityNote.isStillPresent(selectedCountableQuantity, in: newDescription) {
                    self.selectedCountableQuantity = nil
                }
            }
            .onDisappear {
                isFormVisible = false
                mealPhotoSelectionGeneration &+= 1
                isLoadingPhoto = false
                isAnalyzingPhoto = false
                pendingMealPhotoData = nil
                pendingMealPhotoOwnerID = nil
                photoSuggestion = nil
            }
        }
        .task(id: Calendar.current.startOfDay(for: date)) {
            while !Task.isCancelled {
                let now = Date()
                guard let nextDay = Calendar.current.nextDate(
                    after: now,
                    matching: DateComponents(hour: 0, minute: 0, second: 0),
                    matchingPolicy: .nextTime
                ) else { return }
                try? await Task.sleep(nanoseconds: UInt64(max(1, nextDay.timeIntervalSince(now)) * 1_000_000_000))
                guard !Task.isCancelled else { return }
                observedNow = Date()
            }
        }
    }

    @MainActor private func save() async {
        guard isFormVisible, hasFoodDescription, !isSaving else { return }
        guard PrivateProfileAsyncOwnershipGate.mayContinue(
            capturedOwnerID: formOwnerID,
            currentOwnerID: privateData.profile.id
        ) else {
            saveMessage = "本机资料已删除或切换；没有保存旧资料的餐食记录或照片。"
            return
        }
        if let error = UnplannedMealLoggingPolicy.validationError(for: date) {
            observedNow = Date()
            saveMessage = error
            return
        }
        if let existingLog,
           !privateData.unplannedMealLogs.contains(where: { $0.id == existingLog.id }) {
            saveMessage = "这条餐食记录已在其他页面被删除或更改；没有重新创建旧记录。请取消后重新打开。"
            return
        }
        // Validate owner-entered ranges before touching the selected photo.  Otherwise an
        // invalid number pair could create a private copy and return from this form before the
        // matching text record exists.  Launch cleanup is a last-resort repair, not the normal
        // lifecycle of a declined/invalid form submission.
        let calorieRange = validRange(lower: calorieLowerBound, upper: calorieUpperBound)
        let proteinRange = validRange(lower: proteinLowerBound, upper: proteinUpperBound)
        let hasCalorieInput = !calorieLowerBound.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !calorieUpperBound.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasProteinInput = !proteinLowerBound.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !proteinUpperBound.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard (!hasCalorieInput || UnplannedMealLog.validatedCaloriesRange(calorieRange) != nil),
              (!hasProteinInput || UnplannedMealLog.validatedProteinRange(proteinRange) != nil) else {
            saveMessage = "请填写合理的完整范围：热量 0–\(UnplannedMealLog.maximumEstimatedCalories) kcal，蛋白 0–\(UnplannedMealLog.maximumEstimatedProteinGrams)g；也可清空后使用保守宽区间。"
            return
        }
        guard (!hasCalorieInput && !hasProteinInput) || manualRangeConfirmedByOwner else {
            saveMessage = "要采用手动范围，请先确认它已覆盖整份的油、甜饮、配料和实际吃掉量；否则清空数字并保留宽区间。"
            return
        }
        isSaving = true
        defer { isSaving = false }
        var createdReference: String?
        var finalReference = removesExistingPhoto ? nil : existingLog?.localPhotoReference
        if let pendingMealPhotoData {
            guard pendingMealPhotoOwnerID == formOwnerID else {
                saveMessage = "照片归属已失效；没有保存记录。请从当前资料重新打开。"
                return
            }
            do {
                let reference = try PrivateMealPhotoStore.forOwner(formOwnerID).save(data: pendingMealPhotoData)
                // Photo decoding can cross midnight. Check again before retaining any private
                // file so a formerly valid sheet cannot leave an orphan while its date is stale.
                if let error = UnplannedMealLoggingPolicy.validationError(for: date) {
                    try? PrivateMealPhotoStore.forOwner(formOwnerID).delete(localReference: reference)
                    observedNow = Date()
                    saveMessage = error
                    return
                }
                createdReference = reference
                finalReference = reference
            } catch {
                selectedPhoto = nil
                saveMessage = "照片未能安全保存到本机；可以先仅用文字记录。"
                return
            }
        }
        // The text-only route has no await, but keep the same final transaction boundary: a
        // date change between the first form check and JSON write must create neither a log nor
        // an unreachable optional photo.
        if let error = UnplannedMealLoggingPolicy.validationError(for: date) {
            if let createdReference {
                try? PrivateMealPhotoStore.forOwner(formOwnerID).delete(localReference: createdReference)
            }
            observedNow = Date()
            saveMessage = error
            return
        }
        guard PrivateProfileAsyncOwnershipGate.mayContinue(
            capturedOwnerID: formOwnerID,
            currentOwnerID: privateData.profile.id
        ) else {
            if let createdReference {
                try? PrivateMealPhotoStore.forOwner(formOwnerID).delete(localReference: createdReference)
            }
            saveMessage = "本机资料已删除或切换；没有保存旧资料的餐食记录或照片。"
            return
        }
        guard let estimate = makeMealEstimate(localPhotoReference: finalReference) else {
            // The food description was validated before the optional photo transaction; keep
            // this boundary explicit so a future UI change cannot create a quantity-only log.
            saveMessage = "数量后请补菜名，例如：鸡蛋 2 个。"
            return
        }
        let log = UnplannedMealLog(
            id: existingLog?.id ?? estimate.id,
            date: date,
            localPhotoReference: finalReference,
            userDescription: estimate.userDescription,
            estimatedCaloriesRange: estimate.estimatedCaloriesRange,
            estimatedProteinGramsRange: estimate.estimatedProteinGramsRange,
            confidence: estimate.confidence,
            estimateSource: estimate.estimateSource,
            isEstimate: true,
            compositionConfirmation: estimate.compositionConfirmation
        )
        var updatedData = privateData
        if let existingIndex = existingLog.flatMap({ existing in
            updatedData.unplannedMealLogs.firstIndex(where: { $0.id == existing.id })
        }) {
            updatedData.unplannedMealLogs[existingIndex] = log
        } else {
            updatedData.unplannedMealLogs.append(log)
        }
        let oldPhotoReferenceToDelete: String? = existingLog?.localPhotoReference.flatMap { previousReference in
            guard previousReference != finalReference,
                  !PrivateMealPhotoReferenceUsage.isReferenced(previousReference, in: updatedData) else { return nil }
            return previousReference
        }
        // A photo is retained only if its matching private meal record reaches disk. This keeps
        // the local-only promise meaningful even when storage becomes temporarily unavailable.
        do {
            try CoachPrivateStorage.saveLastOwnerData(updatedData)
        } catch {
            if let createdReference {
                do {
                    try PrivateMealPhotoStore.forOwner(formOwnerID).delete(localReference: createdReference)
                } catch {
                    saveMessage = "餐食记录未能保存，且照片暂未清理；请勿卸载 App，可稍后从“我的”删除全部本地资料。"
                    return
                }
            }
            saveMessage = "餐食记录暂未保存；请稍后重试。"
            return
        }
        privateData = updatedData
        if let oldPhotoReferenceToDelete {
            try? PrivateMealPhotoStore.forOwner(formOwnerID).delete(localReference: oldPhotoReferenceToDelete)
        }
        dismiss()
    }

    @MainActor private func loadMealPhoto(_ item: PhotosPickerItem, generation: Int, ownerID: UUID) async {
        do {
            guard let sourceData = try await item.loadTransferable(type: Data.self) else {
                guard isFormVisible, generation == mealPhotoSelectionGeneration else { return }
                isLoadingPhoto = false
                selectedPhoto = nil
                photoStatus = "照片未能读取；可以先仅用文字记录。"
                return
            }
            guard isFormVisible,
                  generation == mealPhotoSelectionGeneration,
                  PrivateProfileAsyncOwnershipGate.mayContinue(
                    capturedOwnerID: ownerID,
                    currentOwnerID: privateData.profile.id
                  ) else { return }
            #if canImport(UIKit)
            guard let normalized = PrivateFoodPhotoPreparation.normalizedJPEG(from: sourceData) else {
                isLoadingPhoto = false
                selectedPhoto = nil
                photoStatus = "照片格式暂不支持；可以先仅用文字记录。"
                return
            }
            #else
            let normalized = sourceData
            #endif
            pendingMealPhotoData = normalized
            pendingMealPhotoOwnerID = ownerID
            resetManualRangesForAcceptedNewPhoto()
            isLoadingPhoto = false
            await analyzeMealPhoto(normalized, generation: generation, ownerID: ownerID)
        } catch {
            guard isFormVisible, generation == mealPhotoSelectionGeneration else { return }
            isLoadingPhoto = false
            selectedPhoto = nil
            photoStatus = "照片未能读取；可以先仅用文字记录。"
        }
    }

    private func acceptCapturedMealPhoto(_ data: Data) {
        mealPhotoSelectionGeneration &+= 1
        let generation = mealPhotoSelectionGeneration
        guard PrivateProfileAsyncOwnershipGate.mayContinue(
            capturedOwnerID: formOwnerID,
            currentOwnerID: privateData.profile.id
        ) else {
            pendingMealPhotoData = nil
            pendingMealPhotoOwnerID = nil
            photoSuggestion = nil
            isAnalyzingPhoto = false
            photoStatus = "本机资料已删除或切换；没有保留旧资料的餐食照片。"
            return
        }
        isLoadingPhoto = false
        pendingMealPhotoData = data
        pendingMealPhotoOwnerID = formOwnerID
        discardUnconfirmedPhotoDefaults()
        resetManualRangesForAcceptedNewPhoto()
        removesExistingPhoto = false
        Task { await analyzeMealPhoto(data, generation: generation, ownerID: formOwnerID) }
    }

    @MainActor private func analyzeMealPhoto(_ data: Data, generation: Int, ownerID: UUID) async {
        guard isFormVisible,
              generation == mealPhotoSelectionGeneration,
              pendingMealPhotoOwnerID == ownerID,
              PrivateProfileAsyncOwnershipGate.mayContinue(
                capturedOwnerID: ownerID,
                currentOwnerID: privateData.profile.id
              ) else { return }
        isAnalyzingPhoto = true
        photoStatus = "正在本机识别可能的餐食类别；照片不上传。"
        let suggestion = await PrivateFoodPhotoAnalyzer.analyze(jpegData: data)
        guard isFormVisible,
              generation == mealPhotoSelectionGeneration,
              pendingMealPhotoOwnerID == ownerID,
              PrivateProfileAsyncOwnershipGate.mayContinue(
                capturedOwnerID: ownerID,
                currentOwnerID: privateData.profile.id
              ) else { return }
        isAnalyzingPhoto = false
        photoSuggestion = suggestion
        if let suggestion { applyRecognizedMealSuggestion(suggestion) }
        photoStatus = suggestion == nil
            ? "本机未能识别出可用的餐食候选；请用文字记录，App 将使用保守宽区间。\(manualRangeResetReminder)"
            : "已填入识别候选；份量尚未确认，已保留热量范围。\(manualRangeResetReminder)"
    }

    private func applyRecognizedMealSuggestion(_ suggestion: PrivateFoodPhotoSuggestion) {
        if existingLog == nil || trimmedDescription.isEmpty {
            description = suggestion.provisionalDescription
        }
        if !composition.isNarrowedByOwner {
            composition = MealQuickPortionPreset.regular.composition
            photoUsesDefaultEstimate = true
        }
    }

    private func removePendingMealPhoto() {
        mealPhotoSelectionGeneration &+= 1
        selectedPhoto = nil
        isLoadingPhoto = false
        isAnalyzingPhoto = false
        pendingMealPhotoData = nil
        pendingMealPhotoOwnerID = nil
        discardUnconfirmedPhotoDefaults()
        photoStatus = "已移除所选照片；将只保存文字和保守估算。"
    }

    /// A discarded or replaced photo cannot leave its unconfirmed normal-plate preset behind.
    /// Owner-edited portions have already cleared this marker and are kept for text-only logging.
    private func discardUnconfirmedPhotoDefaults() {
        photoSuggestion = nil
        guard photoUsesDefaultEstimate else { return }
        photoUsesDefaultEstimate = false
        composition = MealCompositionConfirmation()
    }

    private func validRange(lower: String, upper: String) -> ClosedRange<Int>? {
        guard let lower = Int(lower), let upper = Int(upper), lower >= 0, upper >= lower else { return nil }
        return lower...upper
    }
}

private struct TrainingView: View {
    let plan: TodayPlan

    private var card: TrainingCard? {
        TrainingCatalog.card(for: plan.date)
    }

    private var trainingIsPaused: Bool {
        TodayFeature.isTrainingPaused(plan)
    }

    var body: some View {
        List {
            if plan.trainingMode == .recovery {
                Section("恢复版") {
                    Label(trainingIsPaused ? "今天已暂停计划训练" : "今天已切换保护性恢复版", systemImage: "shield.lefthalf.filled")
                        .font(.headline)
                        .foregroundStyle(CoachPalette.recovery)
                    Text(trainingIsPaused
                         ? "原训练、加量和实时取景今天都不执行；以休息为主，本页不会把休息写成训练完成。"
                         : "原训练的标准版、加量和实时取景提示今天不作为执行目标；按恢复说明安排，不补练。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text(plan.trainingInstruction)
                        .fixedSize(horizontal: false, vertical: true)
                    Label("疼痛、头晕、麻木、呼吸异常或症状加重时立即停止，改休息或寻求专业帮助。", systemImage: "hand.raised")
                        .foregroundStyle(CoachPalette.recovery)
                    DisclosureGroup("查看恢复边界") {
                        Label("三餐仍按今天现有餐卡完成，不因恢复日减餐、断食或用运动补偿。", systemImage: "fork.knife")
                        Label("今天不补练、不加量；目标、热量框架和后续周计划保持不变。", systemImage: "lock.fill")
                    }
                    .font(.footnote)
                }
            } else if let card {
                Section {
                    LabeledContent("训练类型", value: card.loadKind.displayName)
                    LabeledContent("最长用时", value: "不超过 \(card.maxMinutes) 分钟")
                    Text(card.loadKind.executionNote)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Text(card.minimumVersion)
                        .fixedSize(horizontal: false, vertical: true)
                } header: {
                    Label("最低完成版", systemImage: "checkmark.circle")
                } footer: {
                    Text("只完成这一版也算今天训练完成；不为追视频进度额外加量。")
                }

                Section {
                    Text(card.regression)
                        .fixedSize(horizontal: false, vertical: true)
                } header: {
                    Label("觉得吃力时", systemImage: "arrow.down.forward")
                }

                Section {
                    Label(card.stopConditions, systemImage: "exclamationmark.shield")
                        .foregroundStyle(CoachPalette.recovery)
                        .fixedSize(horizontal: false, vertical: true)
                } header: {
                    Label("停止条件", systemImage: "hand.raised")
                }

                Section {
                    if card.video.verifiedCandidateURL != nil {
                        Text("今天课程：\(card.video.title ?? "已核验跟练") · \(card.video.durationDisplay ?? "时长待复核")")
                    } else {
                        Text("今天课程需要重新核验；先按文字最低版完成。")
                    }
                    Text("进入完整训练卡可直接打开课程。视频不下载、不缓存；只在室内静态陆上动作时开启本机实时提醒。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Label(card.livePoseSafetyNote, systemImage: "camera.viewfinder")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } header: {
                    Label("跟练与动作提醒", systemImage: "play.rectangle")
                }
            } else {
                Section("今天怎么做") {
                    Text(plan.trainingInstruction)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Section {
                    Label("恢复动作做到舒服即可，不加量、不补练。", systemImage: "shield.lefthalf.filled")
                        .foregroundStyle(CoachPalette.recovery)
                }
            }
        }
        .navigationTitle(plan.trainingMode == .recovery ? "恢复版" : "训练最低版")
    }
}

private struct FlexibleTrainingView: View {
    @Binding var plan: TodayPlan
    @Binding var privateData: PrivateCoachData
    let onPersistImmediately: (PrivateCoachData) -> Bool

    private var todayStatus: HealthStatus? {
        let entries = privateData.datedHealthStatusNotes.filter {
            Calendar.current.isDate($0.date, inSameDayAs: plan.date)
        }
        return HealthStatusHistoryAggregation.dailyAggregates(from: entries).first?.status
    }

    private var completion: DailyCompletion? {
        TodayFeature.completion(for: plan, in: privateData)
    }

    private var recommendation: FlexibleTrainingRecommendation {
        FlexibleTrainingAdvisor.recommendation(
            for: plan,
            status: todayStatus,
            trainingAlreadyCompleted: completion?.trainingOrRecoveryCompleted == true
        )
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("今天灵活训练", systemImage: "slider.horizontal.3")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(CoachPalette.action)
                    Text(recommendation.recommended.title)
                        .font(.title2.weight(.bold))
                    Text(recommendation.reason)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("不超过 20 分钟 · 只在你明确确认后计入今天")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(CoachPalette.completed)
                }
                .padding(.vertical, 4)
            }

            Section("按今天状态选择") {
                ForEach(recommendation.options) { option in
                    NavigationLink {
                        FlexibleTrainingSessionView(
                            option: option,
                            plan: $plan,
                            privateData: $privateData,
                            onPersistImmediately: onPersistImmediately
                        )
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: option.symbol)
                                .font(.title3)
                                .foregroundStyle(option == recommendation.recommended ? CoachPalette.action : .secondary)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(option.title).font(.headline)
                                    if option == recommendation.recommended {
                                        Text("推荐")
                                            .font(.caption2.weight(.bold))
                                            .foregroundStyle(CoachPalette.action)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(CoachPalette.action.opacity(0.12), in: Capsule())
                                    }
                                }
                                Text(option.subtitle)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(option.durationText)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .accessibilityHint("点按查看动作并开始本机计时；不会自动记为完成")
                }
            }

            Section {
                Text("灵活训练只调整今天的执行方式，不会修改目标体重、训练日历、餐卡或后续周结构。疼痛、疾病、用药/医生限制时请停止并遵循专业建议。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .navigationTitle("灵活训练")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .listStyle(.insetGrouped)
        #endif
    }
}

private struct FlexibleTrainingSessionView: View {
    let option: FlexibleTrainingOption
    @Binding var plan: TodayPlan
    @Binding var privateData: PrivateCoachData
    let onPersistImmediately: (PrivateCoachData) -> Bool
    @Environment(\.scenePhase) private var scenePhase
    @State private var startedAt: Date?
    @State private var endedAt: Date?
    @State private var draftID: UUID?
    @State private var message: String?

    private var persistedDraft: FlexibleTrainingDraft? {
        if let draftID {
            return privateData.pendingFlexibleTrainingDrafts.first { $0.id == draftID }
        }
        return privateData.pendingFlexibleTrainingDrafts
            .filter { Calendar.current.isDate($0.date, inSameDayAs: plan.date) && $0.option == option }
            .sorted { $0.endedAt > $1.endedAt }
            .first
    }

    private var elapsedSeconds: TimeInterval {
        guard let startedAt else { return 0 }
        return max(0, (endedAt ?? .now).timeIntervalSince(startedAt))
    }

    private var elapsedLabel: String {
        let seconds = Int(elapsedSeconds.rounded(.down))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private var reachedSuggestedLimit: Bool {
        elapsedSeconds >= 20 * 60
    }

    private var canCountToday: Bool {
        option.canCountAsTraining
            && plan.trainingMode == .standard
            && !TodayFeature.isTrainingPaused(plan)
            && TodayFeature.canComplete(plan)
            && TodayFeature.completion(for: plan, in: privateData)?.trainingOrRecoveryCompleted != true
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Label(option.title, systemImage: option.symbol)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(CoachPalette.action)
                    Text(option.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("建议 \(option.durationText) · 以舒服呼吸和动作质量为准")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("动作提示") {
                ForEach(instructions, id: \.self) { instruction in
                    Label(instruction, systemImage: "checkmark")
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Label("出现疼痛、头晕、胸闷或不适立即停止；需要时寻求专业帮助。", systemImage: "hand.raised.fill")
                    .font(.footnote)
                    .foregroundStyle(CoachPalette.recovery)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("本机计时") {
                if let startedAt {
                    TimelineView(.periodic(from: startedAt, by: 1)) { _ in
                        LabeledContent(endedAt == nil ? "进行中" : "已停止", value: elapsedLabel)
                            .monospacedDigit()
                    }
                    if endedAt == nil {
                        Button("停止计时") { stopAndPersist(reason: "已停止计时，并保存为待确认草稿。") }
                            .buttonStyle(.borderedProminent)
                            .tint(CoachPalette.recovery)
                        if reachedSuggestedLimit {
                            Label("已达建议上限 20 分钟，可以停止；不会自动继续加量。", systemImage: "clock.badge.checkmark")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(CoachPalette.recovery)
                        }
                    }
                } else {
                    Button {
                        startedAt = .now
                        endedAt = nil
                        draftID = UUID()
                        message = nil
                    } label: {
                        Label("开始灵活训练计时", systemImage: "timer")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(CoachPalette.action)
                }

                if endedAt != nil {
                    if canCountToday, let draft = persistedDraft {
                        Button("确认这段训练并记入今天") { confirmDraft(draft) }
                            .buttonStyle(.borderedProminent)
                            .tint(CoachPalette.completed)
                        Button("丢弃这段训练草稿", role: .destructive) { discardDraft(draft) }
                        Text("已保存为本机待确认草稿：\(option.title) · \(draft.durationLabel)。确认后才计入今天；不会写入 Apple 健康。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        if let draft = persistedDraft {
                            Button("丢弃这段训练草稿", role: .destructive) { discardDraft(draft) }
                            Label("这段 \(option.title) 已保存（\(draft.durationLabel)），只作恢复/放松或今日已完成/暂停，不会计入正式训练。", systemImage: "info.circle")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            Label("这项只作恢复/放松，或今天已完成/暂停；不会计入训练完成。", systemImage: "info.circle")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if let message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .navigationTitle(option.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .listStyle(.insetGrouped)
        #endif
        .onAppear(perform: restoreDraftIfNeeded)
        .onChange(of: scenePhase) { _, phase in
            if phase != .active, startedAt != nil {
                stopAndPersist(reason: "App 已离开前台，计时已停止并保存为待确认草稿。")
            }
        }
        .onDisappear {
            if startedAt != nil {
                stopAndPersist(reason: "已离开训练详情，计时已停止并保存为待确认草稿。")
            } else if let draft = persistedDraft {
                persistDraftIfNeeded(draft)
            }
        }
    }

    private var instructions: [String] {
        switch option {
        case .minimum:
            ["2 分钟原地走或关节热身", "4–6 分钟核心/体态最低版，动作慢一点", "最后 1 分钟呼吸放松"]
        case .easyMovement:
            ["选择轻走、舒缓骑行或室内活动", "全程保持可以说完整句子的强度", "结束后做 2 分钟小腿和髋部放松"]
        case .postureReset:
            ["腹式呼吸 5 次，肩颈放松", "臀桥、鸟狗或靠墙站任选 2 个动作", "每个动作以稳定和无痛为先"]
        case .recoveryStretch:
            ["轻柔呼吸与颈肩活动", "髋部、背部和小腿舒展，不追幅度", "今天不补练、不加量，舒服即可"]
        }
    }

    private func restoreDraftIfNeeded() {
        guard startedAt == nil, endedAt == nil, let draft = persistedDraft else { return }
        draftID = draft.id
        startedAt = draft.startedAt
        endedAt = draft.endedAt
        message = "这段计时已恢复；请核对后确认或丢弃。"
    }

    private func stopAndPersist(reason: String) {
        guard let startedAt else { return }
        let endedAt = Date()
        let draft = FlexibleTrainingDraft(id: draftID ?? UUID(), date: plan.date, option: option, startedAt: startedAt, endedAt: endedAt)
        self.startedAt = nil
        self.endedAt = endedAt
        self.draftID = draft.id
        persistDraftIfNeeded(draft)
        message = reason
    }

    private func persistDraftIfNeeded(_ draft: FlexibleTrainingDraft) {
        let updated = FlexibleTrainingLedger.recording(draft, in: privateData)
        guard updated != privateData else { return }
        guard onPersistImmediately(updated) else {
            message = "本机训练草稿暂未保存；请保持此页打开后重试。"
            return
        }
        privateData = updated
    }

    private func confirmDraft(_ draft: FlexibleTrainingDraft) {
        guard canCountToday else { return }
        let updated = FlexibleTrainingLedger.confirming(draft, for: plan, in: privateData)
        guard updated != privateData else {
            message = "这段训练已确认过，今天不会重复计入。"
            return
        }
        guard onPersistImmediately(updated) else {
            message = "训练完成暂未保存；原有记录未改变，请稍后重试。"
            return
        }
        privateData = updated
        message = "已确认 \(draft.option.title)（\(draft.durationLabel)）；今天只计入一次，不会自动增加下一次训练量。"
    }

    private func discardDraft(_ draft: FlexibleTrainingDraft) {
        let updated = FlexibleTrainingLedger.discarding(draft, in: privateData)
        guard onPersistImmediately(updated) else {
            message = "本机训练草稿暂未丢弃；原有记录未改变。"
            return
        }
        privateData = updated
        startedAt = nil
        endedAt = nil
        draftID = nil
        message = "已丢弃这段本机训练草稿；没有删除既有训练记录。"
    }
}

private struct PendingFlexibleTrainingDraftSection: View {
    @Binding var plan: TodayPlan
    @Binding var privateData: PrivateCoachData
    let onPersistImmediately: (PrivateCoachData) -> Bool

    private var drafts: [FlexibleTrainingDraft] {
        privateData.pendingFlexibleTrainingDrafts.sorted { $0.endedAt > $1.endedAt }
    }

    var body: some View {
        if !drafts.isEmpty {
            Section("灵活训练待确认") {
                Text("停止计时或离开页面后，实际时长会先保存在本机。核对后确认才计入今天；恢复拉伸不会算正式训练。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                ForEach(drafts) { draft in
                    NavigationLink {
                        FlexibleTrainingSessionView(
                            option: draft.option,
                            plan: $plan,
                            privateData: $privateData,
                            onPersistImmediately: onPersistImmediately
                        )
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Label("核对灵活训练草稿", systemImage: "clock.badge.checkmark")
                            Text("\(draft.option.title) · \(draft.durationLabel)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Text("\(draft.startedAt.formatted(date: .abbreviated, time: .shortened)) — \(draft.endedAt.formatted(date: .omitted, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityHint("打开后确认或丢弃这段灵活训练，不会重复计入")
                }
            }
        }
    }
}

private struct TrainingHomeView: View {
    @Binding var plan: TodayPlan
    @Binding var privateData: PrivateCoachData
    let onPersistImmediately: (PrivateCoachData) -> Bool

    private var startDateText: String {
        PlanSchedule.startDate()?.formatted(.dateTime.year().month().day()) ?? "计划开始日"
    }

    private var trainingIsPaused: Bool {
        TodayFeature.isTrainingPaused(plan)
    }

    private var goalSummary: String {
        let goal = privateData.profile.primaryGoal?.trimmingCharacters(in: .whitespacesAndNewlines)
        let weight = privateData.profile.targetWeightKg.map { String(format: "目标 %.1f kg", $0) }
        switch (goal?.isEmpty == false ? goal : nil, weight) {
        case let (goal?, weight?): return "\(goal) · \(weight)"
        case let (goal?, nil): return goal
        case let (nil, weight?): return weight
        case (nil, nil): return "还未设置"
        }
    }

    private var trainingTimeSummary: String {
        guard privateData.profile.dailyRoutineSchedule?.trainingMinutes != nil else {
            return "未设置 · 按默认节奏推荐"
        }
        return "\(trainingTimeLabel) · 点按调整"
    }

    private var trainingTimeLabel: String {
        guard let minutes = privateData.profile.dailyRoutineSchedule?.trainingMinutes else {
            return "时间未设"
        }
        return String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    private var trainingHeroContext: String {
        let progress = SustainableGoalProgress.current(data: privateData, date: plan.date)
        return "\(trainingTimeLabel) · \(goalSummary) · \(progress.completedSessions)/\(progress.targetSessions) 次"
    }

    private var sustainableProgress: SustainableGoalProgress {
        SustainableGoalProgress.current(data: privateData, date: plan.date)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch PlanSchedule.phase(for: plan.date) {
                case .preparation:
                    List {
                        ContentUnavailableView("今晚不训练", systemImage: "bed.double", description: Text("第 1 天于 \(startDateText) 开始。现在不需要补练；仅在开始前一晚做食材、饭盒和睡眠准备。"))
                            .listRowBackground(Color.clear)
                        planSettingsSection
                        PendingWorkoutDraftSection(plan: $plan, privateData: $privateData)
                        PendingFlexibleTrainingDraftSection(plan: $plan, privateData: $privateData, onPersistImmediately: onPersistImmediately)
                    }
                case .completed:
                    List {
                        ContentUnavailableView("8 周阶段完成", systemImage: "checkmark.seal", description: Text("先复盘完成率、腰围、睡眠与恢复；确认后才新建下一阶段训练。"))
                            .listRowBackground(Color.clear)
                        planSettingsSection
                        PendingWorkoutDraftSection(plan: $plan, privateData: $privateData)
                        PendingFlexibleTrainingDraftSection(plan: $plan, privateData: $privateData, onPersistImmediately: onPersistImmediately)
                    }
                case .active:
                    List {
                        Section {
                            if plan.trainingMode == .recovery {
                                NavigationLink {
                                    TrainingView(plan: plan)
                                } label: {
                                    TrainingHeroCard(
                                        eyebrow: "今天的安排",
                                        title: trainingIsPaused ? "今天训练已暂停" : "按恢复版完成即可",
                                        detail: trainingIsPaused
                                            ? "以休息为主，不把休息、轻走或呼吸标成训练完成。"
                                            : "不加量、不补练；按身体状态选择轻走、呼吸或休息。",
                                        context: trainingHeroContext,
                                        action: "查看恢复安排",
                                        symbol: trainingIsPaused ? "pause.fill" : "figure.walk",
                                        color: CoachPalette.recovery
                                    )
                                }
                                .buttonStyle(.plain)
                            } else if let card = TrainingCatalog.card(for: plan.date) {
                                NavigationLink {
                                    TrainingCardDetail(card: card, plan: $plan, privateData: $privateData)
                                } label: {
                                    TrainingHeroCard(
                                        eyebrow: "第\(card.dayIndex)天 · 今日训练",
                                        title: card.title,
                                        detail: card.video.durationDisplay ?? "按自己的节奏完成；只记录真实开始到停止的时长。",
                                        context: trainingHeroContext,
                                        action: card.video.verifiedCandidateURL == nil ? "查看训练" : "开始跟练",
                                        symbol: "play.fill",
                                        color: CoachPalette.action
                                    )
                                }
                                .buttonStyle(.plain)
                                .accessibilityHint("点按进入训练；确认安全设置后才会开始真实计时")
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 12, trailing: 0))
                        .listRowBackground(Color.clear)
                        Section("本周节奏") {
                            VStack(alignment: .leading, spacing: 5) {
                                Label(sustainableProgress.sessionSummary, systemImage: sustainableProgress.completedSessions >= sustainableProgress.targetSessions ? "checkmark.seal.fill" : "target")
                                    .font(.headline)
                                    .foregroundStyle(sustainableProgress.completedSessions >= sustainableProgress.targetSessions ? CoachPalette.completed : CoachPalette.action)
                                Text(sustainableProgress.detail)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                Text("按已确认的标准/灵活训练计算；恢复拉伸不计入。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .accessibilityElement(children: .combine)
                        }
                        planSettingsSection
                        PendingWorkoutDraftSection(plan: $plan, privateData: $privateData)
                        PendingFlexibleTrainingDraftSection(plan: $plan, privateData: $privateData, onPersistImmediately: onPersistImmediately)
                        Section("计划与记录") {
                            NavigationLink("查看 8 周训练日历") {
                                TrainingLibraryView(plan: $plan, privateData: $privateData)
                            }
                        }
                    }
                }
            }
            .navigationTitle("跟练")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            .listStyle(.insetGrouped)
            #endif
        }
    }

    /// Goal and training-time controls stay visible even on the preparation/completed states.
    /// Previously those states only showed “restart”, making the editable plan feel locked.
    @ViewBuilder
    private var planSettingsSection: some View {
        Section("计划设置") {
            NavigationLink {
                PlanStartDateSettingsView(
                    privateData: $privateData,
                    onPersistImmediately: onPersistImmediately
                )
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Label("计划开始日", systemImage: "calendar.badge.clock")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(CoachPalette.action)
                    Text(PlanSchedule.startDate()?.formatted(.dateTime.year().month().day()) ?? "未设置")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                }
                .padding(.vertical, 3)
            }
            .accessibilityHint("点按选择今天或未来的计划开始日；历史记录不会删除或迁移")
            NavigationLink {
                FlexibleTrainingView(
                    plan: $plan,
                    privateData: $privateData,
                    onPersistImmediately: onPersistImmediately
                )
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Label("今日灵活训练", systemImage: "slider.horizontal.3")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(CoachPalette.action)
                    Text("按状态选最低版、轻松活动或恢复动作")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                }
                .padding(.vertical, 3)
            }
            .accessibilityHint("点按选择今天的灵活训练方式；不会自动调整后续计划")
            NavigationLink {
                GoalSettingsView(
                    privateData: $privateData,
                    onPersistImmediately: onPersistImmediately
                )
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Label("调整目标与体重", systemImage: "scope")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(CoachPalette.action)
                    Text(goalSummary)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                }
                .padding(.vertical, 3)
            }
            .accessibilityHint("点按调整目标和目标体重；不会改变当前训练或餐食计划")
            NavigationLink {
                RoutineSettingsView(
                    privateData: $privateData,
                    onPersistImmediately: { onPersistImmediately(privateData) }
                )
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Label("调整训练时间", systemImage: "clock")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(CoachPalette.action)
                    Text(trainingTimeSummary)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                }
                .padding(.vertical, 3)
            }
            .accessibilityHint("点按设置训练时间与本机提醒；不会调整训练日历")
        }
    }
}

/// The training home deliberately has one large destination. A person can recognise today's
/// course, its approximate length, and the next tap without scanning settings-style rows.
private struct TrainingHeroCard: View {
    let eyebrow: String
    let title: String
    let detail: String
    let context: String?
    let action: String
    let symbol: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label(eyebrow, systemImage: symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.84))
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.76))
            }
            VStack(alignment: .leading, spacing: 7) {
                Text(title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(2)
                if let context {
                    Text(context)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.78))
                        .lineLimit(2)
                }
            }
            HStack(spacing: 8) {
                Text(action)
                    .font(.headline)
                Image(systemName: "play.fill")
                    .font(.caption.weight(.bold))
            }
            .foregroundStyle(color)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(.white, in: Capsule())
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// A stopped, real interval remains an owner decision even when the normal plan page has rolled
/// over to preparation or programme-completion state. Surface the exact draft in every phase so
/// the person can still explicitly review or discard it; the detail's same-day gate keeps
/// all old training actions (new timer, feedback, Bilibili, and camera) read-only.
private struct PendingWorkoutDraftSection: View {
    @Binding var plan: TodayPlan
    @Binding var privateData: PrivateCoachData

    private var drafts: [PendingWorkoutConfirmation] {
        privateData.pendingWorkoutConfirmations.sorted { $0.savedAt > $1.savedAt }
    }

    var body: some View {
        if !drafts.isEmpty {
            Section("实际训练待本人确认") {
                Text("这些停止计时的本机草稿不会写入 Apple 健康。请核对实际时长和类型后，主动决定保留或丢弃；跨日草稿不会重新开放旧日训练，阶段完成后同样仍可核对。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                ForEach(drafts) { draft in
                    if let card = TrainingCatalog.all56.first(where: { $0.dayIndex == draft.workout.dayIndex }) {
                        NavigationLink {
                            // A person may deliberately have more than one stopped interval for
                            // one day. Open this exact draft instead of substituting the newest.
                            TrainingCardDetail(
                                card: card,
                                plan: $plan,
                                privateData: $privateData,
                                initialWorkoutConfirmationID: draft.id
                            )
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Label("核对本机训练草稿", systemImage: "checkmark.circle")
                                Text("第\(draft.workout.dayIndex)天 · \(draft.workout.kind.displayName) · \(draft.workout.displayDuration)")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                // The duration alone is not enough to distinguish two real
                                // intervals from one day. Keep the actual start and end on the
                                // list row as well, so the owner can select the correct draft
                                // before opening its per-session sync/discard controls.
                                Text("实际：\(draft.workout.startedAt.formatted(date: .abbreviated, time: .shortened)) — \(draft.workout.endedAt.formatted(date: draft.workout.crossesCalendarDay() ? .abbreviated : .omitted, time: .shortened))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    } else {
                        // Damaged/imported data must not disappear behind a silent filter. It is
                        // deliberately not deleted here: no available card means the owner must
                        // first recover the local record rather than the App guessing a session.
                        Label("一条本机训练草稿无法对应计划日；未写入 Apple 健康，也未自动删除。", systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(CoachPalette.recovery)
                    }
                }
            }
        }
    }
}

/// 食谱库同样按真实日期进入只读日卡，避免在“吃什么”首页连续堆出 56 天长文本。
private struct FoodLibraryView: View {
    @Binding var plan: TodayPlan
    @Binding var privateData: PrivateCoachData
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var calendarColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 0), spacing: 6), count: 7)
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                accessibleDayList
            } else {
                calendarGrid
            }
        }
        .navigationTitle("8 周饮食日历")
    }

    private var calendarGrid: some View {
        ScrollView {
            LazyVGrid(columns: calendarColumns, spacing: 6) {
                ForEach(["六", "日", "一", "二", "三", "四", "五"], id: \.self) { weekday in
                    Text(weekday)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel("星期\(weekday)")
                }

                ForEach(0..<8, id: \.self) { weekOffset in
                    Text(weekLabel(for: weekOffset))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .gridCellColumns(7)
                        .padding(.top, weekOffset == 0 ? 2 : 8)

                    ForEach(dayIndexes(inWeek: weekOffset), id: \.self) { dayIndex in
                        calendarCell(for: dayIndex)
                    }
                }
            }
            .padding()

            VStack(alignment: .leading, spacing: 6) {
                Text("颜色说明").font(.headline)
                Text("盾牌：恢复｜勾：训练与睡前准备完成｜半圆：部分完成｜箭头：明确跳过｜问号：过去未记录｜实心圆：今天｜空心圆：未来待执行。图标、文字与低饱和色共同表达状态。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
        }
    }

    private var accessibleDayList: some View {
        List {
            Section {
                Text("已切换为放大字体列表。每一行都是一天的日卡，状态不只靠颜色表达。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(0..<8, id: \.self) { weekOffset in
                Section(weekLabel(for: weekOffset)) {
                    ForEach(dayIndexes(inWeek: weekOffset), id: \.self) { dayIndex in
                        accessibleDayRow(for: dayIndex)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func calendarCell(for dayIndex: Int) -> some View {
        let status = calendarStatus(for: dayIndex)
        NavigationLink {
            DailyPlanCardView(dayIndex: dayIndex, privateData: $privateData)
        } label: {
            VStack(spacing: 3) {
                Text(String(Calendar.current.component(.day, from: date(for: dayIndex))))
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Image(systemName: status.symbolName)
                    .font(.caption2.weight(.bold))
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: dynamicTypeSize.isAccessibilitySize ? 58 : 48)
            .foregroundStyle(status.foregroundColor)
            .background(status.backgroundColor, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(status.highlightsToday ? CoachPalette.action : .clear, lineWidth: 2)
                    .allowsHitTesting(false)
            }
        }
        .accessibilityLabel("第\(dayIndex)天，\(fullDateLabel(for: dayIndex))，\(status.label)；点按查看当天三餐日卡")
        .accessibilityHint("点按查看当天完整日卡")
    }

    private func accessibleDayRow(for dayIndex: Int) -> some View {
        let status = calendarStatus(for: dayIndex)
        return NavigationLink {
            DailyPlanCardView(dayIndex: dayIndex, privateData: $privateData)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: status.symbolName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(status.foregroundColor)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text("第\(dayIndex)天 · \(fullDateLabel(for: dayIndex))")
                        .font(.headline)
                    Text(status.label)
                        .font(.subheadline)
                        .foregroundStyle(status.foregroundColor)
                }
            }
            .padding(.vertical, 3)
        }
        .accessibilityLabel("第\(dayIndex)天，\(fullDateLabel(for: dayIndex))，\(status.label)；点按查看当天三餐日卡")
    }

    private func dayIndexes(inWeek weekOffset: Int) -> ClosedRange<Int> {
        let start = weekOffset * 7 + 1
        return start...(start + 6)
    }

    private func calendarStatus(for dayIndex: Int) -> CalendarDayStatus {
        CalendarDayStatus.resolve(for: date(for: dayIndex), data: privateData)
    }

    private func date(for dayIndex: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: dayIndex - 1, to: PlanSchedule.startDate() ?? .now) ?? .now
    }

    private func weekLabel(for weekOffset: Int) -> String {
        let firstDay = date(for: weekOffset * 7 + 1)
        let lastDay = date(for: weekOffset * 7 + 7)
        return "第\(weekOffset + 1)周 · \(firstDay.formatted(.dateTime.month().day()))–\(lastDay.formatted(.dateTime.month().day()))"
    }

    private func fullDateLabel(for dayIndex: Int) -> String {
        date(for: dayIndex).formatted(.dateTime.year().month().day().weekday())
    }
}

private struct TrainingLibraryView: View {
    @Binding var plan: TodayPlan
    @Binding var privateData: PrivateCoachData
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showingGoalSettings = false
    @State private var showingRoutineSettings = false

    private let weekdayLabels = ["六", "日", "一", "二", "三", "四", "五"]

    private var calendarColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 0), spacing: 6), count: 7)
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                accessibleDayList
            } else {
                calendarGrid
            }
        }
        .navigationTitle("8 周训练日历")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Menu {
                    Button("调整训练时间", systemImage: "clock") {
                        showingRoutineSettings = true
                    }
                    Button("调整目标", systemImage: "scope") {
                        showingGoalSettings = true
                    }
                } label: {
                    Label("调整", systemImage: "slider.horizontal.3")
                }
                .accessibilityLabel("调整训练日历的时间和目标")
            }
        }
        .sheet(isPresented: $showingRoutineSettings) {
            NavigationStack {
                RoutineSettingsView(
                    privateData: $privateData,
                    onPersistImmediately: persistCurrentPrivateData
                )
            }
        }
        .sheet(isPresented: $showingGoalSettings) {
            NavigationStack {
                GoalSettingsView(
                    privateData: $privateData,
                    onPersistImmediately: persist
                )
            }
        }
    }

    private var calendarGrid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                calendarOverviewCard
                LazyVGrid(columns: calendarColumns, spacing: 6) {
                ForEach(weekdayLabels, id: \.self) { weekday in
                    Text(weekday)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel("星期\(weekday)")
                }

                ForEach(0..<8, id: \.self) { weekOffset in
                    Text(weekLabel(for: weekOffset))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .gridCellColumns(7)
                        .padding(.top, weekOffset == 0 ? 2 : 8)

                    ForEach(cards(inWeek: weekOffset)) { card in
                        calendarCell(for: card)
                    }
                }
                }
            }
            .padding()
            DisclosureGroup("查看状态说明") {
                Text("盾牌：恢复｜勾：三项完成｜半圆：部分完成｜箭头：明确跳过｜问号：过去未记录｜实心圆：今天｜空心圆：未来待执行。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
        }
    }

    private var calendarOverviewCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar.badge.clock")
                .font(.title2.weight(.semibold))
                .foregroundStyle(CoachPalette.action)
                .frame(width: 48, height: 48)
                .background(CoachPalette.action.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text("训练安排")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CoachPalette.action)
                Text(TrainingCatalog.card(for: plan.date)?.title ?? "按今日安排")
                    .font(.headline)
                    .lineLimit(1)
                Text("\(trainingTimeText) · \(privateData.profile.primaryGoal ?? "目标未设置")")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(CoachPalette.action.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("训练安排，\(TrainingCatalog.card(for: plan.date)?.title ?? "按今日安排")，\(trainingTimeText)，\(privateData.profile.primaryGoal ?? "目标未设置")")
    }

    private var trainingTimeText: String {
        guard let minutes = privateData.profile.dailyRoutineSchedule?.trainingMinutes else { return "训练时间未设" }
        return String(format: "%02d:%02d 训练", minutes / 60, minutes % 60)
    }

    private var accessibleDayList: some View {
        List {
            Section {
                Text("已切换为放大字体列表。每一行保留训练名称与完成状态，点按查看当天完整日卡。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(0..<8, id: \.self) { weekOffset in
                Section(weekLabel(for: weekOffset)) {
                    ForEach(cards(inWeek: weekOffset)) { card in
                        accessibleDayRow(for: card)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func calendarCell(for card: TrainingCard) -> some View {
        let status = calendarStatus(for: card.dayIndex)
        NavigationLink {
            DailyPlanCardView(dayIndex: card.dayIndex, privateData: $privateData)
        } label: {
            VStack(spacing: 3) {
                // 单个日期数在 320pt 和放大字体下仍有空间；完整日期由周标题和辅助功能标签提供。
                Text(String(Calendar.current.component(.day, from: date(for: card.dayIndex))))
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Image(systemName: status.symbolName)
                    .font(.caption2.weight(.bold))
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: dynamicTypeSize.isAccessibilitySize ? 58 : 48)
            .foregroundStyle(status.foregroundColor)
            .background(status.backgroundColor, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(status.highlightsToday ? CoachPalette.action : .clear, lineWidth: 2)
                    .allowsHitTesting(false)
            }
        }
        .accessibilityLabel("第\(card.dayIndex)天，\(fullDateLabel(for: card.dayIndex))，\(status.label)，\(card.title)")
        .accessibilityHint("点按查看当天完整日卡")
    }

    private func accessibleDayRow(for card: TrainingCard) -> some View {
        let status = calendarStatus(for: card.dayIndex)
        return NavigationLink {
            DailyPlanCardView(dayIndex: card.dayIndex, privateData: $privateData)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: status.symbolName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(status.foregroundColor)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text("第\(card.dayIndex)天 · \(card.title)")
                        .font(.headline)
                    Text("\(fullDateLabel(for: card.dayIndex)) · \(status.label)")
                        .font(.subheadline)
                        .foregroundStyle(status.foregroundColor)
                }
            }
            .padding(.vertical, 3)
        }
        .accessibilityLabel("第\(card.dayIndex)天，\(fullDateLabel(for: card.dayIndex))，\(status.label)，\(card.title)；点按查看当天完整日卡")
    }

    private func cards(inWeek weekOffset: Int) -> ArraySlice<TrainingCard> {
        let start = weekOffset * 7
        return TrainingCatalog.all56[start..<(start + 7)]
    }

    private func calendarStatus(for dayIndex: Int) -> CalendarDayStatus {
        CalendarDayStatus.resolve(for: date(for: dayIndex), data: privateData)
    }

    private func date(for dayIndex: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: dayIndex - 1, to: PlanSchedule.startDate() ?? .now) ?? .now
    }

    private func weekLabel(for weekOffset: Int) -> String {
        let firstDay = date(for: weekOffset * 7 + 1)
        let lastDay = date(for: weekOffset * 7 + 7)
        return "第\(weekOffset + 1)周 · \(firstDay.formatted(.dateTime.month().day()))–\(lastDay.formatted(.dateTime.month().day()))"
    }

    private func fullDateLabel(for dayIndex: Int) -> String {
        date(for: dayIndex).formatted(.dateTime.year().month().day().weekday())
    }

    private func persistCurrentPrivateData() -> Bool {
        persist(privateData)
    }

    private func persist(_ data: PrivateCoachData) -> Bool {
        do {
            try CoachPrivateStorage.saveLastOwnerData(data)
            return true
        } catch {
            return false
        }
    }
}

/// 日历日卡完整呈现选中日期的三餐、训练和睡前交接。仅当天正式计划日可打卡；历史/未来严格只读。
private struct DailyPlanCardView: View {
    let dayIndex: Int
    @Binding var privateData: PrivateCoachData
    @State private var showingMealSubstitution = false
    @State private var showingHealthStatus = false
    @State private var editablePlan: TodayPlan?
    @State private var completionStatus: String?

    private var scheduledPlan: TodayPlan? {
        guard let start = PlanSchedule.startDate(),
              let date = Calendar.current.date(byAdding: .day, value: dayIndex - 1, to: start),
              let basePlan = PlanSchedule.makePlan(for: date) else { return nil }
        let substituted = MealSubstitutionService.appliedPlan(for: basePlan, in: privateData)
        return HealthCheckInService.replayedPlan(for: date, plan: substituted, data: privateData)
    }

    private var canCheckIn: Bool {
        guard let scheduledPlan else { return false }
        return TodayFeature.canComplete(scheduledPlan)
    }

    private var savedCompletion: DailyCompletion? {
        guard let scheduledPlan else { return nil }
        return TodayFeature.completion(for: scheduledPlan, in: privateData)
    }

    private var savedHealthSummary: DailyHealthStatusSummary? {
        guard let scheduledPlan else { return nil }
        return HealthCheckInService.summary(for: scheduledPlan.date, in: privateData)
    }

    private var skipButtonTitle: String {
        guard let scheduledPlan else { return "今天不执行：标记为跳过" }
        return TodayFeature.completion(for: scheduledPlan, in: privateData)?.isSkipped == true
            ? "撤回今天的跳过"
            : "今天不执行：标记为跳过"
    }

    var body: some View {
        Group {
            if let scheduledPlan {
                List {
                    Section {
                        Text("第\(dayIndex)天 · \(scheduledPlan.date.formatted(.dateTime.year().month().day().weekday()))")
                            .font(.headline)
                        Text(canCheckIn ? "今天的日卡：完成训练与睡前准备；食材替换和身体状态仍从“今天”进入。" : "这是只读计划预览；历史与未来日期不能写入打卡或替换。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if !canCheckIn, scheduledPlan.date < Calendar.current.startOfDay(for: .now) {
                        Section("当天完成情况") {
                            if let savedCompletion {
                                Label(savedCompletion.trainingOrRecoveryCompleted ? "训练/恢复已完成" : "训练/恢复未记录", systemImage: savedCompletion.trainingOrRecoveryCompleted ? "checkmark.circle.fill" : "circle")
                                Label(savedCompletion.bedtimePreparationCompleted ? "睡前准备已完成" : "睡前准备未记录", systemImage: savedCompletion.bedtimePreparationCompleted ? "checkmark.circle.fill" : "circle")
                                if savedCompletion.isSkipped {
                                    Label("当天明确标记为跳过", systemImage: "forward.fill")
                                        .foregroundStyle(CoachPalette.skipped)
                                }
                            } else {
                                Text("当天没有保存完成或跳过记录。")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    if let savedHealthSummary {
                        Section("当天真实记录") {
                            VStack(alignment: .leading, spacing: 4) {
                                Label(savedHealthSummary.hasProtectiveSignal ? "身体状态 · 已采用保护性恢复" : "身体状态", systemImage: savedHealthSummary.hasProtectiveSignal ? "shield.lefthalf.filled" : "heart.text.square")
                                    .font(.subheadline.weight(.semibold))
                                Text(savedHealthSummary.labels.joined(separator: " · "))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    if canCheckIn {
                        Section("今天行动") {
                            let completion = TodayFeature.completion(for: scheduledPlan, in: privateData)
                            ForEach(TodayFeature.actions(plan: scheduledPlan, completion: completion).filter { $0.id != .eat }) { action in
                                let actionLabel = action.title + "：" + action.detail
                                let actionHint = action.isCompleted ? "点按取消今天这项完成状态" : "点按标记今天这项已完成"
                                if action.id == .move, TodayFeature.isTrainingPaused(scheduledPlan), !action.isCompleted {
                                    TodayActionRow(action: action)
                                        .accessibilityLabel(actionLabel)
                                        .accessibilityHint("今天暂停计划训练；不能标记为训练或恢复完成")
                                } else {
                                    Button {
                                        completeAction(action, for: scheduledPlan)
                                    } label: {
                                        TodayActionRow(action: action)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(actionLabel)
                                    .accessibilityHint(actionHint)
                                }
                            }
                        }
                        Section("今天的决定") {
                            let isSkipped = TodayFeature.completion(for: scheduledPlan, in: privateData)?.isSkipped == true
                            Button(skipButtonTitle) {
                                toggleSkip(for: scheduledPlan)
                            }
                            .tint(isSkipped ? CoachPalette.action : CoachPalette.skipped)
                            Text(isSkipped
                                 ? "已明确标记今天跳过；点按可撤回。重新完成任一项也会自动撤回跳过。"
                                 : "仅标记今天整张日卡不执行；不会删掉已有完成记录，也不会自动补练、节食或改后续目标。")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            if let completionStatus {
                                Text(completionStatus)
                                    .font(.footnote)
                                    .foregroundStyle(CoachPalette.recovery)
                            }
                        }
                        Section("今天临时变化") {
                            Button("食材不匹配：确认重排一餐") { showingMealSubstitution = true }
                            Button("记录今天身体状态") { showingHealthStatus = true }
                            Text("餐卡重排需你确认；餐食记录与热量预估已关闭。身体状态只在需要时触发保护性恢复。")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Section("早餐") { MealCardSummary(meal: scheduledPlan.breakfast, profileKitchenSetup: privateData.profile.kitchenSetup) }
                    Section("午餐") { MealCardSummary(meal: scheduledPlan.lunch, profileKitchenSetup: privateData.profile.kitchenSetup) }
                    Section("晚餐") { MealCardSummary(meal: scheduledPlan.dinner, profileKitchenSetup: privateData.profile.kitchenSetup) }
                    Section(scheduledPlan.trainingMode == .recovery ? "恢复训练" : "训练最低版") {
                        Text(scheduledPlan.trainingInstruction)
                    }
                    Section("睡前准备") {
                        ForEach(scheduledPlan.bedtimePreparation, id: \.self) { Text("• \($0)") }
                    }
                }
            } else {
                ContentUnavailableView("当天计划不可用", systemImage: "calendar.badge.exclamationmark")
            }
        }
        .navigationTitle("每日计划")
        .onAppear { editablePlan = scheduledPlan }
        // `editablePlan` exists only because the confirmation sheets need a writable binding.
        // The actual source of truth is `privateData`: a meal substitution or a protection-mode
        // health check-in can be committed from this calendar page, from Today, or from Food.
        // Rebuild this temporary binding after every committed private-data change so opening a
        // second sheet cannot submit a stale pre-substitution/pre-recovery card.
        .onChange(of: privateData) { _, _ in
            editablePlan = scheduledPlan
        }
        .sheet(isPresented: $showingMealSubstitution) {
            if let binding = Binding($editablePlan) {
                MealSubstitutionForm(planDate: binding.wrappedValue.date, plan: binding, privateData: $privateData)
            }
        }
        .sheet(isPresented: $showingHealthStatus) {
            if let binding = Binding($editablePlan) {
                HealthStatusForm(planDate: binding.wrappedValue.date, isFormalPlanDay: true, ownerID: privateData.profile.id) { status, submissionID, formOwnerID in
                    let result = HealthCheckInService.submit(status, submissionID: submissionID, formOwnerID: formOwnerID, at: .now, plan: binding.wrappedValue, data: privateData)
                    if let error = result.validationError { return error }
                    do {
                        try CoachPrivateStorage.saveLastOwnerData(result.data)
                    } catch {
                        return "状态暂未保存；今天的训练与餐卡没有改变。请勿删除 App，确认设备存储可用后重试。"
                    }
                    binding.wrappedValue = result.plan
                    privateData = result.data
                    showingHealthStatus = false
                    return nil
                }
            }
        }
    }

    private func completeAction(_ action: TodayAction, for scheduledPlan: TodayPlan) {
        let updatedData = TodayFeature.completing(action.id, for: scheduledPlan, in: privateData)
        commitCompletion(updatedData, failure: "这项完成状态暂未保存；今天日卡没有改变。")
    }

    private func toggleSkip(for scheduledPlan: TodayPlan) {
        let updatedData = DailySkipService.toggle(for: scheduledPlan, in: privateData)
        commitCompletion(updatedData, failure: "跳过状态暂未保存；今天日卡没有改变。")
    }

    private func commitCompletion(_ updatedData: PrivateCoachData, failure: String) {
        do {
            try CoachPrivateStorage.saveLastOwnerData(updatedData)
        } catch {
            completionStatus = failure
            return
        }
        privateData = updatedData
        completionStatus = nil
    }
}

private struct MealCardSummary: View {
    let meal: MealCard
    let profileKitchenSetup: String?

    init(meal: MealCard, profileKitchenSetup: String? = nil) {
        self.meal = meal
        self.profileKitchenSetup = profileKitchenSetup
    }

    var body: some View {
        NavigationLink(meal.displayTitle) {
            MealCardView(meal: meal, profileKitchenSetup: profileKitchenSetup)
        }
        Text(meal.ingredients.joined(separator: " · "))
            .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        if let firstExecutionStep = meal.firstExecutionStep {
            Text("现在：\(firstExecutionStep)")
                .font(.footnote).foregroundStyle(CoachPalette.action).fixedSize(horizontal: false, vertical: true)
        }
        Text(meal.totalOperationText ?? "总操作待确认")
            .font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
        Text(meal.portionsAndStorage)
            .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}

private struct TrainingCardDetail: View {
    let card: TrainingCard
    @Binding var plan: TodayPlan
    @Binding var privateData: PrivateCoachData
    @State private var effort = 5
    @State private var pain = 0
    @State private var sleepHours = ""
    /// Completion is never preselected: a feedback note about pain, an early stop, or a timer
    /// review must not accidentally turn into a claim that today's training was completed.
    @State private var completed = false
    /// Stable for the current tap/retry only. It prevents an accidental double tap from becoming
    /// two private feedback records; after a successful save a new deliberate feedback gets a new ID.
    @State private var feedbackSubmissionID = UUID()
    @State private var adaptationMessage: String?
    @State private var showingLocalPoseCoach = false
    @State private var showingBilibiliLiveFollowAlong = false
    @State private var confirmingSynchronizedFollowAlong = false
    @State private var workoutStartedAt: Date?
    @State private var completedWorkout: ConfirmedHealthWorkout?
    /// The pending-draft UUID is a stronger UI selection key than the HealthKit retry
    /// identifier.  Normal flows generate a fresh retry identifier for every stop, but an
    /// imported/damaged private file can contain two drafts that reuse one identifier.  When a
    /// person opens one row from “实际训练待本人确认”, every displayed action must stay attached
    /// to that exact local draft rather than silently selecting its sibling.
    @State private var selectedWorkoutConfirmationID: UUID?
    @State private var workoutSessionID = UUID()
    @State private var workoutKind: ConfirmedHealthWorkoutKind
    @State private var healthSyncStatus: String?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    init(
        card: TrainingCard,
        plan: Binding<TodayPlan>,
        privateData: Binding<PrivateCoachData>,
        initialWorkoutConfirmationID: UUID? = nil
    ) {
        self.card = card
        _plan = plan
        _privateData = privateData
        // A stopped session remains an explicit local decision until its owner writes it or
        // discards it. Reopening today's matching training card restores only that exact
        // user-timed interval for review; it never calls HealthKit on its own.
        let savedConfirmation = privateData.wrappedValue.pendingWorkoutConfirmations
            .filter {
                if let initialWorkoutConfirmationID {
                    return $0.id == initialWorkoutConfirmationID
                }
                return $0.workout.dayIndex == card.dayIndex
            }
            .sorted { $0.savedAt > $1.savedAt }
            .first
        _completedWorkout = State(initialValue: savedConfirmation?.workout)
        _selectedWorkoutConfirmationID = State(initialValue: savedConfirmation?.id)
        _workoutSessionID = State(initialValue: savedConfirmation?.workout.syncIdentifier ?? UUID())
        _workoutKind = State(initialValue: savedConfirmation?.workout.kind ?? card.suggestedHealthWorkoutKind)
    }

    private var elapsedSeconds: TimeInterval {
        guard let workoutStartedAt else { return 0 }
        return max(0, Date().timeIntervalSince(workoutStartedAt))
    }

    private var workoutDurationLabel: String {
        let seconds = Int(elapsedSeconds.rounded(.down))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private var currentWorkoutConfirmation: PendingWorkoutConfirmation? {
        if let selectedWorkoutConfirmationID {
            return privateData.pendingWorkoutConfirmations.first {
                $0.id == selectedWorkoutConfirmationID
            }
        }
        return privateData.pendingWorkoutConfirmations.first {
            $0.workout.syncIdentifier == workoutSessionID
        }
    }

    private var canSaveFeedback: Bool {
        cardMatchesCurrentPlanDay && TrainingFeedbackService.canSubmit(for: plan)
    }

    private var trainingIsPausedForMedicalRecovery: Bool {
        plan.trainingMode == .recovery
            && plan.trainingInstruction.contains("暂停计划训练")
    }

    private var cardMatchesCurrentPlanDay: Bool {
        // An already-open detail can outlive midnight. Matching the card's index to a newly
        // bound plan is not enough: it must also be today's formal card before it may launch a
        // new external lesson, local camera session, timer, or feedback submission.
        Calendar.current.isDate(plan.date, inSameDayAs: .now)
            && PlanSchedule.dayIndex(for: plan.date) == card.dayIndex
    }

    private var canStartWorkoutTimer: Bool {
        cardMatchesCurrentPlanDay && TodayFeature.canComplete(plan) && plan.trainingMode == .standard
    }

    private var workoutTimerUnavailableReason: String? {
        if completedWorkout != nil {
            return "本次计时已停止；请回训练详情核对或丢弃草稿后再开始。"
        }
        if plan.trainingMode == .recovery {
            return "今天已切换恢复版，原标准训练不能开始新计时。"
        }
        if !cardMatchesCurrentPlanDay {
            return "这不是今天可执行的训练卡，不能开始新计时。"
        }
        if !TodayFeature.canComplete(plan) {
            return "当前不是正式计划执行日，不能开始新计时。"
        }
        return nil
    }

    #if canImport(UIKit) && canImport(Vision) && canImport(AVFoundation)
    private var supportsIPhoneLivePose: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }
    #endif

    private var trainingChoiceSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                Text("今天的训练")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isReadyToStartFollowAlong ? .white.opacity(0.84) : CoachPalette.action)
                Text(card.title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(isReadyToStartFollowAlong ? .white : .primary)
                Text(card.video.durationDisplay ?? "按自己的节奏完成")
                    .font(.subheadline)
                    .foregroundStyle(isReadyToStartFollowAlong ? .white.opacity(0.80) : .secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if isReadyToStartFollowAlong {
                    Divider()
                        .overlay(.white.opacity(0.22))
                }
            if workoutStartedAt == nil, completedWorkout == nil {
                if let candidateURL = card.video.verifiedCandidateURL {
                    #if canImport(UIKit) && canImport(Vision) && canImport(AVFoundation)
                    if supportsIPhoneLivePose, card.supportsSynchronizedLiveFollowAlong {
                        Button {
                            confirmingSynchronizedFollowAlong = true
                        } label: {
                            Label("开始跟练", systemImage: "play.fill")
                                .frame(maxWidth: .infinity)
                                .foregroundStyle(isReadyToStartFollowAlong ? CoachPalette.action : .white)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .tint(isReadyToStartFollowAlong ? .white : CoachPalette.action)
                        .disabled(!cardMatchesCurrentPlanDay)
                    } else if supportsIPhoneLivePose, !card.supportsSynchronizedLiveFollowAlong {
                        // Endurance cards do not have safe live-pose cues, but the verified
                        // lesson is still useful on iPhone. Keep a single explicit external
                        // fallback instead of leaving the person with a timer-only dead end.
                        Button {
                            openExternalFollowAlong(candidateURL)
                        } label: {
                            Label("打开当天课程", systemImage: "play.rectangle.fill")
                                .frame(maxWidth: .infinity)
                                .foregroundStyle(isReadyToStartFollowAlong ? CoachPalette.action : .white)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .tint(isReadyToStartFollowAlong ? .white : CoachPalette.action)
                        .disabled(!cardMatchesCurrentPlanDay)
                    }
                    #endif
                } else {
                    Label("今天的视频待重新核验，可先按最低版或仅计时", systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                    .foregroundStyle(CoachPalette.recovery)
                }
            }
            if workoutStartedAt != nil || completedWorkout != nil {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    LabeledContent(
                        completedWorkout == nil ? "计时中" : "已停止·待核对",
                        value: completedWorkout?.displayDuration ?? workoutDurationLabel
                    )
                    .monospacedDigit()
                }
            }
            if let completedWorkout {
                Label("已保存本机训练草稿", systemImage: "checkmark.circle")
                    .foregroundStyle(CoachPalette.completed)
                Text("实际计时 \(completedWorkout.displayDuration)。请在下方“计时后核对”确认类型，或丢弃这段草稿。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if workoutStartedAt == nil {
                Button {
                    beginWorkoutTimer()
                } label: {
                    Label("仅计时开始", systemImage: "timer")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .tint(isReadyToStartFollowAlong ? .white : CoachPalette.action)
                .disabled(!canStartWorkoutTimer)
                if !canStartWorkoutTimer {
                    Text("日期已切换：这张旧训练卡不能再开始新计时；已停止并核对的真实训练只保留在本机。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                Button {
                    stopWorkoutTimer()
                } label: {
                    Label("停止并核对记录", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(CoachPalette.recovery)
            }
            if completedWorkout == nil {
                Text("固定 iPhone 后才开启本机基础提醒；视频仍需你亲自点播放。")
                    .font(.footnote)
                    .foregroundStyle(isReadyToStartFollowAlong ? .white.opacity(0.78) : .secondary)
            }
            }
            .padding(isReadyToStartFollowAlong ? 20 : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if isReadyToStartFollowAlong {
                    CoachPalette.action
                        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                }
            }
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 10, trailing: 16))
    }

    /// Only the untouched start state gets a full brand-colour hero surface. Once a real timer
    /// is active or waiting for the owner's review, the normal neutral surface keeps stop and
    /// confirmation states visually distinct from the invitation to begin.
    private var isReadyToStartFollowAlong: Bool {
        workoutStartedAt == nil && completedWorkout == nil && card.video.verifiedCandidateURL != nil
    }

    var body: some View {
        List {
            if plan.trainingMode == .recovery {
                Section {
                    Label("今天已切换保护性恢复版", systemImage: "shield.lefthalf.filled")
                        .font(.headline)
                        .foregroundStyle(CoachPalette.recovery)
                    Text("这张原训练卡现在只作记录参考：不再开始原训练计时、B 站跟练或实时取景。按“练什么”中的恢复说明执行；若刚才已有实际计时，可停止并核对那一段真实记录。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if plan.trainingMode == .standard {
                trainingChoiceSection
            }
            Section {
                DisclosureGroup("训练说明、安全与隐私") {
                Label(card.loadKind.displayName, systemImage: card.loadKind == .recovery ? "figure.walk" : card.loadKind == .endurance ? "figure.outdoor.cycle" : "figure.core.training")
                    .font(.headline)
                Text(card.loadKind.executionNote)
                    .foregroundStyle(.secondary)
                Label(card.stopConditions, systemImage: "hand.raised.fill")
                    .foregroundStyle(CoachPalette.recovery)
                    .fixedSize(horizontal: false, vertical: true)
                LabeledContent("最低完成版", value: card.minimumVersion)
                LabeledContent("标准版", value: card.standardVersion)
                LabeledContent("觉得吃力时", value: card.regression)
                Divider()
                Text(card.followAlongInstruction)
                if let candidateURL = card.video.verifiedCandidateURL {
                    // The iPhone's first action is the in-app, timed follow-along above. Keep
                    // an external link only as the iPad/no-live-cue fallback, where that first
                    // action is unavailable; otherwise two video starts look like two modes.
                    #if canImport(UIKit) && canImport(Vision) && canImport(AVFoundation)
                    if !supportsIPhoneLivePose, plan.trainingMode == .standard && cardMatchesCurrentPlanDay {
                        Button {
                            openExternalFollowAlong(candidateURL)
                        } label: {
                            Label("仅打开今天的 B 站跟练", systemImage: "play.rectangle.fill")
                        }
                        .accessibilityHint("此设备不提供实时取景；将离开本 App 打开当天课程，视频不会缓存")
                    } else if plan.trainingMode != .standard || !cardMatchesCurrentPlanDay {
                        Label(
                            plan.trainingMode == .recovery ? "今天已切换恢复版，原跟练已停用" : "仅当天可打开这节跟练",
                            systemImage: "lock.fill"
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                    #else
                    if plan.trainingMode == .standard && cardMatchesCurrentPlanDay {
                        Button {
                            openExternalFollowAlong(candidateURL)
                        } label: {
                            Label("仅打开今天的 B 站跟练", systemImage: "play.rectangle.fill")
                        }
                    } else {
                        Label("仅当天可打开这节跟练", systemImage: "lock.fill")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    #endif
                    Text("课程：\(card.video.title ?? "")｜\(card.video.uploader ?? "")｜\(card.video.durationDisplay ?? "时长待复核")｜核验于 \(card.video.checkedAt?.formatted(date: .abbreviated, time: .omitted) ?? "")")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let fitNote = card.video.fitNote {
                        Text(fitNote)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Text("课程由 B 站在线播放；本 App 不下载、缓存或录制视频。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Label("这节课程需要重新核验；今天先按文字最低版执行", systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(CoachPalette.recovery)
                }
                Text("本机实时提示只在 App 前台、固定 iPhone 的静态陆上动作时运行；外跳到 B 站或浏览器后会停止。若你主动选择“在 App 内打开 B 站并同步本机提醒”，B 站页面与相机仍各自独立受安全确认和系统状态控制。B 站或 iOS 自行提供画中画时，可由你自行选择使用，但本 App 不承诺或控制第三方视频的画中画。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                ForEach(card.cameraPrompts, id: \.self) { Text("• \($0)") }
                #if canImport(UIKit) && canImport(Vision) && canImport(AVFoundation)
                Label(card.livePoseSafetyNote, systemImage: "exclamationmark.shield")
                    .font(.footnote)
                    .foregroundStyle(CoachPalette.recovery)
                if supportsIPhoneLivePose {
                    Text("只在你主动确认室内陆地、iPhone 已固定后才会开启前置摄像头；跟练中本机每约 0.25 秒刷新基础画面提示。它不是逐动作识别、计数、精确角度测量或诊断：不录像、不缓存、不回放、不保存、不上传。相机/分析不可用、切到后台或未完成安全确认时会明确降级为仅跟练/仅计时。")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    Label("实时取景提醒仅在 iPhone 提供；此 iPad 仅显示训练、计时与反馈。", systemImage: "iphone.slash")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Label("Apple Watch 仅作配对 iPhone 的日卡和计时伴侣；不录像、不做姿态分析，实时提示仍由固定取景的 iPhone 提供。", systemImage: "applewatch")
                    .font(.footnote).foregroundStyle(.secondary)
                #else
                Text("本机取景提醒需在 iPhone 上运行；当前环境不会伪造摄像头或姿态结果。")
                    .font(.footnote).foregroundStyle(.secondary)
                #endif
                if !cardMatchesCurrentPlanDay {
                    Text("日期已切换：这张旧训练卡只保留已发生训练的本机时长核对；不能再打开 B 站、开始本机取景、计时或保存反馈。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                }
                .font(.footnote)
            }
            if workoutStartedAt != nil || completedWorkout != nil || healthSyncStatus != nil {
                Section("计时后核对") {
                Text("仅在本机记录你本人实际开始—停止计时并确认的训练类型与时长；不会用计划时长、相机画面、估算热量、距离、心率或睡眠补写数据，也不会写入 Apple 健康。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let completedWorkout {
                    LabeledContent("已核对运动类型", value: completedWorkout.kind.displayName)
                } else {
                    Text("运动类型会按今天课程预设；开始前不用额外填写。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if plan.trainingMode == .recovery, workoutStartedAt == nil, completedWorkout == nil {
                    Text("恢复版已锁住原训练的新计时；轻走、呼吸或拉伸不需要强行计时。若确实完成另一段实际运动，请在新的当天训练流程中单独核对。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if workoutStartedAt != nil {
                    Text("计时正在进行；请回到页首用“停止并核对记录”结束。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if let finishedWorkout = completedWorkout {
                    LabeledContent("已核对实际时长", value: finishedWorkout.displayDuration)
                    if let confirmation = currentWorkoutConfirmation {
                        Text("已作为本机草稿保存于 \(confirmation.savedAt.formatted(date: .omitted, time: .shortened))；不会写入 Apple 健康。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if finishedWorkout.crossesCalendarDay() {
                        Label("本次真实训练跨过午夜：本机记录保留实际开始和结束时间，不会强行归入今天或改写日卡。", systemImage: "moon.stars")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if finishedWorkout.duration <= 0 {
                        Text("未计到有效时长，不能作为本机训练记录；请重新开始并完成一段实际计时。")
                            .font(.footnote)
                            .foregroundStyle(CoachPalette.recovery)
                    }
                    if canStartWorkoutTimer {
                        Button("重新开始一段计时") {
                            guard discardWorkoutConfirmationIfNeeded() else { return }
                            completedWorkout = nil
                            selectedWorkoutConfirmationID = nil
                            workoutSessionID = UUID()
                            healthSyncStatus = nil
                        }
                    }
                    if currentWorkoutConfirmation != nil {
                        Button("丢弃这段本机训练草稿", role: .destructive) {
                            guard discardWorkoutConfirmationIfNeeded() else { return }
                            completedWorkout = nil
                            selectedWorkoutConfirmationID = nil
                            workoutSessionID = UUID()
                            healthSyncStatus = "已丢弃本机训练草稿；没有向 Apple 健康写入或删除任何数据。"
                        }
                        .font(.footnote)
                    }
                }
                if let healthSyncStatus { Text(healthSyncStatus).font(.footnote).foregroundStyle(.secondary) }
                }
            }
            // Feedback belongs after an actual timed session. Hiding it before the start keeps
            // the training surface about doing the video, rather than filling in a form.
            if completedWorkout != nil || adaptationMessage != nil {
                Section {
                    DisclosureGroup("训练后反馈（可选）") {
                Picker("主观用力", selection: $effort) { ForEach(1...10, id: \.self) { Text("\($0)/10").tag($0) } }
                Picker("疼痛/不适", selection: $pain) { Text("无").tag(0); Text("轻微紧绷").tag(1); Text("疼痛/不适").tag(2) }
                TextField("睡眠小时，可留空", text: $sleepHours)
                if trainingIsPausedForMedicalRecovery {
                    Text("今天暂停计划训练；反馈只记录状态，不标记训练或恢复完成。")
                    Text("只有医生、药品说明或当天恢复说明明确允许的活动，才可另行如实记录；本页不会把休息写成训练完成。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Toggle("我确实完成了今天的训练或恢复", isOn: $completed)
                    Text("默认不勾选。疼痛、提前停止或只记录感受时请保持关闭；保存不适会优先切换恢复版，不会要求补练。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Button(canSaveFeedback ? "保存反馈" : "仅当天可保存反馈") {
                    saveTrainingFeedback()
                }
                .disabled(!canSaveFeedback)
                if !canSaveFeedback {
                    Text("历史、未来或日期已切换的训练卡只读；请在当天对应的训练卡完成后再保存反馈。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let adaptationMessage { Text(adaptationMessage).font(.footnote).foregroundStyle(.secondary) }
                    }
                }
            }
        }
        .navigationTitle(card.title)
        #if canImport(UIKit) && canImport(Vision) && canImport(AVFoundation)
        .sheet(isPresented: $showingLocalPoseCoach) {
            LocalPoseCoachView(
                ownerID: privateData.profile.id,
                prompts: card.cameraPrompts,
                trainingTitle: card.title,
                safetyNote: card.livePoseSafetyNote,
                workoutStartedAt: $workoutStartedAt,
                workoutTimerUnavailableReason: workoutTimerUnavailableReason,
                onStartWorkoutTimer: beginWorkoutTimer,
                onStopWorkoutTimer: { stopWorkoutTimer(reason: $0) }
            )
        }
        .sheet(isPresented: $showingBilibiliLiveFollowAlong) {
            if let followAlongURL = card.video.verifiedCandidateURL {
                LocalPoseCoachView(
                    ownerID: privateData.profile.id,
                    prompts: card.cameraPrompts,
                    trainingTitle: card.title,
                    safetyNote: card.livePoseSafetyNote,
                    followAlongURL: card.video.verifiedInlinePlayerURL ?? followAlongURL,
                    startLiveMonitoringOnAppear: true,
                    workoutStartedAt: $workoutStartedAt,
                    workoutTimerUnavailableReason: workoutTimerUnavailableReason,
                    onStartWorkoutTimer: beginWorkoutTimer,
                    onStopWorkoutTimer: { stopWorkoutTimer(reason: $0) }
                )
            }
        }
        #endif
        .confirmationDialog(
            "同屏开启跟练和实时监测？",
            isPresented: $confirmingSynchronizedFollowAlong,
            titleVisibility: .visible
        ) {
            Button("已固定 iPhone，开始跟练并计时") {
                // This is an explicit owner start, not an inferred video/camera event. Starting
                // the real timer here removes a redundant third tap after safe setup is affirmed.
                beginWorkoutTimer()
                showingBilibiliLiveFollowAlong = true
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("仅用于室内、陆地、静态动作。确认后会开始本机真实计时、加载 B 站跟练并开启前置相机监测；视频仍需你亲自点播放。不要手持手机训练。")
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active, workoutStartedAt != nil {
                stopWorkoutTimer(reason: "App 离开前台，已停止本次计时；请核对实际时长。")
            }
        }
        .onDisappear {
            // A navigation back-swipe must not discard a real elapsed interval merely because
            // this detail view is released. The draft remains local until the owner explicitly
            // discards it; it is never sent to Apple Health.
            if workoutStartedAt != nil {
                stopWorkoutTimer(reason: "已离开训练详情，已停止本次计时；请核对实际时长。")
            }
            if let completedWorkout { persistWorkoutConfirmationIfNeeded(completedWorkout) }
        }
        .onChange(of: plan.trainingMode) { _, mode in
            handleTrainingModeChange(mode)
        }
        .onChange(of: plan.date) { previousDate, currentDate in
            handlePlanDateChange(from: previousDate, to: currentDate)
        }
    }

    private func handleTrainingModeChange(_ mode: TrainingMode) {
        // A risk state can be recorded from “今天” or “健康” while this detail remains
        // alive in another tab. Do not require the person to return here and manually stop
        // the old standard-training timer: preserve only the real elapsed interval, close
        // both local coaching surfaces, and leave the real interval for local review.
        guard mode == .recovery else { return }
        #if canImport(UIKit) && canImport(Vision) && canImport(AVFoundation)
        showingLocalPoseCoach = false
        showingBilibiliLiveFollowAlong = false
        #endif
        if workoutStartedAt != nil {
            stopWorkoutTimer(reason: "今天已从其他页面记录恢复信号，原训练已停止计时；请只核对刚才真实发生的时长，不要继续原训练。")
        }
    }

    private func handlePlanDateChange(from previousDate: Date, to currentDate: Date) {
        // The root shell replaces its bound plan at the local day boundary. An old card must
        // never keep a camera or temporary Bilibili session alive merely because its detail
        // remains on screen. Preserve only the real interval up to the boundary for review.
        guard !Calendar.current.isDate(previousDate, inSameDayAs: currentDate) else { return }
        #if canImport(UIKit) && canImport(Vision) && canImport(AVFoundation)
        showingLocalPoseCoach = false
        showingBilibiliLiveFollowAlong = false
        #endif
        if workoutStartedAt != nil {
            stopWorkoutTimer(reason: "日期已切换，旧日训练已停止计时；请核对截至切换时刻的真实时长。")
        } else if healthSyncStatus == nil {
            healthSyncStatus = "日期已切换：旧训练卡现在只保留已停止训练的本机时长核对。"
        }
    }

    private func saveTrainingFeedback() {
        let trimmedSleep = sleepHours.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedSleep.isEmpty || Double(trimmedSleep) != nil else {
            adaptationMessage = "睡眠请填写有效数字，或留空；本次反馈尚未保存。"
            return
        }
        let feedback = TrainingFeedback(
            id: feedbackSubmissionID,
            effort: effort,
            pain: pain,
            sleepHours: Double(trimmedSleep),
            completed: completed
        )
        let result = TrainingFeedbackService.submit(feedback, plan: plan, data: privateData)
        guard result.wasAccepted else {
            adaptationMessage = result.adaptation.message
            return
        }
        // Feedback can carry pain/short-sleep signals that immediately lock the original
        // training card into recovery.  Persist the feedback and its resulting audit trail
        // before changing the visible card, exactly as with the health-status form.
        do {
            try CoachPrivateStorage.saveLastOwnerData(result.data)
        } catch {
            adaptationMessage = "训练反馈暂未保存；今天的训练卡没有改变。请勿删除 App，确认设备存储可用后重试。"
            return
        }
        plan = result.plan
        privateData = result.data
        feedbackSubmissionID = UUID()
        adaptationMessage = result.adaptation.message
        guard result.plan.trainingMode == .recovery else { return }
        #if canImport(UIKit) && canImport(Vision) && canImport(AVFoundation)
        showingLocalPoseCoach = false
        showingBilibiliLiveFollowAlong = false
        #endif
        if workoutStartedAt != nil {
            stopWorkoutTimer(reason: "已记录不适或短睡眠，原训练已切换恢复版并停止本次计时；请只核对刚才真实发生的时长，不要继续原训练。")
        }
    }

    private func beginWorkoutTimer() {
        guard workoutStartedAt == nil, completedWorkout == nil else { return }
        guard canStartWorkoutTimer else {
            healthSyncStatus = "当前不是今天可执行的标准训练卡；没有开始实际计时。"
            return
        }
        selectedWorkoutConfirmationID = nil
        workoutSessionID = UUID()
        healthSyncStatus = nil
        workoutStartedAt = Date()
    }

    /// External Bilibili playback cannot be a source of pose data. Close the local monitor first
    /// and wait for the sheet's `onDisappear` stop handler to run before leaving the App, so
    /// the verified direct course link cannot imply hidden background capture.
    private func openExternalFollowAlong(_ url: URL) {
        // Both current callers derive their direct lesson from the Bilibili policy, but keep the same
        // boundary at the final system handoff. A future restored/imported course value or a
        // new button must not be able to turn this health/pose screen into a general browser.
        guard BilibiliFollowAlongNavigationPolicy.isAllowed(url) else {
            healthSyncStatus = "未打开链接：只允许当天已核验的 B 站课程。"
            return
        }
        #if canImport(UIKit) && canImport(Vision) && canImport(AVFoundation)
        showingLocalPoseCoach = false
        #endif
        Task { @MainActor in
            await Task.yield()
            // A queued accessibility or normal tap can span the local day boundary.  Recheck
            // immediately before handing off to a third-party app so an old card cannot launch
            // a new lesson after it has become read-only.
            guard cardMatchesCurrentPlanDay, plan.trainingMode == .standard else {
                healthSyncStatus = "日期或恢复状态已切换；没有打开旧训练的 B 站跟练。"
                return
            }
            guard BilibiliFollowAlongNavigationPolicy.isAllowed(url) else {
                healthSyncStatus = "未打开链接：只允许当天已核验的 B 站课程。"
                return
            }
            openURL(url)
        }
    }

    private func stopWorkoutTimer(reason: String? = nil) {
        guard let workoutStartedAt else { return }
        let endedAt = Date()
        completedWorkout = ConfirmedHealthWorkout(
            dayIndex: card.dayIndex,
            startedAt: workoutStartedAt,
            endedAt: endedAt,
            kind: workoutKind,
            syncIdentifier: workoutSessionID
        )
        self.workoutStartedAt = nil
        if let completedWorkout { persistWorkoutConfirmationIfNeeded(completedWorkout) }
        let crossDayNote = completedWorkout?.crossesCalendarDay() == true
            ? " 本次跨过午夜，将保留实际开始和结束时间。"
            : ""
        healthSyncStatus = reason ?? "已停止计时：已在本机记录实际 \(completedWorkout?.displayDuration ?? "00:00:00")；不会写入 Apple 健康。\(crossDayNote)"
    }

    /// Persist a stopped interval before this view can be dismissed. It is intentionally local:
    /// a storage failure cannot be mislabeled as an Apple Health outcome.
    private func persistWorkoutConfirmationIfNeeded(_ workout: ConfirmedHealthWorkout) {
        let updatedData = HealthWorkoutSyncSafety.recordingConfirmation(workout, in: privateData)
        guard updatedData != privateData else { return }
        do {
            try CoachPrivateStorage.saveLastOwnerData(updatedData)
            privateData = updatedData
        } catch {
            healthSyncStatus = "实际训练时段暂未保存到本机。请在此页保持打开，确认设备存储可用后再试。"
        }
    }

    /// A discarded draft must be durably removed before the UI hides its real interval or starts
    /// a new session. Otherwise a storage failure could make an old unreviewed interval vanish
    /// from this screen while it still exists in private data and later reappears unexpectedly.
    @discardableResult
    private func discardWorkoutConfirmationIfNeeded() -> Bool {
        guard let confirmation = currentWorkoutConfirmation else { return true }
        let updatedData = HealthWorkoutSyncSafety.discardingConfirmation(confirmation, in: privateData)
        do {
            try CoachPrivateStorage.saveLastOwnerData(updatedData)
            privateData = updatedData
            return true
        } catch {
            healthSyncStatus = "本机训练草稿暂未丢弃；没有写入或删除 Apple 健康数据。请稍后重试。"
            return false
        }
    }

}

private struct HealthStatusForm: View {
    /// The date belongs to the sheet-opening decision, not to a parent view that might refresh
    /// to tomorrow while this form remains presented.  Requiring an explicit close/reopen after
    /// midnight prevents yesterday's typed symptoms from being silently filed as today's state.
    let planDate: Date
    let isFormalPlanDay: Bool
    @State private var formOwnerID: UUID
    @State private var sleepHours = ""
    @State private var heartRateDelta = ""
    @State private var energy = 0
    @State private var stress = 0
    @State private var nightEatingUrge = 0
    @State private var digestionNote = ""
    @State private var skinNote = ""
    @State private var skinConcerns = Set<SkinConcern>()
    @State private var menstrualPhase: MenstrualPhase?
    @State private var painOrInjury = false
    @State private var menstrualDiscomfort = false
    @State private var illnessSymptoms = false
    @State private var medicationRestriction = false
    @State private var showsOptionalStatusFields = false
    @State private var quickChoice: TodayStatusQuickChoice?
    @State private var submissionID = UUID()
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var observedNow: Date
    @Environment(\.dismiss) private var dismiss
    /// The caller owns its particular plan binding, but must return only after its private
    /// status/audit result is durable.  A failure deliberately leaves this form open so the
    /// person never sees a recovery change that vanishes after a restart.
    /// `nil` means the full status/audit transaction is durable. A message keeps validation and
    /// cross-midnight failures truthful rather than collapsing them into a misleading storage
    /// error.
    let onSave: (HealthStatus, UUID, UUID) -> String?

    init(
        planDate: Date,
        isFormalPlanDay: Bool,
        ownerID: UUID,
        onSave: @escaping (HealthStatus, UUID, UUID) -> String?
    ) {
        self.planDate = planDate
        self.isFormalPlanDay = isFormalPlanDay
        self.onSave = onSave
        _formOwnerID = State(initialValue: ownerID)
        _observedNow = State(initialValue: Date())
    }

    private var openedPlanDayIsCurrent: Bool {
        Calendar.current.isDate(planDate, inSameDayAs: observedNow)
    }

    /// Build the exact status once for both the visible safety preview and the final submit.
    /// The preview deliberately changes only the day's training expectation; it never proposes
    /// a calorie, meal, goal, or weekly-structure change.
    private var draftStatus: HealthStatus {
        HealthStatus(
            sleepHours: Double(sleepHours.trimmingCharacters(in: .whitespacesAndNewlines)),
            restingHeartRateAboveBaseline: Int(heartRateDelta.trimmingCharacters(in: .whitespacesAndNewlines)),
            energy: energy == 0 ? nil : energy,
            stress: stress == 0 ? nil : stress,
            hungerOrNightEatingUrge: nightEatingUrge == 0 ? nil : nightEatingUrge,
            digestionNote: digestionNote.nilIfBlank,
            menstrualPhase: menstrualPhase,
            menstrualDiscomfort: menstrualDiscomfort,
            painOrInjury: painOrInjury,
            illnessSymptoms: illnessSymptoms,
            medicationOrClinicianRestriction: medicationRestriction,
            skinConcerns: Array(skinConcerns),
            skinNote: skinNote.nilIfBlank
        )
    }

    private var willUseRecoveryToday: Bool {
        isFormalPlanDay && draftStatus.validationError == nil && draftStatus.needsProtectiveDowngrade
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("今日状态") {
                    Text("选一个最接近的状态；只在你点保存后写入今天。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(TodayStatusQuickChoice.allCases) { choice in
                            Button { apply(choice) } label: {
                                Label(choice.title, systemImage: choice.symbol)
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.bordered)
                            .tint(quickChoice == choice ? choice.tint : CoachPalette.action)
                        }
                    }
                    if quickChoice == .periodDiscomfort {
                        Label("经期明显不适会让今天切换恢复版；不会自动改热量或后续计划。", systemImage: "shield.lefthalf.filled")
                            .font(.footnote)
                            .foregroundStyle(CoachPalette.recovery)
                    }
                }
                Section("今天的恢复") {
                    TextField("昨晚睡眠（小时，可留空）", text: $sleepHours)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    TextField("静息心率比平时高（次/分，可留空）", text: $heartRateDelta)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                    DisclosureGroup("感觉与经期（可跳过）", isExpanded: $showsOptionalStatusFields) {
                        Picker("精力", selection: $energy) { Text("未记录").tag(0); ForEach(1...5, id: \.self) { Text("\($0)/5").tag($0) } }
                        Picker("压力/情绪负荷", selection: $stress) { Text("未记录").tag(0); ForEach(1...5, id: \.self) { Text("\($0)/5").tag($0) } }
                        Picker("饥饿/夜宵冲动", selection: $nightEatingUrge) { Text("未记录").tag(0); ForEach(1...5, id: \.self) { Text("\($0)/5").tag($0) } }
                        Picker("经期阶段", selection: $menstrualPhase) {
                            Text("未记录").tag(MenstrualPhase?.none)
                            ForEach(MenstrualPhase.allCases, id: \.self) { phase in
                                Text(phase.displayName).tag(MenstrualPhase?.some(phase))
                            }
                        }
                    }
                    Toggle("疼痛或受伤", isOn: $painOrInjury)
                    Toggle("经期明显不适", isOn: $menstrualDiscomfort)
                    Toggle("生病症状", isOn: $illnessSymptoms)
                    Toggle("用药或医生限制", isOn: $medicationRestriction)
                    if willUseRecoveryToday {
                        Label("保存后：今天使用恢复版；三餐、热量与后续训练量不变", systemImage: "shield.lefthalf.filled")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(CoachPalette.recovery)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Section("消化与皮肤（可跳过）") {
                    TextField("消化/排便状态", text: $digestionNote, axis: .vertical)
                    ForEach(SkinConcern.allCases, id: \.self) { concern in
                        Toggle(concern.displayName, isOn: binding(for: concern))
                    }
                    TextField("皮肤状态，例如泛红或干燥", text: $skinNote, axis: .vertical)
                }
                Section {
                    if openedPlanDayIsCurrent {
                        Text(isFormalPlanDay
                             ? "状态只用于当天训练、饮食与恢复建议，不作医疗诊断。皮肤记录只提供低刺激护理与就医阈值提醒，不会推荐或叠加产品。存在风险时会自动切换恢复版并留下记录。"
                             : "这是启动准备或阶段评估日：状态只作为本人私有记录与非医疗休息建议，不创建训练打卡、恢复退阶或新计划。皮肤记录只提供低刺激护理与就医阈值提醒，不会推荐或叠加产品。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Label("日期已切换：这张表单不会保存昨天填写的状态。请取消后打开今天的日卡再记录。", systemImage: "calendar.badge.exclamationmark")
                            .font(.footnote)
                            .foregroundStyle(CoachPalette.recovery)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let saveError {
                        Label(saveError, systemImage: "externaldrive.badge.exclamationmark")
                            .font(.footnote)
                            .foregroundStyle(CoachPalette.recovery)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .coachKeyboardDismissal()
            .navigationTitle("健康状态")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "正在保存…" : "保存") { save() }
                        .disabled(isSaving || !openedPlanDayIsCurrent)
                }
            }
        }
        // A form can remain presented while the app stays foregrounded at midnight.  Refresh
        // the visible boundary on the next local day as well as checking again inside `save()`.
        .task(id: Calendar.current.startOfDay(for: planDate)) {
            while !Task.isCancelled {
                let now = Date()
                guard let nextDay = Calendar.current.nextDate(
                    after: now,
                    matching: DateComponents(hour: 0, minute: 0, second: 0),
                    matchingPolicy: .nextTime
                ) else { return }
                let wait = max(1, nextDay.timeIntervalSince(now))
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                guard !Task.isCancelled else { return }
                observedNow = Date()
            }
        }
    }

    private func save() {
        guard !isSaving else { return }
        guard Calendar.current.isDate(planDate, inSameDayAs: Date()) else {
            observedNow = Date()
            saveError = "日期已切换；这条状态尚未保存。请取消后打开今天的日卡再记录。"
            return
        }
        let trimmedSleep = sleepHours.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedHeartRate = heartRateDelta.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedSleep.isEmpty || Double(trimmedSleep) != nil else {
            saveError = "睡眠请填写有效数字，或留空。"
            return
        }
        guard trimmedHeartRate.isEmpty || Int(trimmedHeartRate) != nil else {
            saveError = "静息心率差值请填写整数，或留空。"
            return
        }
        isSaving = true
        let status = draftStatus
        if let validationError = status.validationError {
            saveError = validationError
            isSaving = false
            return
        }
        if let error = onSave(status, submissionID, formOwnerID) {
            saveError = error
        } else {
            saveError = nil
            submissionID = UUID()
        }
        isSaving = false
    }

    private func apply(_ choice: TodayStatusQuickChoice) {
        quickChoice = choice
        switch choice {
        case .steady:
            energy = 4
            menstrualPhase = nil
            menstrualDiscomfort = false
            illnessSymptoms = false
        case .lowEnergy:
            energy = 2
        case .period:
            menstrualPhase = .menstrual
            menstrualDiscomfort = false
        case .periodDiscomfort:
            menstrualPhase = .menstrual
            menstrualDiscomfort = true
        case .unwell:
            illnessSymptoms = true
        }
    }

    private func binding(for concern: SkinConcern) -> Binding<Bool> {
        Binding(
            get: { skinConcerns.contains(concern) },
            set: { selected in
                if selected { skinConcerns.insert(concern) }
                else { skinConcerns.remove(concern) }
            }
        )
    }
}

private enum TodayStatusQuickChoice: String, CaseIterable, Identifiable {
    case steady
    case lowEnergy
    case period
    case periodDiscomfort
    case unwell

    var id: String { rawValue }

    var title: String {
        switch self {
        case .steady: "状态平稳"
        case .lowEnergy: "精力不足"
        case .period: "经期"
        case .periodDiscomfort: "经期不适"
        case .unwell: "身体不适"
        }
    }

    var symbol: String {
        switch self {
        case .steady: "sun.max"
        case .lowEnergy: "battery.25"
        case .period: "drop"
        case .periodDiscomfort: "drop.triangle"
        case .unwell: "cross.case"
        }
    }

    var tint: Color {
        self == .periodDiscomfort || self == .unwell ? CoachPalette.recovery : CoachPalette.action
    }
}

fileprivate extension String {
    var nilIfBlank: String? { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self }
}

private struct PlanChangeList: View {
    let changes: [PlanChange]
    var body: some View {
        NavigationStack {
            Group {
                if changes.isEmpty { ContentUnavailableView("暂无计划变更", systemImage: "arrow.triangle.2.circlepath", description: Text("低风险自动变更和保护性退阶会在这里留下原因和前后对比。")) }
                else {
                    List(changes.reversed()) { change in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(change.reason).font(.headline)
                            Text("原计划：\(change.before)").font(.footnote)
                            Text("现计划：\(change.after)").font(.footnote)
                            Text(change.authority == .automatic ? "自动执行" : "已确认的重大变更")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(PlanChangeAuditService.explanation(for: change))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }.navigationTitle("计划变更")
        }
    }
}

private struct BudgetImportPreviewSheet: View {
    let preview: BudgetImportPreview
    let existingLedger: MonthlyBudgetLedger
    let onConfirm: ([BudgetImportCandidate]) -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var candidates: [BudgetImportCandidate]
    @State private var importMessage: String?

    init(
        preview: BudgetImportPreview,
        existingLedger: MonthlyBudgetLedger,
        onConfirm: @escaping ([BudgetImportCandidate]) -> Bool
    ) {
        self.preview = preview
        self.existingLedger = existingLedger
        self.onConfirm = onConfirm
        _candidates = State(initialValue: preview.candidates.map { candidate in
            var updated = candidate
            if QianJiBudgetImport.isDuplicate(candidate, in: existingLedger) {
                updated.isSelected = false
            }
            return updated
        })
    }

    private var selectedCandidates: [BudgetImportCandidate] {
        candidates.filter(\.isSelected)
    }

    private var selectedTotal: Decimal {
        selectedCandidates.reduce(0) { $0 + $1.amountYuan }
    }

    private var duplicateCount: Int {
        candidates.filter { QianJiBudgetImport.isDuplicate($0, in: existingLedger) }.count
    }

    var body: some View {
        NavigationStack {
            List {
                Section("导入摘要") {
                    LabeledContent("文件", value: preview.sourceFileName)
                    LabeledContent("工作表", value: preview.sheetName)
                    LabeledContent("已选择", value: "\(selectedCandidates.count) 笔 · ¥\(selectedTotal.description)")
                    if duplicateCount > 0 {
                        Label("检测到 \(duplicateCount) 笔可能重复，已默认取消选择。", systemImage: "doc.on.doc")
                            .font(.footnote)
                            .foregroundStyle(CoachPalette.recovery)
                    }
                    ForEach(preview.warnings, id: \.self) { warning in
                        Text(warning)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Button("全选") {
                            for index in candidates.indices {
                                candidates[index].isSelected = !QianJiBudgetImport.isDuplicate(candidates[index], in: existingLedger)
                            }
                        }
                        Spacer()
                        Button("全部取消") {
                            for index in candidates.indices { candidates[index].isSelected = false }
                        }
                    }
                }

                Section("逐条核对") {
                    ForEach($candidates) { $candidate in
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle(isOn: $candidate.isSelected) {
                                HStack {
                                    Text(candidate.date.formatted(.dateTime.month().day().hour().minute()))
                                    Spacer(minLength: 8)
                                    Text("¥\(candidate.amountYuan.description)")
                                        .monospacedDigit()
                                        .fontWeight(.semibold)
                                }
                            }
                            Text(candidate.note)
                                .font(.subheadline)
                            HStack {
                                Text("钱迹分类：\(candidate.sourceCategory)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer(minLength: 8)
                                Picker("导入分类", selection: $candidate.category) {
                                    ForEach(BudgetCategory.allCases, id: \.self) { category in
                                        Text(category.rawValue).tag(category)
                                    }
                                }
                                .pickerStyle(.menu)
                            }
                            if QianJiBudgetImport.isDuplicate(candidate, in: existingLedger) {
                                Label("可能已在本机账本中", systemImage: "checkmark.circle")
                                    .font(.caption)
                                    .foregroundStyle(CoachPalette.recovery)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section {
                    Text("只有点下“确认导入”后才会整批写入本机账本；保存失败会整批回滚。不会上传 Excel，也不会改动原钱迹文件。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let importMessage {
                        Text(importMessage)
                            .font(.footnote)
                            .foregroundStyle(CoachPalette.recovery)
                    }
                }
            }
            .navigationTitle("核对钱迹账单")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确认导入 \(selectedCandidates.count) 笔") {
                        if onConfirm(candidates) {
                            dismiss()
                        } else {
                            importMessage = "没有完成导入；请检查所选记录后重试。"
                        }
                    }
                    .disabled(selectedCandidates.isEmpty)
                }
            }
        }
    }
}

private struct MyView: View {
    @Binding var privateData: PrivateCoachData
    let onDeleteAllLocalData: () -> Void
    /// Used only by side-effecting settings. It writes through the shell so its durable snapshot
    /// stays coherent with the UI rollback path.
    let onPersistImmediately: (PrivateCoachData) -> Bool
    @State private var amount = ""
    @State private var note = ""
    @State private var category: BudgetCategory = .ingredients
    @State private var budgetStatus: String?
    @State private var showingDeleteConfirmation = false
    @State private var exportDocument: OwnerExportDocument?
    @State private var showingExporter = false
    @State private var exportError: String?
    @State private var showingWeeklyPreview = false
    @State private var calorieLowerBound = ""
    @State private var calorieUpperBound = ""
    @State private var calorieFrameworkConfirmed = false
    @State private var calorieFrameworkMessage: String?
    @State private var calorieAgeYears = ""
    @State private var calorieHeightCm = ""
    @State private var calorieWeightKg = ""
    @State private var calorieFormulaSex: CalorieFormulaSex?
    @State private var calorieActivityLevel: DailyActivityLevel?
    @State private var pendingExpenseDeletion: ExpenseEntry?
    @State private var showingBudgetImporter = false
    @State private var budgetImportPreview: BudgetImportPreview?
    @State private var budgetImportError: String?
    @State private var isParsingBudgetFile = false
    @State private var showingCalorieFramework = false

    private var currentMonthLedger: MonthlyBudgetLedger {
        privateData.ledger(for: .now).snapshot(asOf: .now)
    }

    private var currentMonthEntries: [ExpenseEntry] {
        currentMonthLedger.entries.sorted { $0.date > $1.date }
    }

    private var latestConfirmedWeightKg: Double? {
        privateData.weeklyBodyCheckIns
            .filter { $0.weightKg != nil }
            .sorted { ($0.weightMeasuredAt ?? $0.recordedAt) > ($1.weightMeasuredAt ?? $1.recordedAt) }
            .first?.weightKg
    }

    private var goalSummary: String {
        let goal = privateData.profile.primaryGoal?.trimmingCharacters(in: .whitespacesAndNewlines)
        let weight = privateData.profile.targetWeightKg.map { String(format: "目标 %.1f kg", $0) }
        switch (goal?.isEmpty == false ? goal : nil, weight) {
        case let (goal?, weight?): return "\(goal) · \(weight)"
        case let (goal?, nil): return goal
        case let (nil, weight?): return weight
        case (nil, nil): return "未设置"
        }
    }

    private var calorieRecommendation: CaloriePlanRecommendation? {
        CaloriePlanAdvisor.recommendation(
            weightKg: Double(calorieWeightKg),
            heightCm: Double(calorieHeightCm),
            ageYears: Int(calorieAgeYears),
            formulaSex: calorieFormulaSex,
            activityLevel: calorieActivityLevel
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("计划与时间") {
                    NavigationLink {
                        AppThemeSettingsView()
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Label("外观", systemImage: "paintpalette")
                            Text("海岸青 · 珊瑚暖 · 紫雾蓝")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    NavigationLink {
                        PlanStartDateSettingsView(
                            privateData: $privateData,
                            onPersistImmediately: { onPersistImmediately($0) }
                        )
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Label("计划开始日", systemImage: "calendar.badge.clock")
                            Text(PlanSchedule.startDate()?.formatted(.dateTime.year().month().day()) ?? "未设置")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    NavigationLink {
                        GoalSettingsView(
                            privateData: $privateData,
                            onPersistImmediately: { onPersistImmediately($0) }
                        )
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Label("目标与目标体重", systemImage: "scope")
                            Text(goalSummary)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    NavigationLink {
                        RoutineSettingsView(
                            privateData: $privateData,
                            onPersistImmediately: { onPersistImmediately(privateData) }
                        )
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Label("训练与作息时间", systemImage: "clock")
                            Text(routineSummary)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Section("附近服务与预算") {
                    NavigationLink {
                        NearbyOptionsView(
                            privateData: $privateData,
                            onPersistImmediately: { onPersistImmediately($0) }
                        )
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Label("附近去处", systemImage: "map")
                                .font(.headline)
                            Text("按当前位置更新；价格比较暂不深入，不自动下单")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                if false { // Calorie planning is retained only in old local data, not in the product UI.
                Section {
                    DisclosureGroup("每日热量参考（按需）", isExpanded: $showingCalorieFramework) {
                    if let framework = privateData.profile.dailyCalorieFramework {
                        LabeledContent("当前额度", value: framework.displayName)
                            .font(.headline)
                    }
                    GroupBox("由 App 计算") {
                        VStack(alignment: .leading, spacing: 10) {
                            if latestConfirmedWeightKg == nil {
                                Label("还没有已确认体重；可在这里填写，或先到健康页采用导入体重。", systemImage: "exclamationmark.circle")
                                    .font(.footnote)
                                    .foregroundStyle(CoachPalette.recovery)
                            }
                            TextField("当前体重 kg", text: $calorieWeightKg)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                            TextField("身高 cm", text: $calorieHeightCm)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                            TextField("年龄（18–90）", text: $calorieAgeYears)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                            Picker("计算公式", selection: $calorieFormulaSex) {
                                Text("请选择").tag(CalorieFormulaSex?.none)
                                ForEach(CalorieFormulaSex.allCases) { Text($0.displayName).tag(Optional($0)) }
                            }
                            Picker("日常活动", selection: $calorieActivityLevel) {
                                Text("请选择").tag(DailyActivityLevel?.none)
                                ForEach(DailyActivityLevel.allCases) { Text($0.displayName).tag(Optional($0)) }
                            }
                            if let recommendation = calorieRecommendation {
                                Text("建议额度：\(recommendation.framework.displayName)")
                                    .font(.headline.monospacedDigit())
                                Text(recommendation.explanation)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                Button("采用这组建议") {
                                    calorieLowerBound = String(recommendation.framework.lowerBound)
                                    calorieUpperBound = String(recommendation.framework.upperBound)
                                    calorieFrameworkConfirmed = true
                                    calorieFrameworkMessage = "建议已填入。点下面“确认保存额度”即可生效。"
                                    #if os(iOS)
                                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                                    #endif
                                }
                                .buttonStyle(.borderedProminent)
                            } else {
                                Text("补齐上面五项后会立即出现建议，不需要自己计算。")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    if calorieFrameworkConfirmed {
                        LabeledContent("即将保存", value: "\(calorieLowerBound)–\(calorieUpperBound) kcal/日")
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                    }
                    Button("确认保存额度") { saveCalorieFramework() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!calorieFrameworkConfirmed)
                    if let calorieFrameworkMessage {
                        Text(calorieFrameworkMessage)
                            .font(.footnote)
                            .foregroundStyle(CoachPalette.recovery)
                    }
                    Text("键盘右上方点“完成”即可收起。持续头晕乏力、经期异常、生病或恢复明显变差时，不再继续压低额度。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                }
                }
                Section("个人设置") {
                    NavigationLink {
                        PersonalProfileSettingsView(
                            privateData: $privateData,
                            onPersistImmediately: { onPersistImmediately($0) }
                        )
                    } label: {
                        Label("个人资料与饮食约束", systemImage: "person.text.rectangle")
                    }
                }
                Section("待确认的个性化方向") {
                    if PersonalizationAdvisor.proposals(for: privateData.profile).isEmpty {
                        Text("先填写上方任一日常约束后，这里会只展示可供你确认的建议方向。当前计划保持不变。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(PersonalizationAdvisor.proposals(for: privateData.profile)) { proposal in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(proposal.title)
                                    .font(.subheadline.weight(.semibold))
                                Text(proposal.detail)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                Label(proposal.confirmationBoundary, systemImage: "checkmark.shield")
                                    .font(.footnote)
                                    .foregroundStyle(CoachPalette.recovery)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    if let prompt = PersonalizationAdvisor.missingProfilePrompt(for: privateData.profile) {
                        Text(prompt)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Section("\(currentMonthLedger.monthKey) 预算") {
                    LabeledContent("月上限", value: "¥\(currentMonthLedger.capYuan.description)")
                    LabeledContent("已确认支出", value: "¥\(currentMonthLedger.confirmedSpentYuan.description)")
                    LabeledContent("剩余", value: "¥\(currentMonthLedger.remainingYuan.description)")
                    Text("只统计你手动确认的实际支出；周采购上限和待核验价格不会记为已花。")
                        .font(.footnote).foregroundStyle(.secondary)
                    if let warning = BudgetPolicy.warning(for: currentMonthLedger) { Text(warning).foregroundStyle(CoachPalette.recovery) }
                    ForEach(BudgetCategory.allCases, id: \.self) { category in
                        if let warning = BudgetPolicy.allocationWarning(for: currentMonthLedger, category: category) {
                            Text(warning).font(.footnote).foregroundStyle(CoachPalette.recovery)
                        }
                    }
                }
                Section("本月支出流水") {
                    if currentMonthEntries.isEmpty {
                        Text("本月还没有保存支出。新增后会按日期显示在这里。")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(currentMonthEntries) { entry in
                            HStack(alignment: .top, spacing: 10) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(entry.category.rawValue)
                                        .font(.subheadline.weight(.semibold))
                                    Text(entry.note.isEmpty ? "未填写备注" : entry.note)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                    Text(entry.date.formatted(.dateTime.month().day().hour().minute()))
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                                Spacer(minLength: 8)
                                Text("¥\(entry.amountYuan.description)")
                                    .font(.subheadline.monospacedDigit().weight(.semibold))
                                Menu {
                                    Button("删除后重新记录", systemImage: "trash", role: .destructive) {
                                        pendingExpenseDeletion = entry
                                    }
                                } label: {
                                    Image(systemName: "ellipsis.circle")
                                        .frame(width: 44, height: 44)
                                }
                                .accessibilityLabel("管理这笔支出")
                            }
                        }
                    }
                    Text("金额或类别写错时，可删除后重新记录；App 不会自动修改任何账目。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("从钱迹导入") {
                    Button {
                        showingBudgetImporter = true
                    } label: {
                        Label("选择钱迹 XLSX 文件", systemImage: "square.and.arrow.down")
                    }
                    .disabled(isParsingBudgetFile)
                    if isParsingBudgetFile {
                        ProgressView("正在本机读取，不会上传…")
                    }
                    Text("先生成预览，只列入 \(currentMonthLedger.monthKey) 的支出；收入、转账和其他月份会跳过。你可逐条取消或改分类，确认前预算不会变化。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let budgetImportError {
                        Text(budgetImportError)
                            .font(.footnote)
                            .foregroundStyle(CoachPalette.recovery)
                    }
                }
                Section("只记录实际支出") {
                    Picker("类别", selection: $category) { ForEach(BudgetCategory.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                    TextField("金额（元）", text: $amount)
                    TextField("备注，例如鸡蛋", text: $note)
                    Button("记账") {
                        recordExpense()
                    }
                    if let budgetStatus {
                        Text(budgetStatus).font(.footnote).foregroundStyle(CoachPalette.recovery)
                    }
                }
                Section("隐私") {
                    Text("健康数据、照片和动作视频默认私有；导出或删除需要由本人主动操作。导出副本不含本地照片引用，HealthKit 原始样本也不在本地资料中。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("导出我的本地资料") {
                        do {
                            exportDocument = OwnerExportDocument(data: try PrivateExport.makeOwnerExport(privateData))
                            showingExporter = true
                        }
                        catch { exportError = "导出未能生成，请稍后再试。" }
                    }
                    Button("删除此设备上的全部资料", role: .destructive) { showingDeleteConfirmation = true }
                    if let exportError { Text(exportError).font(.footnote).foregroundStyle(CoachPalette.recovery) }
                }
                Section("朋友内测｜自愿周报") {
                    Text("内测免费；每位体验者在自己的设备上独立建档。周报默认不生成、不发送；只会展示你勾选的文字与完成率，不含资料标识、健康状态、食材餐卡、预算、照片或精确位置。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("预览本周精简周报") { showingWeeklyPreview = true }
                    if privateData.sharedWeeklyReports.isEmpty {
                        Text("尚未生成周报。")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else {
                        ForEach(privateData.sharedWeeklyReports.reversed()) { report in
                            VStack(alignment: .leading, spacing: 3) {
                                if let completionPercentage = report.localDisplayCompletionPercentage {
                                    Text("本地周报｜完成率 \(completionPercentage)%")
                                } else {
                                    Text("本地周报｜格式异常，不能分享")
                                        .foregroundStyle(CoachPalette.recovery)
                                }
                                if report.localDisplayCompletionPercentage != nil, report.observedPlanDays > 0 {
                                    Text("生成时已发生 \(report.observedPlanDays) 个正式计划日\(report.explicitlySkippedPlanDays > 0 ? "，其中 \(report.explicitlySkippedPlanDays) 天明确跳过" : "")")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                } else if report.localDisplayCompletionPercentage == nil {
                                    Text("这是一条本机恢复记录；未发送、不能生成对外载荷。你可撤回它。")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("较早的本地周报未保存复盘范围。")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                Text(report.revokedAt == nil ? "仅本机保存，未发送；可撤回" : "已在本机撤回；未曾发送")
                                    .font(.footnote).foregroundStyle(.secondary)
                                if report.revokedAt == nil {
                                    Button("撤回此本地周报", role: .destructive) { revoke(report) }
                                        .font(.footnote)
                                }
                            }
                        }
                    }
                }
            }
            .coachKeyboardDismissal()
            .navigationTitle("我的")
            .confirmationDialog(
                "删除这笔支出？",
                isPresented: Binding(
                    get: { pendingExpenseDeletion != nil },
                    set: { if !$0 { pendingExpenseDeletion = nil } }
                ),
                titleVisibility: .visible
            ) {
                if let pendingExpenseDeletion {
                    Button("删除 ¥\(pendingExpenseDeletion.amountYuan.description)", role: .destructive) {
                        deleteExpense(pendingExpenseDeletion)
                    }
                }
                Button("取消", role: .cancel) { pendingExpenseDeletion = nil }
            } message: {
                Text("只删除这条本机账目；不会下单、退款或修改其他记录。")
            }
            .onAppear {
                if let framework = privateData.profile.dailyCalorieFramework {
                    calorieLowerBound = String(framework.lowerBound)
                    calorieUpperBound = String(framework.upperBound)
                }
                calorieHeightCm = privateData.profile.heightCm.map { String(format: "%.0f", $0) } ?? ""
                calorieWeightKg = latestConfirmedWeightKg.map { String(format: "%.1f", $0) } ?? ""
                calorieAgeYears = privateData.profile.ageYears.map(String.init) ?? ""
                calorieFormulaSex = privateData.profile.calorieFormulaSex
                calorieActivityLevel = privateData.profile.dailyActivityLevel
            }
            .fileExporter(isPresented: $showingExporter, document: exportDocument, contentType: .json, defaultFilename: "私人健康教练-我的资料") { result in
                if case .failure = result { exportError = "没有写入导出文件；你的原始资料仍保留在本机。" }
            }
            .fileImporter(
                isPresented: $showingBudgetImporter,
                allowedContentTypes: [UTType(filenameExtension: "xlsx") ?? .spreadsheet],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case let .success(urls):
                    guard let url = urls.first else {
                        budgetImportError = "没有选择文件；预算没有变化。"
                        return
                    }
                    loadBudgetImport(from: url)
                case .failure:
                    budgetImportError = "没有读取文件；预算没有变化。"
                }
            }
            .alert("删除全部本地资料？", isPresented: $showingDeleteConfirmation) {
                Button("删除", role: .destructive) { deleteAllLocalData() }
                Button("取消", role: .cancel) {}
            } message: {
                Text("将删除此 App 内的档案（含作息时间表、模糊地点和优惠偏好）、计划完成记录、状态、周复盘趋势、训练反馈、预算、替换餐、计划外餐食记录及其关联本地照片。不会删除苹果健康 App 原始数据或系统照片图库，也不会删除其他独立资料的照片。")
            }
            .sheet(isPresented: $showingWeeklyPreview) {
                WeeklyReportPreviewForm(privateData: privateData, ownerID: privateData.profile.id) { report, ownerID in
                    addWeeklyReport(report, expectedOwnerID: ownerID)
                }
            }
            .sheet(
                isPresented: Binding(
                    get: { budgetImportPreview != nil },
                    set: { if !$0 { budgetImportPreview = nil } }
                )
            ) {
                if let budgetImportPreview {
                    BudgetImportPreviewSheet(
                        preview: budgetImportPreview,
                        existingLedger: currentMonthLedger,
                        onConfirm: importBudgetCandidates
                    )
                }
            }
        }
    }

    private var routineSummary: String {
        guard let schedule = privateData.profile.dailyRoutineSchedule else {
            return "未启用自定义时间"
        }
        return "第一餐 \(clockText(schedule.breakfastMinutes)) · 训练 \(clockText(schedule.trainingMinutes)) · 睡前 \(clockText(schedule.bedtimePreparationMinutes))"
    }

    private func clockText(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    @MainActor private func deleteAllLocalData() {
        // Retain the deleted owner ID only long enough to clear that owner's system alerts.
        // `beginFreshProfileAfterDeletion` immediately replaces the binding with a new UUID, so
        // reading it after that call could accidentally clear a future profile's reminders.
        let deletedOwnerID = privateData.profile.id
        // An export document is only an in-memory FileDocument until the person chooses a save
        // destination. Clear this and old confirmation presentation state at the deletion
        // boundary; otherwise a sheet retained for one UI turn could appear to belong to the
        // new profile after full local deletion.
        exportDocument = nil
        showingExporter = false
        showingWeeklyPreview = false
        // Freeze in-flight HealthKit work before moving local files. A failed deletion reopens
        // the unchanged owner; a committed deletion leaves a tombstone for old async screens.
        PrivateProfileAsyncOwnershipGate.beginDeletion(of: deletedOwnerID)
        do { try LocalDataDeletion.deleteAll(data: privateData) }
        catch {
            PrivateProfileAsyncOwnershipGate.cancelDeletion(of: deletedOwnerID)
            exportError = "本地照片或资料未能完全删除；当前资料仍保留，请稍后在“我的”重试。"
            return
        }
        PrivateProfileAsyncOwnershipGate.commitDeletion(of: deletedOwnerID)
        // The parent now returns to explicit first-run setup. It does not recreate or autosave a
        // blank owner profile immediately after an owner requested full deletion.
        onDeleteAllLocalData()
        #if os(iOS)
        // The notification center is outside the JSON transaction, so explicitly clear only this
        // App's fixed reminder IDs after the owner deletion has succeeded. This touches neither
        // HealthKit nor any other app's notifications.
        Task { @MainActor in
            await LocalReminderCoordinator.invalidateAndClear(ownerID: deletedOwnerID)
        }
        #endif
    }

    private func revoke(_ report: SharedWeeklyReport) {
        guard let index = privateData.sharedWeeklyReports.firstIndex(where: { $0.id == report.id }) else { return }
        var updatedData = privateData
        updatedData.sharedWeeklyReports[index] = WeeklyReportSharing.revoke(report)
        guard onPersistImmediately(updatedData) else {
            exportError = "撤回周报暂未保存；这份周报仍只保留在本机，状态没有改变。"
            return
        }
        privateData = updatedData
    }

    private func saveCalorieFramework() {
        guard calorieFrameworkConfirmed,
              let lowerBound = Int(calorieLowerBound),
              let upperBound = Int(calorieUpperBound),
              let framework = DailyCalorieFramework(lowerBound: lowerBound, upperBound: upperBound) else {
            calorieFrameworkMessage = "请填写有效范围：下限大于 0，且上限不小于下限。"
            return
        }
        if let safetyError = CaloriePlanAdvisor.confirmationError(for: framework) {
            calorieFrameworkMessage = safetyError
            return
        }
        let before = privateData.profile.dailyCalorieFramework?.displayName ?? "未设置"
        var updatedData = privateData
        updatedData.profile.dailyCalorieFramework = framework
        if let height = Double(calorieHeightCm), (100...250).contains(height) { updatedData.profile.heightCm = height }
        if let age = Int(calorieAgeYears), (18...90).contains(age) { updatedData.profile.ageYears = age }
        updatedData.profile.calorieFormulaSex = calorieFormulaSex
        updatedData.profile.dailyActivityLevel = calorieActivityLevel
        if let weight = Double(calorieWeightKg), weight.isFinite, (20...400).contains(weight) {
            let weekStart = WeeklyReviewService.weekStart()
            let existing = updatedData.weeklyBodyCheckIns.first {
                Calendar.current.isDate($0.weekStart, inSameDayAs: weekStart)
            }
            if existing?.weightKg != weight {
                let replacement = WeeklyBodyCheckIn(
                    id: existing?.id ?? UUID(),
                    weekStart: weekStart,
                    weightKg: weight,
                    weightSource: .manual,
                    weightMeasuredAt: .now,
                    waistCm: existing?.waistCm,
                    note: existing?.note
                )
                updatedData.weeklyBodyCheckIns.removeAll {
                    Calendar.current.isDate($0.weekStart, inSameDayAs: weekStart)
                }
                updatedData.weeklyBodyCheckIns.append(replacement)
            }
        }
        updatedData.planChanges.append(PlanChange(kind: .calorieFramework, authority: .requiresConfirmation, reason: "用户主动确认每日热量额度；如资料齐全，建议由近期体重、身高、年龄、公式与活动水平生成。", before: before, after: framework.displayName))
        guard onPersistImmediately(updatedData) else {
            calorieFrameworkMessage = "热量参考暂未保存；当前范围没有改变。"
            return
        }
        privateData = updatedData
        calorieFrameworkConfirmed = false
        calorieFrameworkMessage = nil
    }

    private func recordExpense() {
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Decimal(string: amount), value.isFinite, value >= 0, !trimmedNote.isEmpty else {
            budgetStatus = "请填写有效且不小于 0 的实际金额和备注；未记录任何支出。"
            return
        }
        var updatedData = privateData
        updatedData.recordExpense(ExpenseEntry(category: category, amountYuan: value, note: trimmedNote))
        guard onPersistImmediately(updatedData) else {
            budgetStatus = "这笔支出暂未保存，预算没有改变；请稍后重试。"
            return
        }
        privateData = updatedData
        amount = ""
        note = ""
        budgetStatus = "已仅记录到本机预算；不代表下单或价格核验。"
    }

    private func loadBudgetImport(from url: URL) {
        isParsingBudgetFile = true
        budgetImportError = nil
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
            isParsingBudgetFile = false
        }
        do {
            budgetImportPreview = try QianJiBudgetImport.parseXLSX(
                at: url,
                targetMonthKey: currentMonthLedger.monthKey
            )
        } catch {
            budgetImportPreview = nil
            budgetImportError = (error as? LocalizedError)?.errorDescription ?? "文件读取失败；预算没有变化。"
        }
    }

    private func importBudgetCandidates(_ candidates: [BudgetImportCandidate]) -> Bool {
        let ledger = currentMonthLedger
        let selected = candidates.filter { $0.isSelected && !QianJiBudgetImport.isDuplicate($0, in: ledger) }
        guard !selected.isEmpty else {
            budgetImportError = "没有新的已选支出可导入；预算没有变化。"
            return false
        }
        var updatedData = privateData
        selected.forEach { updatedData.recordExpense($0.expenseEntry()) }
        guard onPersistImmediately(updatedData) else {
            budgetImportError = "导入保存失败；整批记录已回滚，预算没有变化。"
            return false
        }
        privateData = updatedData
        budgetImportPreview = nil
        budgetImportError = nil
        budgetStatus = "已从钱迹导入 \(selected.count) 笔确认支出；重复记录没有再次计入。"
        return true
    }

    private func deleteExpense(_ entry: ExpenseEntry) {
        var updatedData = privateData
        for index in updatedData.monthlyBudgetLedgers.indices {
            updatedData.monthlyBudgetLedgers[index].entries.removeAll { $0.id == entry.id }
        }
        updatedData.budgetLedger.entries.removeAll { $0.id == entry.id }
        guard onPersistImmediately(updatedData) else {
            budgetStatus = "这笔支出暂未删除；账本没有改变。请稍后重试。"
            pendingExpenseDeletion = nil
            return
        }
        privateData = updatedData
        pendingExpenseDeletion = nil
        budgetStatus = "已删除这条本机账目；其他预算记录未改变。"
    }

    private func addWeeklyReport(_ report: SharedWeeklyReport, expectedOwnerID: UUID) {
        guard PrivateProfileAsyncOwnershipGate.mayContinue(
            capturedOwnerID: expectedOwnerID,
            currentOwnerID: privateData.profile.id
        ) else {
            exportError = "原资料已删除或切换；没有生成或保存周报到新资料。"
            return
        }
        var updatedData = privateData
        updatedData.sharedWeeklyReports.append(report)
        guard onPersistImmediately(updatedData) else {
            exportError = "本地周报暂未保存；没有生成或发送任何内容。"
            return
        }
        privateData = updatedData
    }
}

/// Low-frequency profile fields live one level below “我的”, so the main tab remains a compact
/// control center instead of a long web-form. Nothing here grants location, network, or alerts.
private struct PersonalProfileSettingsView: View {
    @Binding var privateData: PrivateCoachData
    let onPersistImmediately: (PrivateCoachData) -> Bool
    @State private var displayName = ""
    @State private var approximateArea = ""
    @State private var workSchedule = ""
    @State private var commuteMode = ""
    @State private var kitchenSetup = ""
    @State private var foodPreferences = ""
    @State private var trainingExperience = ""
    @State private var availableEquipment = ""
    @State private var heightCm = ""
    @State private var message: String?

    var body: some View {
        Form {
            Section("只在本机保存") {
                TextField("怎么称呼你", text: $displayName)
                TextField("运动基础，例如零基础/已有规律训练", text: $trainingExperience)
                TextField("可用器械，例如瑜伽垫/弹力带（可留空）", text: $availableEquipment)
                TextField("身高 cm（可留空）", text: $heightCm)
                #if os(iOS)
                    .keyboardType(.decimalPad)
                #endif
                TextField("工作/作息，例如 10:00–19:00", text: $workSchedule)
                TextField("通勤方式，例如电动车/步行", text: $commuteMode)
                TextField("厨房设备，例如电饭锅 + 一个电磁炉锅", text: $kitchenSetup)
                Text("两个月计划共 61 天（前 56 天正式餐卡 + 5 天收尾复盘），默认以“电饭锅 + 一个电磁炉锅”为基准。设备不同会在餐卡中提示确认；不会自动延长时间、换设备或改菜单。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                TextField("饮食偏好或禁忌（可留空）", text: $foodPreferences, axis: .vertical)
            }
            Section("附近搜索地点（可选）") {
                TextField("附近搜索地点（小区/地铁站，可留空）", text: $approximateArea)
                Text("这是未开定位时的模糊备用地点；在“附近去处”中可主动按手机当前位置更新。不会持续定位、保存精确坐标、领券、购买或发送位置。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section {
                Button("保存本机个人资料") { save() }
                    .tint(CoachPalette.action)
                if let message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(CoachPalette.recovery)
                }
            }
        }
        .navigationTitle("个人资料")
        .onAppear { load() }
    }

    private func load() {
        displayName = privateData.profile.displayName
        approximateArea = privateData.profile.approximateArea ?? ""
        workSchedule = privateData.profile.workSchedule ?? ""
        commuteMode = privateData.profile.commuteMode ?? ""
        kitchenSetup = privateData.profile.kitchenSetup ?? ""
        foodPreferences = privateData.profile.foodPreferences ?? ""
        trainingExperience = privateData.profile.trainingExperience ?? ""
        availableEquipment = privateData.profile.availableEquipment ?? ""
        heightCm = privateData.profile.heightCm.map { String(format: "%.1f", $0) } ?? ""
    }

    private func save() {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            message = "请保留一个称呼；其余字段都可以留空。"
            return
        }
        let trimmedHeight = heightCm.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsedHeight = Double(trimmedHeight)
        guard trimmedHeight.isEmpty || (parsedHeight?.isFinite == true && (50...250).contains(parsedHeight!)) else {
            message = "身高如填写，需为 50–250 cm 的有效数值；也可以留空。"
            return
        }
        let normalizedArea = ApproximateAreaPolicy.normalized(approximateArea)
        if let areaError = ApproximateAreaPolicy.validationError(for: normalizedArea) {
            message = areaError
            return
        }
        var updatedData = privateData
        updatedData.profile.displayName = name
        updatedData.profile.approximateArea = normalizedArea
        updatedData.profile.workSchedule = workSchedule.nilIfBlank
        updatedData.profile.commuteMode = commuteMode.nilIfBlank
        updatedData.profile.kitchenSetup = kitchenSetup.nilIfBlank
        updatedData.profile.foodPreferences = foodPreferences.nilIfBlank
        updatedData.profile.trainingExperience = trainingExperience.nilIfBlank
        updatedData.profile.availableEquipment = availableEquipment.nilIfBlank
        updatedData.profile.heightCm = parsedHeight
        guard onPersistImmediately(updatedData) else {
            message = "个人资料暂未保存；当前资料与计划没有改变。"
            return
        }
        privateData = updatedData
        message = "已仅保存到本机；当前计划、热量、训练和餐卡均未改变。目标或训练结构仍需单独确认。"
    }
}

private struct GoalSettingsView: View {
    @Binding var privateData: PrivateCoachData
    let onPersistImmediately: (PrivateCoachData) -> Bool
    @State private var draftGoal = ""
    @State private var pendingGoal = ""
    @State private var targetWeightText = ""
    @State private var pendingTargetWeightKg: Double?
    @State private var sustainablePace: SustainableGoalPace = .gentle
    @State private var sustainableDays = 3
    @State private var sustainableMinutes = 10
    @State private var sustainableReviewWeeks = 2
    @State private var showingConfirmation = false
    @State private var message: String?

    var body: some View {
        Form {
            Section("当前目标") {
                Text(privateData.profile.primaryGoal ?? "未设置")
                    .font(.headline)
                Text(privateData.profile.sustainableGoal?.summary ?? "尚未设置可持续节奏")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("体重进度") {
                if let currentWeight = latestConfirmedWeightKg {
                    LabeledContent("最近确认体重", value: String(format: "%.1f kg", currentWeight))
                    if let target = privateData.profile.targetWeightKg {
                        let delta = target - currentWeight
                        LabeledContent("目标体重", value: String(format: "%.1f kg", target))
                        LabeledContent("还差", value: delta == 0 ? "已达到目标" : String(format: "%+.1f kg", delta))
                    } else {
                        Text("设置目标体重后，这里会显示与最近确认体重的差值。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("还没有本周确认体重；可在“健康 → 本周复盘”记录，目标页只使用你主动确认的数值。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Section("修改目标") {
                TextField("例如：两个月减脂塑形，优先腰腹和体态", text: $draftGoal, axis: .vertical)
                .lineLimit(3...6)
                TextField("目标体重 kg（可选）", text: $targetWeightText)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
                Button("检查并保存目标", systemImage: "checkmark.shield") {
                    prepareConfirmation()
                }
                .tint(CoachPalette.action)
                if let message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(CoachPalette.recovery)
                }
            }
            Section("可持续节奏") {
                Picker("推进方式", selection: $sustainablePace) {
                    ForEach(SustainableGoalPace.allCases, id: \.self) { pace in
                        Text(pace.displayName).tag(pace)
                    }
                }
                Text(sustainablePace.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Stepper("每周训练 \(sustainableDays) 次", value: $sustainableDays, in: 1...7)
                Stepper("每次最低 \(sustainableMinutes) 分钟", value: $sustainableMinutes, in: 5...60, step: 5)
                Stepper("每 \(sustainableReviewWeeks) 周复盘", value: $sustainableReviewWeeks, in: 1...8)
                Text("这是你给自己的可执行上限与复盘节奏，不是必须满勤的考核；漏做不补练。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            PlanEffectSummary(
                title: "目标保存后",
                immediate: "目标、目标体重和可持续复盘提示会立即更新",
                unchanged: "今天及未来训练日卡、餐卡、采购清单和历史记录保持不变"
            )
        }
        .navigationTitle("我的目标")
        .onAppear {
            draftGoal = privateData.profile.primaryGoal ?? ""
            targetWeightText = privateData.profile.targetWeightKg.map { String(format: "%.1f", $0) } ?? ""
            let goal = privateData.profile.sustainableGoal ?? SustainableGoal()
            sustainablePace = goal.pace
            sustainableDays = goal.weeklyTrainingDays
            sustainableMinutes = goal.minimumMinutes
            sustainableReviewWeeks = goal.reviewEveryWeeks
        }
        .alert("确认调整目标？", isPresented: $showingConfirmation) {
            Button("取消", role: .cancel) {}
            Button("确认保存") { saveConfirmedGoal() }
        } message: {
            Text(goalConfirmationText)
        }
    }

    private func prepareConfirmation() {
        let normalized = draftGoal.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = Double(targetWeightText.trimmingCharacters(in: .whitespacesAndNewlines))
        guard targetWeightText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (target != nil && (30...300).contains(target!)) else {
            message = "目标体重请填写 30–300 kg。"
            return
        }
        let goalChanged = normalized != privateData.profile.primaryGoal?.trimmingCharacters(in: .whitespacesAndNewlines)
        let weightChanged = target != privateData.profile.targetWeightKg
        let newSustainableGoal = SustainableGoal(
            pace: sustainablePace,
            weeklyTrainingDays: sustainableDays,
            minimumMinutes: sustainableMinutes,
            reviewEveryWeeks: sustainableReviewWeeks
        )
        let sustainableChanged = newSustainableGoal != privateData.profile.sustainableGoal
        guard !goalChanged || !normalized.isEmpty else {
            message = "文字目标不能留空；若只调体重，请保留当前目标。"
            return
        }
        guard goalChanged || weightChanged || sustainableChanged else {
            message = "目标没有变化，无需重复保存。"
            return
        }
        pendingGoal = normalized
        pendingTargetWeightKg = target
        message = nil
        showingConfirmation = true
    }

    private func saveConfirmedGoal() {
        var updatedData = privateData
        let previousTargetWeight = privateData.profile.targetWeightKg
        let previousSustainableGoal = privateData.profile.sustainableGoal
        if let result = GoalAdjustmentService.confirmedChange(from: privateData.profile.primaryGoal, to: pendingGoal) {
            updatedData.profile.primaryGoal = result.goal
            updatedData.planChanges.append(result.change)
        }
        updatedData.profile.targetWeightKg = pendingTargetWeightKg
        updatedData.profile.sustainableGoal = SustainableGoal(
            pace: sustainablePace,
            weeklyTrainingDays: sustainableDays,
            minimumMinutes: sustainableMinutes,
            reviewEveryWeeks: sustainableReviewWeeks
        )
        if previousTargetWeight != updatedData.profile.targetWeightKg {
            let before = previousTargetWeight.map { String(format: "目标 %.1f kg", $0) } ?? "目标体重未设置"
            let after = updatedData.profile.targetWeightKg.map { String(format: "目标 %.1f kg", $0) } ?? "目标体重未设置"
            updatedData.planChanges.append(PlanChange(
                kind: .goal,
                authority: .requiresConfirmation,
                reason: "用户主动确认调整目标体重；本次只更新进度参照，不自动改训练、餐卡、热量或历史记录。",
                before: before,
                after: after
            ))
        }
        if previousSustainableGoal != updatedData.profile.sustainableGoal,
           let sustainable = updatedData.profile.sustainableGoal {
            updatedData.planChanges.append(PlanChange(
                kind: .goal,
                authority: .requiresConfirmation,
                reason: "用户主动确认调整可持续节奏；本次只更新建议与复盘提示，不自动改训练日历或补练。",
                before: previousSustainableGoal?.summary ?? "可持续节奏未设置",
                after: sustainable.summary
            ))
        }
        guard onPersistImmediately(updatedData) else {
            message = "目标暂未保存；当前目标和计划都没有改变。"
            return
        }
        privateData = updatedData
        draftGoal = updatedData.profile.primaryGoal ?? ""
        targetWeightText = pendingTargetWeightKg.map { String(format: "%.1f", $0) } ?? ""
        message = "目标已保存到本机；当前餐食和训练计划保持不变。"
    }

    private var goalConfirmationText: String {
        let currentGoal = privateData.profile.primaryGoal ?? "未设置"
        let currentWeight = privateData.profile.targetWeightKg.map { String(format: "%.1f kg", $0) } ?? "未设置"
        let newGoal = pendingGoal.isEmpty ? currentGoal : pendingGoal
        let newWeight = pendingTargetWeightKg.map { String(format: "%.1f kg", $0) } ?? "未设置"
        let sustainable = SustainableGoal(
            pace: sustainablePace,
            weeklyTrainingDays: sustainableDays,
            minimumMinutes: sustainableMinutes,
            reviewEveryWeeks: sustainableReviewWeeks
        )
        return "目标：\(currentGoal) → \(newGoal)\n目标体重：\(currentWeight) → \(newWeight)\n可持续节奏：\(sustainable.summary)\n当前餐食和训练计划保持不变，仅更新建议与复盘提示。"
    }

    private var latestConfirmedWeightKg: Double? {
        privateData.weeklyBodyCheckIns
            .filter { $0.weightKg != nil }
            .sorted { ($0.weightMeasuredAt ?? $0.recordedAt) > ($1.weightMeasuredAt ?? $1.recordedAt) }
            .first?.weightKg
    }
}

/// Central owner-facing control for the calendar's anchor date. This is intentionally separate
/// from the daily routine time table: the anchor remaps day cards, while routine times only
/// change suggestions/reminders. A confirmation preview makes that boundary visible before any
/// preference or audit record is written.
private struct PlanStartDateSettingsView: View {
    @Binding var privateData: PrivateCoachData
    let onPersistImmediately: (PrivateCoachData) -> Bool
    @State private var selectedDate = Calendar.current.startOfDay(for: .now)
    @State private var showingConfirmation = false
    @State private var message: String?

    private var currentStartDate: Date? { PlanSchedule.startDate() }
    private var preview: PlanSchedule.StartDatePreview? {
        PlanSchedule.previewStartDate(selectedDate)
    }

    var body: some View {
        Form {
            Section("当前计划") {
                LabeledContent("当前开始日", value: currentStartDate?.formatted(.dateTime.year().month().day()) ?? "未设置")
                Text("计划由 8 周执行 + 收尾复盘组成（约两个月，共 61 天）。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("选择新的开始日") {
                DatePicker(
                    "开始日",
                    selection: $selectedDate,
                    in: Calendar.current.startOfDay(for: .now)...,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                if let preview {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("将于 \(preview.newStartDate.formatted(.dateTime.year().month().day())) 开始")
                            .font(.headline)
                        Text(preview.dateRangeDescription)
                            .font(.subheadline)
                        Text("只影响未来尚未开始的日卡映射；既有训练、状态、采购、目标和历史记录不会删除、迁移或覆盖。训练时间表仍需单独调整。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 4)
                } else {
                    Text("开始日只能选择今天或未来日期。")
                        .font(.footnote)
                        .foregroundStyle(CoachPalette.recovery)
                }
                Button("预览并确认变更", systemImage: "checkmark.shield") {
                    guard preview != nil else { return }
                    showingConfirmation = true
                }
                .tint(CoachPalette.action)
                if let message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            PlanEffectSummary(
                title: "保存后",
                immediate: "跟练与备餐日历会按新的开始日显示；第 1 天日期清晰可见",
                unchanged: "训练时刻、提醒设置和 2026-08-10 以来的历史记录保持原样"
            )
        }
        .navigationTitle("计划开始日")
        .onAppear {
            // Reopen the settings on the durable anchor when it is still selectable. Falling
            // back to today is necessary for the legacy/default past anchor, but never discard
            // an owner's already chosen future date just because the view was recreated.
            let today = Calendar.current.startOfDay(for: .now)
            if let currentStartDate, currentStartDate >= today {
                selectedDate = currentStartDate
            } else {
                selectedDate = today
            }
        }
        .confirmationDialog("确认调整计划开始日？", isPresented: $showingConfirmation, titleVisibility: .visible) {
            Button("确认并保存") { saveConfirmed() }
            Button("取消", role: .cancel) {}
        } message: {
            if let preview {
                Text("新的 \(preview.dateRangeDescription)。只重排未来日卡，不改写历史；训练时间表不变。")
            } else {
                Text("开始日只能是今天或未来日期。")
            }
        }
    }

    private func saveConfirmed() {
        guard let preview else {
            message = "开始日只能选择今天或未来日期。"
            return
        }
        guard !Calendar.current.isDate(preview.currentStartDate, inSameDayAs: preview.newStartDate) else {
            message = "开始日没有变化，无需重复保存。"
            return
        }
        guard PlanSchedule.setStartDate(preview.newStartDate) else {
            message = "开始日未保存；历史记录未改变。"
            return
        }
        var updatedData = privateData
        updatedData.planChanges.append(PlanChange(
            kind: .progression,
            authority: .requiresConfirmation,
            reason: "用户主动确认调整计划开始日；仅重排未来未开始日卡，不删除、迁移或覆盖历史记录。",
            before: preview.currentStartDate.formatted(.dateTime.year().month().day()),
            after: preview.newStartDate.formatted(.dateTime.year().month().day())
        ))
        guard onPersistImmediately(updatedData) else {
            // UserDefaults has no throwing write API; explicitly restore the previous anchor if
            // the private audit write fails so the UI never advertises a partially saved change.
            UserDefaults.standard.set(preview.currentStartDate.timeIntervalSince1970, forKey: PlanSchedule.restartDateDefaultsKey)
            NotificationCenter.default.post(name: PlanSchedule.didRestartNotification, object: nil)
            message = "开始日暂未保存；当前计划与历史记录没有改变。请稍后重试。"
            return
        }
        privateData = updatedData
        message = "已保存；新的第 1 天从 \(preview.newStartDate.formatted(.dateTime.year().month().day())) 开始。"
    }
}

private struct RoutineSettingsView: View {
    @Binding var privateData: PrivateCoachData
    let onPersistImmediately: () -> Bool
    @State private var usesCustomRoutine = false
    @State private var wakeTime = Self.time(hour: 12, minute: 0)
    @State private var breakfastTime = Self.time(hour: 12, minute: 30)
    @State private var lunchTime = Self.time(hour: 13, minute: 0)
    @State private var dinnerTime = Self.time(hour: 19, minute: 0)
    @State private var trainingTime = Self.time(hour: 20, minute: 0)
    @State private var bedtimePreparationTime = Self.time(hour: 23, minute: 15)
    @State private var quietStartTime = Self.time(hour: 23, minute: 30)
    @State private var quietEndTime = Self.time(hour: 9, minute: 0)
    @State private var breakfastReminder = false
    @State private var lunchReminder = false
    @State private var dinnerReminder = false
    @State private var trainingReminder = false
    @State private var bedtimePreparationReminder = false
    @State private var message: String?
    /// Notification-center updates are asynchronous and not transactional with SwiftUI taps.
    /// Keep one owner-requested synchronization in flight so two rapid taps cannot race and
    /// restore an older notification selection after a newer saved schedule.
    @State private var isSynchronizingReminders = false

    var body: some View {
        Form {
            Section {
                Toggle("按我的时间表推荐下一件事", isOn: $usesCustomRoutine)
                Text("开启后可直接选择起床、三餐、训练和睡前时间；它只改变首页建议顺序，不会创建系统提醒、判定漏做、补早餐或补练。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if !usesCustomRoutine {
                    Button("现在选择训练时间", systemImage: "clock.badge.checkmark") {
                        usesCustomRoutine = true
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }
            if usesCustomRoutine {
                Section("日常时间") {
                    DatePicker("通常起床", selection: $wakeTime, displayedComponents: .hourAndMinute)
                    DatePicker("早餐/第一餐", selection: $breakfastTime, displayedComponents: .hourAndMinute)
                    DatePicker("午餐", selection: $lunchTime, displayedComponents: .hourAndMinute)
                    DatePicker("晚餐", selection: $dinnerTime, displayedComponents: .hourAndMinute)
                    DatePicker("训练", selection: $trainingTime, displayedComponents: .hourAndMinute)
                    DatePicker("睡前准备", selection: $bedtimePreparationTime, displayedComponents: .hourAndMinute)
                }
                .datePickerStyle(.compact)
                Section("静默时间") {
                    DatePicker("静默开始", selection: $quietStartTime, displayedComponents: .hourAndMinute)
                    DatePicker("静默结束", selection: $quietEndTime, displayedComponents: .hourAndMinute)
                    Text("静默时段内的提醒不会被偷偷挪到其他时间；请自行调整时间或关闭该项。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .datePickerStyle(.compact)
                Section("本机提醒（可选）") {
                    Toggle("第一餐提醒", isOn: $breakfastReminder)
                    Toggle("午餐/饭盒提醒", isOn: $lunchReminder)
                    Toggle("晚餐提醒", isOn: $dinnerReminder)
                    Toggle("训练或恢复提醒", isOn: $trainingReminder)
                    Toggle("睡前准备提醒", isOn: $bedtimePreparationReminder)
                    Text("首次创建只在你点“允许通知并更新提醒”后请求系统权限。之后保存时间表会按已授权状态更新或清除这几项本机提醒；不会用其他提醒代替，也不包含健康、食材、位置或价格信息。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    #if os(iOS)
                    Button(isSynchronizingReminders ? "正在更新提醒…" : "允许通知并更新提醒") {
                        // `.disabled` normally prevents a second tap, but an accessibility
                        // action already queued before SwiftUI redraws can still enter this
                        // closure. Check before mutating/persisting the schedule: otherwise a
                        // newer private preference could reach disk while the in-flight task
                        // finishes scheduling the older selection.
                        guard !isSynchronizingReminders else { return }
                        persistScheduleAndAudit()
                        guard saveScheduleBeforeNotificationSideEffect() else {
                            // The parent shell has restored the durable binding. Restore this
                            // screen's draft too, so a failed save is not visually mistaken for
                            // a saved time/reminder selection while the owner remains here.
                            load()
                            return
                        }
                        let schedule = privateData.profile.dailyRoutineSchedule
                        let preferences = privateData.profile.dailyReminderPreferences ?? reminderPreferences
                        synchronizeSavedReminders(
                            schedule: schedule,
                            preferences: preferences,
                            requestingAuthorization: true,
                            prefix: nil
                        )
                    }
                    .disabled(isSynchronizingReminders || !usesCustomRoutine || !reminderPreferences.hasAnyEnabled)
                    #else
                    Text("系统提醒仅在 iPhone/iPad 设置；Mac 不创建移动端提醒。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    #endif
                }
            }
            PlanEffectSummary(
                title: "时间保存后",
                immediate: "首页下一件事、跟练页时间摘要和已授权的本机提醒会更新",
                unchanged: "训练日历内容、完成记录和历史数据不会被重排或覆盖"
            )
            Section {
                Button(saveButtonTitle) { save() }
                    .tint(CoachPalette.action)
                    .disabled(isSynchronizingReminders)
                if let message { Text(message).font(.footnote).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("我的时间表")
        .onAppear { load() }
    }

    private func load() {
        // Reminder choices remain private preferences even while the owner temporarily turns
        // off the custom schedule.  Load them before the no-schedule early return so reopening
        // this screen cannot visually reset those choices and then overwrite them on a later
        // save.  A nil schedule still creates no system reminder.
        let preferences = privateData.profile.dailyReminderPreferences ?? DailyReminderPreferences()
        breakfastReminder = preferences.breakfastEnabled
        lunchReminder = preferences.lunchEnabled
        dinnerReminder = preferences.dinnerEnabled
        trainingReminder = preferences.trainingEnabled
        bedtimePreparationReminder = preferences.bedtimePreparationEnabled
        guard let routine = privateData.profile.dailyRoutineSchedule else {
            usesCustomRoutine = false
            return
        }
        usesCustomRoutine = true
        wakeTime = Self.time(minutes: routine.wakeMinutes)
        breakfastTime = Self.time(minutes: routine.breakfastMinutes)
        lunchTime = Self.time(minutes: routine.lunchMinutes)
        dinnerTime = Self.time(minutes: routine.dinnerMinutes)
        trainingTime = Self.time(minutes: routine.trainingMinutes)
        bedtimePreparationTime = Self.time(minutes: routine.bedtimePreparationMinutes)
        quietStartTime = Self.time(minutes: routine.quietStartMinutes)
        quietEndTime = Self.time(minutes: routine.quietEndMinutes)
    }

    private func save() {
        // Keep the same hard gate as the button state. A notification synchronization owns both
        // the saved schedule snapshot and the system update; a second save must wait rather
        // than persist a newer snapshot that has no matching notification synchronization.
        guard !isSynchronizingReminders else { return }
        persistScheduleAndAudit()
        guard saveScheduleBeforeNotificationSideEffect() else {
            // Keep the editable controls aligned with the rollback performed by the app shell.
            // A later retry then starts from the actually durable schedule rather than a stale
            // in-memory draft that was explicitly reported as unsaved.
            load()
            return
        }
        #if os(iOS)
        let schedule = privateData.profile.dailyRoutineSchedule
        let preferences = privateData.profile.dailyReminderPreferences ?? reminderPreferences
        synchronizeSavedReminders(
            schedule: schedule,
            preferences: preferences,
            requestingAuthorization: false,
            prefix: usesCustomRoutine
                ? "已保存；首页会按这个顺序建议下一件事。"
                : "已关闭自定义时间表；不会把任何一天判为漏做。"
        )
        #else
        message = usesCustomRoutine ? "已保存；首页会按这个顺序建议下一件事。" : "已关闭自定义时间表；不会把任何一天判为漏做。"
        #endif
    }

    private var reminderPreferences: DailyReminderPreferences {
        DailyReminderPreferences(
            breakfastEnabled: breakfastReminder,
            lunchEnabled: lunchReminder,
            dinnerEnabled: dinnerReminder,
            trainingEnabled: trainingReminder,
            bedtimePreparationEnabled: bedtimePreparationReminder
        )
    }

    private var saveButtonTitle: String {
        usesCustomRoutine && reminderPreferences.hasAnyEnabled
            ? "保存时间表并更新已授权提醒"
            : "保存时间表"
    }

    /// Saving settings always precedes this system side effect.  The initial permission request
    /// remains tied to its dedicated owner-labelled button; an ordinary save only uses the
    /// authorization state already granted by the system and otherwise clears stale App alerts.
    private func synchronizeSavedReminders(
        schedule: DailyRoutineSchedule?,
        preferences: DailyReminderPreferences,
        requestingAuthorization: Bool,
        prefix: String?
    ) {
        guard !isSynchronizingReminders else { return }
        // This view can outlive a full-profile deletion briefly while its Task is queued on the
        // main actor. Capture the owner at the tap boundary, alongside the already-captured
        // schedule/preferences, so an old task can never borrow a newly created profile ID.
        let ownerID = privateData.profile.id
        isSynchronizingReminders = true
        message = requestingAuthorization ? "正在按已保存的时间表请求或更新本机提醒…" : "已保存时间表；正在更新已授权的本机提醒…"
        Task { @MainActor in
            let synchronization: String
            if requestingAuthorization {
                synchronization = await LocalReminderCoordinator.requestAuthorizationAndSynchronize(
                    ownerID: ownerID,
                    schedule: schedule,
                    preferences: preferences
                )
            } else {
                synchronization = await LocalReminderCoordinator.synchronize(
                    ownerID: ownerID,
                    schedule: schedule,
                    preferences: preferences
                )
            }
            isSynchronizingReminders = false
            if let prefix {
                message = "\(prefix)\(synchronization)"
            } else {
                message = synchronization
            }
        }
    }

    private func persistSchedule() {
        privateData.profile.dailyRoutineSchedule = usesCustomRoutine ? DailyRoutineSchedule(
            wakeMinutes: Self.minutes(for: wakeTime),
            breakfastMinutes: Self.minutes(for: breakfastTime),
            lunchMinutes: Self.minutes(for: lunchTime),
            dinnerMinutes: Self.minutes(for: dinnerTime),
            trainingMinutes: Self.minutes(for: trainingTime),
            bedtimePreparationMinutes: Self.minutes(for: bedtimePreparationTime),
            quietStartMinutes: Self.minutes(for: quietStartTime),
            quietEndMinutes: Self.minutes(for: quietEndTime)
        ) : nil
        privateData.profile.dailyReminderPreferences = reminderPreferences
    }

    private func persistScheduleAndAudit() {
        let previous = privateData.profile.dailyRoutineSchedule
        persistSchedule()
        let current = privateData.profile.dailyRoutineSchedule
        guard previous != current else { return }
        privateData.planChanges.append(PlanChange(
            kind: .routineSchedule,
            authority: .requiresConfirmation,
            reason: "用户主动确认调整日常时间表；本次更新首页建议与已授权提醒，不重排训练日历或覆盖历史记录。",
            before: Self.scheduleSummary(previous),
            after: Self.scheduleSummary(current)
        ))
    }

    private static func scheduleSummary(_ schedule: DailyRoutineSchedule?) -> String {
        guard let schedule else { return "未启用自定义时间表" }
        func clock(_ minutes: Int) -> String { String(format: "%02d:%02d", minutes / 60, minutes % 60) }
        return "第一餐 \(clock(schedule.breakfastMinutes)) · 训练 \(clock(schedule.trainingMinutes)) · 睡前 \(clock(schedule.bedtimePreparationMinutes))"
    }

    /// System notifications are outside the JSON autosave transaction.  Make this settings
    /// action durable first, before requesting authorization or clearing/creating reminders, so
    /// a failed private-file write cannot leave alerts for a schedule that disappeared on restart.
    private func saveScheduleBeforeNotificationSideEffect() -> Bool {
        guard onPersistImmediately() else {
            message = "时间表暂未保存；没有请求或更新系统提醒。请勿删除 App，稍后重试。"
            return false
        }
        return true
    }

    private static func time(hour: Int, minute: Int) -> Date {
        Calendar.current.date(from: DateComponents(hour: hour, minute: minute)) ?? .now
    }

    private static func time(minutes: Int) -> Date { time(hour: minutes / 60, minute: minutes % 60) }

    private static func minutes(for date: Date) -> Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}

/// A compact, repeated contract for settings screens. It prevents the common ambiguity where
/// an editable value looks like it will rewrite the whole plan even though it only changes
/// recommendations, summaries, or owner-authorized reminders.
private struct PlanEffectSummary: View {
    let title: String
    let immediate: String
    let unchanged: String

    var body: some View {
        Section(title) {
            Label(immediate, systemImage: "arrow.triangle.2.circlepath")
                .font(.footnote)
                .foregroundStyle(CoachPalette.action)
                .fixedSize(horizontal: false, vertical: true)
            Label(unchanged, systemImage: "lock.fill")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct NearbyOptionsView: View {
    @Binding var privateData: PrivateCoachData
    let onPersistImmediately: (PrivateCoachData) -> Bool
    @State private var gym = false
    @State private var swimming = false
    @State private var bike = false
    @State private var grocery = false
    @State private var message: String?
    @State private var handoffStatus: String?
    @Environment(\.openURL) private var openURL
    #if os(iOS) && canImport(CoreLocation)
    @StateObject private var location = NearbyCurrentLocationProvider()
    #endif

    private var searches: [NearbyPlaceSearch] {
        var values: [NearbyPlaceSearch] = []
        if gym { values.append(NearbyPlaceSearch(title: "找附近健身房", kind: .gym, symbol: "dumbbell")) }
        if swimming { values.append(NearbyPlaceSearch(title: "找附近游泳馆", kind: .swimming, symbol: "figure.pool.swim")) }
        if grocery { values.append(NearbyPlaceSearch(title: "找附近生鲜商超", kind: .grocery, symbol: "basket")) }
        if bike { values.append(NearbyPlaceSearch(title: "找附近共享单车", kind: .sharedBike, symbol: "bicycle")) }
        // An empty preference set means “未筛选”, not “没有可用入口”.  First-time users can
        // open a map search immediately; toggles only narrow the list after they deliberately
        // choose their usual categories.
        return values.isEmpty ? allSearches : values
    }

    private var allSearches: [NearbyPlaceSearch] {
        [
            NearbyPlaceSearch(title: "找附近健身房", kind: .gym, symbol: "dumbbell"),
            NearbyPlaceSearch(title: "找附近游泳馆", kind: .swimming, symbol: "figure.pool.swim"),
            NearbyPlaceSearch(title: "找附近生鲜商超", kind: .grocery, symbol: "basket"),
            NearbyPlaceSearch(title: "找附近共享单车", kind: .sharedBike, symbol: "bicycle")
        ]
    }

    var body: some View {
        Form {
            Section("常用类别（可选筛选）") {
                Toggle("健身房", isOn: $gym)
                Toggle("游泳馆", isOn: $swimming)
                Toggle("生鲜商超", isOn: $grocery)
                Toggle("共享单车", isOn: $bike)
                Text("不勾选也能直接查找；勾选后只显示你选的类别。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("附近地点") {
                #if os(iOS) && canImport(CoreLocation)
                Button { location.refresh() } label: {
                    Label(locationButtonTitle, systemImage: "location.fill")
                }
                .disabled(location.status == .locating)
                switch location.status {
                case .ready:
                    Label("已按当前位置更新本次地图搜索", systemImage: "checkmark.circle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(CoachPalette.completed)
                case .locating:
                    Label("正在更新附近地点…", systemImage: "location.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                case .denied:
                    Text("未获定位权限，地图会改用你填写的模糊地点或默认附近搜索。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Link("去系统设置开启定位", destination: URL(string: UIApplication.openSettingsURLString)!)
                        .font(.footnote.weight(.semibold))
                case .unavailable:
                    Text("当前位置暂不可用，可稍后重试或使用模糊地点。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                case .idle:
                    Text("首次点按会请求“使用期间”定位权限。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Text("只在本页短暂取约 100 米的地图中心，不保存、不上传、不持续追踪；点按下面的项目后才打开 Apple 地图。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                #else
                Text("Mac 版不读取设备位置；可在 iPhone 上更新附近地点。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                #endif
            }
            Section("手动查找") {
                Text("可直接点按；若已授权定位，会优先使用手机当前位置。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                #if os(iOS) && canImport(CoreLocation)
                if location.status == .locating {
                    Label("正在定位，地图入口会在定位完成后启用", systemImage: "location.circle")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(CoachPalette.action)
                }
                #endif
                ForEach(searches) { search in
                    if let url = mapSearchURL(for: search) {
                        Button { openMaps(url, searchTitle: search.title) } label: {
                            Label(search.title, systemImage: search.symbol)
                        }
                        #if os(iOS) && canImport(CoreLocation)
                        .disabled(location.status == .locating)
                        #endif
                    }
                }
                // Price comparison is intentionally kept out of the primary nearby flow until
                // a reliable provider is available. Keep the existing manual tool discoverable,
                // but make its deferred/owner-entered nature explicit so it is not mistaken for
                // automatic live comparison.
                DisclosureGroup {
                    NavigationLink {
                        NearbyPriceCompareView(
                            preferences: privateData.profile.nearbyOfferPreferences ?? NearbyOfferPreferences()
                        )
                    } label: {
                        Label("打开手动比价工具", systemImage: "arrow.left.arrow.right")
                    }
                    Text("暂不接入实时商家价格或自动抓取。需要时由你输入同一规格的两家价格，结果仅作本机排序参考。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } label: {
                    Label("价格比较（暂缓深入）", systemImage: "pause.circle")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                if let handoffStatus {
                    Text(handoffStatus)
                        .font(.footnote)
                        .foregroundStyle(CoachPalette.recovery)
                }
                Text("点按后才交给 Apple 地图搜索；定位完成前不会使用旧地点。App 不自动查价、不领券或支付。价格和优惠以你打开的店铺页面为准。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section {
                Button { save() } label: {
                    Label("保存并刷新地图入口", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(CoachPalette.action)
                if let message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(message.hasPrefix("已保存") ? CoachPalette.completed : CoachPalette.recovery)
                }
            }
        }
        .navigationTitle("附近去处")
        .onAppear {
            load()
            #if os(iOS) && canImport(CoreLocation)
            // Once the owner has already granted while-in-use access, reopening this page keeps
            // nearby results current without another prompt or any background tracking.
            location.refreshIfAuthorized()
            #endif
        }
    }

    private func mapSearchURL(for search: NearbyPlaceSearch) -> URL? {
        NearbyPlaceSearchLink.mapsURL(
            for: search.kind,
            approximateArea: privateData.profile.approximateArea,
            currentLocation: {
                #if os(iOS) && canImport(CoreLocation)
                location.coordinate
                #else
                nil
                #endif
            }()
        )
    }

    #if os(iOS) && canImport(CoreLocation)
    private var locationButtonTitle: String {
        location.status == .locating ? "更新中" : "按当前位置更新"
    }
    #endif

    private func openMaps(_ url: URL, searchTitle: String) {
        handoffStatus = nil
        openURL(url) { accepted in
            handoffStatus = accepted ? "已交给 Apple 地图：\(searchTitle)。" : "系统暂时无法打开 Apple 地图；请确认地图 App 可用后再试。"
        }
    }

    private func load() {
        let preferences = privateData.profile.nearbyOfferPreferences ?? NearbyOfferPreferences()
        gym = preferences.gymRemindersEnabled
        swimming = preferences.swimmingRemindersEnabled
        bike = preferences.bikeRemindersEnabled
        grocery = preferences.groceryRemindersEnabled
    }

    private func save() {
        var updatedData = privateData
        let existing = privateData.profile.nearbyOfferPreferences ?? NearbyOfferPreferences()
        updatedData.profile.nearbyOfferPreferences = NearbyOfferPreferences(
            gymRemindersEnabled: gym,
            swimmingRemindersEnabled: swimming,
            bikeRemindersEnabled: bike,
            groceryRemindersEnabled: grocery,
            deliveryRemindersEnabled: existing.deliveryRemindersEnabled,
            // Threshold fields remain in the model for backward-compatible decoding, but this
            // surface no longer edits them while live comparison is intentionally unavailable.
            basketSavingsThresholdYuan: existing.basketSavingsThresholdYuan,
            swimSingleEntryThresholdYuan: existing.swimSingleEntryThresholdYuan
        )
        guard onPersistImmediately(updatedData) else {
            message = "附近偏好暂未保存；地点与价格均未查询。"
            return
        }
        privateData = updatedData
        message = "已保存到本机。现在可直接点地图搜索，自己核验价格。"
    }
}

private struct NearbyPlaceSearch: Identifiable {
    let title: String
    let kind: NearbyOfferKind
    let symbol: String
    var id: String { kind.rawValue }
}

private struct NearbyPriceCompareView: View {
    let preferences: NearbyOfferPreferences
    @State private var kind: NearbyComparisonKind = .grocery
    @State private var candidates = [NearbyPriceCandidate(), NearbyPriceCandidate()]

    private var validCandidates: [NearbyPriceCandidate.Value] {
        candidates.compactMap { $0.value }.sorted { $0.price < $1.price }
    }

    private var result: NearbyMultiPriceComparisonResult? {
        guard validCandidates.count >= 2 else { return nil }
        return NearbyMultiPriceComparisonResult(kind: kind, ranked: validCandidates, preferences: preferences)
    }

    var body: some View {
        Form {
            Section("比较项目") {
                Picker("类别", selection: $kind) {
                    ForEach(NearbyComparisonKind.allCases) { value in
                        Text(value.title).tag(value)
                    }
                }
                Text(kind.inputHint)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("多家方案") {
                ForEach($candidates) { $candidate in
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("店名/方案名（可留空）", text: $candidate.name)
                        TextField(kind.pricePrompt, text: $candidate.priceText)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                        if candidates.count > 2 {
                            Button("删除这家", role: .destructive) {
                                candidates.removeAll { $0.id == candidate.id }
                            }
                            .font(.footnote)
                        }
                    }
                }
                Button("再加一家", systemImage: "plus.circle") {
                    candidates.append(NearbyPriceCandidate())
                }
            }
            Section("比价结果") {
                if let result {
                    Label(result.summary, systemImage: result.symbol)
                        .foregroundStyle(result.isNotable ? CoachPalette.completed : .primary)
                    ForEach(Array(validCandidates.enumerated()), id: \.element.id) { index, candidate in
                        HStack(spacing: 12) {
                            Text("\(index + 1)")
                                .font(.caption.weight(.bold).monospacedDigit())
                                .foregroundStyle(index == 0 ? CoachPalette.completed : .secondary)
                                .frame(width: 22, height: 22)
                                .background(
                                    (index == 0 ? CoachPalette.completed : Color.secondary).opacity(0.12),
                                    in: Circle()
                                )
                            Text(candidate.name)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text("¥\(priceText(candidate.price))")
                                .font(.body.monospacedDigit().weight(.semibold))
                        }
                        .accessibilityLabel("第 \(index + 1) 名，\(candidate.name)，¥\(priceText(candidate.price))")
                    }
                    if let thresholdDetail = result.thresholdDetail {
                        Text(thresholdDetail)
                            .font(.footnote)
                            .foregroundStyle(result.isNotable ? CoachPalette.completed : .secondary)
                    }
                } else {
                    Text("填入至少两家不低于 ¥0 的价格后，自动排序并比较。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                Button("清空本次输入", role: .destructive) {
                    candidates = [NearbyPriceCandidate(), NearbyPriceCandidate()]
                }
                Text("价格仅用于这次屏幕上的计算：不联网、不保存、不领券或下单。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .coachKeyboardDismissal()
        .navigationTitle("手动比价")
    }

    private func priceText(_ price: Decimal) -> String {
        String(format: "%.2f", NSDecimalNumber(decimal: price).doubleValue)
    }
}

private enum NearbyComparisonKind: String, CaseIterable, Identifiable {
    case grocery
    case swimming
    case gym
    case sharedBike

    var id: String { rawValue }

    var title: String {
        switch self {
        case .grocery: "生鲜商超"
        case .swimming: "游泳馆"
        case .gym: "健身房"
        case .sharedBike: "共享单车"
        }
    }

    var pricePrompt: String {
        switch self {
        case .grocery: "本次到手价（元）"
        case .swimming: "单次价格（元）"
        case .gym: "单次/月卡价格（元）"
        case .sharedBike: "本次骑行价格（元）"
        }
    }

    var inputHint: String {
        switch self {
        case .grocery: "请用同一购物清单的到手价比较。"
        case .swimming: "请用同一时段、同一入场方式的单次价比较。"
        case .gym: "请用同一种卡型或同一单次入场方式比较。"
        case .sharedBike: "请用同一路程、同一优惠规则下的价格比较。"
        }
    }
}

private struct NearbyPriceCandidate: Identifiable {
    struct Value: Identifiable {
        let id: UUID
        let name: String
        let price: Decimal
    }

    let id = UUID()
    var name = ""
    var priceText = ""

    var value: Value? {
        guard let price = Decimal(string: priceText.trimmingCharacters(in: .whitespacesAndNewlines)), price >= 0 else { return nil }
        return Value(id: id, name: name.nilIfBlank ?? "未命名方案", price: price)
    }
}

private struct NearbyMultiPriceComparisonResult {
    let summary: String
    let thresholdDetail: String?
    let isNotable: Bool
    let symbol: String

    init(
        kind: NearbyComparisonKind,
        ranked: [NearbyPriceCandidate.Value],
        preferences: NearbyOfferPreferences
    ) {
        let lowest = ranked[0]
        let highest = ranked[ranked.count - 1]
        let difference = highest.price - lowest.price
        if difference == 0 {
            summary = "\(ranked.count) 家同价：¥\(Self.yuan(lowest.price))"
        } else {
            summary = "最低：\(lowest.name) ¥\(Self.yuan(lowest.price))，比最高低 ¥\(Self.yuan(difference))"
        }
        switch kind {
        case .grocery:
            let threshold = Decimal(preferences.basketSavingsThresholdYuan)
            isNotable = difference >= threshold
            thresholdDetail = difference >= threshold
                ? "达到你的商超比价线：至少省 ¥\(preferences.basketSavingsThresholdYuan)。"
                : "差价未达到你的商超比价线 ¥\(preferences.basketSavingsThresholdYuan)。"
        case .swimming:
            let threshold = Decimal(preferences.swimSingleEntryThresholdYuan)
            isNotable = lowest.price <= threshold
            thresholdDetail = lowest.price <= threshold
                ? "最低价 ¥\(Self.yuan(lowest.price)) 不高于你的游泳单次线 ¥\(preferences.swimSingleEntryThresholdYuan)。"
                : "最低价 ¥\(Self.yuan(lowest.price)) 仍高于你的游泳单次线 ¥\(preferences.swimSingleEntryThresholdYuan)。"
        case .gym, .sharedBike:
            isNotable = difference > 0
            thresholdDetail = difference > 0 ? "已按相同条件找出更低价；请再确认有效期和限制。" : nil
        }
        symbol = isNotable ? "checkmark.circle.fill" : "equal.circle"
    }

    private static func yuan(_ value: Decimal) -> String {
        String(format: "%.2f", NSDecimalNumber(decimal: value).doubleValue)
    }
}

private struct WeeklyReportPreviewForm: View {
    let privateData: PrivateCoachData
    /// This is only a local identity token for the parent callback; it is never embedded in the
    /// report or an external payload.
    let ownerID: UUID
    let onConfirm: (SharedWeeklyReport, UUID) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var goalProgress = ""
    @State private var reflection = ""
    @State private var helpRequest = ""
    @State private var confirmed = false

    private var weekStart: Date {
        Calendar.current.dateInterval(of: .weekOfYear, for: .now)?.start ?? Calendar.current.startOfDay(for: .now)
    }

    private var selection: WeeklyReportSelection {
        WeeklyReportSelection(goalProgress: goalProgress.nilIfBlank, subjectiveReflection: reflection.nilIfBlank, helpRequest: helpRequest.nilIfBlank)
    }

    private var preview: WeeklyReportPreview {
        WeeklyReportSharing.preview(from: privateData, weekStart: weekStart, selection: selection)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("你选择写进周报的内容") {
                    TextField("本周进展（可留空）", text: $goalProgress, axis: .vertical)
                    TextField("主观感受（可留空）", text: $reflection, axis: .vertical)
                    TextField("希望朋友怎样支持（可留空）", text: $helpRequest, axis: .vertical)
                }
                Section("预览") {
                    LabeledContent("完成率", value: "\(Int((preview.completionRate * 100).rounded()))%")
                    if let goalProgress = selection.goalProgress { Text("进展：\(goalProgress)") }
                    if let reflection = selection.subjectiveReflection { Text("感受：\(reflection)") }
                    if let helpRequest = selection.helpRequest { Text("需要：\(helpRequest)") }
                    Text("不包含：姓名、资料标识或位置，健康状态、HealthKit 摘要、照片、餐食与训练明细、预算或完整私有资料。此页不会发送任何内容。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    Toggle("我确认仅生成这份本地精简周报", isOn: $confirmed)
                    Text("生成后仍未发送；未来如需对外分享，必须在单独的系统分享步骤再次由你确认。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("本周周报预览")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确认生成") {
                        guard let report = WeeklyReportSharing.makeReport(from: privateData, weekStart: weekStart, selection: selection, confirmed: confirmed) else { return }
                        onConfirm(report, ownerID)
                        dismiss()
                    }
                    .disabled(!confirmed)
                }
            }
        }
    }
}

private struct OwnerExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    let data: Data

    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

private struct HealthHomeView: View {
    @Binding var plan: TodayPlan
    @Binding var privateData: PrivateCoachData
    let onPersistImmediately: (PrivateCoachData) -> Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showingHealthStatus = false
    @State private var snapshot: HealthSnapshot?
    @State private var status = "尚未请求访问"
    @State private var isWorking = false
    @State private var baselineText = ""
    @State private var recoveryDecision: HealthRecoveryDecision?
    @State private var weeklyWeightText = ""
    @State private var weeklyWaistText = ""
    @State private var weeklyNote = ""
    @State private var weeklyReviewStatus: String?
    @State private var showingExpense = false
    @State private var showingHealthExportFileImporter = false
    @State private var isImportingHealthExport = false
    @State private var healthExportPreview: AppleHealthExportPreview?
    @State private var healthExportImportStatus: String?
    @State private var showingImportedWeightConfirmation = false
    @State private var showingHealthSummaryWeightConfirmation = false
    @State private var showingWorkoutEvidence = false
    @State private var workoutImportStatus: String?
    @State private var showingWorkoutBatchConfirmation = false
    @State private var pendingEligibleWorkouts: [HealthWorkoutSummary] = []

    private var currentWeekStart: Date {
        WeeklyReviewService.weekStart()
    }

    private var weeklyReview: WeeklyReviewSummary {
        WeeklyReviewService.summary(for: currentWeekStart, data: privateData, asOf: .now)
    }

    private var weeklyCompletionValue: String {
        guard weeklyReview.observedPlanDays > 0 else { return "待开始" }
        let percent = Int((weeklyReview.completionRate * 100).rounded())
        return "\(percent)%"
    }

    private var weeklyCompletionDetail: String {
        guard weeklyReview.observedPlanDays > 0 else { return "本机打卡 · 尚无已过计划日" }
        return "本机打卡 · 已过 \(weeklyReview.observedPlanDays) 天"
    }

    private var todayStatus: DailyHealthStatusSummary? {
        HealthCheckInService.summary(for: plan.date, in: privateData)
    }

    /// 准备日和阶段评估日可记录本人状态、读取一次性摘要，但不作为第 1–56 天的训练日。
    private var isFormalPlanDay: Bool {
        PlanSchedule.dayIndex(for: plan.date) != nil
    }

    private var pendingWorkoutCandidates: [HealthWorkoutSummary] {
        guard let snapshot else { return [] }
        return snapshot.recentWorkouts.filter { workout in
            !privateData.importedWorkoutRecords.contains {
                abs($0.startedAt.timeIntervalSince(workout.startedAt)) < 1
                    && $0.kind == workout.kind
                    && $0.durationMinutes == workout.durationMinutes
            }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HealthTodayCard(
                        status: todayStatus,
                        isFormalPlanDay: isFormalPlanDay,
                        onRecord: { showingHealthStatus = true }
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                Section {
                    HealthSyncHeroCard(
                        isWorking: isWorking,
                        status: status,
                        onSync: { Task { await requestAndLoad(requestAuthorization: true) } }
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                Section("关键指标") {
                    LazyVGrid(
                        columns: dynamicTypeSize.isAccessibilitySize
                            ? [GridItem(.flexible())]
                            : [GridItem(.flexible()), GridItem(.flexible())],
                        spacing: 10
                    ) {
                        HealthMetricTile(
                            title: "睡眠",
                            value: snapshot?.sleepHoursLastNight.map { String(format: "%.1f 小时", $0) }
                                ?? weeklyReview.averageSleepHours.map { String(format: "周均 %.1f 小时", $0) }
                                ?? "待记录",
                            detail: snapshot?.sleepHoursLastNight == nil ? "手动记录 · 本周均值" : snapshotMetricDetail("昨晚"),
                            symbol: "bed.double.fill",
                            tint: CoachPalette.action
                        )
                        HealthMetricTile(
                            title: "体重",
                            value: snapshot?.weightKg.map { String(format: "%.1f kg", $0) }
                                ?? weeklyReview.latestWeightKg.map { String(format: "%.1f kg", $0) }
                                ?? "待记录",
                            detail: snapshot?.weightKg == nil ? "手动记录 · 最近周趋势" : snapshotMetricDetail("近 30 天最新"),
                            symbol: "scalemass.fill",
                            tint: CoachPalette.partial
                        )
                        HealthMetricTile(
                            title: "腰围",
                            value: weeklyReview.latestWaistCm.map { String(format: "%.1f cm", $0) } ?? "待记录",
                            detail: "手动记录 · 最近周趋势",
                            symbol: "ruler.fill",
                            tint: CoachPalette.recovery
                        )
                        HealthMetricTile(
                            title: "本周执行",
                            value: weeklyCompletionValue,
                            detail: weeklyCompletionDetail,
                            symbol: "chart.bar.fill",
                            tint: CoachPalette.completed
                        )
                    }
                    .padding(.vertical, 4)
                }

                Section("本周") {
                    WeeklyExecutionTrajectory(days: weeklyReview.executionDays)
                        .padding(.vertical, 4)
                    VStack(alignment: .leading, spacing: 6) {
                        Label(weeklyReview.suggestedVariable.displayName, systemImage: "target")
                            .font(.headline)
                            .foregroundStyle(CoachPalette.action)
                        Text(weeklyReview.suggestion)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    NavigationLink {
                        WeeklyHealthReviewView(
                            review: weeklyReview,
                            weightText: $weeklyWeightText,
                            waistText: $weeklyWaistText,
                            note: $weeklyNote,
                            message: weeklyReviewStatus,
                            hasCheckIn: hasCurrentWeekCheckIn,
                            onSave: saveWeeklyCheckIn,
                            onClear: clearWeeklyCheckIn
                        )
                    } label: {
                        Label(hasCurrentWeekCheckIn ? "查看并更新本周复盘" : "填写体重、腰围与本周复盘", systemImage: "chart.line.uptrend.xyaxis")
                    }
                }

                Section("数据") {
                    #if os(iOS) && canImport(HealthKit)
                    if let weight = snapshot?.weightKg, healthExportPreview == nil {
                        Button {
                            showingHealthSummaryWeightConfirmation = true
                        } label: {
                            Label("采用读取到的 \(String(format: "%.1f", weight)) kg 到体重趋势", systemImage: "checkmark.shield.fill")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    #endif
                    Button {
                        showingHealthExportFileImporter = true
                    } label: {
                        Label("从 Apple 健康导出 ZIP 本机预览", systemImage: "doc.zipper")
                    }
                    .disabled(isImportingHealthExport)
                    if isImportingHealthExport {
                        ProgressView("正在本机解析；大型导出可能需要几分钟")
                    }
                    if let healthExportImportStatus {
                        Text(healthExportImportStatus)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let healthExportPreview {
                        if let weight = healthExportPreview.snapshot.weightKg,
                           healthExportPreview.latestWeightRecordedAt != nil {
                            Button {
                                showingImportedWeightConfirmation = true
                            } label: {
                            Label("采用导入的 \(String(format: "%.1f", weight)) kg 到体重趋势", systemImage: "checkmark.shield.fill")
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        NavigationLink {
                            AppleHealthExportPreviewView(
                                preview: healthExportPreview,
                                onAdoptWeight: adoptImportedWeight
                            )
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Label("查看导出摘要", systemImage: "doc.text.magnifyingglass")
                                Text("截至 \(healthExportPreview.exportDate.formatted(date: .abbreviated, time: .shortened)) · 原始样本未保存")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Text("只读取你手动选择的 ZIP；不上传、不改原文件。解压的 XML 在解析结束前删除，预览本身不写入打卡。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    NavigationLink {
                        HealthDataPermissionsView(
                            snapshot: snapshot,
                            recoveryDecision: recoveryDecision,
                            status: status,
                            isWorking: isWorking,
                            isFormalPlanDay: isFormalPlanDay,
                            hasBaseline: privateData.profile.restingHeartRateBaseline != nil,
                            baselineText: $baselineText,
                            onRequest: { Task { await requestAndLoad(requestAuthorization: true) } },
                            onSaveBaseline: saveBaseline,
                            onClearBaseline: clearBaseline
                        )
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Label("Apple 健康与数据权限", systemImage: "heart.text.square")
                            Text(snapshot?.hasAnyReadableMetric == true ? "摘要已读取 · 点此查看来源与权限" : "查看读取范围与权限")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Section("训练记录") {
                    let eligibleWorkouts = HealthWorkoutImportPolicy.eligible(
                        snapshot?.recentWorkouts ?? [],
                        minimumMinutes: privateData.profile.sustainableGoal?.minimumMinutes ?? 10,
                        imported: privateData.importedWorkoutRecords
                    )
                    if !eligibleWorkouts.isEmpty {
                        let minimumMinutes = privateData.profile.sustainableGoal?.minimumMinutes ?? 10
                        Button {
                            pendingEligibleWorkouts = eligibleWorkouts
                            showingWorkoutBatchConfirmation = true
                        } label: {
                            Label("一键采用 \(eligibleWorkouts.count) 条达标运动", systemImage: "checkmark.seal.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(CoachPalette.action)
                        Text("已发现 \(eligibleWorkouts.count) 条达到每次最低 \(minimumMinutes) 分钟的运动；确认后一次录入本机训练轨迹。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else if snapshot != nil, !pendingWorkoutCandidates.isEmpty {
                        let minimumMinutes = privateData.profile.sustainableGoal?.minimumMinutes ?? 10
                        Text("已同步最近 7 天运动；当前没有新的运动达到每次最低 \(minimumMinutes) 分钟。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if !privateData.importedWorkoutRecords.isEmpty {
                        ForEach(privateData.importedWorkoutRecords.sorted { $0.startedAt > $1.startedAt }.prefix(8)) { record in
                            HStack(spacing: 10) {
                                Image(systemName: record.kind == .cycling ? "bicycle" : record.kind == .swimming ? "figure.pool.swim" : "figure.walk")
                                    .foregroundStyle(CoachPalette.completed)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(record.kind.displayName)
                                        .font(.subheadline.weight(.semibold))
                                    Text("\(record.startedAt.formatted(date: .abbreviated, time: .shortened)) · \(record.durationMinutes) 分钟 · \(record.source.displayName)")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(CoachPalette.completed)
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 6)
                            .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(.quaternary, lineWidth: 1)
                                    .allowsHitTesting(false)
                            }
                            .listRowBackground(Color.clear)
                            .accessibilityElement(children: .combine)
                        }
                    }
                    if let snapshot, !snapshot.recentWorkouts.isEmpty {
                        ForEach(pendingWorkoutCandidates.prefix(5)) { workout in
                            HStack(spacing: 10) {
                                Image(systemName: workout.kind == .cycling ? "bicycle" : workout.kind == .swimming ? "figure.pool.swim" : "figure.walk")
                                    .foregroundStyle(CoachPalette.action)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(workout.kind.displayName)
                                        .font(.subheadline.weight(.semibold))
                                    Text("\(workout.startedAt.formatted(date: .abbreviated, time: .shortened)) · \(workout.durationMinutes) 分钟")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("采用") { importHealthWorkout(workout) }
                                    .buttonStyle(.bordered)
                                    .tint(CoachPalette.action)
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 6)
                            .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(.quaternary, lineWidth: 1)
                                    .allowsHitTesting(false)
                            }
                            .listRowBackground(Color.clear)
                            .accessibilityElement(children: .contain)
                        }
                        if pendingWorkoutCandidates.isEmpty {
                            Text("最近 7 天的运动都已采用；不会重复保存。")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Text("Apple 健康只提供运动原始摘要；点“采用”后才会保存到本机训练轨迹，不会改 Apple 健康或自动重排计划。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        let minimumMinutes = privateData.profile.sustainableGoal?.minimumMinutes ?? 10
                        let belowMinimumCount = pendingWorkoutCandidates.filter {
                            $0.durationMinutes > 0 && $0.durationMinutes < minimumMinutes
                        }.count
                        if belowMinimumCount > 0 {
                            Text("有 \(belowMinimumCount) 条运动低于当前每次最低 \(minimumMinutes) 分钟，未自动列入目标进度；仍可按需逐条采用。")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("同步 Apple 健康后，这里会列出最近 7 天可核对的运动。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    #if os(iOS) && canImport(PhotosUI)
                    Button {
                        showingWorkoutEvidence = true
                    } label: {
                        Label("上传训练截图并补录", systemImage: "photo.on.rectangle")
                    }
                    Text("截图只作本机核对依据；不会自动识别时长或类型，保存前请你确认日期、运动和分钟数。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    #endif
                    if let workoutImportStatus {
                        Text(workoutImportStatus)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("健康")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            .listStyle(.insetGrouped)
            #endif
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    if isFormalPlanDay {
                        GlobalQuickLogMenu(
                            onHealth: { showingHealthStatus = true },
                            onExpense: { showingExpense = true }
                        )
                    }
                }
            }
        }
        .onAppear {
            if let baseline = privateData.profile.restingHeartRateBaseline,
               HealthKitSafetyBridge.hasUsableRestingHeartRateBaseline(baseline) {
                baselineText = String(format: "%.0f", baseline)
            } else if privateData.profile.restingHeartRateBaseline != nil {
                status = "已保存的静息心率基线数值异常，暂未参与恢复判断；请重新确认或清除。"
            }
            loadWeeklyCheckIn()
        }
        .task(id: privateData.profile.id) {
            guard snapshot == nil else { return }
            await requestAndLoad(requestAuthorization: false)
        }
        // HealthKit summaries are deliberately transient and describe the day on which the
        // owner asked to read them. An open Health tab can survive the app shell's midnight
        // plan refresh, so discard that old-day screen state rather than presenting it as a
        // summary or recovery decision for the newly active day.
        .onChange(of: plan.date) { previousDate, currentDate in
            guard !Calendar.current.isDate(previousDate, inSameDayAs: currentDate) else { return }
            snapshot = nil
            recoveryDecision = nil
            status = "日期已切换；上一天的 Apple 健康摘要未保留。需要时请主动读取今天的摘要。"
            loadWeeklyCheckIn()
        }
        .sheet(isPresented: $showingHealthStatus) {
            HealthStatusForm(planDate: plan.date, isFormalPlanDay: isFormalPlanDay, ownerID: privateData.profile.id) { status, submissionID, formOwnerID in
                let result = HealthCheckInService.submit(status, submissionID: submissionID, formOwnerID: formOwnerID, at: .now, plan: plan, data: privateData)
                if let error = result.validationError { return error }
                do {
                    try CoachPrivateStorage.saveLastOwnerData(result.data)
                } catch {
                    return "状态暂未保存；今天的训练与餐卡没有改变。请勿删除 App，确认设备存储可用后重试。"
                }
                plan = result.plan
                privateData = result.data
                showingHealthStatus = false
                return nil
            }
        }
        .sheet(isPresented: $showingExpense) {
            QuickExpenseForm(privateData: $privateData, onPersistImmediately: onPersistImmediately)
        }
        #if os(iOS) && canImport(PhotosUI)
        .sheet(isPresented: $showingWorkoutEvidence) {
            WorkoutEvidenceForm(privateData: $privateData, onPersistImmediately: onPersistImmediately) { message in
                workoutImportStatus = message
            }
        }
        #endif
        .fileImporter(
            isPresented: $showingHealthExportFileImporter,
            allowedContentTypes: [.zip],
            allowsMultipleSelection: false,
            onCompletion: handleHealthExportSelection
        )
        .confirmationDialog("采用导入体重到本周趋势？", isPresented: $showingImportedWeightConfirmation, titleVisibility: .visible) {
            Button("确认采用") {
                if let healthExportPreview {
                    healthExportImportStatus = adoptImportedWeight(healthExportPreview)
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("只保存最近一条聚合体重到本机周趋势；不保存健康原始样本，不会自动改变目标、训练或餐卡。")
        }
        .confirmationDialog("采用 Apple 健康体重到本周趋势？", isPresented: $showingHealthSummaryWeightConfirmation, titleVisibility: .visible) {
            Button("确认采用") {
                healthExportImportStatus = adoptHealthSummaryWeight()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("只把你刚读取并确认的体重保存为本周趋势点；不保存 HealthKit 原始样本，不自动改变目标、训练或餐卡。")
        }
        .confirmationDialog("一次采用符合条件的运动？", isPresented: $showingWorkoutBatchConfirmation, titleVisibility: .visible) {
            Button("确认采用 \(pendingEligibleWorkouts.count) 条") {
                importHealthWorkouts(pendingEligibleWorkouts)
            }
            Button("取消", role: .cancel) {}
        } message: {
            let minimumMinutes = privateData.profile.sustainableGoal?.minimumMinutes ?? 10
            let details = pendingEligibleWorkouts.prefix(4).map {
                "\($0.startedAt.formatted(date: .abbreviated, time: .shortened)) · \($0.kind.displayName) · \($0.durationMinutes) 分钟"
            }.joined(separator: "\n")
            let suffix = pendingEligibleWorkouts.count > 4 ? "\n…其余 \(pendingEligibleWorkouts.count - 4) 条" : ""
            Text("仅保存达到每次最低 \(minimumMinutes) 分钟的运动摘要到本机，不改 Apple 健康、不自动完成正式训练，也不重排后续计划。\n\(details)\(suffix)")
        }
    }

    private func snapshotMetricDetail(_ window: String) -> String {
        guard let snapshot else { return window }
        if snapshot.source.contains("导出") {
            return "历史导出 · \(snapshot.fetchedAt.formatted(date: .numeric, time: .omitted))"
        }
        return "Apple 健康 · \(window)"
    }

    private func importHealthWorkout(_ workout: HealthWorkoutSummary) {
        guard workout.durationMinutes > 0 else { workoutImportStatus = "这条运动没有有效时长，未保存。"; return }
        if privateData.importedWorkoutRecords.contains(where: {
            abs($0.startedAt.timeIntervalSince(workout.startedAt)) < 1 && $0.kind == workout.kind && $0.durationMinutes == workout.durationMinutes
        }) {
            workoutImportStatus = "这条 Apple 健康运动已经采用过，不会重复保存。"
            return
        }
        var updated = privateData
        updated.importedWorkoutRecords.append(ImportedWorkoutRecord(startedAt: workout.startedAt, endedAt: workout.endedAt, kind: workout.kind, source: .appleHealth))
        guard onPersistImmediately(updated) else { workoutImportStatus = "训练暂未保存；原有记录没有改变。"; return }
        privateData = updated
        workoutImportStatus = "已保存 \(workout.kind.displayName) \(workout.durationMinutes) 分钟到本机训练轨迹；计划不会自动重排。"
    }

    private func importHealthWorkouts(_ workouts: [HealthWorkoutSummary]) {
        let eligible = HealthWorkoutImportPolicy.eligible(
            workouts,
            minimumMinutes: privateData.profile.sustainableGoal?.minimumMinutes ?? 10,
            imported: privateData.importedWorkoutRecords
        )
        guard !eligible.isEmpty else {
            workoutImportStatus = "没有新的达标运动需要采用；已有记录不会重复保存。"
            return
        }
        var updated = privateData
        updated.importedWorkoutRecords.append(contentsOf: eligible.map {
            ImportedWorkoutRecord(startedAt: $0.startedAt, endedAt: $0.endedAt, kind: $0.kind, source: .appleHealth)
        })
        guard onPersistImmediately(updated) else {
            workoutImportStatus = "运动暂未保存；原有记录没有改变。"
            return
        }
        privateData = updated
        pendingEligibleWorkouts = []
        workoutImportStatus = "已一次采用 \(eligible.count) 条 Apple 健康运动；共 \(eligible.reduce(0) { $0 + $1.durationMinutes }) 分钟。计划不会自动重排。"
    }

    private func handleHealthExportSelection(_ selection: Result<[URL], Error>) {
        guard !isImportingHealthExport else { return }
        guard case let .success(urls) = selection, let url = urls.first else {
            if case let .failure(error) = selection,
               (error as NSError).code != NSUserCancelledError {
                healthExportImportStatus = "没有读取导出 ZIP；本机健康记录未改变。"
            }
            return
        }
        isImportingHealthExport = true
        healthExportImportStatus = "正在本机读取 Apple 健康导出；不上传、不写入打卡。"
        Task { @MainActor in
            do {
                let preview = try await Task.detached(priority: .userInitiated) {
                    try AppleHealthExportImporter.preview(fromArchiveAt: url)
                }.value
                healthExportPreview = preview
                snapshot = preview.snapshot
                recoveryDecision = nil
                healthExportImportStatus = "已生成本机历史摘要；未保存原始样本，也未用它调整今天训练。"
            } catch let error as LocalizedError {
                healthExportPreview = nil
                healthExportImportStatus = error.errorDescription ?? "导出 ZIP 未能解析；本机健康记录未改变。"
            } catch {
                healthExportPreview = nil
                healthExportImportStatus = "导出 ZIP 未能解析；本机健康记录未改变。"
            }
            isImportingHealthExport = false
        }
    }

    private func adoptImportedWeight(_ preview: AppleHealthExportPreview) -> String {
        guard let result = AppleHealthWeightAdoption.adopting(
            preview: preview,
            in: privateData,
            confirmed: true
        ) else {
            return "这份导出没有可采用的体重，或测量时间在未来；本机趋势未改变。"
        }
        if result.wasAlreadySaved {
            return "这条导出体重已保存过；未重复新增趋势点。"
        }
        guard onPersistImmediately(result.data) else {
            return "体重趋势暂未保存；原有周趋势和其他记录都没有改变。"
        }
        privateData = result.data
        loadWeeklyCheckIn()
        return "已将 \(String(format: "%.1f", result.weightKg)) kg 保存到 \(result.weekStart.formatted(date: .abbreviated, time: .omitted)) 开始的周趋势；未导入原始样本，不会自动改目标或训练。"
    }

    private func adoptHealthSummaryWeight() -> String {
        guard let snapshot,
              let weight = snapshot.weightKg,
              weight.isFinite, (20...400).contains(weight),
              !snapshot.source.contains("导出") else {
            return "当前没有可采用的实时 Apple 健康体重；本机趋势未改变。"
        }
        let weekStart = WeeklyReviewService.weekStart(for: snapshot.fetchedAt)
        let existing = privateData.weeklyBodyCheckIns.first {
            Calendar.current.isDate($0.weekStart, inSameDayAs: weekStart)
        }
        if existing?.weightKg == weight, existing?.weightSource == .confirmedHealthKitSummary {
            return "这条 Apple 健康体重已经确认过，不会重复记录。"
        }
        let replacement = WeeklyBodyCheckIn(
            id: existing?.id ?? UUID(),
            weekStart: weekStart,
            recordedAt: snapshot.fetchedAt,
            weightKg: weight,
            weightSource: .confirmedHealthKitSummary,
            weightMeasuredAt: snapshot.fetchedAt,
            waistCm: existing?.waistCm,
            note: existing?.note
        )
        var updatedData = privateData
        updatedData.weeklyBodyCheckIns.removeAll {
            Calendar.current.isDate($0.weekStart, inSameDayAs: weekStart)
        }
        updatedData.weeklyBodyCheckIns.append(replacement)
        guard onPersistImmediately(updatedData) else {
            return "体重暂未保存；原有记录没有改变。"
        }
        privateData = updatedData
        loadWeeklyCheckIn()
        return "已把 \(String(format: "%.1f", weight)) kg 保存为本人确认的 Apple 健康摘要体重；可在健康趋势和目标进度中查看。"
    }

    private func saveBaseline() {
        let trimmedBaseline = baselineText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Double(trimmedBaseline), HealthKitSafetyBridge.hasUsableRestingHeartRateBaseline(value) else {
            status = "请输入 20–250 次/分的有效静息心率基线，或留空不使用心率自动退阶。"
            return
        }
        var updatedData = privateData
        updatedData.profile.restingHeartRateBaseline = value
        guard onPersistImmediately(updatedData) else {
            status = "静息心率基线暂未保存；当前恢复判断没有改变。"
            return
        }
        privateData = updatedData
        status = "已保存私有基线。只有静息心率高于该基线至少 8 次/分时，才会自动切换恢复版。"
    }

    private func clearBaseline() {
        var updatedData = privateData
        updatedData.profile.restingHeartRateBaseline = nil
        guard onPersistImmediately(updatedData) else {
            status = "静息心率基线暂未清除；当前恢复判断没有改变。"
            return
        }
        privateData = updatedData
        baselineText = ""
        recoveryDecision = nil
        status = "已清除本机静息心率基线。以后不会仅因心率触发自动退阶；睡眠和你手动记录的风险状态仍按原规则保护。"
    }

    private var hasCurrentWeekCheckIn: Bool {
        privateData.weeklyBodyCheckIns.contains { Calendar.current.isDate($0.weekStart, inSameDayAs: currentWeekStart) }
    }

    private func loadWeeklyCheckIn() {
        // This view can remain alive across a Monday midnight. Clear the editable draft first:
        // without that, last week's values could be accidentally saved as a new trend point in
        // the new week merely because no current-week record exists yet.
        weeklyWeightText = ""
        weeklyWaistText = ""
        weeklyNote = ""
        weeklyReviewStatus = nil
        guard let checkIn = privateData.weeklyBodyCheckIns.first(where: { Calendar.current.isDate($0.weekStart, inSameDayAs: currentWeekStart) }) else { return }
        weeklyWeightText = checkIn.weightKg.map { String(format: "%.1f", $0) } ?? ""
        weeklyWaistText = checkIn.waistCm.map { String(format: "%.1f", $0) } ?? ""
        weeklyNote = checkIn.note ?? ""
    }

    private func saveWeeklyCheckIn() {
        let trimmedWeight = weeklyWeightText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedWaist = weeklyWaistText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedWeight.isEmpty || Double(trimmedWeight) != nil,
              trimmedWaist.isEmpty || Double(trimmedWaist) != nil else {
            weeklyReviewStatus = "体重和腰围请填写有效数字，或留空。"
            return
        }
        let weight = Double(trimmedWeight)
        let waist = Double(trimmedWaist)
        guard (weight == nil || (weight!.isFinite && (20...400).contains(weight!))),
              (waist == nil || (waist!.isFinite && (30...300).contains(waist!))) else {
            weeklyReviewStatus = "体重如填写需在 20–400 kg，腰围需在 30–300 cm；也可以只保存备注。"
            return
        }
        guard weight != nil || waist != nil || weeklyNote.nilIfBlank != nil else {
            weeklyReviewStatus = "请至少填写体重、腰围或一条备注；如要删除已有记录，请使用“清除本周趋势点”。"
            return
        }
        let existing = privateData.weeklyBodyCheckIns.first { Calendar.current.isDate($0.weekStart, inSameDayAs: currentWeekStart) }
        let replacement = WeeklyBodyCheckIn(
            id: existing?.id ?? UUID(),
            weekStart: currentWeekStart,
            weightKg: weight,
            waistCm: waist,
            note: weeklyNote.nilIfBlank
        )
        var updatedData = privateData
        updatedData.weeklyBodyCheckIns.removeAll { Calendar.current.isDate($0.weekStart, inSameDayAs: currentWeekStart) }
        updatedData.weeklyBodyCheckIns.append(replacement)
        guard onPersistImmediately(updatedData) else {
            weeklyReviewStatus = "本周趋势点暂未保存；原有记录没有改变。"
            return
        }
        privateData = updatedData
        weeklyReviewStatus = "已保存为本机私有周趋势点；本周复盘只给一个建议，不会自动改计划。"
    }

    private func clearWeeklyCheckIn() {
        var updatedData = privateData
        updatedData.weeklyBodyCheckIns.removeAll { Calendar.current.isDate($0.weekStart, inSameDayAs: currentWeekStart) }
        guard onPersistImmediately(updatedData) else {
            weeklyReviewStatus = "本周趋势点暂未清除；原有记录没有改变。"
            return
        }
        privateData = updatedData
        weeklyWeightText = ""
        weeklyWaistText = ""
        weeklyNote = ""
        weeklyReviewStatus = "已清除本周私有趋势点；这不会影响 Apple 健康 App 的任何数据。"
    }

    private func trendValue(_ value: Double, change: Double?, unit: String) -> String {
        let valueText = String(format: "%.1f %@", value, unit)
        guard let change else { return valueText }
        return "\(valueText)（较上次\(String(format: "%+.1f", change)) \(unit)）"
    }

    @MainActor private func requestAndLoad(requestAuthorization: Bool) async {
        // The visible button disables quickly, but retain the same boundary here in case an
        // accessibility action or queued tap reaches this async method before a redraw.
        guard !isWorking else { return }
        // The asynchronous HealthKit permission/read flow belongs to the plan day that was
        // visible when the owner tapped. If midnight changes the bound day while HealthKit is
        // presenting a permission sheet or returning samples, those results must never be
        // interpreted as today's status or cause a new-day recovery downgrade.
        let requestedPlanDate = plan.date
        // Capture the owner at the explicit read action. A full local-data deletion can finish
        // while the permission sheet or HealthKit query is suspended; its old result must not
        // appear in, or apply a recovery change to, a newly created profile.
        let ownerID = privateData.profile.id
        isWorking = true
        status = requestAuthorization ? "正在请求权限并同步 Apple 健康…" : "正在读取已授权的 Apple 健康摘要…"
        defer { isWorking = false }
        #if os(iOS) && canImport(HealthKit)
        do {
            let provider = NativeHealthKitProvider(permissionPlan: .readOnly)
            if requestAuthorization {
                try await provider.requestAuthorization()
            }
            // Authorization itself may have kept this task suspended while the owner deleted
            // the local profile. Do not start a new sensitive HealthKit read for that deleted
            // profile merely to discard the result later.
            guard PrivateProfileAsyncOwnershipGate.mayContinue(
                capturedOwnerID: ownerID,
                currentOwnerID: privateData.profile.id
            ) else {
                snapshot = nil
                recoveryDecision = nil
                status = "本机资料已删除或切换；没有继续读取旧资料的 Apple 健康摘要。"
                return
            }
            let loadedSnapshot = try await provider.readSummary().sanitizedForDisplay()
            guard Calendar.current.isDate(plan.date, inSameDayAs: requestedPlanDate),
                  PrivateProfileAsyncOwnershipGate.mayContinue(
                    capturedOwnerID: ownerID,
                    currentOwnerID: privateData.profile.id
                  ) else {
                snapshot = nil
                recoveryDecision = nil
                status = Calendar.current.isDate(plan.date, inSameDayAs: requestedPlanDate)
                    ? "读取期间本机资料已删除或切换；旧资料的 Apple 健康摘要未用于新资料。需要时请主动重新读取。"
                    : "读取期间日期已切换；上一天的 Apple 健康结果未用于今天。需要时请主动读取今天的摘要。"
                return
            }
            snapshot = loadedSnapshot
            if requestAuthorization {
                let eligible = HealthWorkoutImportPolicy.eligible(
                    loadedSnapshot.recentWorkouts,
                    minimumMinutes: privateData.profile.sustainableGoal?.minimumMinutes ?? 10,
                    imported: privateData.importedWorkoutRecords
                )
                if !eligible.isEmpty {
                    pendingEligibleWorkouts = eligible
                    showingWorkoutBatchConfirmation = true
                }
            }
            guard let currentSnapshot = snapshot, currentSnapshot.hasAnyReadableMetric else {
                recoveryDecision = nil
                status = requestAuthorization
                    ? "本次没有可读的 Apple 健康摘要：可能未授权、尚无对应记录或数据暂不可用。若运动没有显示，请在“健康 → 共享 → App → YouyeHealthCoach”允许读取“锻炼记录”后再同步。App 不会补造数据。"
                    : "没有自动读取到已授权摘要。点“立即同步 Apple 健康”可检查权限并重试；App 不会补造数据。"
                return
            }
            recoveryDecision = HealthKitSafetyBridge.recoveryDecision(snapshot: currentSnapshot, restingHeartRateBaseline: privateData.profile.restingHeartRateBaseline)
            let appliedAt = Date()
            guard Calendar.current.isDate(plan.date, inSameDayAs: requestedPlanDate),
                  Calendar.current.isDate(appliedAt, inSameDayAs: requestedPlanDate),
                  PrivateProfileAsyncOwnershipGate.mayContinue(
                    capturedOwnerID: ownerID,
                    currentOwnerID: privateData.profile.id
                  ) else {
                snapshot = nil
                recoveryDecision = nil
                status = Calendar.current.isDate(plan.date, inSameDayAs: requestedPlanDate)
                    ? "读取期间本机资料已删除或切换；旧资料的 Apple 健康摘要未用于新资料。需要时请主动重新读取。"
                    : "读取期间日期已切换；上一天的 Apple 健康结果未用于今天。需要时请主动读取今天的摘要。"
                return
            }
            if let application = HealthKitSafetyBridge.applyOncePerProtectedDay(
                snapshot: currentSnapshot,
                restingHeartRateBaseline: privateData.profile.restingHeartRateBaseline,
                at: appliedAt,
                plan: plan,
                data: privateData
            ) {
                switch application {
                case let .applied(applied):
                    // A protective downgrade changes both the visible day card and the private
                    // audit trail.  Persist that paired state before presenting the change: a
                    // failed local write must not show a recovery day that disappears after a
                    // restart, nor claim the audit was retained when it was not.
                    guard PrivateProfileAsyncOwnershipGate.mayContinue(
                        capturedOwnerID: ownerID,
                        currentOwnerID: privateData.profile.id
                    ) else {
                        snapshot = nil
                        recoveryDecision = nil
                        status = "本机资料已删除或切换；旧资料摘要没有保存或改写新资料的日卡。"
                        return
                    }
                    do {
                        try CoachPrivateStorage.saveLastOwnerData(applied.data)
                        plan = applied.plan
                        privateData = applied.data
                        status = "已读取摘要并因恢复信号切换为恢复版；原因已记入计划变更记录。"
                    } catch {
                        status = "已读取摘要并识别到恢复信号，但本机保护记录暂未保存；为避免重开后丢失，本次没有切换日卡。请勿删除 App，确认设备存储可用后再读取，或先手动记录今天状态。"
                    }
                case .alreadyProtected:
                    status = "已读取摘要；今天已经是恢复版，保留原有依据，不重复写入变更记录。"
                }
            } else {
                status = isFormalPlanDay
                    ? "已读取本次设备内摘要。没有触发自动退阶；体重、体脂、步数和活动数据不会自动改你的目标、热量或训练量。"
                    : "已读取本次设备内摘要。当前不是正式计划日，只供查看；不会创建恢复审计、改写日卡或开启下一阶段。"
            }
        } catch {
            status = HealthKitAccessMessage.readFailure(error)
        }
        #else
        status = "当前 Mac 端不读取或写入 Apple 健康；不会伪造健康数据。可继续使用手动状态和本周复盘。"
        #endif
    }
}

private struct HealthSyncHeroCard: View {
    let isWorking: Bool
    let status: String
    let onSync: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "heart.text.square.fill")
                    .font(.title2)
                    .foregroundStyle(CoachPalette.action)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Apple 健康同步")
                        .font(.headline)
                    Text("读取运动、睡眠和体重；数据只在本机核对")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            Button(action: onSync) {
                Label(isWorking ? "正在同步 Apple 健康…" : "立即同步 Apple 健康", systemImage: isWorking ? "hourglass" : "arrow.triangle.2.circlepath")
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .buttonStyle(.borderedProminent)
            .tint(CoachPalette.action)
            .disabled(isWorking)
            if isWorking {
                ProgressView("正在读取已授权的健康摘要")
                    .font(.footnote)
            } else {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(CoachPalette.action.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(CoachPalette.action.opacity(0.18), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .accessibilityElement(children: .contain)
    }
}

private struct HealthTodayCard: View {
    let status: DailyHealthStatusSummary?
    let isFormalPlanDay: Bool
    let onRecord: () -> Void

    private var isRecovery: Bool { status?.hasProtectiveSignal == true && isFormalPlanDay }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isRecovery ? "shield.lefthalf.filled" : status == nil ? "heart.text.square" : "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(isRecovery ? CoachPalette.recovery : status == nil ? CoachPalette.action : CoachPalette.completed)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 5) {
                    Text(isRecovery ? "今天恢复优先" : status == nil ? "今天感觉怎么样？" : "今天状态已记录")
                        .font(.title3.bold())
                    Text(summaryText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            Button(status == nil ? "记录今天状态" : "更新今天状态", action: onRecord)
                .buttonStyle(.borderedProminent)
                .tint(isRecovery ? CoachPalette.recovery : CoachPalette.action)
                .controlSize(.large)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background((isRecovery ? CoachPalette.recovery : CoachPalette.action).opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke((isRecovery ? CoachPalette.recovery : CoachPalette.action).opacity(0.20), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .accessibilityElement(children: .contain)
    }

    private var summaryText: String {
        if let status {
            return status.labels.prefix(4).joined(separator: " · ")
        }
        return isFormalPlanDay
            ? "记录睡眠、精力和身体感受，出现风险信号时只把今天调整为恢复版。"
            : "可记录睡眠、精力和身体感受；不创建训练打卡、恢复退阶或新计划。"
    }
}

private struct HealthMetricTile: View {
    let title: String
    let value: String
    let detail: String
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
            Text(value)
                .font(.headline.monospacedDigit())
                .fixedSize(horizontal: false, vertical: true)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 94, alignment: .topLeading)
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.quaternary, lineWidth: 1)
                .allowsHitTesting(false)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct WeeklyHealthReviewView: View {
    let review: WeeklyReviewSummary
    @Binding var weightText: String
    @Binding var waistText: String
    @Binding var note: String
    let message: String?
    let hasCheckIn: Bool
    let onSave: () -> Void
    let onClear: () -> Void

    var body: some View {
        Form {
            Section("本周复盘") {
                TextField("体重 kg（可留空）", text: $weightText)
                TextField("腰围 cm（可留空）", text: $waistText)
                TextField("这周的感受或阻碍（可留空）", text: $note, axis: .vertical)
                Button("保存本周趋势", action: onSave)
                if hasCheckIn {
                    Button("清除本周趋势", role: .destructive, action: onClear)
                }
                if let message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Text("这些记录只保存在本机，不会自动改目标、热量、训练或周结构。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("执行轨迹") {
                LabeledContent(
                    "完成率",
                    value: review.observedPlanDays == 0 ? "尚无正式计划日" : "\(Int((review.completionRate * 100).rounded()))%"
                )
                LabeledContent("明确完成训练反馈", value: "\(review.completedTrainingFeedbackDays) 天")
                Text("本周执行轨迹")
                    .font(.subheadline.weight(.semibold))
                WeeklyExecutionTrajectory(days: review.executionDays)
                if review.explicitlySkippedPlanDays > 0 {
                    Text("本周有 \(review.explicitlySkippedPlanDays) 天明确跳过；已完成项照实计入，未完成项按 0 项计。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Text("过去未记录不等于失败；明确跳过不等于忘记。跳过日只按实际完成项计入。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("这里只回顾餐卡建议与备餐执行。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("身体趋势") {
                LabeledContent("睡眠周均", value: review.averageSleepHours.map { String(format: "%.1f 小时", $0) } ?? "暂无")
                if let weight = review.latestWeightKg {
                    LabeledContent("体重", value: trendValue(weight, change: review.weightChangeKg, unit: "kg"))
                    if let source = review.latestWeightSource {
                        LabeledContent("体重来源", value: source.displayName)
                    }
                    if let measuredAt = review.latestWeightMeasuredAt {
                        LabeledContent("体重测量时间", value: measuredAt.formatted(date: .abbreviated, time: .shortened))
                    }
                }
                if let waist = review.latestWaistCm {
                    LabeledContent("腰围", value: trendValue(waist, change: review.waistChangeCm, unit: "cm"))
                }
                if !review.skinLabels.isEmpty {
                    LabeledContent("皮肤/身体", value: review.skinLabels.joined(separator: "、"))
                }
                if let note = review.weeklyNote {
                    Text("本周备注：\(note)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("下周只关注一件事") {
                Text("本周只关注一件事")
                    .font(.subheadline.weight(.semibold))
                Label(review.suggestedVariable.displayName, systemImage: "target")
                    .font(.headline)
                    .foregroundStyle(CoachPalette.action)
                Text(review.suggestion)
                    .foregroundStyle(.secondary)
                Text("下周准备清单（仅供你手动执行）")
                    .font(.subheadline.weight(.semibold))
                ForEach(review.preparationChecklist, id: \.self) { item in
                    Label(item, systemImage: "circle")
                        .font(.subheadline)
                }
                Text("这不是自动应用：不会改你的提醒时间、餐卡、热量、训练或周结构。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("这是建议，不会自动写入或修改计划。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("本周复盘")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func trendValue(_ value: Double, change: Double?, unit: String) -> String {
        let valueText = String(format: "%.1f %@", value, unit)
        guard let change else { return valueText }
        return "\(valueText)（较上次\(String(format: "%+.1f", change)) \(unit)）"
    }
}

#if os(iOS) && canImport(PhotosUI)
private struct WorkoutEvidenceForm: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var privateData: PrivateCoachData
    let onPersistImmediately: (PrivateCoachData) -> Bool
    let onResult: (String) -> Void
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var photoAttached = false
    @State private var startedAt = Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now
    @State private var durationMinutes = "60"
    @State private var kind: ConfirmedHealthWorkoutKind = .cycling
    @State private var note = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("截图（可选）") {
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label(photoAttached ? "已选择截图（仅作核对）" : "选择 Apple 健康 / 健身截图", systemImage: "photo.on.rectangle")
                    }
                    .onChange(of: selectedPhoto) { _, newValue in
                        photoAttached = newValue != nil
                    }
                    Text("不会上传或保存原图；截图里的日期、运动和时长请你在下方手动确认。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("确认训练") {
                    DatePicker("开始时间", selection: $startedAt, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                    Picker("运动类型", selection: $kind) {
                        ForEach(ConfirmedHealthWorkoutKind.allCases) { Text($0.displayName).tag($0) }
                    }
                    TextField("实际分钟数（1–1440）", text: $durationMinutes)
                        .keyboardType(.numberPad)
                    TextField("备注（可选，例如来自 Apple 健康）", text: $note, axis: .vertical)
                    if let error { Text(error).font(.footnote).foregroundStyle(CoachPalette.recovery) }
                }
                Section {
                    Button("保存到本机训练轨迹") { save() }
                        .buttonStyle(.borderedProminent)
                        .tint(CoachPalette.action)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .navigationTitle("补录训练")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        }
    }

    private func save() {
        guard let minutes = Int(durationMinutes.trimmingCharacters(in: .whitespacesAndNewlines)), (1...1_440).contains(minutes) else {
            error = "请输入 1–1440 分钟的实际时长。"
            return
        }
        let endedAt = startedAt.addingTimeInterval(TimeInterval(minutes * 60))
        guard endedAt <= Date() else { error = "结束时间不能晚于现在，请核对日期和时长。"; return }
        let source: ImportedWorkoutSource = photoAttached ? .screenshot : .manual
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if privateData.importedWorkoutRecords.contains(where: { abs($0.startedAt.timeIntervalSince(startedAt)) < 1 && $0.kind == kind && $0.durationMinutes == minutes }) {
            error = "相同时间、类型和时长的记录已存在，不会重复保存。"
            return
        }
        var updated = privateData
        updated.importedWorkoutRecords.append(ImportedWorkoutRecord(startedAt: startedAt, endedAt: endedAt, kind: kind, source: source, note: trimmedNote.isEmpty ? nil : trimmedNote))
        guard onPersistImmediately(updated) else { error = "训练暂未保存；原有记录没有改变。"; return }
        privateData = updated
        onResult("已保存 \(kind.displayName) \(minutes) 分钟（\(source.displayName)）到本机训练轨迹。")
        dismiss()
    }
}
#endif

private struct AppleHealthExportPreviewView: View {
    let preview: AppleHealthExportPreview
    let onAdoptWeight: (AppleHealthExportPreview) -> String
    @State private var showingWeightConfirmation = false
    @State private var adoptionMessage: String?

    private var snapshot: HealthSnapshot { preview.snapshot }

    var body: some View {
        Form {
            Section("导出范围") {
                LabeledContent("文件", value: preview.archiveFileName)
                LabeledContent("导出时间", value: preview.exportDate.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("参与聚合的记录", value: "\(preview.relevantRecordCount) 条")
                Label("这是历史文件摘要，不会代替今天的实时 Apple 健康读取。", systemImage: "clock.arrow.circlepath")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("本机聚合预览") {
                HealthSummaryRow(label: "体重", value: snapshot.weightKg.map { String(format: "%.1f kg", $0) })
                if let date = preview.latestWeightRecordedAt {
                    LabeledContent("体重测量时间", value: date.formatted(date: .abbreviated, time: .shortened))
                }
                HealthSummaryRow(label: "体脂", value: snapshot.bodyFatPercent.map { String(format: "%.1f%%", $0) })
                HealthSummaryRow(label: "近 14 天日均步数", value: snapshot.averageDailySteps14d.map(String.init))
                HealthSummaryRow(label: "导出时点的昨晚睡眠", value: snapshot.sleepHoursLastNight.map { String(format: "%.1f 小时", $0) })
                HealthSummaryRow(label: "静息心率", value: snapshot.restingHeartRate.map { String(format: "%.0f 次/分", $0) })
                HealthSummaryRow(label: "导出前 24 小时活动能量", value: snapshot.activeEnergyKcal.map { String(format: "%.0f kcal", $0) })
                HealthSummaryRow(label: "导出前 24 小时运动", value: snapshot.workoutMinutes.map { String(format: "%.0f 分钟", $0) })
                HealthSummaryRow(label: "其中游泳", value: snapshot.swimMinutes.map { String(format: "%.0f 分钟", $0) })
                ForEach(snapshot.availabilityNotes, id: \.self) { note in
                    Label(note, systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("可选保存") {
                if let weight = snapshot.weightKg, let measuredAt = preview.latestWeightRecordedAt {
                    Text("只可将 \(String(format: "%.1f", weight)) kg 作为 \(measuredAt.formatted(date: .abbreviated, time: .omitted)) 所在周的体重趋势点。如该周已有体重，确认后只替换体重，保留腰围和本人备注。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button {
                        showingWeightConfirmation = true
                    } label: {
                        Label("确认采用这条体重", systemImage: "checkmark.shield")
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Text("这份导出没有可采用的近 30 天体重；可继续只查看其他摘要。")
                        .foregroundStyle(.secondary)
                }
                if let adoptionMessage {
                    Text(adoptionMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section("隐私与影响") {
                Text("原始 XML 已在解析返回前删除；不保存原始样本、路线或心电图，不上传，不写入 Apple 健康。预览不会修改今天的恢复判断；仅上方体重需要你再次确认才保存。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("健康导出预览")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .confirmationDialog("采用这条体重？", isPresented: $showingWeightConfirmation, titleVisibility: .visible) {
            Button("确认保存到周趋势") {
                adoptionMessage = onAdoptWeight(preview)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("只保存一条聚合体重与测量时间；不导入其他原始样本，不会自动改目标、热量、训练或周结构。")
        }
    }
}

private struct HealthDataPermissionsView: View {
    let snapshot: HealthSnapshot?
    let recoveryDecision: HealthRecoveryDecision?
    let status: String
    let isWorking: Bool
    let isFormalPlanDay: Bool
    let hasBaseline: Bool
    @Binding var baselineText: String
    let onRequest: () -> Void
    let onSaveBaseline: () -> Void
    let onClearBaseline: () -> Void

    var body: some View {
        Form {
            Section("Apple 健康") {
                #if os(iOS) && canImport(HealthKit)
                Button(isWorking ? "正在读取…" : "读取一次健康摘要", action: onRequest)
                    .disabled(isWorking)
                Text("只读取体重、体脂、步数、睡眠、静息心率、活动能量与运动时长。这里不请求写入权限，也不读取游泳距离。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if !isFormalPlanDay {
                    Text("当前不是第 1–56 天：摘要仅供查看，不会调整日卡或创建恢复审计。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                #else
                Text("Mac 不读取或写入 Apple 健康；手动状态和周复盘仍保存在本机。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                #endif
                Text(status)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("恢复判断（可选）") {
                TextField("静息心率基线（次/分）", text: $baselineText)
                Button("保存基线", action: onSaveBaseline)
                if hasBaseline {
                    Button("清除静息心率基线", role: .destructive, action: onClearBaseline)
                }
                Text("基线必须由你确认。未填写时不会根据心率自动调整；睡眠少于 6 小时仍会保护性退阶。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let recoveryDecision {
                Section("本次恢复判断") {
                    LabeledContent("心率基线", value: recoveryDecision.baselineIsConfirmed ? "已确认" : "未设置")
                    if let delta = recoveryDecision.restingHeartRateAboveBaseline {
                        LabeledContent("相对基线", value: "\(delta >= 0 ? "+" : "")\(delta) 次/分")
                    }
                    Label(
                        recoveryDecision.reason ?? (recoveryDecision.triggersRecovery ? "已触发恢复保护" : "未触发自动退阶"),
                        systemImage: recoveryDecision.triggersRecovery ? "shield.lefthalf.filled" : "checkmark.circle"
                    )
                    .foregroundStyle(recoveryDecision.triggersRecovery ? CoachPalette.recovery : CoachPalette.completed)
                }
            }

            if let snapshot {
                Section("本次摘要") {
                    LabeledContent("数据来源", value: snapshot.source)
                    LabeledContent("最后读取", value: snapshot.fetchedAt.formatted(date: .abbreviated, time: .shortened))
                    HealthSummaryRow(label: "体重", value: snapshot.weightKg.map { String(format: "%.1f kg", $0) })
                    HealthSummaryRow(label: "体脂", value: snapshot.bodyFatPercent.map { String(format: "%.1f%%", $0) })
                    HealthSummaryRow(label: "近 14 天日均步数", value: snapshot.averageDailySteps14d.map(String.init))
                    HealthSummaryRow(label: "昨晚睡眠", value: snapshot.sleepHoursLastNight.map { String(format: "%.1f 小时", $0) })
                    HealthSummaryRow(label: "静息心率", value: snapshot.restingHeartRate.map { String(format: "%.0f 次/分", $0) })
                    HealthSummaryRow(label: "近 24 小时活动能量", value: snapshot.activeEnergyKcal.map { String(format: "%.0f kcal", $0) })
                    HealthSummaryRow(label: "最近运动", value: snapshot.workoutMinutes.map { String(format: "%.0f 分钟", $0) })
                    HealthSummaryRow(label: "最近游泳", value: snapshot.swimMinutes.map { String(format: "%.0f 分钟", $0) })
                    ForEach(snapshot.availabilityNotes, id: \.self) { note in
                        Label(note, systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("隐私边界") {
                Text("当前只读 Apple 健康摘要；实际训练仅保存在本机，不写入 Apple 健康。摘要不保存 HealthKit 原始样本，也不上传敏感数据。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("数据与权限")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

private struct HealthSummaryRow: View {
    let label: String
    let value: String?
    var body: some View { LabeledContent(label, value: value ?? "未记录") }
}

private struct PlaceholderView: View {
    let title: String
    let subtitle: String
    let symbol: String
    var body: some View {
        ContentUnavailableView(title, systemImage: symbol, description: Text(subtitle))
    }
}
#endif
