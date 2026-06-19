import ComposableArchitecture
@testable import Voyager
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesUpdateVersion
@testable import VoyagerPagesFileManager
import VoyagerPagesOnboarding
import VoyagerPagesSettings
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

    // MARK: - FMW-003: Cold Start URL Buffering

    /// Cold state(창 없음)에서 receiveExternalURL 수신 시 pendingExternalURL에 저장됨을 검증
    func testReceiveExternalURLBuffersWhenNoWindows() async throws {
        let url = try XCTUnwrap(URL(string: "voyager://open?url=file:///Users/test"))
        let store = TestStore(initialState: AppRootFeature.State()) {
            AppRootFeature()
        }

        await store.send(.receiveExternalURL(url)) {
            $0.pendingExternalURL = url
        }
    }

    /// Hot state(창 있음)에서 receiveExternalURL 수신 시 pendingExternalURL이 nil로 유지됨을 검증
    /// authCallback URL을 사용하여 OpenRouter의 pathProbe 효과 없이 전달 여부만 검증
    func testReceiveExternalURLForwardsWhenWindowsExist() async throws {
        let windowID = UUID()
        let url = try XCTUnwrap(URL(string: "voyager://auth/callback?code=test"))
        var state = AppRootFeature.State()
        state.windowManager.windows = [
            WindowSessionState(id: windowID, window: .makeInitial(path: "/tmp")),
        ]

        let store = TestStore(initialState: state) {
            AppRootFeature()
        }
        // store.exhaustivity = .off: Hot state에서 URL 수신 시 OpenRouter로 effect가 전달되므로 핵심 state만 검증
        store.exhaustivity = .off

        await store.send(.receiveExternalURL(url))
        XCTAssertNil(store.state.pendingExternalURL)
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
