import Foundation

private func trainingCard(_ day: Int, _ title: String, _ standard: String, _ minimum: String, _ regression: String, _ stop: String, _ prompts: [String], _ minutes: Int) -> TrainingCard {
    TrainingCard(dayIndex: day, title: title, standardVersion: standard, minimumVersion: minimum, regression: regression, stopConditions: stop, followAlongInstruction: "跟练只做到自己能保持呼吸的版本；不追视频速度和次数。", cameraPrompts: prompts, maxMinutes: minutes)
}

public enum WeeksThreeFourTrainingCatalog {
    public static let cards: [TrainingCard] = [
        trainingCard(15, "A 死虫稳定", "死虫每侧 8 次；臀桥 15 次；侧平板每侧 25 秒，做 3 轮。", "死虫每侧 6 次→臀桥 12 次，做 1 轮。", "死虫短杠杆；侧平板改侧卧呼气。", "腰痛、髋前侧锐痛、屏息立即停止。", ["腰背不拱起", "骨盆不前倾"], 18),
        trainingCard(16, "B 肩胛体态", "墙面滑手 12 次；鸟狗每侧 8 次；墙面俯卧撑 10 次，做 2 轮。", "墙面滑手 8 次→鸟狗每侧 6 次，做 1 轮。", "墙面俯卧撑离墙更近；鸟狗只抬手。", "肩痛、手麻、眩晕立即停止。", ["肩膀远离耳朵", "头颈中立"], 15),
        trainingCard(17, "C 腰腹 + 坐站", "坐站 12 次；交替臀桥每侧 8 次；死虫每侧 8 次；桌沿平板 25 秒，做 2 轮。", "坐站 8 次→臀桥 10 次→死虫每侧 6 次，做 1 轮。", "椅子升高；桌沿平板改墙面支撑。", "膝痛、腰痛、无法呼吸立即停止。", ["膝盖对脚尖", "腰背自然"], 18),
        trainingCard(18, "恢复轻走", "轻走 30 分钟；胸椎旋转每侧 6 次；髋屈肌拉伸每侧 30 秒。", "轻走 15 分钟→呼吸 5 次。", "只做平地轻走，不拉到痛。", "胸痛、异常气短、头晕立即停止。", ["步幅自然", "肩颈放松"], 40),
        trainingCard(19, "A 腰腹小循环", "死虫每侧 8 次；反向卷腹 8 次；臀桥 15 次，做 3 轮。", "死虫每侧 6 次→臀桥 12 次，做 1 轮。", "反向卷腹改骨盆后卷；减小幅度。", "腰部疼痛、腿麻、屏息立即停止。", ["骨盆后卷", "动作慢于呼吸"], 18),
        trainingCard(20, "游泳/耐力骑", "游泳 50m+休息×8，或共享单车 45 分钟；结束后呼吸 5 次。", "轻走 20 分钟→呼吸 5 次。", "取消间歇，改轻松游/走。", "胸痛、异常气短、头晕、关节痛立即停止。", ["全身入镜", "呼吸连续"], 60),
        trainingCard(21, "恢复周复盘", "拉伸 20 分钟；呼吸 5 次；记录睡眠、疼痛和完成率。", "呼吸 5 次→婴儿式呼吸 5 次。", "只做平躺呼吸，不因复盘加练。", "拉伸锐痛、麻木或症状加重立即停止。", ["肩颈放松", "幅度可控"], 25),
        trainingCard(22, "A 长呼气核心", "90/90 呼吸 5 次；死虫每侧 8 次；侧平板每侧 25 秒；臀桥 15 次，做 2 轮。", "呼吸 5 次→死虫每侧 6 次，做 1 轮。", "侧平板改侧卧呼气；死虫短杠杆。", "腰痛、头晕、无法说短句立即停止。", ["呼气收肋", "腰背贴地"], 18),
        trainingCard(23, "B 胸椎髋部", "墙面滑手 12 次；猫牛 8 次；鸟狗每侧 8 次；髋屈肌拉伸每侧 30 秒，做 2 轮。", "墙面滑手 8 次→猫牛 6 次→鸟狗每侧 6 次。", "鸟狗只抬手；拉伸幅度减半。", "肩痛、腰痛或眩晕立即停止。", ["骨盆不旋转", "颈部放松"], 18),
        trainingCard(24, "C 全身低冲击", "坐站 12 次；桌沿俯卧撑 8 次；臀桥 15 次；鸟狗每侧 8 次，做 2 轮。", "坐站 8 次→墙面俯卧撑 6 次→臀桥 10 次。", "改墙面俯卧撑；坐站使用高椅。", "膝痛、肩痛、腰痛立即停止。", ["膝盖对脚尖", "肩胛稳定"], 20),
        trainingCard(25, "恢复骑行", "共享单车或步行 30 分钟，能完整说话；猫牛 8 次；呼吸 5 次。", "轻走 15 分钟→呼吸 5 次。", "只做轻走，取消骑行。", "胸痛、异常气短、头晕立即停止。", ["视线前方", "肩颈放松"], 40),
        trainingCard(26, "A 侧向稳定", "死虫每侧 8 次；站姿抗侧屈每侧 20 秒；臀桥 15 次，做 3 轮。", "死虫每侧 6 次→站姿抗侧屈每侧 15 秒。", "站姿抗侧屈改双手压大腿，幅度小。", "腰痛、侧腹锐痛或屏息立即停止。", ["躯干不侧倒", "呼吸连续"], 18),
        trainingCard(27, "游泳/骑行恢复", "轻松游 30–40 分钟或骑行 45 分钟；不做间歇；结束拉伸 10 分钟。", "轻走 20 分钟→拉伸 5 分钟。", "只做轻走与呼吸。", "胸痛、异常气短、头晕、关节痛立即停止。", ["全身入镜", "不追配速"], 60),
        trainingCard(28, "恢复 + 周复盘", "上背髋部拉伸 20 分钟；记录体重趋势、腰围、睡眠、皮肤和训练反馈。", "呼吸 5 次→记录状态。", "只记录，不因单日数据加练或减餐。", "拉伸出现锐痛或症状加重立即停止。", ["不屏息", "幅度小而可控"], 25)
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

public extension TrainingCatalog {
    static let firstFourWeeks = TrainingCatalog.firstFourteenDays + WeeksThreeFourTrainingCatalog.cards
}
