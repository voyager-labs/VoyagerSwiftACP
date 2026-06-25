import Foundation

public enum AccountAuthScenario: String, Sendable, Equatable, CaseIterable {
    case signedOut
    case signedIn
    case authExpired
    case loading
    case error

    public var title: String {
        switch self {
        case .signedOut:
            "Signed Out"
        case .signedIn:
            "Signed In"
        case .authExpired:
            "Auth Expired"
        case .loading:
            "Loading"
        case .error:
            "Error"
        }
    }
}

public enum AIConnectionScenario: String, Sendable, Equatable, CaseIterable {
    case notConfigured
    case connected
    case connectionError

    public var title: String {
        switch self {
        case .notConfigured:
            "Not Configured"
        case .connected:
            "Connected"
        case .connectionError:
            "Connection Error"
        }
    }
}

public enum PermissionScenario: String, Sendable, Equatable, CaseIterable {
    case allGranted
    case denied

    public var title: String {
        switch self {
        case .allGranted:
            "All Granted"
        case .denied:
            "Denied"
        }
    }
}

public enum PersistenceScenario: String, Sendable, Equatable, CaseIterable {
    case clean
    case populated

    public var title: String {
        switch self {
        case .clean:
            "Clean"
        case .populated:
            "Populated"
        }
    }
}

public enum FailureLatencyScenario: String, Sendable, Equatable, CaseIterable {
    case none
    case error
    case latency

    public var title: String {
        switch self {
        case .none:
            "None"
        case .error:
            "Error"
        case .latency:
            "Latency"
        }
    }
}

public struct SettingsHostScenario: Sendable, Equatable {
    public let accountAuth: AccountAuthScenario
    public let aiConnection: AIConnectionScenario
    public let permissions: PermissionScenario
    public let persistence: PersistenceScenario
    public let failureLatency: FailureLatencyScenario

    public init(
        accountAuth: AccountAuthScenario,
        aiConnection: AIConnectionScenario,
        permissions: PermissionScenario,
        persistence: PersistenceScenario,
        failureLatency: FailureLatencyScenario,
    ) {
        self.accountAuth = accountAuth
        self.aiConnection = aiConnection
        self.permissions = permissions
        self.persistence = persistence
        self.failureLatency = failureLatency
    }

    public var id: String {
        [
            "accountAuth=\(accountAuth.rawValue)",
            "aiConnection=\(aiConnection.rawValue)",
            "permissions=\(permissions.rawValue)",
            "persistence=\(persistence.rawValue)",
            "failureLatency=\(failureLatency.rawValue)",
        ]
        .joined(separator: ",")
    }

    public var title: String {
        [
            accountAuth.title,
            aiConnection.title,
            permissions.title,
            persistence.title,
            failureLatency.title,
        ]
        .joined(separator: " · ")
    }

    public var summary: String {
        [
            "Account \(accountAuth.title.lowercased())",
            "AI \(aiConnection.title.lowercased())",
            "permissions \(permissions.title.lowercased())",
            "persistence \(persistence.title.lowercased())",
            "failure latency \(failureLatency.title.lowercased())",
        ]
        .joined(separator: ", ") + "."
    }

    public var accountLoaded: Bool {
        accountAuth == .signedIn
    }

    public var sessionLapse: Bool {
        accountAuth == .authExpired
    }

    public var debugMenuWired: Bool {
        true
    }
}

public enum SettingsHostPreset: String, Sendable, Equatable, CaseIterable {
    case defaultSandbox
    case signedOut
    case signedIn
    case authExpired
    case accountLoading
    case accountError
    case aiNotConfigured
    case aiConnected
    case aiConnectionError
    case permissionsAllGranted
    case permissionsDenied
    case errorStates

    public var scenario: SettingsHostScenario {
        switch self {
        case .defaultSandbox, .signedOut:
            SettingsHostScenario(
                accountAuth: .signedOut,
                aiConnection: .notConfigured,
                permissions: .allGranted,
                persistence: .clean,
                failureLatency: .none,
            )
        case .signedIn, .permissionsAllGranted:
            SettingsHostScenario(
                accountAuth: .signedIn,
                aiConnection: .connected,
                permissions: .allGranted,
                persistence: .populated,
                failureLatency: .none,
            )
        case .aiNotConfigured:
            SettingsHostScenario(
                accountAuth: .signedIn,
                aiConnection: .notConfigured,
                permissions: .allGranted,
                persistence: .populated,
                failureLatency: .none,
            )
        case .authExpired:
            SettingsHostScenario(
                accountAuth: .authExpired,
                aiConnection: .connected,
                permissions: .allGranted,
                persistence: .populated,
                failureLatency: .none,
            )
        case .accountLoading:
            SettingsHostScenario(
                accountAuth: .loading,
                aiConnection: .notConfigured,
                permissions: .allGranted,
                persistence: .clean,
                failureLatency: .none,
            )
        case .accountError:
            SettingsHostScenario(
                accountAuth: .error,
                aiConnection: .notConfigured,
                permissions: .allGranted,
                persistence: .clean,
                failureLatency: .error,
            )
        case .aiConnected:
            SettingsHostScenario(
                accountAuth: .signedIn,
                aiConnection: .connected,
                permissions: .allGranted,
                persistence: .populated,
                failureLatency: .none,
            )
        case .aiConnectionError:
            SettingsHostScenario(
                accountAuth: .signedIn,
                aiConnection: .connectionError,
                permissions: .allGranted,
                persistence: .populated,
                failureLatency: .error,
            )
        case .permissionsDenied:
            SettingsHostScenario(
                accountAuth: .signedIn,
                aiConnection: .connected,
                permissions: .denied,
                persistence: .populated,
                failureLatency: .none,
            )
        case .errorStates:
            SettingsHostScenario(
                accountAuth: .error,
                aiConnection: .connectionError,
                permissions: .denied,
                persistence: .populated,
                failureLatency: .error,
            )
        }
    }

    public var id: String {
        rawValue
    }

    public var title: String {
        switch self {
        case .defaultSandbox:
            "Default Sandbox"
        case .signedOut:
            "Signed Out"
        case .signedIn:
            "Signed In"
        case .authExpired:
            "Auth Expired"
        case .accountLoading:
            "Account Loading"
        case .accountError:
            "Account Error"
        case .aiNotConfigured:
            "AI Not Configured"
        case .aiConnected:
            "AI Connected"
        case .aiConnectionError:
            "AI Connection Error"
        case .permissionsAllGranted:
            "Permissions All Granted"
        case .permissionsDenied:
            "Permissions Denied"
        case .errorStates:
            "Error States"
        }
    }

    public var summary: String {
        switch self {
        case .defaultSandbox:
            "Signed out, AI not configured, permissions granted, clean persistence, no failures."
        case .signedOut:
            "Signed out, AI not configured, permissions granted, clean persistence, no failures."
        case .signedIn:
            "Signed in, AI connected, permissions granted, populated persistence, no failures."
        case .authExpired:
            "Auth expired, AI connected, permissions granted, populated persistence, no failures."
        case .accountLoading:
            "Account loading, AI not configured, permissions granted, clean persistence, no failures."
        case .accountError:
            "Account error, AI not configured, permissions granted, clean persistence, failing operations."
        case .aiNotConfigured:
            "Signed in, AI not configured, permissions granted, populated persistence, no failures."
        case .aiConnected:
            "Signed in, AI connected, permissions granted, populated persistence, no failures."
        case .aiConnectionError:
            "Signed in, AI connection error, permissions granted, populated persistence, failing operations."
        case .permissionsAllGranted:
            "Signed in, AI connected, all permissions granted, populated persistence, no failures."
        case .permissionsDenied:
            "Signed in, AI connected, permissions denied, populated persistence, no failures."
        case .errorStates:
            "Account error, AI connection error, permissions denied, populated persistence, failing operations."
        }
    }

    public static func parse(_ raw: String?) -> SettingsHostPreset {
        guard let raw, let preset = SettingsHostPreset(rawValue: raw) else {
            return .defaultSandbox
        }
        return preset
    }
}
