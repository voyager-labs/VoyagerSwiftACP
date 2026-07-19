import Foundation
import VoyagerShared

public struct ValueNormalizeResult: Equatable {
    public let values: [String]?
    public let errorMessage: String?
    public let resetIndices: [Int]

    public init(values: [String]?, errorMessage: String?, resetIndices: [Int]) {
        self.values = values
        self.errorMessage = errorMessage
        self.resetIndices = resetIndices
    }
}

public enum ConditionValueNormalizer {
    public static func formatDateOnly(_ date: Date) -> String {
        DateNormalizerUtils.formatDateOnly(date)
    }

    public static func formatDateOnlyString(_ text: String) -> String? {
        guard let date = DateNormalizerUtils.parseDate(text) else { return nil }
        return DateNormalizerUtils.formatDateOnly(date)
    }

    public static func canonicalSingleDateString(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let literal = RelativeDateConditionLiteral(canonicalLiteral: trimmed) { return literal.encodedLiteral() }
        if AppliedFilterValueUtils.isTodayFunctionLiteral(trimmed) { return trimmed }
        return formatDateOnlyString(trimmed)
    }

    public static func canonicalAbsoluteDateString(_ text: String) -> String? {
        formatDateOnlyString(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    public static func parseDate(_ text: String) -> Date? {
        DateNormalizerUtils.parseDate(text)
    }

    public static func normalize(
        contract: Condition.ValueContract,
        rawValues: [String],
        editingIndex: Int?,
    ) -> ValueNormalizeResult {
        switch contract.input {
        case .none: .init(values: [], errorMessage: nil, resetIndices: [])
        case .singleText: normalizeSingleText(rawValues)
        case .listText: normalizeListText(rawValues)
        case .singleNumber: normalizeSingleNumber(rawValues)
        case .rangeNumber: normalizeRangeNumber(rawValues, editingIndex: editingIndex)
        case .listNumber: normalizeListNumber(rawValues)
        case .singleDate: normalizeSingleDate(rawValues)
        case .rangeDate: normalizeRangeDate(rawValues, editingIndex: editingIndex)
        case .toggle: normalizeToggle(rawValues)
        }
    }

    public static func deduplicatedTokenValues(_ rawValues: [String]) -> [String] {
        var seen: Set<String> = []
        return rawValues.compactMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return seen.insert(trimmed.folding(options: [.caseInsensitive], locale: .current)).inserted ? trimmed : nil
        }
    }

    private static func required(_ texts: [String]) -> [String]? {
        let trimmed = texts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        return trimmed.contains(where: \.isEmpty) ? nil : trimmed
    }

    private static func listParts(_ values: [String]) -> [String] {
        values.flatMap { $0.split(whereSeparator: { $0 == "," || $0.isNewline }) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func normalizeSingleText(_ values: [String]) -> ValueNormalizeResult {
        guard let values = required([values.first ?? ""]) else { return .init(
            values: nil,
            errorMessage: "Value is required.",
            resetIndices: [0],
        ) }
        return .init(values: values, errorMessage: nil, resetIndices: [])
    }

    private static func normalizeListText(_ values: [String]) -> ValueNormalizeResult {
        let parts = listParts(values)
        guard !parts.isEmpty else { return .init(values: nil, errorMessage: "Value is required.", resetIndices: [0]) }
        return .init(values: parts, errorMessage: nil, resetIndices: [])
    }

    private static func normalizeSingleNumber(_ values: [String]) -> ValueNormalizeResult {
        guard let values = required([values.first ?? ""]) else { return .init(
            values: nil,
            errorMessage: "Value is required.",
            resetIndices: [0],
        ) }
        guard Double(values[0]) != nil else { return .init(
            values: nil,
            errorMessage: "Enter a valid number.",
            resetIndices: [0],
        ) }
        return .init(values: values, errorMessage: nil, resetIndices: [])
    }

    private static func normalizeRangeNumber(_ rawValues: [String], editingIndex: Int?) -> ValueNormalizeResult {
        let values = rawValues + Array(repeating: "", count: max(0, 2 - rawValues.count))
        let trimmed = values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let empty = trimmed.indices.filter { trimmed[$0].isEmpty }
        let invalid = trimmed.indices.filter { !trimmed[$0].isEmpty && Double(trimmed[$0]) == nil }
        if !invalid.isEmpty { return .init(values: nil, errorMessage: "Enter valid numbers.", resetIndices: invalid) }
        if empty.count == 1 || (editingIndex.flatMap { empty.contains($0) ? $0 : nil } != nil) { return .init(
            values: nil,
            errorMessage: nil,
            resetIndices: empty,
        ) }
        guard empty.isEmpty else { return .init(values: nil, errorMessage: "Value is required.", resetIndices: empty) }
        return .init(values: trimmed, errorMessage: nil, resetIndices: [])
    }

    private static func normalizeListNumber(_ values: [String]) -> ValueNormalizeResult {
        let parts = listParts(values)
        guard !parts.isEmpty else { return .init(values: nil, errorMessage: "Value is required.", resetIndices: [0]) }
        guard parts.allSatisfy({ Double($0) != nil }) else { return .init(
            values: nil,
            errorMessage: "Enter valid numbers.",
            resetIndices: [0],
        ) }
        return .init(values: parts, errorMessage: nil, resetIndices: [])
    }

    private static func normalizeSingleDate(_ values: [String]) -> ValueNormalizeResult {
        guard let values = required([values.first ?? ""]),
              let date = canonicalSingleDateString(values[0])
        else { return .init(
            values: nil,
            errorMessage: "Enter a valid date.",
            resetIndices: [0],
        ) }
        return .init(values: [date], errorMessage: nil, resetIndices: [])
    }

    private static func normalizeRangeDate(_ rawValues: [String], editingIndex: Int?) -> ValueNormalizeResult {
        let values = rawValues + Array(repeating: "", count: max(0, 2 - rawValues.count))
        let trimmed = values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let empty = trimmed.indices.filter { trimmed[$0].isEmpty }
        let invalid = trimmed.indices.filter { !trimmed[$0].isEmpty && canonicalAbsoluteDateString(trimmed[$0]) == nil }
        if !invalid.isEmpty { return .init(values: nil, errorMessage: "Enter valid dates.", resetIndices: invalid) }
        if empty.count == 1 || (editingIndex.flatMap { empty.contains($0) ? $0 : nil } != nil) { return .init(
            values: nil,
            errorMessage: nil,
            resetIndices: empty,
        ) }
        guard empty.isEmpty else { return .init(values: nil, errorMessage: "Value is required.", resetIndices: empty) }
        return .init(values: trimmed.compactMap(canonicalAbsoluteDateString), errorMessage: nil, resetIndices: [])
    }

    private static func normalizeToggle(_ values: [String]) -> ValueNormalizeResult {
        guard let value = values.first?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !value.isEmpty
        else { return .init(
            values: nil,
            errorMessage: "Value is required.",
            resetIndices: [0],
        ) }
        guard value == "true" || value == "false" else { return .init(
            values: nil,
            errorMessage: "Enter true or false.",
            resetIndices: [0],
        ) }
        return .init(values: [value], errorMessage: nil, resetIndices: [])
    }
}
