import Foundation

/// 8 周饮食/训练日历共用的日状态。它只解释已保存的本地完成记录与恢复变更，
/// 不会从未来日期推断失败，也不会写入任何计划。
public enum CalendarDayStatus: String, Sendable, Equatable {
    case recovery
    case completed
    case partiallyCompleted
    case skipped
    case today
    /// A past scheduled day with no saved daily record. This is deliberately not a missed/failure
    /// state: a person may have been offline, ill, travelling, or simply chosen not to log.
    case unrecorded
    case upcoming

    public var label: String {
        switch self {
        case .recovery: "恢复"
        case .completed: "完成"
        case .partiallyCompleted: "部分完成"
        case .skipped: "已跳过"
        case .today: "今天"
        case .unrecorded: "过去未记录"
        case .upcoming: "待执行"
        }
    }

    public var symbolName: String {
        switch self {
        case .recovery: "shield.fill"
        case .completed: "checkmark.circle.fill"
        case .partiallyCompleted: "circle.lefthalf.filled"
        case .skipped: "forward.fill"
        case .today: "circle.fill"
        case .unrecorded: "questionmark.circle"
        case .upcoming: "circle"
        }
    }

    public static func resolve(
        for date: Date,
        data: PrivateCoachData,
        asOf now: Date = .now,
        calendar: Calendar = .current
    ) -> CalendarDayStatus {
        // The 8-week calendar is a view of formal plan days only. A prep-day or post-program
        // private health note must never paint a date as a recovery workout day.
        guard PlanSchedule.dayIndex(for: date, calendar: calendar) != nil else {
            return calendar.startOfDay(for: date) < calendar.startOfDay(for: now) ? .unrecorded : .upcoming
        }
        let dayStart = calendar.startOfDay(for: date)
        let todayStart = calendar.startOfDay(for: now)
        // A future date is never a completed, skipped, or recovery day in the calendar—even if
        // a damaged/imported local file happens to contain a future-dated completion or audit.
        // The App has no UI path to create those records, but fail closed so a clock correction
        // or malformed private JSON cannot make tomorrow look already executed.
        guard dayStart <= todayStart else { return .upcoming }
        let isToday = dayStart == todayStart
        let hasRecovery = data.planChanges.contains {
            // A calendar recovery state is evidence of an actually applied, low-risk safety
            // downgrade—not a generic plan-change label. Recovery downgrades are the only
            // change kind allowed to be automatic; require that durable authority as well so a
            // malformed/imported "requires confirmation" record cannot paint a day as executed.
            !$0.isReverted
                && $0.kind == .recoveryDowngrade
                && $0.authority == .automatic
                && calendar.isDate($0.createdAt, inSameDayAs: date)
        }
        if hasRecovery { return .recovery }

        let completion = data.executionCompletion(for: date, calendar: calendar)
        if completion?.isSkipped == true { return .skipped }
        // Meal logging is retired from the coach flow. A calendar completion now means the two
        // still-actionable commitments—training/recovery and sleep preparation—were completed.
        // Older meal history is preserved and can still make a past day partial, but it cannot
        // block a completed training day merely because new meal logging is no longer offered.
        if let completion,
           completion.trainingOrRecoveryCompleted,
           completion.bedtimePreparationCompleted {
            return .completed
        }
        if let completion,
           completion.trainingOrRecoveryCompleted || completion.bedtimePreparationCompleted || completion.completedMealCount > 0 {
            return .partiallyCompleted
        }
        if isToday { return .today }
        if dayStart < todayStart { return .unrecorded }
        return .upcoming
    }
}
