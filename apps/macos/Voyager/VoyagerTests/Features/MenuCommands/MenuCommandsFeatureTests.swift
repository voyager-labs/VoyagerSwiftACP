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

    /// VOY-165-undo_fallback: 빈 text responder에서도 FileManager Undo capability 유지
    /// responder가 편집 중이지만 자체 history가 없을 때 file operation fallback이 메뉴를 활성화하는지 검증한다.
    /// - 검증 내용: responder capability false와 file operation capability true의 결합
    /// - 사전 조건: text responder 편집 중, responder Undo 불가, FileManager Undo 가능
    /// - 기대 결과: Undo/Redo command capability 활성화
    func testUndoCapabilityIncludesFileFallbackWhenTextResponderHistoryIsEmpty() {
        XCTAssertTrue(EditMenuCommands.canPerformUndoRedoCommand(
            textResponderIsEditing: true,
            canHandleByTextResponder: false,
            canPerformFileOperation: true,
        ))
        XCTAssertTrue(EditMenuCommands.canPerformUndoRedoCommand(
            textResponderIsEditing: true,
            canHandleByTextResponder: true,
            canPerformFileOperation: false,
        ))
        XCTAssertFalse(EditMenuCommands.canPerformUndoRedoCommand(
            textResponderIsEditing: true,
            canHandleByTextResponder: false,
            canPerformFileOperation: false,
        ))
    }

    /// VOY-165-undo_fallback: history 없는 responder는 AppKit dispatch 전에 FileManager fallback
    /// selector 수신 가능 여부와 실제 Undo capability를 구분해 no-op responder가 fallback을 가로채지 않는지 검증한다.
    /// - 검증 내용: responder capability false일 때 dispatch 생략과 fallback 호출 횟수
    /// - 사전 조건: text responder 편집 중, responder Undo 불가, FileManager Undo 가능, selector dispatch 가능
    /// - 기대 결과: responder dispatch 0회와 FileManager fallback 1회
    func testUndoRedoSkipsDispatchForResponderWithoutHistory() {
        var responderAttemptCount = 0
        var fallbackCount = 0

        EditMenuCommands.performUndoRedoAction(
            textResponderIsEditing: true,
            canHandleByTextResponder: false,
            isComposerPresented: false,
            sendResponderAction: {
                responderAttemptCount += 1
                return true
            },
            sendFallback: {
                fallbackCount += 1
            },
        )

        XCTAssertEqual(responderAttemptCount, 0)
        XCTAssertEqual(fallbackCount, 1)
    }

    /// VOY-165-undo_fallback: text responder가 Undo를 처리하지 못하면 FileManager fallback 실행
    /// responder 후보 존재와 실제 AppKit dispatch 성공을 구분하는지 검증한다.
    /// - 검증 내용: responder dispatch 실패 후 fallback 호출 횟수
    /// - 사전 조건: text responder 편집 중, Composer 닫힘, AppKit dispatch false
    /// - 기대 결과: responder 시도 1회와 FileManager fallback 1회
    func testUndoRedoFallsBackWhenTextResponderDoesNotHandleAction() {
        var responderAttemptCount = 0
        var fallbackCount = 0

        EditMenuCommands.performUndoRedoAction(
            textResponderIsEditing: true,
            canHandleByTextResponder: true,
            isComposerPresented: false,
            sendResponderAction: {
                responderAttemptCount += 1
                return false
            },
            sendFallback: {
                fallbackCount += 1
            },
        )

        XCTAssertEqual(responderAttemptCount, 1)
        XCTAssertEqual(fallbackCount, 1)
    }

    /// VOY-165-undo_fallback: Composer 표시 중 FileManager fallback 차단
    /// responder dispatch 실패 후에도 Composer가 file operation Undo를 차단하는지 검증한다.
    /// - 검증 내용: responder dispatch 시도와 fallback 미호출
    /// - 사전 조건: text responder 편집 중, Composer 열림, AppKit dispatch false
    /// - 기대 결과: responder 시도 1회와 FileManager fallback 0회
    func testUndoRedoDoesNotFallBackWhileComposerIsPresented() {
        var responderAttemptCount = 0
        var fallbackCount = 0

        EditMenuCommands.performUndoRedoAction(
            textResponderIsEditing: true,
            canHandleByTextResponder: true,
            isComposerPresented: true,
            sendResponderAction: {
                responderAttemptCount += 1
                return false
            },
            sendFallback: {
                fallbackCount += 1
            },
        )

        XCTAssertEqual(responderAttemptCount, 1)
        XCTAssertEqual(fallbackCount, 0)
    }

    func testMenuCommandStateReflectsFocusedWindowAiChatAvailabilityAndTitles() {
        let focusedID = makeUUID("00000000-0000-0000-0000-000000000041")
        let unfocusedID = makeUUID("00000000-0000-0000-0000-000000000042")

        var focusedWindow = FileManagerFeature.State.makeInitial(path: "/Users/test/Documents")
        guard let activeTabID = focusedWindow.contentTabs.activeTabID else {
            XCTFail("Expected focused window to have an active tab")
            return
        }
        focusedWindow.inspector.inspectorVisible = true
        focusedWindow.inspector.inspectorPaneExists = true
        focusedWindow.inspector.activeMode = .chat
        focusedWindow.inspector.aiChat.mode = .sessions

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
        XCTAssertFalse(menuState.isNewChatPresented)
        XCTAssertTrue(menuState.isChatHistoryPresented)
        XCTAssertTrue(menuState.canUseAiChatInspector)
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
        XCTAssertEqual(menuState.newChatTitle, "New Chat")
        XCTAssertEqual(menuState.chatHistoryTitle, "Show Chat History")

        appState.windowManager.windows[id: focusedID]?.window.contentTabs.tabs[id: activeTabID]?.anchor = .homeDefault
        XCTAssertFalse(MenuCommandsState(state: appState).canUseAiChatInspector)

        appState.windowManager.windows[id: focusedID]?.window.contentTabs.tabs[id: activeTabID]?.anchor = .aiChat(
            sessionID: "menu-test",
        )
        XCTAssertFalse(MenuCommandsState(state: appState).canUseAiChatInspector)

        appState.windowManager.windows[id: focusedID]?.window.contentTabs.tabs[id: activeTabID]?.anchor = .directory(
            path: "/Users/test/Documents",
        )
        XCTAssertTrue(MenuCommandsState(state: appState).canUseAiChatInspector)

        appState.windowManager.focusedWindowID = nil
        menuState = MenuCommandsState(state: appState)
        XCTAssertFalse(menuState.canUseAiChatInspector)
        XCTAssertEqual(menuState.newChatTitle, "New Chat")
        XCTAssertEqual(menuState.chatHistoryTitle, "Show Chat History")
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
