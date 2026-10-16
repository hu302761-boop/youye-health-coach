import Foundation

public enum MealEstimateConfidence: String, Codable, Sendable { case low, medium, high }

public enum MealEstimateSource: String, Codable, Sendable, Equatable {
    case textAndOptionalPhotoReference
    case ownerProvidedRange
    case onDevicePhotoCandidate
    case ownerConfirmedComposition
}

/// The owner selects an ordinary-language amount instead of calculating calories. The factors
/// deliberately keep wide bounds because a photo cannot reveal cooking oil, hidden layers or
/// exact weight. They adjust only an estimate; they never change the daily calorie framework.
public enum MealPortionChoice: String, Sendable, Equatable, CaseIterable, Identifiable {
    case small
    case regular
    case large
    case uncertain

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .small: "少一点"
        case .regular: "大致一份"
        case .large: "多一点"
        case .uncertain: "不确定"
        }
    }

    /// Portion labels were originally written into the private note itself.  Keep recognizing
    /// them on read so changing the lighter UI language never turns an existing record into a
    /// dish name containing an implementation marker.  New code should persist `rawValue` when
    /// it needs a stable identifier; these labels are solely a migration boundary for records
    /// already on the device.
    public var persistedDisplayNames: [String] {
        switch self {
        case .small: [displayName, "少量／约半份"]
        case .regular: [displayName, "常规一份"]
        case .large: [displayName, "较多／约 1.5 份"]
        case .uncertain: [displayName]
        }
    }

    public static func fromPersistedDisplayName(_ value: String) -> Self? {
        allCases.first { $0.persistedDisplayNames.contains(value) }
    }

    public func adjusting(_ range: ClosedRange<Int>) -> ClosedRange<Int> {
        let factors: (lower: Double, upper: Double)
        switch self {
        case .small: factors = (0.45, 0.80)
        case .regular, .uncertain: factors = (1, 1)
        case .large: factors = (1.10, 1.50)
        }
        let lower = min(
            UnplannedMealLog.maximumEstimatedCalories,
            max(0, Int((Double(range.lowerBound) * factors.lower).rounded(.down)))
        )
        let upper = min(
            UnplannedMealLog.maximumEstimatedCalories,
            max(lower, Int((Double(range.upperBound) * factors.upper).rounded(.up)))
        )
        return lower...upper
    }

    /// Reconstructs the broad pre-portion range for editing records created by this App. It is
    /// not shown as recovered nutrition truth; it simply prevents applying the same saved
    /// portion factor twice when the owner opens a record and changes the amount.
    public func restoringApproximateBase(from adjusted: ClosedRange<Int>) -> ClosedRange<Int> {
        let factors: (lower: Double, upper: Double)
        switch self {
        case .small: factors = (0.45, 0.80)
        case .regular, .uncertain: factors = (1, 1)
        case .large: factors = (1.10, 1.50)
        }
        let lower = min(
            UnplannedMealLog.maximumEstimatedCalories,
            max(0, Int((Double(adjusted.lowerBound) / factors.lower).rounded()))
        )
        let upper = min(
            UnplannedMealLog.maximumEstimatedCalories,
            max(lower, Int((Double(adjusted.upperBound) / factors.upper).rounded()))
        )
        return lower...upper
    }
}

public enum UnplannedMealSpaceSignal: Sendable, Equatable {
    case unavailable
    /// The owner confirmed a daily reference, but the fixed self-cooking cards intentionally
    /// do not invent nutrition values.  A plan-external meal below that reference therefore
    /// cannot prove that the full day remains within it.
    case cannotDetermineDailyTotal
    case mayExceedDailyFramework

    public var displayText: String {
        switch self {
        case .unavailable: "未设置经确认的每日热量框架，不能判断今天是否超出。"
        case .cannotDetermineDailyTotal: "已设置每日热量参考，但三餐卡没有可核验热量，不能据此判断今天全天是否超出；仍以正常下一餐为准。"
        case .mayExceedDailyFramework: "计划外餐食的估算上限本身已高于每日参考上限；这只是可能性，不能据此断言已超标。"
        }
    }
}

/// 计划外餐食照片只保存在用户本地资料目录；模型输出永远以范围和“估算”呈现，不能替代称重。
public struct UnplannedMealLog: Codable, Sendable, Equatable, Identifiable {
    /// These ceilings protect a local import or an accidental extra-zero from turning a
    /// conservative meal note into a nonsensical daily total. They are validation limits, not
    /// nutrition targets or claims about what a person should eat.
    public static let maximumEstimatedCalories = 20_000
    public static let maximumEstimatedProteinGrams = 2_000
    public let id: UUID
    public let date: Date
    public let localPhotoReference: String?
    public let userDescription: String
    public let estimatedCaloriesRange: ClosedRange<Int>?
    public let estimatedProteinGramsRange: ClosedRange<Int>?
    public let confidence: MealEstimateConfidence?
    public let estimateSource: MealEstimateSource
    public let isEstimate: Bool
    public let compositionConfirmation: MealCompositionConfirmation?

    /// A compact history label strips serialization-only annotations while intentionally
    /// retaining `照片候选：…`. A Vision category must stay visible as a candidate, whereas the
    /// six-field composition and internal quantity marker belong to the editor, not a diary row.
    public var displayDescription: String {
        let beforeComposition = userDescription.components(separatedBy: "｜盘中确认：").first ?? userDescription
        let withoutQuantity = MealQuantityNote.removingStoredActualQuantity(from: beforeComposition)
        return withoutQuantity
            .split(separator: "｜")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != "照片候选保守区间" }
            .joined(separator: "｜")
    }

    public init(
        id: UUID = UUID(), date: Date = .now, localPhotoReference: String? = nil, userDescription: String,
        estimatedCaloriesRange: ClosedRange<Int>? = nil, estimatedProteinGramsRange: ClosedRange<Int>? = nil,
        confidence: MealEstimateConfidence? = nil,
        estimateSource: MealEstimateSource = .textAndOptionalPhotoReference,
        isEstimate: Bool = true,
        compositionConfirmation: MealCompositionConfirmation? = nil
    ) {
        self.id = id; self.date = date
        // 资料文件只接受 App 私有照片引用；外部 URL 或图库路径不能混入私有健康记录。
        self.localPhotoReference = Self.isValidLocalPhotoReference(localPhotoReference) ? localPhotoReference : nil
        self.userDescription = userDescription
        let calories = Self.validatedRange(estimatedCaloriesRange, maximum: Self.maximumEstimatedCalories)
        self.estimatedCaloriesRange = calories
        self.estimatedProteinGramsRange = Self.validatedRange(estimatedProteinGramsRange, maximum: Self.maximumEstimatedProteinGrams)
        // A confidence label without a retained calorie range would look like a completed
        // nutritional assessment. Invalid/imported ranges therefore remain a text-only note.
        self.confidence = calories == nil ? nil : confidence
        self.estimateSource = calories == nil ? .textAndOptionalPhotoReference : estimateSource
        self.isEstimate = isEstimate
        self.compositionConfirmation = compositionConfirmation
    }

    public var displaySummary: String {
        guard let calories = Self.validatedRange(estimatedCaloriesRange, maximum: Self.maximumEstimatedCalories) else { return "已记录计划外餐食；待补充菜品或照片后估算。" }
        let protein = estimatedProteinGramsRange.map { "｜蛋白质约 \($0.lowerBound)–\($0.upperBound)g" } ?? ""
        let confidenceText = confidence.map { "（\($0.displayName)）" } ?? ""
        // A manually confirmed menu/scale range is the selected evidence source. Retained
        // component choices are useful context for editing, but must not reintroduce a second,
        // conflicting "recommended" number in the diary.
        if estimateSource == .ownerConfirmedComposition,
           let compositionConfirmation,
           compositionConfirmation.isNarrowedByOwner {
            return "建议记账 \(compositionConfirmation.recommendedCalories) kcal｜确认后的估算范围 \(calories.lowerBound)–\(calories.upperBound) kcal\(protein)\(confidenceText)。照片估算不是称重值。\(nextMealGuidance)"
        }
        return "估算 \(calories.lowerBound)–\(calories.upperBound) kcal\(protein)\(confidenceText)。照片与菜品分量会带来误差，不作为精准热量。\(nextMealGuidance)"
    }

    /// Short provenance for compact history rows.  Keep this separate from `estimateBasis`,
    /// which is intentionally fuller for the editable current-day view.
    public var historyEstimateLabel: String {
        switch estimateSource {
        case .onDevicePhotoCandidate:
            "本机照片候选 · 宽范围"
        case .ownerProvidedRange:
            "你确认的范围 · 仍为估算"
        case .ownerConfirmedComposition:
            "盘中已核对 · 仍为估算"
        case .textAndOptionalPhotoReference:
            "文字记录 · 宽范围"
        }
    }

    /// This is an explanation of the range source, not an assertion that a photo was understood.
    /// A selected image is merely a private visual reference until the owner adds text/amounts.
    public var estimateBasis: String {
        switch estimateSource {
        case .ownerProvidedRange:
            return "范围依据：你补充的分量/菜单范围；仍是估算，不是营养检测。"
        case .onDevicePhotoCandidate:
            return "范围依据：本机 Vision 图像候选和你确认的菜品/分量；油、酱汁和遮挡仍可导致较大误差。"
        case .ownerConfirmedComposition:
            return "范围依据：照片/文字加上你确认的主食、肉蛋豆、蔬菜、油酱和实际吃掉比例；仍是估算，不是称重或营养检测。"
        case .textAndOptionalPhotoReference:
            return "范围依据：你的文字描述和可选本地照片参考；未做精准识别或称重。"
        }
    }

    /// 没有菜单与克重时不伪造“今天吃超标”的结论，也不以补练或节食作补偿。
    public var nextMealGuidance: String {
        " 下一餐正常回到原计划；不补练、不挨饿。若食材不匹配，拍现有食材后再重排。"
    }

    /// 仅在计划外餐食的估算上限本身超过用户确认的日框架时给出“可能”提醒；固定
    /// 三餐没有被伪造营养数值，因此低于框架的单餐也不能反推全天未超出。不会自动
    /// 改变餐卡、目标或训练。
    public func spaceSignal(confirmedDailyCalorieFramework: DailyCalorieFramework?) -> UnplannedMealSpaceSignal {
        guard let confirmedDailyCalorieFramework,
              let estimatedCaloriesRange = Self.validatedRange(estimatedCaloriesRange, maximum: Self.maximumEstimatedCalories) else { return .unavailable }
        return estimatedCaloriesRange.upperBound > confirmedDailyCalorieFramework.upperBound
            ? .mayExceedDailyFramework
            : .cannotDetermineDailyTotal
    }

    private static func isValidLocalPhotoReference(_ reference: String?) -> Bool {
        PrivateMealPhotoStore.isValidLocalPhotoReference(reference)
    }

    public static func validatedCaloriesRange(_ range: ClosedRange<Int>?) -> ClosedRange<Int>? {
        validatedRange(range, maximum: maximumEstimatedCalories)
    }

    public static func validatedProteinRange(_ range: ClosedRange<Int>?) -> ClosedRange<Int>? {
        validatedRange(range, maximum: maximumEstimatedProteinGrams)
    }

    private static func validatedRange(_ range: ClosedRange<Int>?, maximum: Int) -> ClosedRange<Int>? {
        guard let range,
              range.lowerBound >= 0,
              range.upperBound >= range.lowerBound,
              range.upperBound <= maximum else { return nil }
        return range
    }

    private enum CodingKeys: String, CodingKey {
        case id, date, localPhotoReference, userDescription, estimatedCaloriesRange
        case estimatedProteinGramsRange, confidence, estimateSource, isEstimate, compositionConfirmation
    }

    /// Older notes remain readable, while malformed imported numeric ranges are reduced to a
    /// text-only local note. This is safer than allowing a corrupt total to be displayed as an
    /// estimate or crash arithmetic used by the daily summary.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        date = try values.decode(Date.self, forKey: .date)
        localPhotoReference = Self.isValidLocalPhotoReference(try values.decodeIfPresent(String.self, forKey: .localPhotoReference))
            ? try values.decodeIfPresent(String.self, forKey: .localPhotoReference)
            : nil
        userDescription = try values.decode(String.self, forKey: .userDescription)
        let calories = Self.validatedCaloriesRange(try values.decodeIfPresent(ClosedRange<Int>.self, forKey: .estimatedCaloriesRange))
        estimatedCaloriesRange = calories
        estimatedProteinGramsRange = Self.validatedProteinRange(try values.decodeIfPresent(ClosedRange<Int>.self, forKey: .estimatedProteinGramsRange))
        confidence = calories == nil ? nil : try values.decodeIfPresent(MealEstimateConfidence.self, forKey: .confidence)
        if calories == nil {
            estimateSource = .textAndOptionalPhotoReference
        } else if let decodedSource = try values.decodeIfPresent(MealEstimateSource.self, forKey: .estimateSource) {
            estimateSource = decodedSource
        } else {
            estimateSource = confidence == .medium ? .ownerProvidedRange : .textAndOptionalPhotoReference
        }
        isEstimate = try values.decodeIfPresent(Bool.self, forKey: .isEstimate) ?? true
        compositionConfirmation = try values.decodeIfPresent(
            MealCompositionConfirmation.self,
            forKey: .compositionConfirmation
        )
    }
}

public extension MealEstimateConfidence {
    var displayName: String {
        switch self {
        case .low: "低置信度"
        case .medium: "已补充分量"
        case .high: "仍需核对"
        }
    }
}

public enum UnplannedMealEstimator {
    /// 仅接收用户主动提交的描述/本地图片引用；无菜单和克重时保持低置信度与较宽范围。
    public static func conservativeEstimate(
        description: String,
        localPhotoReference: String? = nil,
        portionChoice: MealPortionChoice = .uncertain,
        at date: Date = .now
    ) -> UnplannedMealLog {
        UnplannedMealLog(
            date: date, localPhotoReference: localPhotoReference, userDescription: description,
            estimatedCaloriesRange: portionChoice.adjusting(450...900),
            estimatedProteinGramsRange: 20...40,
            confidence: .low
        )
    }

    /// 用户可主动补充餐盒克重、菜单或自行核对后的范围。范围仍是记录而非营养检测结果，
    /// 且只影响“可能挤占当天空间”的提示，绝不会反向改餐食、热量框架或训练。
    public static func estimate(
        description: String,
        localPhotoReference: String? = nil,
        photoSuggestedCaloriesRange: ClosedRange<Int>? = nil,
        photoRequiresConservativeRange: Bool = false,
        portionChoice: MealPortionChoice = .uncertain,
        manualCaloriesRange: ClosedRange<Int>? = nil,
        manualProteinRange: ClosedRange<Int>? = nil,
        manualRangeConfirmedByOwner: Bool = false,
        compositionConfirmation: MealCompositionConfirmation? = nil,
        at date: Date = .now
    ) -> UnplannedMealLog {
        // A typed pair of numbers is not enough to narrow a photographed meal: oil, sweet
        // drinks, add-ons, and the eaten fraction can still be missing. The UI must obtain this
        // explicit whole-serving confirmation; callers that omit it safely keep the wide range.
        if manualRangeConfirmedByOwner,
           let calories = UnplannedMealLog.validatedCaloriesRange(manualCaloriesRange) {
            let protein = UnplannedMealLog.validatedProteinRange(manualProteinRange)
            return UnplannedMealLog(
                date: date,
                localPhotoReference: localPhotoReference,
                userDescription: description,
                estimatedCaloriesRange: calories,
                estimatedProteinGramsRange: protein,
                confidence: .medium,
                estimateSource: .ownerProvidedRange,
                compositionConfirmation: compositionConfirmation
            )
        }
        if !photoRequiresConservativeRange,
           let compositionConfirmation, compositionConfirmation.hasAnyOwnerSelection {
            return UnplannedMealLog(
                date: date,
                localPhotoReference: localPhotoReference,
                userDescription: description,
                estimatedCaloriesRange: compositionConfirmation.estimatedCaloriesRange,
                estimatedProteinGramsRange: nil,
                confidence: compositionConfirmation.isNarrowedByOwner ? .medium : .low,
                estimateSource: .ownerConfirmedComposition,
                compositionConfirmation: compositionConfirmation
            )
        }
        if let photoCalories = UnplannedMealLog.validatedCaloriesRange(photoSuggestedCaloriesRange) {
            // “Less than usual” does not establish the amount of absorbed oil, sugar, toppings,
            // or hidden filling in a high-energy / drink candidate.  Preserve its full category
            // interval unless the owner supplies a whole-serving menu or scale range above.
            let retainedPhotoRange = photoRequiresConservativeRange
                ? photoCalories
                : portionChoice.adjusting(photoCalories)
            return UnplannedMealLog(
                date: date,
                localPhotoReference: localPhotoReference,
                userDescription: description,
                estimatedCaloriesRange: retainedPhotoRange,
                estimatedProteinGramsRange: nil,
                confidence: .low,
                estimateSource: .onDevicePhotoCandidate,
                compositionConfirmation: photoRequiresConservativeRange ? nil : compositionConfirmation
            )
        }
        return conservativeEstimate(
            description: description,
            localPhotoReference: localPhotoReference,
            portionChoice: portionChoice,
            at: date
        )
    }
}

/// A plan-external meal can be honestly recorded only for the local day on which the owner is
/// submitting it. This prevents a stale sheet from filing yesterday's typed description under a
/// different plan after midnight; it does not alter meals, training, or calorie goals.
public enum UnplannedMealLoggingPolicy {
    public static func validationError(
        for date: Date,
        at now: Date = .now,
        calendar: Calendar = .current
    ) -> String? {
        guard calendar.isDate(date, inSameDayAs: now) else {
            return "日期已切换；这条计划外餐食尚未记录。请关闭后从今天日卡重新打开。"
        }
        guard PlanSchedule.dayIndex(for: date, calendar: calendar) != nil else {
            return "当前不是第 1–56 天正式计划日，不能记录计划外餐食。"
        }
        return nil
    }
}

public enum UnplannedMealDaySummary {
    /// 仅累加当天已记录的计划外餐食估算上限；它不是全天准确摄入，也不包含计划餐、
    /// 未记录餐次或 Apple Health 数据。
    public static func estimatedUpperBound(
        for date: Date,
        logs: [UnplannedMealLog],
        calendar: Calendar = .current
    ) -> Int? {
        let values = logs
            .filter { calendar.isDate($0.date, inSameDayAs: date) }
            .compactMap { UnplannedMealLog.validatedCaloriesRange($0.estimatedCaloriesRange)?.upperBound }
        guard !values.isEmpty else { return nil }
        // The stored range validator already makes overflow unrealistic, but keep aggregate
        // arithmetic non-trapping even if a future data importer bypasses that constructor.
        return values.reduce(0) { total, value in
            let result = total.addingReportingOverflow(value)
            return result.overflow ? Int.max : result.partialValue
        }
    }

    public static func spaceSignal(
        for date: Date,
        logs: [UnplannedMealLog],
        confirmedFramework: DailyCalorieFramework?,
        calendar: Calendar = .current
    ) -> UnplannedMealSpaceSignal {
        guard let framework = confirmedFramework, let upperBound = estimatedUpperBound(for: date, logs: logs, calendar: calendar) else { return .unavailable }
        // The self-cooking cards deliberately contain execution detail rather than invented
        // nutrition totals.  Thus an external-meal aggregate below the daily reference is not
        // evidence that the full day is within range; only an aggregate that independently
        // exceeds the reference supports a cautious “may exceed” signal.
        return upperBound > framework.upperBound ? .mayExceedDailyFramework : .cannotDetermineDailyTotal
    }

    /// 计划外餐食只产生说明性估算，不是计划变更输入。这个审计点让界面和未来的
    /// 自动化都不能把一次照片/文字估算当成改餐卡、改训练、改目标或创建计划变更的授权。
    public static func preservesPlan(
        before: PrivateCoachData,
        after: PrivateCoachData
    ) -> Bool {
        before.profile == after.profile
            && before.dailyCompletions == after.dailyCompletions
            && before.planChanges == after.planChanges
            && before.datedHealthStatusNotes == after.datedHealthStatusNotes
            && before.mealSubstitutions == after.mealSubstitutions
            && before.trainingFeedback == after.trainingFeedback
            && before.trainingCards == after.trainingCards
            && before.healthWorkoutSyncs == after.healthWorkoutSyncs
            && before.pendingHealthWorkoutSyncs == after.pendingHealthWorkoutSyncs
            && before.pendingWorkoutConfirmations == after.pendingWorkoutConfirmations
    }
}

public struct UnplannedMealDeletionResult: Sendable, Equatable {
    public let data: PrivateCoachData
    /// Present only when no remaining private record references this exact photo. The caller must
    /// delete this App-private file before committing the returned data, so a failed deletion
    /// leaves the visible record and its retry path intact.
    public let photoReferenceToDelete: String?
    public let deletedLog: UnplannedMealLog?
}

public enum UnplannedMealDeletionService {
    /// A person may delete one of their own unplanned-meal logs at any time; this is privacy
    /// control, not a plan adjustment. The operation never modifies meals, calorie framework,
    /// workouts, completions, or health state.
    public static func prepareDeletion(
        logID: UUID,
        from data: PrivateCoachData
    ) -> UnplannedMealDeletionResult {
        guard let log = data.unplannedMealLogs.first(where: { $0.id == logID }) else {
            return UnplannedMealDeletionResult(data: data, photoReferenceToDelete: nil, deletedLog: nil)
        }
        var changed = data
        changed.unplannedMealLogs.removeAll { $0.id == logID }

        let reference = log.localPhotoReference
        let isStillReferenced = reference.map {
            PrivateMealPhotoReferenceUsage.isReferenced($0, in: changed)
        } ?? false
        return UnplannedMealDeletionResult(
            data: changed,
            photoReferenceToDelete: isStillReferenced ? nil : reference,
            deletedLog: log
        )
    }
}
