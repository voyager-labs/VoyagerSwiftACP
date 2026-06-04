import Foundation

public struct RelativeDateConditionLiteral: Sendable, Equatable, Codable {
    public enum Direction: String, Sendable, Codable, Equatable {
        case past
        case future
    }

    public enum Unit: String, Sendable, Codable, Equatable {
        case day
        case week
        case month
        case year

        var displayName: String {
            switch self {
            case .day: "day"
            case .week: "week"
            case .month: "month"
            case .year: "year"
            }
        }

        var displayPluralName: String {
            switch self {
            case .day: "days"
            case .week: "weeks"
            case .month: "months"
            case .year: "years"
            }
        }

        var calendarComponent: Calendar.Component {
            switch self {
            case .day: .day
            case .week: .weekOfYear
            case .month: .month
            case .year: .year
            }
        }
    }

    public static let canonicalNamespace = "voyager.relativeDate"
    public static let canonicalVersion = "v1"

    public let direction: Direction
    public let amount: Int
    public let unit: Unit
    public let anchorDateLiteral: String

    public init(direction: Direction, amount: Int, unit: Unit, anchorDateLiteral: String) {
        self.direction = direction
        self.amount = amount
        self.unit = unit
        self.anchorDateLiteral = anchorDateLiteral.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public init?(canonicalLiteral: String) {
        guard let parsed = Self.parse(canonicalLiteral) else { return nil }
        self = parsed
    }

    public static func parse(_ text: String) -> RelativeDateConditionLiteral? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 6,
              parts[0] == canonicalNamespace,
              parts[1] == canonicalVersion,
              let direction = Direction(rawValue: parts[2]),
              let amount = Int(parts[3]),
              amount > 0,
              let unit = Unit(rawValue: parts[4]),
              isValidDateOnlyLiteral(parts[5])
        else {
            return nil
        }

        return RelativeDateConditionLiteral(
            direction: direction,
            amount: amount,
            unit: unit,
            anchorDateLiteral: parts[5],
        )
    }

    public static func encode(
        direction: Direction,
        amount: Int,
        unit: Unit,
        anchorDateLiteral: String,
    ) -> String? {
        guard amount > 0 else { return nil }
        let trimmedAnchor = anchorDateLiteral.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidDateOnlyLiteral(trimmedAnchor) else { return nil }
        return [
            canonicalNamespace,
            canonicalVersion,
            direction.rawValue,
            String(amount),
            unit.rawValue,
            trimmedAnchor,
        ].joined(separator: ":")
    }

    public func encodedLiteral() -> String? {
        Self.encode(
            direction: direction,
            amount: amount,
            unit: unit,
            anchorDateLiteral: anchorDateLiteral,
        )
    }

    public func displayText() -> String {
        Self.displayText(direction: direction, amount: amount, unit: unit, anchorDateLiteral: anchorDateLiteral)
    }

    public static func displayText(
        direction: Direction,
        amount: Int,
        unit: Unit,
        anchorDateLiteral _: String,
    ) -> String {
        guard amount > 0 else { return "Value" }
        let unitLabel = amount == 1 ? unit.displayName : unit.displayPluralName
        switch direction {
        case .past:
            return "\(amount) \(unitLabel) ago"
        case .future:
            return "In \(amount) \(unitLabel)"
        }
    }

    public func resolve(now: Date, calendar: Calendar = .current) -> Date? {
        let normalizedNow = DateNormalizerUtils.normalizedDay(now)
        let amount = direction == .past ? -amount : amount
        guard let resolved = calendar.date(
            byAdding: unit.calendarComponent,
            value: amount,
            to: normalizedNow,
        ) else {
            return nil
        }
        return DateNormalizerUtils.normalizedDay(resolved)
    }

    public var anchorDate: Date? {
        DateNormalizerUtils.parseDate(anchorDateLiteral)
    }

    private static func isValidDateOnlyLiteral(_ text: String) -> Bool {
        guard let date = DateNormalizerUtils.parseDate(text) else { return false }
        return DateNormalizerUtils.formatDateOnly(date) == text
    }
}
