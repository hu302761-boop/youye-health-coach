import Foundation

public struct HealthSnapshot: Codable, Sendable, Equatable {
    public let fetchedAt: Date
    public var weightKg: Double?
    public var bodyFatPercent: Double?
    public var averageDailySteps14d: Int?
    public var sleepHoursLastNight: Double?
    public var restingHeartRate: Double?
    public var activeEnergyKcal: Double?
    public var workoutMinutes: Double?
    public var swimMinutes: Double?
    public var source: String
    /// Availability notes explain conservative omissions (for example, conflicting step sources)
    /// without turning an empty metric into fabricated zero data. The snapshot remains transient.
    public var availabilityNotes: [String]
    /// Recent workouts are transient candidates for explicit owner import.
    public var recentWorkouts: [HealthWorkoutSummary]

    public init(fetchedAt: Date = .now, weightKg: Double? = nil, bodyFatPercent: Double? = nil, averageDailySteps14d: Int? = nil, sleepHoursLastNight: Double? = nil, restingHeartRate: Double? = nil, activeEnergyKcal: Double? = nil, workoutMinutes: Double? = nil, swimMinutes: Double? = nil, source: String = "HealthKit", availabilityNotes: [String] = [], recentWorkouts: [HealthWorkoutSummary] = []) {
        self.fetchedAt = fetchedAt; self.weightKg = weightKg; self.bodyFatPercent = bodyFatPercent; self.averageDailySteps14d = averageDailySteps14d
        self.sleepHoursLastNight = sleepHoursLastNight; self.restingHeartRate = restingHeartRate; self.activeEnergyKcal = activeEnergyKcal
        self.workoutMinutes = workoutMinutes; self.swimMinutes = swimMinutes; self.source = source; self.availabilityNotes = availabilityNotes; self.recentWorkouts = recentWorkouts
    }

    /// HealthKit 读取权限无法逐项判断；所有聚合字段都为空时，只能诚实地视为“本次没有可读摘要”。
    public var hasAnyReadableMetric: Bool {
        weightKg != nil || bodyFatPercent != nil || averageDailySteps14d != nil || sleepHoursLastNight != nil
            || restingHeartRate != nil || activeEnergyKcal != nil || workoutMinutes != nil || swimMinutes != nil || !recentWorkouts.isEmpty
    }

    /// A user-facing boundary for the transient summary screen. This describes the query
    /// windows, not a claim that every field was authorized or available. HealthKit does not
    /// expose per-read-type authorization status, so an empty value must remain visibly empty.
    public var queryScopeDescription: String {
        "体重/体脂取近 30 天最新值；步数仅在单一来源时计算近 14 天日均，多来源时保留空值避免重复累计；睡眠仅取昨晚窗口内的实际睡眠分段（不计清醒/仅在床上）；静息心率取近 7 天最新值；活动能量仅在单一来源时累计近 24 小时，运动取近 24 小时。步数/活动能量等数量样本只取完整位于窗口内的记录，避免把窗口外的整段数值算进来；睡眠和运动时长则先裁到查询窗口、再按重叠区间并集汇总，避免手机、Watch 或其他来源重复累计。"
    }

    /// Health summaries are deliberately transient: the app retains only user-entered state and
    /// explicit workout-sync receipts, never this snapshot or its raw HealthKit samples.
    public var localRetentionDescription: String {
        "该摘要仅供当前查看，不写入本机资料、导出或朋友周报；空值表示未授权、无记录或暂不可用，不以计划数据补齐。"
    }

    /// 只检查摘要本身，不以 UI 备注或来源文本推断异常。适用于恢复桥接等不经过界面
    /// 清洗的调用路径；任何一个异常字段都让自动调整停在“请核对”的安全侧。
    public var hasInvalidMetric: Bool {
        func invalid(_ value: Double?, outside range: ClosedRange<Double>) -> Bool {
            guard let value else { return false }
            return !value.isFinite || !range.contains(value)
        }
        if invalid(weightKg, outside: 20...400)
            || invalid(bodyFatPercent, outside: 0...100)
            || invalid(sleepHoursLastNight, outside: 0...24)
            || invalid(restingHeartRate, outside: 20...250)
            || invalid(activeEnergyKcal, outside: 0...15_000)
            || invalid(workoutMinutes, outside: 0...1_440)
            || invalid(swimMinutes, outside: 0...1_440) {
            return true
        }
        if let steps = averageDailySteps14d, !(0...200_000).contains(steps) { return true }
        if let swimMinutes, let workoutMinutes, swimMinutes > workoutMinutes { return true }
        return false
    }

    /// HealthKit 是来源而不是绝对正确性担保：用户的历史记录可能包含误录或异常样本。
    /// 在进入界面和恢复判断前先隐藏明显不可能的聚合值，保留简短原因而不把异常数值
    /// 再次展示。该方法不持久化、不会改写 Apple 健康中的任何记录。
    public func sanitizedForDisplay() -> HealthSnapshot {
        var notes = availabilityNotes
        var sanitized = self

        func valid(_ value: Double?, in range: ClosedRange<Double>, label: String) -> Double? {
            guard let value else { return nil }
            guard value.isFinite, range.contains(value) else {
                notes.append("\(label)数值异常，未显示；请在 Apple 健康核对。")
                return nil
            }
            return value
        }

        sanitized.weightKg = valid(weightKg, in: 20...400, label: "体重")
        sanitized.bodyFatPercent = valid(bodyFatPercent, in: 0...100, label: "体脂")
        sanitized.sleepHoursLastNight = valid(sleepHoursLastNight, in: 0...24, label: "睡眠")
        sanitized.restingHeartRate = valid(restingHeartRate, in: 20...250, label: "静息心率")
        sanitized.activeEnergyKcal = valid(activeEnergyKcal, in: 0...15_000, label: "活动能量")
        sanitized.workoutMinutes = valid(workoutMinutes, in: 0...1_440, label: "运动时长")
        sanitized.swimMinutes = valid(swimMinutes, in: 0...1_440, label: "游泳时长")
        if let steps = averageDailySteps14d, !(0...200_000).contains(steps) {
            sanitized.averageDailySteps14d = nil
            notes.append("近 14 天日均步数数值异常，未显示；请在 Apple 健康核对。")
        }
        if let swim = sanitized.swimMinutes,
           let workout = sanitized.workoutMinutes,
           swim > workout {
            sanitized.swimMinutes = nil
            notes.append("游泳时长高于最近运动总时长，未显示；请在 Apple 健康核对。")
        }
        var seen = Set<String>()
        sanitized.availabilityNotes = notes.filter { seen.insert($0).inserted }
        return sanitized
    }
}

public struct HealthWorkoutSummary: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let startedAt: Date
    public let endedAt: Date
    public let kind: ConfirmedHealthWorkoutKind
    public let title: String

    public init(id: UUID = UUID(), startedAt: Date, endedAt: Date, kind: ConfirmedHealthWorkoutKind, title: String) {
        self.id = id; self.startedAt = startedAt; self.endedAt = max(endedAt, startedAt); self.kind = kind; self.title = title
    }

    public var durationMinutes: Int { Int((max(0, endedAt.timeIntervalSince(startedAt)) / 60).rounded(.down)) }
}

/// A private, platform-neutral interval used only while creating a current-screen aggregate.
/// It lets the HealthKit adapter avoid inflating sleep or workout duration when two trusted
/// devices write records covering the same time. It is not persisted or exported.
public struct HealthTimeInterval: Sendable, Equatable {
    public let start: Date
    public let end: Date

    public init?(start: Date, end: Date) {
        guard end > start else { return nil }
        self.start = start
        self.end = end
    }

    /// HealthKit 谓词可能返回起点在窗口外、但与窗口相交的样本。"昨晚"与"近 24 小时"
    /// 的汇总只能计入窗口内重叠部分；裁剪结果依旧只用于当次界面，不会保存为健康样本。
    public func clipped(to window: HealthTimeInterval) -> HealthTimeInterval? {
        HealthTimeInterval(start: max(start, window.start), end: min(end, window.end))
    }
}

/// Health sources can contain overlapping sleep/workout samples from a phone, Watch, or another
/// authorized app. Sum the union, never the raw sample durations. Adjacent intervals are joined
/// too, avoiding artificial gaps from clock precision. This makes a conservative aggregate; it
/// does not decide which device is "more correct" or persist any source samples.
public enum HealthIntervalAggregation {
    public static func clipped(_ intervals: [HealthTimeInterval], to window: HealthTimeInterval) -> [HealthTimeInterval] {
        intervals.compactMap { $0.clipped(to: window) }
    }

    public static func unionDuration(of intervals: [HealthTimeInterval]) -> TimeInterval {
        let ordered = intervals.sorted {
            $0.start == $1.start ? $0.end < $1.end : $0.start < $1.start
        }
        guard var current = ordered.first else { return 0 }
        var duration: TimeInterval = 0
        for interval in ordered.dropFirst() {
            if interval.start <= current.end {
                if interval.end > current.end {
                    current = HealthTimeInterval(start: current.start, end: interval.end)!
                }
            } else {
                duration += current.end.timeIntervalSince(current.start)
                current = interval
            }
        }
        return duration + current.end.timeIntervalSince(current.start)
    }
}

/// Step samples are quantities rather than time intervals, so this app cannot safely union
/// overlapping phone/Watch samples without inventing a source-priority rule. A single source
/// may use HealthKit's own cumulative aggregate; multiple sources stay visibly unavailable.
public enum HealthStepAggregation {
    public static func average14Days(sourceCount: Int, totalSteps: Double?) -> (value: Int?, note: String?) {
        guard sourceCount > 0, let totalSteps else { return (nil, nil) }
        guard sourceCount == 1 else {
            return (nil, "步数存在多个来源，本次未合并，避免 iPhone/Watch 等数据重复累计")
        }
        // HealthKit normally returns a finite cumulative quantity, but imported/test stores or
        // a provider failure can still surface NaN, infinity, a negative value, or an amount so
        // large that converting it to Int would trap.  Keep the metric unavailable and explain
        // the omission rather than crashing or displaying a fabricated daily average.
        guard totalSteps.isFinite, (0...2_800_000).contains(totalSteps) else {
            return (nil, "步数摘要数值异常，本次未显示；请在 Apple 健康核对")
        }
        return (Int(totalSteps / 14.0), nil)
    }
}

/// Like steps, active energy is a quantity rather than an interval. When multiple sources are
/// present, summing their samples can double-count a Watch/iPhone pair. Keep it unavailable
/// until the user can inspect the source in Apple Health instead of manufacturing a total.
public enum HealthActiveEnergyAggregation {
    public static func total24Hours(sourceCount: Int, totalKilocalories: Double?) -> (value: Double?, note: String?) {
        guard sourceCount > 0, let totalKilocalories else { return (nil, nil) }
        guard sourceCount == 1 else {
            return (nil, "活动能量存在多个来源，本次未合并，避免 iPhone/Watch 等数据重复累计")
        }
        guard totalKilocalories.isFinite, (0...15_000).contains(totalKilocalories) else {
            return (nil, "活动能量摘要数值异常，本次未显示；请在 Apple 健康核对")
        }
        return (totalKilocalories, nil)
    }
}

/// Quantity samples (steps and active energy) cannot be safely split at a query boundary:
/// unlike a sleep/workout duration, HealthKit exposes one value for the whole sample interval.
/// A cross-boundary sample is therefore excluded rather than counted in full and overstating the
/// requested day/window. This intentionally differs from duration samples, which are clipped
/// and unioned in `HealthIntervalAggregation`.
public enum HealthQuantityWindowPolicy {
    public static func isFullyContained(_ sample: HealthTimeInterval, in window: HealthTimeInterval) -> Bool {
        sample.start >= window.start && sample.end <= window.end
    }

    /// The native adapter expresses the same conservative rule to HealthKit with both strict
    /// boundaries. Keeping this in one place avoids future quantity queries reintroducing an
    /// overlap-based total.
    #if os(iOS) && canImport(HealthKit)
    static let predicateOptions: HKQueryOptions = [.strictStartDate, .strictEndDate]
    #endif
}

public enum HealthKitReadMetric: String, Codable, Sendable, CaseIterable {
    /// 游泳时长从用户已授权的运动记录汇总；不额外读取游泳距离，减少不必要的数据访问。
    case bodyMass, bodyFatPercentage, stepCount, sleepAnalysis, restingHeartRate, activeEnergyBurned, workouts
}

public struct HealthKitPermissionPlan: Codable, Sendable, Equatable {
    public let readMetrics: Set<HealthKitReadMetric>

    public init(
        readMetrics: Set<HealthKitReadMetric> = Set(HealthKitReadMetric.allCases)
    ) {
        self.readMetrics = readMetrics
    }

    /// Every HealthKit permission request in this product is read-only. Actual training can be
    /// timed and checked in locally, but is never written back to Apple Health.
    public static let readOnly = HealthKitPermissionPlan()
}

public enum ConfirmedHealthWorkoutKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case coreTraining
    case flexibility
    case walking
    case cycling
    case swimming

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .coreTraining: "腰腹/力量训练"
        case .flexibility: "拉伸/恢复活动"
        case .walking: "步行"
        case .cycling: "骑行"
        case .swimming: "游泳"
        }
    }
}

public enum ImportedWorkoutSource: String, Codable, Sendable, Equatable {
    case appleHealth
    case screenshot
    case manual

    public var displayName: String {
        switch self {
        case .appleHealth: "Apple 健康"
        case .screenshot: "截图核对"
        case .manual: "手动补录"
        }
    }
}

/// A minimal, owner-confirmed external workout record. The app keeps the claimed interval and
/// source only; it never stores a screenshot or raw HealthKit sample and never writes back to
/// Apple Health. Details from a screenshot are always entered/confirmed by the owner.
public struct ImportedWorkoutRecord: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let startedAt: Date
    public let endedAt: Date
    public let kind: ConfirmedHealthWorkoutKind
    public let source: ImportedWorkoutSource
    public let note: String?
    public let importedAt: Date

    public init(id: UUID = UUID(), startedAt: Date, endedAt: Date, kind: ConfirmedHealthWorkoutKind, source: ImportedWorkoutSource, note: String? = nil, importedAt: Date = .now) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = max(endedAt, startedAt)
        self.kind = kind
        self.source = source
        let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.note = trimmedNote?.isEmpty == true ? nil : trimmedNote
        self.importedAt = importedAt
    }

    public var duration: TimeInterval { max(0, endedAt.timeIntervalSince(startedAt)) }
    public var durationMinutes: Int { Int((duration / 60).rounded(.down)) }
}

/// Centralised, deterministic policy for turning transient Apple Health candidates into
/// owner-confirmed local records. HealthKit remains read-only: this policy only filters and
/// de-duplicates candidates, while the UI still asks for one explicit owner confirmation.
public enum HealthWorkoutImportPolicy {
    public static func eligible(
        _ candidates: [HealthWorkoutSummary],
        minimumMinutes: Int,
        imported: [ImportedWorkoutRecord]
    ) -> [HealthWorkoutSummary] {
        let threshold = max(1, minimumMinutes)
        var seen = Set<String>()
        return candidates
            .filter { $0.durationMinutes >= threshold }
            .sorted { $0.startedAt > $1.startedAt }
            .filter { candidate in
                let candidateKey = key(startedAt: candidate.startedAt, kind: candidate.kind, durationMinutes: candidate.durationMinutes)
                guard seen.insert(candidateKey).inserted else { return false }
                return !imported.contains {
                    key(startedAt: $0.startedAt, kind: $0.kind, durationMinutes: $0.durationMinutes) == candidateKey
                }
            }
    }

    private static func key(startedAt: Date, kind: ConfirmedHealthWorkoutKind, durationMinutes: Int) -> String {
        "\(startedAt.timeIntervalSinceReferenceDate.rounded())|\(kind.rawValue)|\(durationMinutes)"
    }
}

/// Values are supplied by the user at sync time, not inferred from a plan, camera, or HealthKit.
public struct ConfirmedHealthWorkout: Codable, Sendable, Equatable {
    public let dayIndex: Int
    public let startedAt: Date
    public let endedAt: Date
    public let kind: ConfirmedHealthWorkoutKind
    /// Stable for one local user-confirmed session. It identifies an App-private draft only and
    /// is never sent to Apple Health.
    public let syncIdentifier: UUID

    public init(dayIndex: Int, startedAt: Date, endedAt: Date, kind: ConfirmedHealthWorkoutKind, syncIdentifier: UUID = UUID()) {
        self.dayIndex = dayIndex
        self.startedAt = startedAt
        self.endedAt = max(endedAt, startedAt)
        self.kind = kind
        self.syncIdentifier = syncIdentifier
    }

    private enum CodingKeys: String, CodingKey {
        case dayIndex, startedAt, endedAt, kind, syncIdentifier
    }

    /// A stopped interval must describe one real formal-plan day.  Restored data can bypass the
    /// timer UI, so reject a future/out-of-range day index or an inverted interval rather than
    /// silently normalizing it into a seemingly valid local workout draft.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let dayIndex = try values.decode(Int.self, forKey: .dayIndex)
        let startedAt = try values.decode(Date.self, forKey: .startedAt)
        let endedAt = try values.decode(Date.self, forKey: .endedAt)
        guard (1...56).contains(dayIndex), endedAt > startedAt else {
            throw DecodingError.dataCorruptedError(
                forKey: .dayIndex,
                in: values,
                debugDescription: "A confirmed workout must have a formal day index and positive observed duration."
            )
        }
        self.init(
            dayIndex: dayIndex,
            startedAt: startedAt,
            endedAt: endedAt,
            kind: try values.decode(ConfirmedHealthWorkoutKind.self, forKey: .kind),
            syncIdentifier: try values.decode(UUID.self, forKey: .syncIdentifier)
        )
    }

    /// The write payload uses these exact user-observed boundaries; it never rounds a plan’s
    /// intended duration up or down to manufacture a Health workout.
    public var duration: TimeInterval { endedAt.timeIntervalSince(startedAt) }
    public var elapsedSeconds: Int { max(0, Int(duration.rounded(.down))) }
    public var displayDuration: String {
        let seconds = elapsedSeconds
        return String(format: "%02d:%02d:%02d", seconds / 3600, (seconds / 60) % 60, seconds % 60)
    }

    /// A real session may begin before midnight and end after it. This is only an explanatory
    /// label for the confirmation UI: Apple Health still receives the exact observed timestamps,
    /// never a duration forced into the scheduled plan day.
    public func crossesCalendarDay(calendar: Calendar = .current) -> Bool {
        !calendar.isDate(startedAt, inSameDayAs: endedAt)
    }
}

public protocol HealthSummaryProviding: Sendable {
    func requestAuthorization() async throws
    func readSummary() async throws -> HealthSnapshot
}

/// User-facing failure text is intentionally narrow: HealthKit does not reveal every individual
/// read authorization decision, so the app must not claim a specific metric was denied unless
/// the platform actually reported an authorization failure.
public enum HealthKitAccessMessage {
    public static func readFailure(_ error: Error) -> String {
        guard let healthError = error as? HealthKitError else {
            return "本次无法读取 Apple 健康摘要，可能是系统暂时不可用。没有使用计划数据补齐；可稍后重试或在“今天”手动记录状态。"
        }
        switch healthError {
        case .unavailable:
            return "此设备当前不可用 Apple 健康。App 不会显示或补造健康数据；可继续使用手动状态和周复盘。"
        case .authorizationNotGranted:
            return "尚未获得 Apple 健康授权。你可以在系统健康权限中调整后重试；未授权时仍可手动记录睡眠、精力、疼痛和皮肤状态。"
        case let .metricUnavailable(metric):
            return "Apple 健康中的“\(metric)”在此设备上暂不可用；本次未生成不完整的替代数据。可稍后重试或继续手动记录。"
        }
    }
}

#if os(iOS) && canImport(HealthKit)
import HealthKit

/// iOS 17 正式实现：仅读取经授权的最小健康摘要。
/// 原始样本不离开设备，也不写入本 App 的私有 JSON。
public final class NativeHealthKitProvider: HealthSummaryProviding, @unchecked Sendable {
    private let store: HKHealthStore
    private let permissionPlan: HealthKitPermissionPlan

    /// This provider never requests a share type and never writes to Apple Health.
    public init(store: HKHealthStore = HKHealthStore(), permissionPlan: HealthKitPermissionPlan = .readOnly) {
        self.store = store; self.permissionPlan = permissionPlan
    }

    public func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { throw HealthKitError.unavailable }
        let readTypes = try makeReadTypes()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            store.requestAuthorization(toShare: [], read: readTypes) { success, error in
                if let error { continuation.resume(throwing: error) }
                else if success { continuation.resume() }
                else { continuation.resume(throwing: HealthKitError.authorizationNotGranted) }
            }
        }
    }

    public func readSummary() async throws -> HealthSnapshot {
        guard HKHealthStore.isHealthDataAvailable() else { throw HealthKitError.unavailable }
        let now = Date()
        let metrics = permissionPlan.readMetrics
        let weight = metrics.contains(.bodyMass)
            ? try await latestQuantity(.bodyMass, unit: .gramUnit(with: .kilo), since: Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now, through: now)
            : nil
        let bodyFat = metrics.contains(.bodyFatPercentage)
            ? try await latestQuantity(.bodyFatPercentage, unit: .percent(), since: Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now, through: now).map { $0 * 100 }
            : nil
        let stepSummary = metrics.contains(.stepCount)
            ? try await averageSteps14Days(now: now)
            : (value: nil, note: nil)
        let sleep = metrics.contains(.sleepAnalysis) ? try await sleepHoursLastNight(now: now) : nil
        let heartRate = metrics.contains(.restingHeartRate)
            ? try await latestQuantity(.restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute()), since: Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now, through: now)
            : nil
        let energySummary = metrics.contains(.activeEnergyBurned)
            ? try await activeEnergy24Hours(now: now)
            : (value: nil, note: nil)
        let workouts = metrics.contains(.workouts) ? try await workoutSummary(now: now) : (total: nil, swim: nil, recent: [HealthWorkoutSummary]())
        return HealthSnapshot(
            fetchedAt: now,
            weightKg: weight,
            bodyFatPercent: bodyFat,
            averageDailySteps14d: stepSummary.value,
            sleepHoursLastNight: sleep,
            restingHeartRate: heartRate,
            activeEnergyKcal: energySummary.value,
            workoutMinutes: workouts.total,
            swimMinutes: workouts.swim,
            source: "HealthKit 摘要",
            availabilityNotes: [stepSummary.note, energySummary.note].compactMap { $0 },
            recentWorkouts: workouts.recent
        )
    }

    /// Every metric in a single summary is bounded by the same captured `through` instant. This
    /// avoids a slow later query seeing a newer sample than `HealthSnapshot.fetchedAt`, which
    /// would make one displayed summary span multiple unlabelled moments in time.
    private func latestQuantity(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        since start: Date,
        through end: Date
    ) async throws -> Double? {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else { throw HealthKitError.metricUnavailable(identifier.rawValue) }
        // Quantities cannot be safely prorated when a sample crosses this boundary. Keep only
        // fully-contained samples rather than counting their whole interval in a shorter window.
        let predicate = HKQuery.predicateForSamples(
            withStart: start,
            end: end,
            options: HealthQuantityWindowPolicy.predicateOptions
        )
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Double?, Error>) in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: 1, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]) { _, samples, error in
                if let error { continuation.resume(throwing: error); return }
                let sample = samples?.first as? HKQuantitySample
                continuation.resume(returning: sample?.quantity.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }

    private func averageSteps14Days(now: Date) async throws -> (value: Int?, note: String?) {
        guard let type = HKObjectType.quantityType(forIdentifier: .stepCount) else { throw HealthKitError.metricUnavailable("stepCount") }
        let start = Calendar.current.date(byAdding: .day, value: -14, to: now) ?? now
        let predicate = HKQuery.predicateForSamples(
            withStart: start,
            end: now,
            options: HealthQuantityWindowPolicy.predicateOptions
        )
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(value: Int?, note: String?), Error>) in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: [.cumulativeSum, .separateBySource]) { _, statistics, error in
                if let error { continuation.resume(throwing: error); return }
                let total = statistics?.sumQuantity()?.doubleValue(for: .count())
                let result = HealthStepAggregation.average14Days(sourceCount: statistics?.sources?.count ?? 0, totalSteps: total)
                continuation.resume(returning: result)
            }
            store.execute(query)
        }
    }

    private func activeEnergy24Hours(now: Date) async throws -> (value: Double?, note: String?) {
        guard let type = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) else {
            throw HealthKitError.metricUnavailable("activeEnergyBurned")
        }
        let start = Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now
        let predicate = HKQuery.predicateForSamples(
            withStart: start,
            end: now,
            options: HealthQuantityWindowPolicy.predicateOptions
        )
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(Double?, String?), Error>) in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: [.cumulativeSum, .separateBySource]
            ) { _, statistics, error in
                if let error { continuation.resume(throwing: error); return }
                let total = statistics?.sumQuantity()?.doubleValue(for: .kilocalorie())
                continuation.resume(returning: HealthActiveEnergyAggregation.total24Hours(
                    sourceCount: statistics?.sources?.count ?? 0,
                    totalKilocalories: total
                ))
            }
            store.execute(query)
        }
    }

    private func sleepHoursLastNight(now: Date) async throws -> Double? {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { throw HealthKitError.metricUnavailable("sleepAnalysis") }
        let calendar = Calendar.current
        // The nominal sleep window is 18:00 yesterday–12:00 today. In the morning, never query
        // beyond the captured snapshot time: a clock-corrupt future sample must not become part
        // of “last night”, yet the stable nominal start keeps the intended overnight boundary.
        let nominalEnd = calendar.startOfDay(for: now).addingTimeInterval(12 * 3600)
        let start = calendar.date(byAdding: .hour, value: -18, to: nominalEnd) ?? now
        let end = min(nominalEnd, now)
        guard let window = HealthTimeInterval(start: start, end: end) else { return nil }
        // No strict boundary option: collect every sample that overlaps the window, then clip it
        // below. A strict end date would silently omit a session that spans the current boundary.
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Double?, Error>) in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error { continuation.resume(throwing: error); return }
                let inBed = HKCategoryValueSleepAnalysis.inBed.rawValue
                let awake = HKCategoryValueSleepAnalysis.awake.rawValue
                let intervals = (samples as? [HKCategorySample] ?? [])
                    // HealthKit distinguishes actual sleep stages from "in bed" and awake.
                    // Only the former count toward sleep hours; duplicate sources are unioned below.
                    .filter { $0.value != inBed && $0.value != awake }
                    .compactMap { HealthTimeInterval(start: $0.startDate, end: $0.endDate) }
                let seconds = HealthIntervalAggregation.unionDuration(of: HealthIntervalAggregation.clipped(intervals, to: window))
                continuation.resume(returning: seconds > 0 ? seconds / 3600.0 : nil)
            }
            store.execute(query)
        }
    }

    private func workoutSummary(now: Date) async throws -> (total: Double?, swim: Double?, recent: [HealthWorkoutSummary]) {
        let type = HKObjectType.workoutType()
        let summaryStart = Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now
        let recentStart = Calendar.current.date(byAdding: .day, value: -7, to: now) ?? summaryStart
        guard let window = HealthTimeInterval(start: summaryStart, end: now) else { return (nil, nil, []) }
        // Include workouts overlapping this 24-hour window, then clip their intervals before
        // unioning so a cross-boundary workout contributes only its in-window duration.
        let predicate = HKQuery.predicateForSamples(withStart: recentStart, end: now, options: [])
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(total: Double?, swim: Double?, recent: [HealthWorkoutSummary]), Error>) in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error { continuation.resume(throwing: error); return }
                let workouts = (samples as? [HKWorkout] ?? [])
                let totalIntervals = workouts.compactMap { HealthTimeInterval(start: $0.startDate, end: $0.endDate) }
                let swimIntervals = workouts
                    .filter { $0.workoutActivityType == .swimming }
                    .compactMap { HealthTimeInterval(start: $0.startDate, end: $0.endDate) }
                let total = HealthIntervalAggregation.unionDuration(of: HealthIntervalAggregation.clipped(totalIntervals, to: window)) / 60.0
                let swim = HealthIntervalAggregation.unionDuration(of: HealthIntervalAggregation.clipped(swimIntervals, to: window)) / 60.0
                let recent = workouts.compactMap { workout -> HealthWorkoutSummary? in
                    guard workout.endDate > recentStart, workout.startDate < now else { return nil }
                    // A workout crossing the seven-day or current-time boundary is represented
                    // only by the observable portion in this sync window; future minutes and
                    // pre-window minutes must never be offered for adoption.
                    let startedAt = max(workout.startDate, recentStart)
                    let endedAt = min(workout.endDate, now)
                    guard endedAt > startedAt else { return nil }
                    let kind: ConfirmedHealthWorkoutKind
                    switch workout.workoutActivityType {
                    case .cycling: kind = .cycling
                    case .swimming: kind = .swimming
                    case .walking: kind = .walking
                    default: kind = .coreTraining
                    }
                    return HealthWorkoutSummary(startedAt: startedAt, endedAt: endedAt, kind: kind, title: kind.displayName)
                }.sorted { $0.startedAt > $1.startedAt }
                continuation.resume(returning: (total > 0 ? total : nil, swim > 0 ? swim : nil, recent))
            }
            store.execute(query)
        }
    }

    private func makeReadTypes() throws -> Set<HKObjectType> {
        var result = Set<HKObjectType>()
        for metric in permissionPlan.readMetrics {
            switch metric {
            case .bodyMass: try insertQuantity(.bodyMass, into: &result)
            case .bodyFatPercentage: try insertQuantity(.bodyFatPercentage, into: &result)
            case .stepCount: try insertQuantity(.stepCount, into: &result)
            case .restingHeartRate: try insertQuantity(.restingHeartRate, into: &result)
            case .activeEnergyBurned: try insertQuantity(.activeEnergyBurned, into: &result)
            case .sleepAnalysis:
                if let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { result.insert(type) }
                else { throw HealthKitError.metricUnavailable(metric.rawValue) }
            case .workouts: result.insert(HKObjectType.workoutType())
            }
        }
        return result
    }

    private func insertQuantity(_ identifier: HKQuantityTypeIdentifier, into set: inout Set<HKObjectType>) throws {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else { throw HealthKitError.metricUnavailable(identifier.rawValue) }
        set.insert(type)
    }
}

public enum HealthKitError: Error, Sendable, Equatable {
    case unavailable
    case authorizationNotGranted
    case metricUnavailable(String)
}
#else

/// macOS/command-line placeholder: no Apple Health access exists outside the iPhone/iPad
/// target. It never fabricates HealthKit data or silently redirects a desktop call elsewhere.
public struct UnavailableHealthKitProvider: HealthSummaryProviding {
    public init() {}
    public func requestAuthorization() async throws { throw HealthKitError.unavailable }
    public func readSummary() async throws -> HealthSnapshot { throw HealthKitError.unavailable }
}

public enum HealthKitError: Error, Sendable, Equatable {
    case unavailable
    case authorizationNotGranted
    case metricUnavailable(String)
}
#endif
