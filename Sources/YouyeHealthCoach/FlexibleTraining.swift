import Foundation

/// 当天训练不是只有一张固定日卡。这个轻量选项层把“今天能做多少”交给本人选择，
/// 但仍沿用当天的恢复保护，不自动加量、不改写后续周结构。
public enum FlexibleTrainingOption: String, Codable, CaseIterable, Identifiable, Sendable, Equatable {
    case minimum
    case easyMovement
    case postureReset
    case recoveryStretch

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .minimum: "最低完成版"
        case .easyMovement: "轻松活动"
        case .postureReset: "腰腹体态轻量版"
        case .recoveryStretch: "恢复与拉伸"
        }
    }

    public var subtitle: String {
        switch self {
        case .minimum: "时间少、精力一般时，完成今天最小有效动作"
        case .easyMovement: "不追配速，用轻走、骑行或舒展把身体动起来"
        case .postureReset: "呼吸、核心唤醒和体态重置，不追次数"
        case .recoveryStretch: "疼痛、经期不适或需要休息时，只做舒服的恢复动作"
        }
    }

    public var durationText: String {
        switch self {
        case .minimum: "6–10 分钟"
        case .easyMovement: "10–20 分钟"
        case .postureReset: "8–12 分钟"
        case .recoveryStretch: "6–15 分钟"
        }
    }

    public var symbol: String {
        switch self {
        case .minimum: "checkmark.circle"
        case .easyMovement: "figure.walk"
        case .postureReset: "figure.core.training"
        case .recoveryStretch: "figure.cooldown"
        }
    }

    /// 恢复/拉伸是舒缓动作，不能被误记成训练完成；其余选项只有在本人明确确认后才可计入。
    public var canCountAsTraining: Bool { self != .recoveryStretch }
}

/// A locally timed flexible session.  Stopping the timer creates a pending draft; it is not a
/// completion until the owner explicitly confirms it.  Keeping the option and real interval
/// here prevents the flexible path from collapsing into an anonymous “training done” flag.
public struct FlexibleTrainingDraft: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let date: Date
    public let option: FlexibleTrainingOption
    public let startedAt: Date
    public let endedAt: Date

    public init(id: UUID = UUID(), date: Date, option: FlexibleTrainingOption, startedAt: Date, endedAt: Date) {
        self.id = id
        self.date = date
        self.option = option
        self.startedAt = startedAt
        self.endedAt = max(endedAt, startedAt)
    }

    public var duration: TimeInterval { max(0, endedAt.timeIntervalSince(startedAt)) }
    public var durationLabel: String {
        let seconds = Int(duration.rounded(.down))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

/// A confirmed local flexible session retained for weekly review.  It contains no photo,
/// HealthKit sample, location, or calorie information.
public struct FlexibleTrainingSession: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let date: Date
    public let option: FlexibleTrainingOption
    public let startedAt: Date
    public let endedAt: Date

    public init(id: UUID = UUID(), date: Date, option: FlexibleTrainingOption, startedAt: Date, endedAt: Date) {
        self.id = id
        self.date = date
        self.option = option
        self.startedAt = startedAt
        self.endedAt = max(endedAt, startedAt)
    }

    public var duration: TimeInterval { max(0, endedAt.timeIntervalSince(startedAt)) }
    public var durationLabel: String {
        let seconds = Int(duration.rounded(.down))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

public enum FlexibleTrainingLedger {
    public static func recording(_ draft: FlexibleTrainingDraft, in data: PrivateCoachData) -> PrivateCoachData {
        var changed = data
        changed.pendingFlexibleTrainingDrafts.removeAll { $0.id == draft.id }
        changed.pendingFlexibleTrainingDrafts.append(draft)
        return changed
    }

    public static func discarding(_ draft: FlexibleTrainingDraft, in data: PrivateCoachData) -> PrivateCoachData {
        var changed = data
        changed.pendingFlexibleTrainingDrafts.removeAll { $0.id == draft.id }
        return changed
    }

    /// Confirm an option-aware session exactly once. Recovery/stretch is retained for review but
    /// deliberately does not set the day's formal training completion flag.
    public static func confirming(_ draft: FlexibleTrainingDraft, for plan: TodayPlan, in data: PrivateCoachData) -> PrivateCoachData {
        guard !data.flexibleTrainingSessions.contains(where: { $0.id == draft.id }) else { return data }
        var changed = data
        changed.pendingFlexibleTrainingDrafts.removeAll { $0.id == draft.id }
        changed.flexibleTrainingSessions.append(
            FlexibleTrainingSession(id: draft.id, date: draft.date, option: draft.option, startedAt: draft.startedAt, endedAt: draft.endedAt)
        )
        guard draft.option.canCountAsTraining else { return changed }
        return TodayFeature.markingCompleted(.move, for: plan, in: changed, at: draft.endedAt)
    }
}

public struct FlexibleTrainingRecommendation: Sendable, Equatable {
    public let options: [FlexibleTrainingOption]
    public let recommended: FlexibleTrainingOption
    public let reason: String

    public init(options: [FlexibleTrainingOption], recommended: FlexibleTrainingOption, reason: String) {
        self.options = options
        self.recommended = recommended
        self.reason = reason
    }
}

public enum FlexibleTrainingAdvisor {
    /// 推荐只读取当天已由本人提交的状态和当前计划，不读取或保存 HealthKit 原始样本。
    /// 保护信号优先于“想练什么”：医生/用药限制或生病时只给恢复动作。
    public static func recommendation(
        for plan: TodayPlan,
        status: HealthStatus?,
        trainingAlreadyCompleted: Bool
    ) -> FlexibleTrainingRecommendation {
        if trainingAlreadyCompleted {
            return FlexibleTrainingRecommendation(
                options: [.recoveryStretch],
                recommended: .recoveryStretch,
                reason: "今天训练已确认，不补练；如想活动，只做放松。"
            )
        }

        let requiresRestOnly = TodayFeature.isTrainingPaused(plan)
            || status?.painOrInjury == true
            || status?.illnessSymptoms == true
            || status?.medicationOrClinicianRestriction == true
            || status?.menstrualDiscomfort == true
        if requiresRestOnly {
            return FlexibleTrainingRecommendation(
                options: [.recoveryStretch],
                recommended: .recoveryStretch,
                reason: "今天以休息和恢复为主，不把休息标成训练完成。"
            )
        }

        let lowEnergy = (status?.energy ?? 3) <= 2
            || (status?.sleepHours.map { $0 < 6.5 } ?? false)
        if plan.trainingMode == .recovery || status?.needsProtectiveDowngrade == true || lowEnergy {
            return FlexibleTrainingRecommendation(
                options: [.minimum, .easyMovement, .recoveryStretch],
                recommended: status?.needsProtectiveDowngrade == true ? .recoveryStretch : .minimum,
                reason: status?.needsProtectiveDowngrade == true
                    ? "今天有恢复信号，先从最低版或恢复动作开始。"
                    : "精力/睡眠偏低，降低门槛即可；完成后不会自动加量。"
            )
        }

        return FlexibleTrainingRecommendation(
            options: [.minimum, .postureReset, .easyMovement],
            recommended: .minimum,
            reason: "按今天时间和身体感受任选一项；完成后不会自动改变后续计划。"
        )
    }
}
