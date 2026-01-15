import ComposableArchitecture
import Foundation

struct MDItemPropertyClient: Sendable {
    var fetchAll: @Sendable () async throws -> [MDItemProperty]
}

extension MDItemPropertyClient: DependencyKey, TestDependencyKey {
    static let liveValue = MDItemPropertyClient(
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

                    return MDItemProperty(
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

    nonisolated(unsafe) static var testValue: MDItemPropertyClient = .init(fetchAll: { [] })
}

extension DependencyValues {
    nonisolated var mdItemPropertyClient: MDItemPropertyClient {
        get { self[MDItemPropertyClient.self] }
        set { self[MDItemPropertyClient.self] = newValue }
    }
}
