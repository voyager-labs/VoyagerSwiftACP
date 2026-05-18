import Foundation
import VoyagerShared

public struct Condition: Equatable, Identifiable, Hashable, Sendable {
    public var propertyKey: String
    public var propertyLabel: String
    public var propertyType: String
    public var operatorCode: String?
    public var operatorLabel: String?
    public var operatorValueArity: Int?
    public var operatorValueUIKind: String?
    public var valueType: String = "unknown"
    public var values: [String]?
    public var isActive: Bool = true

    public var id: String { propertyKey }

    public var isSearchReady: Bool {
        guard isActive else { return false }
        guard operatorCode != nil else { return false }

        if let operatorValueArity, operatorValueArity == 0 {
            return true
        }

        guard let values, !values.isEmpty else { return false }
        return ConditionValueEncoder.encode(condition: self, values: values) != nil
    }

    public init(
        propertyKey: String,
        propertyLabel: String,
        propertyType: String,
        operatorCode: String? = nil,
        operatorLabel: String? = nil,
        operatorValueArity: Int? = nil,
        operatorValueUIKind: String? = nil,
        valueType: String = "unknown",
        values: [String]? = nil,
        isActive: Bool = true
    ) {
        self.propertyKey = propertyKey
        self.propertyLabel = propertyLabel
        self.propertyType = propertyType
        self.operatorCode = operatorCode
        self.operatorLabel = operatorLabel
        self.operatorValueArity = operatorValueArity
        self.operatorValueUIKind = operatorValueUIKind
        self.valueType = valueType
        self.values = values
        self.isActive = isActive
    }
}
