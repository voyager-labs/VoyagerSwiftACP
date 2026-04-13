import Foundation

public enum SystemPropertyTypeKey: String, Equatable, Sendable {
    case string
    case number
    case date
    case boolean
    case stringList = "string_list"
    case categorical
    case unknown

    public var valueType: String {
        rawValue
    }

    public var operatorKey: String {
        rawValue
    }

    public var operatorKeyOrNil: String? {
        self == .unknown ? nil : rawValue
    }

    public init(rawType: String) {
        switch rawType.lowercased() {
        case "string":
            self = .string
        case "number":
            self = .number
        case "date":
            self = .date
        case "boolean":
            self = .boolean
        case "string_list":
            self = .stringList
        case "categorical":
            self = .categorical
        default:
            self = .unknown
        }
    }

    public static func normalizedValueType(from rawType: String) -> String {
        SystemPropertyTypeKey(rawType: rawType).valueType
    }

    public static func operatorKey(from rawType: String) -> String {
        SystemPropertyTypeKey(rawType: rawType).operatorKey
    }

    public static func operatorKeyOrNil(from rawType: String) -> String? {
        SystemPropertyTypeKey(rawType: rawType).operatorKeyOrNil
    }
}
