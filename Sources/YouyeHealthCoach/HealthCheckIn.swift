import Foundation

public struct DatedHealthStatus: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let date: Date
    public let status: HealthStatus

    public init(id: UUID = UUID(), date: Date = .now, status: HealthStatus) {
        self.id = id
        self.date = date
        self.status = status
    }
}

public struct DailyHealthStatusAggregate: Sendable, Equatable {
    public let day: Date
    public let latestAt: Date
    public let status: HealthStatus
    /// Any safety signal recorded during the day remains evidence even if a later update only
    /// corrects sleep or adds skin/digestion detail.
    public let hasProtectiveSignal: Bool
}

/// Converts any number of same-day owner updates into one review point. Scalar fields use the
/// latest non-nil value; categorical safety flags and skin concerns are unions. This prevents
/// one night of sleep from being weighted multiple times while retaining conservative safety.
public enum HealthStatusHistoryAggregation {
    public static func dailyAggregates(
        from entries: [DatedHealthStatus],
        calendar: Calendar = .current
    ) -> [DailyHealthStatusAggregate] {
        let groups = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.date) }
        return groups.compactMap { (day: Date, values: [DatedHealthStatus]) -> DailyHealthStatusAggregate? in
            let sorted = values.sorted { $0.date < $1.date }
            guard let latest = sorted.last else { return nil }
            let statuses = sorted.map(\.status)
            func latestValue<T>(_ value: (HealthStatus) -> T?) -> T? {
                statuses.reversed().compactMap(value).first
            }
            let skinValues = Set(statuses.flatMap { $0.skinConcerns.map(\.rawValue) })
            let merged = HealthStatus(
                sleepHours: latestValue(\.sleepHours),
                restingHeartRateAboveBaseline: latestValue(\.restingHeartRateAboveBaseline),
                energy: latestValue(\.energy),
                stress: latestValue(\.stress),
                hungerOrNightEatingUrge: latestValue(\.hungerOrNightEatingUrge),
                digestionNote: latestValue(\.digestionNote),
                menstrualPhase: latestValue(\.menstrualPhase),
                menstrualDiscomfort: statuses.contains { $0.menstrualDiscomfort },
                painOrInjury: statuses.contains { $0.painOrInjury },
                illnessSymptoms: statuses.contains { $0.illnessSymptoms },
                medicationOrClinicianRestriction: statuses.contains { $0.medicationOrClinicianRestriction },
                skinConcerns: SkinConcern.allCases.filter { skinValues.contains($0.rawValue) },
                skinNote: latestValue(\.skinNote)
            )
            return DailyHealthStatusAggregate(
                day: day,
                latestAt: latest.date,
                status: merged,
                hasProtectiveSignal: statuses.contains { $0.needsProtectiveDowngrade }
            )
        }
        .sorted { $0.day < $1.day }
    }
}

public struct HealthCheckInResult: Sendable, Equatable {
    public let plan: TodayPlan
    public let data: PrivateCoachData
    public let automaticChange: PlanChange?
    public let guidance: [String]
    public let validationError: String?
}

/// 今日页使用的最小状态摘要：来自用户当天主动保存的状态，不包含 HealthKit 原始样本或诊断结论。
public struct DailyHealthStatusSummary: Sendable, Equatable {
    public let updatedAt: Date
    public let labels: [String]
    public let hasProtectiveSignal: Bool

    public init(updatedAt: Date, labels: [String], hasProtectiveSignal: Bool) {
        self.updatedAt = updatedAt
        self.labels = labels
        self.hasProtectiveSignal = hasProtectiveSignal
    }
}

public enum HealthCheckInService {
    /// 只记录私有状态；自动行为仅限安全性退阶，绝不在此处自动改目标、热量或加量。
    /// `submissionID` 是一次明确保存操作的稳定标识；双击或重试同一提交不得重复追加状态和审计记录。
    public static func submit(
        _ status: HealthStatus,
        submissionID: UUID = UUID(),
        formOwnerID: UUID? = nil,
        at date: Date = .now,
        plan: TodayPlan,
        data: PrivateCoachData,
        calendar: Calendar = .current
    ) -> HealthCheckInResult {
        // A sheet may survive a full local-data deletion or profile replacement. When the UI
        // supplies its captured owner, reject the old private symptoms at the service boundary
        // instead of attaching them to the newly active profile.
        if let formOwnerID, formOwnerID != data.profile.id {
            return HealthCheckInResult(
                plan: plan,
                data: data,
                automaticChange: nil,
                guidance: [],
                validationError: "本机资料已删除或切换；没有把旧页面中的身体状态写入新资料。"
            )
        }
        if let validationError = status.validationError {
            return HealthCheckInResult(plan: plan, data: data, automaticChange: nil, guidance: [], validationError: validationError)
        }
        // A status is a record of the moment the owner pressed save, not of a stale sheet's
        // original plan date.  If midnight passed while a form stayed open, fail closed instead
        // of filing the new-day status under an old card (or silently treating it as a non-formal
        // note). The caller can reopen today's card and decide again with current context.
        guard calendar.isDate(plan.date, inSameDayAs: date) else {
            return HealthCheckInResult(
                plan: plan,
                data: data,
                automaticChange: nil,
                guidance: [],
                validationError: "日期已切换；这条状态尚未保存。请关闭后打开今天的日卡再记录。"
            )
        }
        let isFormalPlanDay = isFormalPlanDay(plan: plan, at: date, calendar: calendar)
        if let existing = data.datedHealthStatusNotes.first(where: { $0.id == submissionID }) {
            let restoredPlan = replayedPlan(for: date, plan: plan, data: data, calendar: calendar)
            return HealthCheckInResult(
                plan: restoredPlan,
                data: data,
                automaticChange: nil,
                guidance: DailyGuidance.make(
                    for: existing.status,
                    trainingMode: restoredPlan.trainingMode,
                    isFormalPlanDay: isFormalPlanDay
                ),
                validationError: nil
            )
        }
        var changedData = data
        changedData.healthStatusNotes.append(status)
        changedData.datedHealthStatusNotes.append(DatedHealthStatus(id: submissionID, date: date, status: status))
        guard isFormalPlanDay else {
            return HealthCheckInResult(
                plan: plan,
                data: changedData,
                automaticChange: nil,
                guidance: DailyGuidance.make(for: status, trainingMode: plan.trainingMode, isFormalPlanDay: false),
                validationError: nil
            )
        }
        // A status can be submitted from a screen that was opened before another tab saved a
        // recovery signal.  Rebuild from the durable private history first: a stale standard
        // card must not append a second recovery audit or briefly expose the old workout.
        let durablePlan = replayedPlan(for: date, plan: plan, data: data, calendar: calendar)
        let adjusted = PlanAdjuster.adjustment(for: status, plan: durablePlan, at: date)
        if let change = adjusted.change { changedData.planChanges.append(change) }
        return HealthCheckInResult(plan: adjusted.plan, data: changedData, automaticChange: adjusted.change, guidance: DailyGuidance.make(for: status, trainingMode: adjusted.plan.trainingMode), validationError: nil)
    }

    /// App 重开后只从当日已保存的状态重放必要的保护性退阶。
    /// 这里绝不新增变更记录，避免一次已记录的安全调整在每次启动时重复写入。
    public static func replayedPlan(
        for date: Date,
        plan: TodayPlan,
        data: PrivateCoachData,
        calendar: Calendar = .current
    ) -> TodayPlan {
        guard isFormalPlanDay(plan: plan, at: date, calendar: calendar) else { return plan }
        let statusReplayedPlan = dailyStatuses(for: date, in: data, calendar: calendar).reduce(plan) { partialPlan, datedStatus in
            PlanAdjuster.adjustment(for: datedStatus.status, plan: partialPlan, at: datedStatus.date).plan
        }
        // Current schema persists the minimal status necessary to replay a recovery day.  Keep
        // an older, audit-only private record fail-safe too: it is evidence that this exact day
        // was already protectively downgraded, so reopening must not silently restore standard
        // training merely because the old record predates dated-status storage.
        guard statusReplayedPlan.trainingMode == .standard,
              data.planChanges.contains(where: {
                  $0.kind == .recoveryDowngrade
                      && $0.authority == .automatic
                      && calendar.isDate($0.createdAt, inSameDayAs: date)
              }) else {
            return statusReplayedPlan
        }
        return PlanAdjuster.adjustment(
            for: HealthStatus(painOrInjury: true),
            plan: statusReplayedPlan,
            at: date
        ).plan
    }

    /// 同日提示由私有的当日状态派生，以便页面重开后仍可见；不另存诊断或推断文本。
    public static func guidance(
        for date: Date,
        plan: TodayPlan,
        data: PrivateCoachData,
        calendar: Calendar = .current
    ) -> [String] {
        let statuses = dailyStatuses(for: date, in: data, calendar: calendar)
        let formalPlanDay = isFormalPlanDay(plan: plan, at: date, calendar: calendar)
        let messages = statuses.flatMap {
            DailyGuidance.make(for: $0.status, trainingMode: plan.trainingMode, isFormalPlanDay: formalPlanDay)
        }
        var seen = Set<String>()
        return messages.filter { seen.insert($0).inserted }
    }

    /// 摘要合并当天所有状态的最小标签。用户可能上午记录疼痛、晚上再补充皮肤或压力；
    /// 后一条普通记录不能把前一条保护性信号从首页隐藏。这里不保留任何 HealthKit 原始样本。
    public static func summary(
        for date: Date,
        in data: PrivateCoachData,
        calendar: Calendar = .current
    ) -> DailyHealthStatusSummary? {
        let statuses = dailyStatuses(for: date, in: data, calendar: calendar)
        guard let aggregate = HealthStatusHistoryAggregation.dailyAggregates(from: statuses, calendar: calendar).first else { return nil }
        return DailyHealthStatusSummary(
            updatedAt: aggregate.latestAt,
            labels: labels(for: aggregate.status),
            hasProtectiveSignal: aggregate.hasProtectiveSignal
        )
    }

    private static func labels(for status: HealthStatus) -> [String] {
        var labels: [String] = []
        if let sleepHours = status.sleepHours { labels.append("睡眠 \(String(format: "%.1f", sleepHours)) 小时") }
        if let heartRateDelta = status.restingHeartRateAboveBaseline {
            labels.append("静息心率较平时 \(heartRateDelta >= 0 ? "+" : "")\(heartRateDelta) 次/分")
        }
        if let energy = status.energy { labels.append("精力 \(energy)/5") }
        if let stress = status.stress { labels.append("压力 \(stress)/5") }
        if let hunger = status.hungerOrNightEatingUrge { labels.append("饥饿/夜宵冲动 \(hunger)/5") }
        if let phase = status.menstrualPhase { labels.append(phase.displayName) }
        if status.menstrualDiscomfort { labels.append("经期不适") }
        if status.painOrInjury { labels.append("疼痛/受伤") }
        if status.illnessSymptoms { labels.append("生病症状") }
        if status.medicationOrClinicianRestriction { labels.append("用药/医生限制") }
        labels.append(contentsOf: status.skinConcerns.map(\.displayName))
        if status.digestionNote != nil { labels.append("消化已记录") }
        return labels.isEmpty ? ["已保存今日状态"] : labels
    }

    private static func dailyStatuses(
        for date: Date,
        in data: PrivateCoachData,
        calendar: Calendar
    ) -> [DatedHealthStatus] {
        data.datedHealthStatusNotes
            .filter { calendar.isDate($0.date, inSameDayAs: date) }
            .sorted { $0.date < $1.date }
    }

    /// 启动准备日与阶段评估日允许保留本人主动记录的状态，但它们不属于第 1–56 天，
    /// 因而不能生成“恢复退阶”审计、改写日卡或在重开时重放训练变化。
    private static func isFormalPlanDay(plan: TodayPlan, at date: Date, calendar: Calendar) -> Bool {
        calendar.isDate(plan.date, inSameDayAs: date)
            && PlanSchedule.dayIndex(for: plan.date, calendar: calendar) != nil
    }
}

public enum PlanChangeAuditService {
    /// The audit timeline is permanent explanatory context; it is not a command surface. In
    /// particular, a safety downgrade cannot be “undone” from a list, because the underlying
    /// pain, illness, medication, menstrual or sleep signal still requires a protective plan.
    /// Major goal/calorie/progression/week-structure changes require a separately confirmed new
    /// proposal and are never changed by toggling an old audit record.
    public static func canRevert(_ change: PlanChange) -> Bool { false }

    public static func explanation(for change: PlanChange) -> String {
        if change.kind == .recoveryDowngrade {
            return "保护性恢复记录不能在此撤回；请先更新当天身体状态。风险信号存在时仍以恢复版为准。"
        }
        if change.authority == .requiresConfirmation {
            return "这是已确认的记录；如要调整，请创建新的确认变更，不覆盖历史。"
        }
        return "此记录用于解释当天已发生的低风险调整；不在历史列表中直接改写。"
    }
}

/// HealthKit 原始样本不进入计划系统；这里只把已读取的“本次摘要”转成两项保守恢复信号。
/// 体重、体脂、步数、活动能量和运动时长绝不在此处自动改变饮食框架、目标或训练加量。
public enum HealthKitSafetyBridge {
    /// A HealthKit summary is a transient observation, not a reusable health-history record.
    /// Automatic recovery may only use a read that completed on the same local calendar day and
    /// no later than the action attempting to apply it. This prevents a restored, delayed, or
    /// clock-corrupt snapshot from changing today's workout merely because its metrics happen
    /// to look valid. The UI also checks its visible day around the async read; keep this rule
    /// here for every non-UI caller.
    public static func isCurrentSafetySnapshot(
        _ snapshot: HealthSnapshot,
        at date: Date,
        calendar: Calendar = .current
    ) -> Bool {
        snapshot.fetchedAt <= date
            && calendar.isDate(snapshot.fetchedAt, inSameDayAs: date)
    }

    /// 静息心率基线由本人主动确认，但旧资料、导入或异常录入也可能留下无意义数值。
    /// 只有合理的成人静息心率范围才可参与“相对基线”的自动保护判断。
    public static func hasUsableRestingHeartRateBaseline(_ baseline: Double?) -> Bool {
        guard let baseline else { return false }
        return baseline.isFinite && (20...250).contains(baseline)
    }

    public static func status(from snapshot: HealthSnapshot, restingHeartRateBaseline: Double?) -> HealthStatus {
        // Callers normally sanitize before display, but the recovery bridge is also public and
        // must be safe when invoked directly by a future adapter or test path.
        let sanitizedSnapshot = snapshot.sanitizedForDisplay()
        let heartRateDelta = hasUsableRestingHeartRateBaseline(restingHeartRateBaseline)
            ? restingHeartRateBaseline.flatMap { baseline in
            sanitizedSnapshot.restingHeartRate.map { Int(($0 - baseline).rounded(.towardZero)) }
            }
            : nil
        return HealthStatus(
            sleepHours: sanitizedSnapshot.sleepHoursLastNight,
            restingHeartRateAboveBaseline: heartRateDelta
        )
    }

    public static func hasProtectiveSignal(in status: HealthStatus) -> Bool {
        guard status.validationError == nil else { return false }
        return (status.sleepHours ?? 24) < 6 || (status.restingHeartRateAboveBaseline ?? 0) >= 8
    }

    /// 仅供界面解释本次摘要的保护性判断；不保存原始 HealthKit 样本，也不改变目标或热量框架。
    public static func recoveryDecision(snapshot: HealthSnapshot, restingHeartRateBaseline: Double?) -> HealthRecoveryDecision {
        let status = status(from: snapshot, restingHeartRateBaseline: restingHeartRateBaseline)
        let baselineIsUsable = hasUsableRestingHeartRateBaseline(restingHeartRateBaseline)
        if snapshot.hasInvalidMetric {
            return HealthRecoveryDecision(
                baselineIsConfirmed: baselineIsUsable,
                restingHeartRateAboveBaseline: nil,
                triggersRecovery: false,
                reason: "本次健康摘要含异常数值，未改变训练；请在 Apple 健康核对后重读或手动记录状态。"
            )
        }
        if restingHeartRateBaseline != nil, !baselineIsUsable {
            return HealthRecoveryDecision(
                baselineIsConfirmed: false,
                restingHeartRateAboveBaseline: nil,
                triggersRecovery: (status.sleepHours ?? 24) < 6,
                reason: (status.sleepHours ?? 24) < 6
                    ? "昨晚睡眠少于 6 小时；静息心率基线数值异常，未参与判断。"
                    : "静息心率基线数值异常，未参与恢复判断；请重新确认基线。"
            )
        }
        guard status.validationError == nil else {
            return HealthRecoveryDecision(
                baselineIsConfirmed: baselineIsUsable,
                restingHeartRateAboveBaseline: status.restingHeartRateAboveBaseline,
                triggersRecovery: false,
                reason: "本次健康摘要数值异常，未改变训练；请稍后重读或手动记录状态。"
            )
        }
        if (status.sleepHours ?? 24) < 6 {
            return HealthRecoveryDecision(
                baselineIsConfirmed: restingHeartRateBaseline != nil,
                restingHeartRateAboveBaseline: status.restingHeartRateAboveBaseline,
                triggersRecovery: true,
                reason: "昨晚睡眠少于 6 小时"
            )
        }
        if (status.restingHeartRateAboveBaseline ?? 0) >= 8 {
            return HealthRecoveryDecision(
                baselineIsConfirmed: true,
                restingHeartRateAboveBaseline: status.restingHeartRateAboveBaseline,
                triggersRecovery: true,
                reason: "静息心率比你确认的基线高至少 8 次/分"
            )
        }
        return HealthRecoveryDecision(
            baselineIsConfirmed: restingHeartRateBaseline != nil,
            restingHeartRateAboveBaseline: status.restingHeartRateAboveBaseline,
            triggersRecovery: false,
            reason: nil
        )
    }

    public static func apply(
        snapshot: HealthSnapshot,
        restingHeartRateBaseline: Double?,
        at date: Date = .now,
        plan: TodayPlan,
        data: PrivateCoachData,
        calendar: Calendar = .current
    ) -> HealthCheckInResult? {
        guard calendar.isDate(plan.date, inSameDayAs: date),
              isCurrentSafetySnapshot(snapshot, at: date, calendar: calendar),
              PlanSchedule.dayIndex(for: plan.date, calendar: calendar) != nil else { return nil }
        guard !snapshot.hasInvalidMetric else { return nil }
        let status = status(from: snapshot, restingHeartRateBaseline: restingHeartRateBaseline)
        guard status.validationError == nil, hasProtectiveSignal(in: status) else { return nil }
        return HealthCheckInService.submit(status, at: date, plan: plan, data: data, calendar: calendar)
    }

    /// 从 HealthKit 再次读取同一日摘要时，不重复追加同一类保护性状态或变更记录。
    /// 这不改变恢复判断：如果当天已经因用户状态、训练反馈或先前摘要处于恢复版，
    /// 只如实返回“已保护”，保留既有的可回溯依据。
    public static func applyOncePerProtectedDay(
        snapshot: HealthSnapshot,
        restingHeartRateBaseline: Double?,
        at date: Date = .now,
        plan: TodayPlan,
        data: PrivateCoachData,
        calendar: Calendar = .current
    ) -> HealthKitSafetyApplication? {
        guard calendar.isDate(plan.date, inSameDayAs: date),
              isCurrentSafetySnapshot(snapshot, at: date, calendar: calendar),
              PlanSchedule.dayIndex(for: plan.date, calendar: calendar) != nil else { return nil }
        guard !snapshot.hasInvalidMetric else { return nil }
        let status = status(from: snapshot, restingHeartRateBaseline: restingHeartRateBaseline)
        guard status.validationError == nil, hasProtectiveSignal(in: status) else { return nil }

        let hasExistingProtection = plan.trainingMode == .recovery || data.planChanges.contains {
            $0.kind == .recoveryDowngrade && calendar.isDate($0.createdAt, inSameDayAs: date)
        }
        if hasExistingProtection { return .alreadyProtected }
        return apply(snapshot: snapshot, restingHeartRateBaseline: restingHeartRateBaseline, at: date, plan: plan, data: data, calendar: calendar)
            .map(HealthKitSafetyApplication.applied)
    }
}

/// HealthKit 摘要只保留计划所需的恢复结果；重复读取不能制造新的健康历史或审计噪音。
public enum HealthKitSafetyApplication: Sendable, Equatable {
    case applied(HealthCheckInResult)
    case alreadyProtected
}

public struct HealthRecoveryDecision: Sendable, Equatable {
    public let baselineIsConfirmed: Bool
    public let restingHeartRateAboveBaseline: Int?
    public let triggersRecovery: Bool
    public let reason: String?

    public init(baselineIsConfirmed: Bool, restingHeartRateAboveBaseline: Int?, triggersRecovery: Bool, reason: String?) {
        self.baselineIsConfirmed = baselineIsConfirmed
        self.restingHeartRateAboveBaseline = restingHeartRateAboveBaseline
        self.triggersRecovery = triggersRecovery
        self.reason = reason
    }
}

/// 保护性退阶当天的跨页面行动说明。它不会改变餐卡、热量框架或目标，
/// 只确保“今天 / 吃什么 / 练什么”给出同一套非惩罚性行动边界。
public struct RecoveryDaySupport: Sendable, Equatable {
    public let trainingAction: String
    public let foodAction: String
    public let bedtimeAction: String

    public init(trainingAction: String, foodAction: String, bedtimeAction: String) {
        self.trainingAction = trainingAction
        self.foodAction = foodAction
        self.bedtimeAction = bedtimeAction
    }
}

/// Checks the immutable boundaries of a recovery plan. This prevents a future refactor from
/// quietly using recovery as a route to reduce food, raise load, or alter a confirmed framework.
public enum RecoveryPlanAudit {
    public static func validate(_ original: TodayPlan, protected: TodayPlan) -> [String] {
        var errors: [String] = []
        guard protected.trainingMode == .recovery else {
            return ["保护性退阶必须将训练模式设为恢复版"]
        }
        if original.breakfast != protected.breakfast || original.lunch != protected.lunch || original.dinner != protected.dinner {
            errors.append("保护性退阶不得改写当天三餐餐卡")
        }
        if !protected.trainingInstruction.contains("不加量") || !protected.trainingInstruction.contains("停止") {
            errors.append("恢复版必须明确不加量与停止条件")
        }
        guard let support = RecoveryDaySupportService.make(for: protected) else {
            return errors + ["恢复版必须生成跨页面行动说明"]
        }
        if !support.trainingAction.contains("不补练") || !support.foodAction.contains("不因恢复日减餐") || !support.bedtimeAction.contains("睡眠") {
            errors.append("恢复说明必须覆盖不补练、正常吃与睡眠优先")
        }
        return errors
    }
}

public enum RecoveryDaySupportService {
    public static func make(for plan: TodayPlan) -> RecoveryDaySupport? {
        guard plan.trainingMode == .recovery else { return nil }
        let trainingAction: String
        if plan.trainingInstruction.contains("暂停计划训练") {
            trainingAction = "训练已暂停：今天以休息和恢复为主；只有医生、药品说明或当天恢复说明明确允许时才做日常活动。症状加重时停止并寻求专业帮助，不补练、不加量。"
        } else {
            trainingAction = "训练已降为恢复版：轻松走 20 分钟 + 温和呼吸/活动；疼痛、头晕或症状加重就停止，不补练、不加量。"
        }
        return RecoveryDaySupport(
            trainingAction: trainingAction,
            foodAction: "三餐仍按今天现有餐卡吃；保留正常蛋白质、主食和蔬菜，不因恢复日减餐、断食或用运动补偿。",
            bedtimeAction: "今晚优先准备饭盒后提前离屏；把睡眠和恢复放在加练之前。"
        )
    }
}

/// 非医疗的当日提示。除安全性恢复退阶外，这些提示不覆写健康目标、热量框架或训练量。
public enum DailyGuidance {
    /// The Today card starts with a small, source-ordered action list. The full list remains
    /// available to the owner in the UI; this helper only prevents a dense check-in from turning
    /// the daily card into a wall of text.
    public static func initiallyVisible(_ guidance: [String], maximumCount: Int = 2) -> [String] {
        Array(guidance.prefix(max(0, maximumCount)))
    }

    public static func make(
        for status: HealthStatus,
        trainingMode: TrainingMode,
        isFormalPlanDay: Bool = true
    ) -> [String] {
        var guidance: [String] = []
        if trainingMode == .recovery && isFormalPlanDay {
            guidance.append("今天已切换恢复版：不加量、不补练，优先轻松活动和早点睡。")
        }
        if status.painOrInjury {
            guidance.append("已记录疼痛或受伤：今天不测试疼痛动作、不拉到痛；只做不加重症状的轻松活动或休息。疼痛明显、负重困难、麻木无力或加重时请停止并咨询专业人士。")
        }
        if status.illnessSymptoms {
            guidance.append("已记录生病症状：今天以休息、补液和规律进食为先，不做强度训练或补练。发热、胸痛、呼吸困难、意识异常或症状加重时请尽快就医。")
        }
        if status.medicationOrClinicianRestriction {
            guidance.append("已记录用药或医生限制：今天以医生/药品说明优先，不自行加量或尝试新训练；不确定能否运动时先咨询开药医生或药师。")
        }
        if status.menstrualDiscomfort {
            guidance.append(isFormalPlanDay
                            ? "经期明显不适：今天恢复版已优先，按舒适度休息或轻松走动；不因训练完成度、食欲或体重波动减餐、补练。"
                            : "经期明显不适已记录：按舒适度休息或轻松走动；这不是正式训练日，不会创建恢复退阶或计划变更。")
        }
        if (status.hungerOrNightEatingUrge ?? 0) >= 4 { guidance.append("夜宵冲动较高：18:20 可准备无糖豆浆 300ml + 鸡蛋 1 个；不以饿肚子或罚练补偿。") }
        if (status.stress ?? 0) >= 4 { guidance.append("压力较高：训练只做最低版；睡前留 10 分钟离开屏幕、做呼气更长的呼吸。") }
        if (status.energy ?? 5) <= 2 && trainingMode == .standard { guidance.append("精力偏低：训练维持最低版，不加次数；晚餐保留蛋白质和蔬菜。") }
        if let phase = status.menstrualPhase {
            switch phase {
            case .menstrual:
                guidance.append("已记录经期：按感受选择最低版或轻松走动；不因体重短期波动减餐或加练。")
            case .luteal:
                guidance.append("已记录黄体期：提前准备正常加餐与规律正餐；不以饿肚子或罚练应对食欲和体重波动。")
            case .follicular, .ovulation:
                guidance.append("已记录\(phase.displayName)：按当天睡眠、精力和疼痛决定训练，不自动加量。")
            }
        }
        if let digestion = status.digestionNote, !digestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { guidance.append("已记录消化状态：饮食优先温和、熟软；若持续加重、便血、剧烈腹痛或明显脱水，请就医。") }
        if !status.skinConcerns.isEmpty {
            let labels = status.skinConcerns.map(\.displayName).joined(separator: "、")
            guidance.append("已记录皮肤关注项（\(labels)）：温和清洁、保湿和防晒；不要同时叠加多种刺激性产品。")
            if status.skinConcerns.contains(.irritationOrAllergy) {
                guidance.append("出现刺激/疑似过敏：先停用新加或刺激性产品；若有面部肿胀、呼吸不适、迅速加重或持续不退，请尽快就医。")
            }
            if status.skinConcerns.contains(.inflamedAcne) {
                guidance.append("红肿痘持续加重、疼痛明显、留疤风险高或反复数周时，建议预约皮肤科；不挤压、不叠加刷酸/去角质。")
            }
        } else if let skin = status.skinNote, !skin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guidance.append("已记录皮肤状态：保持温和清洁和防晒，不同时叠加多种刺激性产品。")
        }
        return guidance
    }
}

public struct ProposedMajorPlanChange: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let kind: PlanChangeKind
    public let reason: String
    public let before: String
    public let after: String
    public let createdAt: Date

    /// A caller may only propose changes that require the owner's confirmation.  This can be
    /// reached by restored/local automation paths as the product grows, so an invalid kind is
    /// rejected rather than crashing the App with an internal assertion.
    public init?(
        kind: PlanChangeKind,
        reason: String,
        before: String,
        after: String,
        createdAt: Date = .now
    ) {
        guard PlanAdjuster.authority(for: kind) == .requiresConfirmation else { return nil }
        self.id = UUID()
        self.kind = kind
        self.reason = reason
        self.before = before
        self.after = after
        self.createdAt = createdAt
    }

    public func confirm(at date: Date = .now) -> PlanChange {
        PlanChange(kind: kind, authority: .requiresConfirmation, reason: reason, before: before, after: after, createdAt: date)
    }
}
