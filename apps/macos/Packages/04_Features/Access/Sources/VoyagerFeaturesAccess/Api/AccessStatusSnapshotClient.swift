import ComposableArchitecture
import Foundation
import VoyagerEntitiesAppPreferences
import VoyagerShared

public struct AccessStatusSnapshotClient: Sendable {
    public var load: @Sendable () async -> AccessStatusSnapshot?
    public var save: @Sendable (_ snapshot: AccessStatusSnapshot) async -> Void
    public var remove: @Sendable () async -> Void

    public nonisolated init(
        load: @escaping @Sendable () async -> AccessStatusSnapshot?,
        save: @escaping @Sendable (_ snapshot: AccessStatusSnapshot) async -> Void,
        remove: @escaping @Sendable () async -> Void,
    ) {
        self.load = load
        self.save = save
        self.remove = remove
    }
}

extension AccessStatusSnapshotClient: DependencyKey {
    public nonisolated static var liveValue: AccessStatusSnapshotClient {
        AccessStatusSnapshotClient(
            load: {
                @Dependency(\.userDefaultsClient)
                var userDefaults
                guard let data = userDefaults.object(SettingsKeys.accessStatusSnapshot) as? Data else {
                    return nil
                }
                return try? JSONDecoder().decode(AccessStatusSnapshot.self, from: data)
            },
            save: { snapshot in
                @Dependency(\.userDefaultsClient)
                var userDefaults
                guard let data = try? JSONEncoder().encode(snapshot) else { return }
                userDefaults.setObject(data, SettingsKeys.accessStatusSnapshot)
            },
            remove: {
                @Dependency(\.userDefaultsClient)
                var userDefaults
                userDefaults.setObject(nil, SettingsKeys.accessStatusSnapshot)
            },
        )
    }

    public nonisolated static var testValue: AccessStatusSnapshotClient {
        AccessStatusSnapshotClient(
            load: { nil },
            save: { _ in },
            remove: {},
        )
    }

    public nonisolated static var previewValue: AccessStatusSnapshotClient {
        testValue
    }
}

public extension DependencyValues {
    nonisolated var accessStatusSnapshotClient: AccessStatusSnapshotClient {
        get { self[AccessStatusSnapshotClient.self] }
        set { self[AccessStatusSnapshotClient.self] = newValue }
    }
}
