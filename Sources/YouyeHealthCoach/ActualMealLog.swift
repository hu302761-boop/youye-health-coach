import Foundation

public enum ActualMealRelationship: String, Codable, Sendable, Equatable {
    case asPlanned
    case different
    case planExternal

    public var displayName: String {
        switch self {
        case .asPlanned: "按计划"
        case .different: "吃了别的"
        case .planExternal: "本餐计划外"
        }
    }
}

/// A private, owner-entered meal diary entry. It records what was actually eaten and remains
/// separate from calorie estimates: writing a sentence here never invents nutrition values.
public struct ActualMealLog: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let date: Date
    public let slot: MealSlot
    public let relationship: ActualMealRelationship
    public let description: String
    public let portionNote: String?
    public let localPhotoReference: String?
    public let estimatedCaloriesRange: ClosedRange<Int>?
    public let compositionConfirmation: MealCompositionConfirmation?
    public let recordedAt: Date

    public init(
        id: UUID = UUID(),
        date: Date,
        slot: MealSlot,
        relationship: ActualMealRelationship,
        description: String,
        portionNote: String? = nil,
        localPhotoReference: String? = nil,
        estimatedCaloriesRange: ClosedRange<Int>? = nil,
        compositionConfirmation: MealCompositionConfirmation? = nil,
        recordedAt: Date = .now
    ) {
        self.id = id
        self.date = date
        self.slot = slot
        self.relationship = relationship
        self.description = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPortion = portionNote?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.portionNote = normalizedPortion?.isEmpty == false ? normalizedPortion : nil
        self.localPhotoReference = PrivateMealPhotoStore.isValidLocalPhotoReference(localPhotoReference) ? localPhotoReference : nil
        self.estimatedCaloriesRange = UnplannedMealLog.validatedCaloriesRange(estimatedCaloriesRange)
        self.compositionConfirmation = compositionConfirmation
        self.recordedAt = recordedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, date, slot, relationship, description, portionNote, localPhotoReference
        case estimatedCaloriesRange, compositionConfirmation, recordedAt
    }

    /// Older local meal records have no calorie field. Keep that value absent instead of
    /// inventing a historical estimate during migration.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        date = try values.decode(Date.self, forKey: .date)
        slot = try values.decode(MealSlot.self, forKey: .slot)
        relationship = try values.decode(ActualMealRelationship.self, forKey: .relationship)
        description = try values.decode(String.self, forKey: .description)
        portionNote = try values.decodeIfPresent(String.self, forKey: .portionNote)
        let decodedPhoto = try values.decodeIfPresent(String.self, forKey: .localPhotoReference)
        localPhotoReference = PrivateMealPhotoStore.isValidLocalPhotoReference(decodedPhoto) ? decodedPhoto : nil
        estimatedCaloriesRange = UnplannedMealLog.validatedCaloriesRange(
            try values.decodeIfPresent(ClosedRange<Int>.self, forKey: .estimatedCaloriesRange)
        )
        compositionConfirmation = try values.decodeIfPresent(
            MealCompositionConfirmation.self,
            forKey: .compositionConfirmation
        )
        recordedAt = try values.decode(Date.self, forKey: .recordedAt)
    }

    public var validationError: String? {
        if description.isEmpty { return "请写下这餐实际吃了什么。" }
        if description.count > 240 { return "餐食记录请控制在 240 个字以内。" }
        if let portionNote, portionNote.count > 120 { return "份量备注请控制在 120 个字以内。" }
        return nil
    }

    public var energyText: String? {
        estimatedCaloriesRange.map { range in
            // A menu or scale range is a deliberate owner override. Older records can retain
            // previously entered plate components too, but their calculated midpoint must never
            // become the diary value for a different owner-provided range.
            if usesOwnerProvidedEnergyRange {
                return "菜单/秤范围 · \(range.lowerBound)–\(range.upperBound) kcal（仍为估算，非称重）"
            }
            // A retained component form must never override the explicit boundary of a
            // conservative photo candidate. This also keeps older local records honest if they
            // happen to contain both fields from a previous editor state.
            if retainsConservativePhotoCandidate {
                return "\(historyEstimateLabel) · \(range.lowerBound)–\(range.upperBound) kcal"
            }
            if let compositionConfirmation, compositionConfirmation.isNarrowedByOwner {
                return "盘中已核对 · 建议记账 \(compositionConfirmation.recommendedCalories) kcal（估算范围 \(range.lowerBound)–\(range.upperBound)，非称重）"
            }
            return "\(historyEstimateLabel) · \(range.lowerBound)–\(range.upperBound) kcal"
        }
    }

    /// Presentation-only portion text for the diary.  Keep the serialized markers in
    /// `portionNote` so an edit can restore its honest estimation boundary, but never surface
    /// those implementation details in a history row.  An owner-confirmed count is made easy
    /// to scan without implying that it was converted into a weight or a new calorie value.
    public var displayPortionNote: String? {
        guard let portionNote else { return nil }
        let actualQuantity = MealQuantityNote.storedActualQuantity(in: portionNote)?
            .replacingOccurrences(of: "实际数量：", with: "数量：")
        let internalMarkers: Set<String> = [
            "照片候选保守区间",
            "照片默认范围",
            "照片已移除，保留候选范围",
            "菜单/秤热量范围"
        ]
        var fragments = MealQuantityNote.removingStoredActualQuantity(from: portionNote)
            .split(separator: "｜")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !internalMarkers.contains($0) }
        if let actualQuantity { fragments.append(actualQuantity) }
        return fragments.isEmpty ? nil : fragments.joined(separator: "｜")
    }

    /// Compact source boundary for both the current and historical diary rows.  The optional
    /// image is a private reference, not evidence that a photo supplied a weighed calorie value.
    public var historyEstimateLabel: String {
        if usesOwnerProvidedEnergyRange {
            return "菜单/秤范围 · 仍为估算"
        }
        if retainsConservativePhotoCandidate {
            return removedPhotoRetainsCandidateRange
                ? "本机照片候选（照片已移除） · 宽范围"
                : "本机照片候选 · 宽范围"
        }
        if removedPhotoRetainsCandidateRange { return "本机照片已移除 · 宽范围" }
        if compositionConfirmation?.isNarrowedByOwner == true {
            return "盘中已核对 · 仍为估算"
        }
        if localPhotoReference != nil {
            return "本机照片参考 · 宽范围"
        }
        if relationship == .asPlanned {
            return "计划食材估算"
        }
        return "实际餐食估算"
    }

    private var usesOwnerProvidedEnergyRange: Bool {
        portionNote?.contains("菜单/秤热量范围") == true
    }

    private var retainsConservativePhotoCandidate: Bool {
        portionNote?.contains("照片候选保守区间") == true
            || portionNote?.contains("照片默认范围") == true
    }

    private var removedPhotoRetainsCandidateRange: Bool {
        portionNote?.contains("照片已移除，保留候选范围") == true
    }
}

public enum ActualMealLogService {
    public static func log(
        for date: Date,
        slot: MealSlot,
        in data: PrivateCoachData,
        calendar: Calendar = .current
    ) -> ActualMealLog? {
        data.actualMealLogs
            .filter { calendar.isDate($0.date, inSameDayAs: date) && $0.slot == slot }
            .max { $0.recordedAt < $1.recordedAt }
    }

    public static func recording(
        _ log: ActualMealLog,
        in data: PrivateCoachData,
        calendar: Calendar = .current
    ) -> Result<PrivateCoachData, ActualMealLogError> {
        if let validationError = log.validationError {
            return .failure(.validation(validationError))
        }
        var changed = data
        changed.actualMealLogs.removeAll {
            calendar.isDate($0.date, inSameDayAs: log.date) && $0.slot == log.slot
        }
        changed.actualMealLogs.append(log)
        return .success(changed)
    }

    public static func removing(
        date: Date,
        slot: MealSlot,
        from data: PrivateCoachData,
        calendar: Calendar = .current
    ) -> PrivateCoachData {
        var changed = data
        changed.actualMealLogs.removeAll {
            calendar.isDate($0.date, inSameDayAs: date) && $0.slot == slot
        }
        return changed
    }

    /// Returns the previous App-private photo only after the replacement data no longer refers
    /// to it anywhere. Callers persist `updatedData` first, then delete this file; a crash in
    /// between leaves only a launch-cleanable orphan and never a dangling visible record.
    public static func photoReferenceToDeleteAfterReplacement(
        previousReference: String?,
        replacementReference: String?,
        updatedData: PrivateCoachData
    ) -> String? {
        guard let previousReference,
              previousReference != replacementReference,
              !PrivateMealPhotoReferenceUsage.isReferenced(previousReference, in: updatedData) else { return nil }
        return previousReference
    }
}

/// Re-validates the identity and day at the write boundary. A meal form can remain open while
/// midnight passes or while the local owner record is replaced; neither stale screen may write
/// into the newly active day or owner.
public enum ActualMealSubmissionPolicy {
    public static func validationError(
        for planDate: Date,
        formOwnerID: UUID,
        currentOwnerID: UUID,
        at now: Date = .now,
        calendar: Calendar = .current
    ) -> String? {
        guard formOwnerID == currentOwnerID else {
            return "本机资料已删除或切换；没有保存旧页面中的餐食或照片。"
        }
        guard calendar.isDate(planDate, inSameDayAs: now) else {
            return "日期已切换；这餐尚未保存。请关闭后从今天重新打开记录。"
        }
        return nil
    }
}

public enum ActualMealLogError: Error, Sendable, Equatable {
    case validation(String)

    public var message: String {
        switch self {
        case let .validation(message): message
        }
    }
}
