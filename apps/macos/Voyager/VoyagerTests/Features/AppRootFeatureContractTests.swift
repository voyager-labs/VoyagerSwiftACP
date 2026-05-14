import ComposableArchitecture
@testable import Voyager
import VoyagerPagesOnboarding
import XCTest

@MainActor
final class AppRootFeatureContractTests: XCTestCase {
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

    func testMenuCommandsDelegateForwardsToWindowManager() async {
        let store = TestStore(initialState: AppRootFeature.State()) {
            AppRootFeature()
        }

        await store.send(.menuCommands(.delegate(.windowManager(.file(.quickLook)))))
        await store.receive(\.windowManager.file.quickLook)
    }

    func testMenuCommandsDelegateForwardsToUpdater() async {
        let store = TestStore(initialState: AppRootFeature.State()) {
            AppRootFeature()
        }

        await store.send(.menuCommands(.delegate(.updater(.checkForUpdates))))
        await store.receive(\.updater.checkForUpdates)
    }

    func testWindowManagerOpenAISettingsDelegateSelectsAISettings() async {
        let store = TestStore(initialState: AppRootFeature.State()) {
            AppRootFeature()
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.windowManager(.delegate(.openAISettings)))
        await store.receive(.openAISettings)
        await store.receive(.settings(.selectSection(.ai)))
    }

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
        await store.receive(\.windowManager.windows)
    }

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
        await store.receive(\.windowManager.windows)
        await store.receive(\.windowManager.windows)
    }

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
}
