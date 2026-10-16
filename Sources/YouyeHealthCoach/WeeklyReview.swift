import Foundation

public enum WeeklyWeightSource: String, Codable, Sendable, Equatable {
    case manual
    case confirmedAppleHealthExport
    case confirmedHealthKitSummary

    public var displayName: String {
        switch self {
        case .manual: "本人手动记录"
        case .confirmedAppleHealthExport: "本人确认的 Apple 健康导出"
        case .confirmedHealthKitSummary: "本人确认的 Apple 健康摘要"
        }
    }
}

/// 仅由本人确认保存的周趋势点；可手动输入，或从本机 Apple 健康导出预览中
/// 单独确认一条体重。它不写入 HealthKit、不含原始样本，也不会据此自动更改目标。
public struct WeeklyBodyCheckIn: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let weekStart: Date
    public let recordedAt: Date
    public let weightKg: Double?
    public let weightSource: WeeklyWeightSource
    public let weightMeasuredAt: Date?
    public let waistCm: Double?
    public let note: String?

    public init(
        id: UUID = UUID(),
        weekStart: Date,
        recordedAt: Date = .now,
        weightKg: Double? = nil,
        weightSource: WeeklyWeightSource = .manual,
        weightMeasuredAt: Date? = nil,
        waistCm: Double? = nil,
        note: String? = nil
    ) {
        self.id = id
        self.weekStart = weekStart
        self.recordedAt = recordedAt
        self.weightKg = weightKg
        self.weightSource = weightSource
        self.weightMeasuredAt = weightKg == nil ? nil : (weightMeasuredAt ?? recordedAt)
        self.waistCm = waistCm
        self.note = note
    }

    private enum CodingKeys: String, CodingKey {
        case id, weekStart, recordedAt, weightKg, weightSource, weightMeasuredAt, waistCm, note
    }

    /// A trend point restored from a local file is not trusted merely because it decodes.  Drop
    /// impossible or non-finite measurement fields while retaining the date and optional note;
    /// this prevents one damaged import from becoming a false weekly or 56-day body trend.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        weekStart = try values.decode(Date.self, forKey: .weekStart)
        recordedAt = try values.decode(Date.self, forKey: .recordedAt)
        let decodedWeight = try values.decodeIfPresent(Double.self, forKey: .weightKg)
        weightKg = Self.isValidWeight(decodedWeight) ? decodedWeight : nil
        weightSource = (try? values.decode(WeeklyWeightSource.self, forKey: .weightSource)) ?? .manual
        let decodedWeightDate = try values.decodeIfPresent(Date.self, forKey: .weightMeasuredAt)
        weightMeasuredAt = weightKg == nil ? nil : (decodedWeightDate ?? recordedAt)
        let decodedWaist = try values.decodeIfPresent(Double.self, forKey: .waistCm)
        waistCm = Self.isValidWaist(decodedWaist) ? decodedWaist : nil
        note = try values.decodeIfPresent(String.self, forKey: .note)
    }

    private static func isValidWeight(_ value: Double?) -> Bool {
        guard let value else { return true }
        return value.isFinite && (20...400).contains(value)
    }

    private static func isValidWaist(_ value: Double?) -> Bool {
        guard let value else { return true }
        return value.isFinite && (30...300).contains(value)
    }
}

public enum WeeklyReviewVariable: String, Codable, Sendable, Equatable {
    case keepRoutine
    case bedtimePreparation
    case mealPreparation
    case recoveryPriority

    public var displayName: String {
        switch self {
        case .keepRoutine: "维持当前节奏"
        case .bedtimePreparation: "睡前准备"
        case .mealPreparation: "备饭准备"
        case .recoveryPriority: "恢复优先"
        }
    }

    /// 仅供本人查看的下一周准备动作。它不会写入提醒、餐卡、训练或热量框架。
    public var preparationChecklist: [String] {
        switch self {
        case .keepRoutine:
            [
                "沿用现有三餐和训练结构，不加量、不改热量框架。",
                "今晚只确认明天的饭盒、冰袋和食材是否就位。"
            ]
        case .bedtimePreparation:
            [
                "睡前 10 分钟离开屏幕，把明天饭盒放到看得见的位置。",
                "把熄灯时间写进自己的日程；做不到时直接保留训练最低版。"
            ]
        case .mealPreparation:
            [
                "睡前洗好饭盒、放好冰袋，并称出或解冻明天的主蛋白。",
                "晚餐优先做两份，第二份按餐卡冷藏，作为次日午餐。",
                "缺食材时先拍现有食材并确认重排，不跳餐或临时节食。"
            ]
        case .recoveryPriority:
            [
                "下一周训练先按最低版执行；疼痛、头晕或症状加重立即停止。",
                "三餐正常按餐卡吃，不因恢复日减餐、断食或补练。",
                "把早点睡和轻松活动排在加练之前。"
            ]
        }
    }
}

/// 周复盘内的一天：仅展示已保存的执行状态。计划开始前/结束后的日子明确标为非计划日，
/// 不计入完成率，也不会被称为漏做。
public struct WeeklyExecutionDay: Sendable, Equatable, Identifiable {
    public let date: Date
    public let dayIndex: Int?
    public let completedActions: Int?
    /// Actual meal diary entries remain visible even when an older build did not create the
    /// matching whole-food completion snapshot. This count is evidence, not an extra score.
    public let recordedMeals: Int?
    public let status: CalendarDayStatus?
    public let isObservedPlanDay: Bool

    public var id: Date { date }

    public init(date: Date, dayIndex: Int?, completedActions: Int?, recordedMeals: Int?, status: CalendarDayStatus?, isObservedPlanDay: Bool) {
        self.date = date
        self.dayIndex = dayIndex
        self.completedActions = completedActions
        self.recordedMeals = recordedMeals
        self.status = status
        self.isObservedPlanDay = isObservedPlanDay
    }
}

public struct WeeklyReviewSummary: Sendable, Equatable {
    public let weekStart: Date
    /// 分母只包含已经发生、且位于 56 天正式计划中的日期；准备日和未来日期不计入。
    public let observedPlanDays: Int
    /// 主人主动标记为整日跳过的已发生计划日。跳过不会伪装成遗漏，也不会抹掉已完成动作；
    /// 其未完成动作仍按 0 项计入完成率，便于如实回顾而不是惩罚。
    public let explicitlySkippedPlanDays: Int
    public let completionRate: Double
    /// Unique date/meal-slot records within already observed formal plan days. Kept separate
    /// from the three-pillar score so one recorded breakfast never becomes a completed food day.
    public let recordedMealEntries: Int
    /// Number of observed plan days containing at least one explicit `completed == true`
    /// training feedback. Timer drafts and early-stop/pain-only feedback are not counted.
    public let completedTrainingFeedbackDays: Int
    /// 本周连续 7 天的执行轨迹；只作回顾解释，不触发自动改计划。
    public let executionDays: [WeeklyExecutionDay]
    public let averageSleepHours: Double?
    public let skinLabels: [String]
    public let latestWeightKg: Double?
    public let latestWeightSource: WeeklyWeightSource?
    public let latestWeightMeasuredAt: Date?
    public let weightChangeKg: Double?
    public let latestWaistCm: Double?
    public let waistChangeCm: Double?
    public let weeklyNote: String?
    public let suggestedVariable: WeeklyReviewVariable
    public let suggestion: String
    /// 建议后的手动准备清单；没有副作用，也不代表 App 会自动执行。
    public let preparationChecklist: [String]
    public let evidence: [String]
}

/// 周复盘只观察趋势和执行摩擦，并且一次仅提出一个低风险、可拒绝的执行变量。
/// 不会自动改目标、热量框架、训练加量或周结构。
public enum WeeklyReviewService {
    public static func weekStart(for date: Date = .now, calendar: Calendar = .current) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    public static func summary(
        for weekStart: Date,
        data: PrivateCoachData,
        asOf date: Date = .now,
        calendar: Calendar = .current
    ) -> WeeklyReviewSummary {
        let end = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
        let observedDates = observedPlanDates(weekStart: weekStart, end: end, asOf: date, calendar: calendar)
        let observedDayStarts = Set(observedDates.map { calendar.startOfDay(for: $0) })
        // Apply the same “already observed” scope to every private signal, not just completion
        // counts. Imported or malformed future-dated sleep/skin/trend records must never steer
        // this week's recovery recommendation before that calendar day has actually arrived.
        let asOfEnd = nextDayBoundary(after: date, calendar: calendar)
        let weekCompletions = observedDates.compactMap {
            data.executionCompletion(for: $0, calendar: calendar)
        }
        let completedActions = weekCompletions.reduce(0) { $0 + $1.completedCount }
        let explicitlySkippedPlanDays = weekCompletions.filter(\.isSkipped).count
        let completionRate = observedDates.isEmpty ? 0 : Double(completedActions) / Double(observedDates.count * 3)
        let recordedMealEntries = observedDates.reduce(0) { count, observedDate in
            let slots = Set(data.actualMealLogs
                .filter { calendar.isDate($0.date, inSameDayAs: observedDate) }
                .map { $0.slot.rawValue })
            return count + slots.count
        }
        let completedTrainingFeedbackDays = observedDates.filter { observedDate in
            data.trainingFeedback.contains {
                $0.completed && calendar.isDate($0.date, inSameDayAs: observedDate)
            }
        }.count
        let executionDays = executionDays(weekStart: weekStart, end: end, data: data, asOf: date, observedDayStarts: observedDayStarts, calendar: calendar)

        // 私有状态可以在准备日或阶段评估日记录，但周复盘的睡眠、皮肤和
        // 保护性信号只反映第 1–56 天的正式执行日，避免阶段外记录意外改变周建议。
        let weekStatusEntries = data.datedHealthStatusNotes
            .filter {
                $0.date >= weekStart
                    && $0.date < end
                    && $0.date < asOfEnd
                    && observedDayStarts.contains(calendar.startOfDay(for: $0.date))
                    && PlanSchedule.dayIndex(for: $0.date, calendar: calendar) != nil
            }
        let dailyHealth = HealthStatusHistoryAggregation.dailyAggregates(from: weekStatusEntries, calendar: calendar)
        let sleepValues = dailyHealth.compactMap { $0.status.sleepHours }
        let averageSleep = sleepValues.isEmpty ? nil : sleepValues.reduce(0, +) / Double(sleepValues.count)
        let skinLabels = Array(Set(dailyHealth.flatMap { $0.status.skinConcerns.map(\.displayName) })).sorted()
        let hasProtectiveSignal = dailyHealth.contains { $0.hasProtectiveSignal }

        let checkIns = data.weeklyBodyCheckIns
            .filter { $0.weekStart <= weekStart && $0.recordedAt < asOfEnd }
            .sorted { $0.weekStart < $1.weekStart }
        let currentCheckIn = checkIns.last { calendar.isDate($0.weekStart, inSameDayAs: weekStart) }
        let priorCheckIn = checkIns.last { $0.weekStart < weekStart }
        let latestWeight = currentCheckIn?.weightKg
        let latestWaist = currentCheckIn?.waistCm
        let weightChange = latestWeight.flatMap { current in priorCheckIn?.weightKg.map { current - $0 } }
        let waistChange = latestWaist.flatMap { current in priorCheckIn?.waistCm.map { current - $0 } }
        let weeklyNote = currentCheckIn?.note

        var evidence: [String]
        if observedDates.isEmpty {
            evidence = ["本周尚无已发生的正式计划日；准备日和未来日期未计入完成率"]
        } else {
            evidence = ["已发生正式计划日 \(observedDates.count) 天，三件事完成率 \(Int((completionRate * 100).rounded()))%"]
        }
        if explicitlySkippedPlanDays > 0 {
            evidence.append("其中 \(explicitlySkippedPlanDays) 天由你明确跳过：状态会保留为“跳过”，已完成项照实计入，未完成项为 0")
        }
        if recordedMealEntries > 0 { evidence.append("已保存实际餐食记录 \(recordedMealEntries) 餐；它们与三件事完成率分开展示") }
        if completedTrainingFeedbackDays > 0 { evidence.append("其中 \(completedTrainingFeedbackDays) 天保存了本人明确的训练/恢复完成反馈") }
        if let averageSleep { evidence.append("已记录睡眠均值 \(String(format: "%.1f", averageSleep)) 小时") }
        if let weightChange { evidence.append("体重相对上次 \(signed(weightChange)) kg") }
        if let waistChange { evidence.append("腰围相对上次 \(signed(waistChange)) cm") }
        if !skinLabels.isEmpty { evidence.append("皮肤记录：\(skinLabels.joined(separator: "、"))") }

        let variable: WeeklyReviewVariable
        let suggestion: String
        if observedDates.isEmpty {
            variable = .keepRoutine
            suggestion = "本周正式计划尚未开始或尚无可复盘日：先按当天日卡准备，不对完成率、目标、热量或训练作判断。"
        } else if hasProtectiveSignal || (averageSleep ?? 24) < 6 {
            variable = .recoveryPriority
            suggestion = "下周只优先一个变量：恢复。把主训练保持在最低版；睡眠、疼痛或生病信号出现时直接改轻走和呼吸，不补练。"
        } else if completionRate < 0.5 {
            variable = .mealPreparation
            suggestion = "下周只优先一个变量：备饭。睡前先完成饭盒、冰袋和次日蛋白解冻；训练和热量框架先不改。"
        } else if (averageSleep ?? 24) < 7 {
            variable = .bedtimePreparation
            suggestion = "下周只优先一个变量：睡前准备。把离开屏幕和明日饭盒放到固定时间；不因睡眠波动减餐或加练。"
        } else {
            variable = .keepRoutine
            suggestion = "下周先维持当前节奏：不加训练量、不改热量框架。连续两周稳定完成后，如想调整目标再由你单独确认。"
        }

        return WeeklyReviewSummary(
            weekStart: weekStart,
            observedPlanDays: observedDates.count,
            explicitlySkippedPlanDays: explicitlySkippedPlanDays,
            completionRate: completionRate,
            recordedMealEntries: recordedMealEntries,
            completedTrainingFeedbackDays: completedTrainingFeedbackDays,
            executionDays: executionDays,
            averageSleepHours: averageSleep,
            skinLabels: skinLabels,
            latestWeightKg: latestWeight,
            latestWeightSource: latestWeight == nil ? nil : currentCheckIn?.weightSource,
            latestWeightMeasuredAt: latestWeight == nil ? nil : currentCheckIn?.weightMeasuredAt,
            weightChangeKg: weightChange,
            latestWaistCm: latestWaist,
            waistChangeCm: waistChange,
            weeklyNote: weeklyNote,
            suggestedVariable: variable,
            suggestion: suggestion,
            preparationChecklist: variable.preparationChecklist,
            evidence: evidence
        )
    }

    private static func observedPlanDates(weekStart: Date, end: Date, asOf date: Date, calendar: Calendar) -> [Date] {
        let todayEnd = nextDayBoundary(after: date, calendar: calendar)
        var cursor = calendar.startOfDay(for: weekStart)
        var dates: [Date] = []
        while cursor < end && cursor < todayEnd {
            if PlanSchedule.dayIndex(for: cursor, calendar: calendar) != nil {
                dates.append(cursor)
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return dates
    }

    private static func nextDayBoundary(after date: Date, calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) ?? date
    }

    private static func executionDays(
        weekStart: Date,
        end: Date,
        data: PrivateCoachData,
        asOf date: Date,
        observedDayStarts: Set<Date>,
        calendar: Calendar
    ) -> [WeeklyExecutionDay] {
        var cursor = calendar.startOfDay(for: weekStart)
        var days: [WeeklyExecutionDay] = []
        while cursor < end {
            let dayIndex = PlanSchedule.dayIndex(for: cursor, calendar: calendar)
            let completion = data.executionCompletion(for: cursor, calendar: calendar)
            let isObserved = observedDayStarts.contains(calendar.startOfDay(for: cursor))
            let recordedMeals = dayIndex == nil || !isObserved ? nil : Set(
                data.actualMealLogs
                    .filter { calendar.isDate($0.date, inSameDayAs: cursor) }
                    .map { $0.slot.rawValue }
            ).count
            days.append(
                WeeklyExecutionDay(
                    date: cursor,
                    dayIndex: dayIndex,
                    completedActions: dayIndex == nil ? nil : completion?.completedCount ?? 0,
                    recordedMeals: recordedMeals,
                    status: dayIndex.map { _ in CalendarDayStatus.resolve(for: cursor, data: data, asOf: date, calendar: calendar) },
                    isObservedPlanDay: isObserved
                )
            )
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return days
    }

    private static func signed(_ value: Double) -> String { String(format: "%+.1f", value) }
}
