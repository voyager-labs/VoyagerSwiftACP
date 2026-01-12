import ComposableArchitecture
import ServiceManagement

struct LaunchAtLoginClient: Sendable {
    var isEnabled: @Sendable () -> Bool
    var setEnabled: @Sendable (Bool) throws -> Void

    nonisolated init(
        isEnabled: @escaping @Sendable () -> Bool,
        setEnabled: @escaping @Sendable (Bool) throws -> Void,
    ) {
        self.isEnabled = isEnabled
        self.setEnabled = setEnabled
    }
}

extension LaunchAtLoginClient: DependencyKey {
    nonisolated static var liveValue: LaunchAtLoginClient {
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

    nonisolated static var testValue: LaunchAtLoginClient {
        LaunchAtLoginClient(
            isEnabled: { false },
            setEnabled: { _ in },
        )
    }

    nonisolated static var previewValue: LaunchAtLoginClient {
        LaunchAtLoginClient(
            isEnabled: { false },
            setEnabled: { _ in },
        )
    }
}

extension DependencyValues {
    nonisolated var launchAtLoginClient: LaunchAtLoginClient {
        get { self[LaunchAtLoginClient.self] }
        set { self[LaunchAtLoginClient.self] = newValue }
    }
}
