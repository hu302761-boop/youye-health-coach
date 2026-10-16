import Foundation

/// A deliberately broad, non-diagnostic suggestion derived from Apple's on-device image
/// classification. It is never an exact calorie count and cannot be saved without the owner
/// also confirming the visible food and approximate portion in words.
public struct PrivateFoodPhotoSuggestion: Sendable, Equatable {
    public let categoryLabels: [String]
    public let estimatedCaloriesRange: ClosedRange<Int>
    /// A classifier can recognise an energy-dense or potentially sweet-drink category without
    /// seeing the actual portion, absorbed oil, sugar, filling, or sauce. In that case the UI
    /// must retain the candidate's wide range instead of converting a generic “normal plate”
    /// default into a precise-looking log.
    public let requiresConservativeCalorieRange: Bool
    /// Several broad food groups in one photo may be separate servings. This is retained
    /// separately from a high-energy/drink category so the UI can explain the actual reason
    /// for keeping the range wide without inventing a sweet drink.
    public let hasMultipleUnconfirmedComponents: Bool

    public init(
        categoryLabels: [String],
        estimatedCaloriesRange: ClosedRange<Int>,
        requiresConservativeCalorieRange: Bool = false,
        hasMultipleUnconfirmedComponents: Bool = false
    ) {
        self.categoryLabels = categoryLabels
        self.estimatedCaloriesRange = estimatedCaloriesRange
        self.requiresConservativeCalorieRange = requiresConservativeCalorieRange
        self.hasMultipleUnconfirmedComponents = hasMultipleUnconfirmedComponents
    }

    public var categorySummary: String {
        categoryLabels.joined(separator: "、")
    }

    /// Vision returns a broad visual group, not a dish name. Persisting this explicit prefix on
    /// the one-tap route prevents a classifier category from later reading as if the owner had
    /// typed or weighed the exact food. The owner can still replace it with a real dish name.
    public var provisionalDescription: String {
        "照片候选：\(categorySummary)"
    }

    public var conservativeRangeSummary: String {
        hasMultipleUnconfirmedComponents ? "多样食物/甜饮等不确定项" : "甜饮/高能量不确定项"
    }
}

/// Converts potentially noisy Vision labels into a small number of conservative food groups.
/// The widest plausible group wins when several foods are visible, reducing the chance that a
/// mixed meal is presented as a deceptively small estimate. A visible second food group or drink
/// is treated as an unconfirmed extra rather than silently folded into a single-plate estimate.
public enum PrivateFoodPhotoSuggestionPolicy {
    private struct Group {
        let displayName: String
        let tokens: [String]
        let calories: ClosedRange<Int>
        let priority: Int
        let requiresConservativeCalorieRange: Bool
    }

    private static let groups = [
        Group(
            displayName: "油炸/披萨/汉堡/甜点类",
            tokens: ["fried", "fritter", "french fry", "pizza", "burger", "hamburger", "cake", "pastry", "doughnut", "donut", "ice cream", "dessert"],
            calories: 600...1_200,
            priority: 5,
            requiresConservativeCalorieRange: true
        ),
        Group(
            displayName: "米饭/面食/三明治等主食餐",
            tokens: ["rice", "noodle", "pasta", "spaghetti", "sandwich", "burrito", "dumpling", "bread", "waffle", "pancake"],
            calories: 450...1_000,
            priority: 4,
            requiresConservativeCalorieRange: false
        ),
        Group(
            displayName: "肉/鱼/蛋白质主菜",
            tokens: ["chicken", "beef", "pork", "meat", "steak", "fish", "seafood", "shrimp", "egg", "tofu"],
            calories: 350...900,
            priority: 3,
            requiresConservativeCalorieRange: false
        ),
        Group(
            displayName: "蔬菜/水果/汤类",
            tokens: ["salad", "vegetable", "broccoli", "fruit", "apple", "orange", "banana", "soup"],
            calories: 150...650,
            priority: 2,
            requiresConservativeCalorieRange: false
        ),
        Group(
            displayName: "饮品",
            tokens: ["drink", "beverage", "coffee", "tea", "juice", "smoothie", "milkshake"],
            calories: 50...500,
            priority: 1,
            // A photo cannot distinguish water, unsweetened tea, and a sweetened drink with
            // toppings. Keep the full category range until the owner supplies menu/label data.
            requiresConservativeCalorieRange: true
        )
    ]

    /// Most Vision labels can be matched as broad substrings, but `tea` is short enough to
    /// occur inside unrelated food words such as `steak`. Require it to be a label word so a
    /// meat candidate does not gain a fictitious sweet-drink allowance.
    private static func identifier(_ identifier: String, matches token: String) -> Bool {
        guard identifier.contains(token) else { return false }
        guard token == "tea" else { return true }
        return identifier.split(whereSeparator: { !$0.isLetter }).contains { $0 == token }
    }

    /// A Vision object label such as `coffee table` describes furniture, not a drink. Ignore
    /// those labels before grouping so a desk photo cannot create a 50–500 kcal drink draft.
    private static func isFurnitureLabel(_ identifier: String) -> Bool {
        let words = identifier.split(whereSeparator: { !$0.isLetter })
        return words.contains("table") && (words.contains("coffee") || words.contains("tea"))
    }

    public static func suggestion(for classificationIdentifiers: [String]) -> PrivateFoodPhotoSuggestion? {
        let normalized = classificationIdentifiers
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
            .filter { !isFurnitureLabel($0) }
        guard !normalized.isEmpty else { return nil }

        let matched = groups.filter { group in
            normalized.contains { classificationIdentifier in
                group.tokens.contains { token in
                    Self.identifier(classificationIdentifier, matches: token)
                }
            }
        }
        // Tableware, a plate, or an otherwise non-food result is not a meal candidate.  Do not
        // turn that absence of evidence into a generic category with a one-tap save route; the
        // form will instead ask the owner to write what was actually eaten and keep its broad
        // text-based range.
        guard !matched.isEmpty else { return nil }

        let sortedLabels = matched
            .sorted { lhs, rhs in lhs.priority > rhs.priority }
            .map(\.displayName)
        let hasDrinkCandidate = matched.contains { $0.displayName == "饮品" }
        // Keep the concise three-label presentation, but never truncate a visible drink from
        // the actual confirmation text when it contributed to the conservative range. The
        // owner needs to see that candidate before using the one-tap save path.
        let labels: [String]
        if sortedLabels.count > 3, hasDrinkCandidate {
            labels = Array(sortedLabels.filter { $0 != "饮品" }.prefix(2)) + ["饮品"]
        } else {
            labels = Array(sortedLabels.prefix(3))
        }
        let mostConservative = matched.max { lhs, rhs in
            if lhs.calories.upperBound == rhs.calories.upperBound {
                return lhs.calories.lowerBound < rhs.calories.lowerBound
            }
            return lhs.calories.upperBound < rhs.calories.upperBound
        }!
        // A photo can contain multiple meal components, but Vision's broad categories cannot
        // establish whether they are one mixed dish, separate servings, or how much oil/sauce
        // belongs to each. Retaining only the single widest group would quietly omit a plausible
        // second food component. Widen only the upper bound; this is a conservative category
        // range, not an itemized calorie calculation.
        let foodGroupCount = matched.filter { $0.displayName != "饮品" }.count
        let unconfirmedFoodComponentAllowance = max(0, foodGroupCount - 1) * 350
        let hasDrinkAlongsideFood = hasDrinkCandidate && matched.count > 1
        let unconfirmedDrinkAllowance = hasDrinkAlongsideFood ? 500 : 0
        let hasMultipleUnconfirmedComponents = foodGroupCount > 1 || hasDrinkAlongsideFood
        let estimatedCalories: ClosedRange<Int>
        if hasMultipleUnconfirmedComponents {
            estimatedCalories = mostConservative.calories.lowerBound...min(
                UnplannedMealLog.maximumEstimatedCalories,
                mostConservative.calories.upperBound
                    + unconfirmedFoodComponentAllowance
                    + unconfirmedDrinkAllowance
            )
        } else {
            estimatedCalories = mostConservative.calories
        }
        return PrivateFoodPhotoSuggestion(
            categoryLabels: labels,
            estimatedCaloriesRange: estimatedCalories,
            requiresConservativeCalorieRange: matched.contains { $0.requiresConservativeCalorieRange }
                || hasMultipleUnconfirmedComponents,
            hasMultipleUnconfirmedComponents: hasMultipleUnconfirmedComponents
        )
    }
}

#if canImport(Vision) && canImport(ImageIO)
import ImageIO
import Vision

/// Runs only Apple's system Vision classifier against an in-memory, already-normalized photo.
/// There is no network request, analytics event, server model, or retained classification result.
public enum PrivateFoodPhotoAnalyzer {
    public static func analyze(jpegData: Data) async -> PrivateFoodPhotoSuggestion? {
        await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithData(jpegData as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
            let request = VNClassifyImageRequest()
            do {
                try VNImageRequestHandler(cgImage: image).perform([request])
            } catch {
                return nil
            }
            let identifiers = (request.results ?? [])
                .filter { $0.confidence >= 0.08 }
                .prefix(12)
                .map(\.identifier)
            return PrivateFoodPhotoSuggestionPolicy.suggestion(for: identifiers)
        }.value
    }
}
#else
public enum PrivateFoodPhotoAnalyzer {
    public static func analyze(jpegData _: Data) async -> PrivateFoodPhotoSuggestion? { nil }
}
#endif
