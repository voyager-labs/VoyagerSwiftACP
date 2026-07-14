import ComposableArchitecture
import Foundation
import VoyagerShared

public struct CollectionSearchAISettingsClient: Sendable {
    public var load: @Sendable () -> CollectionSearchAISettings
    public var save: @Sendable (CollectionSearchAISettings) -> Void
    public var reset: @Sendable () -> Void

    nonisolated public init(
        load: @escaping @Sendable () -> CollectionSearchAISettings,
        save: @escaping @Sendable (CollectionSearchAISettings) -> Void,
        reset: @escaping @Sendable () -> Void,
    ) {
        self.load = load
        self.save = save
        self.reset = reset
    }
}

extension CollectionSearchAISettingsClient: DependencyKey {
    nonisolated public static var liveValue: CollectionSearchAISettingsClient {
        live()
    }

    nonisolated public static var testValue: CollectionSearchAISettingsClient {
        live(userDefaultsClient: .testValue)
    }

    nonisolated public static var previewValue: CollectionSearchAISettingsClient {
        testValue
    }
}

public extension DependencyValues {
    nonisolated var collectionSearchAISettingsClient: CollectionSearchAISettingsClient {
        get { self[CollectionSearchAISettingsClient.self] }
        set { self[CollectionSearchAISettingsClient.self] = newValue }
    }
}

public extension CollectionSearchAISettingsClient {
    nonisolated static func live(userDefaultsClient: UserDefaultsClient = .liveValue)
        -> CollectionSearchAISettingsClient
    {
        CollectionSearchAISettingsClient(
            load: {
                guard let data = userDefaultsClient.object(SettingsKeys.collectionSearchAISettings) as? Data else {
                    return .default
                }

                do {
                    return try JSONDecoder().decode(CollectionSearchAISettings.self, from: data)
                } catch {
                    return .default
                }
            },
            save: { settings in
                do {
                    let data = try JSONEncoder().encode(settings)
                    userDefaultsClient.setObject(data, SettingsKeys.collectionSearchAISettings)
                } catch {
                    userDefaultsClient.setObject(nil, SettingsKeys.collectionSearchAISettings)
                }
            },
            reset: {
                userDefaultsClient.setObject(nil, SettingsKeys.collectionSearchAISettings)
            },
        )
    }
}
