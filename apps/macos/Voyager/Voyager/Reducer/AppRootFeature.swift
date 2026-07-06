import AppKit
import ComposableArchitecture
import Foundation
import VoyagerFeaturesAccountAccess
import VoyagerFeaturesUpdateVersion
import VoyagerPagesFileManager
import VoyagerPagesSettings
import VoyagerShared

@Reducer
struct AppRootFeature {
    typealias State = AppRootState
    typealias Action = AppRootAction

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

        Reduce { state, action in
            reduceAppLifecycle(into: &state, action: action)
        }
        Reduce { state, action in
            reducePreferencesAndCommands(into: &state, action: action)
        }
        Reduce { state, _ in
            state.menuCommands = MenuCommandsState(state: state)
            return .none
        }
    }

    private func reduceAppLifecycle(
        into _: inout State,
        action: Action,
    ) -> Effect<Action> {
        switch action {
        case .lifecycle(.launch(.willFinishLaunching)):
            // ponytail: launch 1회 bootstrap — General/Appearance load를 SettingsFeature가 담당.
            .merge(
                startLaunchObservers(),
                .send(.settings(.bootstrapLocalPreferences)),
                .send(.settings(.ai(.onAppear))),
            )

        case let .lifecycle(.delegate(delegateAction)):
            reduceLifecycleDelegate(delegateAction)

        case .lifecycle(.termination(.willTerminate)):
            .cancel(id: CancelID.appDidBecomeActiveObserver)

        case .lifecycle(.sessionExpiredDetected):
            .merge(
                .send(.settings(.accessStatusLoaded(.none))),
                .send(.settings(.account(.access(._sessionExpiredDetected)))),
            )

        case let .lifecycle(.sessionLapseGuard(.delegate(.unlocked(snapshot)))):
            .send(.settings(.accessStatusLoaded(snapshot.status)))

        case let .lifecycle(.accountAccessGate(.accountAccessGranted(snapshot))):
            // ponytail: AppLifecycle이 fetch한 launch snapshot을 Settings hydration으로 1회 전달 +
            // AI bootstrap은 launch 시점으로 이동. didBootstrap가 탭 렌더 중복 send를 no-op 처리한다.
            .send(.settings(.appLifecycleAccessSnapshotReady(snapshot)))

        case .appDidBecomeActive:
            .none

        default:
            .none
        }
    }

    private func reduceLifecycleDelegate(
        _ delegateAction: AppLifecycleAction.Delegate,
    ) -> Effect<Action> {
        switch delegateAction {
        case .openInitialWindowIfNeeded:
            .send(.windowManager(.lifecycle(.openInitialWindowIfNeeded)))

        case let .reopenWindowIfNeeded(hasVisibleWindows):
            .send(.windowManager(.lifecycle(.reopenWindowIfNeeded(hasVisibleWindows: hasVisibleWindows))))

        case .startHelperIfNeeded:
            .none
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
            // ponytail: in-state gate. AppLifecycle snapshot hydration이 이미 state를 채움.
            // 활성 상태일 때만 AI tab 딥링크 선택. native Settings scene은 항상 오픈.
            let selectAI: Effect<Action> = state.settings.accessStatus.isActive
                ? .send(.settings(.selectSection(.ai)))
                : .none
            return .merge(
                selectAI,
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

        default:
            return .none
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
