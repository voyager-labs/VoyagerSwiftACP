import Foundation

enum EntrySearchUtils {
    static func convertCollectionItems(
        _ items: [JSONValue],
        showHidden: Bool,
    ) -> [Entry] {
        let converted = items.compactMap(makeCollectionItem)
        guard !showHidden else { return converted }
        return converted.filter { !$0.isHidden }
    }

    private static func makeCollectionItem(_ value: JSONValue) -> Entry? {
        guard let payload = value.objectValue,
              let path = payload.stringValue(for: "path")
        else {
            return nil
        }

        let url = URL(fileURLWithPath: path)
        let name = payload.stringValue(for: "name") ?? url.lastPathComponent
        let fileExtension = payload.stringValue(for: "extension") ?? url.pathExtension
        let kind = payload.stringValue(for: "fileKind") ?? fallbackKind(for: fileExtension)
        let size = payload.doubleValue(for: "size").map(Int64.init) ?? 0
        let modifiedDate = SearchItemDateParser.parse(payload.stringValue(for: "modificationDate")) ?? .distantPast
        let createdDate = SearchItemDateParser.parse(payload.stringValue(for: "creationDate")) ?? modifiedDate
        let addedDate = SearchItemDateParser.parse(payload.stringValue(for: "addedDate")) ?? modifiedDate
        let lastOpenedDate = SearchItemDateParser.parse(payload.stringValue(for: "lastOpenedDate"))
        let isHidden = payload.boolValue(for: "isHidden") ?? name.hasPrefix(".")
        let isDirectory = payload.boolValue(for: "isDirectory") ?? false

        return Entry(
            name: name,
            fullPath: path,
            isDirectory: isDirectory,
            isHidden: isHidden,
            size: size,
            modifiedDate: modifiedDate,
            createdDate: createdDate,
            addedDate: addedDate,
            lastOpenedDate: lastOpenedDate,
            fileExtension: fileExtension,
            kind: kind,
            creatorApplication: nil,
            tags: nil,
            additionalInfo: nil,
        )
    }

    private static func fallbackKind(for fileExtension: String) -> String {
        fileExtension.isEmpty ? "File" : "\(fileExtension.uppercased()) File"
    }
}

private enum SearchItemDateParser {
    private static let isoFormatterWithFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let fallbackFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    private static let fallbackFormatterWithFractional: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSS"
        return formatter
    }()

    private static let fallbackFormatterWithOffset: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ssXXXXX"
        return formatter
    }()

    private static let fallbackFormatterWithFractionalAndOffset: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSSXXXXX"
        return formatter
    }()

    private static let dateOnlyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func parse(_ value: String?) -> Date? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else {
            return nil
        }

        if let date = isoFormatterWithFractional.date(from: value) {
            return date
        }
        if let date = isoFormatter.date(from: value) {
            return date
        }
        if let date = fallbackFormatterWithFractionalAndOffset.date(from: value) {
            return date
        }
        if let date = fallbackFormatterWithOffset.date(from: value) {
            return date
        }
        if let date = fallbackFormatterWithFractional.date(from: value) {
            return date
        }
        if let date = fallbackFormatter.date(from: value) {
            return date
        }
        return dateOnlyFormatter.date(from: value)
    }
}

private extension JSONValue {
    var stringValue: String? {
        guard case let .string(value) = self else { return nil }
        return value
    }

    var doubleValue: Double? {
        guard case let .number(value) = self else { return nil }
        return value
    }

    var boolValue: Bool? {
        guard case let .bool(value) = self else { return nil }
        return value
    }

    var objectValue: [String: JSONValue]? {
        guard case let .object(value) = self else { return nil }
        return value
    }
}

private extension [String: JSONValue] {
    func stringValue(for key: String) -> String? {
        self[key]?.stringValue
    }

    func doubleValue(for key: String) -> Double? {
        self[key]?.doubleValue
    }

    func boolValue(for key: String) -> Bool? {
        self[key]?.boolValue
    }
}
