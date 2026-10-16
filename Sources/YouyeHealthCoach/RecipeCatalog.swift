import Foundation

/// 完整 56 天菜单。日期排程只引用这一份目录，避免首页和“吃什么”页出现不同的菜谱。
public enum RecipeCatalog {
    public static let all56: [MealCard] =
        WeekOneRecipeCatalog.cards
        + WeekTwoRecipeCatalog.cards
        + WeekThreeRecipeCatalog.cards
        + WeekFourRecipeCatalog.cards
        + WeekFiveRecipeCatalog.cards
        + WeekSixRecipeCatalog.cards
        + WeekSevenRecipeCatalog.cards
        + WeekEightRecipeCatalog.cards
}

/// The same execution contract applies to catalog recipes and an owner-confirmed
/// same-day replacement. Keeping it here prevents a hand-entered card from
/// bypassing the 20-minute, timing, or single-kitchen safety rules.
public enum MealRecipeCardAudit {
    public static func validationErrors(for card: MealCard, titlePrefix: String = "") -> [String] {
        let name = titlePrefix.isEmpty ? "" : "\(titlePrefix)："
        var errors: [String] = []
        if card.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { errors.append("\(name)缺餐卡名称") }
        if card.ingredients.isEmpty || !card.ingredients.allSatisfy({ $0.range(of: #"\d+(?:\.\d+)?\s*(?:g|克|ml|毫升)"#, options: .regularExpression) != nil }) { errors.append("\(name)每项食材都必须含克数或液体毫升") }
        if card.thawAndPortion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { errors.append("\(name)缺前置解冻或分装说明") }
        // Audit the strings that are actually rendered, rather than the legacy persisted
        // wording.  In particular, a generic historical “锅” is rendered as the one
        // induction pot, and the executable UI must keep the same minute-by-minute contract.
        let visibleSteps = card.visibleTimedSteps
        if visibleSteps.count < 4 || !visibleSteps.allSatisfy({ $0.range(of: #"\b\d{1,2}:\d{2}\b"#, options: .regularExpression) != nil }) { errors.append("\(name)每步都必须是分钟级步骤") }
        let timingText = visibleSteps.joined(separator: "\n")
        let visibleStartMinutes = visibleSteps.compactMap(\.firstClockMinute)
        if visibleStartMinutes.count != visibleSteps.count {
            errors.append("\(name)分钟步骤缺可解析的起始时间")
        } else if visibleStartMinutes.first != 0 {
            errors.append("\(name)分钟步骤必须从 0:00 开始")
        } else if zip(visibleStartMinutes, visibleStartMinutes.dropFirst()).contains(where: { $0 > $1 }) {
            errors.append("\(name)分钟步骤不能倒序")
        }
        if card.thawAndPortion.contains("鸡蛋使用前清洗") || card.thawAndPortion.contains("鸡蛋洗净") {
            errors.append("\(name)鸡蛋无需在使用前清洗；请改为保持蛋壳清洁、打蛋后洗手")
        }
        let vagueTimingTokens = ["按包装", "包装时间", "煮至包装", "看情况", "视情况", "适量", "少许", "大约", "分钟左右"]
        if vagueTimingTokens.contains(where: { timingText.contains($0) }) || timingText.range(of: #"约\s*\d+\s*分钟"#, options: .regularExpression) != nil {
            errors.append("\(name)分钟步骤不能使用含糊时长；请限定食材规格并写出确切分钟")
        }
        // A clock duration by itself is not an adequate safety finish line for a raw animal
        // protein: pan heat, thickness and starting temperature vary. `foodSafetyFinish` is
        // rendered as its own immutable card field, so old stored cards cannot lose the endpoint
        // simply because their older timed-step wording only carried the clock duration.
        if card.foodSafetyFinish == nil,
           ["鸡胸", "鸡腿", "鸡肉", "牛肉", "肥牛", "里脊", "瘦肉", "肉末", "鱼片", "鱼柳", "巴沙鱼", "虾仁", "鸡蛋"].contains(where: { token in card.ingredients.contains(where: { $0.contains(token) }) }) {
            errors.append("\(name)含生鲜动物蛋白但缺可显示的熟度终点")
        }
        let executionText = card.thawAndPortion + "\n" + timingText
        if executionText.contains("另一锅") || executionText.contains("另一个锅") || executionText.contains("第二口锅") { errors.append("\(name)只能使用一个电饭锅和一个电磁炉锅，不能要求第二口锅") }
        let requiresHeating = ["加热", "蒸", "煮", "炒", "煎", "烧开", "焯"].contains { executionText.contains($0) }
        let namesAvailableAppliance = executionText.contains("电饭锅") || executionText.contains("电磁炉锅") || executionText.contains("微波")
        if requiresHeating && !namesAvailableAppliance { errors.append("\(name)缺本餐使用设备说明") }
        if !card.portionsAndStorage.contains("做两份") && !card.portionsAndStorage.contains("做 2 份") && !card.portionsAndStorage.contains("做 1 份") { errors.append("\(name)缺份数/饭盒说明") }
        let hasSafeReheat = card.portionsAndStorage.contains("加热") || card.portionsAndStorage.contains("热透") || card.portionsAndStorage.contains("煮热")
        let hasSafeColdChain = card.portionsAndStorage.contains("冷食需全程冷藏") || card.portionsAndStorage.contains("全程冷藏") || card.portionsAndStorage.contains("冷藏并在午前")
        if !card.portionsAndStorage.contains("2 小时内冷藏") || (!hasSafeReheat && !hasSafeColdChain) { errors.append("\(name)缺安全冷藏、复热或冷食冷链规则") }
        guard let totalMinutes = card.portionsAndStorage.firstMatch(of: #"总操作\s*(\d+)\s*分钟"#).flatMap({ Int($0) }) else { errors.append("\(name)缺总操作分钟"); return errors }
        if totalMinutes > 20 { errors.append("\(name)总操作超过 20 分钟") }
        // A final clock label is not enough on its own: "19:00 再煮 4 分钟" ends at
        // 23:00 even if an author accidentally omitted a later timestamp. Combine the visible
        // clock endpoints with explicit per-step durations so the 20-minute promise cannot be
        // bypassed by a deceptively early last label.
        let timedStepEnd = visibleSteps.maximumDeclaredStepEndMinute
        if timedStepEnd == nil { errors.append("\(name)分钟步骤缺可解析的时间点") }
        else if let timedStepEnd, timedStepEnd > totalMinutes { errors.append("\(name)步骤结束于 \(timedStepEnd) 分钟，超过声明的总操作 \(totalMinutes) 分钟") }
        return errors
    }
}

public extension MealCard {
    /// Keep the equipment boundary visible on every card instead of making the person infer what
    /// a generic “锅” means. A card may legitimately be no-cook, or need only one of the two
    /// appliances; neither case should pretend that an extra appliance is available.
    var kitchenSetup: String {
        let usesRiceCooker = requiresRiceCooker
        let usesMicrowave = executionText.contains("微波")
        let usesInductionPot = requiresInductionPot

        switch (usesRiceCooker, usesInductionPot) {
        case (true, true): return "本餐使用：1 个电饭锅 + 1 个电磁炉锅；不需要第二口锅。"
        case (true, false): return "本餐使用：电饭锅；不需要电磁炉锅或第二口锅。"
        case (false, true): return "本餐使用：1 个电磁炉锅；不需要电饭锅或第二口锅。"
        case (false, false) where usesMicrowave: return "本餐使用：午间微波炉复热；不增加家中锅具。"
        case (false, false): return "本餐不需加热设备；只用现有餐具完成，不需要额外锅具。"
        }
    }

    /// Requirement flags deliberately come from the recipe instructions, not the friendly
    /// `kitchenSetup` sentence. That sentence also says which appliances are *not* needed.
    var requiresRiceCooker: Bool {
        executionText.contains("电饭锅")
    }

    var requiresInductionPot: Bool {
        let textWithoutRiceCooker = executionText.replacingOccurrences(of: "电饭锅", with: "")
        return textWithoutRiceCooker.contains("电磁炉锅") || textWithoutRiceCooker.contains("同一个电磁炉锅") || textWithoutRiceCooker.contains("锅")
    }

    private var executionText: String {
        thawAndPortion + "\n" + timedSteps.joined(separator: "\n")
    }
}

/// The fixed MVP menu is authored only for the owner's stated two-appliance setup. Profile text
/// must never silently rewrite a recipe; it can only show a clear boundary leading to the
/// explicit, owner-confirmed same-day replacement flow.
public enum KitchenCompatibility {
    public static let supportedSetupDescription = "电饭锅 + 一个电磁炉锅"

    public static func notice(for meal: MealCard, profileKitchenSetup: String?) -> String? {
        guard let raw = profileKitchenSetup?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        let normalized = raw.lowercased().replacingOccurrences(of: " ", with: "")
        let hasRiceCooker = normalized.contains("电饭锅") || normalized.contains("电饭煲")
        let hasInduction = normalized.contains("电磁炉") || normalized.contains("电磁锅")
        let requiresRiceCooker = meal.requiresRiceCooker
        let requiresInduction = meal.requiresInductionPot
        guard (requiresRiceCooker && !hasRiceCooker) || (requiresInduction && !hasInduction) else { return nil }
        return "你记录的厨房设备是“\(raw)”，与这张卡的“\(meal.kitchenSetup)”不匹配。不要自行延长时间或改用未确认设备；请先在“吃什么”拍食材并确认文字与克数，再重排当天未完成餐次。"
    }
}

public enum WeekOneRecipeCatalog {
    public static let cards: [MealCard] = [
        MealCard(title: "周一｜黑椒鸡腿西兰花饭", ingredients: ["去骨鸡腿肉片 300g", "西兰花 500g", "熟米饭 360g（180g×2）", "油 8g", "生抽 8g", "黑胡椒 1g"], thawAndPortion: "周日将鸡腿分装 300g；前一晚从冷冻移冷藏 8–12 小时。熟饭 180g×2 盒冷冻，前一晚移冷藏。", timedSteps: ["0:00 电饭锅加热两盒饭；西兰花掰小朵。", "1:00 电磁炉锅加油 8g，鸡腿铺开炒 4 分钟，盛出。", "5:00 西兰花加水 60ml，盖盖 5 分钟。", "10:00 鸡腿回锅，加生抽和黑胡椒，翻 2 分钟。", "12:00–15:00 菜饭均分两盒，今晚一盒、明午一盒。"], portionsAndStorage: "做两份；明午盒摊平，2 小时内冷藏。携带用保温袋+冰袋；中午加热至中心冒热气，一次吃完。总操作 15 分钟。", substitutions: "鸡腿可换鸡胸 300g；西兰花可换冷冻花菜 500g，水 70ml、盖 5 分钟。"),
        MealCard(title: "周二｜番茄豆腐鸡蛋饭", ingredients: ["北豆腐 500g", "鸡蛋 2 个（约 100g）", "番茄 500g", "熟米饭 360g（180g×2）", "油 7g", "生抽 5g"], thawAndPortion: "豆腐冷藏保存，不冷冻；番茄洗好擦干。熟饭 180g×2 前一晚移冷藏。鸡蛋保持蛋壳清洁，打蛋后洗手。", timedSteps: ["0:00 电饭锅加热两盒饭；番茄切块、豆腐切 2cm 块、鸡蛋打散。", "1:00 锅加油 7g，鸡蛋炒 90 秒，盛出。", "3:00 番茄加水 30ml，盖盖 4 分钟。", "7:00 下豆腐和生抽，轻推 3 分钟。", "10:00 鸡蛋回锅 1 分钟。", "11:00–15:00 分两盒，明午盒立即摊平冷藏。"], portionsAndStorage: "做两份；第二盒 2 小时内冷藏，次日一次加热到全盒冒热气。豆腐菜不常温放置超过 2 小时。总操作 15 分钟。", substitutions: "无番茄换菌菇 400g+水 40ml；无豆腐换鸡蛋 4 个（约 200g）+青菜 300g。"),
        MealCard(title: "周三｜蒜香鸡胸卷心菜饭", ingredients: ["鸡胸肉片 300g", "卷心菜 500g", "熟米饭 360g（180g×2）", "油 8g", "蒜 5g", "生抽 8g"], thawAndPortion: "鸡胸 300g 前一晚由冷冻移冷藏；卷心菜提前洗净沥干。熟饭 180g×2 移冷藏。", timedSteps: ["0:00 电饭锅加热饭；卷心菜切细。", "1:00 锅加油 8g、蒜 5g，鸡胸炒 4 分钟，盛出。", "5:00 卷心菜加水 50ml，盖盖 5 分钟。", "10:00 鸡胸回锅，加生抽翻 2 分钟至全熟。", "12:00–15:00 均分两盒，标注日期。"], portionsAndStorage: "做两份；明午盒 2 小时内冷藏，保温袋+冰袋通勤；中午彻底加热一次。总操作 15 分钟。", substitutions: "鸡胸可换去皮鸡腿 300g；卷心菜可换娃娃菜 500g。"),
        MealCard(title: "周四｜孜然里脊彩椒红薯", ingredients: ["里脊肉丝 280g", "彩椒 200g", "洋葱 200g", "熟红薯 400g（200g×2）", "油 7g", "生抽 8g", "孜然 1g"], thawAndPortion: "里脊 280g 前一晚移冷藏；熟红薯 200g×2 冷藏不超过 24 小时。彩椒洋葱洗净擦干。", timedSteps: ["0:00 电饭锅蒸热红薯；彩椒洋葱切丝。", "1:00 锅加油 7g，里脊炒 4 分钟至变色，盛出。", "5:00 彩椒洋葱加水 30ml，盖盖 4 分钟。", "9:00 肉丝回锅，加生抽和孜然，翻 2 分钟。", "11:00–15:00 红薯与肉菜分两盒；蔬菜放凉后冷藏。"], portionsAndStorage: "做两份；红薯和肉菜分格，第二份 2 小时内冷藏；次日肉菜彻底加热，红薯热透。总操作 15 分钟。", substitutions: "彩椒可换西葫芦 400g；红薯可换熟米饭 360g。"),
        MealCard(title: "周五｜肉末豆腐青菜饭", ingredients: ["瘦肉末 200g", "北豆腐 500g", "青菜 500g", "熟米饭 360g（180g×2）", "油 7g", "生抽 8g", "蒜 5g"], thawAndPortion: "肉末 200g 分装，前一晚移冷藏；豆腐当天拆封沥水。熟饭 180g×2 前一晚移冷藏。", timedSteps: ["0:00 电饭锅加热饭；豆腐切块、青菜洗净。", "1:00 锅加油 7g、蒜 5g，肉末炒 4 分钟至无粉红。", "5:00 豆腐加水 50ml 和生抽，盖盖 4 分钟。", "9:00 下青菜翻炒 3 分钟。", "12:00–15:00 分两盒，第二盒摊平冷藏。"], portionsAndStorage: "做两份；肉末必须完全熟透，第二份 2 小时内冷藏，次日一次加热至冒热气。总操作 15 分钟。", substitutions: "肉末可换鸡胸肉末 220g；青菜可换冷冻菠菜 400g。"),
        MealCard(title: "周六｜黑椒鱼片花菜饭", ingredients: ["冷冻鱼片 320g", "花菜 500g", "熟米饭 360g（180g×2）", "油 7g", "生抽 6g", "黑胡椒 1g"], thawAndPortion: "鱼片前一晚移冷藏解冻并放在接液盒内；熟饭 180g×2 前一晚移冷藏。花菜掰小朵。", timedSteps: ["0:00 电饭锅加热饭；鱼片用厨房纸吸干。", "1:00 锅加油 7g，鱼片每面煎 2 分钟，盛出。", "5:00 花菜加水 60ml，盖盖 5 分钟。", "10:00 鱼片回锅，加生抽黑胡椒，轻翻 1 分钟。", "11:00–15:00 鱼片与花菜均分两盒，检查无生心。"], portionsAndStorage: "做两份；鱼片熟透后第二盒 2 小时内冷藏，次日彻底加热一次。鱼片不在室温久放。总操作 15 分钟。", substitutions: "鱼片可换虾仁 300g（炒 3 分钟）；花菜可换西兰花 500g。"),
        MealCard(title: "周日｜咖喱鸡肉胡萝卜豌豆饭", ingredients: ["去皮鸡腿肉片 300g", "冷冻胡萝卜豌豆 500g", "熟米饭 360g（180g×2）", "油 6g", "咖喱粉 2g", "生抽 6g", "水 60ml"], thawAndPortion: "鸡腿 300g 前一晚移冷藏；冷冻蔬菜无需解冻。熟饭 180g×2 前一晚移冷藏。", timedSteps: ["0:00 电饭锅加热饭；备好咖喱粉、生抽和水。", "1:00 锅加油 6g，鸡腿炒 4 分钟至变色，盛出。", "5:00 冷冻蔬菜加水 60ml，盖盖 5 分钟。", "10:00 鸡肉回锅，加咖喱粉、生抽，翻 2 分钟至全熟。", "12:00–15:00 均分两盒，明午盒摊平冷藏。"], portionsAndStorage: "做两份；第二份 2 小时内冷藏，次日彻底加热至中心冒热气，一次吃完。总操作 15 分钟。", substitutions: "鸡腿可换鸡胸 300g；冷冻蔬菜可换卷心菜 500g，水 40ml。")
    ]

    public static func validate() -> [String] {
        validate(cards)
    }

    public static func validate(_ cards: [MealCard]) -> [String] {
        cards.flatMap { card in
            var errors = MealRecipeCardAudit.validationErrors(for: card, titlePrefix: card.title)
            if !card.thawAndPortion.contains("前一晚") && !card.thawAndPortion.contains("前一周") && !card.thawAndPortion.contains("周日") && !card.thawAndPortion.contains("前夜") {
                errors.append("\(card.title)：缺前置说明")
            }
            return errors
        }
    }
}

extension String {
    func firstMatch(of pattern: String) -> String? {
        guard let range = range(of: pattern, options: .regularExpression) else { return nil }
        let text = String(self[range])
        return text.components(separatedBy: CharacterSet.decimalDigits.inverted).first(where: { !$0.isEmpty })
    }

    /// Returns the first visible recipe-clock token as elapsed whole minutes.  Recipe cards use
    /// a human-readable `m:ss` timeline, so the audit fails closed on malformed seconds instead
    /// of treating a corrupted or out-of-order step as executable.
    var firstClockMinute: Int? {
        let pattern = #"\b(\d{1,2}):(\d{2})\b"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(startIndex..., in: self)
        guard let match = expression.firstMatch(in: self, range: range),
              match.numberOfRanges == 3,
              let minuteRange = Range(match.range(at: 1), in: self),
              let secondRange = Range(match.range(at: 2), in: self),
              let minute = Int(self[minuteRange]),
              let second = Int(self[secondRange]), second < 60 else {
            return nil
        }
        return minute + (second > 0 ? 1 : 0)
    }
}

extension Array where Element == String {
    /// Captures every visible mm:ss token, including the end of a range such as 12:00–15:00.
    /// This makes “总操作 15 分钟” a checkable execution contract rather than a decorative label.
    var maximumClockMinute: Int? {
        let pattern = #"\b(\d{1,2}):(\d{2})\b"#
        var maximum: Int?
        for step in self {
            guard let expression = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(step.startIndex..., in: step)
            for result in expression.matches(in: step, range: range) {
                guard result.numberOfRanges == 3,
                      let minuteRange = Range(result.range(at: 1), in: step),
                      let secondRange = Range(result.range(at: 2), in: step),
                      let minute = Int(step[minuteRange]),
                      let second = Int(step[secondRange]),
                      second < 60 else { continue }
                let value = minute + (second > 0 ? 1 : 0)
                maximum = Swift.max(maximum ?? value, value)
            }
        }
        return maximum
    }

    /// The largest known end point across all recipe steps. A step may expose its finish as a
    /// clock range (`12:00–15:00`) or as an explicit duration after its opening clock
    /// (`18:00 盖盖煮 4 分钟`). Both are execution commitments and must fit the card's stated
    /// total. Seconds round upward: a 90-second egg step cannot be treated as only one minute.
    var maximumDeclaredStepEndMinute: Int? {
        let clockPattern = #"\b(\d{1,2}):(\d{2})\b"#
        let durationPattern = #"(\d+(?:\.\d+)?)\s*(分钟|分|秒)"#
        guard let clockExpression = try? NSRegularExpression(pattern: clockPattern),
              let durationExpression = try? NSRegularExpression(pattern: durationPattern) else {
            return maximumClockMinute
        }

        var maximum = maximumClockMinute
        for step in self {
            let range = NSRange(step.startIndex..., in: step)
            let clocks = clockExpression.matches(in: step, range: range)
            guard let firstClock = clocks.first,
                  firstClock.numberOfRanges == 3,
                  let minuteRange = Range(firstClock.range(at: 1), in: step),
                  let secondRange = Range(firstClock.range(at: 2), in: step),
                  let startMinute = Int(step[minuteRange]),
                  let startSecond = Int(step[secondRange]), startSecond < 60 else { continue }

            let stepStart = startMinute + (startSecond > 0 ? 1 : 0)
            for durationMatch in durationExpression.matches(in: step, range: range) {
                guard durationMatch.numberOfRanges == 3,
                      let valueRange = Range(durationMatch.range(at: 1), in: step),
                      let unitRange = Range(durationMatch.range(at: 2), in: step),
                      let value = Double(step[valueRange]), value.isFinite, value >= 0 else { continue }
                let unit = String(step[unitRange])
                let durationMinutes: Int
                switch unit {
                case "秒": durationMinutes = Int((value / 60).rounded(.up))
                default: durationMinutes = Int(value.rounded(.up))
                }
                maximum = Swift.max(maximum ?? 0, stepStart + durationMinutes)
            }
        }
        return maximum
    }
}
