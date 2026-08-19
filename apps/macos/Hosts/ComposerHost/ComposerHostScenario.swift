import Foundation

public struct ComposerHostScenario: Sendable, Equatable {
    public let preset: ComposerHostPreset
    public let title: String

    public var id: String {
        preset.rawValue
    }

    public init(preset: ComposerHostPreset, title: String) {
        self.preset = preset
        self.title = title
    }
}

public enum ComposerHostPreset: String, CaseIterable, Sendable, Hashable {
    case empty
    case propertyMenu
    case textValue
    case numberRange
    case boolean
    case tokenList
    case dateRange

    public var title: String {
        scenario.title
    }

    public var scenario: ComposerHostScenario {
        switch self {
        case .empty:
            .init(preset: self, title: "Empty")
        case .propertyMenu:
            .init(preset: self, title: "Property Menu")
        case .textValue:
            .init(preset: self, title: "Text Value")
        case .numberRange:
            .init(preset: self, title: "Number Range")
        case .boolean:
            .init(preset: self, title: "Boolean")
        case .tokenList:
            .init(preset: self, title: "Token List")
        case .dateRange:
            .init(preset: self, title: "Date Range")
        }
    }

    public static func resolve(_ rawValue: String?) -> Self {
        guard let rawValue, let preset = Self(rawValue: rawValue) else {
            return .empty
        }
        return preset
    }
}
