import Foundation

public enum FollowAlongVideoSource: String, Codable, Sendable { case bilibili }

public extension FollowAlongVideoSource {
    var displayName: String {
        switch self { case .bilibili: "B站" }
    }

    /// A search URL is intentionally not a claimed course or a streaming integration. It lets the
    /// person search the explicitly shown keywords in B 站 without this app downloading, caching,
    /// embedding, or certifying any third-party video.
    func searchURL(for query: String) -> URL? {
        var components = URLComponents(string: "https://search.bilibili.com/all")
        components?.queryItems = [URLQueryItem(name: "keyword", value: query)]
        return components?.url
    }
}

public struct FollowAlongVideo: Codable, Sendable, Equatable {
    public let source: FollowAlongVideoSource
    public let searchQuery: String
    public let title: String?
    public let uploader: String?
    public let url: URL?
    public let checkedAt: Date?
    public let durationSeconds: Int?
    public let fitNote: String?
    public let status: String

    public init(source: FollowAlongVideoSource = .bilibili, searchQuery: String, title: String? = nil, uploader: String? = nil, url: URL? = nil, checkedAt: Date? = nil, durationSeconds: Int? = nil, fitNote: String? = nil, status: String = "待核验") {
        self.source = source; self.searchQuery = searchQuery; self.title = title; self.uploader = uploader; self.url = url; self.checkedAt = checkedAt; self.durationSeconds = durationSeconds; self.fitNote = fitNote; self.status = status
    }

    public var safeSearchURL: URL? { source.searchURL(for: searchQuery) }

    /// Only an explicit, timestamped candidate may use its direct URL. Default "待核验" cards
    /// never present a guessed deep link as a playable or approved course. Imported/local data
    /// is not trusted either: a damaged "已核验" record cannot turn this into a general external
    /// browser entry point or an in-App URL loaded next to camera coaching.
    public var verifiedCandidateURL: URL? {
        guard status == "已核验", checkedAt != nil, title != nil, uploader != nil,
              let durationSeconds, durationSeconds > 0,
              let fitNote, !fitNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let url, BilibiliFollowAlongNavigationPolicy.isAllowed(url) else { return nil }
        return url
    }

    /// Uses Bilibili's own inline player for the synchronized camera surface instead of loading
    /// the long mobile/detail page next to Vision. The BVID is derived only from the already
    /// verified direct lesson; if it cannot be parsed conservatively, callers keep the original
    /// verified page and report real-device playback as unverified.
    public var verifiedInlinePlayerURL: URL? {
        guard let verifiedURL = verifiedCandidateURL,
              let bvid = verifiedURL.pathComponents.first(where: { component in
                  component.hasPrefix("BV")
                      && (12...20).contains(component.count)
                      && component.allSatisfy { $0.isLetter || $0.isNumber }
              }) else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "player.bilibili.com"
        components.path = "/player.html"
        components.queryItems = [
            URLQueryItem(name: "bvid", value: bvid),
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "high_quality", value: "1"),
            URLQueryItem(name: "autoplay", value: "0")
        ]
        guard let playerURL = components.url,
              BilibiliFollowAlongNavigationPolicy.isAllowed(playerURL) else { return nil }
        return playerURL
    }

    public var durationDisplay: String? {
        guard let durationSeconds, durationSeconds > 0 else { return nil }
        return String(format: "%d:%02d", durationSeconds / 60, durationSeconds % 60)
    }
}

/// Timestamped Bilibili pages checked in the browser on 2026-08-17. Cards use a small,
/// conservative category mapping so the owner receives a direct lesson without searching.
/// Video media is never downloaded, bundled, or cached by this catalogue.
public enum CuratedTrainingVideoLibrary {
    private static let checkedAt = Date(timeIntervalSince1970: 1_786_945_800)

    public static func video(for title: String, standardVersion: String) -> FollowAlongVideo {
        if title.hasPrefix("C") || title.contains("全身") || title.contains("坐站") {
            return fullBody
        }
        if title.hasPrefix("B") || title.contains("体态") || title.contains("肩胛") || title.contains("胸椎髋部") {
            return posture
        }
        if standardVersion.contains("死虫") || standardVersion.contains("侧平板") || standardVersion.contains("臀桥") {
            return core
        }
        return recovery
    }

    public static let core = FollowAlongVideo(
        searchQuery: "核心激活 死虫 臀桥 侧平板 鸟狗 跟练",
        title: "核心激活训练-死虫 臀桥 蚌式 侧平板 鸟狗",
        uploader: "小爱aprang",
        url: URL(string: "https://www.bilibili.com/video/BV1mpTq6qE9G"),
        checkedAt: checkedAt,
        durationSeconds: 599,
        fitNote: "用于本卡的核心静态动作；始终以本卡最低版、退阶和停止条件为准。",
        status: "已核验"
    )

    public static let posture = FollowAlongVideo(
        searchQuery: "新手 徒手 直背 体态 跟练",
        title: "帕梅拉 - 10分钟 直背训练｜改善体态 打造性感美背 新手练背 徒手完成",
        uploader: "帕梅拉PamelaReif",
        url: URL(string: "https://www.bilibili.com/video/BV1ui4y1q7fQ"),
        checkedAt: checkedAt,
        durationSeconds: 636,
        fitNote: "用于零器械体态日；动作慢于视频也可以，锐痛、麻木或眩晕立即停止。",
        status: "已核验"
    )

    public static let fullBody = FollowAlongVideo(
        searchQuery: "初级 全身 无跳跃 无器械 跟练",
        title: "帕梅拉 - 10min 全身训练-初级友好|无跳跃+间隔|无器械 (Pamela Reif Official)",
        uploader: "帕梅拉PamelaReif",
        url: URL(string: "https://www.bilibili.com/video/BV1Ky4y1p7ZF"),
        checkedAt: checkedAt,
        durationSeconds: 622,
        fitNote: "用于低冲击全身日；保留休息间隔，不追加轮数、不跟做任何疼痛动作。",
        status: "已核验"
    )

    public static let recovery = FollowAlongVideo(
        searchQuery: "久坐 全身 拉伸 恢复 跟练",
        title: "20分钟久坐全身拉伸｜舒缓疼痛、改善体态、提升睡眠质量、解压【周六野Zoey】",
        uploader: "周六野Zoey",
        url: URL(string: "https://www.bilibili.com/video/BV1X142147nu"),
        checkedAt: checkedAt,
        durationSeconds: 1_389,
        fitNote: "仅在安全的静态环境做恢复拉伸；耐力日须先结束游泳、骑行或步行并固定手机。",
        status: "已核验"
    )
}

public struct TrainingCard: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let dayIndex: Int
    public let title: String
    public let standardVersion: String
    public let minimumVersion: String
    public let regression: String
    public let stopConditions: String
    public let followAlongInstruction: String
    public let cameraPrompts: [String]
    public let maxMinutes: Int
    public let video: FollowAlongVideo

    public init(id: UUID = UUID(), dayIndex: Int, title: String, standardVersion: String, minimumVersion: String, regression: String, stopConditions: String, followAlongInstruction: String, cameraPrompts: [String], maxMinutes: Int, video: FollowAlongVideo? = nil) {
        self.id = id; self.dayIndex = dayIndex; self.title = title; self.standardVersion = standardVersion; self.minimumVersion = minimumVersion; self.regression = regression; self.stopConditions = stopConditions; self.followAlongInstruction = followAlongInstruction; self.cameraPrompts = cameraPrompts; self.maxMinutes = maxMinutes
        self.video = video ?? CuratedTrainingVideoLibrary.video(for: title, standardVersion: standardVersion)
    }
}

/// 训练负荷只用于展示和审计周结构；不根据它自动加量，也不替代当天的疼痛、睡眠与疾病退阶。
public enum TrainingLoadKind: String, Codable, Sendable, Equatable {
    case coreOrPosture
    case endurance
    case recovery

    public var displayName: String {
        switch self {
        case .coreOrPosture: "腰腹/体态训练日"
        case .endurance: "轻耐力选择日"
        case .recovery: "恢复优先日"
        }
    }

    public var executionNote: String {
        switch self {
        case .coreOrPosture: "只做最低版也有效；动作质量和呼吸优先，不追次数。"
        case .endurance: "游泳或骑行任选其一；不追配速，无法舒服呼吸时改轻走。"
        case .recovery: "不加量、不补练；轻走、呼吸和拉伸都算完成。"
        }
    }
}

public extension TrainingCard {
    var loadKind: TrainingLoadKind {
        // “游泳/骑行恢复”仍是可选耐力日（可改轻走），优先按耐力归类；真正恢复日不靠它填补恢复配额。
        if title.contains("游泳") || title.contains("轻松游") || title.contains("游/") || title.contains("耐力") { return .endurance }
        if title.contains("恢复") { return .recovery }
        return .coreOrPosture
    }

    /// A card can be a recovery-priority day and still start with walking, cycling, or water.
    /// Keep that planning classification intact, but never treat the moving segment as suitable
    /// for a same-screen video and camera session.  This deliberately inspects the prescribed
    /// standard sequence rather than only the title: titles such as “恢复骑行” otherwise look
    /// like a stationary recovery card and can accidentally expose the wrong control.
    var containsMovingOrWaterSegment: Bool {
        let prescribedMovement = title + "\n" + standardVersion
        return ["游泳", "轻松游", "共享单车", "骑行", "轻走", "步行"].contains {
            prescribedMovement.contains($0)
        }
    }

    /// The camera is for stable, indoor, land-based movements only. It must never encourage a
    /// person to look at a screen while walking, cycling, or in/near water.
    var livePoseSafetyNote: String {
        if containsMovingOrWaterSegment {
            return "游泳、骑行和步行时不要开启取景或看手机。完成移动部分后，如要做本卡的呼吸、拉伸或腰腹静态动作，再把手机固定在稳定位置开启提醒。"
        }
        return "仅用于室内、静态、陆上动作。把手机固定在稳定位置后再开启；不要边走、骑车、游泳或手持手机边训练。"
    }

    var livePoseButtonTitle: String {
        containsMovingOrWaterSegment ? "完成移动后开启静态动作提醒" : "开启实时本机动作提醒"
    }

    /// Synchronized video + camera is only an execution option for a verified lesson and a
    /// stationary land-based card. Endurance cards remain text/video-only while moving or near
    /// water, even if they happen to reuse a verified recovery video.
    var supportsSynchronizedLiveFollowAlong: Bool {
        !containsMovingOrWaterSegment && video.verifiedCandidateURL != nil
    }

    /// Default only pre-fills the UI. The person chooses the actual activity type and duration
    /// before anything is written to Apple Health.
    var suggestedHealthWorkoutKind: ConfirmedHealthWorkoutKind {
        if title.contains("游") { return .swimming }
        if title.contains("骑") { return .cycling }
        if title.contains("走") { return .walking }
        if loadKind == .recovery { return .flexibility }
        return .coreTraining
    }
}

/// 防止目录更新后悄悄出现连续高负荷或缺失恢复周。这里只检查保守的结构底线：
/// 每 7 天至少一日恢复、没有连续 4 日腰腹/体态训练、每周至少一个可替换为轻走的耐力选择日。
public enum TrainingLoadAudit {
    public static func validate(_ cards: [TrainingCard]) -> [String] {
        var errors: [String] = []
        guard cards.count == 56 else { return ["训练负荷审计需要完整 56 天训练卡"] }

        let sorted = cards.sorted { $0.dayIndex < $1.dayIndex }
        guard sorted.map(\.dayIndex) == Array(1...56) else { return ["训练卡日序号必须连续覆盖第 1–56 天"] }

        for weekStart in stride(from: 0, to: sorted.count, by: 7) {
            let week = Array(sorted[weekStart..<(weekStart + 7)])
            let weekNumber = weekStart / 7 + 1
            if !week.contains(where: { $0.loadKind == .recovery }) { errors.append("第\(weekNumber)周缺恢复优先日") }
            if !week.contains(where: { $0.loadKind == .endurance }) { errors.append("第\(weekNumber)周缺可选游泳/骑行耐力日") }
            if week.contains(where: { $0.maxMinutes > 60 }) { errors.append("第\(weekNumber)周存在超过 60 分钟的训练卡") }
        }

        var coreOrPostureRun = 0
        for card in sorted {
            if card.loadKind == .coreOrPosture {
                coreOrPostureRun += 1
                if coreOrPostureRun >= 4 { errors.append("第\(card.dayIndex)天形成连续 4 天腰腹/体态训练") }
            } else {
                coreOrPostureRun = 0
            }
        }
        return errors
    }
}

/// Beyond weekly load, preserve a beginner-safe execution floor for every individual card.
/// This remains a catalogue audit only: it never auto-progresses a person based on the text.
public enum TrainingExecutionAudit {
    public static func validate(_ cards: [TrainingCard]) -> [String] {
        var errors: [String] = []
        guard cards.count == 56 else { return ["训练执行审计需要完整 56 天训练卡"] }

        for card in cards {
            let label = "第\(card.dayIndex)天 \(card.title)"
            if !card.minimumVersion.contains("→") { errors.append("\(label)最低版必须给出按顺序可执行的动作") }
            if card.minimumVersion.contains("跳") || card.standardVersion.contains("跳") { errors.append("\(label)不应在零基础腰腹/体态计划中加入跳跃要求") }
            let allText = card.standardVersion + card.minimumVersion + card.regression + card.stopConditions
            if ["哑铃", "杠铃", "壶铃", "弹力带", "跑步机"].contains(where: allText.contains) {
                errors.append("\(label)要求了当前计划未提供的器械")
            }
            if !card.stopConditions.contains("停止") && !card.stopConditions.contains("求助") { errors.append("\(label)停止条件未明确要求停止") }
            if card.video.verifiedCandidateURL == nil { errors.append("\(label)缺已核验的 B 站直达课程") }
            if let durationSeconds = card.video.durationSeconds,
               durationSeconds > card.maxMinutes * 60 {
                errors.append("\(label)直达课程时长超过本卡最长用时")
            }
            if card.livePoseSafetyNote.isEmpty { errors.append("\(label)缺实时取景安全边界") }
            if card.containsMovingOrWaterSegment && !card.livePoseSafetyNote.contains("不要开启取景") {
                errors.append("\(label)含移动/水中环节时必须禁止同步取景")
            }
            if card.containsMovingOrWaterSegment && card.supportsSynchronizedLiveFollowAlong {
                errors.append("\(label)含移动/水中环节时不得提供同屏视频和相机")
            }
        }
        return errors
    }
}

public enum WeekOneTrainingCatalog {
    public static let cards: [TrainingCard] = [
        TrainingCard(dayIndex: 1, title: "A 腰腹入门", standardVersion: "呼气收肋 5 次；死虫每侧 8 次；臀桥 12 次；桌沿平板 20 秒，做 2 轮。", minimumVersion: "90/90 呼吸 5 次→死虫每侧 6 次→臀桥 12 次，做 1 轮，约 6 分钟。", regression: "死虫改短杠杆；桌沿平板改站姿靠墙支撑。", stopConditions: "腰痛、头晕、腹压不适或无法正常呼吸立即停止。", followAlongInstruction: "跟练视频只跟前 10 分钟；动作暂停时以自己的呼吸和疼痛信号为准。", cameraPrompts: ["全身入镜", "腰背保持自然，不塌腰", "膝盖朝脚尖方向"], maxMinutes: 15),
        TrainingCard(dayIndex: 2, title: "B 体态激活", standardVersion: "下巴内收 10×5 秒；墙面滑手 10 次；鸟狗每侧 8 次；Y-T-W 各 6 次，做 2 轮。", minimumVersion: "下巴内收 5 次→墙面滑手 8 次→鸟狗每侧 6 次，做 1 轮。", regression: "鸟狗改四点跪姿抬手，不抬腿；墙面滑手减小幅度。", stopConditions: "肩颈锐痛、麻木或眩晕立即停止。", followAlongInstruction: "跟练时站在侧前方，保持慢速；不追求视频节奏。", cameraPrompts: ["头部与躯干保持一条线", "肩膀远离耳朵", "骨盆不要左右旋转"], maxMinutes: 12),
        TrainingCard(dayIndex: 3, title: "A 腰腹稳定", standardVersion: "死虫每侧 8 次；侧平板每侧 20 秒；反向卷腹 8 次，做 2 轮。", minimumVersion: "死虫每侧 6 次→侧平板改屈膝每侧 15 秒，做 1 轮。", regression: "侧平板改侧卧呼气；反向卷腹改骨盆后卷小幅度。", stopConditions: "腰部代偿、髋前侧锐痛或屏息立即停止。", followAlongInstruction: "侧面跟练，保持能说短句；不跟做跳跃动作。", cameraPrompts: ["腰部不离地", "骨盆不向前翻", "动作慢于口令也可以"], maxMinutes: 15),
        TrainingCard(dayIndex: 4, title: "恢复骑 + 核心激活", standardVersion: "共享单车/步行 30 分钟，能完整说话；下车后呼吸、鸟狗和站姿抗侧屈各 2 轮。", minimumVersion: "轻走 10 分钟→90/90 呼吸 5 次→鸟狗每侧 6 次。", regression: "不骑车，改平地轻走；鸟狗改坐姿呼气收肋。", stopConditions: "胸痛、异常气短、头晕或膝痛立即停止并求助。", followAlongInstruction: "本日不追求跟练速度，以恢复为主。", cameraPrompts: ["骑行时视线前方", "肩膀放松", "膝盖不向内夹"], maxMinutes: 40),
        TrainingCard(dayIndex: 5, title: "B 体态 + 深层核心", standardVersion: "下巴内收 10 次；墙面滑手 10 次；鸟狗每侧 8 次；桌沿支撑 25 秒，做 3 轮。", minimumVersion: "下巴内收 5 次→墙面滑手 8 次→鸟狗每侧 6 次，做 1 轮。", regression: "桌沿支撑改墙面支撑；鸟狗保持四点跪姿。", stopConditions: "腰痛、肩关节锐痛或无法保持呼吸立即停止。", followAlongInstruction: "跟练视频只完成最低版；质量优先于轮数。", cameraPrompts: ["耳朵、肩、髋大致对齐", "肘部不锁死", "骨盆保持水平"], maxMinutes: 18),
        TrainingCard(dayIndex: 6, title: "游泳/耐力骑 + 腰腹", standardVersion: "游泳 50m+休息 30–45 秒×8；或共享单车 45 分钟；回家后死虫、侧平板、反向卷腹各 2 轮。", minimumVersion: "轻松走 20 分钟→死虫每侧 6 次→呼吸 5 次。", regression: "取消间歇，改轻松游/走；不做卷腹。", stopConditions: "异常气短、胸痛、头晕、关节痛立即停止。", followAlongInstruction: "游泳不追配速；视频仅作为陆上动作演示。", cameraPrompts: ["全身入镜", "腰背自然", "动作中持续呼吸"], maxMinutes: 60),
        TrainingCard(dayIndex: 7, title: "恢复 + 核心复位", standardVersion: "上背/髋部拉伸 20 分钟；90/90 呼吸 5 次；死虫每侧 6 次；臀桥 12 次，做 2 轮。", minimumVersion: "90/90 呼吸 5 次→婴儿式呼吸 5 次，约 6 分钟。", regression: "只做平躺呼吸和轻松走，不做核心动作。", stopConditions: "拉伸出现锐痛、麻木或症状加重立即停止。", followAlongInstruction: "恢复日不需要跟完整视频，保持温和和可呼吸。", cameraPrompts: ["动作幅度小而可控", "肩颈放松", "不屏息"], maxMinutes: 25)
    ]

    public static func validate() -> [String] {
        cards.flatMap { card in
            var errors: [String] = []
            if card.minimumVersion.isEmpty || card.standardVersion.isEmpty { errors.append("\(card.title)：缺最低版或标准版") }
            if card.regression.isEmpty { errors.append("\(card.title)：缺退阶") }
            if card.stopConditions.isEmpty { errors.append("\(card.title)：缺停止条件") }
            if card.cameraPrompts.count < 2 { errors.append("\(card.title)：摄像头提示不足") }
            if card.maxMinutes > 60 { errors.append("\(card.title)：时间超限") }
            return errors
        }
    }
}
