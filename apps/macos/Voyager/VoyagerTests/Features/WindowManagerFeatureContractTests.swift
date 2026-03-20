import ComposableArchitecture
@testable import Voyager
import VoyagerPagesOnboarding
import XCTest

@MainActor
final class WindowManagerFeatureContractTests: XCTestCase {
    func testApplyAppPreferencesFansOutToAllWindows() async {
        let firstID = UUID()
        let secondID = UUID()

        var initialState = WindowManagerFeature.State()
        initialState.windows = [
            WindowSessionState(id: firstID, window: .makeInitial(windowID: firstID, path: "/a")),
            WindowSessionState(id: secondID, window: .makeInitial(windowID: secondID, path: "/b")),
        ]

        var preferences = AppPreferencesState()
        preferences.viewLayout = .grid
        preferences.groupKey = .kind

        let store = TestStore(initialState: initialState) {
            WindowManagerFeature()
        } withDependencies: {
            $0.onboardingWindowClient.showIfNeeded = { false }
            $0.fileManagerWindowClient.open = { _ in }
        }
        store.exhaustivity = .off

        await store.send(.applyAppPreferences(preferences)) {
            $0.appPreferences = preferences
        }
    }

    func testQuickLookRoutesToFocusedWindowCommandBus() async {
        let focusedID = UUID()

        var initialState = WindowManagerFeature.State()
        initialState.windows = [
            WindowSessionState(id: focusedID, window: .makeInitial(windowID: focusedID, path: "/tmp")),
        ]
        initialState.focusedWindowID = focusedID

        let store = TestStore(initialState: initialState) {
            WindowManagerFeature()
        }
        store.exhaustivity = .off

        await store.send(.quickLook)
    }

    func testNewFolderRoutesToFocusedWindow() async {
        let focusedID = UUID()

        var initialState = WindowManagerFeature.State()
        initialState.windows = [
            WindowSessionState(id: focusedID, window: .makeInitial(windowID: focusedID, path: "/tmp")),
        ]
        initialState.focusedWindowID = focusedID

        let store = TestStore(initialState: initialState) {
            WindowManagerFeature()
        }
        store.exhaustivity = .off

        await store.send(.newFolder)
    }

    func testCopyRoutesToFocusedWindow() async {
        let focusedID = UUID()

        var initialState = WindowManagerFeature.State()
        initialState.windows = [
            WindowSessionState(id: focusedID, window: .makeInitial(windowID: focusedID, path: "/tmp")),
        ]
        initialState.focusedWindowID = focusedID

        let store = TestStore(initialState: initialState) {
            WindowManagerFeature()
        }
        store.exhaustivity = .off

        await store.send(.copy)
    }

    func testToggleSidebarRoutesToFocusedWindow() async {
        let focusedID = UUID()

        var initialState = WindowManagerFeature.State()
        initialState.windows = [
            WindowSessionState(id: focusedID, window: .makeInitial(windowID: focusedID, path: "/tmp")),
        ]
        initialState.focusedWindowID = focusedID

        let store = TestStore(initialState: initialState) {
            WindowManagerFeature()
        }
        store.exhaustivity = .off

        await store.send(.toggleSidebar)
    }

    func testNoCommandSentWhenNoFocusedWindow() async {
        let store = TestStore(initialState: WindowManagerFeature.State()) {
            WindowManagerFeature()
        }

        await store.send(.quickLook)
    }
}
