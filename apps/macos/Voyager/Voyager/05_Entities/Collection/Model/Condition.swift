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
}
