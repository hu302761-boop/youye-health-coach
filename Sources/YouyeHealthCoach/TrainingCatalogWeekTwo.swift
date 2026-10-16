import Foundation

public enum WeekTwoTrainingCatalog {
    public static let cards: [TrainingCard] = [
        TrainingCard(dayIndex: 8, title: "A 核心控制进阶", standardVersion: "死虫每侧 8 次；侧平板屈膝每侧 25 秒；反向卷腹 8 次，做 2 轮。", minimumVersion: "死虫每侧 6 次→侧卧呼气每侧 5 次，做 1 轮。", regression: "死虫改短杠杆；侧平板改侧卧呼气。", stopConditions: "腰痛、屏息、髋前侧锐痛立即停止。", followAlongInstruction: "跟练视频只做无跳跃版本，先完成动作范围再考虑增加。", cameraPrompts: ["腰背不拱起", "骨盆稳定", "呼气时收肋"], maxMinutes: 15),
        TrainingCard(dayIndex: 9, title: "B 墙面体态", standardVersion: "墙面滑手 12 次；鸟狗每侧 8 次；墙面俯卧撑 10 次；下巴内收 10 次，做 2 轮。", minimumVersion: "墙面滑手 8 次→鸟狗每侧 6 次→下巴内收 5 次，做 1 轮。", regression: "墙面俯卧撑离墙更近；鸟狗只抬手。", stopConditions: "肩关节锐痛、手麻或头晕立即停止。", followAlongInstruction: "跟练保持慢速，不追视频次数。", cameraPrompts: ["头颈中立", "肩胛不耸肩", "肋骨不外翻"], maxMinutes: 15),
        TrainingCard(dayIndex: 10, title: "A 核心 + 臀腿", standardVersion: "臀桥 15 次；死虫每侧 8 次；坐站 10 次；侧平板每侧 20 秒，做 2 轮。", minimumVersion: "臀桥 12 次→坐站 8 次→死虫每侧 6 次，做 1 轮。", regression: "坐站使用更高的椅子；侧平板改侧卧呼气。", stopConditions: "膝痛、腰痛或呼吸紊乱立即停止。", followAlongInstruction: "坐站控制下落，不做跳蹲。", cameraPrompts: ["膝盖对准脚尖", "臀部向后坐", "腰背保持自然"], maxMinutes: 18),
        TrainingCard(dayIndex: 11, title: "恢复轻走 + 胸髋活动", standardVersion: "轻走 30 分钟；猫牛 8 次；胸椎旋转每侧 6 次；髋屈肌拉伸每侧 30 秒。", minimumVersion: "轻走 15 分钟→呼吸 5 次→胸椎旋转每侧 4 次。", regression: "只做平地轻走和呼吸；不拉到疼痛。", stopConditions: "胸痛、异常气短、头晕或疼痛加重立即停止。", followAlongInstruction: "恢复日不跟高强度课程，以能说完整句子为准。", cameraPrompts: ["步幅自然", "肩颈放松", "身体不向一侧塌"], maxMinutes: 40),
        TrainingCard(dayIndex: 12, title: "B 体态稳定", standardVersion: "墙面滑手 10 次；鸟狗每侧 8 次；桌沿平板 25 秒；臀桥 15 次，做 3 轮。", minimumVersion: "墙面滑手 8 次→鸟狗每侧 6 次→桌沿支撑 15 秒，做 1 轮。", regression: "桌沿支撑改墙面支撑；鸟狗改四点跪姿抬手。", stopConditions: "腰塌、肩痛或无法呼吸立即停止。", followAlongInstruction: "每轮之间休息 45–60 秒，不追求连续跟完。", cameraPrompts: ["肩髋大致成线", "骨盆不旋转", "肘部不过伸"], maxMinutes: 20),
        TrainingCard(dayIndex: 13, title: "游泳/骑行耐力", standardVersion: "游泳 50m+休息 30–45 秒×8，或共享单车 45 分钟；结束后死虫每侧 6 次×2 轮。", minimumVersion: "轻走 20 分钟→死虫每侧 6 次→呼吸 5 次。", regression: "取消间歇，改连续轻松游或轻走；不做核心加餐。", stopConditions: "胸痛、异常气短、头晕、关节痛立即停止。", followAlongInstruction: "不追配速，保持可说短句；视频只作陆上动作示范。", cameraPrompts: ["全身入镜", "呼吸连续", "动作不代偿"], maxMinutes: 60),
        TrainingCard(dayIndex: 14, title: "恢复 + 周复盘", standardVersion: "上背/髋部拉伸 20 分钟；90/90 呼吸 5 次；臀桥 12 次，做 2 轮；记录反馈。", minimumVersion: "呼吸 5 次→婴儿式呼吸 5 次→记录睡眠/疼痛。", regression: "只做平躺呼吸；不因周复盘加练或减餐。", stopConditions: "拉伸锐痛、麻木或症状加重立即停止。", followAlongInstruction: "恢复日只做温和版本，周复盘看趋势而不是单日体重。", cameraPrompts: ["肩颈放松", "呼吸不屏息", "幅度小而可控"], maxMinutes: 25)
    ]

    public static func validate() -> [String] {
        cards.flatMap { card in
            var errors: [String] = []
            if card.minimumVersion.isEmpty || card.standardVersion.isEmpty || card.regression.isEmpty || card.stopConditions.isEmpty { errors.append("\(card.title)：缺训练安全字段") }
            if card.cameraPrompts.count < 2 { errors.append("\(card.title)：摄像头提示不足") }
            if card.maxMinutes > 60 { errors.append("\(card.title)：时间超限") }
            return errors
        }
    }
}

public enum TrainingCatalog {
    public static let firstFourteenDays = WeekOneTrainingCatalog.cards + WeekTwoTrainingCatalog.cards

    /// 训练页与今天页均只通过本地日期对应的计划日读取训练卡；超出 56 天不循环伪造。
    public static func card(for date: Date, calendar: Calendar = .current) -> TrainingCard? {
        guard let dayIndex = PlanSchedule.dayIndex(for: date, calendar: calendar) else { return nil }
        return all56.first { $0.dayIndex == dayIndex }
    }
}
