import Foundation

public enum CalorieFormulaSex: String, Codable, Sendable, CaseIterable, Identifiable {
    case female, male
    public var id: String { rawValue }
    public var displayName: String { self == .female ? "女性公式" : "男性公式" }
    fileprivate var mifflinOffset: Double { self == .female ? -161 : 5 }
}

public enum DailyActivityLevel: String, Codable, Sendable, CaseIterable, Identifiable {
    case mostlySeated, lightlyActive, moderatelyActive, highlyActive
    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .mostlySeated: "久坐，日常步行较少"
        case .lightlyActive: "轻活动／每周训练 1–3 次"
        case .moderatelyActive: "中等活动／每周训练 3–5 次"
        case .highlyActive: "高活动／体力工作或高频训练"
        }
    }
    fileprivate var factor: Double {
        switch self {
        case .mostlySeated: 1.20
        case .lightlyActive: 1.35
        case .moderatelyActive: 1.50
        case .highlyActive: 1.65
        }
    }
}

public struct CaloriePlanRecommendation: Sendable, Equatable {
    public let framework: DailyCalorieFramework
    public let estimatedRestingEnergy: Int
    public let estimatedMaintenanceEnergy: Int
    public let deficitPercentRange: ClosedRange<Int>

    public var explanation: String {
        "按 Mifflin–St Jeor 公式估算静息消耗约 \(estimatedRestingEnergy) kcal，结合活动水平估算维持约 \(estimatedMaintenanceEnergy) kcal；建议先采用约 \(deficitPercentRange.lowerBound)%–\(deficitPercentRange.upperBound)% 的温和缺口。"
    }
}

public enum CaloriePlanAdvisor {
    public static func recommendation(
        weightKg: Double?,
        heightCm: Double?,
        ageYears: Int?,
        formulaSex: CalorieFormulaSex?,
        activityLevel: DailyActivityLevel?
    ) -> CaloriePlanRecommendation? {
        guard let weightKg, weightKg.isFinite, (20...400).contains(weightKg),
              let heightCm, heightCm.isFinite, (100...250).contains(heightCm),
              let ageYears, (18...90).contains(ageYears),
              let formulaSex, let activityLevel else { return nil }

        let resting = 10 * weightKg + 6.25 * heightCm - 5 * Double(ageYears) + formulaSex.mifflinOffset
        guard resting >= 800, resting <= 4_500 else { return nil }
        let maintenance = resting * activityLevel.factor
        let safetyFloor = max(1_200.0, resting * 0.95)
        let lower = roundedTo50(max(safetyFloor, maintenance * 0.82))
        let upper = roundedTo50(max(Double(lower), maintenance * 0.88))
        guard let framework = DailyCalorieFramework(lowerBound: lower, upperBound: upper) else { return nil }
        return CaloriePlanRecommendation(
            framework: framework,
            estimatedRestingEnergy: Int(resting.rounded()),
            estimatedMaintenanceEnergy: Int(maintenance.rounded()),
            deficitPercentRange: 12...18
        )
    }

    /// A confirmed range is allowed only inside a broad adult safety envelope. This is not a
    /// prescription: it blocks accidental crash-diet numbers and obvious extra zeros.
    public static func confirmationError(for framework: DailyCalorieFramework) -> String? {
        if framework.lowerBound < 1_200 {
            return "不能保存低于 1200 kcal/日的额度；这可能形成过低摄入，需要医生或注册营养师单独评估。"
        }
        if framework.upperBound > 5_000 {
            return "额度高于 5000 kcal/日，可能是输入错误，请重新核对。"
        }
        if framework.upperBound - framework.lowerBound > 800 {
            return "范围过宽，无法用于清晰的每日提醒；请缩小到 800 kcal 以内。"
        }
        return nil
    }

    private static func roundedTo50(_ value: Double) -> Int {
        Int((value / 50).rounded()) * 50
    }
}

