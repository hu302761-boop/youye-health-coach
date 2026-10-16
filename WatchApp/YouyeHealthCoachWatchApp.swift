import Foundation
import SwiftUI
import WatchConnectivity

/// watchOS companion: a paired-iPhone surface for today’s meals, minimum training and a local
/// elapsed-time display. It intentionally has no camera, video buffer, pose analysis or playback.
@main
struct YouyeHealthCoachWatchApp: App {
    @StateObject private var companion = WatchCompanionStore()

    var body: some Scene {
        WindowGroup {
            WatchTodayView(companion: companion)
        }
    }
}

@MainActor
final class WatchCompanionStore: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var breakfast = "等待配对 iPhone 同步"
    @Published private(set) var lunch = "等待配对 iPhone 同步"
    @Published private(set) var dinner = "等待配对 iPhone 同步"
    @Published private(set) var training = "在 iPhone 打开计划后同步"
    @Published private(set) var minimum = ""
    @Published private(set) var isRecovery = false
    @Published private(set) var cameraBoundary = "实时姿态提示只在配对 iPhone 固定取景时可用。"
    @Published private(set) var planDate: Date?
    @Published private(set) var hasFormalPlanDay = false
    @Published private(set) var syncStatus = "等待配对 iPhone 同步当天日卡"
    /// The Watch keeps only the timestamp needed to reject an out-of-order *minimal* context.
    /// It is not a workout, HealthKit, video, camera, or location history.
    private var lastPublishedAt: Date?
    /// A transport-only iPhone ordering token. This is not retained as health, profile, photo,
    /// location, or workout data; it only disambiguates several context updates received in one
    /// ISO-8601 timestamp second.
    private var lastTransportRevision: Int64?

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    nonisolated func session(_: WCSession, activationDidCompleteWith _: WCSessionActivationState, error _: Error?) {
        Task { @MainActor [weak self] in self?.apply(WCSession.default.receivedApplicationContext) }
    }

    nonisolated func session(_: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor [weak self] in self?.apply(applicationContext) }
    }

    private func apply(_ context: [String: Any]) {
        guard let rawPublishedAt = context["publishedAt"] as? String,
              let publishedAt = ISO8601DateFormatter().date(from: rawPublishedAt) else {
            clearDailyCard()
            syncStatus = "收到的 iPhone 日卡缺少同步时间，已清空旧内容；请在 iPhone 打开 App 后重新同步。"
            return
        }
        guard let transportRevision = (context["transportRevision"] as? NSNumber)?.int64Value else {
            clearDailyCard()
            syncStatus = "收到的 iPhone 日卡缺少同步顺序，已清空旧内容；请在 iPhone 打开 App 后重新同步。"
            return
        }
        guard shouldApplyIncomingCard(publishedAt, revision: transportRevision) else { return }
        lastPublishedAt = publishedAt
        lastTransportRevision = transportRevision
        guard context["isFormalPlanDay"] as? Bool == true else {
            clearDailyCard()
            syncStatus = context["unavailableMessage"] as? String
                ?? "iPhone 当前没有可执行的正式日卡；Watch 不自行生成计划。"
            return
        }
        guard let rawDate = context["date"] as? String,
              let planDate = ISO8601DateFormatter().date(from: rawDate),
              let breakfast = context["breakfast"] as? String,
              let lunch = context["lunch"] as? String,
              let dinner = context["dinner"] as? String,
              let training = context["training"] as? String,
              let minimum = context["trainingMinimum"] as? String,
              let isRecovery = context["isRecovery"] as? Bool,
              let cameraBoundary = context["cameraBoundary"] as? String else {
            clearDailyCard()
            syncStatus = "收到的 iPhone 日卡不完整，已清空旧内容；请在 iPhone 打开 App 后重新同步。"
            return
        }
        hasFormalPlanDay = true
        self.planDate = planDate
        self.breakfast = breakfast
        self.lunch = lunch
        self.dinner = dinner
        self.training = training
        self.minimum = minimum
        self.isRecovery = isRecovery
        self.cameraBoundary = cameraBoundary
        syncStatus = "已由 iPhone 同步 · \(publishedAt.formatted(date: .omitted, time: .shortened))"
    }

    /// Keep the Watch target independently compilable: it repeats the tiny, shared ordering
    /// rule rather than linking the iPhone coach module or receiving any broader profile data.
    private func shouldApplyIncomingCard(_ incoming: Date, revision: Int64) -> Bool {
        guard let lastPublishedAt else { return true }
        if incoming > lastPublishedAt { return true }
        if incoming < lastPublishedAt { return false }
        guard let lastTransportRevision else { return true }
        return revision >= lastTransportRevision
    }

    /// An unavailable or malformed iPhone context must remove the old in-memory card as well as
    /// hiding it.  This keeps a future view change from accidentally reusing yesterday's meal or
    /// training labels after private iPhone data was deleted, locked for recovery, or expired.
    private func clearDailyCard() {
        hasFormalPlanDay = false
        planDate = nil
        breakfast = ""
        lunch = ""
        dinner = ""
        training = ""
        minimum = ""
        isRecovery = false
        cameraBoundary = "实时姿态提示只在配对 iPhone 固定取景时可用。"
    }

    /// Watch may remain open across midnight. Re-evaluate the iPhone card against the current
    /// clock at render time instead of trusting the date that was true when context arrived.
    func hasTodayPlan(at now: Date = .now) -> Bool {
        guard hasFormalPlanDay, let planDate else { return false }
        return Calendar.current.isDate(planDate, inSameDayAs: now)
    }

    func syncMessage(at now: Date = .now) -> String {
        guard planDate != nil else { return syncStatus }
        guard hasTodayPlan(at: now) else {
            return "上次同步不是今天的日卡，不当作今天计划显示；请在 iPhone 打开 App 更新。"
        }
        return syncStatus
    }
}

private struct WatchTodayView: View {
    @ObservedObject var companion: WatchCompanionStore
    @State private var startedAt: Date?

    private var duration: TimeInterval { startedAt.map { Date().timeIntervalSince($0) } ?? 0 }

    var body: some View {
        // Recheck at a short cadence because a Watch can remain visible across midnight.  The
        // source card must disappear promptly; it is never silently reused as tomorrow's plan.
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let hasTodayPlan = companion.hasTodayPlan(at: timeline.date)
            List {
                Section("今天") {
                    Text(companion.syncMessage(at: timeline.date)).font(.footnote)
                    if hasTodayPlan {
                        Label(companion.isRecovery ? "恢复优先" : "按最低版完成", systemImage: companion.isRecovery ? "heart.circle" : "checkmark.circle")
                        Text("早：\(companion.breakfast)")
                        Text("午：\(companion.lunch)")
                        Text("晚：\(companion.dinner)")
                    } else {
                        Text("Watch 不自行生成餐食或训练。请在配对 iPhone 打开 App；同步后这里才显示今天日卡。")
                            .font(.footnote)
                    }
                }
                if hasTodayPlan {
                    Section("练什么") {
                        Text(companion.training)
                        if !companion.minimum.isEmpty { Text(companion.minimum).font(.footnote) }
                    }
                }
                if hasTodayPlan {
                    Section("实际计时") {
                        Text(duration.formatted(.time(pattern: .minuteSecond)))
                            .monospacedDigit()
                        Button(startedAt == nil ? "开始计时" : "停止计时") {
                            startedAt = startedAt == nil ? Date() : nil
                        }
                        Text("仅在 Watch 本地显示；不会自行创建 Apple 健康 workout。真实训练仍要回 iPhone 核对类型与实际起止时间后确认同步。")
                            .font(.footnote)
                    }
                    Section("实时提示") {
                        Text(companion.cameraBoundary).font(.footnote)
                        Text("Watch 没有录像、缓存、回放或姿态分析；请在配对 iPhone 上开启实时动作提醒。").font(.footnote)
                    }
                }
            }
            .onChange(of: hasTodayPlan) { _, isCurrentDay in
                if !isCurrentDay { startedAt = nil }
            }
        }
        .onChange(of: companion.planDate) { previousDay, newDay in
            if shouldResetLocalTimer(previousDay: previousDay, newDay: newDay) {
                startedAt = nil
            }
        }
        .onChange(of: companion.hasFormalPlanDay) { _, isFormalPlanDay in
            if !isFormalPlanDay { startedAt = nil }
        }
    }

    /// The Watch target deliberately does not link the iPhone/Mac coach module: it receives a
    /// fixed, whitelisted WatchConnectivity context only. Keep this tiny date rule local so the
    /// companion remains independently compilable, while the shared rule-check fixture verifies
    /// the same calendar semantics.
    private func shouldResetLocalTimer(previousDay: Date?, newDay: Date?) -> Bool {
        guard let previousDay, let newDay else { return previousDay != nil || newDay != nil }
        return !Calendar.current.isDate(previousDay, inSameDayAs: newDay)
    }
}
