import ComposableArchitecture
import Foundation
import VoyagerShared

public struct AiChatDefaultSettingsClient: Sendable {
    public var load: @Sendable () -> AiChatDefaultSettings
    public var save: @Sendable (AiChatDefaultSettings) -> Void
    public var reset: @Sendable () -> Void

    nonisolated public init(
        load: @escaping @Sendable () -> AiChatDefaultSettings,
        save: @escaping @Sendable (AiChatDefaultSettings) -> Void,
        reset: @escaping @Sendable () -> Void,
    ) {
        self.load = load
        self.save = save
        self.reset = reset
    }
}

extension AiChatDefaultSettingsClient: DependencyKey {
    nonisolated public static var liveValue: AiChatDefaultSettingsClient {
        live()
    }

    nonisolated public static var testValue: AiChatDefaultSettingsClient {
        live(userDefaultsClient: .testValue)
    }

    nonisolated public static var previewValue: AiChatDefaultSettingsClient {
        testValue
    }
}

public extension DependencyValues {
    nonisolated var aiChatDefaultSettingsClient: AiChatDefaultSettingsClient {
        get { self[AiChatDefaultSettingsClient.self] }
        set { self[AiChatDefaultSettingsClient.self] = newValue }
    }
}

public extension AiChatDefaultSettingsClient {
    nonisolated static func live(userDefaultsClient: UserDefaultsClient = .liveValue)
        -> AiChatDefaultSettingsClient
    {
        AiChatDefaultSettingsClient(
            load: {
                guard let data = userDefaultsClient.object(SettingsKeys.aiChatDefaultSettings) as? Data else {
                    return .default
                }

                do {
                    return try JSONDecoder().decode(AiChatDefaultSettings.self, from: data)
                } catch {
                    return .default
                }
            },
            save: { settings in
                do {
                    let data = try JSONEncoder().encode(settings)
                    userDefaultsClient.setObject(data, SettingsKeys.aiChatDefaultSettings)
                } catch {
                    userDefaultsClient.setObject(nil, SettingsKeys.aiChatDefaultSettings)
                }
            },
            reset: {
                userDefaultsClient.setObject(nil, SettingsKeys.aiChatDefaultSettings)
            },
        )
    }
}
