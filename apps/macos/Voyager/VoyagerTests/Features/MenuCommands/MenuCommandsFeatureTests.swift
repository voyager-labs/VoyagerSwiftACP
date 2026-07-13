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
            (.restoreLastClosedTab, .file(.restoreLastClosedTab)),
            (.duplicateTab, .file(.duplicateTab)),
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

    /// testCanRestoreLastClosedTabReflectsFocusedWindowRecentlyClosedState 테스트 동작을 검증한다.
    /// focused window의 contentTabs.recentlyClosed 상태에 따라
    /// canRestoreLastClosedTab이 올바르게 반영되는지 검증한다.
    func testCanRestoreLastClosedTabReflectsFocusedWindowRecentlyClosedState() {
        let focusedID = makeUUID("00000000-0000-0000-0000-000000000044")

        // Arrange: recentlyClosed가 nil인 focused window
        var focusedWindow = FileManagerFeature.State.makeInitial(path: "/Users/test/Documents")
        focusedWindow.contentTabs.recentlyClosed = nil

        var appState = AppRootState()
        appState.windowManager.windows = [
            WindowSessionState(id: focusedID, window: focusedWindow),
        ]
        appState.windowManager.focusedWindowID = focusedID

        XCTAssertFalse(MenuCommandsState(state: appState).canRestoreLastClosedTab)

        // Arrange: recentlyClosed에 유효한 snapshot이 있는 focused window
        let snapshot = ClosedContentTabSnapshot(
            page: .directory,
            anchor: .directory(path: "/Users/test/Documents"),
            wasPinned: false,
            closedAt: Date(),
            title: "Documents",
            iconName: "folder",
        )
        focusedWindow.contentTabs.recentlyClosed = snapshot
        appState.windowManager.windows[id: focusedID]?.window = focusedWindow

        XCTAssertTrue(MenuCommandsState(state: appState).canRestoreLastClosedTab)
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

    // MARK: - Duplicate Tab Projection & Routing

    /// canDuplicateActiveContentTab은 focused window에 active tab이 있고
    /// pending close가 없으며 tab count가 max 미만일 때 true여야 한다.
    func testDuplicateTabProjection_enabledWhenActiveTabExists() {
        let focusedID = makeUUID("00000000-0000-0000-0000-000000000050")

        var focusedWindow = FileManagerFeature.State.makeInitial(path: "/Users/test/Documents")
        focusedWindow.pendingContentTabClose = nil

        var appState = AppRootState()
        appState.windowManager.windows = [
            WindowSessionState(id: focusedID, window: focusedWindow),
        ]
        appState.windowManager.focusedWindowID = focusedID

        XCTAssertTrue(MenuCommandsState(state: appState).canDuplicateActiveContentTab)
    }

    /// focused window가 없으면 canDuplicateActiveContentTab은 false여야 한다.
    func testDuplicateTabProjection_disabledWhenNoFocusedWindow() {
        let focusedID = makeUUID("00000000-0000-0000-0000-000000000051")

        var focusedWindow = FileManagerFeature.State.makeInitial(path: "/Users/test/Documents")
        focusedWindow.pendingContentTabClose = nil

        var appState = AppRootState()
        appState.windowManager.windows = [
            WindowSessionState(id: focusedID, window: focusedWindow),
        ]
        // focusedWindowID를 설정하지 않음

        XCTAssertFalse(MenuCommandsState(state: appState).canDuplicateActiveContentTab)
    }

    /// pendingContentTabClose가 nil이 아니면 canDuplicateActiveContentTab은 false여야 한다.
    func testDuplicateTabProjection_disabledWhenPendingClose() {
        let focusedID = makeUUID("00000000-0000-0000-0000-000000000052")

        var focusedWindow = FileManagerFeature.State.makeInitial(path: "/Users/test/Documents")
        guard let activeTabID = focusedWindow.contentTabs.activeTabID else {
            XCTFail("Expected active content tab")
            return
        }
        focusedWindow.pendingContentTabClose = PendingContentTabClose(tabID: activeTabID)

        var appState = AppRootState()
        appState.windowManager.windows = [
            WindowSessionState(id: focusedID, window: focusedWindow),
        ]
        appState.windowManager.focusedWindowID = focusedID

        XCTAssertFalse(MenuCommandsState(state: appState).canDuplicateActiveContentTab)
    }

    /// tab count가 maxTabs에 도달하면 canDuplicateActiveContentTab은 false여야 한다.
    func testDuplicateTabProjection_disabledWhenMaxTabs() {
        let focusedID = makeUUID("00000000-0000-0000-0000-000000000053")

        var focusedWindow = FileManagerFeature.State.makeInitial(path: "/Users/test/Documents")
        focusedWindow.pendingContentTabClose = nil
        // maxTabs까지 탭을 채움
        while focusedWindow.contentTabs.tabs.count < ContentTabConstants.maxTabs {
            let newTab = ContentTabState.withHomeTab()
            if let tab = newTab.tabs.first {
                focusedWindow.contentTabs.tabs.append(tab)
            }
        }
        XCTAssertEqual(focusedWindow.contentTabs.tabs.count, ContentTabConstants.maxTabs)

        var appState = AppRootState()
        appState.windowManager.windows = [
            WindowSessionState(id: focusedID, window: focusedWindow),
        ]
        appState.windowManager.focusedWindowID = focusedID

        XCTAssertFalse(MenuCommandsState(state: appState).canDuplicateActiveContentTab)
    }

    /// AppCommand .duplicateTab이 MenuCommandsFeature를 통해
    /// .delegate(.windowManager(.file(.duplicateTab)))로 라우팅되는지 검증한다.
    func testAppCommandDuplicateTab_routesToFileCommand() async {
        await assertAppCommand(.duplicateTab, routesTo: .file(.duplicateTab))
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
        // 비포괄적: app command → delegate(.windowManager(action)) 단일 라우팅만 검증하며,
        // MenuCommandsFeature가 delegate 외부로 방출하는 다른 부수 효과는 검증 범위 밖이다.
        store.exhaustivity = .off

        await store.send(.view(.app(command)))
        await store.receive {
            guard case let .delegate(.windowManager(action)) = $0 else { return false }
            switch (action, expected) {
            case (.file(.newTab), .file(.newTab)),
                 (.file(.togglePinTab), .file(.togglePinTab)),
                 (.file(.open), .file(.open)),
                 (.file(.quickLook), .file(.quickLook)),
                 (.file(.restoreLastClosedTab), .file(.restoreLastClosedTab)),
                 (.file(.duplicateTab), .file(.duplicateTab)):
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
