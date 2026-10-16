import Foundation

/// A camera session and an embedded streaming page can both be doing expensive first-use work.
/// Give the first Vision result longer than an ordinary refresh before declaring the monitor
/// unavailable; after at least one result, a shorter limit still closes a genuinely stalled
/// pipeline. Keeping this policy platform-neutral makes the timing rule independently testable.
public enum LocalPoseAnalysisWatchdog {
    public static let firstResultGrace: TimeInterval = 8
    public static let refreshStallLimit: TimeInterval = 3

    public static func shouldStop(
        monitoringStartedAt: Date,
        lastResultAt: Date?,
        now: Date
    ) -> Bool {
        let reference = lastResultAt ?? monitoringStartedAt
        let limit = lastResultAt == nil ? firstResultGrace : refreshStallLimit
        return now.timeIntervalSince(reference) >= limit
    }
}

#if canImport(UIKit) && canImport(Vision) && canImport(AVFoundation)
import AVFoundation
import SwiftUI
import UIKit
import Vision

/// The scope of the live local cue. This intentionally does not claim action recognition,
/// rep counting, joint-angle measurement, diagnosis, or correction.
public enum LivePoseFocus: String, Sendable, CaseIterable, Identifiable {
    case wholeBody
    case upperBodyPosture
    case trunkAlignment

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .wholeBody: "全身入镜"
        case .upperBodyPosture: "肩颈与上身"
        case .trunkAlignment: "躯干与骨盆"
        }
    }

    public static func suggested(for trainingTitle: String) -> LivePoseFocus {
        if trainingTitle.contains("体态") || trainingTitle.contains("墙面") || trainingTitle.contains("Y-T-W") {
            return .upperBodyPosture
        }
        if trainingTitle.contains("平板") || trainingTitle.contains("死虫") || trainingTitle.contains("鸟狗") || trainingTitle.contains("腰腹") || trainingTitle.contains("核心") {
            return .trunkAlignment
        }
        return .wholeBody
    }
}

public enum LivePoseCueLevel: String, Sendable {
    case ready, caution, framing, unavailable

    var systemImage: String {
        switch self {
        case .ready: "checkmark.circle.fill"
        case .caution: "exclamationmark.triangle.fill"
        case .framing: "viewfinder"
        case .unavailable: "video.slash.fill"
        }
    }
}

public struct LivePoseCue: Sendable, Equatable {
    public let text: String
    public let level: LivePoseCueLevel

    public init(_ text: String, level: LivePoseCueLevel) {
        self.text = text
        self.level = level
    }
}

/// The capture queue must observe a withdrawal immediately when the main-actor UI is dismissed,
/// while permission callbacks and camera setup may still be in flight.  Keep that one boolean
/// behind a lock instead of sharing an `unsafe` mutable flag across the two executors.
private final class CaptureStartGate: @unchecked Sendable {
    private let lock = NSLock()
    private var requested = false

    /// The public start action is main-actor isolated, but making this atomic also keeps a
    /// queued permission callback from reviving a second setup after a stop.
    func begin() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !requested else { return false }
        requested = true
        return true
    }

    func withdraw() {
        lock.lock()
        requested = false
        lock.unlock()
    }

    var isRequested: Bool {
        lock.lock()
        defer { lock.unlock() }
        return requested
    }
}

/// Converts the camera's gravity-aware rotation into the orientation Vision must apply to the
/// unrotated video-data buffer. `AVCaptureDevice.RotationCoordinator` publishes on the main
/// queue while Vision reads on the capture queue, so the tiny shared value and observer lifetime
/// stay behind one lock. No frame or landmark data is stored here.
private final class CaptureFrameOrientationMonitor: @unchecked Sendable {
    private let lock = NSLock()
    private var generation = 0
    private var orientation: CGImagePropertyOrientation = .up
    private var coordinator: AVCaptureDevice.RotationCoordinator?
    private var observation: NSKeyValueObservation?

    var current: CGImagePropertyOrientation {
        lock.lock()
        defer { lock.unlock() }
        return orientation
    }

    func start(for device: AVCaptureDevice) {
        lock.lock()
        generation += 1
        let token = generation
        let oldObservation = observation
        observation = nil
        coordinator = nil
        orientation = .up
        lock.unlock()
        oldObservation?.invalidate()

        let nextCoordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
        set(rotationAngle: nextCoordinator.videoRotationAngleForHorizonLevelCapture, token: token)
        let nextObservation = nextCoordinator.observe(
            \.videoRotationAngleForHorizonLevelCapture,
            options: [.new]
        ) { [weak self] coordinator, _ in
            self?.set(rotationAngle: coordinator.videoRotationAngleForHorizonLevelCapture, token: token)
        }

        lock.lock()
        guard generation == token else {
            lock.unlock()
            nextObservation.invalidate()
            return
        }
        coordinator = nextCoordinator
        observation = nextObservation
        lock.unlock()
    }

    func stop() {
        lock.lock()
        generation += 1
        let oldObservation = observation
        observation = nil
        coordinator = nil
        orientation = .up
        lock.unlock()
        oldObservation?.invalidate()
    }

    private func set(rotationAngle: CGFloat, token: Int) {
        var normalized = rotationAngle.truncatingRemainder(dividingBy: 360)
        if normalized < 0 { normalized += 360 }
        let quarterTurns = Int((normalized / 90).rounded()) % 4
        let next: CGImagePropertyOrientation
        switch quarterTurns {
        case 1: next = .right
        case 2: next = .down
        case 3: next = .left
        default: next = .up
        }

        lock.lock()
        if generation == token { orientation = next }
        lock.unlock()
    }
}

/// Pure, conservative frame checks for an actively selected exercise view. They only compare
/// confidently visible landmarks in the current frame; no image, video, landmark or result is persisted.
public enum LocalPoseFrameAnalyzer {
    public static func cue(
        observation: VNHumanBodyPoseObservation,
        focus: LivePoseFocus
    ) -> LivePoseCue {
        let allPoints = Array((try? observation.recognizedPoints(.all).values) ?? [:].values)
        let confidentCount = allPoints.filter { $0.confidence >= 0.35 }.count
        guard confidentCount >= 8 else {
            return LivePoseCue("实时提示：关键点不完整。退后一步，让头、躯干和双腿入镜。", level: .framing)
        }

        guard let leftShoulder = point(.leftShoulder, in: observation),
              let rightShoulder = point(.rightShoulder, in: observation) else {
            return LivePoseCue("实时提示：请让双肩清晰入镜，再开始动作。", level: .framing)
        }

        let shoulderTilt = abs(leftShoulder.location.y - rightShoulder.location.y)
        if shoulderTilt > 0.16 {
            return LivePoseCue("实时提示：双肩高度差较大。放慢，肩膀远离耳朵；不适就停止。", level: .caution)
        }

        if focus == .trunkAlignment,
           let leftHip = point(.leftHip, in: observation),
           let rightHip = point(.rightHip, in: observation) {
            let hipTilt = abs(leftHip.location.y - rightHip.location.y)
            let shoulderMidX = (leftShoulder.location.x + rightShoulder.location.x) / 2
            let hipMidX = (leftHip.location.x + rightHip.location.x) / 2
            if hipTilt > 0.18 || abs(shoulderMidX - hipMidX) > 0.22 {
                return LivePoseCue("实时提示：躯干或骨盆看起来偏向一侧。减小幅度，先做最低版并保持呼吸。", level: .caution)
            }
        }

        if focus == .upperBodyPosture {
            return LivePoseCue("实时提示：上身关键点稳定可见。保持下巴轻收、肩膀放松，按自己的节奏。", level: .ready)
        }
        if focus == .trunkAlignment {
            return LivePoseCue("实时提示：躯干关键点稳定可见。保持自然呼吸；腰痛或屏息立即停。", level: .ready)
        }
        return LivePoseCue("实时提示：全身关键点稳定可见。继续慢做，不追次数或速度。", level: .ready)
    }

    private static func point(
        _ joint: VNHumanBodyPoseObservation.JointName,
        in observation: VNHumanBodyPoseObservation
    ) -> VNRecognizedPoint? {
        guard let point = try? observation.recognizedPoint(joint), point.confidence >= 0.35 else { return nil }
        return point
    }
}

/// User-initiated front-camera coaching. Frames are discarded after a roughly four-per-second
/// Vision request; neither footage nor pose results leave the device or enter the private export.
/// This is live-only coaching: there is no recording buffer, playback, export, or session archive.
@MainActor
public final class LocalPoseCoach: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    @Published public private(set) var cue = LivePoseCue("准备启动前置摄像头", level: .unavailable)
    @Published public private(set) var isRunning = false
    @Published public private(set) var isStarting = false
    @Published public private(set) var isAwaitingAuthorization = false
    @Published public private(set) var lastUpdatedAt: Date?
    @Published public var voiceCuesEnabled = true
    public let session = AVCaptureSession()
    /// Vision runs on the capture queue, while UI state stays on the main actor. The focus is a
    /// small immutable `Sendable` value selected at sheet creation, so the frame callback may
    /// safely read it without hopping to the main actor on every frame.
    public nonisolated let focus: LivePoseFocus
    private let queue = DispatchQueue(label: "com.youye.privatehealthcoach.local-pose")
    private let speechSynthesizer = AVSpeechSynthesizer()
    private var lastSpokenText: String?
    private var lastSpokenAt = Date.distantPast
    /// A phone call, another camera client, or a capture runtime error may interrupt the session
    /// before the app itself becomes inactive.  These observers end the local-only monitor rather
    /// than leaving an old preview/state visible or attempting an automatic restart.
    private var captureNotificationTokens: [NSObjectProtocol] = []
    /// Covers the system permission-sheet race: if the user cancels safe setup while the sheet
    /// is open, a later authorization callback must not revive camera capture.
    nonisolated(unsafe) private let startGate = CaptureStartGate()
    nonisolated(unsafe) private let frameOrientationMonitor = CaptureFrameOrientationMonitor()
    nonisolated(unsafe) private var lastAnalysis = Date.distantPast
    /// A live preview is not proof that Vision is still producing cues. Retain only the start
    /// instant (not frames) so the UI watchdog can shut capture down if the first result never
    /// arrives or analysis later stalls.
    private var monitoringStartedAt: Date?

    public init(focus: LivePoseFocus) {
        self.focus = focus
        super.init()
        let notificationCenter = NotificationCenter.default
        captureNotificationTokens = [
            notificationCenter.addObserver(
                forName: AVCaptureSession.wasInterruptedNotification,
                object: session,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.stopForSystemInterruption("相机已被系统中断；已降级为仅跟练/仅计时。")
                }
            },
            notificationCenter.addObserver(
                forName: AVCaptureSession.runtimeErrorNotification,
                object: session,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.stopForSystemInterruption("本机相机运行中断；已降级为仅跟练/仅计时。")
                }
            }
        ]
    }

    public func start() {
        // `isRunning` changes only after the capture queue has configured hardware.  A second
        // tap in that short window used to be able to queue a second configuration.  The
        // requested flag is the owner’s single in-flight start token, and remains true for the
        // whole active capture session until `stop()` deliberately withdraws it.
        guard !isRunning, !isStarting, startGate.begin() else { return }
        isStarting = true
        guard UIDevice.current.userInterfaceIdiom == .phone else {
            startGate.withdraw()
            isStarting = false
            cue = LivePoseCue("实时取景提醒仅在 iPhone 可用；此设备已降级为仅跟练/仅计时。", level: .unavailable)
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startSession()
        case .notDetermined:
            isAwaitingAuthorization = true
            cue = LivePoseCue("请允许相机权限；只用于这次本机实时提示，不录像、不上传。", level: .unavailable)
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor in
                    guard let self else { return }
                    self.isAwaitingAuthorization = false
                    guard self.startGate.isRequested else { return }
                    granted ? self.startSession() : self.setPermissionDeniedCue()
                }
            }
        default:
            setPermissionDeniedCue()
        }
    }

    public func stop() {
        // Make the user-facing state safe immediately, before queueing hardware cleanup. Without
        // this order, a lock/app-switch can leave a short interval where the screen still says
        // “monitoring” even though the person has left the live-coaching context.
        startGate.withdraw()
        isStarting = false
        isAwaitingAuthorization = false
        isRunning = false
        lastUpdatedAt = nil
        monitoringStartedAt = nil
        frameOrientationMonitor.stop()
        stopSpeaking()
        cue = LivePoseCue("取景已停止；本次没有录像、缓存、回放或上传。", level: .unavailable)
        queue.async { [weak self] in
            self?.session.stopRunning()
            self?.session.inputs.forEach { self?.session.removeInput($0) }
            self?.session.outputs.forEach { self?.session.removeOutput($0) }
        }
    }

    private func stopForSystemInterruption(_ message: String) {
        stop()
        cue = LivePoseCue(message, level: .unavailable)
    }

    public func stopSpeaking() {
        speechSynthesizer.stopSpeaking(at: .immediate)
        // A new live session must not inherit the previous session's de-duplication window:
        // after the owner turns voice cues off and on (or stops/restarts the camera), the first
        // caution in the new session should be eligible for one system-volume announcement.
        lastSpokenText = nil
        lastSpokenAt = .distantPast
    }

    private func startSession() {
        queue.async { [weak self] in
            guard let self else { return }
            guard self.startGate.isRequested else { return }
            guard UIDevice.current.userInterfaceIdiom == .phone else {
                self.startGate.withdraw()
                Task { @MainActor in
                    self.isStarting = false
                    self.isRunning = false
                    self.cue = LivePoseCue("实时取景提醒仅在 iPhone 可用；此设备已降级为仅跟练/仅计时。", level: .unavailable)
                }
                return
            }
            // AVCaptureSession raises an Objective-C exception if `startRunning()` is called
            // between beginConfiguration/commitConfiguration. This closure guarantees that
            // every setup path commits before camera hardware starts.
            let configurationFailure: String? = {
                self.session.beginConfiguration()
                defer { self.session.commitConfiguration() }

                self.session.inputs.forEach(self.session.removeInput)
                self.session.outputs.forEach(self.session.removeOutput)
                self.session.sessionPreset = .medium

                guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
                      let input = try? AVCaptureDeviceInput(device: device) else {
                    return "未找到前置摄像头；请按最低版训练。"
                }
                guard self.session.canAddInput(input) else {
                    return "前置摄像头暂不可用于本次取景；请按最低版训练。"
                }
                self.session.addInput(input)
                guard self.startGate.isRequested else {
                    self.session.removeInput(input)
                    return ""
                }

                let output = AVCaptureVideoDataOutput()
                output.alwaysDiscardsLateVideoFrames = true
                output.setSampleBufferDelegate(self, queue: self.queue)
                guard self.session.canAddOutput(output) else {
                    self.session.removeInput(input)
                    return "本机实时分析暂不可用；已降级为仅跟练/仅计时。"
                }
                self.session.addOutput(output)
                guard self.startGate.isRequested else {
                    self.session.removeOutput(output)
                    self.session.removeInput(input)
                    return ""
                }
                // Keep the data output in its native, unmirrored orientation. Vision receives
                // the gravity-aware EXIF orientation separately, avoiding a costly physical
                // buffer reconfiguration while the phone rotates during a live session.
                if let connection = output.connection(with: .video) {
                    if connection.isVideoRotationAngleSupported(0) {
                        connection.videoRotationAngle = 0
                    }
                    if connection.isVideoMirroringSupported {
                        connection.isVideoMirrored = false
                    }
                }
                self.frameOrientationMonitor.start(for: device)
                return nil
            }()

            if let configurationFailure {
                self.frameOrientationMonitor.stop()
                self.startGate.withdraw()
                Task { @MainActor in
                    self.isStarting = false
                    self.isRunning = false
                    if !configurationFailure.isEmpty {
                        self.cue = LivePoseCue(configurationFailure, level: .unavailable)
                    }
                }
                return
            }

            // Stop/dismiss can withdraw consent while configuration is queued. Recheck only
            // after commit, then remove the unused configuration without starting hardware.
            guard self.startGate.isRequested else {
                self.frameOrientationMonitor.stop()
                self.session.beginConfiguration()
                self.session.inputs.forEach(self.session.removeInput)
                self.session.outputs.forEach(self.session.removeOutput)
                self.session.commitConfiguration()
                Task { @MainActor in self.isStarting = false }
                return
            }
            self.session.startRunning()
            Task { @MainActor in
                // The owner can dismiss the sheet while this hardware operation is completing.
                // Do not resurrect a visible "monitoring" state after that withdrawal.
                guard self.startGate.isRequested else {
                    self.isStarting = false
                    return
                }
                self.isStarting = false
                self.isRunning = true
                self.monitoringStartedAt = .now
                self.cue = LivePoseCue("正在实时取景：每约 0.25 秒刷新一次；请让全身入镜。", level: .framing)
            }
        }
    }

    private func setPermissionDeniedCue() {
        startGate.withdraw()
        isStarting = false
        isAwaitingAuthorization = false
        isRunning = false
        cue = LivePoseCue("未取得相机权限；仍可按最低版训练。可在系统设置中改权限。", level: .unavailable)
    }

    nonisolated public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = Date()
        // Throttle Vision rather than camera capture: this keeps the preview fluid while
        // surfacing fresh on-device cues roughly four times a second during the exercise.
        guard now.timeIntervalSince(lastAnalysis) >= 0.25 else { return }
        lastAnalysis = now
        do {
            let request = VNDetectHumanBodyPoseRequest()
            try VNImageRequestHandler(
                cmSampleBuffer: sampleBuffer,
                orientation: frameOrientationMonitor.current
            ).perform([request])
            guard let observation = request.results?.first else {
                Task { @MainActor in self.publish(LivePoseCue("实时提示：未检测到清晰人体。后退一步、改善光线并让全身入镜。", level: .framing), at: now) }
                return
            }
            let focus = self.focus
            let result = LocalPoseFrameAnalyzer.cue(observation: observation, focus: focus)
            Task { @MainActor in self.publish(result, at: now) }
        } catch {
            // A preview alone is not a real-time coaching result. If Vision fails, stop capture
            // instead of leaving the camera on while the UI merely says analysis is unavailable.
            // The owner can deliberately retry from the safe-setup gate; no automatic restart
            // is attempted after a runtime analysis failure.
            Task { @MainActor in
                self.stopForSystemInterruption("实时姿态分析不可用；已停止取景并降级为仅跟练/仅计时。请按最低版完成，或在确认环境安全后手动重试。")
            }
        }
    }

    private func publish(_ next: LivePoseCue, at date: Date) {
        guard isRunning else { return }
        cue = next
        lastUpdatedAt = date
        speakIfNeeded(next, at: date)
    }

    /// Called by the visible coaching screen while it is active. If the preview is alive but
    /// Vision has not delivered an initial cue, or has stalled for too long, stop hardware and
    /// speech rather than merely labeling the UI as downgraded. No automatic camera restart is
    /// attempted; the person must deliberately pass the safety gate and start again.
    public func stopIfAnalysisIsStale(at now: Date = .now) {
        guard isRunning, let monitoringStartedAt else { return }
        guard LocalPoseAnalysisWatchdog.shouldStop(
            monitoringStartedAt: monitoringStartedAt,
            lastResultAt: lastUpdatedAt,
            now: now
        ) else { return }
        stopForSystemInterruption("实时姿态分析已中断；已停止取景并降级为仅跟练/仅计时。请按最低版完成，或在确认环境安全后手动重试。")
    }

    /// Uses the system speech output and its current system volume. This app deliberately
    /// exposes no independent gain control and does not change AVAudioSession volume/category.
    /// Voice is announced only for a changed cue and is rate-limited, so frame analysis never
    /// turns into a four-times-per-second speech queue.
    private func speakIfNeeded(_ cue: LivePoseCue, at date: Date) {
        guard voiceCuesEnabled,
              cue.level != .ready,
              cue.text != lastSpokenText,
              date.timeIntervalSince(lastSpokenAt) >= 1.5 else { return }

        lastSpokenText = cue.text
        lastSpokenAt = date
        let spokenText = cue.text.replacingOccurrences(of: "实时提示：", with: "")
        let utterance = AVSpeechUtterance(string: spokenText)
        utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        speechSynthesizer.stopSpeaking(at: .immediate)
        speechSynthesizer.speak(utterance)
    }
}

public struct LocalPosePreview: UIViewRepresentable {
    public let session: AVCaptureSession
    public init(session: AVCaptureSession) { self.session = session }
    public func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        // `layerClass` should normally guarantee this type, but a UI integration failure must
        // leave the safe "not monitoring" fallback visible rather than crash during setup.
        guard let previewLayer = view.previewLayer else { return view }
        view.attach(session)
        previewLayer.videoGravity = .resizeAspectFill
        return view
    }
    public func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.attach(session)
    }
    public final class PreviewView: UIView {
        override public class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer? { layer as? AVCaptureVideoPreviewLayer }
        private weak var attachedSession: AVCaptureSession?
        private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?

        func attach(_ session: AVCaptureSession) {
            if attachedSession !== session {
                attachedSession = session
                previewLayer?.session = session
                rotationCoordinator = nil
            }
            if rotationCoordinator == nil,
               let input = session.inputs.compactMap({ $0 as? AVCaptureDeviceInput }).first {
                rotationCoordinator = AVCaptureDevice.RotationCoordinator(
                    device: input.device,
                    previewLayer: previewLayer
                )
            }
            setNeedsLayout()
        }

        override public func layoutSubviews() {
            super.layoutSubviews()
            guard let previewLayer,
                  let connection = previewLayer.connection,
                  let angle = rotationCoordinator?.videoRotationAngleForHorizonLevelPreview,
                  connection.isVideoRotationAngleSupported(angle) else { return }
            if abs(connection.videoRotationAngle - angle) > 0.1 {
                connection.videoRotationAngle = angle
            }
        }
    }
}

public struct LocalPoseCoachView: View {
    @StateObject private var coach: LocalPoseCoach
    public let prompts: [String]
    public let safetyNote: String
    /// When present, the owner explicitly chose the in-App Bilibili follow-along route. The
    /// page uses a non-persistent WebKit surface and lives beside the local-only camera coach;
    /// it is not a downloaded, cached, or recorded lesson.
    public let followAlongURL: URL?
    /// The parent presents this only after the owner has explicitly confirmed the fixed,
    /// indoor, land-based setup. It lets the combined route start the local monitor as the
    /// shared screen appears instead of making the owner repeat the same confirmation inside.
    public let startLiveMonitoringOnAppear: Bool
    @Binding private var workoutStartedAt: Date?
    private let workoutTimerUnavailableReason: String?
    private let onStartWorkoutTimer: () -> Void
    private let onStopWorkoutTimer: (String) -> Void
    /// This is deliberately scoped to the loaded private profile.  A device can be reset and
    /// re-onboarded, and a later profile must not inherit a former owner's choice.
    @AppStorage private var voiceCuesEnabled: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var safeSetupConfirmed = false
    /// One explicit synchronized-start request owns both the permission hand-off and camera
    /// start. It survives only the temporary inactive phase caused by iOS's camera permission
    /// sheet; a real background/lock transition or a manual stop clears it.
    @State private var liveMonitoringRequested = false
    @State private var followAlongStatus: String?
    @State private var followAlongUnavailable = false
    @State private var hidesUnavailableFollowAlong = false
    @State private var showsSafetyDetails = false

    private var supportsIPhoneLivePose: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }

    public init(
        ownerID: UUID,
        prompts: [String],
        trainingTitle: String,
        safetyNote: String? = nil,
        followAlongURL: URL? = nil,
        startLiveMonitoringOnAppear: Bool = false,
        workoutStartedAt: Binding<Date?>,
        workoutTimerUnavailableReason: String?,
        onStartWorkoutTimer: @escaping () -> Void,
        onStopWorkoutTimer: @escaping (String) -> Void
    ) {
        LocalDataDeletion.migrateLegacyVoiceCuePreferenceIfNeeded(for: ownerID)
        self.prompts = prompts
        self.safetyNote = safetyNote ?? "仅用于室内、静态、陆上动作；不要边走、骑车、游泳或手持手机边训练。"
        self.followAlongURL = followAlongURL
        self.startLiveMonitoringOnAppear = startLiveMonitoringOnAppear
        _workoutStartedAt = workoutStartedAt
        self.workoutTimerUnavailableReason = workoutTimerUnavailableReason
        self.onStartWorkoutTimer = onStartWorkoutTimer
        self.onStopWorkoutTimer = onStopWorkoutTimer
        _voiceCuesEnabled = AppStorage(
            wrappedValue: true,
            LocalDataDeletion.voiceCuePreferenceKey(for: ownerID)
        )
        _safeSetupConfirmed = State(initialValue: startLiveMonitoringOnAppear)
        _liveMonitoringRequested = State(initialValue: startLiveMonitoringOnAppear)
        _coach = StateObject(wrappedValue: LocalPoseCoach(focus: .suggested(for: trainingTitle)))
    }

    private var cueColor: Color {
        switch coach.cue.level {
        case .ready: .green
        case .caution: .orange
        case .framing: .yellow
        case .unavailable: .secondary
        }
    }

    private var followAlongSurfaceHeight: CGFloat {
        verticalSizeClass == .compact ? 190 : 340
    }

    private var cameraTileSize: CGSize {
        verticalSizeClass == .compact
            ? CGSize(width: 92, height: 122)
            : CGSize(width: 112, height: 158)
    }

    private func workoutDurationLabel(at now: Date) -> String {
        guard let workoutStartedAt else { return "00:00" }
        let seconds = max(0, Int(now.timeIntervalSince(workoutStartedAt).rounded(.down)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    /// This is deliberately derived from the timestamp of a completed Vision result rather
    /// than the camera preview. A visible preview alone is not evidence that live analysis is
    /// still producing cues.
    private func monitoringStatus(at now: Date) -> (text: String, color: Color) {
        guard safeSetupConfirmed else {
            return ("仅跟练/仅计时 · 未开启相机", .secondary)
        }
        guard coach.isRunning else {
            return ("仅跟练/仅计时 · 实时监测未开启", .secondary)
        }
        guard let lastUpdatedAt = coach.lastUpdatedAt else {
            return ("正在读取第一帧…", .yellow)
        }

        let age = now.timeIntervalSince(lastUpdatedAt)
        if age < 0.75 {
            return ("实时监测中 · 刚刚更新", .green)
        }
        if age < 2 {
            return ("分析正在刷新…", .yellow)
        }
        return ("分析已中断 · 已降级为仅跟练/仅计时", .orange)
    }

    @ViewBuilder
    private func cameraSurface(compact: Bool) -> some View {
        Group {
            if coach.isRunning {
                LocalPosePreview(session: coach.session)
                    .accessibilityLabel("实时本机取景预览")
            } else {
                VStack(spacing: compact ? 5 : 10) {
                    Image(systemName: "video.slash")
                        .font(compact ? .title3 : .largeTitle)
                    Text("未开启取景")
                        .font(compact ? .caption.weight(.semibold) : .headline)
                    if !compact {
                        Text("固定 iPhone 并完成安全确认后再开始")
                            .font(.footnote)
                            .multilineTextAlignment(.center)
                    }
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black.opacity(0.06))
                .accessibilityLabel("未开启实时取景，仅跟练或计时")
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: compact ? 12 : 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: compact ? 12 : 16, style: .continuous)
                .stroke(.white.opacity(compact ? 0.75 : 0), lineWidth: compact ? 2 : 0)
        }
    }

    private var sessionControl: some View {
        VStack(spacing: 8) {
            TimelineView(.periodic(from: .now, by: 0.25)) { timeline in
                let monitoring = monitoringStatus(at: timeline.date)
                HStack(spacing: 8) {
                    Circle()
                        .fill(coach.isRunning ? monitoring.color : cueColor)
                        .frame(width: 9, height: 9)
                    Text(monitoring.text)
                        .font(.footnote.weight(.medium))
                        .lineLimit(2)
                    Spacer(minLength: 4)
                    if supportsIPhoneLivePose {
                        Label(voiceCuesEnabled ? "语音开" : "语音关", systemImage: voiceCuesEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if supportsIPhoneLivePose {
                Button(coach.isRunning ? "停止实时取景" : (coach.isStarting ? "正在启动…" : "开始实时取景")) {
                    if coach.isRunning {
                        liveMonitoringRequested = false
                        coach.stop()
                    } else {
                        liveMonitoringRequested = true
                        coach.start()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity, minHeight: 44)
                .disabled((!safeSetupConfirmed && !coach.isRunning) || coach.isStarting)
                .accessibilityHint(safeSetupConfirmed ? "开始或停止本机实时动作提醒" : "先在上方确认 iPhone 已固定且环境安全")
            }
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                if workoutStartedAt == nil {
                    if let workoutTimerUnavailableReason {
                        Label(workoutTimerUnavailableReason, systemImage: "timer.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .accessibilityLabel("实际训练计时不可开始：\(workoutTimerUnavailableReason)")
                    } else {
                        Button {
                            onStartWorkoutTimer()
                        } label: {
                            Label("开始实际训练计时", systemImage: "timer")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityHint("只从你点按这一刻开始记录实际时长")
                    }
                } else {
                    Button {
                        onStopWorkoutTimer("已在同屏跟练页停止计时；请回到训练详情核对真实时长。")
                    } label: {
                        Label("停止并核对 · \(workoutDurationLabel(at: timeline.date))", systemImage: "stop.fill")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .accessibilityHint("停止实际计时并把本机草稿留在训练详情中核对")
                }
            }
            Text("计时只会在你主动选择“开始跟练并计时”或点“开始实际训练计时”后开始；只记录这次确认到停止之间的真实时长。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.regularMaterial)
        .overlay(alignment: .top) { Divider() }
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if supportsIPhoneLivePose {
                        Toggle(isOn: $safeSetupConfirmed) {
                            Label(
                                followAlongURL == nil
                                    ? "我已在室内陆地、iPhone 已固定，且不会边走、骑车或在水中使用"
                                    : "iPhone 已固定在室内陆地；确认后同步开启实时监测",
                                systemImage: "checkmark.shield"
                            )
                        }
                        .tint(.accentColor)
                        .accessibilityHint(followAlongURL == nil ? "确认后可开启本机实时取景" : "确认后会在同屏跟练页启动本机实时监测")
                        Text(followAlongURL == nil
                             ? "安全确认只允许你主动开启相机；未确认时仅显示提示与计时。"
                             : "确认后只启动本机前置取景；B 站视频仍由你点击播放。两者同屏，不录像、不缓存、不上传。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    #if canImport(WebKit)
                    if let followAlongURL, !hidesUnavailableFollowAlong {
                        VStack(alignment: .leading, spacing: 7) {
                            Label("本次 B 站跟练", systemImage: "play.rectangle")
                                .font(.headline)
                            ZStack(alignment: .topTrailing) {
                                EphemeralBilibiliFollowAlongView(url: followAlongURL) {
                                    followAlongStatus = "已拦截非 B 站链接；本次不会离开临时跟练页。"
                                    followAlongUnavailable = true
                                } onLoadUnavailable: {
                                    followAlongUnavailable = true
                                    followAlongStatus = "本次 B 站页面暂不可用（网络、地区、账号或第三方限制）。本机实时监测仍可独立运行，不会把加载失败当作跟练完成。"
                                }
                                .frame(maxWidth: .infinity, minHeight: followAlongSurfaceHeight, idealHeight: followAlongSurfaceHeight)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                                cameraSurface(compact: true)
                                    .frame(width: cameraTileSize.width, height: cameraTileSize.height)
                                    .padding(10)
                                    .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
                            }
                            Text("视频与本机取景同屏显示；右上角小窗只做实时分析，不录像、不缓存、不上传。B 站播放和账号状态仍由第三方决定。")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            if let followAlongStatus {
                                Text(followAlongStatus)
                                    .font(.footnote)
                                    .foregroundStyle(.orange)
                            }
                            if followAlongUnavailable {
                                Button {
                                    hidesUnavailableFollowAlong = true
                                } label: {
                                    Label("切换为仅本机监测", systemImage: "camera.viewfinder")
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    } else {
                        cameraSurface(compact: false)
                            .frame(maxWidth: .infinity, minHeight: followAlongSurfaceHeight, idealHeight: followAlongSurfaceHeight)
                            .overlay(alignment: .bottom) {
                                Label(coach.cue.text, systemImage: coach.cue.level.systemImage)
                                    .font(.footnote.weight(.medium))
                                    .foregroundStyle(.white)
                                    .padding(10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(.black.opacity(0.68))
                            }
                        if followAlongURL != nil, hidesUnavailableFollowAlong {
                            VStack(spacing: 6) {
                                Label("已降级为仅本机监测；本次没有把视频记为已播放或已完成。", systemImage: "exclamationmark.triangle")
                                    .font(.footnote)
                                    .foregroundStyle(.orange)
                                    .fixedSize(horizontal: false, vertical: true)
                                Button("重新尝试加载 B 站视频") {
                                    followAlongUnavailable = false
                                    followAlongStatus = nil
                                    hidesUnavailableFollowAlong = false
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                    #endif
                    TimelineView(.periodic(from: .now, by: 0.25)) { timeline in
                        let monitoring = monitoringStatus(at: timeline.date)
                        ViewThatFits(in: .horizontal) {
                            HStack {
                                Label("实时关注：\(coach.focus.displayName)", systemImage: "dot.radiowaves.left.and.right")
                                Spacer(minLength: 8)
                                Label(monitoring.text, systemImage: "waveform.path.ecg")
                                    .lineLimit(2)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Label("实时关注：\(coach.focus.displayName)", systemImage: "dot.radiowaves.left.and.right")
                                Label(monitoring.text, systemImage: "waveform.path.ecg")
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .font(.footnote)
                        .foregroundStyle(coach.isRunning ? monitoring.color : cueColor)
                    }
                    DisclosureGroup("今天的动作与安全提示", isExpanded: $showsSafetyDetails) {
                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(prompts, id: \.self) { Text("• \($0)") }
                            Label(safetyNote, systemImage: "exclamationmark.shield")
                                .foregroundStyle(.orange)
                            Label("实时上课式提示：画面逐帧分析后立即丢弃；不录像、不缓存、不回放，也不上传。", systemImage: "video.slash.fill")
                                .foregroundStyle(.secondary)
                            Text("这是持续的基础画面提示，不计数、不测精确角度、不诊断或替代真人教练。任何疼痛、头晕、麻木、呼吸异常立即停止。")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 6)
                    }
                    if supportsIPhoneLivePose {
                        Text("相机/分析不可用时会明确降级为仅跟练/仅计时。切换到其他 App、锁屏、来电或切到后台时，本机取景会停止。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Toggle(isOn: $voiceCuesEnabled) {
                            Label("语音提醒", systemImage: "speaker.wave.2.fill")
                        }
                        .tint(.accentColor)
                        Text("开启后，入镜不足、姿态偏侧或分析异常会语音提醒；语音跟随 iPhone 当前系统音量。本 App 不单独设置音量。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Label("实时取景与语音提示仅在 iPhone 开启。此 iPad 仅保留跟练提示与计时。", systemImage: "iphone.slash")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { sessionControl }
            .navigationTitle(followAlongURL == nil ? "实时动作提醒" : "跟练 + 实时监测")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") {
                        if workoutStartedAt != nil {
                            onStopWorkoutTimer("已结束同屏跟练并停止计时；请回到训练详情核对真实时长。")
                        }
                        coach.stop()
                        dismiss()
                    }
                }
            }
            .onAppear {
                coach.voiceCuesEnabled = voiceCuesEnabled
                if liveMonitoringRequested,
                   safeSetupConfirmed,
                   scenePhase == .active,
                   !coach.isRunning,
                   !coach.isStarting {
                    coach.start()
                }
            }
            .onChange(of: voiceCuesEnabled) { _, enabled in
                coach.voiceCuesEnabled = enabled
                if !enabled { coach.stopSpeaking() }
            }
            .onChange(of: safeSetupConfirmed) { _, confirmed in
                if confirmed, followAlongURL != nil, !coach.isRunning, !coach.isStarting {
                    liveMonitoringRequested = true
                    coach.start()
                } else if !confirmed {
                    liveMonitoringRequested = false
                    if coach.isRunning || coach.isStarting { coach.stop() }
                }
            }
            .onChange(of: scenePhase) { _, phase in
                // A live camera session is useful only while this screen is actively visible.
                // The iOS camera permission sheet briefly makes the App inactive; preserve that
                // single explicit request so granting access can finish the synchronized start.
                // All ordinary app switches, calls and locks still clear the request and stop.
                if phase != .active {
                    guard coach.isAwaitingAuthorization else {
                        liveMonitoringRequested = false
                        coach.stop()
                        return
                    }
                } else if liveMonitoringRequested,
                          safeSetupConfirmed,
                          AVCaptureDevice.authorizationStatus(for: .video) == .authorized,
                          !coach.isRunning,
                          !coach.isStarting {
                    coach.start()
                }
            }
            .task(id: coach.isRunning) {
                // UI wording alone is not a safe downgrade. Keep a light foreground watchdog
                // so a frozen Vision pipeline actually closes capture and speech within the
                // same live session. The task ends naturally when `isRunning` becomes false
                // or the sheet disappears.
                while !Task.isCancelled, coach.isRunning {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    guard !Task.isCancelled else { return }
                    coach.stopIfAnalysisIsStale()
                }
            }
            .onDisappear {
                liveMonitoringRequested = false
                if workoutStartedAt != nil {
                    onStopWorkoutTimer("已离开同屏跟练页，实际计时已自动停止；请回到训练详情核对。")
                }
                coach.stop()
            }
        }
    }
}
#endif
