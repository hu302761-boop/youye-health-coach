import Foundation

/// Interprets only the meals the owner has actually recorded against a confirmed daily
/// reference. It never claims an exact total, diagnoses overeating, or changes the next meal.
public enum DailyRecordedCalorieSignal: Sendable, Equatable {
    case notAboveReference
    case mayExceedReference
    case exceedsReference

    public var title: String {
        switch self {
        case .notAboveReference: "截至已记录餐食，区间未超过参考上限"
        case .mayExceedReference: "截至已记录餐食，估算区间可能超过参考上限"
        case .exceedsReference: "截至已记录餐食，估算区间整体高于参考上限"
        }
    }

    public var nextMealGuidance: String {
        switch self {
        case .notAboveReference:
            "下一餐按原餐卡和正常饥饿感执行；不需要为了“留热量”提前少吃。"
        case .mayExceedReference:
            "家常餐和照片只是宽区间，无法确定已超过。下一餐照常按原餐卡克数吃，不跳餐、不补练。"
        case .exceedsReference:
            "这只表示已记录的保守区间高于参考，不是精准诊断。下一餐照常吃原餐卡，不挨饿、不补练，明天正常继续。"
        }
    }

    public var needsAttention: Bool {
        self != .notAboveReference
    }
}

/// Ingredient-derived reference used when the owner marks a catalogue meal as eaten. It remains
/// a visible range; substitutions or changed portions should be recorded through the meal form.
public enum PlannedMealEnergyReference {
    private struct Density {
        let tokens: [String]
        let kcalPerGram: Double
    }

    private static let densities: [Density] = [
        Density(tokens: ["油"], kcalPerGram: 9.0),
        Density(tokens: ["芝麻酱"], kcalPerGram: 6.2),
        Density(tokens: ["腰果"], kcalPerGram: 5.5),
        Density(tokens: ["燕麦"], kcalPerGram: 3.8),
        Density(tokens: ["小米"], kcalPerGram: 3.6),
        Density(tokens: ["全麦意面", "全麦面", "荞麦面", "粉丝"], kcalPerGram: 3.5),
        Density(tokens: ["全麦吐司"], kcalPerGram: 2.5),
        Density(tokens: ["熟鹰嘴豆"], kcalPerGram: 1.64),
        Density(tokens: ["鸡腿"], kcalPerGram: 1.8),
        Density(tokens: ["鸡胸"], kcalPerGram: 1.65),
        Density(tokens: ["牛肉", "肥牛"], kcalPerGram: 2.0),
        Density(tokens: ["里脊", "瘦肉", "肉末"], kcalPerGram: 1.8),
        Density(tokens: ["鸡蛋"], kcalPerGram: 1.43),
        Density(tokens: ["清水金枪鱼"], kcalPerGram: 1.16),
        Density(tokens: ["鱼片", "鱼柳", "巴沙鱼"], kcalPerGram: 1.1),
        Density(tokens: ["虾仁", "虾皮"], kcalPerGram: 1.0),
        Density(tokens: ["熟米饭"], kcalPerGram: 1.16),
        Density(tokens: ["红薯", "紫薯"], kcalPerGram: 0.86),
        Density(tokens: ["玉米"], kcalPerGram: 0.96),
        Density(tokens: ["土豆"], kcalPerGram: 0.77),
        Density(tokens: ["北豆腐", "嫩豆腐", "豆腐"], kcalPerGram: 0.8),
        Density(tokens: ["无糖豆浆"], kcalPerGram: 0.33),
        Density(tokens: ["香蕉"], kcalPerGram: 0.89),
        Density(tokens: ["苹果", "橙子"], kcalPerGram: 0.5),
        Density(tokens: ["南瓜"], kcalPerGram: 0.26),
        Density(tokens: ["西兰花", "花菜", "卷心菜", "青菜", "番茄", "黄瓜", "菌菇", "香菇", "口蘑", "杏鲍菇", "娃娃菜", "白菜", "冬瓜", "西葫芦", "茄子", "波菜", "芦笋", "四季豆", "豌豆", "胡萝卜", "彩椒", "青椒", "洋葱", "生菜", "芹菜", "西芹", "芥蓝"], kcalPerGram: 0.3)
    ]

    public static func estimatedRange(for meal: MealCard) -> ClosedRange<Int> {
        let divisor = meal.title.hasPrefix("午餐｜昨晚便当")
            || meal.portionsAndStorage.contains("做两份")
            || meal.portionsAndStorage.contains("做 2 份") ? 2.0 : 1.0
        let total = meal.ingredients.reduce(0.0) { partial, ingredient in
            guard let grams = firstMetricAmount(in: ingredient),
                  let density = densities.first(where: { item in item.tokens.contains { ingredient.contains($0) } }) else {
                return partial
            }
            return partial + grams * density.kcalPerGram
        } / divisor

        let fallback = meal.title.hasPrefix("早餐") ? 350...550 : 450...750
        guard total >= 180, total <= 1_500 else { return fallback }
        return max(0, Int((total * 0.88).rounded(.down)))...Int((total * 1.12).rounded(.up))
    }

    public static func fallbackRange(for slot: MealSlot) -> ClosedRange<Int> {
        slot == .breakfast ? 300...600 : 450...900
    }

    private static func firstMetricAmount(in text: String) -> Double? {
        let pattern = #"(\d+(?:\.\d+)?)\s*(?:g|克|ml|毫升)"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return Double(text[range])
    }
}

/// A visible source row for a daily total. It deliberately keeps the recorded meal wording and
/// its range together, so a total can always be traced back to the owner's local diary rather
/// than looking like an unexplained calorie verdict.
public struct DailyCalorieRecordedEntry: Sendable, Equatable, Identifiable {
    public let id: String
    public let label: String
    public let estimatedRange: ClosedRange<Int>?
    public let estimateSourceLabel: String?

    public init(id: String, label: String, estimatedRange: ClosedRange<Int>?, estimateSourceLabel: String?) {
        self.id = id
        self.label = label
        self.estimatedRange = estimatedRange
        self.estimateSourceLabel = estimateSourceLabel
    }
}

public struct DailyCalorieIntakeSummary: Sendable, Equatable {
    public let recordedRange: ClosedRange<Int>?
    public let remainingRange: ClosedRange<Int>?
    public let entriesMissingCalories: Int
    /// All local meal records that explain the card, including notes that do not have a usable
    /// calorie range. A missing estimate must stay visible rather than silently disappearing.
    public let recordedEntries: [DailyCalorieRecordedEntry]
    public let framework: DailyCalorieFramework?
    public let recordedSignal: DailyRecordedCalorieSignal?
    public let threshold: DailyCalorieThreshold?
    public let progressRange: ClosedRange<Double>?

    public var targetEstimate: Int? {
        framework.map { Self.roundedDiaryValue(($0.lowerBound + $0.upperBound) / 2) }
    }

    public var recordedEstimate: Int? {
        recordedRange.map { Self.roundedDiaryValue(($0.lowerBound + $0.upperBound) / 2) }
    }

    public var remainingEstimate: Int? {
        guard entriesMissingCalories == 0,
              let targetEstimate else { return nil }
        // Before the first recorded meal, the whole confirmed daily framework is still available.
        // Showing “尚未记录” here hid the most useful number exactly when the day was starting.
        guard let recordedEstimate else { return targetEstimate }
        return max(0, targetEstimate - recordedEstimate)
    }

    public static func make(for date: Date, data: PrivateCoachData, calendar: Calendar = .current) -> Self {
        let actual = data.actualMealLogs.filter { calendar.isDate($0.date, inSameDayAs: date) }
        let external = data.unplannedMealLogs.filter { calendar.isDate($0.date, inSameDayAs: date) }
        let entries = actual.map {
            DailyCalorieRecordedEntry(
                id: "actual-\($0.id.uuidString)",
                label: "\($0.slot.displayName) · \($0.description)",
                estimatedRange: $0.estimatedCaloriesRange,
                estimateSourceLabel: $0.estimatedCaloriesRange == nil ? nil : $0.historyEstimateLabel
            )
        } + external.map {
            DailyCalorieRecordedEntry(
                id: "extra-\($0.id.uuidString)",
                label: "加餐 · \($0.displayDescription)",
                estimatedRange: UnplannedMealLog.validatedCaloriesRange($0.estimatedCaloriesRange),
                estimateSourceLabel: UnplannedMealLog.validatedCaloriesRange($0.estimatedCaloriesRange) == nil ? nil : $0.historyEstimateLabel
            )
        }
        let ranges = actual.compactMap(\.estimatedCaloriesRange)
            + external.compactMap { UnplannedMealLog.validatedCaloriesRange($0.estimatedCaloriesRange) }
        let missing = actual.filter { $0.estimatedCaloriesRange == nil }.count
            + external.filter { UnplannedMealLog.validatedCaloriesRange($0.estimatedCaloriesRange) == nil }.count
        let recorded = sum(ranges)
        let framework = data.profile.dailyCalorieFramework
        let remaining: ClosedRange<Int>?
        let signal: DailyRecordedCalorieSignal?
        let threshold: DailyCalorieThreshold?
        let progress: ClosedRange<Double>?
        if let recorded, let framework, missing == 0 {
            remaining = max(0, framework.lowerBound - recorded.upperBound)...max(0, framework.upperBound - recorded.lowerBound)
            if recorded.lowerBound > framework.upperBound {
                signal = .exceedsReference
            } else if recorded.upperBound > framework.upperBound {
                signal = .mayExceedReference
            } else {
                signal = .notAboveReference
            }
            let upper = Double(framework.upperBound)
            progress = min(1, Double(recorded.lowerBound) / upper)...min(1, Double(recorded.upperBound) / upper)
            if recorded.lowerBound >= framework.upperBound {
                threshold = .reached
            } else if recorded.upperBound >= framework.upperBound {
                threshold = .mayReach
            } else if recorded.upperBound >= Int((upper * 0.8).rounded(.down)) {
                threshold = .approaching
            } else {
                threshold = .within
            }
        } else if let framework, missing == 0 {
            // An empty diary is not incomplete data. It means no calories have been recorded,
            // so the safe remaining range is exactly the owner-confirmed daily framework.
            remaining = framework.lowerBound...framework.upperBound
            signal = nil
            threshold = .within
            progress = 0...0
        } else {
            remaining = nil
            signal = nil
            threshold = nil
            progress = nil
        }
        return Self(
            recordedRange: recorded,
            remainingRange: remaining,
            entriesMissingCalories: missing,
            recordedEntries: entries,
            framework: framework,
            recordedSignal: signal,
            threshold: threshold,
            progressRange: progress
        )
    }

    private static func sum(_ ranges: [ClosedRange<Int>]) -> ClosedRange<Int>? {
        guard !ranges.isEmpty else { return nil }
        return ranges.reduce(0...0) { total, range in
            let lower = total.lowerBound.addingReportingOverflow(range.lowerBound)
            let upper = total.upperBound.addingReportingOverflow(range.upperBound)
            return (lower.overflow ? Int.max : lower.partialValue)...(upper.overflow ? Int.max : upper.partialValue)
        }
    }

    private static func roundedDiaryValue(_ value: Int) -> Int {
        Int((Double(value) / 5).rounded()) * 5
    }
}

public enum DailyCalorieThreshold: Sendable, Equatable {
    case within, approaching, mayReach, reached

    public var title: String {
        switch self {
        case .within: "仍在今日参考范围内"
        case .approaching: "已接近今日参考上限（≥80%）"
        case .mayReach: "估算区间可能已到今日上限"
        case .reached: "已记录区间已到今日上限"
        }
    }

    public var needsAttention: Bool { self != .within }
}
