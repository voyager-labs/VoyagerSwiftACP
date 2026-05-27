import ComposableArchitecture
import Foundation

public struct RegistryClient: Sendable {
    public var allProperties: @Sendable () -> [RegistrySnapshot.PropertyEntry]
    public var labelForKey: @Sendable (_ key: String) -> String
    public var propertyTypeString: @Sendable (_ key: String) -> String
    public var propertyUnitSpec: @Sendable (_ key: String) -> SystemPropertyUnitSpec?
    public var operatorCodes: @Sendable (_ key: String) -> [String]
    public var operatorDefinition: @Sendable (_ code: String) -> OperatorDefinition
    public var operatorValueUIKind: @Sendable (_ code: String, _ typeKey: String) -> String
    public var resolvePropertyKey: @Sendable (_ key: String) -> PropertyKeyResolution

    public init(
        allProperties: @escaping @Sendable () -> [RegistrySnapshot.PropertyEntry],
        labelForKey: @escaping @Sendable (_ key: String) -> String,
        propertyTypeString: @escaping @Sendable (_ key: String) -> String,
        propertyUnitSpec: @escaping @Sendable (_ key: String) -> SystemPropertyUnitSpec?,
        operatorCodes: @escaping @Sendable (_ key: String) -> [String],
        operatorDefinition: @escaping @Sendable (_ code: String) -> OperatorDefinition,
        operatorValueUIKind: @escaping @Sendable (_ code: String, _ typeKey: String) -> String,
        resolvePropertyKey: @escaping @Sendable (_ key: String) -> PropertyKeyResolution,
    ) {
        self.allProperties = allProperties
        self.labelForKey = labelForKey
        self.propertyTypeString = propertyTypeString
        self.propertyUnitSpec = propertyUnitSpec
        self.operatorCodes = operatorCodes
        self.operatorDefinition = operatorDefinition
        self.operatorValueUIKind = operatorValueUIKind
        self.resolvePropertyKey = resolvePropertyKey
    }
}

public enum PropertyKeyResolution: Equatable, Sendable {
    case canonical(String)
    case legacy(original: String, normalized: String)
    case unknown(String)
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

    func operatorUIKind(for code: String, typeKey: String) -> String {
        operatorValueUIKind(code, typeKey)
    }

    func resolveKey(_ key: String) -> PropertyKeyResolution {
        resolvePropertyKey(key)
    }

    func valueArity(for uiValueKind: String) -> Int {
        switch uiValueKind {
        case "rangeNumber", "rangeDate":
            2
        case "none":
            0
        default:
            1
        }
    }

    func valueType(for uiValueKind: String) -> String {
        switch uiValueKind {
        case "singleNumber", "rangeNumber", "listNumber":
            "number"
        case "singleDate", "rangeDate":
            "date"
        case "toggle":
            "boolean"
        case "listText":
            "string_list"
        default:
            "string"
        }
    }
}

extension RegistryClient: DependencyKey, TestDependencyKey {
    public static let liveValue: RegistryClient = live(snapshot: RegistrySnapshot.load())

    public nonisolated(unsafe) static var testValue: RegistryClient = .init(
        allProperties: { [] },
        labelForKey: { $0 },
        propertyTypeString: { _ in "unknown" },
        propertyUnitSpec: { _ in nil },
        operatorCodes: { _ in [] },
        operatorDefinition: { _ in
            preconditionFailure("operator 정의 누락")
        },
        operatorValueUIKind: { _, _ in
            preconditionFailure("operator ui_value_kind 누락")
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
    private nonisolated static func requiredValue<T>(
        from dictionary: [String: T],
        key: String,
        missingMessage: String,
    ) -> T {
        guard let value = dictionary[key] else {
            preconditionFailure("\(missingMessage): \(key)")
        }
        return value
    }

    private nonisolated static func resolveKey(
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

    static func live(snapshot: RegistrySnapshot) -> RegistryClient {
        let allProperties = snapshot.allProperties
        let labels = snapshot.propertyKeyToLabel
        let types = snapshot.propertyKeyToType
        let unitSpecs = snapshot.propertyKeyToUnitSpec
        let operatorMap = snapshot.operatorCodesByKey
        let operatorDefinitions = snapshot.operatorDefinitions
        let legacyKeyMap = snapshot.legacyKeyMap

        return RegistryClient(
            allProperties: { allProperties },
            labelForKey: { requiredValue(from: labels, key: $0, missingMessage: "ui_label 누락") },
            propertyTypeString: { requiredValue(from: types, key: $0, missingMessage: "type 누락") },
            propertyUnitSpec: { unitSpecs[$0] },
            operatorCodes: { requiredValue(from: operatorMap, key: $0, missingMessage: "operator 옵션 누락") },
            operatorDefinition: { requiredValue(from: operatorDefinitions, key: $0, missingMessage: "operator 정의 누락") },
            operatorValueUIKind: { code, typeKey in
                guard let definition = operatorDefinitions[code],
                      let uiValueKind = definition.uiValueKind?[typeKey]
                else {
                    preconditionFailure("operator ui_value_kind 누락: \(code) / \(typeKey)")
                }
                return uiValueKind
            },
            resolvePropertyKey: { resolveKey($0, labels: labels, legacyKeyMap: legacyKeyMap) },
        )
    }
}
