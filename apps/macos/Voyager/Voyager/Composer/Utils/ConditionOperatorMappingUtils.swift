import Foundation

enum PropertyType {
    case string
    case number
    case datetime
    case boolean
    case stringList
}

enum ValueUIKind {
    case none // 값 없이 사용 (empty/not_empty)
    case singleText // 단일 텍스트
    case singleNumber // 단일 숫자
    case singleDate // 단일 날짜/시간
    case rangeNumber // 숫자 범위 (min,max)
    case rangeDate // 날짜 범위 (from,to)
    case listText // 문자열 목록
    case listNumber // 숫자 목록
    case toggle // 불린 토글
}

struct OperatorUIOption {
    let code: String // 백엔드 operator 코드
    let label: String // UI 표시 라벨
    let valueUI: ValueUIKind
}

enum ConditionOperatorMappingUtils {
    private static let registrySnapshot: SystemPropertyRegistry? = {
        do {
            return try SystemPropertyRegistryLoader.load()
        } catch {
            return nil
        }
    }()

    private static let conditionRegistrySnapshot: PropertyConditionRegistry? = {
        do {
            return try PropertyConditionRegistryLoader.load()
        } catch {
            return nil
        }
    }()

    private static let propertyKeyToType: [String: PropertyType] = {
        guard let registrySnapshot else {
            return [:]
        }

        var mapping: [String: PropertyType] = [:]
        for (_, entries) in registrySnapshot.categories {
            for (key, definition) in entries {
                guard let type = propertyType(from: definition.type) else {
                    continue
                }
                mapping[key] = type
            }
        }

        return mapping
    }()

    private static let propertyKeyToSupported: [String: [String]] = {
        guard let registrySnapshot, let conditionRegistrySnapshot else {
            return [:]
        }

        var mapping: [String: [String]] = [:]
        for (_, entries) in registrySnapshot.categories {
            for (key, definition) in entries {
                guard let type = propertyType(from: definition.type) else {
                    continue
                }
                let typeKey = conditionTypeKey(for: type)
                guard let operators = conditionRegistrySnapshot.typeDefaults[typeKey] else {
                    continue
                }
                mapping[key] = operators
            }
        }

        return mapping
    }()

    private static let propertyKeyToTypeString: [String: String] = {
        guard let registrySnapshot else {
            return [:]
        }

        var mapping: [String: String] = [:]
        for (_, entries) in registrySnapshot.categories {
            for (key, definition) in entries {
                mapping[key] = definition.type
            }
        }
        return mapping
    }()

    private static func propertyType(from valueType: String) -> PropertyType? {
        switch valueType.lowercased() {
        case "string":
            .string
        case "number":
            .number
        case "date", "datetime":
            .datetime
        case "boolean":
            .boolean
        case "string_list":
            .stringList
        default:
            nil
        }
    }

    private static func conditionTypeKey(for type: PropertyType) -> String {
        switch type {
        case .string:
            "string"
        case .number:
            "number"
        case .datetime:
            "date"
        case .boolean:
            "boolean"
        case .stringList:
            "string_list"
        }
    }

    private static func valueUIKind(from raw: String) -> ValueUIKind? {
        switch raw {
        case "none":
            .none
        case "singleText":
            .singleText
        case "singleNumber":
            .singleNumber
        case "singleDate":
            .singleDate
        case "rangeNumber":
            .rangeNumber
        case "rangeDate":
            .rangeDate
        case "listText":
            .listText
        case "listNumber":
            .listNumber
        case "toggle":
            .toggle
        default:
            nil
        }
    }

    private static func registryOperators(for type: PropertyType) -> [OperatorUIOption]? {
        guard let conditionRegistrySnapshot else {
            return nil
        }

        let typeKey = conditionTypeKey(for: type)
        guard let operatorCodes = conditionRegistrySnapshot.typeDefaults[typeKey] else {
            return nil
        }

        let options = operatorCodes.compactMap { code -> OperatorUIOption? in
            guard let definition = conditionRegistrySnapshot.operators[code],
                  let valueUIKey = definition.uiValueKind?[typeKey],
                  let valueUI = valueUIKind(from: valueUIKey)
            else {
                return nil
            }
            guard let label = definition.uiLabel else {
                return nil
            }
            return OperatorUIOption(code: code, label: label, valueUI: valueUI)
        }

        return options.isEmpty ? nil : options
    }

    /// propertyKey로 타입을 찾고 허용 오퍼레이터 목록을 반환
    static func operatorOptions(for propertyKey: String) -> [OperatorUIOption] {
        guard let type = propertyKeyToType[propertyKey] else {
            return []
        }
        let options = registryOperators(for: type) ?? []
        guard let supported = propertyKeyToSupported[propertyKey] else {
            return options
        }
        return options.filter { supported.contains($0.code) }
    }

    /// propertyKey에 대응하는 타입을 노출 (외부에서 모델 생성 시 사용).
    static func propertyType(for propertyKey: String) -> PropertyType? {
        propertyKeyToType[propertyKey]
    }

    /// propertyKey에 대응하는 타입 문자열을 반환 (UI 모델용).
    static func propertyTypeString(for propertyKey: String) -> String {
        propertyKeyToTypeString[propertyKey] ?? "unknown"
    }

    /// operator 코드와 타입 조합으로 값 UI 힌트를 반환
    static func valueUI(for operatorCode: String, propertyKey: String) -> ValueUIKind {
        guard let type = propertyKeyToType[propertyKey] else {
            return .singleText
        }
        return registryOperators(for: type)?.first { $0.code == operatorCode }?.valueUI ?? .singleText
    }
}
