struct Condition: Equatable, Identifiable, Hashable, Sendable {
    var propertyKey: String
    var propertyLabel: String
    var propertyType: String
    var operatorCode: String?
    var operatorLabel: String?
    var operatorValueArity: Int?
    var operatorValueUIKind: String?
    var valueType: String = "unknown"
    var values: [String]?
    var isActive: Bool = true

    var id: String { propertyKey }

    var isSearchReady: Bool {
        guard isActive else { return false }
        guard operatorCode != nil else { return false }

        if let arity = operatorValueArity, arity == 0 {
            return true
        }

        guard let values, !values.isEmpty else { return false }
        return ConditionValueEncoder.encode(condition: self, values: values) != nil
    }
}
