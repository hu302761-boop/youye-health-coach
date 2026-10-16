import Foundation

/// A deliberately conservative bridge between the private profile and future planning.
/// It never mutates a meal, training load, calorie framework, goal, or reminder by itself.
/// The UI can show these as reviewable proposals before a person opts into a real plan change.
public struct PersonalizationProposal: Sendable, Equatable, Identifiable {
    public enum Area: String, Sendable, Equatable {
        case schedule = "作息"
        case commute = "通勤"
        case kitchen = "厨房"
        case food = "饮食"
        case goal = "目标"
        case foundation = "运动基础"
        case equipment = "器械"
        case area = "活动范围"
    }

    public let area: Area
    public let title: String
    public let detail: String
    public let confirmationBoundary: String

    public var id: Area { area }

    public init(area: Area, title: String, detail: String, confirmationBoundary: String) {
        self.area = area
        self.title = title
        self.detail = detail
        self.confirmationBoundary = confirmationBoundary
    }
}

public enum PersonalizationAdvisor {
    /// Profile values can improve relevance, but cannot silently overwrite the established 56-day plan.
    /// Each returned item names exactly what needs a separate confirmation in a later planning flow.
    public static func proposals(for profile: UserProfile) -> [PersonalizationProposal] {
        var values: [PersonalizationProposal] = []

        if let goal = normalized(profile.primaryGoal) {
            values.append(.init(
                area: .goal,
                title: "已确认当前关注点",
                detail: "已记录“\(goal)”。当前 8 周计划不会因此被静默改写。",
                confirmationBoundary: "目标、热量框架、连续加量或每周训练结构仍需在单独的变更页逐次确认。"
            ))
        }

        if let experience = normalized(profile.trainingExperience) {
            values.append(.init(
                area: .foundation,
                title: "已记录运动基础",
                detail: "已记录“\(experience)”。后续只能据此提出训练难度候选。",
                confirmationBoundary: "不会跳过最低版、自动加量，或把自述当成医疗/动作评估。"
            ))
        }

        if let equipment = normalized(profile.availableEquipment) {
            values.append(.init(
                area: .equipment,
                title: "已记录可用器械",
                detail: "已记录“\(equipment)”。当前仍以零器械最低版为默认。",
                confirmationBoundary: "使用器械替换动作或改变每周结构前，必须由你确认。"
            ))
        }

        if let schedule = normalized(profile.workSchedule) {
            values.append(.init(
                area: .schedule,
                title: "按你的作息预备提醒",
                detail: "已记录“\(schedule)”。可据此拟定备餐、训练和睡前交接的候选时间。",
                confirmationBoundary: "提醒时间需要你确认；不会自动新增系统通知或改当天训练。"
            ))
        }

        if let commute = normalized(profile.commuteMode) {
            values.append(.init(
                area: .commute,
                title: "把通勤作为恢复背景",
                detail: "已记录“\(commute)”。后续可把疲劳日的建议写成更贴近通勤的低风险活动版本。",
                confirmationBoundary: "不会把通勤步数当作训练完成，也不会自动增加或减少运动量。"
            ))
        }

        if let kitchen = normalized(profile.kitchenSetup) {
            values.append(.init(
                area: .kitchen,
                title: "核对厨房与食谱卡是否匹配",
                detail: "已记录“\(kitchen)”。当前食谱默认电饭锅加一个电磁炉锅、20 分钟内完成。",
                confirmationBoundary: "设备不匹配时，先拍食材并确认文字与克数，再生成当天替换餐；不会自动改菜单。"
            ))
        }

        if let food = normalized(profile.foodPreferences) {
            values.append(.init(
                area: .food,
                title: "把饮食偏好列为替换条件",
                detail: "已记录“\(food)”。后续可据此筛选候选餐卡和等价食材。",
                confirmationBoundary: "涉及热量框架、过敏/禁忌、餐卡或采购数量的变化，均需你逐次确认。"
            ))
        }

        if let area = normalized(profile.approximateArea) {
            values.append(.init(
                area: .area,
                title: "保留模糊活动范围",
                detail: "已记录“\(area)”。仅可用于以后显示待核验的附近运动/采购搜索入口。",
                confirmationBoundary: "不会定位、购买、下单或编造实时价格；精确位置不会被保存。"
            ))
        }

        return values
    }

    public static func missingProfilePrompt(for profile: UserProfile) -> String? {
        let missing = [
            normalized(profile.workSchedule) == nil ? "作息" : nil,
            normalized(profile.commuteMode) == nil ? "通勤" : nil,
            normalized(profile.kitchenSetup) == nil ? "厨房设备" : nil,
            normalized(profile.foodPreferences) == nil ? "饮食偏好" : nil,
            normalized(profile.primaryGoal) == nil ? "当前关注点" : nil,
            normalized(profile.trainingExperience) == nil ? "运动基础" : nil,
            normalized(profile.availableEquipment) == nil ? "可用器械" : nil
        ].compactMap { $0 }
        guard !missing.isEmpty else { return nil }
        return "还可补充\(missing.joined(separator: "、"))；留空也不影响当前 56 天计划。"
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// Builds an owner-confirmed goal update without changing meals, calories, training load, or
/// weekly structure. The caller persists the returned profile value and audit entry together.
public enum GoalAdjustmentService {
    public static func confirmedChange(
        from currentGoal: String?,
        to requestedGoal: String,
        at date: Date = .now
    ) -> (goal: String, change: PlanChange)? {
        let requested = normalized(requestedGoal)
        guard let requested else { return nil }

        let current = normalized(currentGoal)
        guard current != requested else { return nil }

        let change = PlanChange(
            kind: .goal,
            authority: .requiresConfirmation,
            reason: "用户主动确认调整当前目标；本次只更新目标描述，不自动改餐卡、热量、训练加量或每周结构。",
            before: current ?? "未设置",
            after: requested,
            createdAt: date
        )
        return (requested, change)
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
