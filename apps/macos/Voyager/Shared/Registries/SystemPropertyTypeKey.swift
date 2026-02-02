import Foundation

enum SystemPropertyTypeKey: String, Equatable, Sendable {
    case string
    case number
    case date
    case boolean
    case stringList = "string_list"
    case categorical
    case unknown

    init(rawType: String) {
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

    static func normalizedValueType(from rawType: String) -> String {
        SystemPropertyTypeKey(rawType: rawType).valueType
    }

    static func operatorKey(from rawType: String) -> String {
        SystemPropertyTypeKey(rawType: rawType).operatorKey
    }

    static func operatorKeyOrNil(from rawType: String) -> String? {
        SystemPropertyTypeKey(rawType: rawType).operatorKeyOrNil
    }

    var valueType: String {
        rawValue
    }

    var operatorKey: String {
        rawValue
    }

    var operatorKeyOrNil: String? {
        self == .unknown ? nil : rawValue
    }
}
