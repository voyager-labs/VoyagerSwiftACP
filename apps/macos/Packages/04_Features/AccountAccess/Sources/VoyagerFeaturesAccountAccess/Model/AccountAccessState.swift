import ComposableArchitecture
import Foundation

public enum AccountAccessHandoffScope: Hashable, Sendable {
    case onboarding
    case lifecycle
    case settings
}

public struct AccountAccessHandoffTransaction: Equatable, Sendable {
    public let context: AppHandoffContext
    public let scope: AccountAccessHandoffScope

    public init(
        context: AppHandoffContext,
        scope: AccountAccessHandoffScope,
    ) {
        self.context = context
        self.scope = scope
    }
}

public enum SyncReason: Equatable, Sendable {
    case foreground
    case login
    case manual
    case retry
    case refreshDeadline

    var priority: Int {
        switch self {
        case .refreshDeadline:
            3
        case .login, .manual, .retry:
            2
        case .foreground:
            1
        }
    }

    var bypassesFreshness: Bool {
        self != .foreground
    }
}

@ObservableState
public struct AccountAccessState: Equatable {
    public var status: AccessStatus?
    public var snapshot: AccessStatusSnapshot?
    public var isSubmitting: Bool = false
    public var errorMessage: String?
    public var deviceBindingFailure: DeviceBindingFailure?
    public var isComplete: Bool = false
    public var trialExpiresAt: Date?
    public var hasAccountSession: Bool = false
    public var didBootstrap: Bool = false
    public var isSignInInProgress: Bool = false
    public var didSignInFail: Bool = false
    /// 승인된 sign-in handoff의 고정 컨텍스트와 취소 범위.
    public var handoffTransaction: AccountAccessHandoffTransaction?
    public var fetchGeneration: Int = 0
    /// 가장 최근에 완전한 session sync가 끝난 시각. partial 결과는 갱신하지 않는다.
    public var lastCompleteSyncAt: Date?
    /// session sync completion이 현재 session intent에 속하는지 검증하는 식별자.
    public var syncGeneration: UInt64 = 0
    /// 현재 실행 중인 session sync의 우선순위 판단 근거.
    public var inFlightSyncReason: SyncReason?
    /// foreground/TTL persisted session 재검증의 최신 요청 식별자.
    public var revalidationGeneration: Int = 0
    /// fetchAccessStatus 재시도 횟수 (최대 3). 성공 시 0으로 리셋.
    public var fetchRetryCount: Int = 0
    /// device binding transient 실패 누적 횟수. 임계값 이후 support/account 경로로 escalates.
    public var deviceBindingRetryCount: Int = 0
    /// 현재 대기 중인 handoff state. awaitingCallback에서 설정, callback 처리 후 초기화.
    public var handoffPendingState: String?
    /// 공유 handoff state를 claim한 뒤 token exchange가 진행 중인 flow 식별자.
    public var handoffExchangeState: String?
    /// handoff마다 증가하여 이전 rollback completion이 새 로그인 상태를 덮지 못하게 한다.
    public var handoffGeneration: UInt64 = 0

    // MARK: - Refresh Deadline

    /// Refresh deadline scheduler 활성화 여부.
    public var ttlTimerActive: Bool = false
    /// Refresh deadline을 무효화하는 세대 식별자.
    public var refreshDeadlineGeneration: UInt64 = 0
    /// 호환성을 위해 유지하는 refresh 실패 수.
    public var consecutiveRefreshFailures: Int = 0
    /// 현재 세션의 access token 만료 시각. Refresh deadline이 이 값을 기준으로 계산된다.
    public var sessionExpiresAt: Date?
    /// 현재 credential의 stable binding. 비동기 sync completion은 이 값을 함께 검증한다.
    public var sessionBindingID: UUID?

    /// 세션 만료 여부. true이면 중복 _sessionExpiredDetected를 무시한다 (dedup guard).
    public var isSessionExpired: Bool = false
    public var updateEligibilityFailure: UpdateEligibilityFailure?

    public init() {}

    public var showsRetry: Bool {
        if deviceBindingFailure?.isRetryable == true {
            return accessUnlockPrimaryCTA == .retry
        }
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
        if isSubmitting {
            return .pending
        }
        if !hasAccountSession {
            return .blocked
        }
        if let deviceBindingFailure {
            return deviceBindingFailure.stepState
        }
        if updateEligibilityFailure != nil {
            return .blocked
        }
        if isComplete, status?.isActive == true {
            return .complete
        }
        guard let status else {
            // status를 아직 모르지만 조회 실패(decoding/notConfigured)가 발생했으면 error.
            // entitlement_access_flow.md: 조회 실패는 access_status 값을 확정하지 않고 error 축에서 처리.
            return errorMessage == nil ? .pending : .error
        }
        switch status {
        case .coreLicenseActive, .trialActive, .internalTestActive:
            return .pending
        case .networkFailure:
            return .error
        case .none, .trialExpired, .revoked, .refunded:
            return .blocked
        }
    }

    // MARK: - ONB-002 Affordances

    public var canStartLogin: Bool {
        accountAccessAuthAxis == .signedOut
            || accountAccessAuthAxis == .signInFailed
    }

    public var canRefreshAccess: Bool {
        accountAccessAuthAxis == .signedIn
            && !isSubmitting
            && !isSignInInProgress
            && deviceBindingFailure == nil
    }

    public var canRetry: Bool {
        if deviceBindingFailure?.isRetryable == true {
            return accessUnlockPrimaryCTA == .retry && !isSubmitting
        }
        return accountAccessStepState == .error && !isSubmitting
    }

    public var requiresAccountSession: Bool {
        !hasAccountSession
    }

    /// VOY-397: 화면에 표시할 primary CTA를 상태에서 도출.
    /// direct checkout은 core ONB recovery 경로에서 숨김.
    public var accessUnlockPrimaryCTA: AccessUnlockPrimaryCTA {
        if isSubmitting {
            return .pending
        }
        if !hasAccountSession {
            return .login
        }
        if isComplete, status?.isActive == true {
            return .next
        }
        if updateEligibilityFailure != nil {
            return .eligibleDownload
        }
        if let deviceBindingFailure {
            return primaryCTA(for: deviceBindingFailure)
        }
        guard let status else {
            return errorMessage == nil ? .pending : .retry
        }
        switch status {
        case .coreLicenseActive, .trialActive, .internalTestActive:
            return .pending
        case .networkFailure:
            return .retry
        case .none, .trialExpired, .revoked, .refunded:
            return .webPricing
        }
    }

    /// AppLifecycle/Settings가 launch access snapshot을 같은 방식으로 상태에 반영한다.
    public mutating func hydrateLaunchSnapshotState(_ snapshot: AccessStatusSnapshot) {
        status = snapshot.status
        self.snapshot = snapshot
        trialExpiresAt = snapshot.currentPeriodEnd
        deviceBindingFailure = nil
        isComplete = snapshot.isActive && snapshot.isDeviceBindingVerified && snapshot.hasSession
        isSignInInProgress = false
        didSignInFail = false
        handoffPendingState = nil
        handoffExchangeState = nil
        errorMessage = nil
        updateEligibilityFailure = nil
        deviceBindingFailure = nil
        deviceBindingRetryCount = 0
        hasAccountSession = snapshot.hasSession
        sessionExpiresAt = snapshot.sessionExpiresAt
        sessionBindingID = nil
        isSessionExpired = false
        didBootstrap = true
        fetchGeneration += 1
        lastCompleteSyncAt = snapshot.fetchedAt
        syncGeneration += 1
        inFlightSyncReason = nil
    }

    private func primaryCTA(for deviceBindingFailure: DeviceBindingFailure) -> AccessUnlockPrimaryCTA {
        if deviceBindingFailure.isRetryable, deviceBindingRetryCount >= 3 {
            return .account
        }
        return deviceBindingFailure.primaryCTA
    }

    /// access_status를 확정할 수 없는 실패를 세션 만료와 분리해 error 축으로 반영한다.
    public mutating func hydrateAccessFailureState(
        error: AccessError,
        sessionExpiresAt: Date?,
    ) {
        status = error == .networkFailure ? .networkFailure : nil
        snapshot = nil
        trialExpiresAt = nil
        isSignInInProgress = false
        didSignInFail = false
        handoffPendingState = nil
        handoffExchangeState = nil
        errorMessage = Self.errorMessage(for: error)
        deviceBindingFailure = nil
        deviceBindingRetryCount = 0
        hasAccountSession = sessionExpiresAt != nil
        self.sessionExpiresAt = sessionExpiresAt
        sessionBindingID = nil
        isSessionExpired = false
        isComplete = false
        didBootstrap = true
        fetchGeneration += 1
        lastCompleteSyncAt = nil
        syncGeneration += 1
        inFlightSyncReason = nil
        updateEligibilityFailure = nil
    }

    private static func errorMessage(for error: AccessError) -> String {
        switch error {
        case .networkFailure:
            "Network error. Please try again."
        case .notConfigured:
            "Access service is not configured."
        case .decodingFailure:
            "Failed to process the response."
        case .unauthorized:
            "Session expired. Sign in again to continue."
        case .unknownGatewayCode:
            "An unexpected error occurred."
        }
    }
}
