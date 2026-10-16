import Foundation

public struct ShoppingItem: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let name: String
    public let quantity: String
    public let prepNote: String
    public let mustBuy: Bool

    public init(id: UUID = UUID(), name: String, quantity: String, prepNote: String = "", mustBuy: Bool = true) {
        self.id = id; self.name = name; self.quantity = quantity; self.prepNote = prepNote; self.mustBuy = mustBuy
    }

    /// UUID 仅供当前列表渲染；持久化勾选使用稳定键，避免 App 重启后随机 UUID 导致已购状态丢失。
    /// This unscoped form is retained solely to read old on-device flags; new flags must include
    /// their program week so “鸡蛋 16 个” in two different weeks cannot share completion state.
    public var stableKey: String { "\(name)|\(quantity)" }
}

public struct WeeklyShoppingPlan: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let weekNumber: Int
    public let budgetCapYuan: Decimal
    public let items: [ShoppingItem]
    public let priceStatus: String

    public init(id: UUID = UUID(), weekNumber: Int, budgetCapYuan: Decimal, items: [ShoppingItem], priceStatus: String = "待核验：未提供实时价格") {
        self.id = id; self.weekNumber = weekNumber; self.budgetCapYuan = budgetCapYuan; self.items = items; self.priceStatus = priceStatus
    }

    public var requiredItems: [ShoppingItem] { items.filter(\.mustBuy) }

    public func stableKey(for item: ShoppingItem) -> String {
        "week-\(weekNumber)|\(item.stableKey)"
    }
}

/// The owner’s ¥1,500 cap is a calendar-month total across food, swimming, transport,
/// skincare and buffer. The 56-day program spans roughly two months, so its food reservation
/// must neither pretend to be one month’s total nor silently consume the whole two-month budget.
/// This is a planning ceiling only; no price is asserted and only a user-recorded receipt counts
/// as spending in the monthly ledger.
public enum ProgramFoodBudgetPolicy {
    public static let eightWeekReservationYuan: Decimal = 1_600
    public static let weeklyReservationYuan: Decimal = 200

    public static func guidance(for plan: WeeklyShoppingPlan) -> String {
        "8 周食材预留合计 ¥\(eightWeekReservationYuan.description)，本周预留 ¥\(plan.budgetCapYuan.description)。这是为两个月 ¥1,500/月总预算留出游泳、通勤、护肤和缓冲后的计划上限，不是实时价格、账单或已花金额。"
    }
}

public enum ShoppingPurchaseState {
    /// Existing local files used an unscoped `name|quantity` key.  Its original week is not
    /// knowable after an upgrade, so treating it as purchased in the currently visible week
    /// could falsely say that a later week's groceries already exist.  Keep it inert until the
    /// owner explicitly taps the item again; then replace it with the unambiguous week-scoped
    /// key.  “Unknown” is safer than inventing a purchase.
    public static func isMarkedPurchased(_ item: ShoppingItem, in plan: WeeklyShoppingPlan, keys: Set<String>) -> Bool {
        keys.contains(plan.stableKey(for: item))
    }

    public static func toggled(_ item: ShoppingItem, in plan: WeeklyShoppingPlan, keys: Set<String>) -> Set<String> {
        var changed = keys
        let scoped = plan.stableKey(for: item)
        let legacy = item.stableKey
        if changed.contains(scoped) {
            changed.remove(scoped)
        } else {
            changed.insert(scoped)
        }
        // Touching the visible current-week item clears an old ambiguous key and replaces it
        // with a deliberate, week-scoped owner confirmation.
        changed.remove(legacy)
        return changed
    }

    /// Whether the owner explicitly confirmed that this week's item is already at home.
    /// Keys are week-scoped so inventory confirmed for week 1 cannot silently satisfy week 2.
    public static func isMarkedAtHome(_ item: ShoppingItem, in plan: WeeklyShoppingPlan, keys: Set<String>) -> Bool {
        keys.contains(plan.stableKey(for: item))
    }

    /// Toggle the owner-confirmed “already have at home” state. This state is independent from
    /// purchased state and does not delete the original plan item, allowing an easy restore.
    public static func toggledAtHome(_ item: ShoppingItem, in plan: WeeklyShoppingPlan, keys: Set<String>) -> Set<String> {
        var changed = keys
        let scoped = plan.stableKey(for: item)
        if changed.contains(scoped) {
            changed.remove(scoped)
        } else {
            changed.insert(scoped)
        }
        changed.remove(item.stableKey)
        return changed
    }
}

public enum InitialShoppingPlans {
    public static let weekOne = WeeklyShoppingPlan(weekNumber: 1, budgetCapYuan: 200, items: [
        ShoppingItem(name: "去骨鸡腿肉片", quantity: "900g（300g×3袋）", prepNote: "按每餐 300g 分袋，周一/二冷藏，其余冷冻"),
        ShoppingItem(name: "鸡胸肉片", quantity: "600g（300g×2袋）", prepNote: "按每餐 300g 分袋冷冻"),
        ShoppingItem(name: "里脊肉丝", quantity: "280g（1袋）", prepNote: "按一餐分袋冷冻，前一晚移冷藏"),
        ShoppingItem(name: "瘦肉末", quantity: "200g（1袋）", prepNote: "冷冻，使用前一晚移冷藏"),
        ShoppingItem(name: "冷冻鱼片", quantity: "320g（1袋）", prepNote: "使用前一晚移冷藏并放接液盒"),
        ShoppingItem(name: "北豆腐", quantity: "1kg（500g×2盒）", prepNote: "冷藏保存，不冷冻"),
        ShoppingItem(name: "鸡蛋", quantity: "12个", prepNote: "早餐 10 个+周二晚餐 2 个；冷藏保存，保持蛋壳清洁、打蛋后洗手"),
        ShoppingItem(name: "西兰花/卷心菜/番茄/青菜/花菜/彩椒/洋葱/胡萝卜豌豆", quantity: "合计 4–4.5kg", prepNote: "洗净沥干，按菜谱分装；叶菜优先前半周吃"),
        ShoppingItem(name: "大米/红薯", quantity: "大米600g（熟饭180g×6盒）、红薯400g", prepNote: "熟饭分盒冷冻；红薯200g×2冷藏不超过24小时"),
        breakfastEssentials,
        breakfastProduce,
        pantryEssentials
    ])

    public static let weekTwo = WeeklyShoppingPlan(weekNumber: 2, budgetCapYuan: 200, items: [
        ShoppingItem(name: "牛肉片", quantity: "560g（280g×2袋）", prepNote: "按餐分袋冷冻"),
        ShoppingItem(name: "虾仁", quantity: "300g", prepNote: "冷冻，前一晚移冷藏"),
        ShoppingItem(name: "冷冻鱼片/巴沙鱼片", quantity: "320g", prepNote: "冷冻；前一晚移冷藏并放接液盒"),
        ShoppingItem(name: "鸡胸肉片", quantity: "300g", prepNote: "分袋冷冻"),
        ShoppingItem(name: "去皮鸡腿肉片", quantity: "300g", prepNote: "分袋冷冻"),
        ShoppingItem(name: "北豆腐", quantity: "900g", prepNote: "冷藏保存"),
        ShoppingItem(name: "鸡蛋", quantity: "12个", prepNote: "早餐 10 个+周四晚餐 2 个；冷藏保存"),
        ShoppingItem(name: "口蘑/西葫芦/番茄/四季豆/青菜/生菜/娃娃菜/白菜/芹菜/木耳", quantity: "合计约 4–4.5kg（木耳150g）", prepNote: "按每餐克数分装；木耳开封当天用"),
        ShoppingItem(name: "大米/玉米", quantity: "大米约720g、玉米300g", prepNote: "熟饭分盒；玉米按150g×2分装"),
        breakfastEssentials,
        breakfastProduce,
        pantryEssentials
    ])

    public static let weekThree = WeeklyShoppingPlan(weekNumber: 3, budgetCapYuan: 200, items: [
        ShoppingItem(name: "去皮鸡腿肉片", quantity: "600g（300g×2袋）", prepNote: "按餐分袋，前一晚移冷藏"),
        ShoppingItem(name: "鸡胸肉片", quantity: "600g（300g×2袋）", prepNote: "按餐分袋冷冻"),
        ShoppingItem(name: "瘦肉末", quantity: "250g", prepNote: "冷冻，前一晚移冷藏"),
        ShoppingItem(name: "肥牛片", quantity: "220g", prepNote: "冷冻，前一晚移冷藏"),
        ShoppingItem(name: "北豆腐", quantity: "1.2kg", prepNote: "冷藏保存"),
        ShoppingItem(name: "鸡蛋/虾皮", quantity: "鸡蛋 14 个、虾皮 10g", prepNote: "早餐 10 个+晚餐 4 个；虾皮分 5g×2"),
        ShoppingItem(name: "冷冻豌豆胡萝卜/菌菇/芦笋/冬瓜/白菜/青菜", quantity: "合计约 4kg", prepNote: "按餐克数分装"),
        ShoppingItem(name: "大米", quantity: "600g（熟饭 180g×6盒）", prepNote: "周日煮熟分盒冷冻"),
        breakfastEssentials,
        breakfastProduce,
        pantryEssentials
    ])

    public static let weekFour = WeeklyShoppingPlan(weekNumber: 4, budgetCapYuan: 200, items: [
        ShoppingItem(name: "鸡胸肉片", quantity: "550g（300g＋250g）", prepNote: "按周一、周五分两袋冷冻，前一晚移冷藏"),
        ShoppingItem(name: "冷冻鱼片", quantity: "320g", prepNote: "冷冻；周二前一晚移冷藏并放接液盒"),
        ShoppingItem(name: "里脊肉丝", quantity: "280g", prepNote: "按周四一袋冷冻，前一晚移冷藏"),
        ShoppingItem(name: "虾仁", quantity: "300g", prepNote: "按周六一袋冷冻，前一晚移冷藏"),
        ShoppingItem(name: "肥牛/牛肉片", quantity: "280g", prepNote: "按周日一袋冷冻，前一晚移冷藏"),
        ShoppingItem(name: "鸡蛋", quantity: "13个", prepNote: "早餐 10 个+周三晚餐 3 个；冷藏保存"),
        ShoppingItem(name: "即食木耳/熟鹰嘴豆", quantity: "木耳150g、鹰嘴豆200g", prepNote: "开封当天用；鹰嘴豆分100g×2冷藏"),
        ShoppingItem(name: "花菜/番茄/黄瓜/青椒洋葱/生菜/白菜", quantity: "合计约 4.2kg", prepNote: "洗净沥干；黄瓜、生菜单独装，叶菜优先前半周吃"),
        ShoppingItem(name: "大米/土豆", quantity: "大米约720g、土豆450g", prepNote: "熟饭按180g×8和150g×2分盒；土豆熟块225g×2冷藏不超过24小时"),
        breakfastEssentials,
        breakfastProduce,
        pantryEssentials
    ])

    public static let weekFive = WeeklyShoppingPlan(weekNumber: 5, budgetCapYuan: 200, items: [
        ShoppingItem(name: "去皮鸡腿肉片", quantity: "600g（300g×2袋）", prepNote: "按周一、周六分袋冷冻，前一晚移冷藏"),
        ShoppingItem(name: "鸡胸肉片", quantity: "600g（300g×2袋）", prepNote: "按周四、周六分袋冷冻，前一晚移冷藏"),
        ShoppingItem(name: "冷冻鱼片", quantity: "320g", prepNote: "周三前一晚移冷藏并放接液盒"),
        ShoppingItem(name: "牛肉片", quantity: "260g", prepNote: "周五一袋冷冻，前一晚移冷藏"),
        ShoppingItem(name: "虾仁", quantity: "250g", prepNote: "周日前一晚移冷藏"),
        ShoppingItem(name: "北豆腐/鸡蛋", quantity: "北豆腐900g、鸡蛋13个", prepNote: "早餐 10 个+周二晚餐 3 个；豆腐冷藏"),
        ShoppingItem(name: "杏鲍菇/韭菜/西兰花/黄瓜/番茄/胡萝卜/菠菜/白菜", quantity: "合计约 4.3kg", prepNote: "洗净沥干；菠菜、韭菜优先前半周吃"),
        ShoppingItem(name: "大米/全麦面", quantity: "大米约720g、全麦面160g", prepNote: "熟饭按180g×10和150g×2分盒；面条80g×2干分装，酱汁另装"),
        breakfastEssentials,
        breakfastProduce,
        pantryEssentials
    ])

    public static let weekSix = WeeklyShoppingPlan(weekNumber: 6, budgetCapYuan: 200, items: [
        ShoppingItem(name: "去皮鸡腿肉片", quantity: "600g（300g×2袋）", prepNote: "按周一、周五分袋冷冻，前一晚移冷藏"),
        ShoppingItem(name: "里脊肉丝", quantity: "280g", prepNote: "周三一袋冷冻，前一晚移冷藏"),
        ShoppingItem(name: "虾仁", quantity: "300g", prepNote: "周四前一晚移冷藏"),
        ShoppingItem(name: "牛肉片", quantity: "280g", prepNote: "周六一袋冷冻，前一晚移冷藏"),
        ShoppingItem(name: "北豆腐/鸡蛋", quantity: "北豆腐800g、鸡蛋14个", prepNote: "早餐 10 个+晚餐 4 个；豆腐冷藏"),
        ShoppingItem(name: "西葫芦/番茄/木耳/胡萝卜/青椒/西兰花/香菇/青菜/洋葱/卷心菜", quantity: "合计约 4.5kg", prepNote: "洗净沥干；木耳开封当天用，叶菜优先前半周吃"),
        ShoppingItem(name: "大米/荞麦面/玉米/南瓜", quantity: "大米约720g、荞麦面140g、玉米300g、南瓜450g", prepNote: "熟饭按180g×8分盒；面70g×2、玉米150g×2、南瓜225g×2分装"),
        breakfastEssentials,
        breakfastProduce,
        pantryEssentials
    ])

    public static let weekSeven = WeeklyShoppingPlan(weekNumber: 7, budgetCapYuan: 200, items: [
        ShoppingItem(name: "去皮鸡腿肉片", quantity: "600g（300g×2袋）", prepNote: "按周一、周六分袋冷冻，前一晚移冷藏"),
        ShoppingItem(name: "冷冻鱼片", quantity: "320g", prepNote: "周二前一晚移冷藏并放接液盒"),
        ShoppingItem(name: "瘦肉末/鸡胸肉片", quantity: "瘦肉末220g、鸡胸300g", prepNote: "分别按周三、周四分袋冷冻，前一晚移冷藏"),
        ShoppingItem(name: "虾仁", quantity: "250g", prepNote: "周五前一晚移冷藏"),
        ShoppingItem(name: "牛肉片", quantity: "260g", prepNote: "周日前一晚移冷藏"),
        ShoppingItem(name: "北豆腐/鸡蛋/腰果", quantity: "北豆腐400g、鸡蛋12个、腰果15g", prepNote: "早餐 10 个+周五晚餐 2 个；豆腐冷藏；腰果按 7.5g×2 小袋分装"),
        ShoppingItem(name: "花菜/番茄/菌菇/茄子/西芹/豌豆/白菜/海带丝/青菜", quantity: "合计约 4.4kg", prepNote: "洗净沥干；海带提前泡发冲洗，叶菜优先前半周吃"),
        ShoppingItem(name: "大米/快熟荞麦面", quantity: "大米约900g、荞麦面140g", prepNote: "熟饭按180g×12分盒；荞麦面70g×2干分装，汤面留餐须2小时内冷藏"),
        breakfastEssentials,
        breakfastProduce,
        pantryEssentials
    ])

    public static let weekEight = WeeklyShoppingPlan(weekNumber: 8, budgetCapYuan: 200, items: [
        ShoppingItem(name: "去皮鸡腿肉片", quantity: "300g", prepNote: "周一一袋冷冻，前一晚移冷藏"),
        ShoppingItem(name: "鸡胸肉片", quantity: "300g", prepNote: "周三一袋冷冻，前一晚移冷藏"),
        ShoppingItem(name: "冷冻鱼片", quantity: "320g", prepNote: "周四前一晚移冷藏并放接液盒"),
        ShoppingItem(name: "里脊肉丝", quantity: "280g", prepNote: "周五一袋冷冻，前一晚移冷藏"),
        ShoppingItem(name: "虾仁", quantity: "280g", prepNote: "周六前一晚移冷藏"),
        ShoppingItem(name: "北豆腐/鸡蛋", quantity: "北豆腐1kg、鸡蛋12个", prepNote: "早餐 10 个+周日晚餐 2 个；豆腐冷藏"),
        ShoppingItem(name: "彩椒/洋葱/菌菇/青菜/番茄/冬瓜/芥蓝/娃娃菜", quantity: "合计约 4.3kg", prepNote: "洗净沥干；青菜、芥蓝、娃娃菜优先前半周吃"),
        ShoppingItem(name: "大米/全麦意面/玉米/粉丝", quantity: "大米约720g、意面150g、玉米300g、粉丝80g", prepNote: "熟饭按180g×8分盒；意面75g×2、玉米150g×2、粉丝40g×2分装"),
        breakfastEssentials,
        breakfastProduce,
        pantryEssentials
    ])

    /// 7 天早餐循环固定覆盖项。鸡蛋与豆腐如也在晚餐出现，采购时按本周各晚餐用量一并加总。
    private static let breakfastEssentials = ShoppingItem(
        name: "早餐循环｜燕麦/无糖豆浆/全麦吐司/玉米/红薯/小米/嫩豆腐/金枪鱼",
        quantity: "燕麦80g、豆浆850ml、吐司140g、玉米160g、红薯200g、小米35g、嫩豆腐150g、金枪鱼60g",
        prepNote: "燕麦按40g×2、吐司70g×2分装；豆腐和金枪鱼开封当天吃完；红薯/玉米按早餐份冷藏"
    )
    private static let breakfastProduce = ShoppingItem(
        name: "早餐水果蔬菜｜猕猴桃/香蕉/橙子/苹果/番茄/黄瓜",
        quantity: "猕猴桃100g、香蕉60g、橙子150g、苹果150g、番茄250g、黄瓜150g",
        prepNote: "水果按单份留存；切开的番茄、黄瓜不隔夜，优先前半周吃"
    )
    private static let pantryEssentials = ShoppingItem(
        name: "基础调味｜食用油/生抽/盐/蒜/葱姜/黑胡椒/醋/咖喱或孜然",
        quantity: "油约100g、生抽100ml、盐10g、蒜30g、葱姜30g、黑胡椒5g、醋20ml、咖喱或孜然5g",
        prepNote: "按周小瓶/小袋备好；只用于餐卡已列调味，不按实时价格或套餐补货"
    )
}

public enum ShoppingPlanCatalog {
    public static func plan(forWeek weekNumber: Int) -> WeeklyShoppingPlan? {
        switch weekNumber {
        case 1: InitialShoppingPlans.weekOne
        case 2: InitialShoppingPlans.weekTwo
        case 3: InitialShoppingPlans.weekThree
        case 4: InitialShoppingPlans.weekFour
        case 5: InitialShoppingPlans.weekFive
        case 6: InitialShoppingPlans.weekSix
        case 7: InitialShoppingPlans.weekSeven
        case 8: InitialShoppingPlans.weekEight
        default: nil
        }
    }

    /// The program has a fixed eight-week sequence. Keep look-ahead explicit so the UI can
    /// offer next week's prep list without guessing from calendar dates or creating week 9.
    public static func nextPlan(after plan: WeeklyShoppingPlan) -> WeeklyShoppingPlan? {
        self.plan(forWeek: plan.weekNumber + 1)
    }
}

/// The compact weekly list is useful in a shop, but grouped vegetables alone must not hide the
/// gram-level purchase contract of the actual meal cards. This read-only reference derives from
/// the same 56-day dinner and seven-card breakfast catalogues used by the daily plan. It creates
/// no inventory claim, price, purchase, or automatic substitution.
public enum WeeklyMealIngredientReference {
    public struct Day: Sendable, Equatable, Identifiable {
        public let dayIndex: Int
        public let breakfast: MealCard
        public let dinner: MealCard

        public var id: Int { dayIndex }
    }

    public static func days(forWeek weekNumber: Int) -> [Day] {
        guard (1...8).contains(weekNumber) else { return [] }
        let firstIndex = (weekNumber - 1) * 7 + 1
        return (firstIndex..<(firstIndex + 7)).compactMap { dayIndex in
            guard RecipeCatalog.all56.indices.contains(dayIndex - 1) else { return nil }
            return Day(
                dayIndex: dayIndex,
                breakfast: BreakfastCatalog.card(dayIndex: dayIndex),
                dinner: RecipeCatalog.all56[dayIndex - 1]
            )
        }
    }
}

/// 采购表是 56 天餐卡的执行输入，而不是装饰性列表。此处只做类别和关键蛋白覆盖审计；
/// 价格仍保持待核验，实际购买量可由用户根据库存调整后确认。
public enum ShoppingPlanCoverageAudit {
    /// The seven-card breakfast cycle contains five egg breakfasts (10 eggs), not fourteen.
    /// Add only the exact dinner use for that week, so the shopping list does not quietly spend
    /// extra budget on unused perishable food.
    private static let requiredEggsByWeek = [12, 12, 14, 13, 13, 14, 12, 12]

    public static func validate() -> [String] {
        var errors: [String] = []
        for weekNumber in 1...8 {
            guard let plan = ShoppingPlanCatalog.plan(forWeek: weekNumber) else {
                errors.append("第\(weekNumber)周缺采购清单")
                continue
            }
            let text = plan.requiredItems.map { "\($0.name) \($0.quantity)" }.joined(separator: " ")
            if !plan.requiredItems.contains(where: { $0.name.contains("早餐循环") }) { errors.append("第\(weekNumber)周缺早餐循环采购项") }
            if !plan.requiredItems.contains(where: { $0.name.contains("早餐水果蔬菜") }) { errors.append("第\(weekNumber)周缺早餐水果蔬菜采购项") }
            if !plan.requiredItems.contains(where: { $0.name.contains("基础调味") }) { errors.append("第\(weekNumber)周缺基础调味采购项") }
            if !containsAny(text, ["鸡", "牛", "鱼", "虾", "肉", "豆腐", "鸡蛋"]) { errors.append("第\(weekNumber)周缺蛋白采购类别") }
            if !containsAny(text, ["菜", "番茄", "菇", "瓜", "椒", "木耳", "白菜", "芥", "海带", "胡萝卜", "芦笋", "豆"]) { errors.append("第\(weekNumber)周缺蔬菜采购类别") }
            if !containsAny(text, ["米", "面", "玉米", "土豆", "南瓜", "粉丝", "吐司", "燕麦", "红薯", "小米"]) { errors.append("第\(weekNumber)周缺主食采购类别") }
            if eggCount(in: text) < requiredEggsByWeek[weekNumber - 1] { errors.append("第\(weekNumber)周鸡蛋不足以覆盖早餐循环和晚餐") }

            let weekCards = Array(RecipeCatalog.all56[((weekNumber - 1) * 7)..<(weekNumber * 7)])
            let derivedDays = WeeklyMealIngredientReference.days(forWeek: weekNumber)
            if derivedDays.count != 7 { errors.append("第\(weekNumber)周缺逐餐克数核对参考") }
            if derivedDays.map(\.dinner) != weekCards { errors.append("第\(weekNumber)周逐餐采购参考未引用真实晚餐卡") }
            if derivedDays.contains(where: { $0.breakfast.ingredients.isEmpty || $0.dinner.ingredients.isEmpty }) {
                errors.append("第\(weekNumber)周逐餐采购参考缺早餐或晚餐食材")
            }
            let dinnerText = weekCards.flatMap(\.ingredients).joined(separator: " ")
            for (recipeKeyword, shoppingKeywords) in keyProteinCoverage where dinnerText.contains(recipeKeyword) && !containsAny(text, shoppingKeywords) {
                errors.append("第\(weekNumber)周采购未覆盖晚餐关键蛋白：\(recipeKeyword)")
            }
        }
        return errors
    }

    private static let keyProteinCoverage: [(String, [String])] = [
        ("鸡腿", ["鸡腿"]), ("鸡胸", ["鸡胸"]), ("里脊", ["里脊"]), ("肉末", ["肉末"]),
        ("虾仁", ["虾仁"]), ("鱼片", ["鱼片", "巴沙鱼"]), ("巴沙鱼", ["巴沙鱼", "鱼片"]),
        ("牛肉", ["牛肉", "肥牛"]), ("肥牛", ["肥牛", "牛肉"]), ("北豆腐", ["北豆腐"])
    ]

    private static func containsAny(_ text: String, _ terms: [String]) -> Bool { terms.contains { text.contains($0) } }

    private static func eggCount(in text: String) -> Int {
        guard let range = text.range(of: #"鸡蛋\s*(\d+)\s*个"#, options: .regularExpression) else { return 0 }
        let fragment = String(text[range])
        return Int(fragment.filter(\.isNumber)) ?? 0
    }
}
