import Foundation

nonisolated struct PropertyConditionRegistry: Decodable {
    let kind: String?
    let version: String?
    let propertyTypes: [String: PropertyType]
    let operators: [String: OperatorDefinition]

    private enum CodingKeys: String, CodingKey {
        case kind = "$kind"
        case version = "$version"
        case propertyTypes = "property_types"
        case operators
    }
}

nonisolated struct PropertyType: Decodable {
    let operators: [String]
}

nonisolated struct OperatorDefinition: Decodable {
    let uiLabel: String?
    let mdqueryOperator: String?
    let valueShape: ValueShape?
    let valueCount: ValueCount?
    let allowedTypes: [String]?
    let inverseOf: String?
    let aliases: [String]?
    let uiValueKind: [String: String]?

    private enum CodingKeys: String, CodingKey {
        case uiLabel = "ui_label"
        case mdqueryOperator = "mdquery_operator"
        case valueShape = "value_shape"
        case valueCount = "value_count"
        case allowedTypes = "allowed_types"
        case inverseOf = "inverse_of"
        case aliases
        case uiValueKind = "ui_value_kind"
    }
}

nonisolated enum ValueShape: String, Decodable {
    case none
    case single
    case list
    case range
}

nonisolated enum ValueCount: Decodable, Equatable {
    case fixed(Int)
    case multiple

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intValue = try? container.decode(Int.self) {
            self = .fixed(intValue)
            return
        }
        let text = try container.decode(String.self)
        if text == "n" {
            self = .multiple
            return
        }
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Unsupported value_count: \(text)",
        )
    }
}
