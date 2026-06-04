import Foundation

/// Typed error reasons for native Codex authentication flows.
///
/// Each case maps to a distinct failure mode that the reducer layer can handle
/// with targeted UI feedback.  Do **not** collapse these into `.unknown`.
public enum CodexNativeAuthError: Error, Equatable, Sendable {
    /// The user explicitly cancelled the in-progress auth flow.
    case cancelled
    /// The auth flow exceeded its allowed duration.
    case timeout
    /// The OAuth callback did not match the expected flow identifier.
    case callbackMismatch
    /// The Codex authentication service is not currently available
    /// (e.g. the real SDK integration has not been wired yet).
    case loginUnavailable
    /// A network failure occurred during the auth exchange.
    case networkError(String)
}
