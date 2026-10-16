#if canImport(UIKit) && canImport(WatchConnectivity)
import Foundation
import WatchConnectivity

/// A tiny, non-sensitive handoff from the paired iPhone to Apple Watch.
/// It deliberately excludes HealthKit summaries, photos, pose output, video, location and the
/// full private profile. The Watch is a companion display/timer; live camera coaching is iPhone-only.
@MainActor
public final class PhoneWatchCompanionBridge: NSObject, WCSessionDelegate {
    public static let shared = PhoneWatchCompanionBridge()
    /// This carries no owner/profile data.  It distinguishes multiple application-context
    /// publishes created within the same ISO-8601 second, where the timestamp alone cannot
    /// establish which latest-card state the Watch should retain.
    private var lastTransportRevision: Int64 = 0

    private override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    public func publish(plan: TodayPlan, training: TrainingCard?) {
        guard WCSession.isSupported() else { return }
        let payload = WatchDailyCardPayload.make(plan: plan, training: training)
        publish(payload)
    }

    /// Recovery-mode invalidation uses the same whitelisted application-context transport as a
    /// normal card. It overwrites any stale executable Watch card rather than attempting a
    /// queue, file transfer, or full-profile fallback.
    public func invalidateDailyCard(message: String = "iPhone 本机资料暂时无法读取；Watch 不显示临时日卡。") {
        guard WCSession.isSupported() else { return }
        publish(.unavailable(message: message))
    }

    private func publish(_ payload: WatchDailyCardPayload) {
        do {
            try WCSession.default.updateApplicationContext(
                payload.applicationContext(transportRevision: nextTransportRevision())
            )
        } catch {
            // The next state change will retry. Do not queue health or video data as a fallback.
        }
    }

    private func nextTransportRevision(now: Date = .now) -> Int64 {
        // Milliseconds survive an App-process restart much better than an increment-only
        // counter.  Increment again within one millisecond so two same-tick publications still
        // remain strictly ordered.
        let epochMilliseconds = Int64((now.timeIntervalSince1970 * 1_000).rounded(.down))
        lastTransportRevision = max(lastTransportRevision + 1, epochMilliseconds)
        return lastTransportRevision
    }

    public nonisolated func session(_: WCSession, activationDidCompleteWith _: WCSessionActivationState, error _: Error?) {}
    public nonisolated func sessionDidBecomeInactive(_: WCSession) {}
    public nonisolated func sessionDidDeactivate(_: WCSession) { WCSession.default.activate() }
}
#endif
