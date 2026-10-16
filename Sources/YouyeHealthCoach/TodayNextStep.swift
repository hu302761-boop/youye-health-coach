import Foundation

/// The home screen should answer one question before exposing the full daily card:
/// “what is the next smallest useful thing to do?”  This is a presentation recommendation only.
/// It neither records completion nor changes meals, training, calories, or reminders.
public struct TodayNextStep: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case breakfast, lunch, dinner, training, bedtimePreparation, recovery, windDown, finished, skipped

        fileprivate var displayName: String {
            switch self {
            case .breakfast: return "早餐"
            case .lunch: return "午餐"
            case .dinner: return "晚餐"
            default: return "下一"
            }
        }
    }

    public let kind: Kind
    public let eyebrow: String
    public let title: String
    public let detail: String
    public let actionLabel: String

    public init(kind: Kind, eyebrow: String, title: String, detail: String, actionLabel: String) {
        self.kind = kind
        self.eyebrow = eyebrow
        self.title = title
        self.detail = detail
        self.actionLabel = actionLabel
    }
}

public enum TodayNextStepAdvisor {
    /// The prep shortcut describes the meal that is happening *now*. It is intentionally driven
    /// only by the clock window: legacy meal-completion records must not turn into a hidden debt
    /// or change the preparation suggestion after meal logging was retired.
    public static func quickLogMealSlot(
        plan: TodayPlan,
        completion: DailyCompletion?,
        schedule: DailyRoutineSchedule? = nil,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> MealSlot {
        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)
        let visibleSlots = mealOrder(
            plan: plan,
            completion: completion,
            schedule: schedule,
            hour: hour,
            minute: minute
        )
        let selected = visibleSlots.first?.0 ?? .dinner
        switch selected {
        case .breakfast: return .breakfast
        case .lunch: return .lunch
        case .dinner: return .dinner
        case .training, .bedtimePreparation, .recovery, .windDown, .finished, .skipped:
            return .dinner
        }
    }

    /// Times guide display order only. They are deliberately broad and never read a person’s
    /// location, HealthKit records, or work schedule, and do not trigger notifications.
    ///
    /// The order is intentionally “what can I do now?” rather than a completion debt list:
    /// meal cards surface as preparation suggestions in their own window, the training card
    /// takes priority only around the owner-selected training time, and a completed workout
    /// immediately advances the home card to the next useful preparation step. Meal completion
    /// flags are not consulted here because meal logging is retired; old records remain inert.
    public static func recommend(
        plan: TodayPlan,
        completion: DailyCompletion?,
        schedule: DailyRoutineSchedule? = nil,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> TodayNextStep {
        if completion?.isSkipped == true {
            return .init(
                kind: .skipped,
                eyebrow: "今天已暂停",
                title: "已标记为跳过",
                detail: "不补练、不节食；想恢复执行时，先撤回跳过，再从一项最低版开始。",
                actionLabel: "查看今天日卡"
            )
        }

        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)
        let trainingPending = completion?.trainingOrRecoveryCompleted != true
        let bedtimePending = completion?.bedtimePreparationCompleted != true

        // Meal logging is retired. Meal cards remain available from the on-demand prep flow,
        // but breakfast/lunch/dinner must never become an unfinished debt or prevent today's
        // training-focused plan from reaching completion.
        if isWindDownTime(schedule: schedule, hour: hour, minute: minute) {
            if bedtimePending {
                return .init(
                    kind: .bedtimePreparation,
                    eyebrow: "现在先收尾",
                    title: "完成睡前准备，不再补任务",
                    detail: plan.bedtimePreparation.first ?? "准备明天的饭盒、食材和睡眠环境。",
                    actionLabel: "查看睡前准备"
                )
            }
            return .init(
                kind: .windDown,
                eyebrow: "今天先到这里",
                title: "优先休息，不补餐或补练",
                detail: "餐卡和训练安排仍可查看；现在不需要补任务、补练或压缩睡眠。",
                actionLabel: "查看今天日卡"
            )
        }

        if trainingPending, plan.trainingMode == .recovery {
            return .init(
                kind: .recovery,
                eyebrow: "恢复优先",
                title: "按今天恢复说明安排",
                detail: "优先休息；只有说明允许且无不适时才做轻活动。症状加重或疼痛时停止，不补练。",
                actionLabel: "查看恢复说明"
            )
        }

        if trainingPending, shouldSurfaceTraining(schedule: schedule, hour: hour, minute: minute) {
            return .init(
                kind: .training,
                eyebrow: "到训练时间了",
                title: "开始腰腹与体态训练",
                detail: "先做最低版；今天已记录的运动完成情况会让主任务自动前进，不要求重复训练。",
                actionLabel: "查看训练说明"
            )
        }

        if let meal = suggestedMeal(schedule: schedule, hour: hour, minute: minute, trainingPending: trainingPending) {
            return .init(
                kind: meal.kind,
                eyebrow: "下一步备餐",
                title: "准备\(meal.kind.displayName)餐卡",
                detail: "按餐卡准备这一餐，默认自炊且总操作不超过 20 分钟；不需要记录是否吃过。",
                actionLabel: "查看备餐建议"
            )
        }

        if trainingPending {
            // A workout that is still pending after its preferred window remains available as
            // the fallback action, but it is never placed ahead of the quiet/sleep boundary.
            return .init(
                kind: .training,
                eyebrow: "今天还没动",
                title: "做训练最低版或轻松恢复",
                detail: "如果现在仍有精力且没有不适，可完成最低版；不补时长、不追进度，睡前不强行开始。",
                actionLabel: "查看训练说明"
            )
        }

        if bedtimePending {
            return .init(
                kind: .bedtimePreparation,
                eyebrow: "给明天省脑力",
                title: "完成 3 分钟睡前交接",
                detail: plan.bedtimePreparation.first ?? "准备明天的饭盒、食材和睡眠环境。",
                actionLabel: "查看睡前准备"
            )
        }

        // Training/recovery and sleep preparation are the only remaining daily commitments.
        return .init(
            kind: .finished,
            eyebrow: "今天已完成",
            title: "训练与睡前准备已完成",
            detail: "保持正常进食和休息；无需额外补练或压缩下一餐。",
            actionLabel: "查看今天日卡"
        )
    }

    private struct SuggestedMeal {
        let kind: TodayNextStep.Kind
    }

    private static func shouldSurfaceTraining(
        schedule: DailyRoutineSchedule?,
        hour: Int,
        minute: Int
    ) -> Bool {
        let now = hour * 60 + minute
        guard let schedule else {
            // No owner schedule: keep the broad legacy evening window as a safe fallback.
            return now >= 17 * 60
        }
        let start = schedule.trainingMinutes
        // Give a short lead-in so “现在准备训练” appears shortly before the selected time,
        // while never letting a late-night training preference override the quiet boundary.
        let leadIn = max(0, start - 30)
        // The wind-down guard in `recommend` already handles the circular bedtime interval.
        // Never use `now < bedtime` as an alternate training condition: with a late training
        // preference (for example 23:45) that would incorrectly surface training at breakfast.
        return now >= leadIn
    }

    private static func suggestedMeal(
        schedule: DailyRoutineSchedule?,
        hour: Int,
        minute: Int,
        trainingPending: Bool
    ) -> SuggestedMeal? {
        let now = hour * 60 + minute
        guard let schedule else {
            switch hour {
            case 5..<11: return SuggestedMeal(kind: .breakfast)
            case 11..<16: return SuggestedMeal(kind: .lunch)
            case 16..<22: return SuggestedMeal(kind: .dinner)
            default: return nil
            }
        }
        // Before a user-selected wake time there is no honest “next meal” action. Keep the
        // card quiet and let the fallback explain that the day has not started yet.
        if now < schedule.wakeMinutes {
            return nil
        }
        // Midpoints avoid a 90-minute hard-coded debt window and adapt to any user schedule.
        let breakfastLunch = midpoint(schedule.breakfastMinutes, schedule.lunchMinutes)
        let lunchDinner = midpoint(schedule.lunchMinutes, schedule.dinnerMinutes)
        if now < breakfastLunch { return SuggestedMeal(kind: .breakfast) }
        if now < lunchDinner { return SuggestedMeal(kind: .lunch) }
        // Once the training lead-in starts, training takes precedence over dinner prep.
        if now < schedule.trainingMinutes - 30 || !trainingPending { return SuggestedMeal(kind: .dinner) }
        return nil
    }

    private static func midpoint(_ lhs: Int, _ rhs: Int) -> Int {
        lhs + ((rhs - lhs) / 2)
    }

    /// The schedule changes recommendation order only. A late wake-up never turns an unfinished
    /// breakfast into a debt: after the late-wake boundary it resumes from lunch/dinner and never
    /// loops back to breakfast. We do not write completion, send notifications, or alter food.
    private static func mealOrder(
        plan: TodayPlan,
        completion: DailyCompletion?,
        schedule: DailyRoutineSchedule?,
        hour: Int,
        minute: Int
    ) -> [(TodayNextStep.Kind, MealCard, Bool)] {
        let nowMinutes = hour * 60 + minute
        let order: [TodayNextStep.Kind]
        if let schedule {
            if nowMinutes >= schedule.dinnerMinutes - 60 {
                // The home card is a forward-looking guide, not a debt collector. Once the
                // dinner window is open, an unlogged lunch must not reappear after dinner and
                // crowd out recovery, training or sleep preparation. The lunch card stays
                // available for an honest manual record from the daily card.
                order = [.dinner]
            } else if nowMinutes >= schedule.lunchMinutes - 90
                        || (nowMinutes >= schedule.wakeMinutes && schedule.wakeMinutes >= 11 * 60) {
                order = [.lunch, .dinner]
            } else {
                order = [.breakfast, .lunch, .dinner]
            }
        } else {
            switch hour {
            case 5..<11: order = [.breakfast, .lunch, .dinner]
            case 11..<16: order = [.lunch, .dinner]
            default: order = [.dinner]
            }
        }
        // Keep the ordering boundary fail-closed. `Kind` has non-meal cases for the rest of the
        // home-card flow; should a later edit accidentally include one here, simply omit it
        // rather than crashing the person's daily plan.
        return order.compactMap { kind in
            switch kind {
            case .breakfast: return (.breakfast, plan.breakfast, completion?.breakfastCompleted ?? false)
            case .lunch: return (.lunch, plan.lunch, completion?.lunchCompleted ?? false)
            case .dinner: return (.dinner, plan.dinner, completion?.dinnerCompleted ?? false)
            case .training, .bedtimePreparation, .recovery, .windDown, .finished, .skipped: return nil
            }
        }
    }

    /// The quiet/wind-down interval is circular, but its home-card protection ends no later
    /// than 05:00. A person with a noon wake preference can still deliberately open the app at
    /// 08:00 and see breakfast rather than a false assertion that they are asleep; the schedule
    /// is a recommendation preference, not a surveillance or wake-detection system. This only
    /// prevents a brand-new day's card from prescribing catch-up tasks in the genuinely late
    /// night window.
    private static func isWindDownTime(
        schedule: DailyRoutineSchedule?,
        hour: Int,
        minute: Int
    ) -> Bool {
        let nowMinutes = hour * 60 + minute
        guard let schedule else {
            return nowMinutes >= 22 * 60 + 30 || nowMinutes < 5 * 60
        }
        let bedtime = schedule.bedtimePreparationMinutes
        let latestWindDownEnd = 5 * 60
        if bedtime < latestWindDownEnd {
            return nowMinutes >= bedtime && nowMinutes < latestWindDownEnd
        }
        return nowMinutes >= bedtime || nowMinutes < latestWindDownEnd
    }
}
