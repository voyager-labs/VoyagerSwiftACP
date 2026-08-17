import Foundation

public enum TagMDItemUserTagParser {
    /// MDItem의 kMDItemUserTags 항목("name\ncolorCode")을 Tag로 변환합니다.
    nonisolated public static func parse(_ rawTag: String) -> Tag? {
        let components = rawTag.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        guard let rawName = components.first else { return nil }

        let name = normalizedTagName(String(rawName))
        guard !name.isEmpty else { return nil }

        let colorCode = if components.count == 2 {
            Int(String(components[1]).trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        } else {
            0
        }

        return Tag(name: name, colorCode: colorCode)
    }

    nonisolated public static func parseRelaxed(_ rawTag: String, defaultColorCode: Int = 0) -> Tag? {
        // Only use parse() when input has color code format (contains newline).
        // For name-only input, use defaultColorCode directly.
        if rawTag.contains("\n") {
            return parse(rawTag)
        }

        let name = normalizedTagName(rawTag)
        guard !name.isEmpty else { return nil }
        return Tag(name: name, colorCode: defaultColorCode)
    }

    nonisolated private static func normalizedTagName(_ rawName: String) -> String {
        rawName.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
