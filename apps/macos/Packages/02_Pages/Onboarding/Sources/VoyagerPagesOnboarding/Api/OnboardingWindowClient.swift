import AppKit
import ComposableArchitecture
import VoyagerFeaturesAccountAccess

@MainActor private var onboardingWindowController: OnboardingWindowController?

/// 온보딩 창이 열려 있으면 auth callback을 온보딩의 accessUnlock(AccountAccessFeature)로 라우팅.
/// 창이 없으면 false 반환.
@MainActor
public func routeAuthCallbackToOnboardingIfPresent(_ url: URL) -> Bool {
    guard let controller = onboardingWindowController else { return false }
    controller.store.send(.accessUnlock(.loginCallbackReceived(url)))
    return true
}

public enum OnboardingOpenMainWindowRequest: Equatable, Sendable {
    case defaultTabPath
    case explicitPath(String)
}

private actor OnboardingPresentationGate {
    private var hasRequestedPresentation = false

    func claimPresentation() -> Bool {
        if hasRequestedPresentation {
            return false
        }
        hasRequestedPresentation = true
        return true
    }

    func reset() {
        hasRequestedPresentation = false
    }
}

public struct OnboardingWindowClient: Sendable {
    public var isRequired: @Sendable () -> Bool
    public var showIfNeeded: @Sendable () -> Bool
    public var showWindow: @Sendable () async -> Void
    public var closeWindow: @Sendable () async -> Void
    public var openMainWindow: @Sendable (_ request: OnboardingOpenMainWindowRequest) async -> Bool
    public var resetStoredProgress: @Sendable () -> Void

    nonisolated public init(
        isRequired: @escaping @Sendable () -> Bool,
        showIfNeeded: @escaping @Sendable () -> Bool,
        showWindow: @escaping @Sendable () async -> Void,
        closeWindow: @escaping @Sendable () async -> Void,
        openMainWindow: @escaping @Sendable (_ request: OnboardingOpenMainWindowRequest) async -> Bool,
        resetStoredProgress: @escaping @Sendable () -> Void = {},
    ) {
        self.isRequired = isRequired
        self.showIfNeeded = showIfNeeded
        self.showWindow = showWindow
        self.closeWindow = closeWindow
        self.openMainWindow = openMainWindow
        self.resetStoredProgress = resetStoredProgress
    }
}

extension OnboardingWindowClient: DependencyKey {
    nonisolated public static var liveValue: OnboardingWindowClient {
        makeLive(openMainWindow: { _ in
            fatalError("onboardingWindowClient.openMainWindow live dependency is not configured")
        })
    }

    nonisolated public static func makeLive(
        openMainWindow: @escaping @Sendable (_ request: OnboardingOpenMainWindowRequest) async -> Bool,
        accountSessionClient: AccountSessionClient? = nil,
        authNetworkClient: AuthNetworkClient? = nil,
        signInHandoffClient: SignInHandoffClient? = nil,
        permissionDebugScenario: (@Sendable () -> OnboardingPermissionDebugScenario?)? = nil,
    ) -> OnboardingWindowClient {
        makeClient(
            progressClient: OnboardingProgressClient.liveValue,
            openMainWindow: openMainWindow,
            accountSessionClient: accountSessionClient,
            authNetworkClient: authNetworkClient,
            signInHandoffClient: signInHandoffClient,
            permissionDebugScenario: permissionDebugScenario,
        )
    }

    nonisolated static func makeClient(
        progressClient: OnboardingProgressClient,
        openMainWindow: @escaping @Sendable (_ request: OnboardingOpenMainWindowRequest) async -> Bool,
        accountSessionClient: AccountSessionClient? = nil,
        authNetworkClient: AuthNetworkClient? = nil,
        signInHandoffClient: SignInHandoffClient? = nil,
        permissionDebugScenario: (@Sendable () -> OnboardingPermissionDebugScenario?)? = nil,
        showWindow customShowWindow: (@Sendable () async -> Void)? = nil,
        closeWindow customCloseWindow: (@Sendable () async -> Void)? = nil,
    ) -> OnboardingWindowClient {
        let presentationGate = OnboardingPresentationGate()
        let showWindow: @Sendable () async -> Void = customShowWindow ?? {
            await MainActor.run {
                if onboardingWindowController == nil {
                    onboardingWindowController = OnboardingWindowController(
                        openMainWindow: openMainWindow,
                        accountSessionClient: accountSessionClient,
                        authNetworkClient: authNetworkClient,
                        signInHandoffClient: signInHandoffClient,
                        permissionDebugScenario: permissionDebugScenario,
                    )
                }

                onboardingWindowController?.showWindow(nil)
                onboardingWindowController?.window?.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        let closeWindowBase: @Sendable () async -> Void = customCloseWindow ?? {
            await MainActor.run {
                onboardingWindowController?.dismissWithoutTerminate()
                onboardingWindowController = nil
            }
        }
        let closeWindow: @Sendable () async -> Void = {
            await closeWindowBase()
            await presentationGate.reset()
        }

        return OnboardingWindowClient(
            isRequired: {
                isOnboardingRequired(progressClient)
            },
            showIfNeeded: {
                let required = isOnboardingRequired(progressClient)

                if required {
                    Task {
                        if await presentationGate.claimPresentation() {
                            await showWindow()
                        }
                    }
                }
                return required
            },
            showWindow: showWindow,
            closeWindow: closeWindow,
            openMainWindow: openMainWindow,
            resetStoredProgress: progressClient.reset,
        )
    }

    nonisolated private static func isOnboardingRequired(_ progressClient: OnboardingProgressClient) -> Bool {
        switch progressClient.load() {
        case let .success(snapshot):
            !snapshot.stepState.completeComplete
        case .empty, .resetRequired:
            true
        }
    }

    nonisolated public static var testValue: OnboardingWindowClient {
        OnboardingWindowClient(
            isRequired: {
                fatalError("onboardingWindowClient.isRequired test dependency is not configured")
            },
            showIfNeeded: {
                fatalError("onboardingWindowClient.showIfNeeded test dependency is not configured")
            },
            showWindow: {
                fatalError("onboardingWindowClient.showWindow test dependency is not configured")
            },
            closeWindow: {
                fatalError("onboardingWindowClient.closeWindow test dependency is not configured")
            },
            openMainWindow: { _ in
                fatalError("onboardingWindowClient.openMainWindow test dependency is not configured")
            },
            resetStoredProgress: {
                fatalError("onboardingWindowClient.resetStoredProgress test dependency is not configured")
            },
        )
    }

    nonisolated public static var previewValue: OnboardingWindowClient {
        testValue
    }
}

public extension DependencyValues {
    nonisolated var onboardingWindowClient: OnboardingWindowClient {
        get { self[OnboardingWindowClient.self] }
        set { self[OnboardingWindowClient.self] = newValue }
    }
}
