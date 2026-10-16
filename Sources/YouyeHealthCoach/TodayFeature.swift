import Foundation

/// 计划从用户确认的日期开始：56 天正式训练/餐卡 + 5 天收尾复盘，共两个月 61 天。
public enum PlanSchedule {
    public static let totalProgramDays = 61
    public static let formalProgramDays = 56
    /// 不把创建时的系统时区写进组件；调用方日历决定“今天”的本地日界。
    public static let startDateComponents = DateComponents(year: 2026, month: 8, day: 10)
    /// Owner-controlled restart is stored as a tiny local preference, never by rewriting the
    /// existing daily records. A restart only changes how future calendar cards are mapped.
    public static let restartDateDefaultsKey = "youye.healthCoach.planRestartDate"
    public static let didRestartNotification = Notification.Name("youye.healthCoach.planDidRestart")

    /// A read-only preview of moving the plan start. Existing records are intentionally outside
    /// this value: changing the start only remaps future calendar cards.
    public struct StartDatePreview: Equatable, Sendable {
        public let currentStartDate: Date
        public let newStartDate: Date
        public let newEndDate: Date

        public var dateRangeDescription: String {
            "第 1 天 \(newStartDate.formatted(.dateTime.year().month().day())) 至第 61 天 \(newEndDate.formatted(.dateTime.year().month().day()))"
        }
    }

    /// Keep every surface on the same *local-calendar* interpretation of the configured date.
    /// In particular, no view should create the start day with one time zone and compare it with
    /// another: that can make a traveller see day 0 or day 2 around midnight.
    public static func startDate(in calendar: Calendar = .current) -> Date? {
        if let timestamp = UserDefaults.standard.object(forKey: restartDateDefaultsKey) as? Double {
            return calendar.startOfDay(for: Date(timeIntervalSince1970: timestamp))
        }
        return calendar.date(from: startDateComponents).map { calendar.startOfDay(for: $0) }
    }

    /// Starts a fresh two-month (61-day) schedule today while preserving all prior local records.
    public static func restartFromToday(now: Date = .now, calendar: Calendar = .current) {
        _ = setStartDate(calendar.startOfDay(for: now), now: now, calendar: calendar)
    }

    /// Returns whether an owner may choose this date. Past dates are rejected so a new start
    /// cannot make already-recorded days appear to belong to a different run. Today and future
    /// dates are allowed; this keeps "重新开始" useful without deleting history.
    public static func canChooseStartDate(
        _ date: Date,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Bool {
        calendar.startOfDay(for: date) >= calendar.startOfDay(for: now)
    }

    /// Build a confirmation preview without writing preferences or touching private records.
    public static func previewStartDate(
        _ date: Date,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> StartDatePreview? {
        guard let current = startDate(in: calendar), canChooseStartDate(date, now: now, calendar: calendar) else { return nil }
        let normalized = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: totalProgramDays - 1, to: normalized) else { return nil }
        return StartDatePreview(currentStartDate: current, newStartDate: normalized, newEndDate: end)
    }

    /// Persist an owner-selected start date. The write is deliberately tiny and independent of
    /// daily completions, health status, shopping state, goals, or reminder times.
    @discardableResult
    public static func setStartDate(
        _ date: Date,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Bool {
        guard canChooseStartDate(date, now: now, calendar: calendar) else { return false }
        let normalized = calendar.startOfDay(for: date)
        let previous = startDate(in: calendar)
        UserDefaults.standard.set(normalized.timeIntervalSince1970, forKey: restartDateDefaultsKey)
        if previous == nil || !calendar.isDate(previous!, inSameDayAs: normalized) {
            NotificationCenter.default.post(name: didRestartNotification, object: nil)
        }
        return true
    }

    public static func isFinalPreparationDay(on date: Date = .now, calendar: Calendar = .current) -> Bool {
        guard let start = startDate(in: calendar),
              let previousDay = calendar.date(byAdding: .day, value: -1, to: start) else { return false }
        return calendar.isDate(date, inSameDayAs: previousDay)
    }

    public static func hasNotStarted(on date: Date = .now, calendar: Calendar = .current) -> Bool {
        guard let start = startDate(in: calendar) else { return false }
        return calendar.startOfDay(for: date) < calendar.startOfDay(for: start)
    }

    public static func hasEnded(on date: Date = .now, calendar: Calendar = .current) -> Bool {
        guard let start = startDate(in: calendar),
              let end = calendar.date(byAdding: .day, value: totalProgramDays, to: start) else { return false }
        return calendar.startOfDay(for: date) >= calendar.startOfDay(for: end)
    }

    public static func dayIndex(for date: Date, calendar: Calendar = .current) -> Int? {
        guard let start = startDate(in: calendar) else { return nil }
        let startOfStart = calendar.startOfDay(for: start)
        let startOfDate = calendar.startOfDay(for: date)
        guard let offset = calendar.dateComponents([.day], from: startOfStart, to: startOfDate).day,
              (0..<totalProgramDays).contains(offset) else { return nil }
        return offset + 1
    }

    /// Each shopping list belongs to a seven-day program week, which starts on the owner's
    /// program start date (not necessarily on a calendar Monday). The half-open interval makes
    /// a receipt at the following week's midnight belong to that following week.
    public static func programWeekInterval(for date: Date, calendar: Calendar = .current) -> DateInterval? {
        guard let dayIndex = dayIndex(for: date, calendar: calendar),
              let start = startDate(in: calendar),
              let weekStart = calendar.date(
                byAdding: .day,
                value: ((dayIndex - 1) / 7) * 7,
                to: calendar.startOfDay(for: start)
              ),
              let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) else {
            return nil
        }
        return DateInterval(start: weekStart, end: weekEnd)
    }

    public static func makePlan(for date: Date = .now, calendar: Calendar = .current) -> TodayPlan? {
        guard let index = dayIndex(for: date, calendar: calendar),
              index > formalProgramDays || (RecipeCatalog.all56.indices.contains(index - 1) && TrainingCatalog.all56.indices.contains(index - 1)) else { return nil }
        if index > formalProgramDays {
            return ClosingProgramPlan.make(dayIndex: index, date: date)
        }
        let training = TrainingCatalog.all56[index - 1]
        return TodayPlan(
            date: date,
            breakfast: BreakfastCatalog.card(dayIndex: index),
            lunch: LunchCatalog.card(dayIndex: index),
            dinner: RecipeCatalog.all56[index - 1],
            trainingMode: .standard,
            trainingInstruction: training.minimumVersion + "\n\n退阶：" + training.regression + "\n停止条件：" + training.stopConditions,
            bedtimePreparation: ["把明天午餐盒、保温袋和冰袋放好。", "睡前 10 分钟离开屏幕；尽量在 23:45 前熄灯。"]
        )
    }

    public enum Phase: Equatable, Sendable {
        case preparation
        case active(dayIndex: Int)
        case completed
    }

    /// 所有入口共用同一阶段判断，避免准备日被误显示成“已结束”，或完成日继续出现打卡计划。
    public static func phase(for date: Date = .now, calendar: Calendar = .current) -> Phase {
        if hasNotStarted(on: date, calendar: calendar) { return .preparation }
        if let dayIndex = dayIndex(for: date, calendar: calendar) { return .active(dayIndex: dayIndex) }
        return .completed
    }
}

public struct TodayAction: Identifiable, Sendable, Equatable {
    public enum Kind: String, Sendable { case eat, move, prepare }

    public let id: Kind
    public let title: String
    public let detail: String
    public let isCompleted: Bool

    public init(id: Kind, title: String, detail: String, isCompleted: Bool) {
        self.id = id
        self.title = title
        self.detail = detail
        self.isCompleted = isCompleted
    }
}

/// The food pillar contains three separately executable meal cards. It is intentionally distinct
/// from the three-pillar completion score: the day earns its food pillar only after all meals are
/// recorded, while the person can still see exactly which meal remains.
public struct MealCompletionAction: Identifiable, Sendable, Equatable {
    public let id: MealSlot
    public let title: String
    public let detail: String
    public let isCompleted: Bool
    public let isWaived: Bool

    public init(id: MealSlot, title: String, detail: String, isCompleted: Bool, isWaived: Bool = false) {
        self.id = id
        self.title = title
        self.detail = detail
        self.isCompleted = isCompleted
        self.isWaived = isWaived
    }

    /// Even a waived breakfast may later be recorded if the person voluntarily has it as an
    /// early lunch. "无需补" removes obligation; it never blocks an accurate meal record.
    public var canRecordActualMeal: Bool { true }
}

public enum DailySkipService {
    /// Skipping is a whole-day, user-initiated record. It is only allowed for today’s scheduled
    /// plan and can be undone from the same daily card. No completion flags are erased: undoing
    /// the skip restores the person’s already-recorded actions exactly as they were.
    public static func toggle(
        for plan: TodayPlan,
        in data: PrivateCoachData,
        at date: Date = .now,
        calendar: Calendar = .current
    ) -> PrivateCoachData {
        guard TodayFeature.canComplete(plan, at: date, calendar: calendar) else { return data }
        var changed = data
        var completion = changed.executionCompletion(for: plan.date, calendar: calendar)
            ?? DailyCompletion(date: plan.date, foodCompleted: false, trainingOrRecoveryCompleted: false, bedtimePreparationCompleted: false)
        completion.skippedAt = completion.skippedAt == nil ? date : nil
        changed.dailyCompletions.removeAll { calendar.isDate($0.date, inSameDayAs: plan.date) }
        changed.dailyCompletions.append(completion)
        return changed
    }
}

public enum TodayFeature {
    /// 日历的历史/未来日卡只用于查看。写入打卡的唯一窗口是“计划日期就是今天”的正式计划日。
    /// 该限制在业务层执行，避免未来新增 UI 入口误写历史或未来数据。
    public static func canComplete(_ plan: TodayPlan, at date: Date = .now, calendar: Calendar = .current) -> Bool {
        calendar.isDate(plan.date, inSameDayAs: date) && PlanSchedule.dayIndex(for: plan.date, calendar: calendar) != nil
    }

    /// A clinician/medication restriction or illness may turn recovery into a rest-only day.
    /// Keep this semantic boundary alongside completion writes so every UI surface can present
    /// the same truthful state and a future entry point cannot accidentally mark rest as motion.
    public static func isTrainingPaused(_ plan: TodayPlan) -> Bool {
        plan.trainingMode == .recovery
            && plan.trainingInstruction.contains("暂停计划训练")
    }

    public static func actions(plan: TodayPlan, completion: DailyCompletion?) -> [TodayAction] {
        let foodProgress = completion?.foodProgressDescription ?? "三餐 0/3"
        let trainingPaused = isTrainingPaused(plan)
        let moveCompleted = completion?.trainingOrRecoveryCompleted ?? false
        return [
            TodayAction(id: .eat, title: "吃什么", detail: "\(foodProgress)｜晚餐：\(plan.dinner.displayTitle)", isCompleted: completion?.foodCompleted ?? false),
            TodayAction(
                id: .move,
                title: trainingPaused ? "训练已暂停" : "练什么",
                detail: trainingPaused
                    ? (moveCompleted ? "此前完成已保留；之后休息" : "今天休息，不标记训练完成")
                    : (plan.trainingMode == .recovery ? "恢复版" : "最低完成版"),
                isCompleted: moveCompleted
            ),
            TodayAction(id: .prepare, title: "睡前准备", detail: plan.bedtimePreparation.first ?? "完成睡前交接", isCompleted: completion?.bedtimePreparationCompleted ?? false)
        ]
    }

    public static func mealActions(plan: TodayPlan, completion: DailyCompletion?) -> [MealCompletionAction] {
        [
            MealCompletionAction(
                id: .breakfast,
                title: completion?.breakfastWaivedForLateWake == true ? "早餐｜晚起无需补" : "早餐",
                detail: completion?.breakfastWaivedForLateWake == true ? "今天从午餐开始；早餐未按完成记录，也不计失败" : plan.breakfast.displayTitle,
                isCompleted: completion?.breakfastCompleted ?? false,
                isWaived: completion?.breakfastWaivedForLateWake ?? false
            ),
            MealCompletionAction(id: .lunch, title: "午餐", detail: plan.lunch.displayTitle, isCompleted: completion?.lunchCompleted ?? false),
            MealCompletionAction(id: .dinner, title: "晚餐", detail: plan.dinner.displayTitle, isCompleted: completion?.dinnerCompleted ?? false)
        ]
    }

    public static func completion(for date: Date, existing: DailyCompletion?, completing kind: TodayAction.Kind) -> DailyCompletion {
        var value = existing ?? DailyCompletion(date: date, foodCompleted: false, trainingOrRecoveryCompleted: false, bedtimePreparationCompleted: false)
        // Resuming any concrete action is an intentional reversal of today’s whole-day skip.
        value.skippedAt = nil
        switch kind {
        // Kept for data/API compatibility with the original three-pillar action. New UI uses
        // `completingMeal` so breakfast, lunch and dinner remain independently visible.
        case .eat:
            let completed = !value.foodCompleted
            value.breakfastCompleted = completed
            value.lunchCompleted = completed
            value.dinnerCompleted = completed
            value.breakfastWaivedForLateWake = false
            value.foodCompleted = completed
        case .move: value.trainingOrRecoveryCompleted.toggle()
        case .prepare: value.bedtimePreparationCompleted.toggle()
        }
        return value
    }

    public static func completion(for date: Date, existing: DailyCompletion?, completingMeal slot: MealSlot) -> DailyCompletion {
        var value = existing ?? DailyCompletion(date: date, foodCompleted: false, trainingOrRecoveryCompleted: false, bedtimePreparationCompleted: false)
        value.skippedAt = nil
        switch slot {
        case .breakfast:
            value.breakfastCompleted.toggle()
            value.breakfastWaivedForLateWake = false
        case .lunch: value.lunchCompleted.toggle()
        case .dinner: value.dinnerCompleted.toggle()
        }
        value.foodCompleted = (value.breakfastCompleted || value.breakfastWaivedForLateWake) && value.lunchCompleted && value.dinnerCompleted
        return value
    }

    /// 同一天只保留一条打卡；所有变更留在私人资料中，而非仅存在页面临时状态。
    public static func completing(_ kind: TodayAction.Kind, for plan: TodayPlan, in data: PrivateCoachData, at date: Date = .now, calendar: Calendar = .current) -> PrivateCoachData {
        guard canComplete(plan, at: date, calendar: calendar) else { return data }
        var changed = data
        let existing = changed.executionCompletion(for: plan.date, calendar: calendar)
        // Do not let a direct daily-card tap create a movement completion on a rest-only day.
        // If an earlier, genuine completion already exists, retain the owner's ability to correct
        // it by toggling it off; this path can never turn an incomplete paused day into complete.
        if kind == .move,
           isTrainingPaused(plan),
           existing?.trainingOrRecoveryCompleted != true {
            return data
        }
        let updated = completion(for: plan.date, existing: existing, completing: kind)
        changed.dailyCompletions.removeAll { calendar.isDate($0.date, inSameDayAs: plan.date) }
        changed.dailyCompletions.append(updated)
        return changed
    }

    /// Unlike the UI toggle above, this is an idempotent acknowledgement from another explicit
    /// owner action (for example, a submitted “completed training” feedback form). It can only
    /// ever set the requested pillar to complete; it never clears a previous record.
    public static func markingCompleted(_ kind: TodayAction.Kind, for plan: TodayPlan, in data: PrivateCoachData, at date: Date = .now, calendar: Calendar = .current) -> PrivateCoachData {
        guard canComplete(plan, at: date, calendar: calendar) else { return data }
        // Unlike the reversible daily-card control, this API is an affirmative acknowledgement
        // from another form. It must never convert a medically paused rest day into completion.
        guard kind != .move || !isTrainingPaused(plan) else { return data }
        var changed = data
        var completion = changed.executionCompletion(for: plan.date, calendar: calendar)
            ?? DailyCompletion(date: plan.date, foodCompleted: false, trainingOrRecoveryCompleted: false, bedtimePreparationCompleted: false)
        completion.skippedAt = nil
        switch kind {
        case .eat:
            completion.breakfastCompleted = true
            completion.lunchCompleted = true
            completion.dinnerCompleted = true
            completion.foodCompleted = true
        case .move: completion.trainingOrRecoveryCompleted = true
        case .prepare: completion.bedtimePreparationCompleted = true
        }
        changed.dailyCompletions.removeAll { calendar.isDate($0.date, inSameDayAs: plan.date) }
        changed.dailyCompletions.append(completion)
        return changed
    }

    public static func completingMeal(
        _ slot: MealSlot,
        for plan: TodayPlan,
        in data: PrivateCoachData,
        schedule: DailyRoutineSchedule? = nil,
        at date: Date = .now,
        calendar: Calendar = .current
    ) -> PrivateCoachData {
        guard canComplete(plan, at: date, calendar: calendar) else { return data }
        var changed = data
        let existing = changed.executionCompletion(for: plan.date, calendar: calendar)
        var updated = completion(for: plan.date, existing: existing, completingMeal: slot)
        if slot != .breakfast,
           shouldWaiveBreakfastForLateWake(at: date, schedule: schedule, calendar: calendar),
           !updated.breakfastCompleted {
            updated.breakfastWaivedForLateWake = true
            updated.foodCompleted = updated.lunchCompleted && updated.dinnerCompleted
        }
        changed.dailyCompletions.removeAll { calendar.isDate($0.date, inSameDayAs: plan.date) }
        changed.dailyCompletions.append(updated)
        return changed
    }

    /// This acknowledgement runs only after the owner explicitly marks a later meal. It never
    /// runs merely because the App was opened, and never marks breakfast as eaten. A user-owned
    /// noon-or-later wake schedule moves the threshold later; otherwise 11:00 is the boundary.
    private static func shouldWaiveBreakfastForLateWake(
        at date: Date,
        schedule: DailyRoutineSchedule?,
        calendar: Calendar
    ) -> Bool {
        let nowMinutes = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        let threshold = schedule.map { max(11 * 60, $0.wakeMinutes) } ?? 11 * 60
        return nowMinutes >= threshold
    }

    public static func completion(for plan: TodayPlan, in data: PrivateCoachData, calendar: Calendar = .current) -> DailyCompletion? {
        data.executionCompletion(for: plan.date, calendar: calendar)
    }
}
