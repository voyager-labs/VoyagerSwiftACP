import AppKit
import ComposableArchitecture
import Foundation
import VoyagerEntitiesAppPreferences
import VoyagerFeaturesEntryOperations
@testable import VoyagerPagesFileManager
import VoyagerShared
import XCTest

@MainActor
final class FMW001FileManagerWindowTests: XCTestCase {
    private func makeStore(
        initialState: FileManagerWindowState = FileManagerWindowState(),
    ) -> TestStore<FileManagerWindowState, FileManagerWindowAction> {
        TestStore(
            initialState: initialState,
        ) {
            FileManagerWindowCommandRoutingReducer()
        }
    }

    private func makeSelectedState(
        isLoading: Bool,
        isCollectionMode: Bool,
    ) -> FileManagerWindowState {
        var state = FileManagerWindowState()
        state.content.entryViewLayout.selectedIds = ["selected-entry"]
        state.content.entryOperations.isLoading = isLoading
        state.content.entryViewLayout.isCollectionMode = isCollectionMode
        state.content.navigation.navigationState = .folder("/tmp")
        return state
    }

    private var entryCommands: [FileManagerWindowAction.WindowCommand] {
        [
            .newFolder,
            .openSelectedItem,
            .quickLookSelectedItem,
            .cut,
            .copy,
            .paste,
            .duplicate,
            .makeAlias,
            .selectAll,
            .copyAbsolutePaths,
            .copyURLs,
        ]
    }

    // MARK: - VOY-578-entry_commands

    // MARK: - VOY-150-context_menu_loading_capability

    /// VOY-150-context_menu_loading_capability: AppKit 빈 영역 메뉴는 loading capability를 New Folder와 Empty Trash에 적용한다.
    /// 일반 Directory loading 중 stale 메뉴 command가 실행되지 않도록 두 항목의 실제 AppKit enablement가 projection과 일치해야 한다.
    /// - 검증 내용: normal/loading 및 Trash/non-Trash configuration에서 메뉴 항목의 isEnabled 상태.
    /// - 사전 조건: ContentPaneContextMenuBuilder에 ordinary Directory와 Trash의 loading capability configuration을 각각 전달한다.
    /// - 기대 결과: ordinary Directory loading만 New Folder와 Empty Trash가 비활성화되고, normal 상태는 활성 상태를 유지한다.
    func testAppKitBlankAreaMenuAppliesLoadingCapabilityToNewFolderAndEmptyTrash() {
        assertPrimaryMenuItem(title: "New Folder", isTrashFolder: false, canPerformEntryCommands: true, isEnabled: true)
        assertPrimaryMenuItem(title: "Empty Trash", isTrashFolder: true, canPerformEntryCommands: true, isEnabled: true)
        assertPrimaryMenuItem(
            title: "New Folder",
            isTrashFolder: false,
            canPerformEntryCommands: false,
            isEnabled: false,
        )
        assertPrimaryMenuItem(
            title: "Empty Trash",
            isTrashFolder: true,
            canPerformEntryCommands: false,
            isEnabled: false,
        )
    }

    /// FMW-001-entry_commands: 빈 영역 메뉴는 loading 중 Paste와 Select All을 비활성화한다.
    /// 빈 영역 메뉴도 app menu 및 키 입력과 같은 capability projection을 사용해 stale clipboard나 selection 동작을 노출하지 않아야 한다.
    /// - 검증 내용: context menu configuration의 capability와 item count가 Paste, Select All, Sort, Group 활성 정책에 반영된다.
    /// - 사전 조건: 일반 Directory loading 중이고 clipboard에는 항목이 있으나 표시 항목은 없다.
    /// - 기대 결과: Paste, Select All, Sort, Group mutation은 모두 비활성화된다.
    func testEmptyAreaMenuUsesLoadingCapabilityForPasteAndSelectAll() {
        let configuration = ContentPaneContextMenuBuilder.Configuration(
            isTrashFolder: false,
            viewLayout: .list,
            sortKey: .name,
            sortOrder: .ascending,
            groupKey: .none,
            canPaste: true,
            itemCount: 0,
            canPerformEntryCommands: false,
        )

        XCTAssertFalse(configuration.canPasteItems)
        XCTAssertFalse(configuration.canSelectAll)
        XCTAssertFalse(configuration.canChangeSort)
        XCTAssertFalse(configuration.canChangeGroup)
    }

    /// VOY-578-entry_commands: 일반 Directory loading 중 모든 전역 entry 명령 차단
    /// stale 선택이 유지되어도 menu capability와 최종 routing이 함께 명령 실행을 막는지 검증한다.
    /// - 검증 내용: capability false 및 11개 entry command의 하위 action 미방출
    /// - 사전 조건: 일반 Directory mode, entry loading 중, stale 선택 ID 유지
    /// - 기대 결과: 모든 entry command가 no-op으로 종료
    func testOrdinaryDirectoryLoadingDisablesAndBlocksAllEntryCommands() async {
        let state = makeSelectedState(isLoading: true, isCollectionMode: false)
        XCTAssertFalse(state.menuCommandProjection.canPerformEntryCommands)
        let store = makeStore(initialState: state)

        for command in entryCommands {
            await store.send(.request(command))
        }
        await store.finish()
    }

    /// VOY-578-entry_commands: 일반 Directory 정상 상태의 전역 entry 명령 유지
    /// loading이 아닐 때 기존 entry 명령 routing이 모두 보존되는지 검증한다.
    /// - 검증 내용: capability true 및 11개 entry command의 기존 하위 action 전달
    /// - 사전 조건: 일반 Directory mode, entry loading 아님, 선택 ID 존재
    /// - 기대 결과: 모든 entry command가 대응하는 하위 reducer로 전달
    func testNormalDirectoryAllowsAllEntryCommands() async {
        let state = makeSelectedState(isLoading: false, isCollectionMode: false)
        XCTAssertTrue(state.menuCommandProjection.canPerformEntryCommands)

        for command in entryCommands {
            await assertEntryCommand(command, routesFrom: state)
        }
    }

    /// VOY-578-entry_commands: Collection loading의 전역 entry 명령 정책 유지
    /// Collection loading은 ordinary Directory loading guard에 포함되지 않는지 검증한다.
    /// - 검증 내용: capability true 및 11개 entry command의 기존 하위 action 전달
    /// - 사전 조건: Collection mode, entry loading 중, 선택 ID 존재
    /// - 기대 결과: 모든 entry command가 대응하는 하위 reducer로 전달
    func testCollectionLoadingAllowsAllEntryCommands() async {
        let state = makeSelectedState(isLoading: true, isCollectionMode: true)
        XCTAssertTrue(state.menuCommandProjection.canPerformEntryCommands)

        for command in entryCommands {
            await assertEntryCommand(command, routesFrom: state)
        }
    }

    /// VOY-578-entry_commands: 일반 Directory loading 중 비-entry 명령 보존
    /// entry command guard가 hidden files, undo/redo, navigation, layout, tab, composer 명령까지 막지 않는지 검증한다.
    /// - 검증 내용: 각 비-entry command가 기존 하위 reducer action을 방출
    /// - 사전 조건: 일반 Directory mode, entry loading 중
    /// - 기대 결과: 명령 범주별 기존 routing 유지
    func testOrdinaryDirectoryLoadingPreservesNonEntryCommands() async throws {
        var state = makeSelectedState(isLoading: true, isCollectionMode: false)
        state.content.entryOperations.undoRecords = [makeUndoRedoRecord("loading-undo")]
        state.content.entryOperations.redoRecords = [makeUndoRedoRecord("loading-redo")]
        let activeTabID = try XCTUnwrap(state.contentTabs.activeTabID)
        let store = makeStore(initialState: state)

        await store.send(.request(.toggleShowHiddenFiles))
        await store.receive(\.content.view.toggleShowHiddenFilesAndReload)
        await store.send(.request(.requestUndo))
        await store.receive {
            matchesTargetedUndoRedoRequest($0, tabID: activeTabID, request: .undo)
        }
        await store.send(.request(.requestRedo))
        await store.receive {
            matchesTargetedUndoRedoRequest($0, tabID: activeTabID, request: .redo)
        }
        await store.send(.request(.goBack))
        await store.receive(\.navigation.view.goBack)
        await store.send(.request(.setViewLayout(.grid)))
        await store.receive(\.content.view.changeLayout)
        await store.send(.request(.openNewContentTab))
        await store.receive(\.contentTabs.open)
        await store.send(.request(.toggleComposer))
        await store.receive(\.content.composer.view.setPresented)
        await store.finish()
    }

    // MARK: - FMW-001-toggle_sidebar

    /// FMW-001-toggle_sidebar: 사이드바 토글 명령 라우팅
    /// toggleSidebar 요청이 sidebar 리듀서로 전달되는지 검증.
    /// - 검증 내용: request(.toggleSidebar) 전송 시 sidebar.view.setSidebarVisible 수신
    /// - 사전 조건: 기본 상태의 FileManagerWindow
    /// - 기대 결과: sidebar.view.setSidebarVisible 액션 수신
    func test_sidebarToggleRequest_forwardsToSidebarReducer() async {
        let store = makeStore()

        await store.send(.request(.toggleSidebar))
        await store.receive(\.sidebar.view.setSidebarVisible)
        await store.finish()
    }

    /// FMW-001-toggle_sidebar: 반복 토글 멱등성
    /// 연속 toggleSidebar 요청이 매번 올바르게 sidebar 리듀서로 전달되는지 검증.
    /// - 검증 내용: 두 번 연속 toggleSidebar 전송 시 각각 setSidebarVisible 수신
    /// - 사전 조건: sidebarVisible == true 상태
    /// - 기대 결과: 두 번 모두 sidebar.view.setSidebarVisible 수신
    func test_sidebarToggleRequest_repeatedToggle_isIdempotent() async {
        var initialState = FileManagerWindowState()
        initialState.sidebar.sidebarVisible = true

        let store = makeStore(initialState: initialState)

        await store.send(.request(.toggleSidebar))
        await store.receive(\.sidebar.view.setSidebarVisible)

        await store.send(.request(.toggleSidebar))
        await store.receive(\.sidebar.view.setSidebarVisible)
        await store.finish()
    }

    /// FMW-001-toggle_sidebar: 명령 라우팅 시 관련 없는 윈도우 상태 불변
    /// toggleSidebar 라우팅이 inspector 등 관련 없는 상태를 변경하지 않고 불변을 유지하는지 검증.
    /// - 검증 내용: toggleSidebar 전송 후 inspectorVisible 상태 보존
    /// - 사전 조건: inspectorVisible == true
    /// - 기대 결과: inspector 상태 변화 없이 setSidebarVisible만 수신
    func test_commandRouting_doesNotMutateUnrelatedWindowState_sidebarToggle() async {
        var initialState = FileManagerWindowState()
        initialState.inspector.inspectorVisible = true

        let store = makeStore(initialState: initialState)

        await store.send(.request(.toggleSidebar))
        await store.receive(\.sidebar.view.setSidebarVisible)
        await store.finish()
    }

    // MARK: - FMW-001-go_back

    /// FMW-001-go_back: 뒤로 가기 명령 라우팅
    /// goBack 요청이 navigation 리듀서로 전달되는지 검증.
    /// - 검증 내용: request(.goBack) 전송 시 navigation.view.goBack 수신
    /// - 사전 조건: 기본 상태의 FileManagerWindow
    /// - 기대 결과: navigation.view.goBack 액션 수신
    func test_navigationRequest_goBack_forwardsToNavigationReducer() async {
        let store = makeStore()

        await store.send(.request(.goBack))
        await store.receive(\.navigation.view.goBack)
        await store.finish()
    }

    /// FMW-001-go_back: 명령 라우팅 시 관련 없는 윈도우 상태 불변
    /// goBack 라우팅이 sidebar, inspector 등 관련 없는 상태를 변경하지 않고 불변을 유지하는지 검증.
    /// - 검증 내용: goBack 전송 후 sidebarVisible, sidebarWidth 상태 보존
    /// - 사전 조건: sidebarVisible=true, sidebarWidth=250=true
    /// - 기대 결과: 관련 없는 상태 필드 변화 없이 goBack만 수신
    func test_commandRouting_doesNotMutateUnrelatedWindowState_navigation() async {
        var initialState = FileManagerWindowState()
        initialState.sidebar.sidebarVisible = true
        initialState.sidebar.sidebarWidth = 250

        let store = makeStore(initialState: initialState)

        await store.send(.request(.goBack))
        await store.receive(\.navigation.view.goBack)
        await store.finish()
    }

    // MARK: - FMW-001-go_forward

    /// FMW-001-go_forward: 앞으로 가기 명령 라우팅
    /// goForward 요청이 navigation 리듀서로 전달되는지 검증.
    /// - 검증 내용: request(.goForward) 전송 시 navigation.view.goForward 수신
    /// - 사전 조건: 기본 상태의 FileManagerWindow
    /// - 기대 결과: navigation.view.goForward 액션 수신
    func test_navigationRequest_goForward_forwardsToNavigationReducer() async {
        let store = makeStore()

        await store.send(.request(.goForward))
        await store.receive(\.navigation.view.goForward)
        await store.finish()
    }

    // MARK: - FMW-001-go_to_enclosing_directory

    /// FMW-001-go_to_enclosing_directory: 상위 디렉토리 이동 명령 라우팅
    /// goToEnclosingDirectory 요청이 navigation 리듀서로 전달되는지 검증.
    /// - 검증 내용: request(.goToEnclosingDirectory) 전송 시 navigation.view.goToEnclosingDirectory 수신
    /// - 사전 조건: 기본 상태의 FileManagerWindow
    /// - 기대 결과: navigation.view.goToEnclosingDirectory 액션 수신
    func test_navigationRequest_goToEnclosingDirectory_forwardsToNavigationReducer() async {
        let store = makeStore()

        await store.send(.request(.goToEnclosingDirectory))
        await store.receive(\.navigation.view.goToEnclosingDirectory)
        await store.finish()
    }

    // MARK: - FMW-001-open_selected_item

    /// FMW-001-open_selected_item: 선택 항목 없을 때 openSelectedItem no-op
    /// 선택 항목이 없을 때 openSelectedItem 요청이 하위 리듀서로 전달되지 않고 no-op인지 검증.
    /// - 검증 내용: request(.openSelectedItem) 전송 후 하위 리듀서 수신 없음
    /// - 사전 조건: 기본 상태, 선택 항목 없음
    /// - 기대 결과: 하위 리듀서로의 라우팅 없이 finish
    func test_commandWithNoSelection_openSelectedItem_isNoOp() async {
        let store = makeStore()

        await store.send(.request(.openSelectedItem))
        await store.finish()
    }

    /// FMW-001-open_selected_item: 일반 Directory loading 중 Open 비활성 및 no-op
    /// 이전 Directory 선택이 남아 있어도 새 Directory 로딩 중에는 전역 Open이 실행되지 않는지 검증한다.
    /// - 검증 내용: menu projection 비활성 및 request(.openSelectedItem) 최종 routing 차단
    /// - 사전 조건: 일반 Directory mode, entry loading 중, stale 선택 ID 유지
    /// - 기대 결과: canOpen false이고 하위 reducer action 없이 종료
    func testOrdinaryDirectoryLoadingDisablesAndBlocksOpenSelectedItem() async {
        let state = makeSelectedState(isLoading: true, isCollectionMode: false)
        XCTAssertFalse(state.menuCommandProjection.canOpen)
        let store = makeStore(initialState: state)

        await store.send(.request(.openSelectedItem))
        await store.finish()
    }

    /// FMW-001-open_selected_item: 일반 상태에서 Open 허용 및 routing
    /// 로딩 중이 아닌 기존 선택 항목의 전역 Open 동작이 유지되는지 검증한다.
    /// - 검증 내용: menu projection 활성 및 request(.openSelectedItem) 하위 routing
    /// - 사전 조건: 일반 Directory mode, entry loading 아님, 선택 ID 존재
    /// - 기대 결과: canOpen true이고 openSelectedItem command가 entry view layout으로 전달됨
    func testNormalDirectoryAllowsOpenSelectedItem() async {
        let state = makeSelectedState(isLoading: false, isCollectionMode: false)
        XCTAssertTrue(state.menuCommandProjection.canOpen)
        let store = makeStore(initialState: state)

        await store.send(.request(.openSelectedItem))
        await store.receive {
            guard case .content(.entryViewLayout(.delegate(.executeCommand("navigation.openSelectedItem")))) = $0
            else { return false }
            return true
        }
        await store.finish()
    }

    /// FMW-001-open_selected_item: Collection loading 중 Open 정책 유지
    /// Collection loading은 ordinary Directory loading 차단 정책에 포함되지 않는지 검증한다.
    /// - 검증 내용: menu projection 활성 및 request(.openSelectedItem) 하위 routing
    /// - 사전 조건: Collection mode, entry loading 중, 선택 ID 존재
    /// - 기대 결과: canOpen true이고 openSelectedItem command가 entry view layout으로 전달됨
    func testCollectionLoadingAllowsOpenSelectedItem() async {
        let state = makeSelectedState(isLoading: true, isCollectionMode: true)
        XCTAssertTrue(state.menuCommandProjection.canOpen)
        let store = makeStore(initialState: state)

        await store.send(.request(.openSelectedItem))
        await store.receive {
            guard case .content(.entryViewLayout(.delegate(.executeCommand("navigation.openSelectedItem")))) = $0
            else { return false }
            return true
        }
        await store.finish()
    }

    // MARK: - FMW-001-quick_look_selected_item

    /// FMW-001-quick_look_selected_item: 선택 항목 없을 때 quickLookSelectedItem no-op
    /// 선택 항목이 없을 때 quickLookSelectedItem 요청이 하위 리듀서로 전달되지 않고 no-op인지 검증.
    /// - 검증 내용: request(.quickLookSelectedItem) 전송 후 하위 리듀서 수신 없음
    /// - 사전 조건: 기본 상태, 선택 항목 없음
    /// - 기대 결과: 하위 리듀서로의 라우팅 없이 finish
    func test_commandWithNoSelection_quickLookSelectedItem_isNoOp() async {
        let store = makeStore()

        await store.send(.request(.quickLookSelectedItem))
        await store.finish()
    }

    /// FMW-001-quick_look_selected_item: 일반 Directory loading 중 Quick Look 비활성 및 no-op
    /// 이전 Directory 선택이 남아 있어도 새 Directory 로딩 중에는 전역 Quick Look이 실행되지 않는지 검증한다.
    /// - 검증 내용: menu projection 비활성 및 request(.quickLookSelectedItem) 최종 routing 차단
    /// - 사전 조건: 일반 Directory mode, entry loading 중, stale 선택 ID 유지
    /// - 기대 결과: canQuickLook false이고 하위 reducer action 없이 종료
    func testOrdinaryDirectoryLoadingDisablesAndBlocksQuickLookSelectedItem() async {
        let state = makeSelectedState(isLoading: true, isCollectionMode: false)
        XCTAssertFalse(state.menuCommandProjection.canQuickLook)
        let store = makeStore(initialState: state)

        await store.send(.request(.quickLookSelectedItem))
        await store.finish()
    }

    /// FMW-001-quick_look_selected_item: 일반 상태에서 Quick Look 허용 및 routing
    /// 로딩 중이 아닌 기존 선택 항목의 전역 Quick Look 동작이 유지되는지 검증한다.
    /// - 검증 내용: menu projection 활성 및 request(.quickLookSelectedItem) 하위 routing
    /// - 사전 조건: 일반 Directory mode, entry loading 아님, 선택 ID 존재
    /// - 기대 결과: canQuickLook true이고 quickLookSelectedItem command가 entry view layout으로 전달됨
    func testNormalDirectoryAllowsQuickLookSelectedItem() async {
        let state = makeSelectedState(isLoading: false, isCollectionMode: false)
        XCTAssertTrue(state.menuCommandProjection.canQuickLook)
        let store = makeStore(initialState: state)

        await store.send(.request(.quickLookSelectedItem))
        await store.receive {
            guard case .content(.entryViewLayout(.delegate(.executeCommand("navigation.quickLookSelectedItem")))) = $0
            else { return false }
            return true
        }
        await store.finish()
    }

    /// FMW-001-quick_look_selected_item: Collection loading 중 Quick Look 정책 유지
    /// Collection loading은 ordinary Directory loading 차단 정책에 포함되지 않는지 검증한다.
    /// - 검증 내용: menu projection 활성 및 request(.quickLookSelectedItem) 하위 routing
    /// - 사전 조건: Collection mode, entry loading 중, 선택 ID 존재
    /// - 기대 결과: canQuickLook true이고 quickLookSelectedItem command가 entry view layout으로 전달됨
    func testCollectionLoadingAllowsQuickLookSelectedItem() async {
        let state = makeSelectedState(isLoading: true, isCollectionMode: true)
        XCTAssertTrue(state.menuCommandProjection.canQuickLook)
        let store = makeStore(initialState: state)

        await store.send(.request(.quickLookSelectedItem))
        await store.receive {
            guard case .content(.entryViewLayout(.delegate(.executeCommand("navigation.quickLookSelectedItem")))) = $0
            else { return false }
            return true
        }
        await store.finish()
    }

    // MARK: - FMW-001-request_undo

    /// FMW-001-request_undo: undo 명령 라우팅
    /// requestUndo 요청이 entryOperations undoRedo 리듀서로 전달되는지 검증.
    /// - 검증 내용: request(.requestUndo) 전송 시 content.entryOperations.undoRedo.requestUndo 수신
    /// - 사전 조건: 기본 상태의 FileManagerWindow
    /// - 기대 결과: undoRedo.requestUndo 액션 수신
    func test_undoRedoRequest_undo_forwardsToEntryOperations() async throws {
        let (store, activeTabID) = try makeWindowCommandStore(request: .undo)

        await store.send(.request(.requestUndo))
        await store.receive {
            matchesTargetedUndoRedoRequest($0, tabID: activeTabID, request: .undo)
        }
        await store.finish()
    }

    /// FMW-001-request_undo: 표시 중인 Composer는 file Undo/Redo menu capability를 숨긴다.
    /// Text responder가 없는 상태에서도 Composer가 file-operation history보다 우선하는 menu projection을 검증한다.
    /// - 검증 내용: file undo/redo record가 각각 있어도 Composer 표시 중 projection의 canUndo/canRedo가 false인지 확인한다.
    /// - 사전 조건: active Content tab에 undo/redo history가 있고 Collection Filter Composer가 표시 중이다.
    /// - 기대 결과: isComposerPresented는 true이며 file Undo와 Redo menu capability는 모두 false다.
    func testComposerPresentedSuppressesFileUndoRedoMenuProjection() {
        var state = FileManagerWindowState()
        state.content.entryOperations.undoRecords = [makeUndoRedoRecord("composer-undo")]
        state.content.entryOperations.redoRecords = [makeUndoRedoRecord("composer-redo")]
        state.content.composer.isPresented = true

        let projection = state.menuCommandProjection

        XCTAssertTrue(projection.isComposerPresented)
        XCTAssertFalse(projection.canUndo)
        XCTAssertFalse(projection.canRedo)
    }

    /// FMW-001-request_undo: 표시 중인 Collection Filter Composer가 Cmd-Z 파일 작업 fallback을 차단
    /// Composer가 로컬 undo/redo 이력을 소유할 때 FileManager key-command 경계가 이를 침범하지 않는지 검증한다.
    /// - 검증 내용: handleKeyCommand(Cmd-Z)의 EntryOperations requestUndo 미방출과 Composer 이력 불변
    /// - 사전 조건: Composer가 표시 중이고 history와 redoHistory가 각각 1건 존재
    /// - 기대 결과: 하위 file-operation action 없이 기존 history와 redoHistory가 그대로 유지됨
    func testUndoKeyCommandWhenComposerPresentedBlocksEntryOperationsAndPreservesHistory() async {
        var state = FileManagerContentState()
        withDependencies {
            $0.entryLoadingClient = .testValue
            $0.searchClient = .testValue
            $0.registryClient = .testValue
        } operation: {
            _ = FileManagerContentFeature().reduce(
                into: &state,
                action: .composer(.addScope(path: "/VoyagerFixtures/Documents")),
            )
            _ = FileManagerContentFeature().reduce(
                into: &state,
                action: .composer(.addScope(path: "/VoyagerFixtures/Notes")),
            )
            _ = FileManagerContentFeature().reduce(into: &state, action: .composer(.undo))
        }
        state.composer.isPresented = true
        let history = state.composer.history
        let redoHistory = state.composer.redoHistory
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(redoHistory.count, 1)

        let store = TestStore(initialState: state) {
            FileManagerContentFeature()
        }
        let command = makeUndoKeyCommand()

        await store.send(.view(.handleKeyCommand(command)))

        XCTAssertEqual(store.state.composer.history, history)
        XCTAssertEqual(store.state.composer.redoHistory, redoHistory)
        await store.finish()
    }

    /// FMW-001-request_undo: text first-responder의 local history가 비어도 file Undo로 fallback하지 않는다.
    /// 사용자가 빈 편집 이력을 가진 text field에서 Cmd-Z를 눌러도 현재 탭의 file-operation history를 소비하지 않는지 검증한다.
    /// - 검증 내용: text responder가 존재하는 동안 `handleKeyCommand(Cmd-Z)`가 EntryOperations requestUndo를 방출하지 않는다.
    /// - 사전 조건: key window의 first responder가 undo 가능한 action이 없는 NSTextView이고 Composer는 표시되지 않는다.
    /// - 기대 결과: 하위 file-operation action 없이 text responder precedence가 유지된다.
    func testUndoKeyCommandWithEmptyTextResponderHistoryDoesNotFallbackToEntryOperations() async {
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 240, height: 80))
        textView.undoManager?.removeAllActions()
        XCTAssertFalse(textView.undoManager?.canUndo ?? false)

        let command = makeUndoKeyCommand()
        let store = TestStore(initialState: FileManagerContentState()) {
            Reduce<FileManagerContentState, FileManagerContentAction> { state, action in
                guard case let .view(.handleKeyCommand(command)) = action else { return .none }
                return FileManagerContentKeyCommandHandler.effect(
                    for: command,
                    state: state,
                    textResponderIsEditing: true,
                )
            }
        }

        await store.send(.view(.handleKeyCommand(command)))
        await store.finish()
    }

    // MARK: - FMW-001-request_redo

    /// FMW-001-request_redo: redo 명령 라우팅
    /// requestRedo 요청이 entryOperations undoRedo 리듀서로 전달되는지 검증.
    /// - 검증 내용: request(.requestRedo) 전송 시 content.entryOperations.undoRedo.requestRedo 수신
    /// - 사전 조건: 기본 상태의 FileManagerWindow
    /// - 기대 결과: undoRedo.requestRedo 액션 수신
    func test_undoRedoRequest_redo_forwardsToEntryOperations() async throws {
        let (store, activeTabID) = try makeWindowCommandStore(request: .redo)

        await store.send(.request(.requestRedo))
        await store.receive {
            matchesTargetedUndoRedoRequest($0, tabID: activeTabID, request: .redo)
        }
        await store.finish()
    }

    // MARK: - FMW-001-toggle_composer

    /// FMW-001-toggle_composer: 컴포저 토글 명령 라우팅
    /// toggleComposer 요청이 content.composer 리듀서로 전달되는지 검증.
    /// - 검증 내용: request(.toggleComposer) 전송 시 content.composer.view.setPresented 수신
    /// - 사전 조건: 기본 상태의 FileManagerWindow
    /// - 기대 결과: content.composer.view.setPresented 액션 수신
    func test_composerRequest_toggleComposer_forwardsToContentComposer() async {
        let store = makeStore()

        await store.send(.request(.toggleComposer))
        await store.receive(\.content.composer.view.setPresented)
        await store.finish()
    }

    // MARK: - FMW-001-open_new_file_manager_window

    /// FMW-001-open_new_file_manager_window: makeInitial 기본 상태의 windowID 없음
    /// FileManager window 초기 상태와 entry operation state 격리 계약을 검증.
    /// - 검증 내용: FileManagerWindowState.makeInitial이 entry operation windowID를 비운 상태로 시작하는지 검증
    /// - 사전 조건: FileManagerWindowState 기본 생성 또는 makeInitial 사용
    /// - 기대 결과: entry operation windowID와 collection mode 상태가 명확한 기본값 유지
    func testMakeInitialCreatesStateWithoutWindowID() {
        let state = FileManagerWindowState.makeInitial(path: nil)

        XCTAssertNil(state.content.entryOperations.windowID)
    }

    /// FMW-001-open_new_file_manager_window: makeInitial path seed와 entry operation state 분리
    /// FileManager window 초기 상태와 entry operation state 격리 계약을 검증.
    /// - 검증 내용: 초기 path seed가 entry operation windowID를 오염시키지 않는지 검증
    /// - 사전 조건: FileManagerWindowState 기본 생성 또는 makeInitial 사용
    /// - 기대 결과: entry operation windowID와 collection mode 상태가 명확한 기본값 유지
    func testMakeInitialSeedsPathThroughNavigationState() {
        let path = "/Users/test/Documents"
        let state = FileManagerWindowState.makeInitial(path: path)

        XCTAssertNil(state.content.entryOperations.windowID)
    }

    /// FMW-001-open_new_file_manager_window: FileManagerWindowState 기본 collection mode 비활성
    /// FileManager window 초기 상태와 entry operation state 격리 계약을 검증.
    /// - 검증 내용: 기본 window state가 collection mode와 entry operation windowID를 갖지 않는지 검증
    /// - 사전 조건: FileManagerWindowState 기본 생성 또는 makeInitial 사용
    /// - 기대 결과: entry operation windowID와 collection mode 상태가 명확한 기본값 유지
    func testWindowDefaultStateHasNoCollectionMode() {
        let state = FileManagerWindowState()

        XCTAssertFalse(state.content.entryViewLayout.isCollectionMode)
        XCTAssertNil(state.content.entryOperations.windowID)
    }

    /// FMW-001-open_new_file_manager_window: entry operations reset 시 windowID 제거
    /// FileManager window 초기 상태와 entry operation state 격리 계약을 검증.
    /// - 검증 내용: content entryOperations state reset이 windowID를 제거하는지 검증
    /// - 사전 조건: FileManagerWindowState 기본 생성 또는 makeInitial 사용
    /// - 기대 결과: entry operation windowID와 collection mode 상태가 명확한 기본값 유지
    func testContentEntryOperationsResetClearsWindowID() {
        let windowID = UUID()
        var state = FileManagerWindowState.makeInitial(path: nil)
        state.content.entryOperations.windowID = windowID
        XCTAssertEqual(state.content.entryOperations.windowID, windowID)

        state.content.entryOperations = EntryOperationsState()
        XCTAssertNil(state.content.entryOperations.windowID)

        state.content.entryOperations.windowID = windowID
        XCTAssertEqual(state.content.entryOperations.windowID, windowID)
    }

    /// FMW-001-open_new_file_manager_window: FileManager feature 기본 navigation slice 구성
    /// FileManagerFeature.State가 별도 path seed 없이도 기본 탐색 경로와 sidebar 표시 상태를 갖는지 검증한다.
    /// - 검증 내용: content navigation 기본 경로와 sidebar visibility 확인
    /// - 사전 조건: fresh FileManagerFeature.State 생성
    /// - 기대 결과: currentPath는 Home 기본 경로이고 sidebar는 표시 상태임
    func testFeatureInitialStateContainsDefaultNavigationSlices() {
        let state = FileManagerFeature.State()

        XCTAssertEqual(state.content.navigation.currentPath, "Home")
        XCTAssertTrue(state.sidebar.sidebarVisible)
    }

    /// FMW-001-open_new_file_manager_window: onAppear 이후 기본 navigation path 보존
    /// FileManagerFeature onAppear가 초기 window 구성을 깨지 않고 기본 navigation path를 유지하는지 검증한다.
    /// - 검증 내용: onAppear 전송 후 content navigation currentPath 확인
    /// - 사전 조건: 테스트 UserDefaults/date dependency를 주입한 fresh FileManagerFeature.State
    /// - 기대 결과: currentPath가 Home 기본 경로로 유지됨
    func testFeatureOnAppearPreservesDefaultNavigationPath() async {
        let requestID = UUID()
        let store = TestStore(initialState: FileManagerFeature.State()) {
            FileManagerFeature()
        } withDependencies: {
            $0.userDefaultsClient = .testValue
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.uuid = .constant(requestID)
        }
        // 비포괄적: onAppear는 여러 초기화 child action을 방출하므로 FMW-001 초기 path 계약만 검증한다.
        store.exhaustivity = .off

        await store.send(.onAppear)

        XCTAssertEqual(store.state.content.navigation.currentPath, "Home")
    }

    /// FMW-001-open_file_manager_window: 제공된 초기 창 크기가 저장된 autosave frame보다 우선 적용된다.
    /// 실행 중 새 File Manager Window를 열 때 이전 autosave frame이 현재 요청 크기를 덮어쓰지 않는지 검증한다.
    /// - 검증 내용: applyInitialFrame이 initialWindowSizeProvider 값을 window frame에 적용하는지 확인
    /// - 사전 조건: NSWindow autosave frame이 저장되어 있고 initialWindowSizeProvider가 1180x720을 반환
    /// - 기대 결과: window.frame 크기가 1180x720으로 설정됨
    func testApplyInitialFramePrefersProvidedWindowSizeOverAutosave() {
        let autosaveName = FileManagerWindowChrome.frameAutosaveName
        NSWindow.removeFrame(usingName: autosaveName)
        defer { NSWindow.removeFrame(usingName: autosaveName) }

        let storedWindow = NSWindow(contentViewController: NSViewController())
        storedWindow.setFrame(NSRect(x: 0, y: 0, width: 960, height: 510), display: false)
        storedWindow.saveFrame(usingName: autosaveName)

        let window = NSWindow(contentViewController: NSViewController())
        FileManagerWindowChrome.configureWindowStyle(window)

        FileManagerWindowChrome.applyInitialFrame(
            window,
            initialWindowSizeProvider: { NSSize(width: 1180, height: 720) },
            reservesSidebarWidth: false,
        )

        XCTAssertEqual(window.frame.width, 1180, accuracy: 0.5)
        XCTAssertEqual(window.frame.height, 720, accuracy: 0.5)
    }

    private func assertEntryCommand(
        _ command: FileManagerWindowAction.WindowCommand,
        routesFrom state: FileManagerWindowState,
    ) async {
        let store = makeStore(initialState: state)

        await store.send(.request(command))
        await store.receive { action in
            matchesEntryCommandAction(command, action) || matchesAdditionalEntryCommandAction(command, action)
        }
        await store.finish()
    }

    private func assertPrimaryMenuItem(
        title: String,
        isTrashFolder: Bool,
        canPerformEntryCommands: Bool,
        isEnabled: Bool,
    ) {
        let configuration = ContentPaneContextMenuBuilder.Configuration(
            isTrashFolder: isTrashFolder,
            viewLayout: .list,
            sortKey: .name,
            sortOrder: .ascending,
            groupKey: .none,
            canPaste: true,
            itemCount: 1,
            canPerformEntryCommands: canPerformEntryCommands,
        )
        let item = ContentPaneContextMenuBuilder.makePrimaryMenuItem(configuration: configuration, target: self)

        XCTAssertEqual(item.title, title)
        XCTAssertEqual(item.isEnabled, isEnabled)
    }

    private func matchesEntryCommandAction(
        _ command: FileManagerWindowAction.WindowCommand,
        _ action: FileManagerWindowAction,
    ) -> Bool {
        switch (command, action) {
        case (.newFolder, .content(.entryOperations(.edit(.createNewFolder)))),
             (
                 .openSelectedItem,
                 .content(.entryViewLayout(.delegate(.executeCommand("navigation.openSelectedItem")))),
             ),
             (
                 .quickLookSelectedItem,
                 .content(.entryViewLayout(.delegate(.executeCommand("navigation.quickLookSelectedItem")))),
             ),
             (.cut, .content(.entryViewLayout(.delegate(.executeCommand("clipboard.cutSelectedItems"))))),
             (.copy, .content(.entryViewLayout(.delegate(.executeCommand("clipboard.copySelectedItems"))))),
             (.paste, .content(.entryViewLayout(.delegate(.executeCommand("clipboard.pasteItems"))))):
            true

        default:
            false
        }
    }

    private func matchesAdditionalEntryCommandAction(
        _ command: FileManagerWindowAction.WindowCommand,
        _ action: FileManagerWindowAction,
    ) -> Bool {
        switch (command, action) {
        case (.duplicate, .content(.entryViewLayout(.delegate(.executeCommand("clipboard.duplicateSelectedItems"))))),
             (
                 .makeAlias,
                 .content(.entryViewLayout(.delegate(.executeCommand("mutation.createAliasForSelectedItems")))),
             ),
             (.selectAll, .content(.view(.selectAllEntries))),
             (
                 .copyAbsolutePaths,
                 .content(.entryViewLayout(.delegate(.executeCommand("clipboard.copySelectedAbsolutePaths")))),
             ),
             (.copyURLs, .content(.entryViewLayout(.delegate(.executeCommand("clipboard.copySelectedURLs"))))):
            true

        default:
            false
        }
    }

    /// FMW-001-open_file_manager_window: provider가 없으면 저장된 autosave frame을 복원한다.
    /// 앱 재실행 후 첫 File Manager Window가 이전에 저장한 창 크기를 복원하는지 검증한다.
    /// - 검증 내용: applyInitialFrame이 provider nil 상태에서 autosave frame을 window frame으로 복원하는지 확인
    /// - 사전 조건: NSWindow autosave frame이 1240x760으로 저장되어 있고 initialWindowSizeProvider는 nil
    /// - 기대 결과: window.frame 크기가 1240x760으로 설정됨
    func testApplyInitialFrameRestoresAutosavedFrameWhenProviderMissing() {
        let autosaveName = FileManagerWindowChrome.frameAutosaveName
        NSWindow.removeFrame(usingName: autosaveName)
        defer { NSWindow.removeFrame(usingName: autosaveName) }

        let storedWindow = NSWindow(contentViewController: NSViewController())
        storedWindow.setFrame(NSRect(x: 0, y: 0, width: 1240, height: 760), display: false)
        FileManagerWindowChrome.saveFrame(storedWindow)

        let window = NSWindow(contentViewController: NSViewController())
        FileManagerWindowChrome.configureWindowStyle(window)

        FileManagerWindowChrome.applyInitialFrame(
            window,
            initialWindowSizeProvider: nil,
            reservesSidebarWidth: false,
        )

        XCTAssertEqual(window.frame.width, 1240, accuracy: 0.5)
        XCTAssertEqual(window.frame.height, 760, accuracy: 0.5)
    }
}

extension FMW001FileManagerWindowTests {
    // MARK: - FMW-001-open_file_manager_window

    /// FMW-001-open_file_manager_window: File Manager toolbar가 고정된 icon-only 표현을 유지한다.
    /// toolbar의 display mode contextual menu가 앱 전용 메뉴 뒤에 노출되지 않도록 창 스타일 계약을 검증한다.
    /// - 검증 내용: icon-only mode, 사용자 customization, configuration autosave, display mode customization 설정
    /// - 사전 조건: 새 NSWindow에 FileManagerWindowChrome 스타일 적용
    /// - 기대 결과: toolbar 표현과 customization 경로가 모두 고정됨
    func testConfigureWindowStyleDisablesToolbarDisplayModeCustomization() throws {
        let window = NSWindow(contentViewController: NSViewController())

        FileManagerWindowChrome.configureWindowStyle(window)

        let toolbar = try XCTUnwrap(window.toolbar)
        XCTAssertEqual(toolbar.displayMode, .iconOnly)
        XCTAssertFalse(toolbar.allowsUserCustomization)
        XCTAssertFalse(toolbar.autosavesConfiguration)
        if #available(macOS 15.0, *) {
            XCTAssertFalse(toolbar.allowsDisplayModeCustomization)
        }
    }
}

extension FMW001FileManagerWindowTests {
    // MARK: - FMW-001-entry_commands

    /// FMW-001-entry_commands: blank-area AppKit menu container disables automatic item validation.
    /// loading capability가 false인 item을 responder chain이 다시 활성화하면 stale callback guard가 우회될 수 있다.
    /// - 검증 내용: root와 nested builder가 공유하는 container의 autoenablesItems 상태.
    /// - 사전 조건: menu item registry resource를 초기화하지 않는 bare menu container다.
    /// - 기대 결과: container가 false를 반환해 명시적 capability를 보존한다.
    func testBlankAreaMenuContainerDisablesAutomaticValidation() {
        // RED: menu containers inherited AppKit auto-enablement.
        let menu = ContentPaneContextMenuBuilder.makeMenuContainer()

        // GREEN: root and nested builders share an explicit non-auto-enabling container.
        XCTAssertFalse(menu.autoenablesItems)
    }
}

extension FMW001FileManagerWindowTests {
    // MARK: - VOY-619-ai_chat_command_availability

    /// VOY-619-ai_chat_command_availability: 활성 탭의 Inspector capability를 메뉴 projection에 반영한다.
    /// 메뉴가 실행 불가능한 Home/AiChat 탭에서 활성 상태로 노출되지 않도록 canonical anchor capability를 검증한다.
    /// - 검증 내용: Home/AiChat과 Directory/Collection anchor별 canUseAiChatInspector 값
    /// - 사전 조건: 동일한 active tab의 anchor를 지원·미지원 유형으로 전환
    /// - 기대 결과: Inspector 지원 anchor에서만 AiChat 메뉴 명령이 활성화됨
    func testMenuCommandProjectionReflectsActiveTabInspectorCapability() throws {
        var state = FileManagerWindowState.makeInitial(path: "/Users/test/Documents")
        let activeTabID = try XCTUnwrap(state.contentTabs.activeTabID)

        XCTAssertFalse(state.menuCommandProjection.isNewChatPresented)
        XCTAssertFalse(state.menuCommandProjection.isChatHistoryPresented)

        state.inspector.inspectorVisible = true
        state.inspector.inspectorPaneExists = true
        state.inspector.activeMode = .chat
        state.inspector.aiChat.mode = .sessions
        XCTAssertFalse(state.menuCommandProjection.isNewChatPresented)
        XCTAssertTrue(state.menuCommandProjection.isChatHistoryPresented)

        state.inspector.aiChat.mode = .chat
        XCTAssertTrue(state.menuCommandProjection.isNewChatPresented)
        XCTAssertFalse(state.menuCommandProjection.isChatHistoryPresented)

        state.inspector.inspectorPaneExists = false
        XCTAssertFalse(state.menuCommandProjection.isNewChatPresented)
        XCTAssertFalse(state.menuCommandProjection.isChatHistoryPresented)

        XCTAssertTrue(state.menuCommandProjection.canUseAiChatInspector)

        state.contentTabs.tabs[id: activeTabID]?.anchor = .homeDefault
        XCTAssertFalse(state.menuCommandProjection.canUseAiChatInspector)

        state.contentTabs.tabs[id: activeTabID]?.anchor = .aiChat(sessionID: "projection-test")
        XCTAssertFalse(state.menuCommandProjection.canUseAiChatInspector)

        state.contentTabs.tabs[id: activeTabID]?.anchor = .directory(path: "/Users/test/Documents")
        XCTAssertTrue(state.menuCommandProjection.canUseAiChatInspector)

        state.contentTabs.tabs[id: activeTabID]?.anchor = .collectionFile(
            url: URL(fileURLWithPath: "/Users/test/Test.voycoll"),
        )
        XCTAssertTrue(state.menuCommandProjection.canUseAiChatInspector)

        state.contentTabs.tabs[id: activeTabID]?.anchor = .virtualCollection(id: "Favorite")
        XCTAssertTrue(state.menuCommandProjection.canUseAiChatInspector)
    }
}

private enum UndoRedoRequestKind {
    case undo
    case redo
}

private func matchesTargetedUndoRedoRequest(
    _ action: FileManagerWindowAction,
    tabID: ContentTabID,
    request: UndoRedoRequestKind,
) -> Bool {
    switch (request, action) {
    case let (.undo, .tabContent(tabID: targetID, action: .entryOperations(.undoRedo(.requestUndo)))),
         let (.redo, .tabContent(tabID: targetID, action: .entryOperations(.undoRedo(.requestRedo)))):
        targetID == tabID
    default:
        false
    }
}

private func makeUndoKeyCommand() -> KeyCommand {
    KeyCommand(
        keyCode: 6,
        modifiers: [.command],
        characters: "z",
        charactersIgnoringModifiers: "z",
    )
}

@MainActor
private func makeWindowCommandStore(
    request: UndoRedoRequestKind,
) throws -> (
    TestStore<FileManagerWindowState, FileManagerWindowAction>,
    ContentTabID,
) {
    var state = FileManagerWindowState()
    let activeTabID = try XCTUnwrap(state.contentTabs.activeTabID)
    let record = makeUndoRedoRecord(request == .undo ? "undo" : "redo")
    if request == .undo {
        state.content.entryOperations.undoRecords = [record]
    } else {
        state.content.entryOperations.redoRecords = [record]
    }
    let store = TestStore(initialState: state) {
        FileManagerWindowCommandRoutingReducer()
    }
    return (store, activeTabID)
}

private func makeUndoRedoRecord(_ name: String) -> EntryActionRecord {
    EntryActionRecord(
        operationKind: .rename,
        targets: [.init(beforePath: "/tmp/\(name)-old", afterPath: "/tmp/\(name)-new")],
    )
}

@MainActor
private func makeFileManagerContentStore() -> TestStore<FileManagerContentState, FileManagerContentAction> {
    TestStore(initialState: FileManagerContentState()) {
        FileManagerContentFeature()
    }
}
