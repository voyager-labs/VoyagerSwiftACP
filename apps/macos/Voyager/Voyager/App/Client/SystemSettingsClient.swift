import AppKit
import ComposableArchitecture

struct SystemSettingsClient: Sendable {
    var openFullDiskAccess: @Sendable () -> Bool

    nonisolated init(openFullDiskAccess: @escaping @Sendable () -> Bool) {
        self.openFullDiskAccess = openFullDiskAccess
    }
}

extension SystemSettingsClient: DependencyKey {
    nonisolated static var liveValue: SystemSettingsClient {
        SystemSettingsClient(openFullDiskAccess: {
            guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
            else {
                return false
            }
            return NSWorkspace.shared.open(url)
        })
    }

    nonisolated static var testValue: SystemSettingsClient {
        SystemSettingsClient(openFullDiskAccess: { false })
    }

    nonisolated static var previewValue: SystemSettingsClient {
        SystemSettingsClient(openFullDiskAccess: { false })
    }
}

extension DependencyValues {
    nonisolated var systemSettingsClient: SystemSettingsClient {
        get { self[SystemSettingsClient.self] }
        set { self[SystemSettingsClient.self] = newValue }
    }
}
