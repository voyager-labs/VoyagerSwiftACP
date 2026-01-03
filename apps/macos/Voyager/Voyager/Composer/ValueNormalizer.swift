import Foundation

struct ValueNormalizeResult: Equatable {
    /// 정상 변환된 값 배열 (전송용)
    let values: [String]?
    /// 에러 메시지 (nil이면 성공)
    let errorMessage: String?
    /// 에러 시 비울 인덱스 목록
    let resetIndices: [Int]
}

enum ValueNormalizer {
    // 공용 날짜 포맷터 (날짜만, 로컬 타임존)
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func formatDate(_ date: Date) -> String {
        dateFormatter.string(from: date)
    }

    static func parseDate(_ text: String) -> Date? {
        dateFormatter.date(from: text)
    }

    static func expectedArity(for kind: ValueUIKind) -> Int {
        switch kind {
        case .none: 0
        case .rangeNumber, .rangeDate: 2
        default: 1
        }
    }

    // swiftlint:disable cyclomatic_complexity function_body_length
    static func normalize(
        kind: ValueUIKind,
        rawValues: [String],
        editingIndex: Int?,
    ) -> ValueNormalizeResult {
        func requireNonEmpty(_ texts: [String]) -> [String]? {
            let trimmed = texts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            return trimmed.contains(where: \.isEmpty) ? nil : trimmed
        }

        func splitList(_ text: String) -> [String] {
            text
                .split(whereSeparator: { $0 == "," || $0.isNewline })
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }

        switch kind {
        case .none:
            return .init(values: [], errorMessage: nil, resetIndices: [])

        case .singleText:
            guard let trimmed = requireNonEmpty([rawValues.first ?? ""]) else {
                return .init(values: nil, errorMessage: "Value is required.", resetIndices: [0])
            }
            return .init(values: trimmed, errorMessage: nil, resetIndices: [])

        case .listText:
            let parts: [String] = rawValues
                .flatMap { splitList($0) }
            let empties = rawValues.enumerated()
                .compactMap { $0.element.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? $0.offset : nil }
            guard !parts.isEmpty else {
                return .init(
                    values: nil,
                    errorMessage: "Value is required.",
                    resetIndices: empties.isEmpty ? [0] : empties,
                )
            }
            return .init(values: parts, errorMessage: nil, resetIndices: [])

        case .singleNumber:
            guard let trimmed = requireNonEmpty([rawValues.first ?? ""]) else {
                return .init(values: nil, errorMessage: "Value is required.", resetIndices: [0])
            }
            guard Double(trimmed[0]) != nil else {
                return .init(values: nil, errorMessage: "Enter valid number.", resetIndices: [0])
            }
            return .init(values: trimmed, errorMessage: nil, resetIndices: [])

        case .rangeNumber:
            let vals = Array(rawValues.prefix(2))
            let trimmed = vals.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            let empties = trimmed.enumerated()
                .compactMap { $0.element.isEmpty ? $0.offset : nil }
            guard empties.isEmpty else {
                return .init(values: nil, errorMessage: "Value is required.", resetIndices: empties)
            }
            let numbers = trimmed.compactMap { Double($0) }
            guard numbers.count == trimmed.count else {
                let bad = trimmed.enumerated()
                    .compactMap { Double($0.element) == nil ? $0.offset : nil }
                return .init(
                    values: nil,
                    errorMessage: "Enter valid numbers.",
                    resetIndices: bad.isEmpty ? [0, 1] : bad,
                )
            }
            if numbers.count >= 2, numbers[0] > numbers[1] {
                let idx = editingIndex ?? 0
                return .init(values: nil, errorMessage: "From must be ≤ To.", resetIndices: [idx])
            }
            return .init(values: trimmed, errorMessage: nil, resetIndices: [])

        case .listNumber:
            let parts = splitList(rawValues.first ?? "")
            guard !parts.isEmpty else {
                return .init(values: nil, errorMessage: "Value is required.", resetIndices: [0])
            }
            let numbers = parts.compactMap { Double($0) }
            guard numbers.count == parts.count else {
                return .init(values: nil, errorMessage: "Enter valid numbers.", resetIndices: [0])
            }
            return .init(values: parts, errorMessage: nil, resetIndices: [])

        case .singleDate:
            guard let trimmed = requireNonEmpty([rawValues.first ?? ""]) else {
                return .init(values: nil, errorMessage: "Value is required.", resetIndices: [0])
            }
            guard parseDate(trimmed[0]) != nil else {
                return .init(values: nil, errorMessage: "Enter valid date.", resetIndices: [0])
            }
            return .init(values: trimmed, errorMessage: nil, resetIndices: [])

        case .rangeDate:
            let vals = Array(rawValues.prefix(2))
            let trimmed = vals.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            let empties = trimmed.enumerated()
                .compactMap { $0.element.isEmpty ? $0.offset : nil }

            if let editingIndex {
                if editingIndex == 0 {
                    guard !trimmed[0].isEmpty else {
                        return .init(values: nil, errorMessage: "Value is required.", resetIndices: [0])
                    }
                    guard let fromDate = parseDate(trimmed[0]) else {
                        return .init(values: nil, errorMessage: "Enter valid date.", resetIndices: [0])
                    }

                    if !trimmed[1].isEmpty {
                        guard let toDate = parseDate(trimmed[1]) else {
                            return .init(values: nil, errorMessage: "Enter valid date.", resetIndices: [1])
                        }
                        if fromDate > toDate {
                            return .init(values: nil, errorMessage: "From must be ≤ To.", resetIndices: [0])
                        }
                    }

                    return .init(values: trimmed, errorMessage: nil, resetIndices: [])
                } else {
                    guard !trimmed[1].isEmpty else {
                        return .init(values: nil, errorMessage: "Value is required.", resetIndices: [1])
                    }
                    guard let toDate = parseDate(trimmed[1]) else {
                        return .init(values: nil, errorMessage: "Enter valid date.", resetIndices: [1])
                    }
                    if !trimmed[0].isEmpty, let fromDate = parseDate(trimmed[0]) {
                        if fromDate > toDate {
                            return .init(values: nil, errorMessage: "From must be ≤ To.", resetIndices: [editingIndex])
                        }
                    } else if trimmed[0].isEmpty {
                        // From 없으면 To만 반영 (추후 From 입력 대비)
                        return .init(values: trimmed, errorMessage: nil, resetIndices: [])
                    }
                    return .init(values: trimmed, errorMessage: nil, resetIndices: [])
                }
            }

            if !empties.isEmpty {
                return .init(values: nil, errorMessage: "Value is required.", resetIndices: empties)
            }

            let dates = trimmed.compactMap { parseDate($0) }
            guard dates.count == trimmed.count else {
                let bad = trimmed.enumerated()
                    .compactMap { parseDate($0.element) == nil ? $0.offset : nil }
                return .init(values: nil, errorMessage: "Enter valid date.", resetIndices: bad.isEmpty ? [0, 1] : bad)
            }
            if dates.count >= 2, dates[0] > dates[1] {
                let idx = editingIndex ?? 0
                return .init(values: nil, errorMessage: "From must be ≤ To.", resetIndices: [idx])
            }
            return .init(values: trimmed, errorMessage: nil, resetIndices: [])

        case .toggle:
            guard let trimmed = requireNonEmpty([rawValues.first ?? ""]) else {
                return .init(values: nil, errorMessage: "Value is required.", resetIndices: [0])
            }
            let lowered = trimmed[0].lowercased()
            guard lowered == "true" || lowered == "false" else {
                return .init(values: nil, errorMessage: "Select true/false.", resetIndices: [0])
            }
            let normalized = lowered == "true" ? "True" : "False"
            return .init(values: [normalized], errorMessage: nil, resetIndices: [])
        }
    }
    // swiftlint:enable cyclomatic_complexity function_body_length
}
