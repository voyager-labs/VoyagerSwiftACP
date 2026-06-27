import ComposableArchitecture
@testable import Voyager
import VoyagerFeaturesEntryArrangements
import VoyagerFeaturesUpdateVersion
@testable import VoyagerPagesFileManager
import XCTest

/// 메뉴 명령 기능 — 앱/보기/편집/작업 명령의 델리게이트 라우팅을 검증.
@MainActor
final class MenuCommandsFeatureTests: XCTestCase {
    /// testAppCommandRoutesToUpdaterDelegate 테스트 동작을 검증한다.
    func testAppCommandRoutesToUpdaterDelegate() async {
        let store = TestStore(initialState: MenuCommandsFeature.State()) {
            MenuCommandsFeature()
        }
        store.exhaustivity = .off

        await store.send(.view(.app(.checkForUpdates)))
        await store.receive {
            guard case .delegate(.updater(.checkForUpdates)) = $0 else { return false }
            return true
        }
        await store.finish()
    }

    /// testTask3EntryCommandsRouteToWindowManagerDelegate 테스트 동작을 검증한다.
    func testTask3EntryCommandsRouteToWindowManagerDelegate() async {
        let appCases: [(MenuCommandItem.AppCommand, WindowManagerAction)] = [
            (.newTab, .file(.newTab)),
            (.togglePinTab, .file(.togglePinTab)),
            (.open, .file(.open)),
            (.quickLook, .file(.quickLook)),
        ]

        for (command, expected) in appCases {
            await assertAppCommand(command, routesTo: expected)
        }

        let editCases: [(MenuCommandItem.EditCommand, WindowManagerAction)] = [
            (.cut, .edit(.cut)),
            (.copy, .edit(.copy)),
            (.openContextualAiChat, .edit(.openContextualAiChat)),
            (.paste, .edit(.paste)),
            (.duplicate, .edit(.duplicate)),
            (.makeAlias, .edit(.makeAlias)),
            (.copyAbsolutePaths, .edit(.copyAbsolutePaths)),
            (.copyURLs, .edit(.copyURLs)),
        ]

        for (command, expected) in editCases {
            await assertEditCommand(command, routesTo: expected)
        }

        let store = TestStore(initialState: MenuCommandsFeature.State()) {
            MenuCommandsFeature()
        }
        store.exhaustivity = .off

        await store.send(.view(.viewCommand(.toggleShowHiddenFiles)))
        await store.receive {
            guard case let .delegate(.windowManager(action)) = $0 else { return false }
            guard case .window(.toggleShowHiddenFiles) = action else { return false }
            return true
        }
        await store.finish()
    }

    func testMenuCommandStateReflectsFocusedWindowContextualAiChatPresentation() {
        let focusedID = makeUUID("00000000-0000-0000-0000-000000000041")
        let unfocusedID = makeUUID("00000000-0000-0000-0000-000000000042")

        var focusedWindow = FileManagerFeature.State.makeInitial(path: "/Users/test/Documents")
        focusedWindow.inspector.inspectorVisible = true
        focusedWindow.inspector.inspectorPaneExists = true
        focusedWindow.inspector.activeMode = .chat

        var unfocusedWindow = FileManagerFeature.State.makeInitial(path: "/Users/test/Downloads")
        unfocusedWindow.inspector.inspectorVisible = false
        unfocusedWindow.inspector.activeMode = .chat

        var appState = AppRootState()
        appState.windowManager.windows = [
            WindowSessionState(id: focusedID, window: focusedWindow),
            WindowSessionState(id: unfocusedID, window: unfocusedWindow),
        ]
        appState.windowManager.focusedWindowID = focusedID

        XCTAssertTrue(MenuCommandsState(state: appState).isContextualAiChatPresented)

        appState.windowManager.windows[id: focusedID]?.window.inspector.inspectorPaneExists = false

        XCTAssertFalse(MenuCommandsState(state: appState).isContextualAiChatPresented)

        appState.windowManager.windows[id: focusedID]?.window.inspector.inspectorPaneExists = true
        appState.windowManager.windows[id: focusedID]?.window.inspector.inspectorVisible = false

        XCTAssertFalse(MenuCommandsState(state: appState).isContextualAiChatPresented)
    }

    func testCloseTabTitleReflectsActivePinnedContentTab() {
        let focusedID = makeUUID("00000000-0000-0000-0000-000000000043")
        var focusedWindow = FileManagerFeature.State.makeInitial(path: "/Users/test/Documents")
        guard let activeTabID = focusedWindow.contentTabs.activeTabID else {
            XCTFail("Expected active content tab")
            return
        }

        var appState = AppRootState()
        appState.windowManager.windows = [
            WindowSessionState(id: focusedID, window: focusedWindow),
        ]
        appState.windowManager.focusedWindowID = focusedID

        let unpinnedMenuState = MenuCommandsState(state: appState)
        XCTAssertEqual(unpinnedMenuState.closeTabTitle, "Close Tab")
        XCTAssertTrue(unpinnedMenuState.showsCloseTabCommand)
        XCTAssertEqual(unpinnedMenuState.pinTabTitle, "Pin Tab")

        focusedWindow.contentTabs.tabs[id: activeTabID]?.isPinned = true
        appState.windowManager.windows[id: focusedID]?.window = focusedWindow

        let pinnedMenuState = MenuCommandsState(state: appState)
        XCTAssertEqual(pinnedMenuState.closeTabTitle, "Close Tab")
        XCTAssertFalse(pinnedMenuState.showsCloseTabCommand)
        XCTAssertEqual(pinnedMenuState.pinTabTitle, "Unpin Tab")
    }

    private func makeUUID(_ rawValue: String) -> UUID {
        guard let uuid = UUID(uuidString: rawValue) else {
            XCTFail("Invalid UUID fixture: \(rawValue)")
            return UUID()
        }
        return uuid
    }

    private func assertAppCommand(
        _ command: MenuCommandItem.AppCommand,
        routesTo expected: WindowManagerAction,
    ) async {
        let store = TestStore(initialState: MenuCommandsFeature.State()) {
            MenuCommandsFeature()
        }
        store.exhaustivity = .off

        await store.send(.view(.app(command)))
        await store.receive {
            guard case let .delegate(.windowManager(action)) = $0 else { return false }
            switch (action, expected) {
            case (.file(.newTab), .file(.newTab)),
                 (.file(.togglePinTab), .file(.togglePinTab)),
                 (.file(.open), .file(.open)),
                 (.file(.quickLook), .file(.quickLook)):
                return true
            default:
                return false
            }
        }
        await store.finish()
    }

    private func assertEditCommand(
        _ command: MenuCommandItem.EditCommand,
        routesTo expected: WindowManagerAction,
    ) async {
        let store = TestStore(initialState: MenuCommandsFeature.State()) {
            MenuCommandsFeature()
        }
        store.exhaustivity = .off

        await store.send(.view(.edit(command)))
        await store.receive {
            guard case let .delegate(.windowManager(action)) = $0 else { return false }
            switch (action, expected) {
            case (.edit(.cut), .edit(.cut)),
                 (.edit(.copy), .edit(.copy)),
                 (.edit(.openContextualAiChat), .edit(.openContextualAiChat)),
                 (.edit(.paste), .edit(.paste)),
                 (.edit(.duplicate), .edit(.duplicate)),
                 (.edit(.makeAlias), .edit(.makeAlias)),
                 (.edit(.copyAbsolutePaths), .edit(.copyAbsolutePaths)),
                 (.edit(.copyURLs), .edit(.copyURLs)):
                return true
            default:
                return false
            }
        }
        await store.finish()
    }
}
