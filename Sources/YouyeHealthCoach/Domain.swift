import Foundation

public enum TrainingMode: String, Codable, Sendable {
    case standard, recovery
}

public enum PlanChangeKind: String, Codable, Sendable {
    case equivalentIngredient, mealSubstitution, lowImpactTraining, reminderTime, recoveryDowngrade
    case goal, routineSchedule, calorieFramework, progression, weeklyStructure
}

public enum ChangeAuthority: String, Codable, Sendable {
    case automatic, requiresConfirmation
}

/// 仅在用户明确确认后保存的每日热量参考范围；用于计划外餐食的“可能性”提示，不自动改餐卡或训练。
public struct DailyCalorieFramework: Codable, Sendable, Equatable {
    public let lowerBound: Int
    public let upperBound: Int

    public init?(lowerBound: Int, upperBound: Int) {
        guard lowerBound > 0, upperBound >= lowerBound else { return nil }
        self.lowerBound = lowerBound
        self.upperBound = upperBound
    }

    private enum CodingKeys: String, CodingKey { case lowerBound, upperBound }

    /// Restored local data bypasses the confirmation form.  An invalid range must not be able
    /// to turn an imported value into a false "may exceed" intake signal, so fail closed into
    /// the existing read-only recovery path instead of accepting impossible calorie bounds.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let lowerBound = try values.decode(Int.self, forKey: .lowerBound)
        let upperBound = try values.decode(Int.self, forKey: .upperBound)
        guard let framework = Self(lowerBound: lowerBound, upperBound: upperBound) else {
            throw DecodingError.dataCorruptedError(
                forKey: .lowerBound,
                in: values,
                debugDescription: "Daily calorie bounds must be positive and ordered."
            )
        }
        self = framework
    }

    public var range: ClosedRange<Int> { lowerBound...upperBound }
    public var displayName: String { "\(lowerBound)–\(upperBound) kcal/日" }
}

/// 仅用于本人选择的恢复提示，不推断周期、不用于医疗判断，也不会自动调整热量或训练加量。
public enum MenstrualPhase: String, Codable, Sendable, CaseIterable {
    case menstrual
    case follicular
    case ovulation
    case luteal

    public var displayName: String {
        switch self {
        case .menstrual: "经期"
        case .follicular: "卵泡期"
        case .ovulation: "排卵期附近"
        case .luteal: "黄体期"
        }
    }
}

/// 用户主动选择的皮肤关注项。仅生成低刺激护理提示，不用于诊断或推荐产品。
public enum SkinConcern: String, Codable, Sendable, CaseIterable {
    case inflamedAcne
    case dryness
    case redness
    case irritationOrAllergy

    public var displayName: String {
        switch self {
        case .inflamedAcne: "红肿痘"
        case .dryness: "干燥"
        case .redness: "泛红"
        case .irritationOrAllergy: "刺激/疑似过敏"
        }
    }
}

public struct HealthStatus: Codable, Sendable, Equatable {
    public var sleepHours: Double?
    public var restingHeartRateAboveBaseline: Int?
    public var energy: Int?              // 1...5
    public var stress: Int?              // 1...5
    public var hungerOrNightEatingUrge: Int? // 1...5
    public var digestionNote: String?
    public var menstrualPhase: MenstrualPhase?
    public var menstrualDiscomfort: Bool
    public var painOrInjury: Bool
    public var illnessSymptoms: Bool
    public var medicationOrClinicianRestriction: Bool
    public var skinConcerns: [SkinConcern]
    public var skinNote: String?

    public init(
        sleepHours: Double? = nil,
        restingHeartRateAboveBaseline: Int? = nil,
        energy: Int? = nil,
        stress: Int? = nil,
        hungerOrNightEatingUrge: Int? = nil,
        digestionNote: String? = nil,
        menstrualPhase: MenstrualPhase? = nil,
        menstrualDiscomfort: Bool = false,
        painOrInjury: Bool = false,
        illnessSymptoms: Bool = false,
        medicationOrClinicianRestriction: Bool = false,
        skinConcerns: [SkinConcern] = [],
        skinNote: String? = nil
    ) {
        self.sleepHours = sleepHours
        self.restingHeartRateAboveBaseline = restingHeartRateAboveBaseline
        self.energy = energy
        self.stress = stress
        self.hungerOrNightEatingUrge = hungerOrNightEatingUrge
        self.digestionNote = digestionNote
        self.menstrualPhase = menstrualPhase
        self.menstrualDiscomfort = menstrualDiscomfort
        self.painOrInjury = painOrInjury
        self.illnessSymptoms = illnessSymptoms
        self.medicationOrClinicianRestriction = medicationOrClinicianRestriction
        self.skinConcerns = skinConcerns
        self.skinNote = skinNote
    }

    private enum CodingKeys: String, CodingKey {
        case sleepHours, restingHeartRateAboveBaseline, energy, stress, hungerOrNightEatingUrge, digestionNote
        case menstrualPhase, menstrualDiscomfort, painOrInjury, illnessSymptoms, medicationOrClinicianRestriction
        case skinConcerns, skinNote
    }

    /// 健康状态会持续演化：缺失的新增字段必须以安全默认值读取，不能让旧本地资料失效。
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        // Keep a recoverable private history usable if one imported field is malformed, but
        // never let that field enter a recovery decision or weekly average.  The owner may still
        // retain valid booleans (such as pain) from the same status record and record a corrected
        // number later; rejecting the entire file would be less safe and less transparent.
        let decodedSleepHours = try values.decodeIfPresent(Double.self, forKey: .sleepHours)
        sleepHours = Self.isValidSleepHours(decodedSleepHours) ? decodedSleepHours : nil
        let decodedHeartRateDelta = try values.decodeIfPresent(Int.self, forKey: .restingHeartRateAboveBaseline)
        restingHeartRateAboveBaseline = Self.isValidHeartRateDelta(decodedHeartRateDelta) ? decodedHeartRateDelta : nil
        let decodedEnergy = try values.decodeIfPresent(Int.self, forKey: .energy)
        energy = Self.isValidFivePointScore(decodedEnergy) ? decodedEnergy : nil
        let decodedStress = try values.decodeIfPresent(Int.self, forKey: .stress)
        stress = Self.isValidFivePointScore(decodedStress) ? decodedStress : nil
        let decodedHunger = try values.decodeIfPresent(Int.self, forKey: .hungerOrNightEatingUrge)
        hungerOrNightEatingUrge = Self.isValidFivePointScore(decodedHunger) ? decodedHunger : nil
        digestionNote = try values.decodeIfPresent(String.self, forKey: .digestionNote)
        menstrualPhase = try values.decodeIfPresent(MenstrualPhase.self, forKey: .menstrualPhase)
        menstrualDiscomfort = try values.decodeIfPresent(Bool.self, forKey: .menstrualDiscomfort) ?? false
        painOrInjury = try values.decodeIfPresent(Bool.self, forKey: .painOrInjury) ?? false
        illnessSymptoms = try values.decodeIfPresent(Bool.self, forKey: .illnessSymptoms) ?? false
        medicationOrClinicianRestriction = try values.decodeIfPresent(Bool.self, forKey: .medicationOrClinicianRestriction) ?? false
        skinConcerns = try values.decodeIfPresent([SkinConcern].self, forKey: .skinConcerns) ?? []
        skinNote = try values.decodeIfPresent(String.self, forKey: .skinNote)
    }

    public var needsProtectiveDowngrade: Bool {
        painOrInjury || illnessSymptoms || medicationOrClinicianRestriction || menstrualDiscomfort
            || (sleepHours ?? 24) < 6
            || (restingHeartRateAboveBaseline ?? 0) >= 8
    }

    /// 入口再多也不能绕开范围检查：UI、旧本地数据和未来导入路径都在保存前验证。
    public var validationError: String? {
        if !Self.isValidSleepHours(sleepHours) {
            return "睡眠如填写，需为 0–24 小时的有效数值。"
        }
        if !Self.isValidHeartRateDelta(restingHeartRateAboveBaseline) {
            return "静息心率差值如填写，需在 -80 至 +120 次/分之间。"
        }
        if !Self.isValidFivePointScore(energy) { return "精力需为 1–5 分。" }
        if !Self.isValidFivePointScore(stress) { return "压力需为 1–5 分。" }
        if !Self.isValidFivePointScore(hungerOrNightEatingUrge) {
            return "饥饿/夜宵冲动需为 1–5 分。"
        }
        return nil
    }

    private static func isValidSleepHours(_ value: Double?) -> Bool {
        guard let value else { return true }
        return value.isFinite && (0...24).contains(value)
    }

    private static func isValidHeartRateDelta(_ value: Int?) -> Bool {
        guard let value else { return true }
        return (-80...120).contains(value)
    }

    private static func isValidFivePointScore(_ value: Int?) -> Bool {
        guard let value else { return true }
        return (1...5).contains(value)
    }
}

public struct MealCard: Codable, Sendable, Equatable {
    public let title: String
    public let ingredients: [String]
    public let thawAndPortion: String
    public let timedSteps: [String]
    public let portionsAndStorage: String
    public let substitutions: String

    public init(title: String, ingredients: [String], thawAndPortion: String, timedSteps: [String], portionsAndStorage: String, substitutions: String) {
        self.title = title
        self.ingredients = ingredients
        self.thawAndPortion = thawAndPortion
        self.timedSteps = timedSteps
        self.portionsAndStorage = portionsAndStorage
        self.substitutions = substitutions
    }

    /// 早期目录把“第几周/周几”写进了菜名，但计划从 2026-08-10（周一）开始，
    /// 不能把静态标题误呈现成实际星期。保留原始 title 以兼容已存替换记录，界面统一使用此显示名。
    public var displayTitle: String {
        title.replacingOccurrences(of: #"^(?:第\d+周)?周[一二三四五六日]｜"#, with: "", options: .regularExpression)
    }

    /// Older catalogue entries used the generic word “锅” in an otherwise clear two-appliance
    /// recipe. The actual card must never make the owner infer which available pot is meant.
    /// Keep the stored wording compatible with existing private substitutions, but render every
    /// unqualified cooking-pot reference as the one available induction pot. Protected markers
    /// prevent already explicit “电饭锅” and “电磁炉锅” from being rewritten a second time.
    public var visibleTimedSteps: [String] {
        timedSteps.map { step in
            step
                .replacingOccurrences(of: "电磁炉锅", with: "§IP§")
                .replacingOccurrences(of: "电饭锅", with: "§RC§")
                .replacingOccurrences(of: "锅", with: "电磁炉锅")
                .replacingOccurrences(of: "§RC§", with: "电饭锅")
                .replacingOccurrences(of: "§IP§", with: "电磁炉锅")
        }
    }

    /// Small meal entry points should answer “what do I do first?” before asking the owner to
    /// open a long recipe. Keep the authored timestamp so the preview cannot invent a less
    /// precise instruction than the detailed card.
    public var firstExecutionStep: String? {
        visibleTimedSteps.first
    }

    /// The declared total remains absent when a legacy card has no limit. Compact UI must not
    /// quietly turn that absence into a made-up duration.
    public var totalOperationText: String? {
        portionsAndStorage.range(of: #"总操作\s*\d+\s*分钟"#, options: .regularExpression)
            .map { String(portionsAndStorage[$0]) }
    }

    /// A visible, ingredient-derived finish line accompanies the minute-by-minute method on
    /// every rendered card. Timers depend on slice thickness and hob heat, so they never replace
    /// this final check. It is deliberately derived rather than stored in every historical card:
    /// existing local meal substitutions remain decodable, while the UI still never hides the
    /// food-safety boundary from a person cooking a raw animal protein.
    public var foodSafetyFinish: String? {
        let ingredientText = ingredients.joined(separator: " · ")
        var checks: [String] = []
        if ["鸡胸", "鸡腿", "鸡肉", "里脊", "瘦肉", "肉末", "牛肉", "肥牛"].contains(where: ingredientText.contains) {
            checks.append("鸡肉、里脊、肉末或牛肉最厚处无粉红、无血水再出锅")
        }
        if ["鱼片", "鱼柳", "巴沙鱼", "虾仁"].contains(where: ingredientText.contains) {
            checks.append("鱼肉和虾仁全段不透明、无生心再出锅")
        }
        if ingredientText.contains("鸡蛋") {
            checks.append("鸡蛋须蛋液完全凝固再吃或分装")
        }
        guard !checks.isEmpty else { return nil }
        return "出锅前确认：" + checks.joined(separator: "；") + "。"
    }
}

public struct TodayPlan: Codable, Sendable, Equatable {
    public let date: Date
    public var breakfast: MealCard
    public var lunch: MealCard
    public var dinner: MealCard
    public var trainingMode: TrainingMode
    public var trainingInstruction: String
    public var bedtimePreparation: [String]

    public init(date: Date, breakfast: MealCard = DayOnePlan.fallbackBreakfast, lunch: MealCard = DayOnePlan.fallbackLunch, dinner: MealCard, trainingMode: TrainingMode, trainingInstruction: String, bedtimePreparation: [String]) {
        self.date = date
        self.breakfast = breakfast
        self.lunch = lunch
        self.dinner = dinner
        self.trainingMode = trainingMode
        self.trainingInstruction = trainingInstruction
        self.bedtimePreparation = bedtimePreparation
    }

    private enum CodingKeys: String, CodingKey {
        case date, breakfast, lunch, dinner, trainingMode, trainingInstruction, bedtimePreparation
    }

    /// 三餐字段在后续版本加入；老版本仅含晚餐的本地/导入计划仍可安全读取。
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        date = try values.decode(Date.self, forKey: .date)
        dinner = try values.decode(MealCard.self, forKey: .dinner)
        trainingMode = try values.decode(TrainingMode.self, forKey: .trainingMode)
        trainingInstruction = try values.decode(String.self, forKey: .trainingInstruction)
        bedtimePreparation = try values.decode([String].self, forKey: .bedtimePreparation)
        breakfast = try values.decodeIfPresent(MealCard.self, forKey: .breakfast) ?? DayOnePlan.fallbackBreakfast
        lunch = try values.decodeIfPresent(MealCard.self, forKey: .lunch) ?? DayOnePlan.fallbackLunch
    }
}

public struct PlanChange: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let kind: PlanChangeKind
    public let authority: ChangeAuthority
    public let reason: String
    public let before: String
    public let after: String
    public let createdAt: Date
    public var isReverted: Bool

    public init(kind: PlanChangeKind, authority: ChangeAuthority, reason: String, before: String, after: String, createdAt: Date = .now, isReverted: Bool = false) {
        self.id = UUID()
        self.kind = kind
        self.authority = authority
        self.reason = reason
        self.before = before
        self.after = after
        self.createdAt = createdAt
        self.isReverted = isReverted
    }
}

public enum PlanAdjuster {
    /// `at` 是状态实际记录的日期。审计日志和 8 周日历必须标记到该日，不能因为稍后重开或导入而落到“现在”。
    public static func adjustment(for status: HealthStatus, plan: TodayPlan, at date: Date = .now) -> (plan: TodayPlan, change: PlanChange?) {
        // 服务层也会验证用户输入；在调整器再做一次，是为了让 HealthKit、导入或未来
        // 自动化入口都不能用异常数值生成恢复审计或覆写当天日卡。
        guard status.validationError == nil,
              status.needsProtectiveDowngrade,
              plan.trainingMode == .standard else { return (plan, nil) }

        var protectedPlan = plan
        protectedPlan.trainingMode = .recovery
        protectedPlan.trainingInstruction = recoveryInstruction(for: status)
        let reason = recoveryReason(status)
        let change = PlanChange(
            kind: .recoveryDowngrade,
            authority: .automatic,
            reason: reason,
            before: plan.trainingInstruction,
            after: protectedPlan.trainingInstruction,
            createdAt: date
        )
        return (protectedPlan, change)
    }

    public static func authority(for kind: PlanChangeKind) -> ChangeAuthority {
        switch kind {
        case .equivalentIngredient, .lowImpactTraining, .reminderTime, .recoveryDowngrade: .automatic
        case .mealSubstitution: .requiresConfirmation
        case .goal, .routineSchedule, .calorieFramework, .progression, .weeklyStructure: .requiresConfirmation
        }
    }

    private static func recoveryReason(_ status: HealthStatus) -> String {
        if status.painOrInjury { return "已记录疼痛或受伤，训练自动保护性退阶。" }
        if status.illnessSymptoms { return "已记录生病症状，训练自动保护性退阶。" }
        if status.medicationOrClinicianRestriction { return "已记录用药或医生限制，训练自动保护性退阶。" }
        if status.menstrualDiscomfort { return "已记录经期明显不适，训练自动保护性退阶。" }
        if (status.sleepHours ?? 24) < 6 { return "睡眠少于 6 小时，训练自动保护性退阶。" }
        return "静息心率较个人基线高至少 8，训练自动保护性退阶。"
    }

    /// Recovery is not one universal workout. A clinician or medication restriction, and an
    /// active illness, are boundaries the App must not replace with a generic walking target.
    /// Other protective signals may offer optional gentle activity, always with a stop rule.
    private static func recoveryInstruction(for status: HealthStatus) -> String {
        if status.medicationOrClinicianRestriction {
            return "保护性恢复：今天暂停计划训练与任何加量；仅在医生或药品说明明确允许时，按其边界进行日常活动。若不确定则休息；症状、疼痛、头晕或呼吸异常时停止并寻求专业帮助。不补练、不加量。"
        }
        if status.illnessSymptoms {
            return "保护性恢复：今天暂停计划训练和核心动作，以休息、补水和睡眠为先；症状加重、发热、头晕或呼吸异常时停止活动并寻求专业帮助。不补练、不加量。"
        }
        if status.painOrInjury {
            return "保护性恢复：今天不做会加重疼痛的训练；仅在无痛、无头晕且感觉允许时轻松走 5–10 分钟或做温和呼吸。疼痛、麻木或症状加重时停止；不补练、不加量。"
        }
        return "保护性恢复：轻松走 20 分钟 + 90/90 呼吸 5 次、猫牛 8 次、婴儿式呼吸 5 次。疼痛、头晕或症状加重时停止；不补练、不加量。"
    }
}

public enum DayOnePlan {
    public static let fallbackBreakfast = MealCard(
        title: "早餐｜燕麦豆浆鸡蛋果碗",
        ingredients: ["燕麦 40g", "无糖豆浆 300ml", "鸡蛋 2 个（约 100g）", "猕猴桃 100g"],
        thawAndPortion: "前一晚将燕麦 40g 装进带盖碗；鸡蛋保持蛋壳清洁后放电饭锅蒸架，打蛋后洗手。今天做 1 份，不做饭盒。",
        timedSteps: ["0:00 电饭锅加水至最低刻度，放鸡蛋并启动蒸煮。", "0:30 豆浆倒入杯中。", "6:00 剥鸡蛋、切猕猴桃。", "7:00 燕麦拌豆浆，配鸡蛋和水果吃完。"],
        portionsAndStorage: "做 1 份，不做饭盒；鸡蛋可一次蒸 4 个，2 小时内冷藏，3 天内彻底加热一次后吃完。总操作 8 分钟。",
        substitutions: "猕猴桃可换苹果 150g；没有豆浆可换无糖酸奶 200g。"
    )
    public static let fallbackLunch = MealCard(
        title: "午餐｜鸡蛋豆腐青菜饭",
        ingredients: ["鸡蛋 2 个（约 100g）", "北豆腐 200g", "青菜 300g", "熟米饭 135g", "水 300ml"],
        thawAndPortion: "前一晚把豆腐、青菜和熟饭 135g 分装冷藏；鸡蛋保持蛋壳清洁，使用前打蛋后洗手。默认中午在家做 1 份，不留下一餐。午间不在家时，不把这份含蛋、豆腐和熟饭的餐盒当作冷食带走，先拍现有食材并确认重排。",
        timedSteps: ["0:00 电饭锅加水至最低刻度，鸡蛋 2 个放蒸架、熟饭放内胆并启动蒸煮；唯一的电磁炉锅加水 300ml 烧开。", "2:00 下青菜煮 2 分钟。", "4:00 下豆腐煮 1 分钟，沥干装碗。", "5:00 继续蒸鸡蛋和熟饭。", "7:00 剥鸡蛋，确认蛋黄凝固；配热透的熟饭一次吃完。"],
        portionsAndStorage: "做 1 份；食材与熟饭均全程冷藏，熟食须在制作后 2 小时内冷藏。默认在家吃，电饭锅和电磁炉锅食物均加热至中心冒热气后一次吃完。办公室冰箱、微波炉或冷食条件均未确认，不能作为默认步骤；不反复加热。总操作 8 分钟。",
        substitutions: "午间不在家或没有冷藏、复热条件时，请拍现有食材并确认重排当天午餐；青菜可换冷冻西兰花 300g，豆腐可换鸡胸 120g（前夜煮熟冷藏）。"
    )

    public static func make(date: Date = .now) -> TodayPlan {
        return TodayPlan(
            date: date,
            breakfast: fallbackBreakfast,
            lunch: fallbackLunch,
            dinner: MealCard(
                title: "鸡胸绿叶菜（单份）",
                ingredients: ["鸡胸肉片 150g（冷冻来不及解冻则北豆腐 250g）", "绿叶菜 400g", "食用油 5g", "水 40ml", "生抽 5g 或盐 1g"],
                thawAndPortion: "鸡胸提前 8–12 小时放冷藏；来不及解冻直接改北豆腐。今天只做 1 份。",
                timedSteps: ["0:00 中火热电磁炉锅，称油 5g。", "1:00 下鸡胸铺开煎 2 分钟；豆腐则每面煎约 3 分钟。", "3:00 鸡胸翻面再煎 2 分钟，盛出。", "5:00 原锅下绿叶菜和水 40ml，盖盖 3 分钟。", "8:00 加生抽或盐，鸡胸/豆腐回锅翻 1 分钟。", "9:00–12:00 装盘吃完。"],
                portionsAndStorage: "做 1 份，不做饭盒。若有剩余，2 小时内冷藏，明天中午前彻底加热一次后吃完；不反复加热。总操作 12 分钟。",
                substitutions: "绿叶菜可换冷冻西兰花 400g（加水 60ml、盖 5 分钟）；鸡胸/豆腐可换鸡蛋 2 个 + 虾仁 120g。"
            ),
            trainingMode: .standard,
            trainingInstruction: "最低 10 分钟：90/90 呼吸 5 次 → 猫牛 8 次 → 死虫式每侧 6 次 → 臀桥 12 次，做 2 轮。腰痛、头晕或经期明显不适立即停止，改轻松走 20 分钟。",
            bedtimePreparation: ["把明天午餐盒、保温袋和冰袋放好。", "23:45 前熄灯。"]
        )
    }
}

/// 56 天计划开始前只用于准备食材、饭盒与睡眠，不计入计划日，也不显示为第 1 天。
public enum LaunchPreparationPlan {
    public static func make(date: Date = .now, calendar: Calendar = .current) -> TodayPlan {
        // The detailed thaw/portion workflow is safe only on the evening immediately before
        // day one.  Opening the app weeks early must not invite someone to thaw food far too
        // soon merely because all pre-start dates share the preparation phase.
        guard PlanSchedule.isFinalPreparationDay(on: date, calendar: calendar) else {
            return TodayPlan(
                date: date,
                dinner: MealCard(
                    title: "计划尚未开始｜开始前一晚准备",
                    ingredients: ["无需提前解冻或分装"],
                    thawAndPortion: "现在不处理冷冻肉、熟饭或饭盒；到开始前一晚再打开本页完成 10 分钟准备。",
                    timedSteps: ["0:00 查看开始日期和自己的时间表。", "2:00 如需调整起床、三餐或训练时间，只改提醒偏好，不预先标记完成。", "5:00 开始前一晚再将主蛋白转入冷藏并准备饭盒。"],
                    portionsAndStorage: "本页不制作或保存食物，不计入 56 天饮食打卡。",
                    substitutions: "开始前一晚缺少食材时，再拍现有食材并确认重排第 1 天餐卡。"
                ),
                trainingMode: .recovery,
                trainingInstruction: "计划尚未开始：不做计划训练、不预打卡；只按自己的日常活动和休息安排即可。",
                bedtimePreparation: ["开始前一晚再完成食材、饭盒和睡眠准备。"]
            )
        }
        return TodayPlan(
            date: date,
            dinner: MealCard(
                title: "启动准备｜明天第 1 天",
                ingredients: ["去骨鸡腿肉片 300g（冷冻则放入冷藏解冻）", "西兰花 500g（洗净切小朵）", "熟米饭 180g × 2 盒或生米 120g", "食用油 8g", "蒜 5g、生抽 8g、黑胡椒 1g"],
                thawAndPortion: "今晚不强制做正餐。鸡肉从冷冻移到冷藏；明天要做两份，准备 2 个饭盒、保温袋和冰袋。",
                timedSteps: ["0:00 把鸡肉 300g 从冷冻转入冷藏。", "2:00 西兰花洗净切小朵，沥干后冷藏。", "7:00 熟饭分成 180g × 2 盒冷藏/冷冻；没有熟饭则称生米 120g，明天用电饭锅煮。", "10:00 饭盒、保温袋、冰袋放在门口；设好明晚 20 分钟做饭提醒。"],
                portionsAndStorage: "这是启动准备，不计入 56 天饮食打卡。生肉始终冷藏解冻；熟饭 2 小时内冷藏，明天加热到中心冒热气后一次吃完。",
                substitutions: "没有鸡腿肉可准备鸡胸 300g 或北豆腐 500g；没有西兰花可准备花菜或卷心菜 500g。"
            ),
            trainingMode: .recovery,
            trainingInstruction: "今晚不做计划训练。只做 5 分钟轻松走动或呼吸放松；明天开始第 1 天最低完成版。",
            bedtimePreparation: ["把明天的鸡肉从冷冻转到冷藏，蔬菜洗切并准备两只饭盒。", "尽量在 23:45 前熄灯，为明天第 1 天留出恢复。"]
        )
    }
}

/// 两个月计划的第 57–61 天是独立收尾复盘，不循环前 56 天内容。
public enum ClosingProgramPlan {
    public static func make(dayIndex: Int, date: Date = .now) -> TodayPlan {
        let final = dayIndex == 61
        let title = final ? "两个月收尾复盘餐" : "收尾复盘餐 · 第 \(dayIndex) 天"
        return TodayPlan(
            date: date,
            dinner: MealCard(
                title: title,
                ingredients: ["按冰箱已有食材选择已确认的蛋白质、蔬菜和主食"],
                thawAndPortion: "只做今晚 1 份；不自动开启下一周期。",
                timedSteps: ["0:00 核对现有食材与安全保存状态。", "5:00 按已确认食材完成一份自炊餐。", "15:00 记录体重、腰围、睡眠与身体状态。"],
                portionsAndStorage: "收尾日不生成下一天饭盒；熟食 2 小时内冷藏，24 小时内一次彻底加热。",
                substitutions: "缺少食材时使用‘我已有的食材’重新确认，不自动估算热量。"
            ),
            trainingMode: .recovery,
            trainingInstruction: final ? "完成轻松走动、呼吸或已确认的恢复动作，并填写两个月复盘。" : "只做最低恢复版：轻松走动或呼吸 5 分钟。",
            bedtimePreparation: [final ? "完成两个月复盘，确认下一阶段目标。" : "准备明天的睡眠与身体状态记录。"]
        )
    }
}

/// 首个 56 天阶段结束后必须等待用户确认下一阶段，不能循环或回退到启动准备日。
public enum ProgramCompletionPlan {
    public static func make(date: Date = .now) -> TodayPlan {
        TodayPlan(
            date: date,
            dinner: MealCard(
                title: "第 56 天后｜阶段评估",
                ingredients: ["无需新增食材"],
                thawAndPortion: "今天不自动生成下一阶段餐单或采购单。",
                timedSteps: ["0:00 查看完成率、腰围、睡眠与主观恢复。", "5:00 记录疼痛、生病、经期和皮肤状态。", "10:00 决定维持、恢复或提出下一阶段目标，等待本人确认后再排新计划。", "15:00 按冰箱现有食材选择已确认的低风险自炊餐。"],
                portionsAndStorage: "不计入新的计划日；没有确认的新计划前，不自动改变热量、训练量或周结构。",
                substitutions: "沿用已确认的食材等价替换；需要新的餐卡时先由本人确认。"
            ),
            trainingMode: .recovery,
            trainingInstruction: "阶段评估日：只做轻松走动、呼吸或已确认的恢复动作；不自动加量。",
            bedtimePreparation: ["完成 8 周复盘。", "确认下一阶段目标前，不自动开启新的 56 天计划。"]
        )
    }
}
