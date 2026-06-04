import Foundation

struct ParsedSystemKey {
    let prefix: String
    let symbol: String
}

enum SystemKeyParser {
    static func parse(_ key: String) -> ParsedSystemKey {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let separatorIndex = trimmed.firstIndex(of: ":") else {
            return ParsedSystemKey(prefix: "", symbol: trimmed)
        }

        let prefix = trimmed[..<separatorIndex]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let symbol = trimmed[trimmed.index(after: separatorIndex)...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return ParsedSystemKey(prefix: prefix, symbol: symbol)
    }
}
