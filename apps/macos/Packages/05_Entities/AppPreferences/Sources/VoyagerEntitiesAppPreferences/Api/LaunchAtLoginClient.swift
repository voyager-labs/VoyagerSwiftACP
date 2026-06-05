import ComposableArchitecture
import ServiceManagement

public struct LaunchAtLoginClient: Sendable {
    public var isEnabled: @Sendable () -> Bool
    public var setEnabled: @Sendable (Bool) throws -> Void

    nonisolated public init(
        isEnabled: @escaping @Sendable () -> Bool,
        setEnabled: @escaping @Sendable (Bool) throws -> Void,
    ) {
        self.isEnabled = isEnabled
        self.setEnabled = setEnabled
    }
}

extension LaunchAtLoginClient: DependencyKey {
    nonisolated public static var liveValue: LaunchAtLoginClient {
        LaunchAtLoginClient(
            isEnabled: {
                let appService = SMAppService.mainApp
                return appService.status == .enabled
            },
            setEnabled: { enabled in
                let appService = SMAppService.mainApp
                if enabled {
                    try appService.register()
                } else {
                    try appService.unregister()
                }
            },
        )
    }

    nonisolated public static var testValue: LaunchAtLoginClient {
        LaunchAtLoginClient(
            isEnabled: { false },
            setEnabled: { _ in },
        )
    }

    nonisolated public static var previewValue: LaunchAtLoginClient {
        LaunchAtLoginClient(
            isEnabled: { false },
            setEnabled: { _ in },
        )
    }
}

public extension DependencyValues {
    nonisolated var launchAtLoginClient: LaunchAtLoginClient {
        get { self[LaunchAtLoginClient.self] }
        set { self[LaunchAtLoginClient.self] = newValue }
    }
}
