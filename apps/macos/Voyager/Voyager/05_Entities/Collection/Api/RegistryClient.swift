import ComposableArchitecture
import Foundation

struct RegistryClient: Sendable {
    var allProperties: @Sendable () -> [RegistrySnapshot.PropertyEntry]
    var labelForKey: @Sendable (_ key: String) -> String
    var propertyTypeString: @Sendable (_ key: String) -> String
    var operatorCodes: @Sendable (_ key: String) -> [String]
    var operatorDefinition: @Sendable (_ code: String) -> OperatorDefinition
    var operatorValueUIKind: @Sendable (_ code: String, _ typeKey: String) -> String
    var resolvePropertyKey: @Sendable (_ key: String) -> PropertyKeyResolution
}

enum PropertyKeyResolution: Equatable, Sendable {
    case canonical(String)
    case legacy(original: String, normalized: String)
    case unknown(String)
}

extension RegistryClient {
    func label(for key: String) -> String {
        labelForKey(key)
    }

    func propertyTypeString(for key: String) -> String {
        propertyTypeString(key)
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
    static let liveValue: RegistryClient = live(snapshot: RegistrySnapshot.load())

    nonisolated(unsafe) static var testValue: RegistryClient = .init(
        allProperties: { [] },
        labelForKey: { $0 },
        propertyTypeString: { _ in "unknown" },
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

extension DependencyValues {
    nonisolated var registryClient: RegistryClient {
        get { self[RegistryClient.self] }
        set { self[RegistryClient.self] = newValue }
    }
}

extension RegistryClient {
    static func live(snapshot: RegistrySnapshot) -> RegistryClient {
        let allProperties = snapshot.allProperties
        let labels = snapshot.propertyKeyToLabel
        let types = snapshot.propertyKeyToType
        let operatorMap = snapshot.operatorCodesByKey
        let operatorDefinitions = snapshot.operatorDefinitions
        let legacyKeyMap = snapshot.legacyKeyMap

        return RegistryClient(
            allProperties: { allProperties },
            labelForKey: { key in
                guard let label = labels[key] else {
                    preconditionFailure("ui_label 누락: \(key)")
                }
                return label
            },
            propertyTypeString: { key in
                guard let type = types[key] else {
                    preconditionFailure("type 누락: \(key)")
                }
                return type
            },
            operatorCodes: { key in
                guard let options = operatorMap[key] else {
                    preconditionFailure("operator 옵션 누락: \(key)")
                }
                return options
            },
            operatorDefinition: { code in
                guard let definition = operatorDefinitions[code] else {
                    preconditionFailure("operator 정의 누락: \(code)")
                }
                return definition
            },
            operatorValueUIKind: { code, typeKey in
                guard let definition = operatorDefinitions[code],
                      let uiValueKind = definition.uiValueKind?[typeKey]
                else {
                    preconditionFailure("operator ui_value_kind 누락: \(code) / \(typeKey)")
                }
                return uiValueKind
            },
            resolvePropertyKey: { key in
                if labels[key] != nil {
                    return .canonical(key)
                }
                if let normalized = legacyKeyMap[key], labels[normalized] != nil {
                    return .legacy(original: key, normalized: normalized)
                }
                return .unknown(key)
            },
        )
    }
}
