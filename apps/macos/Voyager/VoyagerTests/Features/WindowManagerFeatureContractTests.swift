import ComposableArchitecture
@testable import Voyager
import XCTest

@MainActor
final class WindowManagerFeatureContractTests: XCTestCase {
    func testApplyAppPreferencesFansOutToAllWindows() async {
        let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

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

        await store.send(.applyAppPreferences(preferences)) {
            $0.appPreferences = preferences
        }
        await store.receive(
            .windows(.element(id: firstID, action: .window(.applyAppPreferences(preferences)))),
        )
        await store.receive(
            .windows(.element(id: secondID, action: .window(.applyAppPreferences(preferences)))),
        )
    }

    func testQuickLookRoutesToFocusedWindowCommandBus() async {
        let focusedID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!

        var initialState = WindowManagerFeature.State()
        initialState.windows = [
            WindowSessionState(id: focusedID, window: .makeInitial(windowID: focusedID, path: "/tmp")),
        ]
        initialState.focusedWindowID = focusedID

        let store = TestStore(initialState: initialState) {
            WindowManagerFeature()
        }

        await store.send(.quickLook)
        await store.receive(
            .windows(.element(id: focusedID, action: .window(.request(.quickLookSelectedItem)))),
        )
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

        await store.send(.newFolder)
        await store.receive(
            .windows(.element(id: focusedID, action: .window(.request(.newFolder)))),
        )
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

        await store.send(.copy)
        await store.receive(
            .windows(.element(id: focusedID, action: .window(.request(.copy)))),
        )
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

        await store.send(.toggleSidebar)
        await store.receive(
            .windows(.element(id: focusedID, action: .window(.request(.toggleSidebar)))),
        )
    }

    func testNoCommandSentWhenNoFocusedWindow() async {
        let store = TestStore(initialState: WindowManagerFeature.State()) {
            WindowManagerFeature()
        }

        await store.send(.quickLook)
    }
}
