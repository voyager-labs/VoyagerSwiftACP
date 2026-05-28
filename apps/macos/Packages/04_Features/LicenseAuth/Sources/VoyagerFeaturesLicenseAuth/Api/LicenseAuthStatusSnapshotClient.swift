import ComposableArchitecture
import Foundation
import VoyagerEntitiesAppPreferences
import VoyagerShared

public struct LicenseAuthStatusSnapshotClient: Sendable {
    public var load: @Sendable () async -> LicenseAuthStatusSnapshot?
    public var save: @Sendable (_ snapshot: LicenseAuthStatusSnapshot) async -> Void
    public var remove: @Sendable () async -> Void

    public nonisolated init(
        load: @escaping @Sendable () async -> LicenseAuthStatusSnapshot?,
        save: @escaping @Sendable (_ snapshot: LicenseAuthStatusSnapshot) async -> Void,
        remove: @escaping @Sendable () async -> Void,
    ) {
        self.load = load
        self.save = save
        self.remove = remove
    }
}

extension LicenseAuthStatusSnapshotClient: DependencyKey {
    public nonisolated static var liveValue: LicenseAuthStatusSnapshotClient {
        LicenseAuthStatusSnapshotClient(
            load: {
                @Dependency(\.userDefaultsClient)
                var userDefaults
                guard let data = userDefaults.object(SettingsKeys.accessStatusSnapshot) as? Data else {
                    return nil
                }
                return try? JSONDecoder().decode(LicenseAuthStatusSnapshot.self, from: data)
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

    public nonisolated static var testValue: LicenseAuthStatusSnapshotClient {
        LicenseAuthStatusSnapshotClient(
            load: { nil },
            save: { _ in },
            remove: {},
        )
    }

    public nonisolated static var previewValue: LicenseAuthStatusSnapshotClient {
        testValue
    }
}

public extension DependencyValues {
    nonisolated var licenseAuthStatusSnapshotClient: LicenseAuthStatusSnapshotClient {
        get { self[LicenseAuthStatusSnapshotClient.self] }
        set { self[LicenseAuthStatusSnapshotClient.self] = newValue }
    }
}
