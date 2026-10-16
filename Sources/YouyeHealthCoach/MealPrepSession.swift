import Foundation

public struct MealPrepSessionStep: Identifiable, Equatable, Sendable {
    public let id: Int
    public let scheduledSecond: Int
    public let instruction: String

    public init(id: Int, scheduledSecond: Int, instruction: String) {
        self.id = id
        self.scheduledSecond = max(0, scheduledSecond)
        self.instruction = instruction
    }

    public var scheduledLabel: String {
        String(format: "%d:%02d", scheduledSecond / 60, scheduledSecond % 60)
    }
}

public struct MealPrepSessionPlan: Equatable, Sendable {
    public let title: String
    public let totalSeconds: Int
    public let steps: [MealPrepSessionStep]
    public let foodSafetyFinish: String?
    public let storageInstruction: String

    public init(meal: MealCard) {
        title = meal.displayTitle
        totalSeconds = min(20 * 60, max(60, Self.totalMinutes(in: meal.portionsAndStorage) * 60))
        steps = meal.visibleTimedSteps.enumerated().map { index, instruction in
            MealPrepSessionStep(
                id: index,
                scheduledSecond: Self.firstClockSeconds(in: instruction) ?? 0,
                instruction: instruction
            )
        }
        foodSafetyFinish = meal.foodSafetyFinish
        storageInstruction = meal.portionsAndStorage
    }

    public func timingMessage(for stepIndex: Int, elapsedSeconds: Int) -> String {
        guard steps.indices.contains(stepIndex) else { return "步骤已完成" }
        let delta = steps[stepIndex].scheduledSecond - max(0, elapsedSeconds)
        if delta > 0 { return "卡片时间还有 \(formatted(seconds: delta))；可先称量和摆好下一步食材。" }
        if delta >= -30 { return "现在进行这一步；以食材熟度和安全终点为准。" }
        return "比卡片时间晚 \(formatted(seconds: -delta))；不要为追时间开大火，按熟度完成。"
    }

    public func hardLimitMessage(elapsedSeconds: Int) -> String? {
        guard elapsedSeconds >= totalSeconds else { return nil }
        return "已到卡片 \(totalSeconds / 60) 分钟上限：先关火并检查熟度；不要继续叠加步骤。"
    }

    /// The app cannot supervise a hot pan while it is covered or the phone is locked. The
    /// recipe clock deliberately keeps running from wall-clock time, so returning to the app
    /// must make that boundary explicit instead of silently presenting a later timer value.
    public func returnFromBackgroundMessage(awaySeconds: Int, elapsedSeconds: Int) -> String? {
        let away = max(0, awaySeconds)
        guard away >= 15 else { return nil }
        let elapsed = max(0, elapsedSeconds)
        if elapsed >= totalSeconds {
            return "离开 App \(formatted(seconds: away)) 期间计时仍在继续，现在已到卡片上限。先关火、查看锅具和熟度；App 不能代替你看管炉火。"
        }
        return "离开 App \(formatted(seconds: away)) 期间计时仍在继续，已累计 \(formatted(seconds: elapsed))。先查看锅具和熟度；App 不能代替你看管炉火。"
    }

    private func formatted(seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private static func totalMinutes(in text: String) -> Int {
        guard let range = text.range(of: #"总操作\s*(\d+)\s*分钟"#, options: .regularExpression) else { return 20 }
        let match = String(text[range])
        let digits = match.filter(\.isNumber)
        return Int(digits) ?? 20
    }

    private static func firstClockSeconds(in text: String) -> Int? {
        guard let range = text.range(of: #"\b\d{1,2}:\d{2}\b"#, options: .regularExpression) else { return nil }
        let parts = text[range].split(separator: ":")
        guard parts.count == 2, let minutes = Int(parts[0]), let seconds = Int(parts[1]), (0...59).contains(seconds) else { return nil }
        return minutes * 60 + seconds
    }
}
