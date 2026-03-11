import Foundation

struct ValueNormalizeResult: Equatable {
    /// 정상 변환된 값 배열 (전송용)
    let values: [String]?
    /// 에러 메시지 (nil이면 성공)
    let errorMessage: String?
    /// 에러 시 비울 인덱스 목록
    let resetIndices: [Int]
}

enum ValueNormalizerUtils {
    // 공용 날짜 포맷터 (ISO 8601, 초까지, UTC, Z 표기)
    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    // 날짜만 있는 경우 파싱용
    private static let dateOnlyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    // 시간까지 포함된 경우 (타임존 없음)
    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter
    }()

    private static let dateTimeSpaceFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    static func formatDate(_ date: Date) -> String {
        isoFormatter.string(from: normalizedDay(date))
    }

    static func formatDateOnly(_ date: Date) -> String {
        dateOnlyFormatter.string(from: normalizedDay(date))
    }

    static func formatDateOnlyString(_ text: String) -> String? {
        guard let date = parseDate(text) else { return nil }
        return formatDateOnly(date)
    }

    static func parseDate(_ text: String) -> Date? {
        if let date = isoFormatter.date(from: text) {
            return normalizedDay(date)
        }
        if let date = dateTimeFormatter.date(from: text) {
            return normalizedDay(date)
        }
        if let date = dateTimeSpaceFormatter.date(from: text) {
            return normalizedDay(date)
        }
        if let date = dateOnlyFormatter.date(from: text) {
            return normalizedDay(date)
        }
        return nil
    }

    private static func normalizedDay(_ date: Date) -> Date {
        // 캘린더 컴포넌트는 사용자의 현지 시간대를 기준으로 뽑고,
        // 최종 Date는 UTC 자정으로 고정해 날짜가 하루 당겨지지 않도록 맞춤.
        var localCalendar = Calendar(identifier: .gregorian)
        localCalendar.timeZone = .current
        let comps = localCalendar.dateComponents([.year, .month, .day], from: date)

        var utcCalendar = Calendar(identifier: .gregorian)
        if let utc = TimeZone(secondsFromGMT: 0) {
            utcCalendar.timeZone = utc
        }
        return utcCalendar.date(from: comps) ?? date
    }

    static func startOfDayString(for date: Date) -> String {
        let calendar = Calendar(identifier: .gregorian)
        let utc = TimeZone(secondsFromGMT: 0) ?? .current
        var components = calendar.dateComponents(in: utc, from: date)
        components.hour = 0
        components.minute = 0
        components.second = 0
        let start = calendar.date(from: components) ?? date
        return formatDate(start)
    }

    static func endOfDayString(for date: Date) -> String {
        let calendar = Calendar(identifier: .gregorian)
        let utc = TimeZone(secondsFromGMT: 0) ?? .current
        var components = calendar.dateComponents(in: utc, from: date)
        components.hour = 23
        components.minute = 59
        components.second = 59
        let end = calendar.date(from: components) ?? date
        return formatDate(end)
    }

    static func expectedArity(for kind: String) -> Int {
        switch kind {
        case "none":
            0
        case "rangeNumber", "rangeDate":
            2
        default:
            1
        }
    }

    static func normalize(
        kind: String,
        rawValues: [String],
        editingIndex: Int?,
    ) -> ValueNormalizeResult {
        switch kind {
        case "none":
            .init(values: [], errorMessage: nil, resetIndices: [])

        case "singleText":
            normalizeSingleText(rawValues: rawValues)

        case "listText":
            normalizeListText(rawValues: rawValues)

        case "singleNumber":
            normalizeSingleNumber(rawValues: rawValues)

        case "rangeNumber":
            normalizeRangeNumber(rawValues: rawValues, editingIndex: editingIndex)

        case "listNumber":
            normalizeListNumber(rawValues: rawValues)

        case "singleDate":
            normalizeSingleDate(rawValues: rawValues)

        case "rangeDate":
            normalizeRangeDate(rawValues: rawValues, editingIndex: editingIndex)

        case "toggle":
            normalizeToggle(rawValues: rawValues)

        default:
            normalizeSingleText(rawValues: rawValues)
        }
    }

    private static func requireNonEmpty(_ texts: [String]) -> [String]? {
        let trimmed = texts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        return trimmed.contains(where: \.isEmpty) ? nil : trimmed
    }

    private static func splitList(_ text: String) -> [String] {
        text
            .split(whereSeparator: { $0 == "," || $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func deduplicatedTokenValues(_ rawValues: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []

        for value in rawValues {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let normalized = trimmed.folding(options: [.caseInsensitive], locale: .current)
            if seen.insert(normalized).inserted {
                result.append(trimmed)
            }
        }

        return result
    }

    private static func normalizeSingleText(rawValues: [String]) -> ValueNormalizeResult {
        guard let trimmed = requireNonEmpty([rawValues.first ?? ""]) else {
            return .init(values: nil, errorMessage: "Value is required.", resetIndices: [0])
        }
        return .init(values: trimmed, errorMessage: nil, resetIndices: [])
    }

    private static func normalizeListText(rawValues: [String]) -> ValueNormalizeResult {
        let parts: [String] = rawValues.flatMap { splitList($0) }
        let empties = rawValues.enumerated()
            .compactMap {
                $0.element.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? $0.offset : nil
            }
        guard !parts.isEmpty else {
            return .init(
                values: nil,
                errorMessage: "Value is required.",
                resetIndices: empties.isEmpty ? [0] : empties,
            )
        }
        return .init(values: parts, errorMessage: nil, resetIndices: [])
    }

    private static func normalizeSingleNumber(rawValues: [String]) -> ValueNormalizeResult {
        guard let trimmed = requireNonEmpty([rawValues.first ?? ""]) else {
            return .init(values: nil, errorMessage: "Value is required.", resetIndices: [0])
        }
        guard Double(trimmed[0]) != nil else {
            return .init(values: nil, errorMessage: "Enter a valid number.", resetIndices: [0])
        }
        return .init(values: trimmed, errorMessage: nil, resetIndices: [])
    }

    private static func normalizeRangeNumber(
        rawValues: [String],
        editingIndex: Int?,
    ) -> ValueNormalizeResult {
        let values = rawValues + Array(repeating: "", count: max(0, 2 - rawValues.count))
        let trimmed = values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let numbers = trimmed.map(Double.init)
        let emptyIndices = trimmed.enumerated().compactMap { index, text in
            text.isEmpty ? index : nil
        }
        let invalidIndices = numbers.enumerated().compactMap { index, number in
            trimmed[index].isEmpty || number != nil ? nil : index
        }

        if invalidIndices.isEmpty == false {
            return .init(values: nil, errorMessage: "Enter valid numbers.", resetIndices: invalidIndices)
        }

        if emptyIndices.count == 1 {
            return .init(values: nil, errorMessage: nil, resetIndices: emptyIndices)
        }

        if let editingIndex,
           emptyIndices.contains(editingIndex),
           trimmed[editingIndex].isEmpty
        {
            return .init(values: nil, errorMessage: nil, resetIndices: emptyIndices)
        }

        guard emptyIndices.isEmpty else {
            return .init(values: nil, errorMessage: "Value is required.", resetIndices: emptyIndices)
        }

        return .init(values: trimmed, errorMessage: nil, resetIndices: [])
    }

    private static func normalizeListNumber(rawValues: [String]) -> ValueNormalizeResult {
        let parts: [String] = rawValues.flatMap { splitList($0) }
        let numbers = parts.compactMap(Double.init)
        guard !parts.isEmpty else {
            return .init(values: nil, errorMessage: "Value is required.", resetIndices: [0])
        }
        guard numbers.count == parts.count else {
            return .init(values: nil, errorMessage: "Enter valid numbers.", resetIndices: [0])
        }
        return .init(values: parts, errorMessage: nil, resetIndices: [])
    }

    private static func normalizeSingleDate(rawValues: [String]) -> ValueNormalizeResult {
        guard let trimmed = requireNonEmpty([rawValues.first ?? ""]) else {
            return .init(values: nil, errorMessage: "Value is required.", resetIndices: [0])
        }
        guard parseDate(trimmed[0]) != nil else {
            return .init(values: nil, errorMessage: "Enter a valid date.", resetIndices: [0])
        }
        return .init(values: trimmed, errorMessage: nil, resetIndices: [])
    }

    private static func normalizeRangeDate(
        rawValues: [String],
        editingIndex: Int?,
    ) -> ValueNormalizeResult {
        let values = rawValues + Array(repeating: "", count: max(0, 2 - rawValues.count))
        let trimmed = values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let parsed = trimmed.map(parseDate)
        let emptyIndices = trimmed.enumerated().compactMap { index, text in
            text.isEmpty ? index : nil
        }
        let invalidIndices = parsed.enumerated().compactMap { index, date in
            trimmed[index].isEmpty || date != nil ? nil : index
        }

        if invalidIndices.isEmpty == false {
            return .init(values: nil, errorMessage: "Enter valid dates.", resetIndices: invalidIndices)
        }

        if emptyIndices.count == 1 {
            return .init(values: nil, errorMessage: nil, resetIndices: emptyIndices)
        }

        if let editingIndex,
           emptyIndices.contains(editingIndex),
           trimmed[editingIndex].isEmpty
        {
            return .init(values: nil, errorMessage: nil, resetIndices: emptyIndices)
        }

        guard emptyIndices.isEmpty else {
            return .init(values: nil, errorMessage: "Value is required.", resetIndices: emptyIndices)
        }

        return .init(values: trimmed, errorMessage: nil, resetIndices: [])
    }

    private static func normalizeToggle(rawValues: [String]) -> ValueNormalizeResult {
        guard let first = rawValues.first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
            !first.isEmpty
        else {
            return .init(values: nil, errorMessage: "Value is required.", resetIndices: [0])
        }

        if first == "true" || first == "false" {
            return .init(values: [first], errorMessage: nil, resetIndices: [])
        }

        return .init(values: nil, errorMessage: "Enter true or false.", resetIndices: [0])
    }
}
