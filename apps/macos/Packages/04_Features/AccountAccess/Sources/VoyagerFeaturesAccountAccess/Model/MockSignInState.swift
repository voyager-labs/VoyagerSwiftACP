import Foundation

// MARK: - extracted from AccountAccessClient.swift:141-162

/// Mock sign-in 세션 상태를 공유하는 sendable state holder.
/// Mock sign-in handoff 성공 시 세션이 설정되고, restoreSession에서 읽는다.
public final class MockSignInState: Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var _session: AccountSession?

    nonisolated public init() {}

    nonisolated public var session: AccountSession? {
        lock.lock()
        defer { lock.unlock() }
        return _session
    }

    nonisolated public func setSession(_ session: AccountSession?) {
        lock.lock()
        defer { lock.unlock() }
        _session = session
    }
}
