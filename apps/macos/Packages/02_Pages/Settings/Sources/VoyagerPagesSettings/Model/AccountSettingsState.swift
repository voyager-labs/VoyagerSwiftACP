import ComposableArchitecture

public enum SetAuthState: Equatable, Sendable {
    case signedOut
    case signInInProgress
    case signedIn
    case signInFailed
}

/// Canonical AccountAccess runtime에서 Settings가 표시하는 사실만 복사한 값 projection.
public struct AccountAccessPresentation: Equatable, Sendable {
    public var hasAccountSession: Bool
    public var isSignInInProgress: Bool
    public var didSignInFail: Bool

    public init(
        hasAccountSession: Bool = false,
        isSignInInProgress: Bool = false,
        didSignInFail: Bool = false,
    ) {
        self.hasAccountSession = hasAccountSession
        self.isSignInInProgress = isSignInInProgress
        self.didSignInFail = didSignInFail
    }
}

@ObservableState
public struct AccountSettingsState: Equatable {
    public var presentation = AccountAccessPresentation()
    public var isShowingSignOutConfirmation = false

    public init() {}

    public var setAuthState: SetAuthState {
        if presentation.isSignInInProgress { return .signInInProgress }
        if presentation.didSignInFail { return .signInFailed }
        return presentation.hasAccountSession ? .signedIn : .signedOut
    }
}
