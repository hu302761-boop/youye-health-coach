import Foundation

/// A read-only summary of the first 56 scheduled days.  It deliberately separates an absent
/// record from an explicit skip: the former is missing information, never a claim of failure.
/// Nothing in this type starts a new programme or changes food, training, or calorie settings.
public struct ProgramCompletionReview: Sendable, Equatable {
    public let formalPlanDays: Int
    public let recordedPlanDays: Int
    public let unrecordedPlanDays: Int
    public let explicitlySkippedPlanDays: Int
    public let recordedCompletedActions: Int
    /// Kept against the full 56 × three-action framework so the number is auditable. Unrecorded
    /// days are displayed separately and must not be described as missed or failed.
    public let completionRate: Double
    public let averageSleepHours: Double?
    public let protectiveSignals: [String]
    public let skinLabels: [String]
    public let latestWeightKg: Double?
    public let weightChangeKg: Double?
    public let latestWaistCm: Double?
    public let waistChangeCm: Double?
    public let confirmationChecklist: [String]
    public let evidence: [String]
}

public enum ProgramCompletionReviewService {
    public static func make(
        data: PrivateCoachData,
        asOf date: Date? = nil,
        calendar: Calendar = .current
    ) -> ProgramCompletionReview {
        guard let start = calendar.date(from: PlanSchedule.startDateComponents),
              let end = calendar.date(byAdding: .day, value: 56, to: start) else {
            return emptyReview
        }

        let planDayStarts = Set((0..<56).compactMap {
            calendar.date(byAdding: .day, value: $0, to: calendar.startOfDay(for: start)).map(calendar.startOfDay(for:))
        })
        // Callers showing the completed stage pass the actual current date. A nil `asOf`
        // intentionally remains a full historical audit API for offline review: it must not
        // silently discard a valid week-8 trend point merely because it was saved just after
        // the 56th day ended. Live UI always supplies `now` and therefore stays future-safe.
        let asOfEnd: Date
        if let date {
            asOfEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) ?? date
        } else {
            asOfEnd = .distantFuture
        }
        let completions: [DailyCompletion] = planDayStarts.compactMap { dayStart in
            guard dayStart < asOfEnd else { return nil }
            return data.executionCompletion(for: dayStart, calendar: calendar)
        }
        let recordedDates = Set(completions.map { calendar.startOfDay(for: $0.date) })
        let completedActions = completions.reduce(0) { $0 + $1.completedCount }
        let skippedDays = completions.filter(\.isSkipped).count

        // 显式用计划日门槛过滤，而不只依赖日期区间。这样准备日、阶段评估日
        // 以及任何跨时区保存的阶段外私有状态，都不会污染 56 天阶段评估。
        let planStatusEntries = data.datedHealthStatusNotes
            .filter {
                $0.date < asOfEnd
                    && PlanSchedule.dayIndex(for: $0.date, calendar: calendar) != nil
            }
        let planDailyHealth = HealthStatusHistoryAggregation.dailyAggregates(from: planStatusEntries, calendar: calendar)
        let sleepValues = planDailyHealth.compactMap { $0.status.sleepHours }
        let averageSleep = sleepValues.isEmpty ? nil : sleepValues.reduce(0, +) / Double(sleepValues.count)
        let protectiveSignals = protectionLabels(from: planStatusEntries.map(\.status))
        let skinLabels = Array(Set(planDailyHealth.flatMap { $0.status.skinConcerns.map(\.displayName) })).sorted()

        let bodyCheckIns = data.weeklyBodyCheckIns
            .filter { $0.weekStart >= start && $0.weekStart < end && $0.recordedAt < asOfEnd }
            .sorted { $0.recordedAt < $1.recordedAt }
        let weightPoints = bodyCheckIns.compactMap { $0.weightKg }
        let waistPoints = bodyCheckIns.compactMap { $0.waistCm }
        let latestWeight = weightPoints.last
        let latestWaist = waistPoints.last
        let weightChange = latestWeight.flatMap { latest in weightPoints.first.map { latest - $0 } }
        let waistChange = latestWaist.flatMap { latest in waistPoints.first.map { latest - $0 } }
        let rate = Double(completedActions) / Double(56 * 3)

        var evidence = [
            "正式计划日 56 天；已保存执行记录 \(recordedDates.count) 天，未记录 \(56 - recordedDates.count) 天（未记录不等于失败）",
            "已保存三件事 \(completedActions)/168，记录完成率 \(Int((rate * 100).rounded()))%"
        ]
        if skippedDays > 0 { evidence.append("你明确跳过 \(skippedDays) 天；跳过与未记录分开保留") }
        if let averageSleep { evidence.append("已记录睡眠均值 \(String(format: "%.1f", averageSleep)) 小时") }
        if !protectiveSignals.isEmpty { evidence.append("阶段内保护性信号：\(protectiveSignals.joined(separator: "、"))") }
        if !skinLabels.isEmpty { evidence.append("皮肤记录：\(skinLabels.joined(separator: "、"))") }
        if let weightChange { evidence.append("体重相对阶段首个记录 \(signed(weightChange)) kg") }
        if let waistChange { evidence.append("腰围相对阶段首个记录 \(signed(waistChange)) cm") }

        return ProgramCompletionReview(
            formalPlanDays: 56,
            recordedPlanDays: recordedDates.count,
            unrecordedPlanDays: 56 - recordedDates.count,
            explicitlySkippedPlanDays: skippedDays,
            recordedCompletedActions: completedActions,
            completionRate: rate,
            averageSleepHours: averageSleep,
            protectiveSignals: protectiveSignals,
            skinLabels: skinLabels,
            latestWeightKg: latestWeight,
            weightChangeKg: weightChange,
            latestWaistCm: latestWaist,
            waistChangeCm: waistChange,
            confirmationChecklist: [
                "确认下一阶段目标；未确认前不新开 56 天计划。",
                "如需调整热量参考范围、训练加量或每周结构，逐项确认；本页不会自动修改。",
                "如仍有疼痛、生病、用药限制或明显经期不适，先按恢复优先并按需要咨询专业人士。",
                "按冰箱现有食材选择已确认的自炊餐；需要重排时先确认食材文字与克数。"
            ],
            evidence: evidence
        )
    }

    private static func protectionLabels(from statuses: [HealthStatus]) -> [String] {
        var labels = Set<String>()
        for status in statuses {
            if status.painOrInjury { labels.insert("疼痛/受伤") }
            if status.illnessSymptoms { labels.insert("生病症状") }
            if status.medicationOrClinicianRestriction { labels.insert("用药/医生限制") }
            if status.menstrualDiscomfort { labels.insert("经期不适") }
            if (status.sleepHours ?? 24) < 6 { labels.insert("睡眠少于 6 小时") }
            if (status.restingHeartRateAboveBaseline ?? 0) >= 8 { labels.insert("静息心率较基线高至少 8 次/分") }
        }
        let order = ["疼痛/受伤", "生病症状", "用药/医生限制", "经期不适", "睡眠少于 6 小时", "静息心率较基线高至少 8 次/分"]
        return order.filter(labels.contains)
    }

    private static func signed(_ value: Double) -> String { String(format: "%+.1f", value) }

    private static let emptyReview = ProgramCompletionReview(
        formalPlanDays: 56, recordedPlanDays: 0, unrecordedPlanDays: 56,
        explicitlySkippedPlanDays: 0, recordedCompletedActions: 0, completionRate: 0,
        averageSleepHours: nil, protectiveSignals: [], skinLabels: [], latestWeightKg: nil,
        weightChangeKg: nil, latestWaistCm: nil, waistChangeCm: nil,
        confirmationChecklist: ["确认下一阶段目标；未确认前不新开 56 天计划。"],
        evidence: ["阶段日期无法读取；没有生成或改写任何后续计划。"]
    )
}
