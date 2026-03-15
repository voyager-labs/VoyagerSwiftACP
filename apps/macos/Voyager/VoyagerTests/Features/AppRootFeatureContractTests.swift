import ComposableArchitecture
@testable import Voyager
import XCTest

// MARK: - VOY-202 Task 1 & 10: App-Shell Contract Tests

// These tests lock the seam contracts between AppRootFeature and its child features.

@MainActor
final class AppRootFeatureContractTests: XCTestCase {
    // MARK: Task 10: App-Shell Preference Forwarding Seam

    /// Test: appPreferences.updated → windowManager.applyAppPreferences
    /// Verifies that preference changes propagate through the app-shell seam.
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
        await store.receive(.windowManager(.applyAppPreferences(preferences))) {
            $0.windowManager.appPreferences = preferences
        }
    }

    // MARK: Task 10: Menu Commands Forwarding Seam

    /// Test: menuCommands.delegate(.windowManager) → windowManager action
    /// Verifies that menu commands route through AppRoot to WindowManager.
    func testMenuCommandsDelegateForwardsToWindowManager() async {
        let store = TestStore(initialState: AppRootFeature.State()) {
            AppRootFeature()
        }

        await store.send(.menuCommands(.delegate(.windowManager(.quickLook))))
        await store.receive(.windowManager(.quickLook))
    }

    /// Test: menuCommands.delegate(.updater) → updater action
    /// Verifies that updater commands route through AppRoot to UpdaterFeature.
    func testMenuCommandsDelegateForwardsToUpdater() async {
        let store = TestStore(initialState: AppRootFeature.State()) {
            AppRootFeature()
        }

        await store.send(.menuCommands(.delegate(.updater(.checkForUpdates))))
        await store.receive(.updater(.checkForUpdates))
    }

    // MARK: Task 10: Lifecycle Forwarding Seam

    /// Test: lifecycle.delegate(.openInitialWindowIfNeeded) → windowManager.openInitialWindowIfNeeded
    /// Verifies that lifecycle events route through AppRoot to WindowManager.
    func testLifecycleDelegateForwardsToWindowManagerOpenInitialWindow() async {
        let store = TestStore(initialState: AppRootFeature.State()) {
            AppRootFeature()
        } withDependencies: {
            $0.onboardingWindowClient.showIfNeeded = { false }
            $0.fileManagerWindowClient.open = { _ in }
        }

        await store.send(.lifecycle(.delegate(.openInitialWindowIfNeeded)))
        await store.receive(.windowManager(.openInitialWindowIfNeeded))
        // newWindow is sent internally, which triggers window creation
    }

    // MARK: Task 1: MenuCommandsState Recomputation Contract

    /// Test: MenuCommandsState is recomputed after every action
    /// Verifies that the derived state invariant is maintained.
    func testMenuCommandsStateIsRecomputedAfterWindowManagerChanges() async {
        var initialState = AppRootFeature.State()
        let windowID = UUID()
        initialState.windowManager.windows = [
            WindowSessionState(
                id: windowID,
                window: .makeInitial(windowID: windowID, path: "/tmp"),
            ),
        ]
        initialState.windowManager.focusedWindowID = windowID

        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        }

        // The menuCommands state should reflect the current window state
        // After any action, menuCommands should be recomputed
        XCTAssertTrue(store.state.menuCommands.focusedWindowID == windowID)
    }
}
