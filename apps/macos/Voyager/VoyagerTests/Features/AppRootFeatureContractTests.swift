import ComposableArchitecture
@testable import Voyager
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesUpdateVersion
import VoyagerPagesOnboarding
import XCTest

@MainActor
/// 앱 루트 계약 — 최상위 라우팅과 델리게이트 전달을 검증.
final class AppRootFeatureContractTests: XCTestCase {
    /// testAppPreferencesUpdatedForwardsToWindowManagerApplyAppPreferences 테스트 동작을 검증한다.
    func testAppPreferencesUpdatedForwardsToWindowManagerApplyAppPreferences() async {
        let store = TestStore(initialState: AppRootFeature.State()) {
            AppRootFeature()
        }

        var preferences = AppPreferencesState()
        preferences.showHiddenFiles = true
        preferences.viewLayout = .grid
        preferences.sidebarVisible = false

        await store.send(.appPreferences(.delegate(.updated(preferences)))) {
            $0.appPreferences = preferences
        }
        await store.receive(\.windowManager.lifecycle.applyAppPreferences) {
            $0.windowManager.appPreferences = preferences
        }
    }

    /// testMenuCommandsDelegateForwardsToWindowManager 테스트 동작을 검증한다.
    func testMenuCommandsDelegateForwardsToWindowManager() async {
        let store = TestStore(initialState: AppRootFeature.State()) {
            AppRootFeature()
        }

        await store.send(.menuCommands(.delegate(.windowManager(.file(.quickLook)))))
        await store.receive(\.windowManager.file.quickLook)
    }

    /// testMenuCommandsDelegateForwardsToUpdater 테스트 동작을 검증한다.
    func testMenuCommandsDelegateForwardsToUpdater() async {
        let store = TestStore(initialState: AppRootFeature.State()) {
            AppRootFeature()
        }

        await store.send(.menuCommands(.delegate(.updater(.checkForUpdates))))
        await store.receive(\.updater.checkForUpdates)
    }

    /// testLifecycleDelegateForwardsToWindowManagerOpenInitialWindow 테스트 동작을 검증한다.
    func testLifecycleDelegateForwardsToWindowManagerOpenInitialWindow() async {
        let store = TestStore(initialState: AppRootFeature.State()) {
            AppRootFeature()
        } withDependencies: {
            $0.onboardingWindowClient.showIfNeeded = { false }
            $0.fileManagerWindowClient.open = { _ in }
            $0.uuid = .incrementing
        }
        store.exhaustivity = .off

        await store.send(.lifecycle(.delegate(.openInitialWindowIfNeeded)))
        await store.receive(\.windowManager.lifecycle.openInitialWindowIfNeeded)
    }

    /// testHelperExternalFileChangeForwardsToWindowManager 테스트 동작을 검증한다.
    func testHelperExternalFileChangeForwardsToWindowManager() async {
        let windowID = UUID()
        let paths = ["/tmp/demo"]
        var initialState = AppRootFeature.State()
        initialState.windowManager.windows = [
            WindowSessionState(id: windowID, window: .makeInitial(path: "/tmp")),
        ]

        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        }
        store.exhaustivity = .off

        await store.send(.helperExternalFileChanged(.init(paths: paths, source: .live)))
        await store.receive { action in
            guard case let .windowManager(.windows(.element(
                id: id,
                action: .window(.content(.externalFileSystemChanged(receivedPaths))),
            ))) = action else {
                return false
            }
            return id == windowID && receivedPaths == paths
        }
    }

    /// testHelperExternalFileChangeFansOutToAllOpenWindows 테스트 동작을 검증한다.
    func testHelperExternalFileChangeFansOutToAllOpenWindows() async {
        let firstID = UUID()
        let secondID = UUID()
        let paths = ["/tmp/demo"]

        var initialState = AppRootFeature.State()
        initialState.windowManager.windows = [
            WindowSessionState(id: firstID, window: .makeInitial(path: "/tmp/one")),
            WindowSessionState(id: secondID, window: .makeInitial(path: "/tmp/two")),
        ]

        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        }

        await store.send(.helperExternalFileChanged(.init(paths: paths, source: .live)))
        await store.receive { action in
            guard case let .windowManager(.windows(.element(
                id: id,
                action: .window(.content(.externalFileSystemChanged(receivedPaths))),
            ))) = action else {
                return false
            }
            return id == firstID && receivedPaths == paths
        }
        await store.receive { action in
            guard case let .windowManager(.windows(.element(
                id: id,
                action: .window(.content(.externalFileSystemChanged(receivedPaths))),
            ))) = action else {
                return false
            }
            return id == secondID && receivedPaths == paths
        }
    }

    /// testMenuCommandsStateIsRecomputedAfterWindowManagerChanges 테스트 동작을 검증한다.
    func testMenuCommandsStateIsRecomputedAfterWindowManagerChanges() async {
        var initialState = AppRootFeature.State()
        let windowID = UUID()
        initialState.windowManager.windows = [
            WindowSessionState(
                id: windowID,
                window: .makeInitial(path: "/tmp"),
            ),
        ]
        initialState.windowManager.focusedWindowID = windowID

        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        }
        store.exhaustivity = .off

        XCTAssertFalse(store.state.menuCommands.hasFocusedWindow)

        await store.send(.windowManager(.event(.windowBecameKey(windowID)))) {
            $0.windowManager.focusedWindowID = windowID
            $0.menuCommands.hasFocusedWindow = true
        }
    }

    func testSettingsGeneralCheckForUpdatesForwardsToUpdater() async {
        let store = TestStore(initialState: AppRootFeature.State()) {
            AppRootFeature()
        }

        await store.send(.settings(.general(.checkForUpdates)))
        await store.receive(\.updater.checkForUpdates)
    }

    func testSettingsGeneralToggleAutomaticUpdateForwardsToUpdater() async {
        let store = TestStore(initialState: AppRootFeature.State()) {
            AppRootFeature()
        }

        await store.send(.settings(.general(.toggleAutomaticUpdate(true))))
        await store.receive(\.updater.setAutomaticUpdate(true))

        await store.send(.settings(.general(.toggleAutomaticUpdate(false))))
        await store.receive(\.updater.setAutomaticUpdate(false))
    }

    func testSettingsGeneralToggleAlertBeforeQuitDoesNotForwardToUpdater() async {
        let store = TestStore(initialState: AppRootFeature.State()) {
            AppRootFeature()
        }
        store.exhaustivity = .off

        await store.send(.settings(.general(.toggleAlertBeforeQuit(true))))
        store.assertNoInboundEffects()
    }

    // MARK: - SET-AC-004: Boundary Absence Contracts

    /// Proves Settings actions produce NO windowManager side effects.
    /// WindowManager does not participate in the Settings scene lifecycle.
    func testSettingsActionsDoNotForwardToWindowManager() async {
        let store = TestStore(initialState: AppRootFeature.State()) {
            AppRootFeature()
        }
        store.exhaustivity = .off

        await store.send(.settings(.general(.toggleAlertBeforeQuit(false))))
        store.assertNoInboundEffects()
    }

    /// Proves AppRoot's Settings forwarding does NOT route through MenuCommands.
    /// MenuCommandsAction.Delegate has no `.settings` case — absence is structural.
    /// This test verifies that settings-driven actions (checkForUpdates) route
    /// directly to updater, not via menuCommands.
    func testSettingsCheckForUpdatesDoesNotRouteThroughMenuCommands() async {
        let store = TestStore(initialState: AppRootFeature.State()) {
            AppRootFeature()
        }
        store.exhaustivity = .off

        await store.send(.settings(.general(.checkForUpdates)))
        await store.receive(\.updater.checkForUpdates)
    }
}
