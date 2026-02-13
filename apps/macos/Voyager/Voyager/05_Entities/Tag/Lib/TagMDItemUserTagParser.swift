import Foundation

enum TagMDItemUserTagParser {
    // MDItem의 kMDItemUserTags 항목("name\ncolorCode")을 Tag로 변환합니다.
    nonisolated static func parse(_ rawTag: String) -> Tag? {
        let components = rawTag.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        guard let rawName = components.first else { return nil }

        let name = String(rawName).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }

        let colorCode = if components.count == 2 {
            Int(String(components[1]).trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        } else {
            0
        }

        return Tag(name: name, colorCode: colorCode)
    }
}
