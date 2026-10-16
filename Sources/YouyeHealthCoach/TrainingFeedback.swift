import Foundation

public struct TrainingFeedback: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let date: Date
    public let effort: Int? // 1...10
    public let pain: Int // 0 无，1 紧绷，2 疼痛/不适
    public let sleepHours: Double?
    public let completed: Bool
    public let note: String?

    public init(id: UUID = UUID(), date: Date = .now, effort: Int? = nil, pain: Int = 0, sleepHours: Double? = nil, completed: Bool, note: String? = nil) {
        self.id = id; self.date = date; self.effort = effort; self.pain = pain; self.sleepHours = sleepHours; self.completed = completed; self.note = note
    }
}

public enum TrainingNextAction: String, Codable, Sendable { case maintain, smallProgression, recoveryDowngrade }

public struct TrainingAdaptation: Codable, Sendable, Equatable {
    public let action: TrainingNextAction
    public let message: String
    public let requiresConfirmation: Bool
    public let safetyReason: String?
}

public struct TrainingFeedbackResult: Sendable, Equatable {
    public let plan: TodayPlan
    public let data: PrivateCoachData
    public let adaptation: TrainingAdaptation
    public let automaticChange: PlanChange?
    /// A feedback form is only an execution record for the current scheduled day. Historical and
    /// future training cards are read-only, so they cannot silently create a later safety signal.
    public let wasAccepted: Bool
}

public enum TrainingFeedbackService {
    public static func validationError(for feedback: TrainingFeedback) -> String? {
        if let effort = feedback.effort, !(1...10).contains(effort) { return "主观用力需为 1–10 分。" }
        if !(0...2).contains(feedback.pain) { return "疼痛/不适只能选择无、轻微紧绷或疼痛/不适。" }
        if let sleepHours = feedback.sleepHours, (!sleepHours.isFinite || !(0...24).contains(sleepHours)) {
            return "睡眠如填写，需为 0–24 小时的有效数值。"
        }
        return nil
    }

    public static func canSubmit(
        for plan: TodayPlan,
        at date: Date = .now,
        calendar: Calendar = .current
    ) -> Bool {
        TodayFeature.canComplete(plan, at: date, calendar: calendar)
    }

    public static func adapt(_ feedback: TrainingFeedback) -> TrainingAdaptation {
        if feedback.pain >= 2 { return TrainingAdaptation(action: .recoveryDowngrade, message: "记录到疼痛/不适：下次改轻走 20–30 分钟和呼吸，不做会加重疼痛的核心动作。", requiresConfirmation: false, safetyReason: "疼痛或不适") }
        if (feedback.sleepHours ?? 24) < 6 { return TrainingAdaptation(action: .recoveryDowngrade, message: "睡眠少于 6 小时：下次跳过主核心，做轻走 20 分钟和拉伸。", requiresConfirmation: false, safetyReason: "睡眠不足") }
        if feedback.effort == 9 || feedback.effort == 10 { return TrainingAdaptation(action: .maintain, message: "本次强度过量：下一次只做最低版，不加次数或时长。", requiresConfirmation: false, safetyReason: "主观用力过高") }
        if feedback.completed, let effort = feedback.effort, effort <= 3 { return TrainingAdaptation(action: .smallProgression, message: "动作质量没有问题时，下次最多每项增加 2 次或 5 秒；不自动增加整轮。", requiresConfirmation: true, safetyReason: nil) }
        return TrainingAdaptation(action: .maintain, message: "保持当前训练量，先稳定动作和呼吸。", requiresConfirmation: false, safetyReason: nil)
    }

    /// 保存训练反馈，并把疼痛/睡眠保护信号接入当天计划；不自动增加训练量。
    public static func submit(
        _ feedback: TrainingFeedback,
        at date: Date = .now,
        plan: TodayPlan,
        data: PrivateCoachData,
        calendar: Calendar = .current
    ) -> TrainingFeedbackResult {
        if let validationError = validationError(for: feedback) {
            return TrainingFeedbackResult(plan: plan, data: data, adaptation: TrainingAdaptation(action: .maintain, message: validationError, requiresConfirmation: false, safetyReason: nil), automaticChange: nil, wasAccepted: false)
        }
        guard canSubmit(for: plan, at: date, calendar: calendar) else {
            return TrainingFeedbackResult(
                plan: plan,
                data: data,
                adaptation: TrainingAdaptation(
                    action: .maintain,
                    message: "历史和未来训练卡只读；请在当天训练完成后再保存反馈。",
                    requiresConfirmation: false,
                    safetyReason: nil
                ),
                automaticChange: nil,
                wasAccepted: false
            )
        }

        // A feedback UUID represents one explicit owner submission. A double tap, interrupted
        // UI retry, or repeated delivery of that same submission must not append another feedback
        // row, another health status, or another recovery audit record. A new, later reflection
        // deliberately uses a new UUID and remains separately visible in the private history.
        if let existing = data.trainingFeedback.first(where: { $0.id == feedback.id }) {
            let replayedPlan = HealthCheckInService.replayedPlan(
                for: date,
                plan: plan,
                data: data,
                calendar: calendar
            )
            return TrainingFeedbackResult(
                plan: replayedPlan,
                data: data,
                adaptation: adapt(existing),
                automaticChange: nil,
                wasAccepted: true
            )
        }
        var changedData = data
        // A clinician/medication or illness check-in can pause this day's plan while an already
        // opened training card is still on screen. Rebuild that durable state before accepting
        // the form so an old completion toggle cannot turn a required rest day into completed
        // training, including after the private history is reloaded.
        let durablePlan = HealthCheckInService.replayedPlan(
            for: date,
            plan: plan,
            data: data,
            calendar: calendar
        )
        let trainingIsPaused = isTrainingPaused(durablePlan)
        // The caller may construct a feedback object earlier. Persist the date that was actually
        // accepted, never its UI-construction timestamp, so future/historical views cannot leak
        // a record into the wrong day after an app reload.
        let recordedFeedback = TrainingFeedback(
            id: feedback.id,
            date: date,
            effort: feedback.effort,
            pain: feedback.pain,
            sleepHours: feedback.sleepHours,
            completed: feedback.completed && !trainingIsPaused,
            note: feedback.note
        )
        changedData.trainingFeedback.append(recordedFeedback)
        var adaptation = adapt(recordedFeedback)
        if feedback.completed && trainingIsPaused {
            adaptation = TrainingAdaptation(
                action: adaptation.action,
                message: "已保存训练反馈；今天暂停计划训练，未标记为训练或恢复完成。\(adaptation.message)",
                requiresConfirmation: adaptation.requiresConfirmation,
                safetyReason: adaptation.safetyReason
            )
        }
        let status = HealthStatus(sleepHours: recordedFeedback.sleepHours, painOrInjury: recordedFeedback.pain >= 2)
        // A pain or short-sleep feedback is also a same-day protection signal. Persist only this
        // minimal, user-entered status (not workout video, counts, or a HealthKit sample) so the
        // recovery plan can be replayed after the App is reopened. Without it, the screen could
        // silently return to standard training despite the saved feedback audit entry.
        if status.needsProtectiveDowngrade {
            // A feedback may be followed by a manual same-day state check-in. Preserve each
            // distinct owner entry, but do not append the same protection snapshot twice if a
            // caller retries with a new feedback ID after an interrupted view update.
            let alreadyRecordedEquivalentStatus = changedData.datedHealthStatusNotes.contains { note in
                calendar.isDate(note.date, inSameDayAs: date)
                    && note.status.sleepHours == status.sleepHours
                    && note.status.painOrInjury == status.painOrInjury
                    && !note.status.illnessSymptoms
                    && !note.status.medicationOrClinicianRestriction
                    && !note.status.menstrualDiscomfort
            }
            if !alreadyRecordedEquivalentStatus {
            changedData.healthStatusNotes.append(status)
            changedData.datedHealthStatusNotes.append(DatedHealthStatus(date: date, status: status))
            }
        }
        let adjusted = PlanAdjuster.adjustment(for: status, plan: durablePlan, at: date)
        if let change = adjusted.change { changedData.planChanges.append(change) }
        // “完成训练/恢复” is an explicit owner assertion in the feedback form, so it may mark
        // today’s movement pillar as complete. A non-completion feedback (pain, early stop,
        // notes) must never clear an existing daily completion; that would turn a safety report
        // into an inaccurate claim that the user did nothing.
        if recordedFeedback.completed {
            changedData = TodayFeature.markingCompleted(.move, for: adjusted.plan, in: changedData, at: date, calendar: calendar)
        }
        return TrainingFeedbackResult(plan: adjusted.plan, data: changedData, adaptation: adaptation, automaticChange: adjusted.change, wasAccepted: true)
    }

    private static func isTrainingPaused(_ plan: TodayPlan) -> Bool {
        plan.trainingMode == .recovery
            && plan.trainingInstruction.contains("暂停计划训练")
    }
}
