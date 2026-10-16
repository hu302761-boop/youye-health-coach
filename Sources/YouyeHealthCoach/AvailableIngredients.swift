import Foundation

/// How an ingredient was entered. A photo is only an owner-confirmed aid on this device;
/// it is never treated as a measured amount and never leaves the device.
public enum AvailableIngredientSource: String, Codable, Sendable, CaseIterable, Equatable {
    case manual
    case photoAssisted
}
/// An ingredient currently available at home. This is inventory for prep and shopping only;
/// it is deliberately separate from meal logs, calories, and HealthKit records.
public struct AvailableIngredient: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public var name: String
    public var quantity: Decimal
    public var unit: String
    public var source: AvailableIngredientSource
    public var confirmedAt: Date
    /// A local-only photo reference retained for owner review. It is optional and not uploaded.
    public var localPhotoReference: String?

    public init(
        id: UUID = UUID(),
        name: String,
        quantity: Decimal,
        unit: String = "份",
        source: AvailableIngredientSource = .manual,
        confirmedAt: Date = .now,
        localPhotoReference: String? = nil
    ) {
        self.id = id
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.name = trimmedName.isEmpty ? "未命名食材" : trimmedName
        self.quantity = quantity.isFinite && quantity >= 0 ? quantity : 0
        let trimmedUnit = unit.trimmingCharacters(in: .whitespacesAndNewlines)
        self.unit = trimmedUnit.isEmpty ? "份" : trimmedUnit
        self.source = source
        self.confirmedAt = confirmedAt
        let trimmedReference = localPhotoReference?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.localPhotoReference = trimmedReference?.isEmpty == true ? nil : trimmedReference
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, quantity, unit, source, confirmedAt, localPhotoReference
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
            name: try values.decode(String.self, forKey: .name),
            quantity: try values.decodeIfPresent(Decimal.self, forKey: .quantity) ?? 0,
            unit: try values.decodeIfPresent(String.self, forKey: .unit) ?? "份",
            source: try values.decodeIfPresent(AvailableIngredientSource.self, forKey: .source) ?? .manual,
            confirmedAt: try values.decodeIfPresent(Date.self, forKey: .confirmedAt) ?? .now,
            localPhotoReference: try values.decodeIfPresent(String.self, forKey: .localPhotoReference)
        )
    }

    /// Stable identity used when matching an item in a weekly shopping plan.
    public var stableKey: String { Self.stableName(name) }

    public static func stableName(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
    }

    /// Grouped plan names such as “北豆腐/鸡蛋” match either exact component.
    public func matchesShoppingItem(_ item: ShoppingItem) -> Bool {
        Self.matches(name: name, shoppingName: item.name)
    }

    public static func matches(name: String, shoppingName: String) -> Bool {
        let ingredient = stableName(name)
        let plan = stableName(shoppingName)
        guard !ingredient.isEmpty, !plan.isEmpty else { return false }
        if ingredient == plan { return true }
        let separators = CharacterSet(charactersIn: "/｜|、,，+&")
        let components = shoppingName
            .components(separatedBy: separators)
            .map(stableName)
            .filter { !$0.isEmpty }
        return components.contains(ingredient)
    }
}

/// Pure inventory helpers keep UI flows predictable and make updates easy to persist atomically.
public enum AvailableIngredientInventory {
    public static func matchingIngredients(
        for item: ShoppingItem,
        in inventory: [AvailableIngredient]
    ) -> [AvailableIngredient] {
        inventory.filter { $0.matchesShoppingItem(item) }
    }

    public static func adding(
        _ ingredient: AvailableIngredient,
        to inventory: [AvailableIngredient]
    ) -> [AvailableIngredient] {
        var result = inventory
        result.append(ingredient)
        return result
    }

    public static func removing(
        id: UUID,
        from inventory: [AvailableIngredient]
    ) -> [AvailableIngredient] {
        inventory.filter { $0.id != id }
    }
}
