import AppKit
import ComposableArchitecture
import Foundation
import VoyagerEntitiesCollection
import VoyagerFeaturesExternalFileRouter
import VoyagerFeaturesUpdateVersion
import VoyagerPagesFileManager
import VoyagerPagesSettings
import VoyagerShared

@Reducer
struct AppRootFeature {
    typealias State = AppRootState
    typealias Action = AppRootAction

    @Dependency(\.collectionAlertClient)
    private var collectionAlertClient
    @Dependency(\.notificationCenterClient)
    private var notificationCenterClient

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
            return startLaunchObservers()

        case let .lifecycle(.delegate(delegateAction)):
            switch delegateAction {
            case .openInitialWindowIfNeeded:
                if hasPendingExternalRoutes(state) {
                    return flushPendingExternalRoutes(state: &state)
                }
                return .send(.windowManager(.lifecycle(.openInitialWindowIfNeeded)))

            case let .reopenWindowIfNeeded(hasVisibleWindows):
                return .send(.windowManager(.lifecycle(.reopenWindowIfNeeded(hasVisibleWindows: hasVisibleWindows))))
            }

        case .lifecycle(.termination(.willTerminate)):
            return .cancel(id: CancelID.appDidBecomeActiveObserver)

        case .appDidBecomeActive:
            return .none

        default:
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
            return .concatenate(
                .send(.settings(.selectSection(.ai))),
                .run { _ in
                    await MainActor.run {
                        openNativeSettingsScene()
                    }
                },
            )

        case let .settings(.delegate(.aiConnectionsFileUpdated(file))):
            return .send(.windowManager(.lifecycle(.aiConnectionsFileUpdated(file))))

        case .settings(.general(.checkForUpdates)):
            return .send(.updater(.checkForUpdates))

        case let .settings(.general(.toggleAutomaticUpdate(enabled))):
            return .send(.updater(.setAutomaticUpdate(enabled)))

        case let .externalFileRouter(.delegate(delegateAction)):
            return reduceExternalFileRouterDelegate(delegateAction)

        default:
            return .none
        }
    }

    private func reduceExternalFileRouterDelegate(
        _ action: ExternalFileRouterAction.Delegate,
    ) -> Effect<Action> {
        switch action {
        case .openAppFallback:
            .send(.windowManager(.lifecycle(.openInitialWindowIfNeeded)))

        case let .openFolder(path):
            // ExternalFileRouter가 폴더 열기 요청 — 새 File Manager Window로 라우팅
            .send(.windowManager(.file(.newWindow(path: path))))

        case let .openParentFolder(path, selectEntryPath):
            // ExternalFileRouter가 부모 폴더 열기 요청 — 새 File Manager Window로 라우팅
            .send(.windowManager(.file(.newWindow(path: path, selectEntryID: selectEntryPath))))

        case let .routeToAuthCallback(url):
            // ACC-001 소유의 OAuth callback — FMW-003가 가로채지 않음
            .send(.receiveAuthCallbackURL(url))

        case .showInvalidPathError:
            showExternalFileOpenError(
                title: "Voyager에서 위치를 열 수 없습니다",
                message: "선택한 위치를 찾을 수 없습니다. 경로를 확인한 뒤 다시 시도해 주세요.",
            )

        case let .showPermissionDeniedError(path):
            showExternalFileOpenError(
                title: "Voyager에서 위치를 열 수 없습니다",
                message: "접근 권한이 없어 \(path)를 열 수 없습니다. macOS 시스템 설정에서 Voyager의 파일 및 폴더 접근 권한을 확인해 주세요.",
            )

        case .selectEntryCompleted:
            .none
        }
    }

    private func reduceAuthCallback(
        into _: inout State,
        action: Action,
    ) -> Effect<Action> {
        switch action {
        case .receiveAuthCallbackURL:
            showExternalFileOpenError(
                title: "Voyager 로그인 복귀를 완료할 수 없습니다",
                message: "인증 callback을 계정 인증 흐름으로 전달하는 경로가 아직 연결되어 있지 않습니다. 다시 로그인해 주세요.",
            )

        default:
            .none
        }
    }

    private func reduceExternalURL(
        into state: inout State,
        action: Action,
    ) -> Effect<Action> {
        switch action {
        case let .receiveExternalURL(url):
            // 창이 없으면 버퍼링한다. launch 완료 전에는 didFinishLaunching delegate가 flush하고,
            // 이미 launch가 끝난 no-window 상태에서는 직접 initial window 경로를 요청한다.
            guard !state.windowManager.windows.isEmpty else {
                state.pendingExternalURLs.append(url)
                guard state.lifecycle.didFinishLaunching else { return .none }
                return .send(.lifecycle(.delegate(.openInitialWindowIfNeeded)))
            }
            // 창이 열려 있는 상태에서 ExternalFileRouter로 URL 전달
            return .send(.externalFileRouter(.receive(url)))

        default:
            return .none
        }
    }

    private func reduceExternalFileURL(
        into _: inout State,
        action: Action,
    ) -> Effect<Action> {
        switch action {
        case let .receiveExternalFileURL(url, source, mode):
            .send(.externalFileRouter(.receiveFileURL(url, source: source, mode: mode)))

        case let .receiveCollectionFileURL(url):
            .send(.windowManager(.file(.openCollectionFile(url))))

        default:
            .none
        }
    }

    /// didOpenFirstWindow 분기에서 버퍼링된 외부 URL 큐를 소비하고 리셋
    private func flushPendingExternalURL(state: inout State) -> Effect<Action> {
        let urls = state.pendingExternalURLs
        guard !urls.isEmpty else { return .none }
        state.pendingExternalURLs = []
        // 버퍼링된 URL을 적재 순서대로 ExternalFileRouter에 전달
        return .concatenate(urls.map { url in
            .send(.externalFileRouter(.receive(url)))
        })
    }

    /// Cold state에서 버퍼링된 file:// URL 큐를 flush
    private func flushPendingExternalFileRoutes(state: inout State) -> Effect<Action> {
        let routes = state.pendingExternalFileRoutes
        guard !routes.isEmpty else { return .none }
        state.pendingExternalFileRoutes = []
        return .concatenate(routes.map { route in
            .send(.externalFileRouter(.receiveFileURL(route.url, source: route.source, mode: route.mode)))
        })
    }

    private func hasPendingExternalRoutes(_ state: State) -> Bool {
        !state.pendingExternalURLs.isEmpty || !state.pendingExternalFileRoutes.isEmpty
    }

    private func flushPendingExternalRoutes(state: inout State) -> Effect<Action> {
        .concatenate(
            flushPendingExternalURL(state: &state),
            flushPendingExternalFileRoutes(state: &state),
        )
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
        return didOpenFirstWindow ? flushPendingExternalRoutes(state: &state) : .none
    }

    private func showExternalFileOpenError(title: String, message: String) -> Effect<Action> {
        .run { [collectionAlertClient] _ in
            await collectionAlertClient.showCollectionOpenErrorAlert(title, message)
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
