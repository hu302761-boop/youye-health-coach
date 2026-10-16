import Foundation

#if canImport(ZIPFoundation)
import ZIPFoundation
#endif

/// A one-screen aggregate produced from an Apple Health export selected by the owner.
/// Raw records and the extracted XML never enter `PrivateCoachData`.
public struct AppleHealthExportPreview: Sendable, Equatable {
    public let archiveFileName: String
    public let exportDate: Date
    public let snapshot: HealthSnapshot
    public let relevantRecordCount: Int
    public let latestWeightRecordedAt: Date?
    public let latestBodyFatRecordedAt: Date?
    public let latestRestingHeartRateRecordedAt: Date?

    public init(
        archiveFileName: String,
        exportDate: Date,
        snapshot: HealthSnapshot,
        relevantRecordCount: Int,
        latestWeightRecordedAt: Date?,
        latestBodyFatRecordedAt: Date?,
        latestRestingHeartRateRecordedAt: Date?
    ) {
        self.archiveFileName = archiveFileName
        self.exportDate = exportDate
        self.snapshot = snapshot
        self.relevantRecordCount = max(0, relevantRecordCount)
        self.latestWeightRecordedAt = latestWeightRecordedAt
        self.latestBodyFatRecordedAt = latestBodyFatRecordedAt
        self.latestRestingHeartRateRecordedAt = latestRestingHeartRateRecordedAt
    }

    /// Imported files are historical snapshots. They must not silently drive today's recovery
    /// decision, especially when the owner selects an older export days or months later.
    public func isCurrentDay(asOf date: Date = .now, calendar: Calendar = .current) -> Bool {
        calendar.isDate(exportDate, inSameDayAs: date)
    }
}

public enum AppleHealthExportImportError: Error, Sendable, Equatable, LocalizedError {
    case unsupportedPlatform
    case unreadableArchive
    case archiveTooLarge
    case exportXMLMissing
    case exportXMLTooLarge
    case malformedXML
    case noReadableMetrics

    public var errorDescription: String? {
        switch self {
        case .unsupportedPlatform:
            "当前设备不支持读取 Apple 健康导出 ZIP。"
        case .unreadableArchive:
            "无法读取所选 ZIP；原文件没有被修改。"
        case .archiveTooLarge:
            "所选 ZIP 超过 512 MB 的本机预览上限；未解压或保存健康数据。"
        case .exportXMLMissing:
            "ZIP 中没有找到 Apple 健康导出 XML；请选择健康 App 直接导出的 ZIP。"
        case .exportXMLTooLarge:
            "导出 XML 超过 1 GB 的安全解析上限；未保存任何原始样本。"
        case .malformedXML:
            "Apple 健康导出 XML 不完整或无法解析；本机记录没有改变。"
        case .noReadableMetrics:
            "导出中没有找到本 App 支持的体重、体脂、步数、睡眠、静息心率、活动能量或运动摘要。"
        }
    }
}

public enum AppleHealthExportImporter {
    public static let maximumArchiveBytes: Int64 = 512 * 1_024 * 1_024
    public static let maximumXMLBytes: UInt64 = 1_024 * 1_024 * 1_024

    /// Reads one owner-selected ZIP entirely on-device. The XML is extracted only into a
    /// randomly named temporary directory, parsed with external entities disabled, and removed
    /// before this method returns (success or failure). No route, ECG or unrelated entry is read.
    public static func preview(fromArchiveAt archiveURL: URL) throws -> AppleHealthExportPreview {
        #if canImport(ZIPFoundation) && (os(iOS) || os(macOS))
        let didAccess = archiveURL.startAccessingSecurityScopedResource()
        defer { if didAccess { archiveURL.stopAccessingSecurityScopedResource() } }

        let values = try? archiveURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        if let fileSize = values?.fileSize, fileSize > maximumArchiveBytes {
            throw AppleHealthExportImportError.archiveTooLarge
        }

        let archive: Archive
        do { archive = try Archive(url: archiveURL, accessMode: .read) }
        catch { throw AppleHealthExportImportError.unreadableArchive }

        let candidates = archive.filter { entry in
            entry.type == .file
                && (entry.path as NSString).pathExtension.lowercased() == "xml"
                && !(entry.path as NSString).lastPathComponent.lowercased().contains("cda")
        }
        guard let entry = candidates.max(by: { $0.uncompressedSize < $1.uncompressedSize }) else {
            throw AppleHealthExportImportError.exportXMLMissing
        }
        guard entry.uncompressedSize > 0, entry.uncompressedSize <= maximumXMLBytes else {
            throw AppleHealthExportImportError.exportXMLTooLarge
        }

        let fileManager = FileManager.default
        let temporaryDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("health-export-\(UUID().uuidString)", isDirectory: true)
        let xmlURL = temporaryDirectory.appendingPathComponent("export.xml", isDirectory: false)
        do {
            #if os(iOS)
            try fileManager.createDirectory(
                at: temporaryDirectory,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.complete]
            )
            guard fileManager.createFile(
                atPath: xmlURL.path,
                contents: nil,
                attributes: [.protectionKey: FileProtectionType.complete]
            ) else { throw AppleHealthExportImportError.unreadableArchive }
            #else
            try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
            guard fileManager.createFile(atPath: xmlURL.path, contents: nil) else {
                throw AppleHealthExportImportError.unreadableArchive
            }
            #endif
        } catch let error as AppleHealthExportImportError {
            throw error
        } catch {
            throw AppleHealthExportImportError.unreadableArchive
        }
        defer { try? fileManager.removeItem(at: temporaryDirectory) }

        do {
            let output = try FileHandle(forWritingTo: xmlURL)
            defer { try? output.close() }
            _ = try archive.extract(entry, bufferSize: 64 * 1_024) { chunk in
                try output.write(contentsOf: chunk)
            }
        } catch {
            throw AppleHealthExportImportError.unreadableArchive
        }

        let fallbackDate = values?.contentModificationDate ?? .now
        return try preview(
            fromXMLAt: xmlURL,
            archiveFileName: archiveURL.lastPathComponent,
            fallbackReferenceDate: fallbackDate
        )
        #else
        throw AppleHealthExportImportError.unsupportedPlatform
        #endif
    }

    /// Internal XML entry point kept public so the rule checker can exercise the real streaming
    /// parser with a tiny fixture rather than depending only on string searches.
    public static func preview(
        fromXMLAt xmlURL: URL,
        archiveFileName: String = "Apple 健康导出.zip",
        fallbackReferenceDate: Date = .now
    ) throws -> AppleHealthExportPreview {
        #if os(iOS) || os(macOS)
        let delegate = AppleHealthExportXMLDelegate(fallbackReferenceDate: fallbackReferenceDate)
        guard let parser = XMLParser(contentsOf: xmlURL) else {
            throw AppleHealthExportImportError.malformedXML
        }
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        parser.shouldReportNamespacePrefixes = false
        parser.shouldResolveExternalEntities = false
        guard parser.parse(), parser.parserError == nil else {
            throw AppleHealthExportImportError.malformedXML
        }
        let result = delegate.makePreview(archiveFileName: archiveFileName)
        guard result.snapshot.hasAnyReadableMetric else {
            throw AppleHealthExportImportError.noReadableMetrics
        }
        return result
        #else
        throw AppleHealthExportImportError.unsupportedPlatform
        #endif
    }
}

public struct AppleHealthWeightAdoptionResult: Sendable, Equatable {
    public let data: PrivateCoachData
    public let weekStart: Date
    public let measuredAt: Date
    public let weightKg: Double
    public let replacedWeightKg: Double?
    public let wasAlreadySaved: Bool
}

/// Converts exactly one aggregate into an owner-confirmed weekly trend point. Merely selecting
/// or previewing a ZIP has no persistence effect, and this service never imports raw samples,
/// sleep, heart rate, steps, energy or workouts into the private profile.
public enum AppleHealthWeightAdoption {
    public static func adopting(
        preview: AppleHealthExportPreview,
        in data: PrivateCoachData,
        confirmed: Bool,
        confirmedAt: Date = .now,
        calendar: Calendar = .current
    ) -> AppleHealthWeightAdoptionResult? {
        guard confirmed,
              let weight = preview.snapshot.weightKg,
              weight.isFinite, (20...400).contains(weight),
              let measuredAt = preview.latestWeightRecordedAt,
              measuredAt <= preview.exportDate.addingTimeInterval(5 * 60),
              measuredAt <= confirmedAt.addingTimeInterval(5 * 60) else { return nil }

        let weekStart = WeeklyReviewService.weekStart(for: measuredAt, calendar: calendar)
        let existing = data.weeklyBodyCheckIns.first {
            calendar.isDate($0.weekStart, inSameDayAs: weekStart)
        }
        if let existing,
           existing.weightKg == weight,
           existing.weightSource == .confirmedAppleHealthExport,
           existing.weightMeasuredAt == measuredAt {
            return AppleHealthWeightAdoptionResult(
                data: data,
                weekStart: weekStart,
                measuredAt: measuredAt,
                weightKg: weight,
                replacedWeightKg: existing.weightKg,
                wasAlreadySaved: true
            )
        }

        let replacement = WeeklyBodyCheckIn(
            id: existing?.id ?? UUID(),
            weekStart: weekStart,
            recordedAt: confirmedAt,
            weightKg: weight,
            weightSource: .confirmedAppleHealthExport,
            weightMeasuredAt: measuredAt,
            waistCm: existing?.waistCm,
            note: existing?.note
        )
        var updated = data
        updated.weeklyBodyCheckIns.removeAll {
            calendar.isDate($0.weekStart, inSameDayAs: weekStart)
        }
        updated.weeklyBodyCheckIns.append(replacement)
        return AppleHealthWeightAdoptionResult(
            data: updated,
            weekStart: weekStart,
            measuredAt: measuredAt,
            weightKg: weight,
            replacedWeightKg: existing?.weightKg,
            wasAlreadySaved: false
        )
    }
}

#if os(iOS) || os(macOS)
private final class AppleHealthExportXMLDelegate: NSObject, XMLParserDelegate {
    private struct DatedValue {
        let date: Date
        let value: Double
    }

    private let fallbackReferenceDate: Date
    private var referenceDate: Date
    private var foundExportDate = false
    private var latestWeight: DatedValue?
    private var latestBodyFat: DatedValue?
    private var latestRestingHeartRate: DatedValue?
    private var stepTotalsBySource: [String: Double] = [:]
    private var activeEnergyBySource: [String: Double] = [:]
    private var sleepIntervals: [HealthTimeInterval] = []
    private var workoutIntervals: [HealthTimeInterval] = []
    private var swimIntervals: [HealthTimeInterval] = []
    private(set) var relevantRecordCount = 0

    private lazy var appleDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        return formatter
    }()
    private lazy var fractionalAppleDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS Z"
        return formatter
    }()

    init(fallbackReferenceDate: Date) {
        self.fallbackReferenceDate = fallbackReferenceDate
        referenceDate = fallbackReferenceDate
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        switch elementName {
        case "ExportDate":
            if let value = attributeDict["value"], let date = date(from: value) {
                referenceDate = date
                foundExportDate = true
            }
        case "Record":
            parseRecord(attributeDict)
        case "Workout":
            parseWorkout(attributeDict)
        default:
            break
        }
    }

    func makePreview(archiveFileName: String) -> AppleHealthExportPreview {
        let calendar = Calendar.current
        let nominalSleepEnd = calendar.startOfDay(for: referenceDate).addingTimeInterval(12 * 3_600)
        let sleepStart = calendar.date(byAdding: .hour, value: -18, to: nominalSleepEnd) ?? referenceDate
        let sleepEnd = min(nominalSleepEnd, referenceDate)
        let sleepWindow = HealthTimeInterval(start: sleepStart, end: sleepEnd)
        let workoutStart = calendar.date(byAdding: .day, value: -1, to: referenceDate) ?? referenceDate
        let workoutWindow = HealthTimeInterval(start: workoutStart, end: referenceDate)

        let stepSummary = HealthStepAggregation.average14Days(
            sourceCount: stepTotalsBySource.count,
            totalSteps: stepTotalsBySource.values.reduce(0, +)
        )
        let energySummary = HealthActiveEnergyAggregation.total24Hours(
            sourceCount: activeEnergyBySource.count,
            totalKilocalories: activeEnergyBySource.values.reduce(0, +)
        )
        let sleepSeconds = sleepWindow.map {
            HealthIntervalAggregation.unionDuration(of: HealthIntervalAggregation.clipped(sleepIntervals, to: $0))
        } ?? 0
        let workoutSeconds = workoutWindow.map {
            HealthIntervalAggregation.unionDuration(of: HealthIntervalAggregation.clipped(workoutIntervals, to: $0))
        } ?? 0
        let swimSeconds = workoutWindow.map {
            HealthIntervalAggregation.unionDuration(of: HealthIntervalAggregation.clipped(swimIntervals, to: $0))
        } ?? 0

        var notes = [stepSummary.note, energySummary.note].compactMap { $0 }
        notes.append("这是截至导出时间的本机文件预览，不是今天的实时 Apple 健康同步。")
        if !foundExportDate {
            notes.append("导出文件缺少 ExportDate，时间窗口使用文件日期保守计算。")
        }
        let snapshot = HealthSnapshot(
            fetchedAt: referenceDate,
            weightKg: latestWeight?.value,
            bodyFatPercent: latestBodyFat?.value,
            averageDailySteps14d: stepSummary.value,
            sleepHoursLastNight: sleepSeconds > 0 ? sleepSeconds / 3_600 : nil,
            restingHeartRate: latestRestingHeartRate?.value,
            activeEnergyKcal: energySummary.value,
            workoutMinutes: workoutSeconds > 0 ? workoutSeconds / 60 : nil,
            swimMinutes: swimSeconds > 0 ? swimSeconds / 60 : nil,
            source: "Apple 健康导出（本机预览）",
            availabilityNotes: notes
        ).sanitizedForDisplay()

        return AppleHealthExportPreview(
            archiveFileName: archiveFileName,
            exportDate: referenceDate,
            snapshot: snapshot,
            relevantRecordCount: relevantRecordCount,
            latestWeightRecordedAt: latestWeight?.date,
            latestBodyFatRecordedAt: latestBodyFat?.date,
            latestRestingHeartRateRecordedAt: latestRestingHeartRate?.date
        )
    }

    private func parseRecord(_ attributes: [String: String]) {
        guard let type = attributes["type"] else { return }
        switch type {
        case "HKQuantityTypeIdentifierBodyMass":
            guard let sample = quantitySample(attributes, windowDays: 30),
                  let value = convertedWeight(sample.value, unit: attributes["unit"]) else { return }
            relevantRecordCount += 1
            keepLatest(DatedValue(date: sample.end, value: value), in: &latestWeight)
        case "HKQuantityTypeIdentifierBodyFatPercentage":
            guard let sample = quantitySample(attributes, windowDays: 30),
                  let value = percent(sample.value, unit: attributes["unit"]) else { return }
            relevantRecordCount += 1
            keepLatest(DatedValue(date: sample.end, value: value), in: &latestBodyFat)
        case "HKQuantityTypeIdentifierRestingHeartRate":
            guard let sample = quantitySample(attributes, windowDays: 7),
                  isHeartRateUnit(attributes["unit"]) else { return }
            relevantRecordCount += 1
            keepLatest(DatedValue(date: sample.end, value: sample.value), in: &latestRestingHeartRate)
        case "HKQuantityTypeIdentifierStepCount":
            guard let sample = quantitySample(attributes, windowDays: 14), sample.value >= 0 else { return }
            relevantRecordCount += 1
            let source = normalizedSource(attributes["sourceName"])
            stepTotalsBySource[source, default: 0] += sample.value
        case "HKQuantityTypeIdentifierActiveEnergyBurned":
            guard let sample = quantitySample(attributes, windowDays: 1),
                  let value = kilocalories(sample.value, unit: attributes["unit"]) else { return }
            relevantRecordCount += 1
            let source = normalizedSource(attributes["sourceName"])
            activeEnergyBySource[source, default: 0] += value
        case "HKCategoryTypeIdentifierSleepAnalysis":
            guard isAsleepValue(attributes["value"]),
                  let interval = interval(attributes),
                  interval.end > sleepWindowStart(), interval.start < sleepWindowEnd() else { return }
            relevantRecordCount += 1
            sleepIntervals.append(interval)
        default:
            return
        }
    }

    private func parseWorkout(_ attributes: [String: String]) {
        guard let interval = interval(attributes),
              interval.end > dayOffset(-1), interval.start < referenceDate else { return }
        relevantRecordCount += 1
        workoutIntervals.append(interval)
        if attributes["workoutActivityType"]?.contains("Swimming") == true {
            swimIntervals.append(interval)
        }
    }

    private func quantitySample(
        _ attributes: [String: String],
        windowDays: Int
    ) -> (value: Double, start: Date, end: Date)? {
        guard let rawValue = attributes["value"],
              let value = Double(rawValue), value.isFinite,
              let startText = attributes["startDate"], let endText = attributes["endDate"],
              let start = date(from: startText), let end = date(from: endText), end >= start,
              start >= dayOffset(-windowDays), end <= referenceDate else { return nil }
        // Body measurements are commonly exported as point samples with equal start/end dates.
        // They still satisfy a closed quantity window; duration-only records remain governed by
        // `HealthTimeInterval`, which correctly rejects zero-length sleep or workout samples.
        return (value, start, end)
    }

    private func interval(_ attributes: [String: String]) -> HealthTimeInterval? {
        guard let startText = attributes["startDate"], let endText = attributes["endDate"],
              let start = date(from: startText), let end = date(from: endText) else { return nil }
        return HealthTimeInterval(start: start, end: end)
    }

    private func keepLatest(_ candidate: DatedValue, in stored: inout DatedValue?) {
        if stored == nil || candidate.date > stored!.date { stored = candidate }
    }

    private func dayOffset(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: referenceDate) ?? referenceDate
    }

    private func sleepWindowStart() -> Date {
        let end = Calendar.current.startOfDay(for: referenceDate).addingTimeInterval(12 * 3_600)
        return Calendar.current.date(byAdding: .hour, value: -18, to: end) ?? referenceDate
    }

    private func sleepWindowEnd() -> Date {
        min(Calendar.current.startOfDay(for: referenceDate).addingTimeInterval(12 * 3_600), referenceDate)
    }

    private func date(from text: String) -> Date? {
        appleDateFormatter.date(from: text) ?? fractionalAppleDateFormatter.date(from: text)
    }

    private func convertedWeight(_ value: Double, unit: String?) -> Double? {
        switch unit?.lowercased() {
        case "kg": value
        case "g": value / 1_000
        case "lb", "lbs": value * 0.453_592_37
        default: nil
        }
    }

    private func percent(_ value: Double, unit: String?) -> Double? {
        guard unit == "%" else { return nil }
        return value
    }

    private func kilocalories(_ value: Double, unit: String?) -> Double? {
        switch unit?.lowercased() {
        case "kcal": value
        case "kj": value / 4.184
        default: nil
        }
    }

    private func isHeartRateUnit(_ unit: String?) -> Bool {
        guard let normalized = unit?.lowercased().replacingOccurrences(of: " ", with: "") else { return false }
        return normalized == "count/min" || normalized == "count/minute"
    }

    private func normalizedSource(_ source: String?) -> String {
        let trimmed = source?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "未标注来源" : trimmed
    }

    private func isAsleepValue(_ value: String?) -> Bool {
        guard let value else { return false }
        if value.contains("InBed") || value.contains("Awake") { return false }
        if value.contains("Asleep") { return true }
        return ["1", "3", "4", "5"].contains(value)
    }
}
#endif
