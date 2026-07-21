import ComposableArchitecture
@testable import Voyager
import VoyagerFeaturesAiChat
import VoyagerFeaturesEntryArrangements
import VoyagerFeaturesEntryOperations
import VoyagerFeaturesUpdateVersion
@testable import VoyagerPagesFileManager
import VoyagerWidgetsEntryViewLayout
import XCTest

/// 메뉴 명령 기능 — 앱/보기/편집/작업 명령의 델리게이트 라우팅을 검증.
@MainActor
final class MenuCommandsFeatureTests: XCTestCase {
    /// testAppCommandRoutesToUpdaterDelegate 테스트 동작을 검증한다.
    func testAppCommandRoutesToUpdaterDelegate() async {
        let store = TestStore(initialState: MenuCommandsFeature.State()) {
            MenuCommandsFeature()
        }
        // store.exhaustivity = .off: delegate 라우팅 action만 검증하고 내부 상태 전체 비교는 생략한다.
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
        ]

        for (command, expected) in appCases {
            await assertAppCommand(command, routesTo: expected)
        }

        let editCases: [(MenuCommandItem.EditCommand, WindowManagerAction)] = [
            (.cut, .edit(.cut)),
            (.copy, .edit(.copy)),
            (.newChat, .edit(.newChat)),
            (.showChatHistory, .edit(.showChatHistory)),
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
        // store.exhaustivity = .off: 여러 command의 delegate 라우팅만 검증하고 내부 상태 전체 비교는 생략한다.
        store.exhaustivity = .off

        await store.send(.view(.viewCommand(.toggleShowHiddenFiles)))
        await store.receive {
            guard case let .delegate(.windowManager(action)) = $0 else { return false }
            guard case .window(.toggleShowHiddenFiles) = action else { return false }
            return true
        }
        await store.finish()
    }

    // MARK: - VOY-578-entry_commands

    /// VOY-578-entry_commands: focused window의 entry command capability 투영
    /// focused window 유무와 ordinary Directory/Collection loading 정책이 app menu state에 반영되는지 검증한다.
    /// - 검증 내용: no-focus false, normal Directory true, loading Directory false, loading Collection true
    /// - 사전 조건: 동일한 stale 선택을 가진 FileManager window 상태
    /// - 기대 결과: ordinary Directory loading에서만 capability false
    func testEntryCommandCapabilityReflectsFocusedWindowLoadingPolicy() {
        let focusedID = makeUUID("00000000-0000-0000-0000-000000000057")
        var appState = AppRootState()
        XCTAssertFalse(MenuCommandsState(state: appState).canPerformEntryCommands)

        var focusedWindow = FileManagerFeature.State.makeInitial(path: "/Users/test/Documents")
        focusedWindow.content.entryViewLayout.selectedIds = ["stale-entry"]
        appState.windowManager.windows = [
            WindowSessionState(id: focusedID, window: focusedWindow),
        ]
        appState.windowManager.focusedWindowID = focusedID
        XCTAssertTrue(MenuCommandsState(state: appState).canPerformEntryCommands)

        appState.windowManager.windows[id: focusedID]?.window.content.entryViewLayout.entryOperations.isLoading = true
        let loadingDirectoryMenuState = MenuCommandsState(state: appState)
        XCTAssertFalse(loadingDirectoryMenuState.canPerformEntryCommands)
        XCTAssertFalse(loadingDirectoryMenuState.canOpen)
        XCTAssertFalse(loadingDirectoryMenuState.canQuickLook)
        XCTAssertEqual(loadingDirectoryMenuState.selectedItemCount, 1)

        appState.windowManager.windows[id: focusedID]?.window.content.entryViewLayout.isCollectionMode = true
        XCTAssertTrue(MenuCommandsState(state: appState).canPerformEntryCommands)
    }

    /// VOY-578-entry_commands: text responder 편집 명령 우선권 유지
    /// FileManager entry command가 차단되어도 NSText responder가 처리할 수 있는 편집 명령은 활성화되는지 검증한다.
    /// - 검증 내용: responder 가능/불가능과 entry capability 조합별 활성화 정책
    /// - 사전 조건: ordinary Directory loading capability false를 포함한 순수 정책 입력
    /// - 기대 결과: responder 또는 FileManager fallback 중 하나가 가능하면 활성화
    func testTextResponderEditingRemainsEnabledWhenEntryCommandsAreBlocked() {
        XCTAssertTrue(EditMenuCommands.canPerformTextOrEntryCommand(
            canHandleByTextResponder: true,
            canPerformEntryCommands: false,
        ))
        XCTAssertTrue(EditMenuCommands.canPerformTextOrEntryCommand(
            canHandleByTextResponder: false,
            canPerformEntryCommands: true,
        ))
        XCTAssertFalse(EditMenuCommands.canPerformTextOrEntryCommand(
            canHandleByTextResponder: false,
            canPerformEntryCommands: false,
        ))
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

        var menuState = MenuCommandsState(state: appState)
        XCTAssertTrue(menuState.isContextualAiChatPresented)
        XCTAssertTrue(menuState.isChatHistoryPresented)
        XCTAssertFalse(menuState.isNewChatPresented)
        XCTAssertEqual(menuState.newChatTitle, "New Chat")
        XCTAssertEqual(menuState.chatHistoryTitle, "Hide Chat History")

        appState.windowManager.windows[id: focusedID]?.window.inspector.aiChat.mode = .chat

        menuState = MenuCommandsState(state: appState)
        XCTAssertTrue(menuState.isNewChatPresented)
        XCTAssertFalse(menuState.isChatHistoryPresented)
        XCTAssertEqual(menuState.newChatTitle, "Close Chat")
        XCTAssertEqual(menuState.chatHistoryTitle, "Show Chat History")

        appState.windowManager.windows[id: focusedID]?.window.inspector.inspectorPaneExists = false

        menuState = MenuCommandsState(state: appState)
        XCTAssertFalse(menuState.isContextualAiChatPresented)
        XCTAssertFalse(menuState.isNewChatPresented)
        XCTAssertFalse(menuState.isChatHistoryPresented)

        appState.windowManager.windows[id: focusedID]?.window.inspector.inspectorPaneExists = true
        appState.windowManager.windows[id: focusedID]?.window.inspector.inspectorVisible = false

        menuState = MenuCommandsState(state: appState)
        XCTAssertFalse(menuState.isContextualAiChatPresented)
        XCTAssertFalse(menuState.isNewChatPresented)
        XCTAssertFalse(menuState.isChatHistoryPresented)
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
                 (.file(.restoreLastClosedTab), .file(.restoreLastClosedTab)):
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
        // store.exhaustivity = .off: edit command의 단일 delegate 라우팅만 검증한다.
        store.exhaustivity = .off

        await store.send(.view(.edit(command)))
        await store.receive {
            guard case let .delegate(.windowManager(action)) = $0 else { return false }
            switch (action, expected) {
            case (.edit(.cut), .edit(.cut)),
                 (.edit(.copy), .edit(.copy)),
                 (.edit(.newChat), .edit(.newChat)),
                 (.edit(.showChatHistory), .edit(.showChatHistory)),
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
