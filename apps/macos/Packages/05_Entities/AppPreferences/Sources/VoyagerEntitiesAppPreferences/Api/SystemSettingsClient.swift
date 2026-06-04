import AppKit
import ComposableArchitecture

public struct SystemSettingsClient: Sendable {
    public var openFullDiskAccess: @Sendable () -> Bool

    nonisolated public init(openFullDiskAccess: @escaping @Sendable () -> Bool) {
        self.openFullDiskAccess = openFullDiskAccess
    }
}

extension SystemSettingsClient: DependencyKey {
    nonisolated public static var liveValue: SystemSettingsClient {
        SystemSettingsClient(openFullDiskAccess: {
            guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
            else {
                return false
            }
            return NSWorkspace.shared.open(url)
        })
    }

    nonisolated public static var testValue: SystemSettingsClient {
        SystemSettingsClient(openFullDiskAccess: { false })
    }

    nonisolated public static var previewValue: SystemSettingsClient {
        SystemSettingsClient(openFullDiskAccess: { false })
    }
}

public extension DependencyValues {
    nonisolated var systemSettingsClient: SystemSettingsClient {
        get { self[SystemSettingsClient.self] }
        set { self[SystemSettingsClient.self] = newValue }
    }
}
