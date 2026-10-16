import Foundation

/// A user-owned, device-local daily timing preference. It guides which unfinished action is
/// surfaced next; it never creates notifications, marks an item missed, or changes a meal/training plan.
public struct DailyRoutineSchedule: Codable, Sendable, Equatable {
    public let wakeMinutes: Int
    public let breakfastMinutes: Int
    public let lunchMinutes: Int
    public let dinnerMinutes: Int
    public let trainingMinutes: Int
    public let bedtimePreparationMinutes: Int
    public let quietStartMinutes: Int
    public let quietEndMinutes: Int

    public init?(
        wakeMinutes: Int,
        breakfastMinutes: Int,
        lunchMinutes: Int,
        dinnerMinutes: Int,
        trainingMinutes: Int,
        bedtimePreparationMinutes: Int,
        quietStartMinutes: Int,
        quietEndMinutes: Int
    ) {
        let values = [wakeMinutes, breakfastMinutes, lunchMinutes, dinnerMinutes, trainingMinutes, bedtimePreparationMinutes, quietStartMinutes, quietEndMinutes]
        guard values.allSatisfy({ (0..<1_440).contains($0) }) else { return nil }
        self.wakeMinutes = wakeMinutes
        self.breakfastMinutes = breakfastMinutes
        self.lunchMinutes = lunchMinutes
        self.dinnerMinutes = dinnerMinutes
        self.trainingMinutes = trainingMinutes
        self.bedtimePreparationMinutes = bedtimePreparationMinutes
        self.quietStartMinutes = quietStartMinutes
        self.quietEndMinutes = quietEndMinutes
    }

    private enum CodingKeys: String, CodingKey {
        case wakeMinutes, breakfastMinutes, lunchMinutes, dinnerMinutes
        case trainingMinutes, bedtimePreparationMinutes, quietStartMinutes, quietEndMinutes
    }

    /// Decoded profile data bypasses SwiftUI's time pickers. An out-of-range clock value must
    /// make the private profile recoverable-but-read-only instead of producing an invalid
    /// notification trigger, silently wrapping a time, or inventing a substitute schedule.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let wakeMinutes = try values.decode(Int.self, forKey: .wakeMinutes)
        let breakfastMinutes = try values.decode(Int.self, forKey: .breakfastMinutes)
        let lunchMinutes = try values.decode(Int.self, forKey: .lunchMinutes)
        let dinnerMinutes = try values.decode(Int.self, forKey: .dinnerMinutes)
        let trainingMinutes = try values.decode(Int.self, forKey: .trainingMinutes)
        let bedtimePreparationMinutes = try values.decode(Int.self, forKey: .bedtimePreparationMinutes)
        let quietStartMinutes = try values.decode(Int.self, forKey: .quietStartMinutes)
        let quietEndMinutes = try values.decode(Int.self, forKey: .quietEndMinutes)
        guard let schedule = Self(
            wakeMinutes: wakeMinutes,
            breakfastMinutes: breakfastMinutes,
            lunchMinutes: lunchMinutes,
            dinnerMinutes: dinnerMinutes,
            trainingMinutes: trainingMinutes,
            bedtimePreparationMinutes: bedtimePreparationMinutes,
            quietStartMinutes: quietStartMinutes,
            quietEndMinutes: quietEndMinutes
        ) else {
            throw DecodingError.dataCorruptedError(
                forKey: .wakeMinutes,
                in: values,
                debugDescription: "Daily routine clock values must be within 00:00–23:59."
            )
        }
        self = schedule
    }
}

/// A person must opt in to each local reminder individually. A disabled reminder is not replaced
/// by another notification, and this preference never grants permission by itself.
public struct DailyReminderPreferences: Codable, Sendable, Equatable {
    public var breakfastEnabled: Bool
    public var lunchEnabled: Bool
    public var dinnerEnabled: Bool
    public var trainingEnabled: Bool
    public var bedtimePreparationEnabled: Bool

    public init(
        breakfastEnabled: Bool = false,
        lunchEnabled: Bool = false,
        dinnerEnabled: Bool = false,
        trainingEnabled: Bool = false,
        bedtimePreparationEnabled: Bool = false
    ) {
        self.breakfastEnabled = breakfastEnabled
        self.lunchEnabled = lunchEnabled
        self.dinnerEnabled = dinnerEnabled
        self.trainingEnabled = trainingEnabled
        self.bedtimePreparationEnabled = bedtimePreparationEnabled
    }

    public var hasAnyEnabled: Bool {
        breakfastEnabled || lunchEnabled || dinnerEnabled || trainingEnabled || bedtimePreparationEnabled
    }
}

/// Preference only: this MVP neither polls prices nor schedules a notification by itself.
/// It makes the future consent boundary and the owner’s thresholds explicit and exportable.
///
/// The product-level “special offer” floor is also enforced here rather than only in the
/// settings screen.  Local restore/import data bypasses normal SwiftUI validation, so it must
/// not be able to lower the grocery alert floor below ¥15 or raise the swim-entry ceiling above
/// ¥30.
public struct NearbyOfferPreferences: Codable, Sendable, Equatable {
    public var gymRemindersEnabled: Bool
    public var swimmingRemindersEnabled: Bool
    public var bikeRemindersEnabled: Bool
    public var groceryRemindersEnabled: Bool
    public var deliveryRemindersEnabled: Bool
    public var basketSavingsThresholdYuan: Int
    public var swimSingleEntryThresholdYuan: Int

    public init(
        gymRemindersEnabled: Bool = false,
        swimmingRemindersEnabled: Bool = false,
        bikeRemindersEnabled: Bool = false,
        groceryRemindersEnabled: Bool = false,
        deliveryRemindersEnabled: Bool = false,
        basketSavingsThresholdYuan: Int = 15,
        swimSingleEntryThresholdYuan: Int = 30
    ) {
        self.gymRemindersEnabled = gymRemindersEnabled
        self.swimmingRemindersEnabled = swimmingRemindersEnabled
        self.bikeRemindersEnabled = bikeRemindersEnabled
        self.groceryRemindersEnabled = groceryRemindersEnabled
        self.deliveryRemindersEnabled = deliveryRemindersEnabled
        self.basketSavingsThresholdYuan = max(15, basketSavingsThresholdYuan)
        self.swimSingleEntryThresholdYuan = min(30, max(0, swimSingleEntryThresholdYuan))
    }

    private enum CodingKeys: String, CodingKey {
        case gymRemindersEnabled, swimmingRemindersEnabled, bikeRemindersEnabled
        case groceryRemindersEnabled, deliveryRemindersEnabled
        case basketSavingsThresholdYuan, swimSingleEntryThresholdYuan
    }

    /// Codable synthesis assigns stored properties directly and would bypass the policy in the
    /// designated initializer. Route decoded backups through it so a malformed old JSON cannot
    /// silently relax the major-offer threshold.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            gymRemindersEnabled: try values.decodeIfPresent(Bool.self, forKey: .gymRemindersEnabled) ?? false,
            swimmingRemindersEnabled: try values.decodeIfPresent(Bool.self, forKey: .swimmingRemindersEnabled) ?? false,
            bikeRemindersEnabled: try values.decodeIfPresent(Bool.self, forKey: .bikeRemindersEnabled) ?? false,
            groceryRemindersEnabled: try values.decodeIfPresent(Bool.self, forKey: .groceryRemindersEnabled) ?? false,
            deliveryRemindersEnabled: try values.decodeIfPresent(Bool.self, forKey: .deliveryRemindersEnabled) ?? false,
            basketSavingsThresholdYuan: try values.decodeIfPresent(Int.self, forKey: .basketSavingsThresholdYuan) ?? 15,
            swimSingleEntryThresholdYuan: try values.decodeIfPresent(Int.self, forKey: .swimSingleEntryThresholdYuan) ?? 30
        )
    }

    public var hasAnyReminderEnabled: Bool {
        gymRemindersEnabled || swimmingRemindersEnabled || bikeRemindersEnabled || groceryRemindersEnabled || deliveryRemindersEnabled
    }
}

/// 未来附近服务只需要一个可编辑的模糊范围，不需要也不应长期保存楼栋、单元或门牌。
/// 这不是地址识别器：保守地拦住最常见的精确住址标记，并让本人改成小区/商圈/地铁站附近。
public enum ApproximateAreaPolicy {
    public static func normalized(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    public static func validationError(for value: String?) -> String? {
        guard let rawValue = value, let value = normalized(rawValue) else { return nil }
        guard value.count <= 32 else {
            return "附近搜索地点请只填 32 字以内的模糊范围，例如“望京地铁站附近”。"
        }
        let preciseMarkers = ["号楼", "栋", "单元", "室", "门牌"]
        if preciseMarkers.contains(where: value.contains) {
            return "请勿保存楼栋、单元或门牌；改填小区、商圈或地铁站附近即可。"
        }
        return nil
    }
}

public struct UserProfile: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public var displayName: String
    /// 仅保存用户自行选择的模糊区域，例如“望京/望京西站附近”。
    public var approximateArea: String?
    /// 仅由本人填写/确认的静息心率基线；用于把 HealthKit 摘要转成保守恢复信号。
    /// 不填写就不以心率触发任何自动调整。
    public var restingHeartRateBaseline: Double?
    /// 仅由本人确认的每日热量参考范围；未确认时绝不据计划外餐食判定“超标”。
    public var dailyCalorieFramework: DailyCalorieFramework?
    /// 以下偏好仅供本人在本机查看和未来生成“待确认建议”时参考；它们不会自行改目标、
    /// 热量或训练结构，也绝不进入朋友精简周报。
    public var workSchedule: String?
    public var commuteMode: String?
    public var kitchenSetup: String?
    public var foodPreferences: String?
    /// Owner-confirmed personal focus. It is deliberately descriptive rather than a target
    /// weight or diagnostic claim, and never changes the active plan until a later, separate
    /// major-plan confirmation is made.
    public var primaryGoal: String?
    /// Owner-confirmed destination weight for goal review. It is not a scale reading and never
    /// drives calories, training volume, or automatic plan changes.
    public var targetWeightKg: Double?
    /// 用户确认的可持续节奏；只影响建议与复盘提示，不自动调整历史或未来日卡。
    public var sustainableGoal: SustainableGoal?
    /// A short self-described foundation such as “零基础” or “有规律训练”. This lets the
    /// planner present an appropriate candidate without claiming an assessment was performed.
    public var trainingExperience: String?
    /// Equipment actually available to the owner. The current catalogue remains bodyweight-first
    /// unless a separately confirmed plan change is made.
    public var availableEquipment: String?
    /// Optional owner-entered context. It is private and never used to fabricate a calorie target.
    public var heightCm: Double?
    /// Optional inputs used only to prepare an explainable calorie-framework candidate. They do
    /// not change the plan until the owner explicitly confirms the generated range.
    public var ageYears: Int?
    public var calorieFormulaSex: CalorieFormulaSex?
    public var dailyActivityLevel: DailyActivityLevel?
    /// Optional, only because an absent schedule preserves the familiar generic ordering for
    /// existing users. Once present it is still a suggestion layer, never a notification schedule.
    public var dailyRoutineSchedule: DailyRoutineSchedule?
    /// Explicit local-notification preferences. They carry no health/meal details and are not a
    /// proxy for notification permission, which is requested only from the settings action.
    public var dailyReminderPreferences: DailyReminderPreferences?
    /// Local opt-in preferences for a future, separately authorized offer provider.
    public var nearbyOfferPreferences: NearbyOfferPreferences?

    public init(id: UUID = UUID(), displayName: String, approximateArea: String? = nil, restingHeartRateBaseline: Double? = nil, dailyCalorieFramework: DailyCalorieFramework? = nil, workSchedule: String? = nil, commuteMode: String? = nil, kitchenSetup: String? = nil, foodPreferences: String? = nil, primaryGoal: String? = nil, targetWeightKg: Double? = nil, sustainableGoal: SustainableGoal? = nil, trainingExperience: String? = nil, availableEquipment: String? = nil, heightCm: Double? = nil, ageYears: Int? = nil, calorieFormulaSex: CalorieFormulaSex? = nil, dailyActivityLevel: DailyActivityLevel? = nil, dailyRoutineSchedule: DailyRoutineSchedule? = nil, dailyReminderPreferences: DailyReminderPreferences? = nil, nearbyOfferPreferences: NearbyOfferPreferences? = nil) {
        self.id = id
        self.displayName = displayName
        self.approximateArea = Self.safeApproximateArea(approximateArea)
        self.restingHeartRateBaseline = Self.safeRestingHeartRateBaseline(restingHeartRateBaseline)
        self.dailyCalorieFramework = dailyCalorieFramework
        self.workSchedule = workSchedule
        self.commuteMode = commuteMode
        self.kitchenSetup = kitchenSetup
        self.foodPreferences = foodPreferences
        self.primaryGoal = primaryGoal
        self.targetWeightKg = Self.safeTargetWeightKg(targetWeightKg)
        self.sustainableGoal = sustainableGoal
        self.trainingExperience = trainingExperience
        self.availableEquipment = availableEquipment
        self.heightCm = Self.safeHeightCm(heightCm)
        self.ageYears = Self.safeAgeYears(ageYears)
        self.calorieFormulaSex = calorieFormulaSex
        self.dailyActivityLevel = dailyActivityLevel
        self.dailyRoutineSchedule = dailyRoutineSchedule
        self.dailyReminderPreferences = dailyReminderPreferences
        self.nearbyOfferPreferences = nearbyOfferPreferences
    }

    private enum CodingKeys: String, CodingKey {
        case id, displayName, approximateArea, restingHeartRateBaseline, dailyCalorieFramework
        case workSchedule, commuteMode, kitchenSetup, foodPreferences, primaryGoal, targetWeightKg, sustainableGoal, trainingExperience, availableEquipment, heightCm
        case ageYears, calorieFormulaSex, dailyActivityLevel
        case dailyRoutineSchedule, dailyReminderPreferences, nearbyOfferPreferences
    }

    /// 新增热量参考范围不应使既有本地档案无法读取。
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        displayName = try values.decode(String.self, forKey: .displayName)
        approximateArea = Self.safeApproximateArea(try values.decodeIfPresent(String.self, forKey: .approximateArea))
        restingHeartRateBaseline = Self.safeRestingHeartRateBaseline(
            try values.decodeIfPresent(Double.self, forKey: .restingHeartRateBaseline)
        )
        dailyCalorieFramework = try values.decodeIfPresent(DailyCalorieFramework.self, forKey: .dailyCalorieFramework)
        workSchedule = try values.decodeIfPresent(String.self, forKey: .workSchedule)
        commuteMode = try values.decodeIfPresent(String.self, forKey: .commuteMode)
        kitchenSetup = try values.decodeIfPresent(String.self, forKey: .kitchenSetup)
        foodPreferences = try values.decodeIfPresent(String.self, forKey: .foodPreferences)
        primaryGoal = try values.decodeIfPresent(String.self, forKey: .primaryGoal)
        targetWeightKg = Self.safeTargetWeightKg(try values.decodeIfPresent(Double.self, forKey: .targetWeightKg))
        sustainableGoal = try values.decodeIfPresent(SustainableGoal.self, forKey: .sustainableGoal)
        trainingExperience = try values.decodeIfPresent(String.self, forKey: .trainingExperience)
        availableEquipment = try values.decodeIfPresent(String.self, forKey: .availableEquipment)
        heightCm = Self.safeHeightCm(try values.decodeIfPresent(Double.self, forKey: .heightCm))
        ageYears = Self.safeAgeYears(try values.decodeIfPresent(Int.self, forKey: .ageYears))
        calorieFormulaSex = try values.decodeIfPresent(CalorieFormulaSex.self, forKey: .calorieFormulaSex)
        dailyActivityLevel = try values.decodeIfPresent(DailyActivityLevel.self, forKey: .dailyActivityLevel)
        dailyRoutineSchedule = try values.decodeIfPresent(DailyRoutineSchedule.self, forKey: .dailyRoutineSchedule)
        dailyReminderPreferences = try values.decodeIfPresent(DailyReminderPreferences.self, forKey: .dailyReminderPreferences)
        nearbyOfferPreferences = try values.decodeIfPresent(NearbyOfferPreferences.self, forKey: .nearbyOfferPreferences)
    }

    /// A profile can be restored from an older backup without passing through the settings
    /// field.  Keep the exact-address boundary in the model as well as the UI: malformed or
    /// overly precise text is discarded rather than retained locally or copied into an export.
    private static func safeApproximateArea(_ rawValue: String?) -> String? {
        guard let rawValue,
              let normalized = ApproximateAreaPolicy.normalized(rawValue),
              ApproximateAreaPolicy.validationError(for: normalized) == nil else {
            return nil
        }
        return normalized
    }

    private static func safeAgeYears(_ value: Int?) -> Int? {
        guard let value, (18...90).contains(value) else { return nil }
        return value
    }

    /// These optional values are never needed to construct a plan.  Keep malformed restored
    /// numbers out of the private profile rather than relying on downstream UI to notice them:
    /// an invalid baseline could otherwise be copied into every HealthKit recovery request, and
    /// an invalid height would remain in an export despite having no legitimate user meaning.
    private static func safeRestingHeartRateBaseline(_ value: Double?) -> Double? {
        guard let value, value.isFinite, (20...250).contains(value) else { return nil }
        return value
    }

    private static func safeHeightCm(_ value: Double?) -> Double? {
        guard let value, value.isFinite, (50...250).contains(value) else { return nil }
        return value
    }

    private static func safeTargetWeightKg(_ value: Double?) -> Double? {
        guard let value, value.isFinite, (30...300).contains(value) else { return nil }
        return value
    }
}

/// A compact, owner-entered first-run draft. It deliberately excludes calorie targets, progress
/// rules, and weekly structure: completing setup gives the planner context, but never silently
/// applies a major plan change. System permissions are likewise requested later, feature by
/// feature, rather than as part of onboarding.
public struct FirstRunProfileInput: Sendable, Equatable {
    public var displayName: String
    public var primaryGoal: String?
    public var trainingExperience: String?
    public var availableEquipment: String?
    public var kitchenSetup: String?
    public var workSchedule: String?
    public var dailyRoutineSchedule: DailyRoutineSchedule?

    public init(
        displayName: String,
        primaryGoal: String? = nil,
        trainingExperience: String? = nil,
        availableEquipment: String? = nil,
        kitchenSetup: String? = nil,
        workSchedule: String? = nil,
        dailyRoutineSchedule: DailyRoutineSchedule? = nil
    ) {
        self.displayName = displayName
        self.primaryGoal = Self.normalized(primaryGoal)
        self.trainingExperience = Self.normalized(trainingExperience)
        self.availableEquipment = Self.normalized(availableEquipment)
        self.kitchenSetup = Self.normalized(kitchenSetup)
        self.workSchedule = Self.normalized(workSchedule)
        self.dailyRoutineSchedule = dailyRoutineSchedule
    }

    /// Keeps all prior safety-controlled fields intact. The onboarding sheet is contextual only;
    /// daily calorie bounds, health baselines, consent preferences and all plan history are not
    /// changed here.
    public func applying(to existing: UserProfile) -> UserProfile {
        var profile = existing
        profile.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "我" : displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.primaryGoal = primaryGoal
        profile.trainingExperience = trainingExperience
        profile.availableEquipment = availableEquipment
        profile.kitchenSetup = kitchenSetup
        profile.workSchedule = workSchedule
        profile.dailyRoutineSchedule = dailyRoutineSchedule
        return profile
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

public struct DailyCompletion: Codable, Sendable, Equatable {
    public let date: Date
    /// 三餐分别记录，避免早餐已吃就误显示整天饮食完成。`foodCompleted` 仍是三项总览
    /// 的兼容字段：只有当天需要完成的餐次都完成时才为 true。
    public var breakfastCompleted: Bool
    public var lunchCompleted: Bool
    public var dinnerCompleted: Bool
    /// 晚起不形成早餐债务。这个私有标记只说明本人从午餐/晚餐恢复执行，早餐没有
    /// 被记成吃过，也不应被记成失败。
    public var breakfastWaivedForLateWake: Bool
    public var foodCompleted: Bool
    public var trainingOrRecoveryCompleted: Bool
    public var bedtimePreparationCompleted: Bool
    /// An explicit, reversible choice for the whole day. It is distinct from no record: calendar
    /// history must never describe a person who chose to skip as simply having forgotten.
    public var skippedAt: Date?

    public init(
        date: Date,
        foodCompleted: Bool,
        breakfastCompleted: Bool? = nil,
        lunchCompleted: Bool? = nil,
        dinnerCompleted: Bool? = nil,
        breakfastWaivedForLateWake: Bool = false,
        trainingOrRecoveryCompleted: Bool,
        bedtimePreparationCompleted: Bool,
        skippedAt: Date? = nil
    ) {
        self.date = date
        // A pre-meal-slot caller expressing food completion means the legacy whole-food task.
        // Preserve that intent as all three meals completed, rather than silently converting it
        // into a partial day after an app update.
        self.breakfastCompleted = breakfastCompleted ?? foodCompleted
        self.lunchCompleted = lunchCompleted ?? foodCompleted
        self.dinnerCompleted = dinnerCompleted ?? foodCompleted
        self.breakfastWaivedForLateWake = breakfastWaivedForLateWake && !self.breakfastCompleted
        self.foodCompleted = (self.breakfastCompleted || self.breakfastWaivedForLateWake) && self.lunchCompleted && self.dinnerCompleted
        self.trainingOrRecoveryCompleted = trainingOrRecoveryCompleted
        self.bedtimePreparationCompleted = bedtimePreparationCompleted
        self.skippedAt = skippedAt
    }

    public var completedCount: Int {
        [foodCompleted, trainingOrRecoveryCompleted, bedtimePreparationCompleted].filter { $0 }.count
    }

    public var completedMealCount: Int {
        [breakfastCompleted, lunchCompleted, dinnerCompleted].filter { $0 }.count
    }

    public var completedOrWaivedMealCount: Int {
        [(breakfastCompleted || breakfastWaivedForLateWake), lunchCompleted, dinnerCompleted].filter { $0 }.count
    }

    /// Presentation text keeps an execution waiver distinct from an eaten meal. The three-pillar
    /// completion score may correctly treat a late-wake day as food-complete, but it must never
    /// tell the owner that they ate "3/3" meals when breakfast was intentionally not backfilled.
    public var foodProgressDescription: String {
        if breakfastWaivedForLateWake {
            return "已完成 \(completedMealCount) 餐｜早餐无需补"
        }
        return "三餐 \(completedMealCount)/3"
    }

    public var isSkipped: Bool { skippedAt != nil }

    /// A private restore can very occasionally contain two snapshots for one local plan day
    /// (for example, an interrupted save followed by an old-file import).  A day has no action
    /// timestamps, so choosing the first or last snapshot would silently hide an action the
    /// owner recorded.  Merge the independently recorded action flags instead, while retaining
    /// an explicit skip if it appears in either snapshot.  This is only a local repair; normal
    /// user actions still write exactly one record per day.
    public static func merged(
        _ completions: [DailyCompletion],
        date: Date? = nil
    ) -> DailyCompletion? {
        guard let first = completions.first else { return nil }
        let breakfastCompleted = completions.contains { $0.breakfastCompleted }
        let lunchCompleted = completions.contains { $0.lunchCompleted }
        let dinnerCompleted = completions.contains { $0.dinnerCompleted }
        let breakfastWaived = !breakfastCompleted && completions.contains { $0.breakfastWaivedForLateWake }
        return DailyCompletion(
            date: date ?? first.date,
            foodCompleted: false,
            breakfastCompleted: breakfastCompleted,
            lunchCompleted: lunchCompleted,
            dinnerCompleted: dinnerCompleted,
            breakfastWaivedForLateWake: breakfastWaived,
            trainingOrRecoveryCompleted: completions.contains { $0.trainingOrRecoveryCompleted },
            bedtimePreparationCompleted: completions.contains { $0.bedtimePreparationCompleted },
            skippedAt: completions.compactMap(\.skippedAt).max()
        )
    }

    private enum CodingKeys: String, CodingKey {
        case date, foodCompleted, breakfastCompleted, lunchCompleted, dinnerCompleted, breakfastWaivedForLateWake
        case trainingOrRecoveryCompleted, bedtimePreparationCompleted, skippedAt
    }

    /// The explicit-skip flag arrived after the original completion model. Missing data from an
    /// older private file means “not explicitly skipped”, never “skipped”.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        date = try values.decode(Date.self, forKey: .date)
        let legacyFoodCompleted = try values.decodeIfPresent(Bool.self, forKey: .foodCompleted) ?? false
        breakfastCompleted = try values.decodeIfPresent(Bool.self, forKey: .breakfastCompleted) ?? legacyFoodCompleted
        lunchCompleted = try values.decodeIfPresent(Bool.self, forKey: .lunchCompleted) ?? legacyFoodCompleted
        dinnerCompleted = try values.decodeIfPresent(Bool.self, forKey: .dinnerCompleted) ?? legacyFoodCompleted
        breakfastWaivedForLateWake = (try values.decodeIfPresent(Bool.self, forKey: .breakfastWaivedForLateWake) ?? false) && !breakfastCompleted
        foodCompleted = (breakfastCompleted || breakfastWaivedForLateWake) && lunchCompleted && dinnerCompleted
        trainingOrRecoveryCompleted = try values.decodeIfPresent(Bool.self, forKey: .trainingOrRecoveryCompleted) ?? false
        bedtimePreparationCompleted = try values.decodeIfPresent(Bool.self, forKey: .bedtimePreparationCompleted) ?? false
        skippedAt = try values.decodeIfPresent(Date.self, forKey: .skippedAt)
    }
}

/// 私有健康资料。原始 HealthKit 样本、照片、视频、精确位置均不属于可分享的资料结构。
public struct PrivateCoachData: Codable, Sendable, Equatable {
    /// HealthKit data is read into a transient `HealthSnapshot` for the current screen only.
    /// The full snapshot and every raw sample stay out of this owner-local JSON schema. A minimal
    /// user-visible recovery state may be saved only when it has actually triggered (or the user
    /// entered it) so today's protective plan can survive an app restart; it is not a HealthKit
    /// history, never includes source samples, and is excluded from voluntary friend reports.
    public static let persistsHealthKitSnapshots = false
    public var profile: UserProfile
    public var dailyCompletions: [DailyCompletion]
    public var planChanges: [PlanChange]
    public var healthStatusNotes: [HealthStatus]
    public var datedHealthStatusNotes: [DatedHealthStatus]
    public var unplannedMealLogs: [UnplannedMealLog]
    public var actualMealLogs: [ActualMealLog]
    public var mealSubstitutions: [ConfirmedMealSubstitution]
    /// 仅保存用户确认生成的精简周报；它们仍在本机，未代表发送或对外同步。
    public var sharedWeeklyReports: [SharedWeeklyReport]
    /// 按实际自然月分开保存的账本。旧版单一 budgetLedger 会在解码时迁移进该数组。
    public var monthlyBudgetLedgers: [MonthlyBudgetLedger]
    /// 本人主动记录的体重/腰围周趋势点；不等于 HealthKit 原始数据。
    public var weeklyBodyCheckIns: [WeeklyBodyCheckIn]
    public var budgetLedger: MonthlyBudgetLedger
    public var trainingFeedback: [TrainingFeedback]
    /// 用户确认导入的 Apple 健康或截图训练摘要。只保存最小时间、类型和时长，不保存原始截图或 HealthKit 样本。
    public var importedWorkoutRecords: [ImportedWorkoutRecord]
    /// Legacy local receipt fields retained only so old private JSON remains decodable. New
    /// versions never create, update, display, export, or send these values to Apple Health.
    public var healthWorkoutSyncs: [HealthWorkoutSyncRecord]
    /// Legacy uncertain-write fields retained only for non-destructive decoding of old private
    /// JSON. They no longer create a retry, reminder, UI state, or Apple Health operation.
    public var pendingHealthWorkoutSyncs: [PendingHealthWorkoutSyncRecord]
    /// A real timer was stopped, and the owner left the training detail. This is an App-private
    /// confirmation draft; it is never an Apple Health write attempt or HealthKit record.
    public var pendingWorkoutConfirmations: [PendingWorkoutConfirmation]
    /// Option-aware local sessions for the flexible-training path. Pending drafts remain visible
    /// until the owner confirms or discards them; they never imply an Apple Health write.
    public var pendingFlexibleTrainingDrafts: [FlexibleTrainingDraft]
    public var flexibleTrainingSessions: [FlexibleTrainingSession]
    public var trainingCards: [TrainingCard]
    /// 用户手动勾选的采购完成项；不代表下单、购买或价格确认。
    public var purchasedShoppingItemKeys: Set<String>
    /// 用户确认家中已有的采购项；按周隔离，不代表已购或实际库存数量。
    public var atHomeShoppingItemKeys: Set<String>
    /// 本机已有食材清单，仅用于备餐与采购建议；不属于餐食记录或热量数据。
    public var availableIngredients: [AvailableIngredient]

    public init(profile: UserProfile, dailyCompletions: [DailyCompletion] = [], planChanges: [PlanChange] = [], healthStatusNotes: [HealthStatus] = [], datedHealthStatusNotes: [DatedHealthStatus] = [], unplannedMealLogs: [UnplannedMealLog] = [], actualMealLogs: [ActualMealLog] = [], mealSubstitutions: [ConfirmedMealSubstitution] = [], sharedWeeklyReports: [SharedWeeklyReport] = [], budgetLedger: MonthlyBudgetLedger = MonthlyBudgetLedger(monthKey: "2026-08"), monthlyBudgetLedgers: [MonthlyBudgetLedger]? = nil, weeklyBodyCheckIns: [WeeklyBodyCheckIn] = [], trainingFeedback: [TrainingFeedback] = [], importedWorkoutRecords: [ImportedWorkoutRecord] = [], healthWorkoutSyncs: [HealthWorkoutSyncRecord] = [], pendingHealthWorkoutSyncs: [PendingHealthWorkoutSyncRecord] = [], pendingWorkoutConfirmations: [PendingWorkoutConfirmation] = [], pendingFlexibleTrainingDrafts: [FlexibleTrainingDraft] = [], flexibleTrainingSessions: [FlexibleTrainingSession] = [], trainingCards: [TrainingCard] = [], purchasedShoppingItemKeys: Set<String> = [], atHomeShoppingItemKeys: Set<String> = [], availableIngredients: [AvailableIngredient] = []) {
        self.profile = profile
        self.dailyCompletions = Self.normalizedDailyCompletions(dailyCompletions)
        self.planChanges = planChanges
        self.healthStatusNotes = healthStatusNotes
        self.datedHealthStatusNotes = datedHealthStatusNotes
        self.unplannedMealLogs = unplannedMealLogs
        self.actualMealLogs = actualMealLogs
        self.mealSubstitutions = mealSubstitutions
        self.sharedWeeklyReports = sharedWeeklyReports
        self.budgetLedger = budgetLedger
        self.monthlyBudgetLedgers = monthlyBudgetLedgers ?? [budgetLedger]
        self.weeklyBodyCheckIns = weeklyBodyCheckIns
        self.trainingFeedback = trainingFeedback
        self.importedWorkoutRecords = importedWorkoutRecords
        self.healthWorkoutSyncs = healthWorkoutSyncs
        self.pendingHealthWorkoutSyncs = pendingHealthWorkoutSyncs
        self.pendingWorkoutConfirmations = pendingWorkoutConfirmations
        self.pendingFlexibleTrainingDrafts = pendingFlexibleTrainingDrafts
        self.flexibleTrainingSessions = flexibleTrainingSessions
        self.trainingCards = trainingCards
        self.purchasedShoppingItemKeys = purchasedShoppingItemKeys
        self.atHomeShoppingItemKeys = atHomeShoppingItemKeys
        self.availableIngredients = availableIngredients
    }

    private enum CodingKeys: String, CodingKey {
        case profile, dailyCompletions, planChanges, healthStatusNotes, datedHealthStatusNotes
        case unplannedMealLogs, actualMealLogs, mealSubstitutions, sharedWeeklyReports, budgetLedger, monthlyBudgetLedgers, weeklyBodyCheckIns, trainingFeedback, importedWorkoutRecords, healthWorkoutSyncs, pendingHealthWorkoutSyncs, pendingWorkoutConfirmations, pendingFlexibleTrainingDrafts, flexibleTrainingSessions, trainingCards, purchasedShoppingItemKeys, atHomeShoppingItemKeys, availableIngredients
    }

    /// 数据结构新增“餐食替换”后，旧版本地 JSON 仍可读取；缺失字段按空历史处理。
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        profile = try values.decode(UserProfile.self, forKey: .profile)
        dailyCompletions = Self.normalizedDailyCompletions(
            try values.decodeIfPresent([DailyCompletion].self, forKey: .dailyCompletions) ?? []
        )
        planChanges = try values.decodeIfPresent([PlanChange].self, forKey: .planChanges) ?? []
        healthStatusNotes = try values.decodeIfPresent([HealthStatus].self, forKey: .healthStatusNotes) ?? []
        datedHealthStatusNotes = try values.decodeIfPresent([DatedHealthStatus].self, forKey: .datedHealthStatusNotes) ?? []
        unplannedMealLogs = try values.decodeIfPresent([UnplannedMealLog].self, forKey: .unplannedMealLogs) ?? []
        actualMealLogs = try values.decodeIfPresent([ActualMealLog].self, forKey: .actualMealLogs) ?? []
        mealSubstitutions = try values.decodeIfPresent([ConfirmedMealSubstitution].self, forKey: .mealSubstitutions) ?? []
        sharedWeeklyReports = try values.decodeIfPresent([SharedWeeklyReport].self, forKey: .sharedWeeklyReports) ?? []
        budgetLedger = try values.decodeIfPresent(MonthlyBudgetLedger.self, forKey: .budgetLedger) ?? MonthlyBudgetLedger(monthKey: "2026-08")
        monthlyBudgetLedgers = try values.decodeIfPresent([MonthlyBudgetLedger].self, forKey: .monthlyBudgetLedgers) ?? [budgetLedger]
        weeklyBodyCheckIns = try values.decodeIfPresent([WeeklyBodyCheckIn].self, forKey: .weeklyBodyCheckIns) ?? []
        trainingFeedback = try values.decodeIfPresent([TrainingFeedback].self, forKey: .trainingFeedback) ?? []
        importedWorkoutRecords = try values.decodeIfPresent([ImportedWorkoutRecord].self, forKey: .importedWorkoutRecords) ?? []
        healthWorkoutSyncs = try values.decodeIfPresent([HealthWorkoutSyncRecord].self, forKey: .healthWorkoutSyncs) ?? []
        pendingHealthWorkoutSyncs = try values.decodeIfPresent([PendingHealthWorkoutSyncRecord].self, forKey: .pendingHealthWorkoutSyncs) ?? []
        pendingWorkoutConfirmations = try values.decodeIfPresent([PendingWorkoutConfirmation].self, forKey: .pendingWorkoutConfirmations) ?? []
        pendingFlexibleTrainingDrafts = try values.decodeIfPresent([FlexibleTrainingDraft].self, forKey: .pendingFlexibleTrainingDrafts) ?? []
        flexibleTrainingSessions = try values.decodeIfPresent([FlexibleTrainingSession].self, forKey: .flexibleTrainingSessions) ?? []
        trainingCards = try values.decodeIfPresent([TrainingCard].self, forKey: .trainingCards) ?? []
        purchasedShoppingItemKeys = try values.decodeIfPresent(Set<String>.self, forKey: .purchasedShoppingItemKeys) ?? []
        atHomeShoppingItemKeys = try values.decodeIfPresent(Set<String>.self, forKey: .atHomeShoppingItemKeys) ?? []
        availableIngredients = try values.decodeIfPresent([AvailableIngredient].self, forKey: .availableIngredients) ?? []
    }

    /// Read the week-scoped at-home state for a shopping row.
    public func isShoppingItemAtHome(_ item: ShoppingItem, in plan: WeeklyShoppingPlan) -> Bool {
        ShoppingPurchaseState.isMarkedAtHome(item, in: plan, keys: atHomeShoppingItemKeys)
    }

    /// Toggle a single row without mutating the original weekly plan or purchased history.
    public mutating func toggleShoppingItemAtHome(_ item: ShoppingItem, in plan: WeeklyShoppingPlan) {
        atHomeShoppingItemKeys = ShoppingPurchaseState.toggledAtHome(item, in: plan, keys: atHomeShoppingItemKeys)
    }

    /// Inventory is only a candidate aid: matching never claims that the quantity is sufficient.
    public func availableIngredients(matching item: ShoppingItem) -> [AvailableIngredient] {
        AvailableIngredientInventory.matchingIngredients(for: item, in: availableIngredients)
    }

    /// Read one coherent completion snapshot for a local calendar day even if a caller is
    /// holding a damaged in-memory value that has not yet gone through JSON restoration.
    /// All completion consumers should use this instead of selecting an arbitrary duplicate.
    public func dailyCompletion(for date: Date, calendar: Calendar = .current) -> DailyCompletion? {
        DailyCompletion.merged(
            dailyCompletions.filter { calendar.isDate($0.date, inSameDayAs: date) },
            date: calendar.startOfDay(for: date)
        )
    }

    /// Reconciles explicit evidence created by older App builds that saved an actual meal or a
    /// “completed” training feedback but did not yet write a matching daily snapshot. A real
    /// completion snapshot always wins, including explicit false flags, so this read repair never
    /// overrides a later owner action. Timer drafts and non-completion feedback are deliberately
    /// excluded; the derived value is not persisted and never invents bedtime preparation.
    public func executionCompletion(for date: Date, calendar: Calendar = .current) -> DailyCompletion? {
        if let completion = dailyCompletion(for: date, calendar: calendar) { return completion }
        let recordedSlots = Set(
            actualMealLogs
                .filter { calendar.isDate($0.date, inSameDayAs: date) }
                .map { $0.slot.rawValue }
        )
        let hasCompletedTrainingFeedback = trainingFeedback.contains {
            $0.completed && calendar.isDate($0.date, inSameDayAs: date)
        }
        guard !recordedSlots.isEmpty || hasCompletedTrainingFeedback else { return nil }
        return DailyCompletion(
            date: calendar.startOfDay(for: date),
            foodCompleted: false,
            breakfastCompleted: recordedSlots.contains(MealSlot.breakfast.rawValue),
            lunchCompleted: recordedSlots.contains(MealSlot.lunch.rawValue),
            dinnerCompleted: recordedSlots.contains(MealSlot.dinner.rawValue),
            trainingOrRecoveryCompleted: hasCompletedTrainingFeedback,
            bedtimePreparationCompleted: false
        )
    }

    /// Keep all first-party surfaces deterministic after a repaired local restore.  The app's
    /// existing calendar policy is defined in the device's current local calendar, so use that
    /// same boundary here rather than introducing a second UTC interpretation for saved days.
    private static func normalizedDailyCompletions(
        _ completions: [DailyCompletion],
        calendar: Calendar = .current
    ) -> [DailyCompletion] {
        var groups: [(day: Date, values: [DailyCompletion])] = []
        for completion in completions {
            let day = calendar.startOfDay(for: completion.date)
            if let index = groups.firstIndex(where: { calendar.isDate($0.day, inSameDayAs: day) }) {
                groups[index].values.append(completion)
            } else {
                groups.append((day, [completion]))
            }
        }
        return groups.compactMap { group in
            // Keep an original timestamp.  Replacing it with a `Calendar.current` day-start
            // would change the apparent day for a restore later viewed with another calendar
            // (for example, a traveller or a test/recovery using a fixed calendar).
            DailyCompletion.merged(group.values, date: group.values.first?.date)
        }
    }

    public func ledger(for date: Date, calendar: Calendar = .current) -> MonthlyBudgetLedger {
        let key = MonthlyBudgetLedger.monthKey(for: date, calendar: calendar)
        guard let stored = monthlyBudgetLedgers.first(where: { $0.monthKey == key }) else {
            return MonthlyBudgetLedger(monthKey: key)
        }
        // `recordExpense` always files a record into its calendar month. This read-time filter
        // additionally protects legacy/imported JSON with a wrongly bucketed expense.
        return MonthlyBudgetLedger(
            monthKey: key,
            capYuan: stored.capYuan,
            entries: stored.entries.filter {
                MonthlyBudgetLedger.monthKey(for: $0.date, calendar: calendar) == key
            }
        )
    }

    /// Totals a program-week reservation across every natural-month ledger it touches.  A week
    /// can cross a month boundary, so reading only `ledger(for: today)` would silently omit
    /// receipts from the following month.  Future-dated/imported receipts remain excluded from
    /// the display snapshot, while receipts later on the reviewed calendar day are included.
    public func confirmedSpentYuan(
        in category: BudgetCategory,
        during interval: DateInterval,
        asOf date: Date,
        calendar: Calendar = .current
    ) -> Decimal {
        let nextDay = calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: date)
        ) ?? date.addingTimeInterval(24 * 60 * 60)

        guard interval.start < interval.end else { return 0 }
        let startComponents = calendar.dateComponents([.year, .month], from: interval.start)
        guard var monthCursor = calendar.date(from: startComponents) else { return 0 }

        var total: Decimal = 0
        var seenEntryIDs = Set<UUID>()
        while monthCursor < interval.end {
            // Reuse the canonical month reader. It filters misplaced imported receipts and has
            // deterministic behavior if a damaged JSON file somehow contains duplicate month
            // ledgers, instead of summing both copies.
            let canonicalMonthLedger = ledger(for: monthCursor, calendar: calendar)
            total += canonicalMonthLedger.entries
                .filter {
                    $0.isUserConfirmed && $0.category == category && $0.amountYuan >= 0
                        && $0.date >= interval.start && $0.date < interval.end
                        && $0.date < nextDay
                }
                .filter { seenEntryIDs.insert($0.id).inserted }
                .reduce(0) { $0 + $1.amountYuan }

            guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: monthCursor) else {
                break
            }
            monthCursor = nextMonth
        }
        return total
    }

    public mutating func recordExpense(_ entry: ExpenseEntry, calendar: Calendar = .current) {
        let key = MonthlyBudgetLedger.monthKey(for: entry.date, calendar: calendar)
        if let index = monthlyBudgetLedgers.firstIndex(where: { $0.monthKey == key }) {
            monthlyBudgetLedgers[index].record(entry)
        } else {
            var ledger = MonthlyBudgetLedger(monthKey: key)
            ledger.record(entry)
            monthlyBudgetLedgers.append(ledger)
        }
        // 保持旧字段可读，供旧版导出和迁移；当前 UI 使用上方的按月账本。
        if budgetLedger.monthKey == key { budgetLedger = ledger(for: entry.date, calendar: calendar) }
    }
}

public struct HealthWorkoutSyncRecord: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let sessionID: UUID
    public let startedAt: Date
    public let endedAt: Date
    public let kind: ConfirmedHealthWorkoutKind
    public let savedAt: Date

    public init(id: UUID, sessionID: UUID, startedAt: Date, endedAt: Date, kind: ConfirmedHealthWorkoutKind, savedAt: Date = .now) {
        self.id = id
        self.sessionID = sessionID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.kind = kind
        self.savedAt = savedAt
    }
}

/// A legacy, privacy-minimal marker that may appear in an older local JSON file. It is inert in
/// this version and is deliberately not a claim that Apple Health contains the workout.
public struct PendingHealthWorkoutSyncRecord: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let sessionID: UUID
    public let startedAt: Date
    public let endedAt: Date
    public let kind: ConfirmedHealthWorkoutKind
    public let attemptedAt: Date
    /// Legacy data only. New versions do not show a review reminder or issue a retry.
    public let reviewedAt: Date?

    public init(id: UUID = UUID(), sessionID: UUID, startedAt: Date, endedAt: Date, kind: ConfirmedHealthWorkoutKind, attemptedAt: Date = .now, reviewedAt: Date? = nil) {
        self.id = id
        self.sessionID = sessionID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.kind = kind
        self.attemptedAt = attemptedAt
        self.reviewedAt = reviewedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, sessionID, startedAt, endedAt, kind, attemptedAt, reviewedAt
    }

    /// Pending markers created before the manual-review flag existed remain uncertain and must
    /// therefore reappear in the review list after upgrade, rather than being silently treated
    /// as reviewed or making the whole private profile fail to decode.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        sessionID = try values.decode(UUID.self, forKey: .sessionID)
        startedAt = try values.decode(Date.self, forKey: .startedAt)
        endedAt = try values.decode(Date.self, forKey: .endedAt)
        kind = try values.decode(ConfirmedHealthWorkoutKind.self, forKey: .kind)
        attemptedAt = try values.decode(Date.self, forKey: .attemptedAt)
        reviewedAt = try values.decodeIfPresent(Date.self, forKey: .reviewedAt)
    }
}

/// A stopped, user-timed workout that still awaits the owner's explicit Apple Health decision.
/// It is deliberately separate from `PendingHealthWorkoutSyncRecord`: no HealthKit request has
/// happened yet, so this record must never be presented as “sync failed” or “pending Health”.
public struct PendingWorkoutConfirmation: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let workout: ConfirmedHealthWorkout
    public let savedAt: Date

    public init(id: UUID = UUID(), workout: ConfirmedHealthWorkout, savedAt: Date = .now) {
        self.id = id
        self.workout = workout
        self.savedAt = savedAt
    }
}

public struct WeeklyReportSelection: Codable, Sendable, Equatable {
    public var goalProgress: String?
    public var subjectiveReflection: String?
    public var helpRequest: String?

    public init(goalProgress: String? = nil, subjectiveReflection: String? = nil, helpRequest: String? = nil) {
        self.goalProgress = goalProgress
        self.subjectiveReflection = subjectiveReflection
        self.helpRequest = helpRequest
    }
}

/// 周报预览不是分享对象：它不含用户档案、健康状态、餐食/训练明细或任何本地照片引用。
/// 只有用户在预览页逐次确认后，才会转成可分享的精简摘要。
public struct WeeklyReportPreview: Sendable, Equatable {
    public let weekStart: Date
    /// 只含已发生的正式计划日；准备日和未来日不会被当成未完成。
    public let observedPlanDays: Int
    /// 明确跳过保留为可见状态，不等同于忘记记录。
    public let explicitlySkippedPlanDays: Int
    public let completionRate: Double
    public let selection: WeeklyReportSelection

    public init(weekStart: Date, observedPlanDays: Int, explicitlySkippedPlanDays: Int, completionRate: Double, selection: WeeklyReportSelection) {
        self.weekStart = weekStart
        self.observedPlanDays = observedPlanDays
        self.explicitlySkippedPlanDays = explicitlySkippedPlanDays
        self.completionRate = completionRate
        self.selection = selection
    }
}

/// 仅在用户逐次确认后创建的、可撤回的本地精简周报。
///
/// 周报归属由包含它的 `PrivateCoachData`（即该设备当前的私有档案）决定，故不在
/// 周报本身重复保存 owner UUID。这样即使未来出现系统分享入口，也不会因误把本地
/// 记录直接当成分享负载而泄露内部资料标识。
public struct SharedWeeklyReport: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let weekStart: Date
    /// 生成时实际已发生的正式计划日数量，避免当前周把未来日期误当未完成。
    public let observedPlanDays: Int
    /// 仅供本人/获授权的摘要读者理解“明确跳过”与遗漏的区别；不含任何健康原因。
    public let explicitlySkippedPlanDays: Int
    public let completionRate: Double
    public let selection: WeeklyReportSelection
    public let consentedAt: Date
    public var revokedAt: Date?

    public init(weekStart: Date, observedPlanDays: Int = 0, explicitlySkippedPlanDays: Int = 0, completionRate: Double, selection: WeeklyReportSelection, consentedAt: Date = .now, revokedAt: Date? = nil) {
        self.id = UUID()
        self.weekStart = weekStart
        self.observedPlanDays = observedPlanDays
        self.explicitlySkippedPlanDays = explicitlySkippedPlanDays
        self.completionRate = completionRate
        self.selection = selection
        self.consentedAt = consentedAt
        self.revokedAt = revokedAt
    }

    private enum CodingKeys: String, CodingKey {
        // `ownerID` deliberately remains a legacy decoding key only. Earlier local records
        // decode safely, then the next owner-local save removes that redundant identifier.
        case id, ownerID, weekStart, observedPlanDays, explicitlySkippedPlanDays, completionRate, selection, consentedAt, revokedAt
    }

    /// 旧版本地周报没有复盘范围时可继续读取；0 表示历史记录未保存该说明，而非“0 天完成”。
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        weekStart = try values.decode(Date.self, forKey: .weekStart)
        observedPlanDays = try values.decodeIfPresent(Int.self, forKey: .observedPlanDays) ?? 0
        explicitlySkippedPlanDays = try values.decodeIfPresent(Int.self, forKey: .explicitlySkippedPlanDays) ?? 0
        completionRate = try values.decode(Double.self, forKey: .completionRate)
        selection = try values.decode(WeeklyReportSelection.self, forKey: .selection)
        consentedAt = try values.decode(Date.self, forKey: .consentedAt)
        revokedAt = try values.decodeIfPresent(Date.self, forKey: .revokedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(weekStart, forKey: .weekStart)
        try values.encode(observedPlanDays, forKey: .observedPlanDays)
        try values.encode(explicitlySkippedPlanDays, forKey: .explicitlySkippedPlanDays)
        try values.encode(completionRate, forKey: .completionRate)
        try values.encode(selection, forKey: .selection)
        try values.encode(consentedAt, forKey: .consentedAt)
        try values.encodeIfPresent(revokedAt, forKey: .revokedAt)
    }

    /// Reports created from `WeeklyReviewService` always satisfy these bounds. Keep the check
    /// separate from Codable decoding so an older/local corrupted record remains recoverable in
    /// the owner's private data, while it can never be promoted into a future external payload.
    /// This is summary-shape validation only: it does not inspect or derive any health, meal,
    /// location, photo, or profile information.
    fileprivate var hasValidVoluntarySummary: Bool {
        observedPlanDays >= 0
            && observedPlanDays <= 7
            && explicitlySkippedPlanDays >= 0
            && explicitlySkippedPlanDays <= observedPlanDays
            && completionRate.isFinite
            && (0...1).contains(completionRate)
    }

    /// Local corrupted history remains visible enough to be revoked or removed by its owner,
    /// but it must not be formatted as a plausible progress score.  In particular, converting
    /// a non-finite restored `Double` to `Int` in a SwiftUI label can trap.  This presentation
    /// value never repairs, shares, or silently deletes the underlying local record.
    public var localDisplayCompletionPercentage: Int? {
        guard hasValidVoluntarySummary else { return nil }
        return Int((completionRate * 100).rounded())
    }
}

/// The only shape a future, separately-confirmed system share flow may pass outside the App.
/// It has no profile or owner identifier, consent timestamp, revocation state, health status,
/// meal/training detail, budget, location, HealthKit data, or local file reference.
public struct VoluntaryWeeklyReportPayload: Codable, Sendable, Equatable {
    /// A relative week label rather than an exact calendar date. The recipient only needs to
    /// understand whether this is the current or prior completed week; transmitting the
    /// original week-start date adds an unnecessary behavioural timestamp to a friend report.
    public let period: VoluntaryWeeklyReportPeriod
    public let observedPlanDays: Int
    public let explicitlySkippedPlanDays: Int
    public let completionRate: Double
    public let selection: WeeklyReportSelection

    fileprivate init(report: SharedWeeklyReport) {
        period = report.observedPlanDays >= 7 ? .completedWeek : .currentWeekSoFar
        observedPlanDays = report.observedPlanDays
        explicitlySkippedPlanDays = report.explicitlySkippedPlanDays
        completionRate = report.completionRate
        selection = report.selection
    }
}

/// The future external summary deliberately avoids a precise week/date. It is presentation
/// context only and does not affect local review, export, or the current plan.
public enum VoluntaryWeeklyReportPeriod: String, Codable, Sendable, Equatable {
    case currentWeekSoFar
    case completedWeek

    public var displayName: String {
        switch self {
        case .currentWeekSoFar: "本周截至目前"
        case .completedWeek: "已完成的一周"
        }
    }
}

public enum WeeklyReportSharing {
    public static func preview(
        from data: PrivateCoachData,
        weekStart: Date,
        selection: WeeklyReportSelection,
        asOf date: Date = .now,
        calendar: Calendar = .current
    ) -> WeeklyReportPreview {
        let review = WeeklyReviewService.summary(for: weekStart, data: data, asOf: date, calendar: calendar)
        return WeeklyReportPreview(
            weekStart: weekStart,
            observedPlanDays: review.observedPlanDays,
            explicitlySkippedPlanDays: review.explicitlySkippedPlanDays,
            completionRate: review.completionRate,
            selection: selection
        )
    }

    /// `confirmed` 只能由分享预览页的明确点击传入；默认不生成分享内容。
    public static func makeReport(
        from data: PrivateCoachData,
        weekStart: Date,
        selection: WeeklyReportSelection,
        confirmed: Bool,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> SharedWeeklyReport? {
        guard confirmed else { return nil }
        let preview = preview(from: data, weekStart: weekStart, selection: selection, asOf: now, calendar: calendar)
        return SharedWeeklyReport(
            weekStart: weekStart,
            observedPlanDays: preview.observedPlanDays,
            explicitlySkippedPlanDays: preview.explicitlySkippedPlanDays,
            completionRate: preview.completionRate,
            selection: preview.selection,
            consentedAt: now
        )
    }

    public static func revoke(_ report: SharedWeeklyReport, at date: Date = .now) -> SharedWeeklyReport {
        var revoked = report
        revoked.revokedAt = date
        return revoked
    }

    /// This has no sending side effect. A future system-share screen must call it only after a
    /// fresh, explicit confirmation; a revoked local report cannot be turned into a payload.
    public static func externalPayload(
        for report: SharedWeeklyReport,
        confirmedForThisShare: Bool,
        now: Date = .now
    ) -> VoluntaryWeeklyReportPayload? {
        // A current local report may be withdrawn, but a malformed import, a future-dated
        // consent, or a future week must not become outward-facing merely because a caller
        // supplies `confirmedForThisShare`. The actual sender must still obtain its own fresh
        // confirmation; this method only produces the whitelisted, minimal value.
        guard confirmedForThisShare,
              report.revokedAt == nil,
              report.hasValidVoluntarySummary,
              report.consentedAt <= now,
              report.weekStart <= now else { return nil }
        return VoluntaryWeeklyReportPayload(report: report)
    }
}

public enum PrivateExport {
    /// 导出仅限资料所有者发起。导出副本保留计划与打卡数据，但不会包含 App 私有照片文件引用；
    /// HealthKit 原始样本本就不进入 `PrivateCoachData`，因此也不会出现在导出中。
    public static func portableCopy(of data: PrivateCoachData) -> PrivateCoachData {
        var copy = data
        // A sync receipt only prevents local duplicate writes; it is not needed to recover the
        // owner's health plan and should not be carried into an exported file.
        copy.healthWorkoutSyncs = []
        copy.pendingHealthWorkoutSyncs = []
        copy.pendingWorkoutConfirmations = []
        copy.unplannedMealLogs = data.unplannedMealLogs.map { log in
            UnplannedMealLog(
                id: log.id,
                date: log.date,
                localPhotoReference: nil,
                userDescription: log.userDescription,
                estimatedCaloriesRange: log.estimatedCaloriesRange,
                estimatedProteinGramsRange: log.estimatedProteinGramsRange,
                confidence: log.confidence,
                estimateSource: log.estimateSource,
                isEstimate: log.isEstimate
            )
        }
        copy.actualMealLogs = data.actualMealLogs.map { log in
            ActualMealLog(
                id: log.id,
                date: log.date,
                slot: log.slot,
                relationship: log.relationship,
                description: log.description,
                portionNote: log.portionNote,
                localPhotoReference: nil,
                estimatedCaloriesRange: log.estimatedCaloriesRange,
                recordedAt: log.recordedAt
            )
        }
        copy.mealSubstitutions = data.mealSubstitutions.map { substitution in
            ConfirmedMealSubstitution(
                id: substitution.id,
                date: substitution.date,
                slot: substitution.slot,
                originalMealTitle: substitution.originalMealTitle,
                replacement: substitution.replacement,
                availableFoodSummary: substitution.availableFoodSummary,
                localIngredientPhotoReference: nil,
                confirmedAt: substitution.confirmedAt,
                isReverted: substitution.isReverted
            )
        }
        // Existing-at-home inventory is useful for local prep but remains private; exported
        // snapshots omit any owner-scoped photo references just like meal substitutions.
        copy.availableIngredients = data.availableIngredients.map { ingredient in
            AvailableIngredient(
                id: ingredient.id,
                name: ingredient.name,
                quantity: ingredient.quantity,
                unit: ingredient.unit,
                source: ingredient.source,
                confirmedAt: ingredient.confirmedAt,
                localPhotoReference: nil
            )
        }
        return copy
    }

    public static func makeOwnerExport(_ data: PrivateCoachData) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        // The portable representation deliberately has empty local-only sync arrays.  Omitting
        // their keys as well (rather than serialising `[]`) makes the boundary inspectable in
        // the exported JSON: an export cannot disclose a HealthKit workout UUID, a private
        // session identifier, or even an uncertain write-attempt marker.  This does not affect
        // the on-device Codable store, which keeps those receipts when they are needed to avoid
        // duplicate writes.
        let encodedCopy = try encoder.encode(portableCopy(of: data))
        guard var object = try JSONSerialization.jsonObject(with: encodedCopy) as? [String: Any] else {
            return encodedCopy
        }
        object.removeValue(forKey: "healthWorkoutSyncs")
        object.removeValue(forKey: "pendingHealthWorkoutSyncs")
        object.removeValue(forKey: "pendingWorkoutConfirmations")
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    public static func deleteAll(at url: URL, fileManager: FileManager = .default) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }
}
