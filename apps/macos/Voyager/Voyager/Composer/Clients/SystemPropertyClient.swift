import ComposableArchitecture
import Foundation

struct SystemPropertyClient: Sendable {
    var fetchAll: @Sendable () async throws -> [SystemProperty]
}

extension SystemPropertyClient: DependencyKey, TestDependencyKey {
    static let liveValue = SystemPropertyClient(
        fetchAll: {
            await MainActor.run {
                ConditionMappingUtils.allProperties.map { info in
                    SystemProperty(
                        key: info.key,
                        label: info.label,
                        category: info.category,
                        type: info.type,
                        isDefault: info.isDefault,
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
