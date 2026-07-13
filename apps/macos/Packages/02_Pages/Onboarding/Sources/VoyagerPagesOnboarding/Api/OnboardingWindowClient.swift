import AppKit
import ComposableArchitecture
import Foundation
import VoyagerEntitiesAppPreferences
import VoyagerFeaturesAccountAccess

@MainActor private var onboardingWindowController: OnboardingWindowController?

@MainActor
public func routeAuthCallbackToOnboardingIfPresent(_ url: URL) -> Bool {
    onboardingWindowController?.routeAuthCallback(url) ?? false
}

public enum OnboardingOpenMainWindowRequest: Equatable, Sendable {
    case defaultTabPath
    case explicitPath(String)
}

private struct OnboardingPresentationGate {
    private let hasRequestedPresentation = LockIsolated(false)

    func claimPresentation() -> Bool {
        hasRequestedPresentation.withValue { hasRequestedPresentation in
            guard !hasRequestedPresentation else { return false }
            hasRequestedPresentation = true
            return true
        }
    }

    func reset() {
        hasRequestedPresentation.setValue(false)
    }
}

private enum OnboardingOpenMainWindowAuthorization {
    @TaskLocal static var isAuthorized = false
}

@MainActor
private struct OnboardingWindowComposition {
    let onboardingStore: StoreOf<OnboardingFeature>
    let accountAccessStore: StoreOf<AccountAccessFeature>
    let handlesAuthCallback: Bool
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
        makeStandaloneHost(openMainWindow: { _ in
            fatalError("onboardingWindowClient.openMainWindow live dependency is not configured")
        })
    }

    nonisolated public static func makeMainApp(
        openMainWindow: @escaping @Sendable (_ request: OnboardingOpenMainWindowRequest) async -> Bool,
        resolveAccountAccessStore: @escaping @MainActor @Sendable () -> StoreOf<AccountAccessFeature>,
        forceOnboardingEnvironmentValue: @escaping @Sendable () -> String? = {
            ProcessInfo.processInfo.environment["VOYAGER_SCHEME_FORCE_ONBOARDING"]
        },
        forceFDAEnvironmentValue: @escaping @Sendable () -> String? = {
            ProcessInfo.processInfo.environment["VOYAGER_SCHEME_FORCE_FDA_GRANTED"]
        },
    ) -> OnboardingWindowClient {
        let isForceOnboardingEnabled = isForceOnboardingEnabled(
            environmentValue: forceOnboardingEnvironmentValue(),
            isDebugBuild: isDebugBuild,
        )
        let isForceFullDiskAccessGrantedEnabled = isForceFullDiskAccessGrantedEnabled(
            environmentValue: forceFDAEnvironmentValue(),
            isDebugBuild: isDebugBuild,
        )

        return makeClient(
            progressClient: OnboardingProgressClient.liveValue,
            openMainWindow: openMainWindow,
            makeComposition: { onboardingWindowClient in
                let accountAccessStore = resolveAccountAccessStore()
                let onboardingStore = makeOnboardingStore(
                    progressClient: OnboardingProgressClient.liveValue,
                    onboardingWindowClient: onboardingWindowClient,
                    permissionDebugScenario: nil,
                    isForceFullDiskAccessGrantedEnabled: isForceFullDiskAccessGrantedEnabled,
                )
                return OnboardingWindowComposition(
                    onboardingStore: onboardingStore,
                    accountAccessStore: accountAccessStore,
                    handlesAuthCallback: false,
                )
            },
            isForceOnboardingEnabled: isForceOnboardingEnabled,
        )
    }

    nonisolated public static func makeStandaloneHost(
        openMainWindow: @escaping @Sendable (_ request: OnboardingOpenMainWindowRequest) async -> Bool,
        accountSessionClient: AccountSessionClient? = nil,
        authNetworkClient: AuthNetworkClient? = nil,
        signInHandoffClient: SignInHandoffClient? = nil,
        permissionDebugScenario: (@Sendable () -> OnboardingPermissionDebugScenario?)? = nil,
        forceOnboardingEnvironmentValue: @escaping @Sendable () -> String? = {
            ProcessInfo.processInfo.environment["VOYAGER_SCHEME_FORCE_ONBOARDING"]
        },
        forceFDAEnvironmentValue: @escaping @Sendable () -> String? = {
            ProcessInfo.processInfo.environment["VOYAGER_SCHEME_FORCE_FDA_GRANTED"]
        },
    ) -> OnboardingWindowClient {
        let isForceOnboardingEnabled = isForceOnboardingEnabled(
            environmentValue: forceOnboardingEnvironmentValue(),
            isDebugBuild: isDebugBuild,
        )
        let isForceFullDiskAccessGrantedEnabled = isForceFullDiskAccessGrantedEnabled(
            environmentValue: forceFDAEnvironmentValue(),
            isDebugBuild: isDebugBuild,
        )
        let progressClient = OnboardingProgressClient.liveValue

        return makeClient(
            progressClient: progressClient,
            openMainWindow: openMainWindow,
            makeComposition: { onboardingWindowClient in
                var accountAccessState = AccountAccessFeature.State()
                accountAccessState.handoffScope = .onboarding
                let accountAccessStore = Store(initialState: accountAccessState) {
                    AccountAccessFeature()
                } withDependencies: {
                    if let accountSessionClient {
                        $0.accountSessionClient = accountSessionClient
                    }
                    if let authNetworkClient {
                        $0.authNetworkClient = authNetworkClient
                    }
                    if let signInHandoffClient {
                        $0.signInHandoffClient = signInHandoffClient
                    }
                }
                let onboardingStore = makeOnboardingStore(
                    progressClient: progressClient,
                    onboardingWindowClient: onboardingWindowClient,
                    permissionDebugScenario: permissionDebugScenario,
                    isForceFullDiskAccessGrantedEnabled: isForceFullDiskAccessGrantedEnabled,
                )
                return OnboardingWindowComposition(
                    onboardingStore: onboardingStore,
                    accountAccessStore: accountAccessStore,
                    handlesAuthCallback: true,
                )
            },
            isForceOnboardingEnabled: isForceOnboardingEnabled,
        )
    }

    nonisolated private static func makeClient(
        progressClient: OnboardingProgressClient,
        openMainWindow: @escaping @Sendable (_ request: OnboardingOpenMainWindowRequest) async -> Bool,
        makeComposition: @escaping @MainActor @Sendable (OnboardingWindowClient) -> OnboardingWindowComposition,
        isForceOnboardingEnabled: Bool = false,
    ) -> OnboardingWindowClient {
        let presentationGate = OnboardingPresentationGate()
        let forceOnboarding = LockIsolated(isForceOnboardingEnabled)
        let closeWindowBase: @Sendable () async -> Void = {
            await MainActor.run {
                onboardingWindowController?.dismissWithoutTerminate()
                onboardingWindowController = nil
            }
        }
        let closeWindow: @Sendable () async -> Void = {
            await closeWindowBase()
            forceOnboarding.withValue { $0 = false }
            presentationGate.reset()
        }
        let onboardingWindowClient = makeNestedOnboardingWindowClient(
            closeWindow: closeWindow,
            openMainWindow: openMainWindow,
        )
        let showWindow = makeShowWindow(
            onboardingWindowClient: onboardingWindowClient,
            makeComposition: makeComposition,
        )
        return OnboardingWindowClient(
            isRequired: {
                forceOnboarding.value || isOnboardingRequired(progressClient)
            },
            showIfNeeded: {
                let required = forceOnboarding.value || isOnboardingRequired(progressClient)

                if required, OnboardingOpenMainWindowAuthorization.isAuthorized {
                    return false
                }

                if required, presentationGate.claimPresentation() {
                    Task {
                        await showWindow()
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

    nonisolated private static func makeShowWindow(
        onboardingWindowClient: OnboardingWindowClient,
        makeComposition: @escaping @MainActor @Sendable (OnboardingWindowClient) -> OnboardingWindowComposition,
    ) -> @Sendable () async -> Void {
        {
            await MainActor.run {
                if onboardingWindowController == nil {
                    let composition = makeComposition(onboardingWindowClient)
                    onboardingWindowController = OnboardingWindowController(
                        onboardingStore: composition.onboardingStore,
                        accountAccessStore: composition.accountAccessStore,
                        handlesAuthCallback: composition.handlesAuthCallback,
                    )
                }

                onboardingWindowController?.showWindow(nil)
                onboardingWindowController?.window?.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    nonisolated private static func makeNestedOnboardingWindowClient(
        closeWindow: @escaping @Sendable () async -> Void,
        openMainWindow: @escaping @Sendable (_ request: OnboardingOpenMainWindowRequest) async -> Bool,
    ) -> OnboardingWindowClient {
        OnboardingWindowClient(
            isRequired: { false },
            showIfNeeded: { false },
            showWindow: {},
            closeWindow: closeWindow,
            openMainWindow: { request in
                await OnboardingOpenMainWindowAuthorization.$isAuthorized.withValue(true) {
                    await openMainWindow(request)
                }
            },
        )
    }

    @MainActor
    private static func makeOnboardingStore(
        progressClient: OnboardingProgressClient,
        onboardingWindowClient: OnboardingWindowClient,
        permissionDebugScenario: (@Sendable () -> OnboardingPermissionDebugScenario?)?,
        isForceFullDiskAccessGrantedEnabled: Bool,
    ) -> StoreOf<OnboardingFeature> {
        Store(initialState: OnboardingFeature.State()) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = progressClient
            $0.onboardingWindowClient = onboardingWindowClient
            configurePermissionDependencies(
                &$0,
                permissionDebugScenario: permissionDebugScenario,
                isForceFullDiskAccessGrantedEnabled: isForceFullDiskAccessGrantedEnabled,
            )
        }
    }

    private static func configurePermissionDependencies(
        _ dependencies: inout DependencyValues,
        permissionDebugScenario: (@Sendable () -> OnboardingPermissionDebugScenario?)?,
        isForceFullDiskAccessGrantedEnabled: Bool,
    ) {
        let liveFullDiskAccessClient = FullDiskAccessClient.liveValue
        let liveHelperFolderAccessClient = HelperFolderAccessClient.liveValue
        let liveLaunchAtLoginClient = LaunchAtLoginClient.liveValue
        if isForceFullDiskAccessGrantedEnabled || permissionDebugScenario != nil {
            dependencies.fullDiskAccessClient = FullDiskAccessClient(status: {
                if isForceFullDiskAccessGrantedEnabled {
                    return .granted
                }
                return permissionDebugScenario?()?.fullDiskAccessStatus ?? liveFullDiskAccessClient.status()
            })
        }
        if let permissionDebugScenario {
            dependencies.helperFolderAccessClient = HelperFolderAccessClient(
                checkAccess: {
                    if let helperFolderAccess = permissionDebugScenario()?.helperFolderAccess {
                        return helperFolderAccess
                    }
                    return await liveHelperFolderAccessClient.checkAccess()
                },
                requestAccess: {
                    if let helperFolderAccess = permissionDebugScenario()?.helperFolderAccess {
                        return helperFolderAccess
                    }
                    return await liveHelperFolderAccessClient.requestAccess()
                },
            )
            dependencies.launchAtLoginClient = LaunchAtLoginClient(
                isEnabled: {
                    permissionDebugScenario()?.launchAtLoginEnabled ?? liveLaunchAtLoginClient.isEnabled()
                },
                setEnabled: { _ in },
            )
        }
    }

    nonisolated private static func isOnboardingRequired(_ progressClient: OnboardingProgressClient) -> Bool {
        switch progressClient.load() {
        case let .success(snapshot):
            !snapshot.stepState.completeComplete
        case .empty, .resetRequired:
            true
        }
    }

    nonisolated static func isForceOnboardingEnabled(
        environmentValue: String?,
        isDebugBuild: Bool,
    ) -> Bool {
        isDebugBuild && environmentValue == "1"
    }

    nonisolated static func isForceFullDiskAccessGrantedEnabled(
        environmentValue: String?,
        isDebugBuild: Bool,
    ) -> Bool {
        isDebugBuild && environmentValue == "1"
    }

    nonisolated private static var isDebugBuild: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
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
