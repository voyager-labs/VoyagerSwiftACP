import ComposableArchitecture
import Foundation

@ObservableState
public struct AccountAccessState: Equatable {
    public var status: AccessStatus?
    public var snapshot: AccessStatusSnapshot?
    public var isSubmitting: Bool = false
    public var errorMessage: String?
    public var isComplete: Bool = false
    public var trialExpiresAt: Date?
    public var hasAccountSession: Bool = false
    public var isSignInInProgress: Bool = false
    public var didSignInFail: Bool = false
    public var fetchGeneration: Int = 0
    /// fetchAccessStatus 재시도 횟수 (최대 3). 성공 시 0으로 리셋.
    public var fetchRetryCount: Int = 0
    /// 현재 대기 중인 handoff state. awaitingCallback에서 설정, callback 처리 후 초기화.
    public var handoffPendingState: String?

    // MARK: - TTL Timer

    /// TTL 갱신 타이머 활성화 여부.
    public var ttlTimerActive: Bool = false
    /// TTL 갱신 연속 실패 횟수 (최대 임계값 초과 시 타이머 중단).
    public var consecutiveRefreshFailures: Int = 0
    /// 현재 세션의 access token 만료 시각. TTL 타이머가 이 값을 기준으로 갱신 시점을 계산.
    public var sessionExpiresAt: Date?

    /// 세션 만료 여부. true이면 중복 _sessionExpiredDetected를 무시한다 (dedup guard).
    public var isSessionExpired: Bool = false

    public init() {}

    public var showsRetry: Bool {
        guard let status else { return false }
        return !status.isActive
    }

    // MARK: - ONB-002 Interpretation

    public var accountAccessAuthAxis: AccountAccessAuthAxis {
        if isSignInInProgress {
            return .signInInProgress
        }
        if didSignInFail {
            return .signInFailed
        }
        if hasAccountSession {
            return .signedIn
        }
        return .signedOut
    }

    public var accountAccessStepState: AccountAccessStepState {
        if isSignInInProgress {
            return .pending
        }
        if !hasAccountSession {
            return .blocked
        }
        guard let status else {
            return .pending
        }
        switch status {
        case .coreLicenseActive, .trialActive, .internalTestActive:
            return .complete
        case .networkFailure:
            return .error
        case .none, .trialExpired, .revoked, .refunded:
            return .blocked
        }
    }

    // MARK: - ONB-002 Affordances

    public var canStartLogin: Bool {
        accountAccessAuthAxis == .signedOut || accountAccessAuthAxis == .signInFailed
    }

    public var canRefreshAccess: Bool {
        accountAccessAuthAxis == .signedIn && !isSubmitting && !isSignInInProgress
    }

    public var canRetry: Bool {
        accountAccessStepState == .error && !isSubmitting
    }

    public var requiresAccountSession: Bool {
        !hasAccountSession
    }
}
