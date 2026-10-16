import Foundation

/// The only payload the iPhone may hand to a paired Watch. It is intentionally a small,
/// testable value type so a later bridge edit cannot silently add HealthKit, photo, location or
/// pose data to WatchConnectivity. The Watch is a companion display, never another planner.
public struct WatchDailyCardPayload: Sendable, Equatable {
    public let isFormalPlanDay: Bool
    public let publishedAt: Date
    public let date: Date?
    public let breakfast: String?
    public let lunch: String?
    public let dinner: String?
    public let training: String?
    public let trainingMinimum: String?
    public let isRecovery: Bool?
    public let cameraBoundary: String?
    public let unavailableMessage: String?

    private init(
        isFormalPlanDay: Bool,
        publishedAt: Date,
        date: Date? = nil,
        breakfast: String? = nil,
        lunch: String? = nil,
        dinner: String? = nil,
        training: String? = nil,
        trainingMinimum: String? = nil,
        isRecovery: Bool? = nil,
        cameraBoundary: String? = nil,
        unavailableMessage: String? = nil
    ) {
        self.isFormalPlanDay = isFormalPlanDay
        self.publishedAt = publishedAt
        self.date = date
        self.breakfast = breakfast
        self.lunch = lunch
        self.dinner = dinner
        self.training = training
        self.trainingMinimum = trainingMinimum
        self.isRecovery = isRecovery
        self.cameraBoundary = cameraBoundary
        self.unavailableMessage = unavailableMessage
    }

    /// Only a first-56-days plan gets display details. Preparation and post-program assessment
    /// states intentionally contain no date, food or training values so an old Watch screen has
    /// nothing it can mistake for an executable card.
    public static func make(plan: TodayPlan, training: TrainingCard?, now: Date = .now, calendar: Calendar = .current) -> WatchDailyCardPayload {
        guard let dayIndex = PlanSchedule.dayIndex(for: plan.date, calendar: calendar),
              calendar.isDate(plan.date, inSameDayAs: now) else {
            return unavailable(
                message: "iPhone 当前没有今天的第 1–56 天正式日卡；Watch 不显示旧日卡。",
                now: now
            )
        }
        // The training card is independently looked up by the phone shell, but this payload is
        // a public boundary and must not trust every caller. A mismatched card could otherwise
        // pair today's meals with another day's minimum version on the Watch. Do not substitute
        // a fallback training label here: an incomplete/incorrect card must clear the old Watch
        // display until iPhone republishes a coherent current-day card.
        guard let training, training.dayIndex == dayIndex else {
            return unavailable(
                message: "iPhone 当天训练卡不完整或与日卡不一致；Watch 已清除旧日卡。",
                now: now
            )
        }
        return WatchDailyCardPayload(
            isFormalPlanDay: true,
            publishedAt: now,
            date: plan.date,
            breakfast: plan.breakfast.displayTitle,
            lunch: plan.lunch.displayTitle,
            dinner: plan.dinner.displayTitle,
            training: training.title,
            trainingMinimum: training.minimumVersion,
            isRecovery: plan.trainingMode == .recovery,
            cameraBoundary: "实时姿态与语音提示仅在配对 iPhone 固定取景时可用；Watch 不录像、不做姿态分析。"
        )
    }

    /// A private-data recovery state must clear an already received Watch card. It deliberately
    /// has the exact same minimal shape as any other non-executable state: no fallback meal,
    /// training, health, photo, location or profile data can be shown while iPhone data is
    /// unavailable.
    public static func unavailable(
        message: String = "iPhone 本机资料暂时无法读取；Watch 不显示临时日卡。",
        now: Date = .now
    ) -> WatchDailyCardPayload {
        WatchDailyCardPayload(
            isFormalPlanDay: false,
            publishedAt: now,
            unavailableMessage: message
        )
    }

    /// `updateApplicationContext` is appropriate because only the latest day-card state matters.
    /// Keep its keys explicit rather than serialising an entire private profile or `TodayPlan`.
    /// `transportRevision` is an iPhone-process ordering token, not user data.  ISO 8601
    /// application-context timestamps are deliberately human-readable but commonly arrive at
    /// second precision; two same-second publishes therefore need a separate monotonic tie
    /// breaker so an older minimal card cannot overwrite a newer recovery or invalidation state.
    public func applicationContext(transportRevision: Int64) -> [String: Any] {
        let formatter = ISO8601DateFormatter()
        if !isFormalPlanDay {
            return [
                "isFormalPlanDay": false,
                "publishedAt": formatter.string(from: publishedAt),
                "transportRevision": NSNumber(value: transportRevision),
                "unavailableMessage": unavailableMessage ?? "iPhone 当前没有可执行的正式日卡；Watch 不自行生成计划。"
            ]
        }
        // Keep this fail-closed even though the private initializer and `make` currently
        // establish all of these fields. A future edit must not turn a partial payload into a
        // Watch crash or let it reuse a previous executable card. The unavailable payload clears
        // the Watch's card and contains no profile, health, photo, location or pose data.
        guard let date,
              let breakfast,
              let lunch,
              let dinner,
              let training,
              let trainingMinimum,
              let isRecovery,
              let cameraBoundary else {
            return Self.unavailable(
                message: "iPhone 当天日卡字段不完整；Watch 已清除旧日卡。",
                now: publishedAt
            ).applicationContext(transportRevision: transportRevision)
        }
        return [
            "isFormalPlanDay": true,
            "date": formatter.string(from: date),
            "publishedAt": formatter.string(from: publishedAt),
            "transportRevision": NSNumber(value: transportRevision),
            "breakfast": breakfast,
            "lunch": lunch,
            "dinner": dinner,
            "training": training,
            "trainingMinimum": trainingMinimum,
            "isRecovery": isRecovery,
            "cameraBoundary": cameraBoundary
        ]
    }
}

/// A Watch-local timer belongs to one calendar day, rather than to every incoming iPhone
/// application-context refresh. The iPhone can legitimately republish a same-day card after a
/// meal check-in or a recovery adjustment; that must not erase a deliberately started Watch
/// timer. A missing card or an actual day change does reset it, so stale timing never crosses
/// into another day.
public enum WatchLocalTimerResetPolicy {
    public static func shouldReset(
        previousDay: Date?,
        newDay: Date?,
        calendar: Calendar = .current
    ) -> Bool {
        guard let previousDay, let newDay else { return previousDay != nil || newDay != nil }
        return !calendar.isDate(previousDay, inSameDayAs: newDay)
    }
}

/// `updateApplicationContext` represents the latest iPhone state, but a Watch UI can still
/// receive callbacks while a previous main-actor update is pending.  A timestamped stale card
/// must never replace a newer recovery invalidation (or vice versa).  Equal timestamps remain
/// applicable so an identical state may be safely re-delivered after a transient transport
/// failure.  This value is deliberately about payload ordering only; it carries no health,
/// location, photo, video, or pose data.
public enum WatchDailyCardFreshnessPolicy {
    public static func shouldApply(incoming: Date, replacing current: Date?) -> Bool {
        guard let current else { return true }
        return incoming >= current
    }

    /// The revision is only consulted when the serialised timestamp ties.  That keeps a normal
    /// new iPhone launch (with a later timestamp and a fresh in-process counter) applicable,
    /// while preventing a delayed same-second context from rolling a Watch back.
    public static func shouldApply(
        incoming: Date,
        incomingRevision: Int64,
        replacing current: Date?,
        currentRevision: Int64?
    ) -> Bool {
        guard let current else { return true }
        if incoming > current { return true }
        if incoming < current { return false }
        guard let currentRevision else { return true }
        return incomingRevision >= currentRevision
    }
}
