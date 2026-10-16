import Foundation

public enum MealSlot: String, Codable, Sendable, CaseIterable {
    case breakfast, lunch, dinner

    public var displayName: String {
        switch self {
        case .breakfast: "早餐"
        case .lunch: "午餐"
        case .dinner: "晚餐"
        }
    }
}

/// 由用户看过食材识别建议后主动确认的替换记录。
/// 食材照片仍只保存为本机引用，绝不写入这条可导出的结构化记录。
public struct ConfirmedMealSubstitution: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let date: Date
    public let slot: MealSlot
    public let originalMealTitle: String
    public let replacement: MealCard
    public let availableFoodSummary: String?
    /// The optional original ingredient photo stays in the App-private photo store. It is never
    /// exported or shared, and it is not evidence of an automatic recognition result.
    public var localIngredientPhotoReference: String?
    public let confirmedAt: Date
    /// Reversal keeps a private audit record, but stops this entry from overriding the daily
    /// meal. Its local-only photo reference is retained until file deletion succeeds so a failed
    /// deletion cannot orphan an otherwise-unreachable sensitive image.
    public var isReverted: Bool

    public init(
        id: UUID = UUID(),
        date: Date,
        slot: MealSlot,
        originalMealTitle: String,
        replacement: MealCard,
        availableFoodSummary: String? = nil,
        localIngredientPhotoReference: String? = nil,
        confirmedAt: Date = .now,
        isReverted: Bool = false
    ) {
        self.id = id
        self.date = date
        self.slot = slot
        self.originalMealTitle = originalMealTitle
        self.replacement = replacement
        self.availableFoodSummary = availableFoodSummary
        self.localIngredientPhotoReference = localIngredientPhotoReference?.localPhotoReferenceOrNil
        self.confirmedAt = confirmedAt
        self.isReverted = isReverted
    }

    private enum CodingKeys: String, CodingKey {
        case id, date, slot, originalMealTitle, replacement, availableFoodSummary, localIngredientPhotoReference, confirmedAt, isReverted
    }

    /// Ingredient photos were added after the first local records. Missing photo references are
    /// safely interpreted as no photo rather than breaking existing private plans.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        date = try values.decode(Date.self, forKey: .date)
        slot = try values.decode(MealSlot.self, forKey: .slot)
        originalMealTitle = try values.decode(String.self, forKey: .originalMealTitle)
        replacement = try values.decode(MealCard.self, forKey: .replacement)
        availableFoodSummary = try values.decodeIfPresent(String.self, forKey: .availableFoodSummary)
        localIngredientPhotoReference = try values.decodeIfPresent(String.self, forKey: .localIngredientPhotoReference)?.localPhotoReferenceOrNil
        confirmedAt = try values.decode(Date.self, forKey: .confirmedAt)
        isReverted = try values.decodeIfPresent(Bool.self, forKey: .isReverted) ?? false
    }
}

public struct MealSubstitutionResult: Sendable, Equatable {
    public let plan: TodayPlan
    public let data: PrivateCoachData
    public let substitution: ConfirmedMealSubstitution?
    public let change: PlanChange?
    public let validationErrors: [String]
}

public struct MealSubstitutionReversalResult: Sendable, Equatable {
    public let plan: TodayPlan
    public let data: PrivateCoachData
    /// The target remains identifiable so UI can clear this reference only after the matching
    /// App-private file has actually been removed. No image bytes are returned or exported.
    public let revertedSubstitutionID: UUID?
    /// A photo is offered for deletion only when no other private meal or substitution still
    /// references it. The UI must delete the file before committing the reversal; a failure
    /// therefore leaves both the active substitution and its visible cleanup path intact.
    public let photoReferenceToDelete: String?
    public let wasReverted: Bool
    public let validationErrors: [String]
}

public enum MealSubstitutionService {
    /// 替换餐也必须是可执行食谱卡，不能只保存一句模糊建议。
    public static func validationErrors(for replacement: MealCard) -> [String] {
        MealRecipeCardAudit.validationErrors(for: replacement)
    }

    /// A photograph is only a private visual aid. The owner must explicitly turn it into a
    /// usable food list with a measurable amount before a replacement can affect today.
    public static func availableFoodValidationErrors(_ summary: String?) -> [String] {
        guard let summary = summary?.trimmingCharacters(in: .whitespacesAndNewlines),
              summary.range(of: #"\d+(?:\.\d+)?\s*(?:g|克|ml|毫升|个|份)"#, options: .regularExpression) != nil else {
            return ["请先根据照片或现有食材，确认并填写至少一种食材及克数/份数后再重排。"]
        }
        return []
    }

    /// 只有用户主动确认后才覆写当天餐卡；不会改热量框架、目标、训练或后续日期。
    public static func confirm(
        replacement: MealCard,
        for plan: TodayPlan,
        slot: MealSlot = .dinner,
        availableFoodSummary: String? = nil,
        localIngredientPhotoReference: String? = nil,
        confirmedByUser: Bool,
        at date: Date = .now,
        in data: PrivateCoachData,
        calendar: Calendar = .current
    ) -> MealSubstitutionResult {
        let errors = validationErrors(for: replacement) + availableFoodValidationErrors(availableFoodSummary)
        guard confirmedByUser, errors.isEmpty else {
            return MealSubstitutionResult(plan: plan, data: data, substitution: nil, change: nil, validationErrors: errors)
        }
        guard TodayFeature.canComplete(plan, at: date, calendar: calendar) else {
            return MealSubstitutionResult(
                plan: plan,
                data: data,
                substitution: nil,
                change: nil,
                validationErrors: ["只能确认替换当天的正式计划餐；历史与未来日保持只读。"]
            )
        }

        // A confirmed meal completion is an execution record. Replacing that card afterward
        // would make the plan imply the person ate a different meal, so require the owner to
        // explicitly undo that meal’s completion before proposing a new card.
        if let completion = TodayFeature.completion(for: plan, in: data, calendar: calendar), isCompleted(slot, in: completion) {
            return MealSubstitutionResult(
                plan: plan,
                data: data,
                substitution: nil,
                change: nil,
                validationErrors: ["这餐已标记完成，不能再重排以免改写执行记录。若确实尚未吃，请先在“今天”取消该餐完成状态，再查看重排预览。"]
            )
        }

        var changedPlan = plan
        let original: String
        switch slot {
        case .breakfast:
            original = plan.breakfast.title
            changedPlan.breakfast = replacement
        case .lunch:
            original = plan.lunch.title
            changedPlan.lunch = replacement
        case .dinner:
            original = plan.dinner.title
            changedPlan.dinner = replacement
        }

        let substitution = ConfirmedMealSubstitution(
            date: plan.date,
            slot: slot,
            originalMealTitle: original,
            replacement: replacement,
            availableFoodSummary: availableFoodSummary?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank,
            localIngredientPhotoReference: localIngredientPhotoReference,
            confirmedAt: date
        )
        let change = PlanChange(
            kind: .mealSubstitution,
            authority: .requiresConfirmation,
            reason: "用户确认按现有食材替换当天\(slot.displayName)。",
            before: original,
            after: replacement.title,
            createdAt: date
        )
        var changedData = data
        changedData.mealSubstitutions.append(substitution)
        changedData.planChanges.append(change)
        return MealSubstitutionResult(plan: changedPlan, data: changedData, substitution: substitution, change: change, validationErrors: [])
    }

    private static func isCompleted(_ slot: MealSlot, in completion: DailyCompletion) -> Bool {
        switch slot {
        case .breakfast: completion.breakfastCompleted
        case .lunch: completion.lunchCompleted
        case .dinner: completion.dinnerCompleted
        }
    }

    /// 对同日同餐位取最近一次已确认替换；历史记录保留，便于导出和回溯。
    public static func activeSubstitution(
        for date: Date,
        slot: MealSlot = .dinner,
        in data: PrivateCoachData,
        calendar: Calendar = .current
    ) -> ConfirmedMealSubstitution? {
        data.mealSubstitutions
            .filter { !$0.isReverted && $0.slot == slot && calendar.isDate($0.date, inSameDayAs: date) }
            .max { $0.confirmedAt < $1.confirmedAt }
    }

    /// Revert only the latest active substitution for today. An older confirmed substitution for
    /// the same meal slot resumes automatically; otherwise the original scheduled meal returns.
    /// Historical and future cards remain read-only, exactly like confirmation.
    public static func revokeLatest(
        for plan: TodayPlan,
        slot: MealSlot,
        at date: Date = .now,
        in data: PrivateCoachData,
        calendar: Calendar = .current
    ) -> MealSubstitutionReversalResult {
        guard TodayFeature.canComplete(plan, at: date, calendar: calendar) else {
            return MealSubstitutionReversalResult(plan: plan, data: data, revertedSubstitutionID: nil, photoReferenceToDelete: nil, wasReverted: false, validationErrors: ["只能撤回当天正式计划餐的重排；历史与未来日保持只读。"])
        }
        guard let index = data.mealSubstitutions.indices
            .filter({ !data.mealSubstitutions[$0].isReverted && data.mealSubstitutions[$0].slot == slot && calendar.isDate(data.mealSubstitutions[$0].date, inSameDayAs: plan.date) })
            .max(by: { data.mealSubstitutions[$0].confirmedAt < data.mealSubstitutions[$1].confirmedAt }) else {
            return MealSubstitutionReversalResult(plan: plan, data: data, revertedSubstitutionID: nil, photoReferenceToDelete: nil, wasReverted: false, validationErrors: ["没有可撤回的当天\(slot.displayName)重排。"])
        }

        var changedData = data
        let reverted = changedData.mealSubstitutions[index]
        let photoReference = reverted.localIngredientPhotoReference
        let photoIsReferencedElsewhere = photoReference.map { reference in
            data.unplannedMealLogs.contains { $0.localPhotoReference == reference }
                || data.actualMealLogs.contains { $0.localPhotoReference == reference }
                || data.mealSubstitutions.indices.contains { otherIndex in
                    otherIndex != index && data.mealSubstitutions[otherIndex].localIngredientPhotoReference == reference
                }
        } ?? false
        changedData.mealSubstitutions[index].isReverted = true
        changedData.planChanges.append(PlanChange(
            kind: .mealSubstitution,
            authority: .requiresConfirmation,
            reason: "用户撤回当天\(slot.displayName)重排。",
            before: reverted.replacement.title,
            after: reverted.originalMealTitle,
            createdAt: date
        ))

        let originalPlan = PlanSchedule.makePlan(for: plan.date, calendar: calendar) ?? plan
        let restored = appliedPlan(for: originalPlan, in: changedData, calendar: calendar)
        return MealSubstitutionReversalResult(
            plan: restored,
            data: changedData,
            revertedSubstitutionID: reverted.id,
            photoReferenceToDelete: photoIsReferencedElsewhere ? nil : photoReference,
            wasReverted: true,
            validationErrors: []
        )
    }

    public static func appliedPlan(for plan: TodayPlan, in data: PrivateCoachData, calendar: Calendar = .current) -> TodayPlan {
        var applied = plan
        // Replacements belong to meal slots, not to an undifferentiated “daily replacement”.
        // A person can legitimately confirm breakfast and dinner separately.  Re-applying only
        // the newest substitution overall would silently lose the other meal after navigating
        // away, reloading local data, or publishing the paired daily card.
        for slot in MealSlot.allCases {
            guard let substitution = activeSubstitution(for: plan.date, slot: slot, in: data, calendar: calendar) else {
                continue
            }
            switch slot {
            case .breakfast:
                applied.breakfast = substitution.replacement
            case .lunch:
                applied.lunch = substitution.replacement
            case .dinner:
                applied.dinner = substitution.replacement
            }
        }
        return applied
    }
}

private extension String {
    var nilIfBlank: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }

    var localPhotoReferenceOrNil: String? {
        PrivateMealPhotoStore.isValidLocalPhotoReference(self) ? self : nil
    }
}
