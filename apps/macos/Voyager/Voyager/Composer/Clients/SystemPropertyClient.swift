import ComposableArchitecture
import Foundation

struct SystemPropertyClient: Sendable {
    var fetchAll: @Sendable () async throws -> [SystemProperty]
}

extension SystemPropertyClient: DependencyKey, TestDependencyKey {
    static let liveValue = SystemPropertyClient(
        fetchAll: {
            await MainActor.run {
                let defaultKeys: Set<String> = [
                    "name",
                    "extension",
                    "size",
                    "modifiedAt",
                    "createdAt",
                    "addedAt",
                ]

                return ConditionMappingUtils.allProperties.map { info in
                    let type = ConditionOperatorMappingUtils.propertyType(for: info.key) ?? .string
                    let typeString = switch type {
                    case .string: "string"
                    case .number: "number"
                    case .datetime: "date"
                    case .boolean: "boolean"
                    case .array: "array"
                    }

                    return SystemProperty(
                        key: info.key,
                        label: info.label,
                        category: info.category.rawValue,
                        type: typeString,
                        isDefault: defaultKeys.contains(info.key),
                    )
                }
            }
        },
    )

    nonisolated(unsafe) static var testValue: SystemPropertyClient = .init(fetchAll: { [] })
}

extension DependencyValues {
    nonisolated var systemPropertyClient: SystemPropertyClient {
        get { self[SystemPropertyClient.self] }
        set { self[SystemPropertyClient.self] = newValue }
    }
}
