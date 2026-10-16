#if !os(watchOS)
import CoreXLSX
import CryptoKit
import Foundation

public struct BudgetImportCandidate: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let sourceRow: UInt
    public let date: Date
    public let amountYuan: Decimal
    public let sourceCategory: String
    public let note: String
    public var category: BudgetCategory
    public var isSelected: Bool

    public init(
        id: UUID,
        sourceRow: UInt,
        date: Date,
        amountYuan: Decimal,
        sourceCategory: String,
        note: String,
        category: BudgetCategory,
        isSelected: Bool = true
    ) {
        self.id = id
        self.sourceRow = sourceRow
        self.date = date
        self.amountYuan = amountYuan
        self.sourceCategory = sourceCategory
        self.note = note
        self.category = category
        self.isSelected = isSelected
    }

    public func expenseEntry() -> ExpenseEntry {
        ExpenseEntry(
            id: id,
            date: date,
            category: category,
            amountYuan: amountYuan,
            note: note,
            isUserConfirmed: true
        )
    }
}

public struct BudgetImportPreview: Equatable, Sendable {
    public let sourceFileName: String
    public let sheetName: String
    public var candidates: [BudgetImportCandidate]
    public let skippedRowCount: Int
    public let warnings: [String]
}

public enum BudgetImportError: LocalizedError, Equatable {
    case unreadableWorkbook
    case noWorksheet
    case missingRequiredColumns
    case noExpenseRows

    public var errorDescription: String? {
        switch self {
        case .unreadableWorkbook:
            "无法读取这份 XLSX；文件可能已损坏、加密或不是标准 Excel 工作簿。"
        case .noWorksheet:
            "工作簿里没有可读取的工作表。"
        case .missingRequiredColumns:
            "没有识别到日期、金额和分类/备注列。请从钱迹重新导出 XLSX 后再选。"
        case .noExpenseRows:
            "没有找到可预览的支出记录；收入、转账、无日期或无金额的行不会导入。"
        }
    }
}

public enum QianJiBudgetImport {
    private struct HeaderMapping {
        let rowIndex: Int
        let dateColumn: String
        let amountColumn: String
        let categoryColumn: String?
        let noteColumn: String?
        let typeColumn: String?
        let score: Int
    }

    private static let dateHeaders = ["日期", "时间", "交易时间", "记账时间", "账单时间", "发生时间"]
    private static let amountHeaders = ["金额", "支出金额", "交易金额", "账单金额", "人民币金额"]
    private static let categoryHeaders = ["分类", "类别", "一级分类", "二级分类", "账目分类", "收支分类"]
    private static let noteHeaders = ["备注", "说明", "项目", "商品", "商家", "账单备注", "名称"]
    private static let typeHeaders = ["收支类型", "账单类型", "交易类型", "类型"]

    public static func parseXLSX(
        at url: URL,
        targetMonthKey: String = MonthlyBudgetLedger.monthKey(for: .now),
        calendar: Calendar = .current
    ) throws -> BudgetImportPreview {
        guard let file = XLSXFile(filepath: url.path) else { throw BudgetImportError.unreadableWorkbook }
        let sharedStrings = try? file.parseSharedStrings()
        let workbooks = try file.parseWorkbooks()
        guard !workbooks.isEmpty else { throw BudgetImportError.noWorksheet }

        var sawWorksheet = false
        for workbook in workbooks {
            for (name, path) in try file.parseWorksheetPathsAndNames(workbook: workbook) {
                sawWorksheet = true
                let worksheet = try file.parseWorksheet(at: path)
                let rows = worksheet.data?.rows ?? []
                guard let mapping = bestHeaderMapping(in: rows, sharedStrings: sharedStrings) else { continue }
                let parsed = parseRows(
                    rows,
                    after: mapping,
                    sharedStrings: sharedStrings,
                    sourceFileName: url.lastPathComponent,
                    targetMonthKey: targetMonthKey,
                    calendar: calendar
                )
                guard !parsed.candidates.isEmpty else { continue }
                return BudgetImportPreview(
                    sourceFileName: url.lastPathComponent,
                    sheetName: name ?? "未命名工作表",
                    candidates: parsed.candidates,
                    skippedRowCount: parsed.skipped,
                    warnings: parsed.warnings
                )
            }
        }
        if !sawWorksheet { throw BudgetImportError.noWorksheet }
        throw BudgetImportError.noExpenseRows
    }

    public static func suggestedCategory(sourceCategory: String, note: String) -> BudgetCategory {
        let text = normalized(sourceCategory + " " + note)
        if containsAny(text, ["菜", "肉", "蛋", "奶", "水果", "超市", "生鲜", "食材", "粮油", "调味", "餐饮"]) {
            return .ingredients
        }
        if containsAny(text, ["游泳", "泳池", "泳馆"]) { return .swimming }
        if containsAny(text, ["单车", "骑行", "共享自行车", "哈啰", "青桔", "美团单车"]) { return .cycling }
        if containsAny(text, ["护肤", "洁面", "防晒", "面膜", "痘", "药膏", "耗材"]) { return .skincare }
        return .buffer
    }

    public static func isDuplicate(_ candidate: BudgetImportCandidate, in ledger: MonthlyBudgetLedger) -> Bool {
        ledger.entries.contains { existing in
            if existing.id == candidate.id { return true }
            let sameMinute = abs(existing.date.timeIntervalSince(candidate.date)) < 60
            let sameAmount = existing.amountYuan == candidate.amountYuan
            let sameNote = normalized(existing.note) == normalized(candidate.note)
            return sameMinute && sameAmount && sameNote
        }
    }

    private static func bestHeaderMapping(in rows: [Row], sharedStrings: SharedStrings?) -> HeaderMapping? {
        rows.prefix(20).enumerated().compactMap { index, row -> HeaderMapping? in
            let values = cellValues(in: row, sharedStrings: sharedStrings)
            let date = column(matching: dateHeaders, in: values)
            let amount = column(matching: amountHeaders, in: values)
            let category = column(matching: categoryHeaders, in: values)
            let note = column(matching: noteHeaders, in: values)
            let type = column(matching: typeHeaders, in: values)
            guard let date, let amount, category != nil || note != nil else { return nil }
            return HeaderMapping(
                rowIndex: index,
                dateColumn: date,
                amountColumn: amount,
                categoryColumn: category,
                noteColumn: note,
                typeColumn: type,
                score: 2 + [category, note, type].compactMap { $0 }.count
            )
        }
        .max { lhs, rhs in lhs.score < rhs.score }
    }

    private static func parseRows(
        _ rows: [Row],
        after mapping: HeaderMapping,
        sharedStrings: SharedStrings?,
        sourceFileName: String,
        targetMonthKey: String,
        calendar: Calendar
    ) -> (candidates: [BudgetImportCandidate], skipped: Int, warnings: [String]) {
        var candidates: [BudgetImportCandidate] = []
        var skipped = 0
        var otherMonthCount = 0

        for row in rows.dropFirst(mapping.rowIndex + 1) {
            let cells = Dictionary(uniqueKeysWithValues: row.cells.map { ($0.reference.column.description, $0) })
            let values = cellValues(in: row, sharedStrings: sharedStrings)
            guard
                let dateCell = cells[mapping.dateColumn],
                let date = parsedDate(cell: dateCell, text: values[mapping.dateColumn] ?? "", calendar: calendar),
                let amount = parsedAmount(values[mapping.amountColumn] ?? ""),
                amount > 0
            else {
                if !values.values.allSatisfy({ normalized($0).isEmpty }) { skipped += 1 }
                continue
            }

            let type = mapping.typeColumn.flatMap { values[$0] } ?? ""
            if containsAny(normalized(type), ["收入", "转账", "退款", "借入", "借出"]) {
                skipped += 1
                continue
            }
            guard MonthlyBudgetLedger.monthKey(for: date, calendar: calendar) == targetMonthKey else {
                otherMonthCount += 1
                continue
            }

            let sourceCategory = mapping.categoryColumn.flatMap { values[$0] }?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "未分类"
            var note = mapping.noteColumn.flatMap { values[$0] }?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if note.isEmpty { note = sourceCategory.isEmpty ? "钱迹导入" : sourceCategory }
            let stableKey = [sourceFileName, String(row.reference), date.formatted(.iso8601), amount.description, sourceCategory, note].joined(separator: "|")
            candidates.append(
                BudgetImportCandidate(
                    id: stableUUID(for: stableKey),
                    sourceRow: row.reference,
                    date: date,
                    amountYuan: amount,
                    sourceCategory: sourceCategory,
                    note: note,
                    category: suggestedCategory(sourceCategory: sourceCategory, note: note)
                )
            )
        }

        var warnings: [String] = []
        if otherMonthCount > 0 { warnings.append("另有 \(otherMonthCount) 条不属于 \(targetMonthKey)，本次没有列入。") }
        if skipped > 0 { warnings.append("有 \(skipped) 行是收入/转账、空行或缺少有效日期金额，已跳过。") }
        warnings.append("分类是本机关键词初步映射；请逐条核对后再确认导入。")
        return (candidates, skipped, warnings)
    }

    private static func cellValues(in row: Row, sharedStrings: SharedStrings?) -> [String: String] {
        Dictionary(uniqueKeysWithValues: row.cells.map { cell in
            let value: String
            if let sharedStrings {
                value = cell.stringValue(sharedStrings) ?? cell.inlineString?.text ?? cell.value ?? ""
            } else {
                value = cell.inlineString?.text ?? cell.value ?? ""
            }
            return (cell.reference.column.description, value)
        })
    }

    private static func column(matching aliases: [String], in values: [String: String]) -> String? {
        values.first { _, value in
            let header = normalized(value)
            return aliases.contains { normalized($0) == header }
        }?.key
    }

    private static func parsedDate(cell: Cell, text: String, calendar: Calendar) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let numeric = Double(trimmed), numeric > 20_000, numeric < 100_000 {
            return cell.dateValue
        }
        if let iso = ISO8601DateFormatter().date(from: trimmed) { return iso }
        let formats = [
            "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd",
            "yyyy/MM/dd HH:mm:ss", "yyyy/MM/dd HH:mm", "yyyy/MM/dd",
            "yyyy年M月d日 HH:mm:ss", "yyyy年M月d日 HH:mm", "yyyy年M月d日"
        ]
        for format in formats {
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) { return date }
        }
        return nil
    }

    private static func parsedAmount(_ source: String) -> Decimal? {
        let trimmed = source
            .replacingOccurrences(of: "¥", with: "")
            .replacingOccurrences(of: "￥", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "元", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let parenthesized = trimmed.hasPrefix("(") && trimmed.hasSuffix(")")
        let numeric = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "+-()"))
        guard var amount = Decimal(string: numeric, locale: Locale(identifier: "en_US_POSIX")), amount.isFinite else { return nil }
        if amount < 0 || parenthesized { amount = -amount }
        return amount
    }

    private static func stableUUID(for key: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data(key.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        let uuid: uuid_t = (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        )
        return UUID(uuid: uuid)
    }

    private static func normalized(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .lowercased()
    }

    private static func containsAny(_ value: String, _ needles: [String]) -> Bool {
        needles.contains { value.contains(normalized($0)) }
    }
}
#endif
