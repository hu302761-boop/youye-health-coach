import Foundation

/// Keeps human-friendly food counts separate from a planned recipe's grams and calorie range.
/// A count is an owner-confirmed note, never a weighed amount or a nutrition correction.
public enum MealQuantityNote {
    private static let trailingQuantityPattern = #"\s\d+\s+[^\s｜]+$"#
    /// Chinese meal notes are normally typed without spaces (for example, “鸡蛋2个”).
    /// Recognise only the compact forms for familiar countable units so “意面 200g” and other
    /// weighed portions cannot be silently relabelled as an item count.
    private static let compactKnownUnitPattern = #"\d+\s*(?:个|根|块|粒|片|杯|碗|盘|勺|盒|袋|瓶|串|只|份|把|颗|团|匙|枚)$"#
    /// People commonly type “两个鸡蛋” or “鸡蛋两颗” rather than switching keyboards for
    /// 2. Accept ordinary Chinese numerals only with the same familiar count words; weights
    /// and volumes remain outside this path.
    private static let compactChineseNumeralKnownUnitPattern = #"[一二两俩仨三四五六七八九十]+\s*(?:个|根|块|粒|片|杯|碗|盘|勺|盒|袋|瓶|串|只|份|把|颗|团|匙|枚)$"#
    /// The compact picker can intentionally be used before the food name: `2 个` → `2 个鸡蛋`.
    /// Preserve familiar leading counts as well as the traditional trailing `鸡蛋2个` form.
    /// Custom leading words remain ambiguous next to a food name, so those are retained through
    /// the explicit stored marker written by the picker rather than being guessed from prose.
    private static let leadingCompactKnownUnitPattern = #"^\s*\d+\s*(?:个|根|块|粒|片|杯|碗|盘|勺|盒|袋|瓶|串|只|份|把|颗|团|匙|枚)"#
    private static let leadingCompactChineseNumeralKnownUnitPattern = #"^\s*[一二两俩仨三四五六七八九十]+\s*(?:个|根|块|粒|片|杯|碗|盘|勺|盒|袋|瓶|串|只|份|把|颗|团|匙|枚)"#
    private static let colloquialLeadingCountPattern = #"^\s*(俩|仨)(?=\S)"#
    // A serialized portion note uses `｜` as its field boundary. It must never be consumed as
    // part of a count word, or replacing an old quantity would silently delete the next note.
    private static let storedQuantityPattern = #"实际数量：\s*\d+\s+[^\s｜]+"#
    /// Counts and portions can use a person's own word (such as "小把"), whereas weights,
    /// volumes and energy units must remain ordinary food text instead of becoming a fake count.
    private static let measuredUnits: Set<String> = [
        "g", "克", "kg", "千克", "mg", "毫克", "ml", "毫升", "l", "升", "kcal", "千卡", "大卡", "卡"
    ]

    /// A picker-created quantity is intentionally less permissive than free-form meal text.
    /// Otherwise selecting a custom unit such as "克" would create an authoritative-looking
    /// count marker despite the person never saying that the food was weighed.  Familiar words
    /// such as "小把" and "大颗" remain available, but weight, volume and energy units stay in
    /// the ordinary note field where they do not affect the estimate by themselves.
    public static func isCountableUnit(_ unit: String) -> Bool {
        let trimmed = unit.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...4).contains(trimmed.count),
              !trimmed.contains(where: { $0.isNumber || $0.isWhitespace }) else {
            return false
        }
        return !measuredUnits.contains(trimmed.lowercased())
    }

    /// A count picker may intentionally precede the food name while someone is composing a
    /// note.  The completed record still needs a food description: `2 个` alone cannot tell a
    /// diary or a local photo estimate what was eaten, while `2 个鸡蛋` and `鸡蛋 2 个` can.
    /// If the picker supplied a custom count word, use its exact saved wording so `2 小把` is
    /// also rejected until food text is added.
    public static func hasFoodDescription(_ description: String, excluding actualQuantity: String? = nil) -> Bool {
        var candidate = description.trimmingCharacters(in: .whitespacesAndNewlines)
        if let actualQuantity {
            let rawQuantity = actualQuantity
                .replacingOccurrences(of: "实际数量：", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !rawQuantity.isEmpty {
                candidate = candidate.replacingOccurrences(of: rawQuantity, with: "")
            }
        }
        candidate = candidate.replacingOccurrences(of: leadingCompactKnownUnitPattern, with: "", options: .regularExpression)
        candidate = candidate.replacingOccurrences(of: compactKnownUnitPattern, with: "", options: .regularExpression)
        candidate = candidate.replacingOccurrences(of: leadingCompactChineseNumeralKnownUnitPattern, with: "", options: .regularExpression)
        candidate = candidate.replacingOccurrences(of: compactChineseNumeralKnownUnitPattern, with: "", options: .regularExpression)
        candidate = candidate.replacingOccurrences(of: colloquialLeadingCountPattern, with: "", options: .regularExpression)
        candidate = candidate.replacingOccurrences(of: trailingQuantityPattern, with: "", options: .regularExpression)
        return !candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Returns the final count a person added to a meal description, unless the description is
    /// still exactly the plan title. This prevents a planned recipe title from becoming a false
    /// "actual quantity" merely because it happens to contain a number.
    public static func actualQuantity(from description: String, plannedTitle: String) -> String? {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != plannedTitle else { return nil }
        if let quantity = compactQuantity(
            in: trimmed,
            patterns: [compactKnownUnitPattern, compactChineseNumeralKnownUnitPattern],
            options: [.regularExpression, .backwards]
        ) {
            return quantity
        }
        if let quantity = compactQuantity(
            in: trimmed,
            patterns: [leadingCompactKnownUnitPattern, leadingCompactChineseNumeralKnownUnitPattern],
            options: .regularExpression
        ) {
            return quantity
        }
        if let range = trimmed.range(of: colloquialLeadingCountPattern, options: .regularExpression) {
            return String(trimmed[range]).contains("仨") ? "实际数量：3 个" : "实际数量：2 个"
        }
        guard let range = trimmed.range(
            of: trailingQuantityPattern,
            options: [.regularExpression, .backwards]
        ) else { return nil }
        let quantity = String(trimmed[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = quantity.split(maxSplits: 1, whereSeparator: \.isWhitespace)
        guard parts.count == 2 else { return nil }
        let number = String(parts[0])
        let unit = String(parts[1])
        guard !number.isEmpty, isCountableUnit(unit) else { return nil }
        return "实际数量：\(number) \(unit)"
    }

    private static func compactQuantity(
        in value: String,
        patterns: [String],
        options: String.CompareOptions
    ) -> String? {
        for pattern in patterns {
            guard let range = value.range(of: pattern, options: options) else { continue }
            let raw = String(value[range]).filter { !$0.isWhitespace }
            guard let unit = raw.last.map(String.init),
                  let count = normalizedCount(String(raw.dropLast())),
                  count > 0 else { continue }
            return "实际数量：\(count) \(unit)"
        }
        return nil
    }

    private static func normalizedCount(_ value: String) -> Int? {
        if let numeric = Int(value) { return numeric }
        let values: [Character: Int] = [
            "一": 1, "二": 2, "两": 2, "俩": 2, "仨": 3, "三": 3, "四": 4,
            "五": 5, "六": 6, "七": 7, "八": 8, "九": 9
        ]
        var total = 0
        var digit = 0
        for character in value {
            if character == "十" {
                total += (digit == 0 ? 1 : digit) * 10
                digit = 0
            } else if let value = values[character] {
                digit = value
            } else {
                return nil
            }
        }
        let result = total + digit
        return result > 0 ? result : nil
    }

    /// The compact quantity control can be used before the food name is typed (for example,
    /// `2 小块` → `2 小块鸡蛋`).  Keep that explicit selection only while its exact wording
    /// remains in the draft, so a later manual deletion cannot leave a stale quantity behind.
    public static func isStillPresent(_ actualQuantity: String, in description: String) -> Bool {
        let prefix = "实际数量："
        guard actualQuantity.hasPrefix(prefix) else { return false }
        let rawQuantity = actualQuantity
            .dropFirst(prefix.count)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return !rawQuantity.isEmpty && description.contains(rawQuantity)
    }

    /// Updates the single count in a food draft without appending a second, contradictory one.
    /// This covers both picker spacing (`鸡蛋 2 个`) and ordinary compact Chinese input
    /// (`鸡蛋2个`, `两个鸡蛋`).  A picker-saved custom unit is supplied as a final exact-match
    /// fallback, so `2 小把青菜` can be changed without guessing that arbitrary prose is a unit.
    public static func replacingQuantity(
        in description: String,
        previouslyConfirmed: String? = nil,
        with replacement: String
    ) -> String {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return replacement }

        let knownTrailingPatterns = [compactKnownUnitPattern, compactChineseNumeralKnownUnitPattern]
        if let range = firstMatchingRange(in: trimmed, patterns: knownTrailingPatterns, options: [.regularExpression, .backwards]) {
            return replacing(range: range, in: trimmed, with: replacement)
        }
        let knownLeadingPatterns = [leadingCompactKnownUnitPattern, leadingCompactChineseNumeralKnownUnitPattern]
        if let range = firstMatchingRange(in: trimmed, patterns: knownLeadingPatterns, options: .regularExpression) {
            return replacing(range: range, in: trimmed, with: replacement)
        }
        if let range = trimmed.range(of: colloquialLeadingCountPattern, options: .regularExpression) {
            return replacing(range: range, in: trimmed, with: replacement)
        }
        if let range = trimmed.range(of: trailingQuantityPattern, options: [.regularExpression, .backwards]) {
            return replacing(range: range, in: trimmed, with: replacement)
        }
        if let previouslyConfirmed {
            let old = previouslyConfirmed
                .replacingOccurrences(of: "实际数量：", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !old.isEmpty,
               let range = trimmed.range(of: old, options: .backwards) {
                return replacing(range: range, in: trimmed, with: replacement)
            }
        }
        return "\(trimmed) \(replacement)"
    }

    private static func firstMatchingRange(
        in value: String,
        patterns: [String],
        options: String.CompareOptions
    ) -> Range<String.Index>? {
        for pattern in patterns {
            if let range = value.range(of: pattern, options: options) { return range }
        }
        return nil
    }

    private static func replacing(
        range: Range<String.Index>,
        in value: String,
        with replacement: String
    ) -> String {
        let needsLeadingSpace = range.lowerBound > value.startIndex
            && !value[value.index(before: range.lowerBound)].isWhitespace
        return value.replacingCharacters(in: range, with: "\(needsLeadingSpace ? " " : "")\(replacement)")
    }

    /// Restores a previously confirmed count when a planned meal is reopened. The food title in
    /// that form intentionally remains the recipe title, so reparsing the title would lose the
    /// owner's count on an unrelated later edit.
    public static func storedActualQuantity(in portionNote: String?) -> String? {
        guard let portionNote,
              let range = portionNote.range(of: storedQuantityPattern, options: .regularExpression) else {
            return nil
        }
        return String(portionNote[range])
    }

    /// Removes the private quantity marker from a person-facing description while leaving the
    /// food wording intact. This is used by the plan-external diary, whose estimate metadata is
    /// serialized in the same string for backwards compatibility.
    public static func removingStoredActualQuantity(from value: String) -> String {
        let withoutMarker = value.replacingOccurrences(
            of: storedQuantityPattern,
            with: "",
            options: .regularExpression
        )
        return withoutMarker
            .split(separator: "｜")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "｜")
    }

    /// Replaces every previous internal count marker while preserving unrelated portion notes.
    /// Splitting the serialized note first also avoids leaving doubled separators after an edit.
    public static func merging(_ portionNote: String?, with actualQuantity: String?) -> String? {
        let withoutStoredQuantity = removingStoredActualQuantity(from: portionNote ?? "")
        var fragments = withoutStoredQuantity
            .split(separator: "｜")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if let actualQuantity {
            fragments.append(actualQuantity)
        }
        return fragments.isEmpty ? nil : fragments.joined(separator: "｜")
    }
}
