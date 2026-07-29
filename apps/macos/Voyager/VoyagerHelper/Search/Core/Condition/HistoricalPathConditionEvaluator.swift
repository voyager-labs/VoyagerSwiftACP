import Foundation
import VoyagerEntitiesCollection
import VoyagerShared

enum HistoricalPathConditionEvaluator {
    static func matches(
        _ path: String,
        conditions: [SearchConditionPayload],
        homeURL: URL,
    ) -> Bool {
        let values = PathValues(path: path, homeURL: homeURL)
        return conditions.allSatisfy { condition in
            guard let resolution = HistoricalConditionCompatibility.resolution(
                for: condition,
                canonicalPropertyKey: condition.propertyKey,
            ),
                resolution.isPathDerived
            else {
                return false
            }
            switch resolution.propertyType {
            case .number:
                return matchesNumber(values.number(for: resolution.propertyKey), condition: condition)
            default:
                return matchesString(values.string(for: resolution.propertyKey), condition: condition)
            }
        }
    }
}

private extension HistoricalPathConditionEvaluator {
    struct PathValues {
        let directoryPath: String
        let parentDirectoryName: String
        let depthFromHome: Double
        let relativePathFromHome: String?

        init(path: String, homeURL: URL) {
            let targetURL = URL(fileURLWithPath: path).standardizedFileURL
            let parentURL = targetURL.deletingLastPathComponent()
            directoryPath = parentURL.path
            parentDirectoryName = parentURL.lastPathComponent

            let homePath = homeURL.standardizedFileURL.path
            let targetPath = targetURL.path
            guard targetPath == homePath || targetPath.hasPrefix(homePath + "/") else {
                depthFromHome = -1
                relativePathFromHome = nil
                return
            }
            let relative = targetPath.dropFirst(homePath.count).trimmingCharacters(
                in: CharacterSet(charactersIn: "/"),
            )
            guard relative.isEmpty == false else {
                depthFromHome = -1
                relativePathFromHome = "~/"
                return
            }
            depthFromHome = Double(max(-1, relative.split(separator: "/").count - 1))
            relativePathFromHome = "~/" + relative
        }

        func string(for key: String) -> String? {
            switch key {
            case "dir_path": directoryPath
            case "parent_dir_name": parentDirectoryName
            case "relative_path_from_home": relativePathFromHome
            default: nil
            }
        }

        func number(for key: String) -> Double? {
            key == "depth_from_home" ? depthFromHome : nil
        }
    }

    static func matchesString(
        _ candidate: String?,
        condition: SearchConditionPayload,
    ) -> Bool {
        switch condition.operator {
        case "exists": return candidate != nil
        case "empty": return candidate?.isEmpty != false
        default: break
        }
        guard let candidate else { return false }

        let values = stringValues(condition.value)
        guard values.isEmpty == false else { return false }
        if ["any", "all", "none", "miss"].contains(condition.operator) {
            return matchesStringList(candidate, values: values, operatorCode: condition.operator)
        }
        return matchesSingleString(candidate, value: values[0], operatorCode: condition.operator)
    }

    static func matchesSingleString(
        _ candidate: String,
        value: String,
        operatorCode: String,
    ) -> Bool {
        switch operatorCode {
        case "eq": candidate == value
        case "neq": candidate != value
        case "cn": candidate.contains(value)
        case "nc": candidate.contains(value) == false
        case "sw": candidate.hasPrefix(value)
        case "ew": candidate.hasSuffix(value)
        case "rx": matchesWildcardPattern(candidate, pattern: value)
        default: false
        }
    }

    static func matchesWildcardPattern(_ candidate: String, pattern: String) -> Bool {
        let normalized = pattern
            .replacingOccurrences(of: "\\.\\*", with: "*")
            .replacingOccurrences(of: ".*", with: "*")
            .replacingOccurrences(of: "%", with: "*")
        let escaped = normalized
            .split(separator: "*", omittingEmptySubsequences: false)
            .map { NSRegularExpression.escapedPattern(for: String($0)) }
            .joined(separator: ".*")
        guard let expression = try? NSRegularExpression(pattern: "^\(escaped)$") else { return false }
        let range = NSRange(candidate.startIndex ..< candidate.endIndex, in: candidate)
        return expression.firstMatch(in: candidate, range: range) != nil
    }

    static func matchesStringList(
        _ candidate: String,
        values: [String],
        operatorCode: String,
    ) -> Bool {
        switch operatorCode {
        case "any": values.contains(where: candidate.contains)
        case "all": values.allSatisfy(candidate.contains)
        case "none": values.allSatisfy { candidate.contains($0) == false }
        case "miss": values.contains { candidate.contains($0) == false }
        default: false
        }
    }

    static func matchesNumber(
        _ candidate: Double?,
        condition: SearchConditionPayload,
    ) -> Bool {
        if let result = matchesNumberPresence(candidate, operatorCode: condition.operator) {
            return result
        }
        guard let candidate else { return false }
        return matchesNumberComparison(candidate, condition: condition)
    }

    static func matchesNumberPresence(_ candidate: Double?, operatorCode: String) -> Bool? {
        switch operatorCode {
        case "exists": candidate != nil
        case "empty": candidate == nil
        default: nil
        }
    }

    static func matchesNumberComparison(
        _ candidate: Double,
        condition: SearchConditionPayload,
    ) -> Bool {
        let values = numberValues(condition.value)
        switch (condition.operator, values.count) {
        case ("eq", 1): return candidate == values[0]
        case ("neq", 1): return candidate != values[0]
        case ("gt", 1): return candidate > values[0]
        case ("gte", 1): return candidate >= values[0]
        case ("lt", 1): return candidate < values[0]
        case ("lte", 1): return candidate <= values[0]
        case ("btw", 2): return candidate >= min(values[0], values[1]) && candidate <= max(values[0], values[1])
        case ("nbtw", 2): return candidate < min(values[0], values[1]) || candidate > max(values[0], values[1])
        default: return false
        }
    }

    static func stringValues(_ value: JSONValue?) -> [String] {
        switch value {
        case let .string(text)?: [text]
        case let .array(values)?: values.compactMap { if case let .string(text) = $0 { text } else { nil } }
        default: []
        }
    }

    static func numberValues(_ value: JSONValue?) -> [Double] {
        switch value {
        case let .number(number)?: [number]
        case let .array(values)?: values.compactMap { if case let .number(number) = $0 { number } else { nil } }
        default: []
        }
    }
}
