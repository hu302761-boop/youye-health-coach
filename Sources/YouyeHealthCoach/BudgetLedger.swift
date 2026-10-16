import Foundation

public enum BudgetCategory: String, Codable, Sendable, CaseIterable {
    case ingredients = "食材"
    case swimming = "游泳"
    case cycling = "骑行"
    case skincare = "护肤/耗材"
    case buffer = "缓冲"
}

public struct ExpenseEntry: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let date: Date
    public let category: BudgetCategory
    public let amountYuan: Decimal
    public let note: String
    public let isUserConfirmed: Bool

    public init(id: UUID = UUID(), date: Date = .now, category: BudgetCategory, amountYuan: Decimal, note: String, isUserConfirmed: Bool = true) {
        // Amounts also enter through imported/restored local data. A malformed negative,
        // NaN, or infinite value must never terminate the App, create a fake budget credit, or
        // contaminate a remaining-budget display; normalize it to zero and let the UI's
        // explicit validation prevent normal manual entry in the first place.
        self.id = id
        self.date = date
        self.category = category
        self.amountYuan = amountYuan.isFinite && amountYuan >= 0 ? amountYuan : 0
        self.note = note
        self.isUserConfirmed = isUserConfirmed
    }

    private enum CodingKeys: String, CodingKey {
        case id, date, category, amountYuan, note, isUserConfirmed
    }

    /// Restored local data is still input.  Codable synthesis would assign an invalid decimal
    /// directly and bypass the initializer's finite/non-negative boundary.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try values.decode(UUID.self, forKey: .id),
            date: try values.decode(Date.self, forKey: .date),
            category: try values.decode(BudgetCategory.self, forKey: .category),
            amountYuan: try values.decode(Decimal.self, forKey: .amountYuan),
            note: try values.decode(String.self, forKey: .note),
            isUserConfirmed: try values.decodeIfPresent(Bool.self, forKey: .isUserConfirmed) ?? true
        )
    }
}

public struct MonthlyBudgetLedger: Codable, Sendable, Equatable {
    public let monthKey: String
    public let capYuan: Decimal
    public var entries: [ExpenseEntry]

    public init(monthKey: String, capYuan: Decimal = 1500, entries: [ExpenseEntry] = []) {
        self.monthKey = monthKey
        // The monthly cap is an owner-facing safety boundary. A malformed local backup must not
        // turn it negative, NaN, or infinite and make remaining budget look like a credit.
        self.capYuan = capYuan.isFinite && capYuan >= 0 ? capYuan : 0
        // A receipt UUID is the local idempotency key.  Import/restore can bypass `record`, so
        // keep the first occurrence here as well: a duplicated serialized receipt must never
        // spend the same money twice in one month's displayed total.
        var seenEntryIDs = Set<UUID>()
        self.entries = entries.filter { seenEntryIDs.insert($0.id).inserted }
    }

    private enum CodingKeys: String, CodingKey { case monthKey, capYuan, entries }

    /// Codable synthesis would bypass the initializer's validation. Decode via the initializer
    /// because private exports/backups are still untrusted input when restored to an App.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            monthKey: try values.decode(String.self, forKey: .monthKey),
            capYuan: try values.decodeIfPresent(Decimal.self, forKey: .capYuan) ?? 1_500,
            entries: try values.decodeIfPresent([ExpenseEntry].self, forKey: .entries) ?? []
        )
    }

    /// UI input prevents negative expenses, but decoded/imported private JSON is untrusted.
    /// Ignore malformed negative amounts in all display totals so a damaged receipt cannot make
    /// remaining budget look larger or reduce a category's real confirmed spending.
    public var confirmedSpentYuan: Decimal {
        entries.filter { $0.isUserConfirmed && $0.amountYuan >= 0 }.reduce(0) { $0 + $1.amountYuan }
    }
    public var remainingYuan: Decimal { capYuan - confirmedSpentYuan }

    public func confirmedSpentYuan(in category: BudgetCategory) -> Decimal {
        entries
            .filter { $0.isUserConfirmed && $0.category == category && $0.amountYuan >= 0 }
            .reduce(0) { $0 + $1.amountYuan }
    }

    /// A weekly shopping reservation must be compared with receipts that happened during that
    /// plan week only. Using the month-to-date ingredient total here would falsely report a
    /// later week's list as over budget after an earlier week's groceries were recorded.
    public func confirmedSpentYuan(
        in category: BudgetCategory,
        during interval: DateInterval
    ) -> Decimal {
        entries
            // `DateInterval.contains` includes its end point. Program weeks are deliberately
            // half-open, so a receipt timestamped at the next week's 00:00 must not count
            // toward the preceding week's reservation.
            .filter {
                $0.isUserConfirmed && $0.category == category && $0.amountYuan >= 0
                    && $0.date >= interval.start && $0.date < interval.end
            }
            .reduce(0) { $0 + $1.amountYuan }
    }

    /// Keep an at-least-once UI callback or a retry from counting the same confirmed receipt
    /// twice. A new manual record always receives a new UUID, so this never suppresses a second
    /// real purchase.
    public mutating func record(_ entry: ExpenseEntry) {
        guard !entries.contains(where: { $0.id == entry.id }) else { return }
        entries.append(entry)
    }

    /// A display snapshot must not include a receipt dated after the moment being reviewed.
    /// This prevents malformed/imported future records from shrinking today's available budget.
    public func snapshot(asOf date: Date, calendar: Calendar = .current) -> MonthlyBudgetLedger {
        // Budget is presented as a calendar-day total.  Callers commonly pass the start of
        // today, so a raw `entry.date <= date` comparison would hide purchases made later that
        // same day.  Use the next local day boundary instead: include all of the reviewed day,
        // while still excluding any future-dated imported receipt.
        let nextDay = calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: date)
        ) ?? date.addingTimeInterval(24 * 60 * 60)
        return MonthlyBudgetLedger(
            monthKey: monthKey,
            capYuan: capYuan,
            entries: entries.filter { $0.date < nextDay }
        )
    }
}

public enum BudgetPolicy {
    public static let defaultAllocation: [BudgetCategory: Decimal] = [
        .ingredients: 900, .swimming: 120, .cycling: 50, .skincare: 100, .buffer: 330
    ]

    public static func warning(for ledger: MonthlyBudgetLedger) -> String? {
        if ledger.remainingYuan < 0 { return "已超过月预算；暂停新增非必要支出，先核对账本。" }
        if ledger.remainingYuan < 100 { return "预算缓冲不足 100 元；不自动购买任何服务或商品。" }
        return nil
    }

    public static func allocationWarning(for ledger: MonthlyBudgetLedger, category: BudgetCategory) -> String? {
        guard let allocation = defaultAllocation[category] else { return nil }
        let spent = ledger.confirmedSpentYuan(in: category)
        if spent > allocation { return "\(category.rawValue)已超过本月建议预留 ¥\(allocation.description)；仅供你决定是否调整，App 不会自动削减餐食或购买任何东西。" }
        return nil
    }

    /// 每周采购上限是计划预留，不是实时价格、账单或自动扣款。
    public static func weeklyShoppingGuidance(plan: WeeklyShoppingPlan, confirmedIngredientSpent: Decimal) -> String {
        if confirmedIngredientSpent > plan.budgetCapYuan {
            return "本周已确认食材 ¥\(confirmedIngredientSpent.description)，高于本周预留上限 ¥\(plan.budgetCapYuan.description)。请核对实际账单；不会自动改餐或下单。"
        }
        return "本周食材预留上限 ¥\(plan.budgetCapYuan.description)；已确认食材 ¥\(confirmedIngredientSpent.description)。预留不等于实时价格或已花金额。"
    }
}

/// Manual expense sheets can remain alive while the local profile is deleted or replaced.
/// Re-check ownership and the user-entered values at the final write boundary so a stale sheet
/// cannot spend against a different person's private ledger.
public enum ExpenseSubmissionPolicy {
    public static func validationError(
        amountYuan: Decimal,
        note: String,
        formOwnerID: UUID,
        currentOwnerID: UUID
    ) -> String? {
        guard formOwnerID == currentOwnerID else {
            return "本机资料已删除或切换；没有把旧页面中的支出写入新账本。"
        }
        guard amountYuan.isFinite, amountYuan > 0 else {
            return "请填写大于 0 的有效实际金额；未记录任何支出。"
        }
        guard !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "请填写支出备注；未记录任何支出。"
        }
        return nil
    }
}

public extension MonthlyBudgetLedger {
    static func monthKey(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", components.year ?? 0, components.month ?? 0)
    }
}
