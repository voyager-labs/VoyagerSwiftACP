import Foundation

/// 인증 handoff 결과
public enum SignInHandoffResult: Sendable, Equatable {
    case success(callbackURL: URL)
    case awaitingCallback(state: String)
    case failure
    case cancelled
}
