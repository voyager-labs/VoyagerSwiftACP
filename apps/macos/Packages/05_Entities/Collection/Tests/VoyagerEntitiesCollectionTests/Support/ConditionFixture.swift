@_spi(Testing)
@testable import VoyagerEntitiesCollection

enum ConditionFixture {
    static func make(
        propertyKey: String,
        propertyLabel: String,
        propertyType: String,
        operatorCode: String? = nil,
        operatorLabel: String? = nil,
        contract: Condition.ValueContract? = nil,
        values: [String]? = nil,
        availability: Condition.Availability = .available,
    ) -> Condition {
        let property = Condition.Property(
            key: propertyKey,
            label: propertyLabel,
            type: .init(rawType: propertyType),
            unitContract: nil,
            operatorOptions: operatorCode.map { [.init(code: $0, label: operatorLabel ?? $0)] } ?? [],
        )
        let operation = operatorCode.map {
            Condition.Operation(
                code: $0,
                label: operatorLabel ?? $0,
                valueContract: contract ?? .init(shape: .single, count: .fixed(1), input: .singleText),
            )
        }
        return Condition(
            property: property,
            operation: operation,
            values: values,
            availability: availability,
            opaqueSource: nil,
        )
    }
}
