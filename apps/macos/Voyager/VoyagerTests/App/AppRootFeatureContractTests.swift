import ComposableArchitecture
@testable import Voyager
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesUpdateVersion
@testable import VoyagerPagesFileManager
import VoyagerPagesOnboarding
import VoyagerPagesSettings
import VoyagerShared
import VoyagerWidgetsEntryViewLayout
import XCTest

/// 앱 루트 계약 — 최상위 라우팅과 델리게이트 전달을 검증.
@MainActor
final class AppRootFeatureContractTests: XCTestCase {
    /// testAppPreferencesUpdatedForwardsToWindowManagerApplyAppPreferences 테스트 동작을 검증한다.
    func testAppPreferencesUpdatedForwardsToWindowManagerApplyAppPreferences() async {
        let store = TestStore(initialState: AppRootFeature.State()) {
            AppRootFeature()
        }

        var preferences = Voyager.AppPreferencesState()
        preferences.showHiddenFiles = true
        preferences.viewLayout = EntryViewLayoutState.Mode.grid
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
        var initialState = AppRootFeature.State()
        initialState.windowManager.windows = [
            WindowSessionState(
                id: UUID(),
                window: .makeInitial(path: "/tmp"),
            ),
        ]

        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        }

        await store.send(.lifecycle(.delegate(.openInitialWindowIfNeeded)))
        await store.receive(\.windowManager.lifecycle.openInitialWindowIfNeeded)
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
        } withDependencies: {
            $0.userDefaultsClient.setBool = { _, _ in }
            $0.updaterClient.setAutomaticUpdate = { _ in }
        }

        store.exhaustivity = .off

        await store.send(.settings(.general(.toggleAutomaticUpdate(true))))
        await store.receive { action in
            guard case .updater(.setAutomaticUpdate(true)) = action else {
                return false
            }
            return true
        }

        await store.send(.settings(.general(.toggleAutomaticUpdate(false))))
        await store.receive { action in
            guard case .updater(.setAutomaticUpdate(false)) = action else {
                return false
            }
            return true
        }
    }
}
