import ComposableArchitecture
@testable import Voyager
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
        store.exhaustivity = .off

        await store.send(.view(.app(.checkForUpdates)))
        await store.receive {
            guard case .delegate(.updater(.checkForUpdates)) = $0 else { return false }
            return true
        }
        await store.finish()
    }

    /// FMW-001-request_undo: Edit 메뉴는 native text responder를 Window Entry command보다 우선한다.
    /// - 검증 내용: native action 성공 시 native route, 실패/미지원 시 Window fallback
    /// - 사전 조건: text responder 처리 가능 여부와 deterministic native action 결과
    /// - 기대 결과: native 성공만 Window fallback을 차단하고 미지원 시 native action을 호출하지 않는다.
    func testEditMenuUndoRedoPrioritizesNativeResponderBeforeWindowFallback() {
        let nativeCalls = LockIsolated(0)

        let nativeRoute = EditMenuUndoRedoRouting.resolve(
            canHandleByTextResponder: true,
            sendNativeAction: {
                nativeCalls.withValue { $0 += 1 }
                return true
            },
        )
        let rejectedNativeRoute = EditMenuUndoRedoRouting.resolve(
            canHandleByTextResponder: true,
            sendNativeAction: {
                nativeCalls.withValue { $0 += 1 }
                return false
            },
        )
        let unsupportedRoute = EditMenuUndoRedoRouting.resolve(
            canHandleByTextResponder: false,
            sendNativeAction: {
                nativeCalls.withValue { $0 += 1 }
                return true
            },
        )

        XCTAssertEqual(nativeRoute, .native)
        XCTAssertEqual(rejectedNativeRoute, .window)
        XCTAssertEqual(unsupportedRoute, .window)
        XCTAssertEqual(nativeCalls.value, 2)
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

    /// CTM-001-duplicate_selected_content_tabs: reconciled selected tab이 File 메뉴의 bulk command를 소유한다.
    /// stale selection을 제외한 현재 tab selection만으로 File/Edit Command-D 우선순위를 결정한다.
    /// - 검증 내용: bulk title/enablement와 Entry Duplicate 비활성화
    /// - 사전 조건: focused window에 현재 tab 2개와 stale ID가 함께 선택되고 entry도 선택됨
    /// - 기대 결과: File bulk command만 활성화되고 Edit Entry Duplicate는 비활성화됨
    func testDuplicateSelectedContentTabsProjection_arbitratesFileAndEditCommands() {
        let focusedID = makeUUID("00000000-0000-0000-0000-000000000058")
        var focusedWindow = FileManagerFeature.State.makeInitial(path: "/Users/test/Documents")
        guard let activeTabID = focusedWindow.contentTabs.activeTabID else {
            XCTFail("Expected active content tab")
            return
        }
        let secondTabID = ContentTabID(rawValue: "second-selected-tab")
        focusedWindow.contentTabs.tabs.append(ContentTabItem(
            id: secondTabID,
            page: .home,
            anchor: .homeDefault,
            isPinned: false,
            title: "Second",
            iconName: "house",
        ))
        focusedWindow.contentTabs.selectedTabIDs = [
            activeTabID,
            secondTabID,
            ContentTabID(rawValue: "stale-selected-tab"),
        ]
        focusedWindow.content.entryViewLayout.selectedIds = ["selected-entry"]

        var appState = AppRootState()
        appState.windowManager.windows = [
            WindowSessionState(id: focusedID, window: focusedWindow),
        ]
        appState.windowManager.focusedWindowID = focusedID

        let menuState = MenuCommandsState(state: appState)
        XCTAssertEqual(menuState.selectedContentTabCount, 2)
        XCTAssertTrue(menuState.canDuplicateSelectedContentTabs)
        XCTAssertEqual(menuState.duplicateContentTabTitle, "Duplicate 2 Tabs")
        XCTAssertFalse(menuState.canDuplicateEntries)
    }

    /// CTM-001-duplicate_selected_content_tabs: stale-only selection은 legacy single/Entry fallback을 가로채지 않는다.
    /// canonical tab rows와 reconcile되지 않는 selection은 bulk command presence로 투영하지 않는다.
    /// - 검증 내용: single title/availability와 Entry Duplicate availability
    /// - 사전 조건: stale tab ID만 선택되고 active tab과 selected entry가 존재함
    /// - 기대 결과: File single Shift-Command-D와 Entry Command-D fallback이 유지됨
    func testDuplicateTabProjection_staleOnlySelectionPreservesLegacyFallbacks() {
        let focusedID = makeUUID("00000000-0000-0000-0000-000000000059")
        var focusedWindow = FileManagerFeature.State.makeInitial(path: "/Users/test/Documents")
        guard let activeTabID = focusedWindow.contentTabs.activeTabID else {
            return XCTFail("Expected active content tab")
        }
        focusedWindow.contentTabs.selectedTabIDs = [
            activeTabID,
            ContentTabID(rawValue: "stale-selected-tab"),
        ]
        focusedWindow.content.entryViewLayout.selectedIds = ["selected-entry"]

        var appState = AppRootState()
        appState.windowManager.windows = [
            WindowSessionState(id: focusedID, window: focusedWindow),
        ]
        appState.windowManager.focusedWindowID = focusedID

        let menuState = MenuCommandsState(state: appState)
        XCTAssertEqual(menuState.selectedContentTabCount, 1)
        XCTAssertFalse(menuState.canDuplicateSelectedContentTabs)
        XCTAssertTrue(menuState.canDuplicateActiveContentTab)
        XCTAssertEqual(menuState.duplicateContentTabTitle, "Duplicate Tab")
        XCTAssertTrue(menuState.canDuplicateEntries)
    }

    /// CTM-001-duplicate_selected_content_tabs: pending lifecycle와 zero capacity는 bulk command를 차단한다.
    /// selection presence는 유지하되 실행 availability만 lifecycle/capacity projection으로 비활성화한다.
    /// - 검증 내용: pending close, pending teardown, max tabs, no focus의 disabled matrix
    /// - 사전 조건: reconciled selected tab이 있는 focused window를 각 차단 상태로 변경함
    /// - 기대 결과: 모든 차단 상태에서 bulk command와 Entry Duplicate가 동시에 실행 불가함
    func testDuplicateSelectedContentTabsProjection_disabledForUnavailableContexts() {
        let focusedID = makeUUID("00000000-0000-0000-0000-000000000060")
        var focusedWindow = FileManagerFeature.State.makeInitial(path: "/Users/test/Documents")
        guard let activeTabID = focusedWindow.contentTabs.activeTabID else {
            XCTFail("Expected active content tab")
            return
        }
        let secondTabID = ContentTabID(rawValue: "unavailable-second-selected-tab")
        focusedWindow.contentTabs.tabs.append(ContentTabItem(
            id: secondTabID,
            page: .home,
            anchor: .homeDefault,
            isPinned: false,
            title: "Second",
            iconName: "house",
        ))
        focusedWindow.contentTabs.selectedTabIDs = [activeTabID, secondTabID]

        var appState = AppRootState()
        appState.windowManager.windows = [
            WindowSessionState(id: focusedID, window: focusedWindow),
        ]
        appState.windowManager.focusedWindowID = focusedID

        appState.windowManager.windows[id: focusedID]?.window.pendingContentTabClose = PendingContentTabClose(
            tabID: activeTabID,
        )
        XCTAssertFalse(MenuCommandsState(state: appState).canDuplicateSelectedContentTabs)

        appState.windowManager.windows[id: focusedID]?.window.pendingContentTabClose = nil
        appState.windowManager.windows[id: focusedID]?.window.pendingContentTabTeardown = PendingContentTabTeardown(
            requestID: makeUUID("00000000-0000-0000-0000-000000000061"),
            tabID: activeTabID,
            ownerID: makeUUID("00000000-0000-0000-0000-000000000062"),
        )
        XCTAssertFalse(MenuCommandsState(state: appState).canDuplicateSelectedContentTabs)

        appState.windowManager.windows[id: focusedID]?.window.pendingContentTabTeardown = nil
        while appState.windowManager.windows[id: focusedID]?.window.contentTabs.tabs.count ?? 0
            < ContentTabConstants.maxTabs
        {
            guard let tab = ContentTabState.withHomeTab().tabs.first else { continue }
            appState.windowManager.windows[id: focusedID]?.window.contentTabs.tabs.append(tab)
        }
        let fullMenuState = MenuCommandsState(state: appState)
        XCTAssertEqual(fullMenuState.selectedContentTabCount, 2)
        XCTAssertFalse(fullMenuState.canDuplicateSelectedContentTabs)
        XCTAssertFalse(fullMenuState.canDuplicateEntries)

        appState.windowManager.focusedWindowID = nil
        let noFocusMenuState = MenuCommandsState(state: appState)
        XCTAssertEqual(noFocusMenuState.selectedContentTabCount, 0)
        XCTAssertFalse(noFocusMenuState.canDuplicateSelectedContentTabs)
        XCTAssertFalse(noFocusMenuState.canDuplicateEntries)
    }

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
        var initialState = MenuCommandsFeature.State()
        switch command {
        case .newTab:
            initialState.canOpenNewContentTab = true
        case .togglePinTab:
            initialState.canToggleActiveContentTabPin = true
        case .restoreLastClosedTab:
            initialState.canRestoreLastClosedTab = true
        case .duplicateTab:
            initialState.canDuplicateActiveContentTab = true
        default:
            break
        }
        let store = TestStore(initialState: initialState) {
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
