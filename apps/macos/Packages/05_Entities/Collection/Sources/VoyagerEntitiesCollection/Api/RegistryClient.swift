import ComposableArchitecture
import Foundation

public struct RegistryClient: Sendable {
    public var allProperties: @Sendable () -> [RegistrySnapshot.PropertyEntry]
    public var labelForKey: @Sendable (_ key: String) -> String
    public var propertyTypeString: @Sendable (_ key: String) -> String
    public var propertyUnitSpec: @Sendable (_ key: String) -> SystemPropertyUnitSpec?
    public var operatorCodes: @Sendable (_ key: String) -> [String]
    public var operatorDefinition: @Sendable (_ code: String) -> OperatorDefinition
    public var resolvePropertyKey: @Sendable (_ key: String) -> PropertyKeyResolution
    private var resolveConditionValue: @Sendable (
        _ propertyKey: String,
        _ operatorCode: String?,
        _ values: [String]?,
        _ sourcePayload: CollectionCondition?,
    ) throws -> Condition

    public init(
        allProperties: @escaping @Sendable () -> [RegistrySnapshot.PropertyEntry],
        labelForKey: @escaping @Sendable (_ key: String) -> String,
        propertyTypeString: @escaping @Sendable (_ key: String) -> String,
        propertyUnitSpec: @escaping @Sendable (_ key: String) -> SystemPropertyUnitSpec?,
        operatorCodes: @escaping @Sendable (_ key: String) -> [String],
        operatorDefinition: @escaping @Sendable (_ code: String) -> OperatorDefinition,
        resolvePropertyKey: @escaping @Sendable (_ key: String) -> PropertyKeyResolution,
        resolveCondition: @escaping @Sendable (
            _ propertyKey: String,
            _ operatorCode: String?,
            _ values: [String]?,
            _ sourcePayload: CollectionCondition?,
        ) throws -> Condition = { _, _, _, _ in
            preconditionFailure("condition resolver is unavailable")
        },
    ) {
        self.allProperties = allProperties
        self.labelForKey = labelForKey
        self.propertyTypeString = propertyTypeString
        self.propertyUnitSpec = propertyUnitSpec
        self.operatorCodes = operatorCodes
        self.operatorDefinition = operatorDefinition
        self.resolvePropertyKey = resolvePropertyKey
        resolveConditionValue = resolveCondition
    }
}

public enum PropertyKeyResolution: Equatable, Sendable {
    case canonical(String)
    case legacy(original: String, normalized: String)
    case unknown(String)
}

private struct RegistryLiveContext {
    let allProperties: [RegistrySnapshot.PropertyEntry]
    let labels: [String: String]
    let types: [String: String]
    let unitSpecs: [String: SystemPropertyUnitSpec]
    let operatorMap: [String: [String]]
    let operatorDefinitions: [String: OperatorDefinition]
    let legacyKeyMap: [String: String]
    let propertiesByKey: [String: RegistrySnapshot.PropertyEntry]

    init(snapshot: RegistrySnapshot) {
        allProperties = snapshot.allProperties
        labels = snapshot.propertyKeyToLabel
        types = snapshot.propertyKeyToType
        unitSpecs = snapshot.propertyKeyToUnitSpec
        operatorMap = snapshot.operatorCodesByKey
        operatorDefinitions = snapshot.operatorDefinitions
        legacyKeyMap = snapshot.legacyKeyMap
        propertiesByKey = Dictionary(uniqueKeysWithValues: allProperties.map { ($0.key, $0) })
    }
}

public extension RegistryClient {
    func label(for key: String) -> String {
        labelForKey(key)
    }

    func propertyTypeString(for key: String) -> String {
        propertyTypeString(key)
    }

    func unitSpec(for key: String) -> SystemPropertyUnitSpec? {
        switch resolveKey(key) {
        case let .canonical(canonicalKey):
            propertyUnitSpec(canonicalKey)
        case let .legacy(_, normalized):
            propertyUnitSpec(normalized)
        case .unknown:
            nil
        }
    }

    func operatorCodes(for key: String) -> [String] {
        operatorCodes(key)
    }

    func operatorLabel(for code: String) -> String {
        operatorDefinition(code).uiLabel ?? code
    }

    func resolveKey(_ key: String) -> PropertyKeyResolution {
        resolvePropertyKey(key)
    }

    func resolveCondition(
        propertyKey: String,
        operatorCode: String?,
        values: [String]?,
        sourcePayload: CollectionCondition?,
    ) throws -> Condition {
        try resolveConditionValue(propertyKey, operatorCode, values, sourcePayload)
    }
}

extension RegistryClient: DependencyKey, TestDependencyKey {
    public static let liveValue: RegistryClient = live(snapshot: RegistrySnapshot.load())

    nonisolated(unsafe) public static var testValue: RegistryClient = .init(
        allProperties: { [] },
        labelForKey: { $0 },
        propertyTypeString: { _ in "unknown" },
        propertyUnitSpec: { _ in nil },
        operatorCodes: { _ in [] },
        operatorDefinition: { _ in
            preconditionFailure("operator 정의 누락")
        },
        resolvePropertyKey: { .canonical($0) },
    )
}

public extension DependencyValues {
    var registryClient: RegistryClient {
        get { self[RegistryClient.self] }
        set { self[RegistryClient.self] = newValue }
    }
}

public extension RegistryClient {
    nonisolated private static func requiredValue<T>(
        from dictionary: [String: T],
        key: String,
        missingMessage: String,
    ) -> T {
        guard let value = dictionary[key] else {
            preconditionFailure("\(missingMessage): \(key)")
        }
        return value
    }

    nonisolated private static func resolveKey(
        _ key: String,
        labels: [String: String],
        legacyKeyMap: [String: String],
    ) -> PropertyKeyResolution {
        if labels[key] != nil {
            return .canonical(key)
        }
        if let normalized = legacyKeyMap[key], labels[normalized] != nil {
            return .legacy(original: key, normalized: normalized)
        }
        return .unknown(key)
    }

    nonisolated private static func canonicalKey(
        for propertyKey: String,
        labels: [String: String],
        legacyKeyMap: [String: String],
    ) -> String? {
        switch resolveKey(propertyKey, labels: labels, legacyKeyMap: legacyKeyMap) {
        case let .canonical(key): key
        case let .legacy(_, normalized): normalized
        case .unknown: nil
        }
    }

    nonisolated private static func resolvedProperty(
        key: String,
        label: String,
        type: SystemPropertyTypeKey,
        context: RegistryLiveContext,
    ) -> Condition.Property {
        let options = (context.operatorMap[key] ?? []).compactMap { code -> Condition.OperatorOption? in
            guard let label = context.operatorDefinitions[code]?.uiLabel else { return nil }
            return Condition.OperatorOption(code: code, label: label)
        }
        return .init(
            key: key,
            label: label,
            type: type,
            unitContract: context.unitSpecs[key].flatMap(Condition.UnitContract.init),
            operatorOptions: options,
        )
    }

    nonisolated private static func resolvedOperation(
        propertyKey: String,
        operatorCode: String,
        type: SystemPropertyTypeKey,
        definition: OperatorDefinition,
    ) throws -> Condition.Operation {
        let valueContract = try RegistrySnapshot.validateConditionContract(
            propertyKey: propertyKey,
            operatorCode: operatorCode,
            type: type,
            definition: definition,
        )
        return .init(
            code: operatorCode,
            label: definition.uiLabel ?? operatorCode,
            valueContract: valueContract,
        )
    }

    nonisolated private static func defaultSourcePayload(
        propertyKey: String,
        operatorCode: String?,
        sourcePayload: CollectionCondition?,
    ) -> CollectionCondition {
        sourcePayload ?? .init(propertyKey: propertyKey, operatorCode: operatorCode ?? "", value: nil)
    }

    nonisolated private static func propertyEntry(
        for key: String,
        properties: [String: RegistrySnapshot.PropertyEntry],
        labels: [String: String],
    ) -> (RegistrySnapshot.PropertyEntry, String)? {
        guard let entry = properties[key], let label = labels[key] else { return nil }
        return (entry, label)
    }

    nonisolated private static func resolvedPropertyContext(
        for propertyKey: String,
        context: RegistryLiveContext,
    ) -> (canonicalKey: String, property: Condition.Property)? {
        guard let canonicalKey = canonicalKey(
            for: propertyKey,
            labels: context.labels,
            legacyKeyMap: context.legacyKeyMap,
        ), let (propertyEntry, label) = propertyEntry(
            for: canonicalKey,
            properties: context.propertiesByKey,
            labels: context.labels,
        ) else {
            return nil
        }
        let type = SystemPropertyTypeKey(rawType: propertyEntry.definition.type)
        let property = resolvedProperty(
            key: canonicalKey,
            label: label,
            type: type,
            context: context,
        )
        return (canonicalKey, property)
    }

    nonisolated private static func resolvedCondition(
        property: Condition.Property,
        operation: Condition.Operation,
        values: [String]?,
        sourcePayload: CollectionCondition?,
        originalSource: CollectionCondition,
    ) -> Condition {
        guard sourcePayload == nil || hasValidValueCount(values, contract: operation.valueContract) else {
            return .init(
                property: property,
                operation: operation,
                values: nil,
                availability: .invalidPersistedValue,
                opaqueSource: originalSource,
            )
        }
        return .init(
            property: property,
            operation: operation,
            values: values,
            availability: .available,
            opaqueSource: nil,
        )
    }

    static func live(snapshot: RegistrySnapshot) -> RegistryClient {
        let context = RegistryLiveContext(snapshot: snapshot)

        return RegistryClient(
            allProperties: { context.allProperties },
            labelForKey: { requiredValue(from: context.labels, key: $0, missingMessage: "ui_label 누락") },
            propertyTypeString: { requiredValue(from: context.types, key: $0, missingMessage: "type 누락") },
            propertyUnitSpec: { context.unitSpecs[$0] },
            operatorCodes: { requiredValue(from: context.operatorMap, key: $0, missingMessage: "operator 옵션 누락") },
            operatorDefinition: { requiredValue(
                from: context.operatorDefinitions,
                key: $0,
                missingMessage: "operator 정의 누락",
            )
            },
            resolvePropertyKey: { resolveKey($0, labels: context.labels, legacyKeyMap: context.legacyKeyMap) },
            resolveCondition: { propertyKey, operatorCode, values, sourcePayload in
                try resolveConditionValue(
                    propertyKey: propertyKey,
                    operatorCode: operatorCode,
                    values: values,
                    sourcePayload: sourcePayload,
                    context: context,
                )
            },
        )
    }

    nonisolated private static func resolveConditionValue(
        propertyKey: String,
        operatorCode: String?,
        values: [String]?,
        sourcePayload: CollectionCondition?,
        context: RegistryLiveContext,
    ) throws -> Condition {
        let originalSource = defaultSourcePayload(
            propertyKey: propertyKey,
            operatorCode: operatorCode,
            sourcePayload: sourcePayload,
        )
        guard let resolvedProperty = resolvedPropertyContext(for: propertyKey, context: context) else {
            return opaqueCondition(
                key: propertyKey,
                source: originalSource,
                availability: .unsupportedProperty,
            )
        }
        guard let operatorCode else {
            return Condition(
                property: resolvedProperty.property,
                operation: nil,
                values: nil,
                availability: .available,
                opaqueSource: nil,
            )
        }
        guard resolvedProperty.property.operatorOptions.contains(where: { $0.code == operatorCode }),
              let definition = context.operatorDefinitions[operatorCode]
        else {
            return Condition(
                property: resolvedProperty.property,
                operation: nil,
                values: nil,
                availability: .unsupportedOperator,
                opaqueSource: originalSource,
            )
        }
        let operation = try resolvedOperation(
            propertyKey: resolvedProperty.canonicalKey,
            operatorCode: operatorCode,
            type: resolvedProperty.property.type,
            definition: definition,
        )
        return resolvedCondition(
            property: resolvedProperty.property,
            operation: operation,
            values: values,
            sourcePayload: sourcePayload,
            originalSource: originalSource,
        )
    }

    nonisolated static func opaqueCondition(
        key: String,
        source: CollectionCondition,
        availability: Condition.Availability,
    ) -> Condition {
        Condition(
            property: .init(
                key: key,
                label: key,
                type: .unknown,
                unitContract: nil,
                operatorOptions: [],
            ),
            operation: nil,
            values: nil,
            availability: availability,
            opaqueSource: source,
        )
    }

    nonisolated private static func hasValidValueCount(
        _ values: [String]?,
        contract: Condition.ValueContract,
    ) -> Bool {
        switch contract.count {
        case .fixed(0):
            values == nil || values?.isEmpty == true
        case let .fixed(count):
            values?.count == count
        case .multiple:
            values?.isEmpty == false
        }
    }
}
