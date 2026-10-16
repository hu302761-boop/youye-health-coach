import Foundation

/// 早餐按 7 天循环；每张卡同样满足克数、设备、分钟步骤、保存与 20 分钟上限。
public enum BreakfastCatalog {
    public static let cards: [MealCard] = [
        DayOnePlan.fallbackBreakfast,
        MealCard(title: "早餐｜红薯豆浆鸡蛋", ingredients: ["红薯 200g", "无糖豆浆 300ml", "鸡蛋 2 个（约 100g）", "水 80ml"], thawAndPortion: "前夜红薯切 2cm 块，和鸡蛋放入电饭锅内胆加水 80ml，冷藏。做 1 份。", timedSteps: ["0:00 直接启动电饭锅蒸煮。", "0:30 豆浆倒入杯中。", "8:00 取出红薯和鸡蛋，剥蛋。", "9:00 配豆浆吃完。"], portionsAndStorage: "做 1 份；可前夜蒸好，2 小时内冷藏，次晨彻底加热一次后吃完。总操作 10 分钟。", substitutions: "红薯可换紫薯 200g；豆浆可换无糖酸奶 200g。"),
        MealCard(title: "早餐｜吐司鸡蛋番茄", ingredients: ["全麦吐司 70g（2 片）", "鸡蛋 2 个（约 100g）", "番茄 150g", "水 80ml"], thawAndPortion: "前夜番茄洗好；鸡蛋放入电饭锅蒸架。做 1 份，不做饭盒。", timedSteps: ["0:00 电饭锅加水 80ml，放鸡蛋启动蒸煮。", "0:30 吐司装盘。", "5:30 切番茄。", "7:00 剥蛋，组合吃完。"], portionsAndStorage: "做 1 份；切开的番茄不隔夜。鸡蛋如预先蒸好，2 小时内冷藏，3 天内彻底加热一次后吃完。总操作 8 分钟。", substitutions: "番茄可换小番茄 150g；吐司可换熟玉米 160g。"),
        MealCard(title: "早餐｜玉米豆腐橙子", ingredients: ["预煮玉米 160g", "嫩豆腐 150g", "橙子 150g", "水 80ml"], thawAndPortion: "前夜玉米冷藏；豆腐不拆封。做 1 份，不做饭盒。", timedSteps: ["0:00 玉米放电饭锅蒸架，加水 80ml 启动蒸煮。", "0:30 豆腐倒入碗中。", "4:00 剥橙子。", "6:00 玉米热透后一起吃。"], portionsAndStorage: "做 1 份；开封豆腐当天吃完。玉米如预热，2 小时内冷藏，次晨彻底加热一次后吃完。总操作 7 分钟。", substitutions: "橙子可换苹果 150g；玉米可换红薯 200g。"),
        MealCard(title: "早餐｜隔夜燕麦香蕉鸡蛋", ingredients: ["燕麦 40g", "无糖豆浆 250ml", "香蕉 60g", "鸡蛋 2 个（约 100g）"], thawAndPortion: "前夜燕麦和豆浆装带盖碗冷藏；鸡蛋可与晚餐用电饭锅同蒸好。做 1 份。", timedSteps: ["0:00 取出隔夜燕麦。", "0:30 切香蕉 60g。", "1:00 剥已用电饭锅蒸好的鸡蛋。", "2:00 燕麦配香蕉和鸡蛋吃完。"], portionsAndStorage: "做 1 份；隔夜燕麦 2 小时内冷藏且不超过 24 小时；鸡蛋 3 天内彻底加热一次后吃完。总操作 3 分钟。", substitutions: "香蕉可换猕猴桃 100g；豆浆可换无糖酸奶 200g。"),
        MealCard(title: "早餐｜小米粥鸡蛋黄瓜", ingredients: ["小米 35g", "鸡蛋 2 个（约 100g）", "黄瓜 150g", "水 500ml"], thawAndPortion: "前夜小米淘好加水 500ml，预约电饭锅；鸡蛋可提前蒸好。做 1 份。", timedSteps: ["0:00 取出已预约的小米粥。", "0:30 洗切黄瓜。", "2:00 剥鸡蛋。", "3:00 配粥吃完。"], portionsAndStorage: "做 1 份；粥不建议隔夜。鸡蛋如提前蒸好，2 小时内冷藏，3 天内彻底加热一次后吃完。总操作 4 分钟。", substitutions: "无预约功能则改燕麦 40g+豆浆 300ml；黄瓜可换番茄 150g。"),
        MealCard(title: "早餐｜金枪鱼番茄三明治", ingredients: ["全麦吐司 70g（2 片）", "清水金枪鱼 60g", "番茄 100g", "苹果 150g"], thawAndPortion: "前夜番茄洗好；金枪鱼开罐后当天用完。做 1 份。", timedSteps: ["0:00 番茄切片。", "2:00 吐司放金枪鱼和番茄组合。", "4:00 洗苹果。", "5:00 吃完或装盒带走。"], portionsAndStorage: "做 1 份；若带走，2 小时内冷藏并在午前吃完，不留隔夜。总操作 6 分钟。", substitutions: "金枪鱼可换北豆腐 120g；苹果可换橙子 150g。")
    ]

    public static func card(dayIndex: Int) -> MealCard { cards[(dayIndex - 1) % cards.count] }
}

/// 午餐默认吃前一晚按晚餐卡分出的第二盒；第 1 天使用独立应急自炊盒。
///
/// 不假定办公室有微波炉、冰箱或其他未确认设备。默认午餐在家用已有的一个电磁炉锅
/// 彻底复热；如实际午餐环境不同，必须由本人拍食材并确认重排，不能把隔夜含肉/蛋/豆腐
/// 便当擅自改为冷食或依赖未知设备。
public enum LunchCatalog {
    public static func card(dayIndex: Int) -> MealCard {
        guard dayIndex > 1, RecipeCatalog.all56.indices.contains(dayIndex - 2) else { return DayOnePlan.fallbackLunch }
        let previousDinner = RecipeCatalog.all56[dayIndex - 2]
        return MealCard(
            title: "午餐｜昨晚便当：\(previousDinner.displayTitle)",
            ingredients: previousDinner.ingredients,
            thawAndPortion: "前一晚按原晚餐卡做两份；本午餐盒是其中 1 份。默认中午在家：饭盒一直冷藏到开吃前。若当天不在家，不带这盒，先拍现有食材并确认重排。",
            timedSteps: ["0:00 从冰箱取出昨晚便当 1 盒；检查盒身标注日期。", "0:30 把便当倒入唯一的电磁炉锅，加水 40ml，盖盖中火加热。", "4:00 翻拌后再加热 1 分钟。", "5:00 中心冒热气后一次吃完；不回锅、不留剩饭。"],
            portionsAndStorage: "做 1 份（前一晚晚餐的第二盒）；熟餐须在前一晚 2 小时内冷藏。默认在家只用一个电磁炉锅热透，中心冒热气后一次吃完，不反复加热。办公室冰箱、微波炉或冷食条件均未确认，不能作为本卡默认步骤。总操作 5 分钟。",
            substitutions: "午间不在家或没有冷藏、复热条件时，不带隔夜熟饭；请拍现有食材并确认重排当天自炊午餐，不自动改餐或节食。"
        )
    }
}

/// 午餐不是另做一顿替代餐，而是前一晚第二饭盒。此审计确保每个计划日都明确
/// 写出在家复热、一次彻底复热及午间环境不匹配时的当日自炊重排退路。
public enum CommuterMealSafetyAudit {
    public static func validateLunches(forDays dayIndices: ClosedRange<Int> = 1...56) -> [String] {
        var errors: [String] = []
        for dayIndex in dayIndices {
            let lunch = LunchCatalog.card(dayIndex: dayIndex)
            let label = "第\(dayIndex)天午餐"
            let fieldText = lunch.thawAndPortion + "\n" + lunch.timedSteps.joined(separator: "\n") + "\n" + lunch.portionsAndStorage + "\n" + lunch.substitutions

            let recipeErrors = WeekOneRecipeCatalog.validate([lunch])
            if !recipeErrors.isEmpty {
                errors.append("\(label)未满足食谱执行契约：\(recipeErrors.joined(separator: "；"))")
            }
            if dayIndex > 1 {
                let priorDinner = RecipeCatalog.all56[dayIndex - 2]
                if lunch.ingredients != priorDinner.ingredients { errors.append("\(label)未承接前一晚第二饭盒食材") }
                if !lunch.title.contains(priorDinner.displayTitle) { errors.append("\(label)未标注承接的前晚餐食") }
            }
            for requirement in ["默认中午在家", "2 小时内冷藏", "中心冒热气", "一次吃完", "不反复加热", "电磁炉锅", "未确认"] {
                if !fieldText.contains(requirement) { errors.append("\(label)缺通勤安全提示：\(requirement)") }
            }
            if !lunch.substitutions.contains("午间不在家") || !lunch.substitutions.contains("确认重排") {
                errors.append("\(label)缺午间环境不匹配时的当天自炊重排退路")
            }
        }
        return errors
    }
}

/// One blocking audit for the complete execution menu. It deliberately checks the content that
/// becomes a real daily card, rather than trusting individual week files to be tested in
/// isolation. This is catalogue validation only: it never estimates nutrition or replaces a
/// person’s explicit same-day food confirmation.
public enum DailyMealCatalogAudit {
    public static func validate() -> [String] {
        var errors: [String] = []
        guard RecipeCatalog.all56.count == 56 else {
            return ["晚餐目录必须正好包含 56 天餐卡"]
        }
        guard BreakfastCatalog.cards.count == 7 else {
            return ["早餐循环必须正好包含 7 张餐卡"]
        }

        errors.append(contentsOf: WeekOneRecipeCatalog.validate(RecipeCatalog.all56))
        errors.append(contentsOf: WeekOneRecipeCatalog.validate(BreakfastCatalog.cards))
        errors.append(contentsOf: CommuterMealSafetyAudit.validateLunches())

        // Every visible slot must say how to adapt a mismatch. “无” is not sufficient for the
        // fixed catalogue because this product promises a practical self-cook fallback.
        for dayIndex in 1...56 {
            let cards: [(label: String, card: MealCard)] = [
                ("第\(dayIndex)天早餐", BreakfastCatalog.card(dayIndex: dayIndex)),
                ("第\(dayIndex)天午餐", LunchCatalog.card(dayIndex: dayIndex)),
                ("第\(dayIndex)天晚餐", RecipeCatalog.all56[dayIndex - 1])
            ]
            for item in cards {
                let substitution = item.card.substitutions.trimmingCharacters(in: .whitespacesAndNewlines)
                if substitution.isEmpty || substitution == "无" {
                    errors.append("\(item.label)缺缺食材时的营养等价替换")
                }
                // A no-cook breakfast or a carried lunch need not turn on both appliances. The
                // actual constraint is that no card can demand more than the one rice cooker and
                // one induction pot already available; `WeekOneRecipeCatalog.validate` above
                // blocks a second pot and the rendered meal card always states this boundary.
            }
        }
        return errors
    }
}
