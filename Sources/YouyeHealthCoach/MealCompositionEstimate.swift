import Foundation

/// Household-size confirmations used after a meal photo. The values are intentionally ranges:
/// a camera cannot see exact weight, absorbed oil, sugar, or food hidden under another item.
public enum MealStapleAmount: String, Codable, Sendable, CaseIterable, Identifiable {
    case none, small, regular, large, uncertain
    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .none: "没有"
        case .small: "少一点"
        case .regular: "大致一份"
        case .large: "多一点"
        case .uncertain: "看不准"
        }
    }
    fileprivate var calories: ClosedRange<Int> {
        switch self {
        case .none: 0...0
        case .small: 110...150
        case .regular: 190...260
        case .large: 320...450
        case .uncertain: 70...480
        }
    }
}

public enum MealProteinAmount: String, Codable, Sendable, CaseIterable, Identifiable {
    case none, small, regular, large, eggOne, eggTwo, eggThree, uncertain
    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .none: "没有"
        case .small: "少一点"
        case .regular: "大致一份"
        case .large: "多一点"
        case .eggOne: "鸡蛋 1 个"
        case .eggTwo: "鸡蛋 2 个"
        case .eggThree: "鸡蛋 3 个"
        case .uncertain: "看不准"
        }
    }
    fileprivate var calories: ClosedRange<Int> {
        switch self {
        case .none: 0...0
        case .small: 90...135
        case .regular: 160...240
        case .large: 270...400
        // Egg count is an owner-confirmed count, not a weighed or oil-adjusted value. Oil stays
        // in the separate confirmation, so fried eggs never inherit a falsely narrow estimate.
        case .eggOne: 55...90
        case .eggTwo: 110...180
        case .eggThree: 165...270
        case .uncertain: 60...430
        }
    }
}

public enum MealVegetableAmount: String, Codable, Sendable, CaseIterable, Identifiable {
    case none, small, regular, large, uncertain
    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .none: "没有"
        case .small: "少一点"
        case .regular: "大致一份"
        case .large: "多一点"
        case .uncertain: "看不准"
        }
    }
    fileprivate var calories: ClosedRange<Int> {
        switch self {
        case .none: 0...0
        case .small: 25...50
        case .regular: 50...90
        case .large: 90...150
        case .uncertain: 15...170
        }
    }
}

public enum MealAddedFatAmount: String, Codable, Sendable, CaseIterable, Identifiable {
    case light, regular, rich, uncertain
    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .light: "清蒸水煮／约 1 茶匙油"
        case .regular: "普通炒菜／约 2 茶匙油"
        case .rich: "约 1 汤匙以上／油炸油亮"
        case .uncertain: "不知道用了多少油"
        }
    }
    fileprivate var calories: ClosedRange<Int> {
        switch self {
        case .light: 30...55
        case .regular: 70...110
        case .rich: 130...220
        case .uncertain: 25...280
        }
    }
}

public enum MealExtrasAmount: String, Codable, Sendable, CaseIterable, Identifiable {
    case none, light, regular, rich, uncertain
    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .none: "没有"
        case .light: "少量酱／无糖饮料（≤35 kcal）"
        case .regular: "有酱汁／小杯奶饮"
        case .rich: "浓酱／甜饮／甜点"
        case .uncertain: "看不准"
        }
    }
    fileprivate var calories: ClosedRange<Int> {
        switch self {
        case .none: 0...0
        case .light: 10...35
        case .regular: 60...120
        case .rich: 160...320
        case .uncertain: 0...360
        }
    }
}

public enum MealConsumedFraction: String, Codable, Sendable, CaseIterable, Identifiable {
    case half, threeQuarters, all, uncertain
    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .half: "吃了约一半"
        case .threeQuarters: "吃了约 3/4"
        case .all: "基本吃完"
        case .uncertain: "吃掉多少不确定"
        }
    }
    fileprivate var factor: ClosedRange<Double> {
        switch self {
        case .half: 0.45...0.55
        case .threeQuarters: 0.68...0.82
        case .all: 0.90...1.0
        case .uncertain: 0.55...1.0
        }
    }
}

/// A fast path for everyday photo logging. A preset confirms only the visible plate portions;
/// it must not invent cooking oil or a sweet drink/dessert. Those factors remain unknown until
/// the owner explicitly selects them in the optional detailed controls.
public enum MealQuickPortionPreset: String, Sendable, CaseIterable, Identifiable {
    case light, regular, generous

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .light: "少一点"
        case .regular: "大致一份"
        case .generous: "多一点"
        }
    }

    public var subtitle: String {
        switch self {
        case .light: "比平时少"
        case .regular: "和平时差不多"
        case .generous: "比平时多"
        }
    }

    public var composition: MealCompositionConfirmation {
        switch self {
        case .light:
            MealCompositionConfirmation(
                staple: .small, protein: .small, vegetables: .regular,
                addedFat: .uncertain, extras: .uncertain, consumed: .uncertain
            )
        case .regular:
            MealCompositionConfirmation(
                staple: .regular, protein: .regular, vegetables: .regular,
                addedFat: .uncertain, extras: .uncertain, consumed: .uncertain
            )
        case .generous:
            MealCompositionConfirmation(
                staple: .large, protein: .large, vegetables: .regular,
                addedFat: .uncertain, extras: .uncertain, consumed: .uncertain
            )
        }
    }

    public static func matching(_ composition: MealCompositionConfirmation) -> Self? {
        allCases.first { $0.composition == composition }
    }
}

public struct MealCompositionConfirmation: Codable, Sendable, Equatable {
    public var staple: MealStapleAmount
    public var protein: MealProteinAmount
    public var vegetables: MealVegetableAmount
    public var addedFat: MealAddedFatAmount
    public var extras: MealExtrasAmount
    public var consumed: MealConsumedFraction

    public init(
        staple: MealStapleAmount = .uncertain,
        protein: MealProteinAmount = .uncertain,
        vegetables: MealVegetableAmount = .uncertain,
        addedFat: MealAddedFatAmount = .uncertain,
        extras: MealExtrasAmount = .uncertain,
        consumed: MealConsumedFraction = .uncertain
    ) {
        self.staple = staple
        self.protein = protein
        self.vegetables = vegetables
        self.addedFat = addedFat
        self.extras = extras
        self.consumed = consumed
    }

    public var estimatedCaloriesRange: ClosedRange<Int> {
        let components = [staple.calories, protein.calories, vegetables.calories, addedFat.calories, extras.calories]
        if isNarrowedByOwner {
            // Once every visible source of energy has been confirmed, using every component's
            // simultaneous minimum and maximum greatly overstates uncertainty. Combine their
            // typical household values. Six explicit confirmations support a tighter 8–12%
            // meal-level error; oily/sweet meals and partly eaten plates remain wider because
            // hidden oil and the consumed fraction are harder to judge. This remains an
            // owner-confirmed estimate range, not a weighed recipe or nutrition label, and is
            // never used for untouched photos.
            let servedTypical = components.reduce(0.0) {
                $0 + Double($1.lowerBound + $1.upperBound) / 2
            }
            let consumedTypical = (consumed.factor.lowerBound + consumed.factor.upperBound) / 2
            let center = servedTypical * consumedTypical
            let uncertaintyRate: Double = addedFat == .rich || extras == .rich
                ? 0.12
                : (consumed == .all ? 0.08 : 0.10)
            let margin = max(30, center * uncertaintyRate)
            let lower = max(0, Int((center - margin).rounded(.down)))
            let upper = min(
                UnplannedMealLog.maximumEstimatedCalories,
                max(lower, Int((center + margin).rounded(.up)))
            )
            return lower...upper
        }
        let servedLower = components.reduce(0) { $0 + $1.lowerBound }
        let servedUpper = components.reduce(0) { $0 + $1.upperBound }
        let lower = max(0, Int((Double(servedLower) * consumed.factor.lowerBound).rounded(.down)))
        let upper = min(
            UnplannedMealLog.maximumEstimatedCalories,
            max(lower, Int((Double(servedUpper) * consumed.factor.upperBound).rounded(.up)))
        )
        return lower...upper
    }

    public var isNarrowedByOwner: Bool {
        staple != .uncertain && protein != .uncertain && vegetables != .uncertain
            && addedFat != .uncertain && extras != .uncertain && consumed != .uncertain
    }

    /// One stable number for the diary and the large daily total. It is the rounded midpoint of
    /// the visible interval, not a claim that a phone photo measured exact calories.
    public var recommendedCalories: Int {
        let range = estimatedCaloriesRange
        let midpoint = Double(range.lowerBound + range.upperBound) / 2
        return Int((midpoint / 5).rounded()) * 5
    }

    public var hasAnyOwnerSelection: Bool {
        staple != .uncertain || protein != .uncertain || vegetables != .uncertain
            || addedFat != .uncertain || extras != .uncertain || consumed != .uncertain
    }

    public var confirmationCount: Int {
        [
            staple != .uncertain,
            protein != .uncertain,
            vegetables != .uncertain,
            addedFat != .uncertain,
            extras != .uncertain,
            consumed != .uncertain
        ].filter { $0 }.count
    }

    public var summary: String {
        "主食：\(staple.displayName)；肉蛋豆：\(protein.displayName)；蔬菜：\(vegetables.displayName)；油：\(addedFat.displayName)；酱汁/饮料/甜点：\(extras.displayName)；\(consumed.displayName)"
    }
}
