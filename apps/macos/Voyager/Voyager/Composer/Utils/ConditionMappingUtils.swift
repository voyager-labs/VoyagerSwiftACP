import Foundation

/// UI 라벨을 백엔드에서 기대하는 key/operator 코드로 매핑하는 유틸.
/// 프론트에서 선택한 라벨을 그대로 넘기지 말고 이 매핑을 통해 정규화해 사용한다.
enum ConditionMappingUtils {
    struct PropertyInfo {
        let key: String
        let label: String
        let category: String
        let type: String
        let isDefault: Bool
    }

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

    /// 프로퍼티 라벨 -> propertyKey (registry 기반)
    private static let propertyLabelToKey: [String: String] = {
        let labelToKey = propertyKeyToLabel.reduce(into: [String: String]()) { result, entry in
            let (key, label) = entry
            result[label] = key
            result[label.lowercased()] = key
        }
        return labelToKey
    }()

    /// propertyKey -> 라벨 (registry 기반)
    private static let propertyKeyToLabel: [String: String] = {
        guard let registrySnapshot else {
            return [:]
        }

        var mapping: [String: String] = [:]
        for (_, entries) in registrySnapshot.categories {
            for (key, definition) in entries {
                mapping[key] = resolvedLabel(for: key, definition: definition)
            }
        }
        return mapping
    }()

    /// 오퍼레이터 라벨 -> operator 코드
    private static let operatorLabelToCode: [String: String] = {
        guard let conditionRegistrySnapshot else {
            return [:]
        }

        var mapping: [String: String] = [:]
        for (code, definition) in conditionRegistrySnapshot.operators {
            if let label = definition.uiLabel {
                mapping[label] = code
                mapping[label.lowercased()] = code
            }
            if let aliases = definition.aliases {
                for alias in aliases {
                    mapping[alias] = code
                    mapping[alias.lowercased()] = code
                }
            }
        }
        return mapping
    }()

    /// 라벨을 키로 변환. 없는 경우 nil.
    static func propertyKey(for label: String) -> String? {
        propertyLabelToKey[label] ?? propertyLabelToKey[label.lowercased()]
    }

    /// 백엔드 키를 라벨로 변환. 매핑에 없으면 캐멀/스네이크를 Title Case로 변환한 기본 라벨을 돌려준다.
    static func defaultLabel(forKey key: String) -> String {
        propertyKeyToLabel[key] ?? fallbackLabel(forKey: key)
    }

    private static func fallbackLabel(forKey key: String) -> String {
        // fallback: camelCase/snake_case -> Sentence Case
        let spaced = key
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
        return spaced.prefix(1).uppercased() + spaced.dropFirst()
    }

    static func operatorCode(for label: String) -> String? {
        operatorLabelToCode[label] ?? operatorLabelToCode[label.lowercased()]
    }

    static func categoryLabel(for key: String) -> String {
        fallbackLabel(forKey: key)
    }

    /// 매핑에 정의된 모든 프로퍼티 정보를 반환한다.
    static var allProperties: [PropertyInfo] {
        guard let registrySnapshot else {
            return []
        }

        let properties = registrySnapshot.categories.flatMap { categoryKey, entries in
            entries.map { key, definition in
                PropertyInfo(
                    key: key,
                    label: resolvedLabel(for: key, definition: definition),
                    category: categoryKey,
                    type: definition.type,
                    isDefault: definition.uiPinned ?? false,
                )
            }
        }

        return properties.sorted {
            $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending
        }
    }

    private static func resolvedLabel(
        for key: String,
        definition: SystemPropertyRegistry.SystemPropertyDefinition,
    ) -> String {
        if let label = definition.uiLabel, !label.isEmpty {
            return label
        }
        return fallbackLabel(forKey: key)
    }
}
