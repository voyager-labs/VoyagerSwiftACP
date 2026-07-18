import AppKit
import ComposableArchitecture
import Foundation
import VoyagerEntitiesCollection
import VoyagerFeaturesAccountAccess
import VoyagerFeaturesExternalFileRouter
import VoyagerFeaturesUpdateVersion
import VoyagerPagesFileManager
import VoyagerPagesOnboarding
import VoyagerPagesSettings
import VoyagerShared

@Reducer
struct AppRootFeature {
    typealias State = AppRootState
    typealias Action = AppRootAction

    @Dependency(\.collectionAlertClient)
    var collectionAlertClient
    @Dependency(\.notificationCenterClient)
    private var notificationCenterClient
    @Dependency(\.onboardingWindowClient)
    var onboardingWindowClient
    @Dependency(\.uuid)
    var uuid

    private enum CancelID {
        static let appDidBecomeActiveObserver = "appDidBecomeActiveObserver"
    }

    var body: some Reducer<State, Action> {
        Scope(state: \.lifecycle, action: \.lifecycle) {
            AppLifecycleFeature()
        }
        Scope(state: \.appPreferences, action: \.appPreferences) {
            AppPreferencesFeature()
        }
        Reduce { state, action in
            if case .windowManager = action {
                state.windowPresenceBeforeWindowManagerAction = !state.windowManager.windows.isEmpty
            }
            return .none
        }
        Scope(state: \.windowManager, action: \.windowManager) {
            WindowManagerFeature()
        }
        Scope(state: \.updater, action: \.updater) {
            UpdaterFeature()
        }
        Scope(state: \.settings, action: \.settings) {
            SettingsFeature()
        }
        Scope(state: \.menuCommands, action: \.menuCommands) {
            MenuCommandsFeature()
        }
        Scope(state: \.externalFileRouter, action: \.externalFileRouter) {
            ExternalFileRouterFeature()
        }

        Reduce { state, action in
            reduceAppLifecycle(into: &state, action: action)
        }
        Reduce { state, action in
            reducePreferencesAndCommands(into: &state, action: action)
        }
        Reduce { state, action in
            reduceAuthCallback(into: &state, action: action)
        }
        Reduce { state, action in
            reduceExternalURL(into: &state, action: action)
        }
        Reduce { state, action in
            reduceExternalFileURL(into: &state, action: action)
        }
        Reduce { state, action in
            reduceExternalOpenBatch(into: &state, action: action)
        }
        Reduce { state, action in
            reduceWindowPostAction(into: &state, action: action)
        }
        Reduce { state, _ in
            state.menuCommands = MenuCommandsState(state: state)
            return .none
        }
    }

    private func reduceAppLifecycle(
        into state: inout State,
        action: Action,
    ) -> Effect<Action> {
        switch action {
        case .lifecycle(.launch(.willFinishLaunching)):
            return .merge(
                startLaunchObservers(),
                .send(.settings(.bootstrapLocalPreferences)),
                .send(.settings(.ai(.onAppear))),
            )

        case let .lifecycle(.delegate(delegateAction)):
            return reduceLifecycleDelegate(into: &state, delegateAction)

        case .lifecycle(.termination(.willTerminate)):
            return .merge(
                .cancel(id: CancelID.appDidBecomeActiveObserver),
                handleActivePendingExternalURLGateClosure(state: &state),
                handleActiveExternalOpenBatchGateClosure(state: &state),
            )

        case .lifecycle(.sessionExpiredDetected):
            return .none

        case .lifecycle(.accountAccess):
            let presentationEffect = Effect<Action>.send(.settings(.accountAccessPresentationUpdated(
                makeAccountAccessPresentation(state.lifecycle.accountAccess),
            )))
            guard !state.lifecycle.isExternalRouteFlushAllowed else { return presentationEffect }
            return .merge(
                presentationEffect,
                handleActivePendingExternalURLGateClosure(state: &state),
                handleActiveExternalOpenBatchGateClosure(state: &state),
            )

        case .appDidBecomeActive:
            return .none

        default:
            return .none
        }
    }

    private func reduceLifecycleDelegate(
        into state: inout State,
        _ delegateAction: AppLifecycleAction.Delegate,
    ) -> Effect<Action> {
        switch delegateAction {
        case .openInitialWindowIfNeeded:
            if hasPendingExternalRoutes(state) {
                state.isExternalURLFlushDelegateScheduled = false
                guard !onboardingWindowClient.isRequired() else { return .none }
                guard canFlushPendingExternalRoutes(state) else {
                    guard state.lifecycle.accessGatePhase == .recoveryRequired else { return .none }
                    return .send(.windowManager(.lifecycle(.openInitialWindowIfNeeded)))
                }
                return flushPendingExternalRoutes(state: &state)
            }
            if state.isExternalURLRouteInFlightWithoutWindow {
                state.isExternalURLFlushDelegateScheduled = false
                return .none
            }
            guard state.lifecycle.isExternalRouteFlushAllowed else { return .none }
            return .send(.windowManager(.lifecycle(.openInitialWindowIfNeeded)))

        case let .reopenWindowIfNeeded(hasVisibleWindows):
            return .send(.windowManager(.lifecycle(.reopenWindowIfNeeded(hasVisibleWindows: hasVisibleWindows))))

        case .startHelperIfNeeded:
            return .none
        }
    }

    private func startLaunchObservers() -> Effect<Action> {
        .merge(
            .send(.appPreferences(.load)),
            .run { [notificationCenterClient] send in
                for await _ in notificationCenterClient.notifications(
                    NSApplication.didBecomeActiveNotification,
                    nil,
                ) {
                    await send(.appDidBecomeActive)
                }
            }
            .cancellable(id: CancelID.appDidBecomeActiveObserver, cancelInFlight: true),
        )
    }

    private func reducePreferencesAndCommands(
        into state: inout State,
        action: Action,
    ) -> Effect<Action> {
        switch action {
        case let .appPreferences(.delegate(.updated(preferences))):
            state.appPreferences = preferences
            return .send(.windowManager(.lifecycle(.applyAppPreferences(preferences))))

        case let .menuCommands(.delegate(.windowManager(action))):
            return .send(.windowManager(action))

        case let .menuCommands(.delegate(.updater(action))):
            return .send(.updater(action))

        case .windowManager(.delegate(.openAISettings)):
            return .send(.openAISettings)

        case .openAISettings:
            // 활성 상태일 때만 AI tab 딥링크 선택. native Settings scene은 항상 오픈.
            let selectAI: Effect<Action> = state.settings.accessStatus.isActive
                ? .send(.settings(.selectSection(.ai)))
                : .none
            let openSettings: Effect<Action> = isRunningXCTest()
                ? .none
                : .run { _ in
                    await MainActor.run {
                        openNativeSettingsScene()
                    }
                }
            return .merge(selectAI, openSettings)

        case let .settings(.delegate(delegateAction)):
            return reduceSettingsDelegate(into: &state, delegateAction)

        case .settings(.general(.checkForUpdates)):
            return .send(.updater(.checkForUpdates))

        case let .settings(.general(.toggleAutomaticUpdate(enabled))):
            return .send(.updater(.setAutomaticUpdate(enabled)))

        case let .externalFileRouter(action):
            return reduceExternalFileRouter(into: &state, action)

        default:
            return .none
        }
    }

    private func reduceSettingsDelegate(
        into state: inout State,
        _ delegateAction: SettingsAction.Delegate,
    ) -> Effect<Action> {
        switch delegateAction {
        case let .aiConnectionsFileUpdated(file):
            return .send(.windowManager(.lifecycle(.aiConnectionsFileUpdated(file))))

        case .account(.signInRequested):
            guard !state.lifecycle.accountAccess.hasAccountSession else { return .none }
            return .send(.lifecycle(.accountAccess(.loginTapped(context: .paywall, scope: .lifecycle))))

        case .account(.signOutRequested):
            return .send(.lifecycle(.accountAccess(.signOut)))

        case .account(.retryRequested):
            return .send(.lifecycle(.accountAccess(.retryTapped)))
        }
    }

    private func reduceExternalFileRouter(
        into state: inout State,
        _ action: ExternalFileRouterAction,
    ) -> Effect<Action> {
        switch action {
        case let .delegate(delegateAction):
            return reduceExternalFileRouterDelegate(into: &state, delegateAction)

        case let .failed(error, context):
            if let requestID = context?.trackedRequestID,
               !isCurrentTrackedPendingRequest(requestID, state: state)
            {
                return .none
            }
            if case .urlValidationError = error {
                state.isExternalURLFlushDelegateScheduled = false
                state.isExternalURLRouteInFlightWithoutWindow = false
            }
            return .none

        case let .singletonRequestCompleted(requestID):
            return consumePendingExternalURLCompletion(requestID: requestID, state: &state)

        default:
            return .none
        }
    }

    private func reduceExternalFileRouterDelegate(
        into state: inout State,
        _ action: ExternalFileRouterAction.Delegate,
    ) -> Effect<Action> {
        switch action {
        case let .openAppFallback(requestID):
            routeExternalAppFallback(requestID: requestID, state: &state)
        case let .openFolder(path, requestID):
            routeExternalFolder(path: path, requestID: requestID, state: &state)
        case let .openParentFolder(path, selectEntryPath, requestID):
            routeExternalParentFolder(
                path: path,
                selectEntryPath: selectEntryPath,
                requestID: requestID,
                state: &state,
            )
        case let .routeToAuthCallback(url, requestID):
            routeExternalAuthCallback(url: url, requestID: requestID, state: &state)
        case let .showInvalidPathError(_, requestID):
            showExternalRouteError(
                message: "선택한 위치를 찾을 수 없습니다. 경로를 확인한 뒤 다시 시도해 주세요.",
                requestID: requestID,
                state: &state,
            )
        case let .showPermissionDeniedError(path, requestID):
            showExternalRouteError(
                message: "접근 권한이 없어 \(path)를 열 수 없습니다. macOS 시스템 설정에서 Voyager의 파일 및 폴더 접근 권한을 확인해 주세요.",
                requestID: requestID,
                state: &state,
            )
        case let .batchNormalized(result):
            handleExternalOpenBatchNormalized(result, state: &state)
        case .selectEntryCompleted:
            .none
        }
    }

    private func reduceAuthCallback(
        into state: inout State,
        action: Action,
    ) -> Effect<Action> {
        switch action {
        case let .receiveAuthCallbackURL(url):
            return .send(.lifecycle(.accountAccess(.loginCallbackReceived(url))))

        case let .receiveTrackedAuthCallbackURL(url, requestID):
            guard isCurrentTrackedPendingRequest(requestID, state: state) else { return .none }
            // Production AppDelegate는 receiveAuthCallbackURL을 직접 사용한다. tracked compatibility는
            // AccountAccess handoff 수락을 terminal로 삼고 전체 network lifecycle은 기다리지 않는다.
            return .concatenate(
                .send(.lifecycle(.accountAccess(.loginCallbackReceived(url)))),
                .send(.externalFileRouter(.singletonRequestCompleted(requestID))),
            )

        default:
            return .none
        }
    }

    private func reduceExternalURL(
        into state: inout State,
        action: Action,
    ) -> Effect<Action> {
        switch action {
        case let .receiveExternalURL(url):
            let shouldSchedule = state.windowManager.windows.isEmpty
                || hasPendingExternalRoutes(state)
                || !canFlushPendingExternalRoutes(state)
            guard shouldSchedule else {
                // idle warm-window untracked behavior는 기존 AppDelegate/menu route와 호환되게 유지한다.
                return .send(.externalFileRouter(.receive(url)))
            }

            state.pendingExternalURLs.append(url)
            guard state.windowManager.windows.isEmpty else {
                return flushPendingExternalRoutes(state: &state)
            }
            state.isExternalURLRouteInFlightWithoutWindow = true
            guard state.lifecycle.didFinishLaunching,
                  !state.isExternalURLFlushDelegateScheduled
            else { return .none }
            state.isExternalURLFlushDelegateScheduled = true
            return .send(.lifecycle(.delegate(.openInitialWindowIfNeeded)))

        default:
            return .none
        }
    }

    private func reduceWindowPostAction(
        into state: inout State,
        action: Action,
    ) -> Effect<Action> {
        guard case .windowManager = action else { return .none }

        let hadWindowsBeforeAction = state.windowPresenceBeforeWindowManagerAction ?? false
        let hasWindowsAfterAction = !state.windowManager.windows.isEmpty
        let didOpenFirstWindow = !hadWindowsBeforeAction && hasWindowsAfterAction
        state.windowPresenceBeforeWindowManagerAction = nil
        if hasWindowsAfterAction {
            state.isExternalURLRouteInFlightWithoutWindow = false
        }
        guard didOpenFirstWindow,
              state.activeExternalOpenBatch == nil,
              canFlushPendingExternalRoutes(state)
        else { return .none }
        return flushPendingExternalRoutes(state: &state)
    }

    private func makeAccountAccessPresentation(
        _ accountAccess: AccountAccessFeature.State,
    ) -> AccountAccessPresentation {
        AccountAccessPresentation(
            hasAccountSession: accountAccess.hasAccountSession,
            isSignInInProgress: accountAccess.isSignInInProgress,
            didSignInFail: accountAccess.didSignInFail,
            accessStatus: accountAccess.status,
        )
    }

    private func openSettingsSceneEffect() -> Effect<Action> {
        isRunningXCTest()
            ? .none
            : .run { _ in
                await MainActor.run {
                    openNativeSettingsScene()
                }
            }
    }
}

@MainActor
private func openNativeSettingsScene() {
    NSApp.activate(ignoringOtherApps: true)

    if performSettingsMenuItem() {
        return
    }

    let settingsSelector = Selector(("showSettingsWindow:"))
    if NSApp.sendAction(settingsSelector, to: nil, from: nil) {
        return
    }

    let preferencesSelector = Selector(("showPreferencesWindow:"))
    _ = NSApp.sendAction(preferencesSelector, to: nil, from: nil)
}

@MainActor
private func performSettingsMenuItem() -> Bool {
    guard let mainMenu = NSApp.mainMenu else { return false }

    for item in mainMenu.items {
        guard let submenu = item.submenu else { continue }
        if performSettingsMenuItem(in: submenu) {
            return true
        }
    }

    return false
}

@MainActor
private func performSettingsMenuItem(in menu: NSMenu) -> Bool {
    for index in 0 ..< menu.numberOfItems {
        guard let item = menu.item(at: index) else { continue }
        if isSettingsMenuItem(item) {
            if let action = item.action,
               NSApp.sendAction(action, to: item.target, from: item)
            {
                return true
            }

            menu.performActionForItem(at: index)
            return true
        }

        if let submenu = item.submenu,
           performSettingsMenuItem(in: submenu)
        {
            return true
        }
    }

    return false
}

private func isSettingsMenuItem(_ item: NSMenuItem) -> Bool {
    let normalizedTitle = item.title
        .replacingOccurrences(of: "…", with: "")
        .replacingOccurrences(of: "...", with: "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()

    return normalizedTitle == "settings"
        || normalizedTitle == "preferences"
        || item.action == Selector(("showSettingsWindow:"))
        || item.action == Selector(("showPreferencesWindow:"))
}

private func isRunningXCTest() -> Bool {
    ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
}
