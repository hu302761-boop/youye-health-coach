import Foundation

/// 用户自己选择的可持续节奏。它是目标边界与复盘提示，不是医疗建议，也不会静默改写日卡。
public enum SustainableGoalPace: String, Codable, CaseIterable, Sendable, Equatable {
    case gentle
    case steady
    case flexible

    public var displayName: String {
        switch self {
        case .gentle: "温和推进"
        case .steady: "稳定推进"
        case .flexible: "弹性维持"
        }
    }

    public var detail: String {
        switch self {
        case .gentle: "每周完成 2–3 次，优先睡眠、恢复和动作质量"
        case .steady: "每周完成 3–4 次，按最低版起步，不追连续满勤"
        case .flexible: "每周完成 1–4 次，按当周精力调整，不补练"
        }
    }
}

public struct SustainableGoal: Codable, Sendable, Equatable {
    public var pace: SustainableGoalPace
    public var weeklyTrainingDays: Int
    public var minimumMinutes: Int
    public var reviewEveryWeeks: Int

    public init(
        pace: SustainableGoalPace = .gentle,
        weeklyTrainingDays: Int = 3,
        minimumMinutes: Int = 10,
        reviewEveryWeeks: Int = 2
    ) {
        self.pace = pace
        self.weeklyTrainingDays = min(max(weeklyTrainingDays, 1), 7)
        self.minimumMinutes = min(max(minimumMinutes, 5), 60)
        self.reviewEveryWeeks = min(max(reviewEveryWeeks, 1), 8)
    }

    public var summary: String {
        "\(pace.displayName) · 每周 \(weeklyTrainingDays) 次 · 每次至少 \(minimumMinutes) 分钟"
    }

    public var guardrailText: String {
        "每 \(reviewEveryWeeks) 周复盘一次；漏做不补练，连续两周压力过高就下调节奏。"
    }
}

/// 本周可持续目标的只读执行反馈。只统计本人已确认的正式训练或灵活训练会话；
/// 待确认草稿、恢复拉伸和未来日期不会被算入，避免为了达标制造进度。
public struct SustainableGoalProgress: Sendable, Equatable {
    public let completedSessions: Int
    public let confirmedMinutes: Int
    public let targetSessions: Int
    public let minimumMinutes: Int
    public let isProtectedToday: Bool

    public var sessionSummary: String {
        completedSessions >= targetSessions
            ? "本周已达成 \(completedSessions)/\(targetSessions) 次"
            : "本周 \(completedSessions)/\(targetSessions) 次 · 还需 \(targetSessions - completedSessions) 次"
    }

    public var detail: String {
        "已确认 \(confirmedMinutes) 分钟 · 每次最低 \(minimumMinutes) 分钟"
    }

    public static func current(
        data: PrivateCoachData,
        date: Date = .now,
        calendar: Calendar = .current
    ) -> SustainableGoalProgress {
        let goal = data.profile.sustainableGoal ?? SustainableGoal()
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
        let todayStart = calendar.startOfDay(for: date)
        var standardCompletionDays = Set<Date>()
        var measuredDays = Set<Date>()
        var flexibleSessionCount = 0
        var importedSessionCount = 0
        // Keep distinct sessions as distinct goal completions, while using interval union for
        // minutes so overlapping HealthKit rows cannot inflate the reported time.
        var measuredIntervalsByDay: [Date: [HealthTimeInterval]] = [:]
        for completion in data.dailyCompletions where completion.trainingOrRecoveryCompleted {
            let day = calendar.startOfDay(for: completion.date)
            guard day >= weekStart, day < weekEnd, day <= todayStart,
                  PlanSchedule.dayIndex(for: day, calendar: calendar) != nil else { continue }
            standardCompletionDays.insert(day)
        }
        for session in data.flexibleTrainingSessions where session.option.canCountAsTraining {
            let day = calendar.startOfDay(for: session.date)
            guard day >= weekStart, day < weekEnd, day <= todayStart,
                  session.duration >= TimeInterval(goal.minimumMinutes * 60),
                  PlanSchedule.dayIndex(for: day, calendar: calendar) != nil else { continue }
            flexibleSessionCount += 1
            measuredDays.insert(day)
            if let interval = HealthTimeInterval(start: session.startedAt, end: session.endedAt) {
                measuredIntervalsByDay[day, default: []].append(interval)
            }
        }
        var importedKeys = Set<String>()
        for imported in data.importedWorkoutRecords {
            let day = calendar.startOfDay(for: imported.startedAt)
            guard day >= weekStart, day < weekEnd, day <= todayStart,
                  imported.durationMinutes >= goal.minimumMinutes else { continue }
            let key = "\(imported.startedAt.timeIntervalSinceReferenceDate.rounded())|\(imported.kind.rawValue)|\(imported.durationMinutes)"
            guard importedKeys.insert(key).inserted else { continue }
            importedSessionCount += 1
            measuredDays.insert(day)
            if let interval = HealthTimeInterval(start: imported.startedAt, end: imported.endedAt) {
                measuredIntervalsByDay[day, default: []].append(interval)
            }
        }
        let totalSeconds = measuredIntervalsByDay.values.reduce(0) {
            $0 + HealthIntervalAggregation.unionDuration(of: $1)
        }
        // Standard-session duration is unknown, so represent it conservatively at the owner's
        // minimum threshold rather than claiming an invented measured duration.
        let standardOnlySeconds = standardCompletionDays.subtracting(measuredDays).count * goal.minimumMinutes * 60
        let protected = HealthCheckInService.summary(for: date, in: data)?.hasProtectiveSignal == true
        return SustainableGoalProgress(
            completedSessions: importedSessionCount + flexibleSessionCount + standardCompletionDays.subtracting(measuredDays).count,
            confirmedMinutes: Int(((totalSeconds + TimeInterval(standardOnlySeconds)) / 60).rounded(.down)),
            targetSessions: goal.weeklyTrainingDays,
            minimumMinutes: goal.minimumMinutes,
            isProtectedToday: protected
        )
    }
}
