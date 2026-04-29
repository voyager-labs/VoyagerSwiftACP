import Foundation

/// SET-007 canonical connection state machine for a provider.
///
/// State transitions:
///   notVerified → connectInProgress → connected
///   connectInProgress → connectionFailed → notVerified
///   connected → disconnecting → disconnected
///   any → unavailable (e.g. providerUnsupportedInBuild)
public enum ProviderConnectionState: String, Codable, Sendable, Equatable, CaseIterable {
    case notVerified
    case connectInProgress
    case connected
    case connectionFailed
    case disconnecting
    case disconnected
    case unavailable
}

/// Machine-readable status reason explaining why a provider is in a given state.
/// Stored in the persisted snapshot instead of free-form error strings.
public enum ProviderStatusReason: String, Codable, Sendable, Equatable, CaseIterable {
    case none
    case missingCredential
    case invalidPayload
    case credentialKindMismatch
    case expired
    case providerUnsupportedInBuild
    case networkUnavailable
    case verificationFailed
    case oauthRejected
    case invalidAPIKey
    case corruptedProviderRecord
    case unknown
}

/// Primary row action for a given connection state.
/// Used by Settings UI to determine which button/action to show per provider row.
public enum ProviderRowAction: Sendable, Equatable {
    case connect
    case retry
    case disconnect
    case cancel
    case disabled
}

public extension ProviderConnectionState {
    /// Maps connection state to the primary row action for UI.
    var primaryAction: ProviderRowAction {
        switch self {
        case .notVerified: .connect
        case .connectInProgress: .cancel
        case .connected: .disconnect
        case .connectionFailed: .retry
        case .disconnecting: .disabled
        case .disconnected: .connect
        case .unavailable: .disabled
        }
    }
}
