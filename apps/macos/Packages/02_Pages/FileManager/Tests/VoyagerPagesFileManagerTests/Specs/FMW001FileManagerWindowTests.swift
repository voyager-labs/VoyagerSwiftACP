import AppKit
import ComposableArchitecture
import Foundation
import SwiftUI
import UniformTypeIdentifiers
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
        state.content.entryViewLayout.entryOperations.isLoading = isLoading
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
    /// - 검증 내용: undo/redo unavailable no-op, 기존 하위 action 방출, 새 tab routing 뒤 명시 selection 보존
    /// - 사전 조건: 일반 Directory mode, entry loading 중, active tab의 명시 selection/anchor 유지
    /// - 기대 결과: 명령 범주별 기존 routing을 유지하고 새 tab open이 기존 selection을 축소하지 않음
    func testOrdinaryDirectoryLoadingPreservesNonEntryCommands() async throws {
        var state = makeSelectedState(isLoading: true, isCollectionMode: false)
        state.content.entryViewLayout.entryOperations.undoRecords = [makeUndoRedoRecord("loading-undo")]
        state.content.entryViewLayout.entryOperations.redoRecords = [makeUndoRedoRecord("loading-redo")]
        let selectedTabID = try XCTUnwrap(state.contentTabs.activeTabID)
        state.contentTabs.selectedTabIDs = [selectedTabID]
        state.contentTabs.selectionAnchorID = selectedTabID
        let store = makeStore(initialState: state)

        await store.send(.request(.toggleShowHiddenFiles))
        await store.receive(\.content.view.toggleShowHiddenFilesAndReload)
        await store.send(.request(.requestUndo))
        await store.send(.request(.requestRedo))
        await store.send(.request(.goBack))
        await store.receive(\.navigation.view.goBack)
        await store.send(.request(.setViewLayout(.grid)))
        await store.receive(\.content.view.changeLayout)
        await store.send(.request(.openNewContentTab))
        await store.receive(\.contentTabs.open, .homeDefault)
        XCTAssertEqual(store.state.contentTabs.selectedTabIDs, [selectedTabID])
        XCTAssertEqual(store.state.contentTabs.selectionAnchorID, selectedTabID)
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
            guard case .content(.entryViewLayout(.delegate(.executeCommand(.navigation(.openSelectedItem))))) = $0
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
            guard case .content(.entryViewLayout(.delegate(.executeCommand(.navigation(.openSelectedItem))))) = $0
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
            guard case .content(.entryViewLayout(.delegate(.executeCommand(.navigation(.quickLookSelectedItem))))) = $0
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
            guard case .content(.entryViewLayout(.delegate(.executeCommand(.navigation(.quickLookSelectedItem))))) = $0
            else { return false }
            return true
        }
        await store.finish()
    }

    // MARK: - FMW-001-request_undo

    /// FMW-001-request_undo: root availability가 없으면 undo 명령은 no-op
    /// - 검증 내용: requestUndo가 child local stack을 선택하거나 action을 전달하지 않음
    /// - 사전 조건: 기본 root availability canUndo=false
    /// - 기대 결과: shared UndoManager 호출 및 child action 없이 종료
    func test_undoRedoRequest_undoUnavailable_isNoOp() async {
        let store = makeStore()

        await store.send(.request(.requestUndo))
        await store.finish()
    }

    /// FMW-001-request_undo: 표시 중인 Composer는 file Undo/Redo menu capability를 숨긴다.
    /// Text responder가 없는 상태에서도 Composer가 file-operation history보다 우선하는 menu projection을 검증한다.
    /// - 검증 내용: file undo/redo record가 각각 있어도 Composer 표시 중 projection의 canUndo/canRedo가 false인지 확인한다.
    /// - 사전 조건: active Content tab에 undo/redo history가 있고 Collection Filter Composer가 표시 중이다.
    /// - 기대 결과: isComposerPresented는 true이며 file Undo와 Redo menu capability는 모두 false다.
    func testComposerPresentedSuppressesFileUndoRedoMenuProjection() {
        var state = FileManagerWindowState()
        state.content.entryViewLayout.entryOperations.undoRecords = [makeUndoRedoRecord("composer-undo")]
        state.content.entryViewLayout.entryOperations.redoRecords = [makeUndoRedoRecord("composer-redo")]
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

    /// FMW-001-request_redo: root availability가 없으면 redo 명령은 no-op
    /// - 검증 내용: requestRedo가 child local stack을 선택하거나 action을 전달하지 않음
    /// - 사전 조건: 기본 root availability canRedo=false
    /// - 기대 결과: shared UndoManager 호출 및 child action 없이 종료
    func test_undoRedoRequest_redoUnavailable_isNoOp() async {
        let store = makeStore()

        await store.send(.request(.requestRedo))
        await store.finish()
    }

    /// FMW-001-request_undo: Window responder는 활성 탭 registry manager를 사용하고 foreign manager와 격리된다.
    /// 활성 scope의 file-operation undo가 별도 responder history를 소비하지 않는지 검증한다.
    /// - 검증 내용: coordinator/registry manager identity, undo 적용과 redo 생성, foreign action 미호출과 history 보존
    /// - 사전 조건: 활성 탭 scope에 file-operation record를 등록하고 별도 foreign manager에 action을 등록한다.
    /// - 기대 결과: file-operation undo만 적용되어 redo가 생기고 foreign action은 undo 가능한 상태로 남는다.
    func testEntryUndoManager_isolatedFromForeignResponderAction() throws {
        let registry = FileOperationUndoManagerRegistry()
        let client = FileOperationUndoManagerClient.live(registry: registry)
        let windowID = UUID()
        let coordinator = makeCoordinator(
            windowID: windowID,
            fileOperationUndoManagerRegistry: registry,
            fileOperationUndoManagerClient: client,
        )
        let foreignUndoManager = UndoManager()
        defer {
            coordinator.close()
            registry.deactivateAll(windowID: windowID)
            foreignUndoManager.removeAllActions()
        }

        let activeTabID = try XCTUnwrap(coordinator.store.withState(\.contentTabs.activeTabID))
        let scope = UndoManagerScope(windowID: windowID, contentTabID: activeTabID.rawValue)
        let generation = try XCTUnwrap(client.generation(scope))
        let registryUndoManager = try XCTUnwrap(registry.undoManager(for: scope))
        let window = try XCTUnwrap(coordinator.window)
        let coordinatorUndoManager = try XCTUnwrap(coordinator.windowWillReturnUndoManager(window))
        XCTAssertTrue(coordinatorUndoManager === registryUndoManager)

        let record = EntryActionRecord(
            operationKind: .rename,
            targets: [.init(beforePath: "/entry/old", afterPath: "/entry/new")],
        )
        XCTAssertTrue(client.registerUndo(scope, generation, record))

        let foreignTarget = ForeignUndoTarget()
        foreignUndoManager.beginUndoGrouping()
        foreignUndoManager.registerUndo(withTarget: foreignTarget) { target in
            target.invocationCount += 1
        }
        foreignUndoManager.endUndoGrouping()

        let outcome = client.performUndoRedo(scope, generation, .undo, record.id)

        XCTAssertEqual(outcome, .applied)
        XCTAssertTrue(registryUndoManager.canRedo)
        XCTAssertEqual(foreignTarget.invocationCount, 0)
        XCTAssertTrue(foreignUndoManager.canUndo)
    }

    /// FMW-001-request_undo: 등록되지 않은 Window ID의 Entry manager resolver는 fail-closed 처리한다.
    /// native key window나 first responder manager로 fallback하지 않는 factory 계약을 검증한다.
    /// - 검증 내용: undo/redo 모두 didInvoke=false이고 availability가 비어 있다.
    /// - 사전 조건: registry에 존재하지 않는 임의 Window ID와 expected target
    /// - 기대 결과: 어떤 native manager도 호출하지 않고 no-op으로 종료한다.
    func testFileManagerUndoManagerClient_missingWindowResolverIsNoOp() async {
        let client = UndoManagerClient.live(resolveUndoManager: { _ in nil })
        let missingWindowID = UUID()
        let target = UndoManagerRecordIdentity(ownerID: UUID(), recordID: UUID())

        let undoResult = await client.undo(missingWindowID, expectedTarget: target)
        let redoResult = await client.redo(missingWindowID, expectedTarget: target)
        let availability = await client.availability(missingWindowID)

        XCTAssertFalse(undoResult.didInvoke)
        XCTAssertFalse(redoResult.didInvoke)
        XCTAssertEqual(undoResult.availability, UndoManagerAvailability())
        XCTAssertEqual(redoResult.availability, UndoManagerAvailability())
        XCTAssertEqual(availability, UndoManagerAvailability())
    }

    /// FMW-001-request_undo: terminal이 invocation result보다 먼저 도착해도 late result는 무시됨
    /// - 검증 내용: invoking 중 content terminal success가 request-scoped refresh를 거쳐 뒤늦은 invocation result를 무시함
    /// - 사전 조건: undo client가 invocation result 반환 직전에 controllable gate에서 대기함
    /// - 기대 결과: terminal 직후 refreshing, matching availability 반영 후 idle, late result 수신 후에도 idle 유지
    func testUndoReplay_fastTerminalBeforeInvocationResult_ignoresLateResult() async throws {
        let requestID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000572"))
        let gate = FileManagerUndoInvocationGate()
        let calls = LockIsolated(0)
        let terminalAvailability = UndoManagerAvailability(canUndo: false, canRedo: true)
        let record = EntryActionRecord(
            operationKind: .rename,
            targets: [.init(beforePath: "/source/old", afterPath: "/source/new")],
        )
        var state = FileManagerWindowState()
        let ownerID = state.content.entryViewLayout.entryOperations.undoOwnerID
        let expectedTarget = UndoManagerRecordIdentity(ownerID: ownerID, recordID: record.id)
        state.content.entryViewLayout.entryOperations.undoRecords = [record]
        state.syncActiveTabContentState()
        state.undoManagerAvailability = .init(
            canUndo: true,
            canRedo: false,
            undoTarget: expectedTarget,
        )
        let client = UndoManagerClient(
            registerUndo: { _, _, _ in },
            undo: { _, receivedTarget in
                XCTAssertEqual(receivedTarget, expectedTarget)
                calls.withValue { $0 += 1 }
                await gate.suspend()
                return .init(didInvoke: true, availability: terminalAvailability)
            },
            redo: { _, _ in .init(didInvoke: false, availability: .init()) },
            availability: { _ in terminalAvailability },
        )
        let store = TestStore(initialState: state) {
            CombineReducers {
                FileManagerWindowCommandRoutingReducer()
                FileManagerWindowRoutingReducer()
            }
        } withDependencies: {
            $0.undoManagerClient = client
            $0.uuid = .constant(requestID)
        }

        await store.send(.request(.requestUndo)) {
            $0.undoRedoPhase = .invoking(requestID: requestID, direction: .undo)
        }
        await gate.waitUntilSuspended()
        XCTAssertFalse(store.state.menuCommandProjection.canUndo)
        XCTAssertFalse(store.state.menuCommandProjection.canRedo)

        await store.send(.content(.entryViewLayout(.entryOperations(.outcome(
            .entryActionReplayFinished(direction: .undo, terminal: .success(record)),
        ))))) {
            $0.undoRedoPhase = .refreshing(requestID: requestID)
        }
        await store.receive(\.internal.undoManagerReplayAvailabilityChanged) {
            $0.undoRedoPhase = .idle
            $0.undoManagerAvailability = terminalAvailability
        }
        await gate.resume()
        await store.receive(\.internal.undoManagerInvocationFinished)

        XCTAssertEqual(calls.value, 1)
        XCTAssertEqual(store.state.undoRedoPhase, .idle)
        XCTAssertEqual(store.state.undoManagerAvailability, terminalAvailability)
        await store.finish()
    }

    /// FMW-001-request_undo: replay availability completion은 matching request만 반영한다.
    /// - 검증 내용: stale request completion을 무시하고 matching completion에서 availability와 idle을 함께 commit한다.
    /// - 사전 조건: request-scoped refreshing phase와 서로 다른 stale requestID
    /// - 기대 결과: stale completion 상태 불변, matching completion 후 idle 및 최신 availability 반영
    func testUndoReplay_availabilityRefreshIgnoresStaleRequest() async {
        let requestID = UUID()
        let staleRequestID = UUID()
        let availability = UndoManagerAvailability(canUndo: false, canRedo: true)
        var state = FileManagerWindowState()
        state.undoRedoPhase = .refreshing(requestID: requestID)
        state.undoManagerAvailability = .init(canUndo: true, canRedo: false)
        let store = TestStore(initialState: state) {
            FileManagerWindowCommandRoutingReducer()
        }

        await store.send(.internal(.undoManagerReplayAvailabilityChanged(
            requestID: staleRequestID,
            availability: .init(canUndo: true, canRedo: true),
        )))
        await store.send(.internal(.undoManagerReplayAvailabilityChanged(
            requestID: requestID,
            availability: availability,
        ))) {
            $0.undoRedoPhase = .idle
            $0.undoManagerAvailability = availability
        }
        await store.finish()
    }

    /// FMW-001-request_undo: owner mismatch와 busy terminal은 Window를 desynchronized로 잠금
    /// - 검증 내용: 두 ownership failure 모두 menu command와 후속 shared-manager invocation을 차단함
    /// - 사전 조건: replaying phase이며 root availability는 undo/redo 모두 true
    /// - 기대 결과: desynchronized 유지, canUndo/canRedo false, 후속 request에도 client call 0회
    func testUndoReplay_ownerMismatchAndBusy_desynchronizeAndBlockFurtherCommands() async {
        for reason in [EntryActionReplayFailureReason.ownerRecordMismatch, .ownerBusy] {
            let requestID = UUID()
            let calls = LockIsolated(0)
            let client = UndoManagerClient(
                registerUndo: { _, _, _ in },
                undo: { _, _ in
                    calls.withValue { $0 += 1 }
                    return .init(didInvoke: true, availability: .init())
                },
                redo: { _, _ in
                    calls.withValue { $0 += 1 }
                    return .init(didInvoke: true, availability: .init())
                },
                availability: { _ in .init(canUndo: true, canRedo: true) },
            )
            var state = FileManagerWindowState()
            state.undoManagerAvailability = .init(canUndo: true, canRedo: true)
            state.undoRedoPhase = .replaying(requestID: requestID, direction: .undo)
            let store = TestStore(initialState: state) {
                CombineReducers {
                    FileManagerWindowCommandRoutingReducer()
                    FileManagerWindowRoutingReducer()
                }
            } withDependencies: {
                $0.undoManagerClient = client
            }

            await store.send(.content(.entryViewLayout(.entryOperations(.outcome(
                .entryActionReplayFinished(
                    direction: .undo,
                    terminal: .failure(reason: reason, appliedTargets: []),
                ),
            ))))) {
                $0.undoRedoPhase = .desynchronized
                $0.undoManagerAvailability = .init()
            }
            XCTAssertFalse(store.state.menuCommandProjection.canUndo)
            XCTAssertFalse(store.state.menuCommandProjection.canRedo)

            await store.send(.request(.requestUndo))
            await store.send(.request(.requestRedo))
            XCTAssertEqual(calls.value, 0)
            XCTAssertEqual(store.state.undoRedoPhase, .desynchronized)
            await store.finish()
        }
    }

    /// FMW-001-request_undo: missing owner와 direction mismatch event는 desynchronized로 잠금
    func testUndoManagerEvent_missingOwnerAndDirectionMismatch_desynchronize() async {
        let record = EntryActionRecord(
            operationKind: .rename,
            targets: [.init(beforePath: "/source/old", afterPath: "/source/new")],
        )

        var missingOwnerState = FileManagerWindowState()
        missingOwnerState.undoRedoPhase = .invoking(requestID: UUID(), direction: .undo)
        let missingOwnerStore = TestStore(initialState: missingOwnerState) {
            FileManagerWindowRoutingReducer()
        }
        await missingOwnerStore.send(.internal(.undoManagerEventReceived(.init(
            ownerID: UUID(),
            record: record,
            direction: .undo,
        )))) {
            $0.undoRedoPhase = .desynchronized
        }
        await missingOwnerStore.finish()

        var directionMismatchState = FileManagerWindowState()
        directionMismatchState.undoRedoPhase = .invoking(requestID: UUID(), direction: .undo)
        let activeOwnerID = directionMismatchState.content.entryViewLayout.entryOperations.undoOwnerID
        let directionMismatchStore = TestStore(initialState: directionMismatchState) {
            FileManagerWindowRoutingReducer()
        }
        await directionMismatchStore.send(.internal(.undoManagerEventReceived(.init(
            ownerID: activeOwnerID,
            record: record,
            direction: .redo,
        )))) {
            $0.undoRedoPhase = .desynchronized
        }
        await directionMismatchStore.finish()
    }

    /// FMW-001-request_undo: 비텍스트 Cmd-Z/Cmd-Shift-Z는 Content delegate를 거쳐 Window request로 변환된다.
    /// - 검증 내용: keyboard action이 child EntryOperations request를 직접 만들지 않고 typed delegate와 Window request를 순서대로 방출한다.
    /// - 사전 조건: native editable text responder가 없는 기본 Content 상태
    /// - 기대 결과: undo/redo 각각 requestUndoRedo delegate와 requestUndo/requestRedo Window action이 대응한다.
    func testKeyboardUndoRedo_routesThroughContentDelegateAndWindowRequest() async {
        for (modifiers, direction) in [
            (KeyModifiers.command, EntryActionDirection.undo),
            (KeyModifiers.command.union(.shift), EntryActionDirection.redo),
        ] {
            let command = KeyCommand(
                keyCode: 6,
                modifiers: modifiers,
                characters: modifiers.contains(.shift) ? "Z" : "z",
                charactersIgnoringModifiers: "z",
            )
            let contentStore = TestStore(initialState: FileManagerContentState()) {
                FileManagerContentKeyCommandReducer()
            }
            await contentStore.send(.view(.handleKeyCommand(command)))
            await contentStore.receive { action in
                guard case let .delegate(.requestUndoRedo(receivedDirection)) = action else { return false }
                return receivedDirection == direction
            }
            await contentStore.finish()

            let windowStore = makeStore()
            await windowStore.send(.content(.delegate(.requestUndoRedo(direction))))
            await windowStore.receive { action in
                switch (direction, action) {
                case (.undo, .request(.requestUndo)), (.redo, .request(.requestRedo)):
                    true
                default:
                    false
                }
            }
            await windowStore.finish()
        }
    }

    /// FMW-001-request_undo: editable text responder가 처리 가능한 Cmd-Z/Cmd-Shift-Z는 native responder가 먼저 소비한다.
    /// Menu/keyboard가 responder 전용 manager를 우선하고 Window Entry request를 만들지 않는 계약을 검증한다.
    /// - 검증 내용: direction별 native closure가 true일 때 Content delegate가 방출되지 않는다.
    /// - 사전 조건: undo/redo 가능한 editable text responder를 나타내는 deterministic native seam
    /// - 기대 결과: native undo/redo 각각 1회 호출, FileManager delegate 없음
    func testKeyboardUndoRedo_nativeEditableTextResponderHasPriority() async {
        for direction in [EntryActionDirection.undo, .redo] {
            let nativeCalls = LockIsolated(0)
            let store = TestStore(initialState: FileManagerContentState()) {
                Reduce<FileManagerContentState, FileManagerContentAction> { state, action in
                    guard case let .view(.handleKeyCommand(command)) = action else { return .none }
                    return FileManagerContentKeyCommandHandler.effect(
                        for: command,
                        state: state,
                        consumeNativeUndo: {
                            guard direction == .undo else { return false }
                            nativeCalls.withValue { $0 += 1 }
                            return true
                        },
                        consumeNativeRedo: {
                            guard direction == .redo else { return false }
                            nativeCalls.withValue { $0 += 1 }
                            return true
                        },
                    )
                }
            }
            let modifiers: KeyModifiers = direction == .undo ? .command : [.command, .shift]

            await store.send(.view(.handleKeyCommand(KeyCommand(
                keyCode: 6,
                modifiers: modifiers,
                characters: direction == .undo ? "z" : "Z",
                charactersIgnoringModifiers: "z",
            ))))
            await store.finish()

            XCTAssertEqual(nativeCalls.value, 1)
        }
    }

    /// FMW-001-request_undo: sidebar replay recovery는 dedicated owner만 회전한다.
    /// - 검증 내용: sidebar owner/history 회전과 active content owner 불변
    /// - 사전 조건: sidebar owner를 대상으로 성공한 invalidation completion
    /// - 기대 결과: sidebar에 새 owner와 빈 history, idle availability 반영
    func testUndoReplay_sidebarRecoveryRotatesOnlyDedicatedOwner() async {
        let requestID = UUID()
        let ownerID = UUID()
        let newOwnerID = UUID()
        let record = EntryActionRecord(
            operationKind: .rename,
            targets: [.init(beforePath: "/sidebar/old", afterPath: "/sidebar/new")],
        )
        var state = FileManagerWindowState()
        state.undoRedoPhase = .recovering(requestID: requestID, direction: .undo, ownerID: ownerID)
        state.sidebarEntryDropOperations.undoOwnerID = ownerID
        state.sidebarEntryDropOperations.undoRecords = [record]
        state.sidebarEntryDropOperations.redoRecords = [record]
        let activeOperations = state.content.entryViewLayout.entryOperations
        let availability = UndoManagerAvailability(canUndo: false, canRedo: true)
        let store = TestStore(initialState: state) {
            FileManagerWindowRoutingReducer()
        } withDependencies: {
            $0.uuid = .constant(newOwnerID)
        }

        await store.send(.internal(.undoManagerOwnerInvalidationFinished(
            requestID: requestID,
            ownerID: ownerID,
            result: .init(succeeded: true, availability: availability),
        ))) {
            $0.sidebarEntryDropOperations.rotateUndoOwner(to: newOwnerID)
            $0.undoRedoPhase = .idle
            $0.undoManagerAvailability = availability
        }

        XCTAssertEqual(store.state.content.entryViewLayout.entryOperations, activeOperations)
        await store.finish()
    }

    /// FMW-001-request_undo: operation failure recovery는 owner invalidation 성공 때만 idle로 복귀한다.
    /// - 검증 내용: replay failure가 recovering으로 잠근 뒤 typed availability를 반영하고 stale completion은 무시한다.
    /// - 사전 조건: replaying request/owner/window와 성공 invalidation 결과
    /// - 기대 결과: 성공 completion은 idle, stale request completion은 상태 불변
    func testUndoReplay_operationFailureRecoversOnlyForMatchingInvalidation() async throws {
        let requestID = UUID()
        let staleRequestID = UUID()
        let windowID = UUID()
        let gate = FileManagerUndoInvocationGate()
        var state = FileManagerWindowState()
        state.windowID = windowID
        state.undoManagerAvailability = .init(canUndo: true, canRedo: true)
        state.undoRedoPhase = .replaying(requestID: requestID, direction: .undo)
        let ownerID = state.content.entryViewLayout.entryOperations.undoOwnerID
        let newOwnerID = UUID()
        let uuidCalls = LockIsolated(0)
        let replayRecord = EntryActionRecord(
            operationKind: .rename,
            targets: [.init(beforePath: "/active/old", afterPath: "/active/new")],
        )
        state.content.entryViewLayout.entryOperations.undoRecords = [replayRecord]
        state.content.entryViewLayout.entryOperations.redoRecords = [replayRecord]
        state.syncActiveTabContentState()
        let activeTabID = try XCTUnwrap(state.contentTabs.activeTabID)
        let recoveredAvailability = UndoManagerAvailability(canUndo: false, canRedo: true)
        let client = UndoManagerClient(
            registerUndo: { _, _, _ in },
            undo: { _, _ in .init(didInvoke: false, availability: .init()) },
            redo: { _, _ in .init(didInvoke: false, availability: .init()) },
            invalidateOwner: { receivedWindowID, receivedOwnerID in
                XCTAssertEqual(receivedWindowID, windowID)
                XCTAssertEqual(receivedOwnerID, ownerID)
                await gate.suspend()
                return .init(succeeded: true, availability: recoveredAvailability)
            },
        )
        let store = TestStore(initialState: state) {
            FileManagerWindowRoutingReducer()
        } withDependencies: {
            $0.undoManagerClient = client
            $0.uuid = UUIDGenerator {
                uuidCalls.withValue { $0 += 1 }
                return newOwnerID
            }
        }

        await store.send(.content(.entryViewLayout(.entryOperations(.outcome(
            .entryActionReplayFinished(
                direction: .undo,
                terminal: .failure(reason: .operationFailed, appliedTargets: []),
            ),
        ))))) {
            $0.undoRedoPhase = .recovering(requestID: requestID, direction: .undo, ownerID: ownerID)
            $0.undoManagerAvailability = .init()
        }
        await gate.waitUntilSuspended()
        await store.send(.internal(.undoManagerOwnerInvalidationFinished(
            requestID: staleRequestID,
            ownerID: ownerID,
            result: .init(succeeded: true, availability: .init(canUndo: true, canRedo: true)),
        )))
        XCTAssertEqual(uuidCalls.value, 0)
        await gate.resume()
        await store.receive { action in
            guard case let .internal(.undoManagerOwnerInvalidationFinished(
                receivedRequestID,
                receivedOwnerID,
                result,
            )) = action else { return false }
            return receivedRequestID == requestID
                && receivedOwnerID == ownerID
                && result == .init(succeeded: true, availability: recoveredAvailability)
        } assert: {
            $0.content.entryViewLayout.entryOperations.rotateUndoOwner(to: newOwnerID)
            $0.syncActiveTabContentState()
            $0.undoRedoPhase = .idle
            $0.undoManagerAvailability = recoveredAvailability
        }
        XCTAssertEqual(uuidCalls.value, 1)
        XCTAssertEqual(
            store.state.tabContentStates[activeTabID]?.entryViewLayout.entryOperations,
            store.state.content.entryViewLayout.entryOperations,
        )
        await store.finish()
    }

    /// FMW-001-request_undo: recovery 대상 누락과 inactive owner 중복은 fail-closed 처리된다.
    /// - 검증 내용: missing/ambiguous completion이 UUID를 소비하지 않고 availability를 비움
    /// - 사전 조건: 현재 owner가 없거나 inactive cache 두 곳에 같은 owner가 존재함
    /// - 기대 결과: desynchronized, owner 불변, UUID 호출 0회
    func testUndoReplay_missingOrAmbiguousRecoveryTargetFailsClosedWithoutUUIDConsumption() async {
        let uuidCalls = LockIsolated(0)
        let missingRequestID = UUID()
        let missingOwnerID = UUID()
        var missingState = FileManagerWindowState()
        missingState.undoRedoPhase = .recovering(
            requestID: missingRequestID,
            direction: .undo,
            ownerID: missingOwnerID,
        )
        let missingStore = TestStore(initialState: missingState) {
            FileManagerWindowRoutingReducer()
        } withDependencies: {
            $0.uuid = UUIDGenerator {
                uuidCalls.withValue { $0 += 1 }
                return UUID()
            }
        }

        await missingStore.send(.internal(.undoManagerOwnerInvalidationFinished(
            requestID: missingRequestID,
            ownerID: missingOwnerID,
            result: .init(succeeded: true, availability: .init(canUndo: true, canRedo: true)),
        ))) {
            $0.undoRedoPhase = .desynchronized
        }
        await missingStore.finish()

        let ambiguousRequestID = UUID()
        let ambiguousOwnerID = UUID()
        let firstTabID = ContentTabID(rawValue: "ambiguous-first")
        let secondTabID = ContentTabID(rawValue: "ambiguous-second")
        var ambiguousState = FileManagerWindowState()
        ambiguousState.undoRedoPhase = .recovering(
            requestID: ambiguousRequestID,
            direction: .redo,
            ownerID: ambiguousOwnerID,
        )
        var firstContent = FileManagerContentFeature.State()
        firstContent.entryViewLayout.entryOperations.undoOwnerID = ambiguousOwnerID
        var secondContent = FileManagerContentFeature.State()
        secondContent.entryViewLayout.entryOperations.undoOwnerID = ambiguousOwnerID
        ambiguousState.tabContentStates[firstTabID] = firstContent
        ambiguousState.tabContentStates[secondTabID] = secondContent
        let ambiguousStore = TestStore(initialState: ambiguousState) {
            FileManagerWindowRoutingReducer()
        } withDependencies: {
            $0.uuid = UUIDGenerator {
                uuidCalls.withValue { $0 += 1 }
                return UUID()
            }
        }

        await ambiguousStore.send(.internal(.undoManagerOwnerInvalidationFinished(
            requestID: ambiguousRequestID,
            ownerID: ambiguousOwnerID,
            result: .init(succeeded: true, availability: .init(canUndo: true, canRedo: true)),
        ))) {
            $0.undoRedoPhase = .desynchronized
        }
        await ambiguousStore.finish()
        XCTAssertEqual(uuidCalls.value, 0)
    }

    /// FMW-001-request_undo: 회전된 active owner는 다음 native undo 등록에 사용된다.
    /// - 검증 내용: recovery 직후 entryActionCompleted가 새 owner로 registerUndo를 호출함
    /// - 사전 조건: active owner invalidation 성공과 deterministic replacement owner
    /// - 기대 결과: 새 owner로 1회 등록되고 local undo history에 record가 추가됨
    func testUndoReplay_activeRecoveryAllowsRegistrationWithRotatedOwner() async {
        let requestID = UUID()
        let windowID = UUID()
        let oldOwnerID = UUID()
        let newOwnerID = UUID()
        let registerOwnerIDs = LockIsolated<[UUID]>([])
        let record = EntryActionRecord(
            operationKind: .rename,
            targets: [.init(beforePath: "/active/old", afterPath: "/active/new")],
        )
        var state = FileManagerWindowState()
        state.windowID = windowID
        state.undoRedoPhase = .recovering(requestID: requestID, direction: .undo, ownerID: oldOwnerID)
        state.content.entryViewLayout.entryOperations.windowID = windowID
        state.content.entryViewLayout.entryOperations.undoOwnerID = oldOwnerID
        state.syncActiveTabContentState()
        let client = UndoManagerClient(
            registerUndo: { _, ownerID, _ in registerOwnerIDs.withValue { $0.append(ownerID) } },
            undo: { _, _ in .init(didInvoke: false, availability: .init()) },
            redo: { _, _ in .init(didInvoke: false, availability: .init()) },
        )
        let store = TestStore(initialState: state) {
            CombineReducers {
                FileManagerWindowRoutingReducer()
                Scope(
                    state: \.content.entryViewLayout.entryOperations,
                    action: \.content.entryViewLayout.entryOperations,
                ) {
                    EntryOperationsFeature()
                }
            }
        } withDependencies: {
            $0.undoManagerClient = client
            $0.uuid = .constant(newOwnerID)
        }

        await store.send(.internal(.undoManagerOwnerInvalidationFinished(
            requestID: requestID,
            ownerID: oldOwnerID,
            result: .init(succeeded: true, availability: .init()),
        ))) {
            $0.content.entryViewLayout.entryOperations.rotateUndoOwner(to: newOwnerID)
            $0.syncActiveTabContentState()
            $0.undoRedoPhase = .idle
        }
        await store.send(.content(.entryViewLayout(.entryOperations(.lifecycle(.entryActionCompleted(record)))))) {
            $0.content.entryViewLayout.entryOperations.undoRecords = [record]
        }
        await store.receive(\.content.entryViewLayout.entryOperations.outcome.undoManagerAvailabilityChanged)
        await store.finish()

        XCTAssertEqual(registerOwnerIDs.value, [newOwnerID])
    }

    /// FMW-001-request_undo: owner invalidation 실패는 desynchronized fail-closed 상태를 유지한다.
    /// - 검증 내용: resolver/cleanup 실패 결과가 undo/redo availability를 비우고 command를 계속 잠근다.
    /// - 사전 조건: replaying operation failure와 실패 invalidation client
    /// - 기대 결과: desynchronized, canUndo/canRedo false
    func testUndoReplay_invalidationFailureDesynchronizesAndDisablesMenu() async {
        let requestID = UUID()
        let uuidCalls = LockIsolated(0)
        var state = FileManagerWindowState()
        state.windowID = UUID()
        state.undoManagerAvailability = .init(canUndo: true, canRedo: true)
        state.undoRedoPhase = .replaying(requestID: requestID, direction: .redo)
        let ownerID = state.content.entryViewLayout.entryOperations.undoOwnerID
        let client = UndoManagerClient(
            registerUndo: { _, _, _ in },
            undo: { _, _ in .init(didInvoke: false, availability: .init()) },
            redo: { _, _ in .init(didInvoke: false, availability: .init()) },
            invalidateOwner: { _, _ in .init(succeeded: false, availability: .init(canUndo: true, canRedo: true)) },
        )
        let store = TestStore(initialState: state) {
            FileManagerWindowRoutingReducer()
        } withDependencies: {
            $0.undoManagerClient = client
            $0.uuid = UUIDGenerator {
                uuidCalls.withValue { $0 += 1 }
                return UUID()
            }
        }

        await store.send(.content(.entryViewLayout(.entryOperations(.outcome(
            .entryActionReplayFinished(
                direction: .redo,
                terminal: .failure(reason: .operationFailed, appliedTargets: []),
            ),
        ))))) {
            $0.undoRedoPhase = .recovering(requestID: requestID, direction: .redo, ownerID: ownerID)
            $0.undoManagerAvailability = .init()
        }
        await store.receive(\.internal.undoManagerOwnerInvalidationFinished) {
            $0.undoRedoPhase = .desynchronized
        }
        XCTAssertFalse(store.state.menuCommandProjection.canUndo)
        XCTAssertFalse(store.state.menuCommandProjection.canRedo)
        XCTAssertEqual(store.state.content.entryViewLayout.entryOperations.undoOwnerID, ownerID)
        XCTAssertEqual(uuidCalls.value, 0)
        await store.finish()
    }

    /// FMW-001-request_undo: busy owner는 shared manager 호출을 막고 idle snapshot에서만 허용한다.
    /// sidebar, active, inactive owner 모두 같은 owner-aware preflight를 사용하는지 undo/redo 양방향으로 검증한다.
    /// - 검증 내용: busy에서는 menu disabled/client 0회/UUID 0회이고 idle에서는 expected target으로 정확히 1회 호출한다.
    /// - 사전 조건: manager top identity와 local latest record가 일치하며 동일 record target의 busy 상태만 전환한다.
    /// - 기대 결과: 여섯 owner-direction 조합 모두 busy no-op 후 idle invocation이 성립한다.
    func testUndoRedoBusyOwnerBlocksInvocationUntilIdleAcrossAllOwnerLocations() async {
        for location in UndoOwnerLocation.allCases {
            for direction in [EntryActionDirection.undo, .redo] {
                let ownerID = UUID()
                let record = EntryActionRecord(
                    operationKind: .rename,
                    targets: [.init(
                        beforePath: "/\(location.rawValue)/old",
                        afterPath: "/\(location.rawValue)/new",
                    )],
                )
                let target = UndoManagerRecordIdentity(ownerID: ownerID, recordID: record.id)
                let calls = LockIsolated(0)
                let receivedTargets = LockIsolated<[UndoManagerRecordIdentity?]>([])
                let uuidCalls = LockIsolated(0)
                let requestID = UUID()

                let busyState = makeUndoRedoState(
                    location: location,
                    direction: direction,
                    ownerID: ownerID,
                    record: record,
                    isBusy: true,
                )
                let busyAvailability = busyState.undoManagerAvailability
                let client = UndoManagerClient(
                    registerUndo: { _, _, _ in },
                    undo: { _, receivedTarget in
                        calls.withValue { $0 += 1 }
                        receivedTargets.withValue { $0.append(receivedTarget) }
                        return .init(didInvoke: false, availability: busyAvailability)
                    },
                    redo: { _, receivedTarget in
                        calls.withValue { $0 += 1 }
                        receivedTargets.withValue { $0.append(receivedTarget) }
                        return .init(didInvoke: false, availability: busyAvailability)
                    },
                )
                let makeUUID = UUIDGenerator {
                    uuidCalls.withValue { $0 += 1 }
                    return requestID
                }
                let busyStore = makeStore(initialState: busyState)
                busyStore.dependencies.undoManagerClient = client
                busyStore.dependencies.uuid = makeUUID

                XCTAssertFalse(canInvoke(direction, projection: busyStore.state.menuCommandProjection))
                await busyStore.send(.request(command(for: direction)))
                XCTAssertEqual(busyStore.state.undoRedoPhase, .idle)
                XCTAssertEqual(calls.value, 0)
                XCTAssertEqual(uuidCalls.value, 0)
                await busyStore.finish()

                let idleState = makeUndoRedoState(
                    location: location,
                    direction: direction,
                    ownerID: ownerID,
                    record: record,
                    isBusy: false,
                )
                let idleStore = makeStore(initialState: idleState)
                idleStore.dependencies.undoManagerClient = client
                idleStore.dependencies.uuid = makeUUID

                XCTAssertTrue(canInvoke(direction, projection: idleStore.state.menuCommandProjection))
                await idleStore.send(.request(command(for: direction))) {
                    $0.undoRedoPhase = .invoking(requestID: requestID, direction: direction)
                }
                await idleStore.receive(\.internal.undoManagerInvocationFinished) {
                    $0.undoRedoPhase = .idle
                    $0.undoManagerAvailability = busyAvailability
                }
                XCTAssertEqual(calls.value, 1, location.rawValue)
                XCTAssertEqual(receivedTargets.value, [target], location.rawValue)
                XCTAssertEqual(uuidCalls.value, 1, location.rawValue)
                await idleStore.finish()
            }
        }
    }

    /// FMW-001-request_undo: 검증 불가능한 top identity는 fail-closed no-op 처리한다.
    /// native availability가 true여도 owner/record를 유일하게 증명하지 못하면 Window가 호출하지 않는지 검증한다.
    /// - 검증 내용: unknown, missing, duplicate, record mismatch에서 menu disabled/client 0회/UUID 0회이다.
    /// - 사전 조건: undo와 redo 각각 manager target metadata 또는 local owner 구성이 불완전하다.
    /// - 기대 결과: phase는 idle을 유지하고 shared manager 호출이나 request ID 소비가 없다.
    func testUndoRedoUnknownMissingDuplicateAndMismatchFailClosedWithoutInvocation() async {
        for direction in [EntryActionDirection.undo, .redo] {
            let ownerID = UUID()
            let record = EntryActionRecord(
                operationKind: .rename,
                targets: [.init(beforePath: "/validation/old", afterPath: "/validation/new")],
            )
            let baseState = makeUndoRedoState(
                location: .active,
                direction: direction,
                ownerID: ownerID,
                record: record,
                isBusy: false,
            )

            var unknownState = baseState
            setManagerTarget(nil, direction: direction, state: &unknownState)

            var missingState = baseState
            setManagerTarget(
                .init(ownerID: UUID(), recordID: record.id),
                direction: direction,
                state: &missingState,
            )

            var duplicateState = baseState
            duplicateState.sidebarEntryDropOperations = duplicateState.content.entryViewLayout.entryOperations

            var mismatchState = baseState
            setManagerTarget(
                .init(ownerID: ownerID, recordID: UUID()),
                direction: direction,
                state: &mismatchState,
            )

            for (name, state) in [
                ("unknown", unknownState),
                ("missing", missingState),
                ("duplicate", duplicateState),
                ("mismatch", mismatchState),
            ] {
                let calls = LockIsolated(0)
                let uuidCalls = LockIsolated(0)
                let client = UndoManagerClient(
                    registerUndo: { _, _, _ in },
                    undo: { _, _ in
                        calls.withValue { $0 += 1 }
                        return .init(didInvoke: true, availability: .init())
                    },
                    redo: { _, _ in
                        calls.withValue { $0 += 1 }
                        return .init(didInvoke: true, availability: .init())
                    },
                )
                let store = makeStore(initialState: state)
                store.dependencies.undoManagerClient = client
                store.dependencies.uuid = UUIDGenerator {
                    uuidCalls.withValue { $0 += 1 }
                    return UUID()
                }

                XCTAssertFalse(canInvoke(direction, projection: store.state.menuCommandProjection), name)
                await store.send(.request(command(for: direction)))
                XCTAssertEqual(store.state.undoRedoPhase, .idle, name)
                XCTAssertEqual(calls.value, 0, name)
                XCTAssertEqual(uuidCalls.value, 0, name)
                await store.finish()
            }
        }
    }

    private enum UndoOwnerLocation: String, CaseIterable {
        case sidebar
        case active
        case inactive
    }

    private func makeUndoRedoState(
        location: UndoOwnerLocation,
        direction: EntryActionDirection,
        ownerID: UUID,
        record: EntryActionRecord,
        isBusy: Bool,
    ) -> FileManagerWindowState {
        var state = FileManagerWindowState()
        state.windowID = UUID()
        var operations = EntryOperationsState(undoOwnerID: ownerID)
        switch direction {
        case .undo:
            operations.undoRecords = [record]
        case .redo:
            operations.redoRecords = [record]
        }
        if let busyPath = record.targets.first?.beforePath {
            operations.itemStates[busyPath] = .init(isBusy: isBusy)
        }

        switch location {
        case .sidebar:
            state.sidebarEntryDropOperations = operations
        case .active:
            state.content.entryViewLayout.entryOperations = operations
            state.syncActiveTabContentState()
        case .inactive:
            var inactiveContent = FileManagerContentFeature.State()
            inactiveContent.entryViewLayout.entryOperations = operations
            state.tabContentStates[ContentTabID(rawValue: "owner-aware-inactive")] = inactiveContent
        }

        let target = UndoManagerRecordIdentity(ownerID: ownerID, recordID: record.id)
        setManagerTarget(target, direction: direction, state: &state)
        return state
    }

    private func setManagerTarget(
        _ target: UndoManagerRecordIdentity?,
        direction: EntryActionDirection,
        state: inout FileManagerWindowState,
    ) {
        switch direction {
        case .undo:
            state.undoManagerAvailability = .init(canUndo: true, undoTarget: target)
        case .redo:
            state.undoManagerAvailability = .init(canRedo: true, redoTarget: target)
        }
    }

    private func command(for direction: EntryActionDirection) -> FileManagerWindowAction.WindowCommand {
        direction == .undo ? .requestUndo : .requestRedo
    }

    private func canInvoke(
        _ direction: EntryActionDirection,
        projection: FileManagerWindowMenuCommandProjection,
    ) -> Bool {
        direction == .undo ? projection.canUndo : projection.canRedo
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

        XCTAssertNil(state.content.entryViewLayout.entryOperations.windowID)
    }

    /// FMW-001-open_new_file_manager_window: makeInitial path seed와 entry operation state 분리
    /// FileManager window 초기 상태와 entry operation state 격리 계약을 검증.
    /// - 검증 내용: 초기 path seed가 entry operation windowID를 오염시키지 않는지 검증
    /// - 사전 조건: FileManagerWindowState 기본 생성 또는 makeInitial 사용
    /// - 기대 결과: entry operation windowID와 collection mode 상태가 명확한 기본값 유지
    func testMakeInitialSeedsPathThroughNavigationState() {
        let path = "/Users/test/Documents"
        let state = FileManagerWindowState.makeInitial(path: path)

        XCTAssertNil(state.content.entryViewLayout.entryOperations.windowID)
    }

    /// FMW-001-open_new_file_manager_window: FileManagerWindowState 기본 collection mode 비활성
    /// FileManager window 초기 상태와 entry operation state 격리 계약을 검증.
    /// - 검증 내용: 기본 window state가 collection mode와 entry operation windowID를 갖지 않는지 검증
    /// - 사전 조건: FileManagerWindowState 기본 생성 또는 makeInitial 사용
    /// - 기대 결과: entry operation windowID와 collection mode 상태가 명확한 기본값 유지
    func testWindowDefaultStateHasNoCollectionMode() {
        let state = FileManagerWindowState()

        XCTAssertFalse(state.content.entryViewLayout.isCollectionMode)
        XCTAssertNil(state.content.entryViewLayout.entryOperations.windowID)
    }

    /// FMW-001-open_new_file_manager_window: entry operations reset 시 windowID 제거
    /// FileManager window 초기 상태와 entry operation state 격리 계약을 검증.
    /// - 검증 내용: content entryOperations state reset이 windowID를 제거하는지 검증
    /// - 사전 조건: FileManagerWindowState 기본 생성 또는 makeInitial 사용
    /// - 기대 결과: entry operation windowID와 collection mode 상태가 명확한 기본값 유지
    func testContentEntryOperationsResetClearsWindowID() {
        let windowID = UUID()
        var state = FileManagerWindowState.makeInitial(path: nil)
        state.content.entryViewLayout.entryOperations.windowID = windowID
        XCTAssertEqual(state.content.entryViewLayout.entryOperations.windowID, windowID)

        state.content.entryViewLayout.entryOperations = EntryOperationsState()
        XCTAssertNil(state.content.entryViewLayout.entryOperations.windowID)

        state.content.entryViewLayout.entryOperations.windowID = windowID
        XCTAssertEqual(state.content.entryViewLayout.entryOperations.windowID, windowID)
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
        case (.newFolder, .content(.entryViewLayout(.entryOperations(.edit(.createNewFolder))))),
             (
                 .openSelectedItem,
                 .content(.entryViewLayout(.delegate(.executeCommand(.navigation(.openSelectedItem))))),
             ),
             (
                 .quickLookSelectedItem,
                 .content(.entryViewLayout(.delegate(.executeCommand(.navigation(.quickLookSelectedItem))))),
             ),
             (.cut, .content(.entryViewLayout(.delegate(.executeCommand(.clipboard(.cutSelectedItems)))))),
             (.copy, .content(.entryViewLayout(.delegate(.executeCommand(.clipboard(.copySelectedItems)))))),
             (.paste, .content(.entryViewLayout(.delegate(.executeCommand(.clipboard(.pasteItems)))))):
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
        case (.duplicate, .content(.entryViewLayout(.delegate(.executeCommand(.clipboard(.duplicateSelectedItems)))))),
             (
                 .makeAlias,
                 .content(.entryViewLayout(.delegate(.executeCommand(.mutation(.createAliasForSelectedItems))))),
             ),
             (.selectAll, .content(.view(.selectAllEntries))),
             (
                 .copyAbsolutePaths,
                 .content(.entryViewLayout(.delegate(.executeCommand(.clipboard(.copySelectedAbsolutePaths))))),
             ),
             (.copyURLs, .content(.entryViewLayout(.delegate(.executeCommand(.clipboard(.copySelectedURLs)))))):
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

    private func makeCoordinator(
        windowID: UUID,
        fileOperationUndoManagerRegistry: FileOperationUndoManagerRegistry,
        fileOperationUndoManagerClient: FileOperationUndoManagerClient,
    ) -> FileManagerWindowCoordinator {
        let store = Store(initialState: FileManagerFeature.State()) {
            FileManagerFeature()
        } withDependencies: {
            $0.fileOperationUndoManagerClient = fileOperationUndoManagerClient
        }
        return FileManagerWindowCoordinator(
            windowID: windowID,
            store: store,
            fileOperationUndoManagerRegistry: fileOperationUndoManagerRegistry,
            makeContentViewController: { _, _ in NSViewController() },
        )
    }
}

private final class ForeignUndoTarget {
    var invocationCount = 0
}

private actor FileManagerUndoInvocationGate {
    private var suspension: CheckedContinuation<Void, Never>?
    private var suspensionWaiters: [CheckedContinuation<Void, Never>] = []

    func suspend() async {
        await withCheckedContinuation { continuation in
            suspension = continuation
            suspensionWaiters.forEach { $0.resume() }
            suspensionWaiters.removeAll()
        }
    }

    func waitUntilSuspended() async {
        guard suspension == nil else { return }
        await withCheckedContinuation { continuation in
            suspensionWaiters.append(continuation)
        }
    }

    func resume() {
        suspension?.resume()
        suspension = nil
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

    /// FMW-001-open_file_manager_window: Sidebar 외 배경은 기존 window movement를 유지한다.
    /// Sidebar hosting surface의 국소 override가 window 전역 이동 설정을 약화하지 않는지 검증한다.
    /// - 검증 내용: configureWindowStyle 이후 isMovableByWindowBackground true.
    /// - 사전 조건: 새 NSWindow에 FileManagerWindowChrome 스타일을 적용한다.
    /// - 기대 결과: File Manager window의 background movement가 계속 활성화된다.
    func testConfigureWindowStyleKeepsBackgroundWindowMovementEnabled() {
        let window = NSWindow(contentViewController: NSViewController())

        FileManagerWindowChrome.configureWindowStyle(window)

        XCTAssertTrue(window.isMovableByWindowBackground)
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
    case let (.undo, .tabContent(tabID: targetID, action: .entryViewLayout(.entryOperations(.undoRedo(.requestUndo))))),
         let (.redo, .tabContent(tabID: targetID, action: .entryViewLayout(.entryOperations(.undoRedo(.requestRedo))))):
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
        state.content.entryViewLayout.entryOperations.undoRecords = [record]
    } else {
        state.content.entryViewLayout.entryOperations.redoRecords = [record]
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

extension FMW001FileManagerWindowTests {
    // MARK: - FMW-001-move_content_tab_to_window

    /// FMW-001-move_content_tab_to_window: target 선택은 request UUID를 한 번 생성해 모든 delegate 계층에 보존한다.
    /// 사용자가 같은 target을 반복 선택해도 pending tab에는 하나의 요청만 전달되는 계약을 검증한다.
    /// - 검증 내용: Sidebar pending state, Sidebar delegate, Window delegate의 request identity와 중복 억제.
    /// - 사전 조건: source window ID, active tab, 두 target projection, 고정 UUID dependency가 있다.
    /// - 기대 결과: 첫 선택만 동일 request를 두 delegate 계층에 전달하고 두 번째 선택은 no-op이다.
    func testContentTabMoveSelectionCreatesOneRequestAndPreservesDelegateIdentity() async throws {
        let requestID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000301"))
        let sourceWindowID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000302"))
        let targetWindowID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000303"))
        var state = FileManagerWindowState()
        let tabID = try XCTUnwrap(state.contentTabs.activeTabID)
        state.sidebar.currentWindowID = sourceWindowID
        state.sidebar.contentTabMoveTargets = [
            ContentTabMoveTarget(windowID: targetWindowID, displayTitle: "Research"),
        ]
        let request = ContentTabMoveRequest(
            requestID: requestID,
            sourceWindowID: sourceWindowID,
            tabID: tabID,
            targetWindowID: targetWindowID,
        )
        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.uuid = .constant(requestID)
        }

        await store.send(.sidebar(.view(.moveContentTab(tabID: tabID, targetWindowID: targetWindowID)))) {
            $0.sidebar.pendingContentTabMoveRequest = request
        }
        await store.receive(\.sidebar.delegate.requestContentTabMove, request)
        await store.receive(\.delegate.requestContentTabMove, request)

        await store.send(.sidebar(.view(.moveContentTab(tabID: tabID, targetWindowID: targetWindowID))))
    }

    /// FMW-001-move_content_tab_to_window: matching success만 pending 요청을 종료한다.
    /// manager terminal이 현재 request와 정확히 일치할 때만 진행 표시가 사라지는 stale-safe 계약을 검증한다.
    /// - 검증 내용: stale success no-op과 matching success의 pending clear.
    /// - 사전 조건: source tab에 pending move request가 있고 stale request ID가 별도로 있다.
    /// - 기대 결과: stale terminal은 불변이고 matching terminal만 pending을 nil로 만든다.
    func testContentTabMoveSuccessClearsOnlyMatchingPendingRequest() async throws {
        let request = try makeContentTabMoveRequest()
        var state = FileManagerWindowState()
        state.sidebar.pendingContentTabMoveRequest = request
        let store = TestStore(initialState: state) {
            FileManagerFeature()
        }

        await store.send(.contentTabMoveSucceeded(requestID: UUID()))
        await store.send(.contentTabMoveSucceeded(requestID: request.requestID)) {
            $0.sidebar.pendingContentTabMoveRequest = nil
        }
    }

    /// FMW-001-move_content_tab_to_window: matching rejection은 네 사용자 범주만 window presentation으로 매핑한다.
    /// 내부 transfer 세부 정보 대신 고정된 사용자 의미만 source window에 표시하는 계약을 검증한다.
    /// - 검증 내용: unavailable/capacity/busy/generic terminal의 pending clear와 typed presentation 설정.
    /// - 사전 조건: 각 범주마다 matching pending request가 설정되어 있다.
    /// - 기대 결과: presentation은 request ID와 네 범주 중 하나만 보존한다.
    func testContentTabMoveRejectionMapsAllUserFacingCategories() async throws {
        for category in ContentTabMoveFailurePresentation.Category.allCases {
            let request = try makeContentTabMoveRequest()
            var state = FileManagerWindowState()
            state.sidebar.pendingContentTabMoveRequest = request
            let store = TestStore(initialState: state) {
                FileManagerFeature()
            }

            await store.send(.contentTabMoveRejected(requestID: request.requestID, category: category)) {
                $0.sidebar.pendingContentTabMoveRequest = nil
                $0.contentTabMoveFailurePresentation = ContentTabMoveFailurePresentation(
                    requestID: request.requestID,
                    category: category,
                )
            }
        }
    }

    /// FMW-001-move_content_tab_to_window: stale rejection과 stale dismiss는 현재 presentation을 변경하지 않는다.
    /// 늦게 도착한 manager/UI action이 새로운 failure ownership을 지우지 않는 계약을 검증한다.
    /// - 검증 내용: request ID mismatch terminal과 dismiss의 no-op.
    /// - 사전 조건: matching pending request와 다른 request ID의 기존 presentation이 있다.
    /// - 기대 결과: stale rejection은 pending을, stale dismiss는 presentation을 그대로 유지한다.
    func testContentTabMoveStaleTerminalAndDismissAreNoOps() async throws {
        let request = try makeContentTabMoveRequest()
        let presentation = ContentTabMoveFailurePresentation(requestID: UUID(), category: .busy)
        var state = FileManagerWindowState()
        state.sidebar.pendingContentTabMoveRequest = request
        state.contentTabMoveFailurePresentation = presentation
        let store = TestStore(initialState: state) {
            FileManagerFeature()
        }

        await store.send(.contentTabMoveRejected(requestID: UUID(), category: .generic))
        await store.send(.view(.dismissContentTabMoveFailure(requestID: UUID())))
    }

    /// FMW-001-move_content_tab_to_window: failure dismiss는 presentation 외 transfer semantic state를 변경하지 않는다.
    /// 사용자가 오류를 닫아도 target projection과 pending/ContentTab 상태가 보존되는 계약을 검증한다.
    /// - 검증 내용: matching dismiss의 presentation-only mutation.
    /// - 사전 조건: failure presentation, target projection, content tab state가 설정되어 있다.
    /// - 기대 결과: presentation만 nil이고 target과 ContentTab 상태는 동일하다.
    func testContentTabMoveFailureDismissPreservesTransferSemanticState() async throws {
        let request = try makeContentTabMoveRequest()
        let target = ContentTabMoveTarget(windowID: request.targetWindowID, displayTitle: "Research")
        var state = FileManagerWindowState()
        state.sidebar.contentTabMoveTargets = [target]
        state.contentTabMoveFailurePresentation = ContentTabMoveFailurePresentation(
            requestID: request.requestID,
            category: .unavailable,
        )
        let contentTabs = state.contentTabs
        let store = TestStore(initialState: state) {
            FileManagerFeature()
        }

        await store.send(.view(.dismissContentTabMoveFailure(requestID: request.requestID))) {
            $0.contentTabMoveFailurePresentation = nil
        }

        XCTAssertEqual(store.state.sidebar.contentTabMoveTargets, [target])
        XCTAssertEqual(store.state.contentTabs, contentTabs)
        XCTAssertNil(store.state.sidebar.pendingContentTabMoveRequest)
    }

    /// FMW-001-move_content_tab_to_window: 빈 projection과 current window target은 move command를 만들지 않는다.
    /// app projection이 비었거나 방어적으로 제거된 경우 Sidebar가 registry fallback 없이 no-op인지 검증한다.
    /// - 검증 내용: target filtering 순서와 유효하지 않은 target action의 delegate 미방출.
    /// - 사전 조건: current window와 동일한 target만 주입되거나 projection이 비어 있다.
    /// - 기대 결과: available target은 비고 move action은 pending/delegate를 만들지 않는다.
    func testContentTabMoveProjectionExcludesCurrentWindowAndEmptySelectionIsNoOp() async throws {
        let sourceWindowID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000310"))
        var state = FileManagerWindowState()
        let tabID = try XCTUnwrap(state.contentTabs.activeTabID)
        state.sidebar.currentWindowID = sourceWindowID
        state.sidebar.contentTabMoveTargets = [
            ContentTabMoveTarget(windowID: sourceWindowID, displayTitle: "Current"),
        ]
        XCTAssertTrue(ContentTabMoveProjection.availableTargets(
            state.sidebar.contentTabMoveTargets,
            currentWindowID: sourceWindowID,
        ).isEmpty)
        let store = TestStore(initialState: state) {
            FileManagerFeature()
        }

        await store.send(.sidebar(.view(.moveContentTab(tabID: tabID, targetWindowID: UUID()))))
    }

    /// FMW-001-move_content_tab_to_window: target projection은 주입 순서를 보존한다.
    /// Sidebar menu가 display title이나 window ID로 재정렬하지 않는 순수 projection 계약을 검증한다.
    /// - 검증 내용: current window defensive filtering 이후 target 순서.
    /// - 사전 조건: current window를 사이에 포함한 세 target이 고정 순서로 주입된다.
    /// - 기대 결과: current window만 제거되고 나머지 두 target 순서는 그대로다.
    func testContentTabMoveProjectionPreservesInjectedTargetOrder() throws {
        let currentWindowID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000320"))
        let first = try ContentTabMoveTarget(
            windowID: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000321")),
            displayTitle: "Zeta",
        )
        let second = try ContentTabMoveTarget(
            windowID: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000322")),
            displayTitle: "Alpha",
        )
        let current = ContentTabMoveTarget(windowID: currentWindowID, displayTitle: "Current")

        XCTAssertEqual(
            ContentTabMoveProjection.availableTargets([first, current, second], currentWindowID: currentWindowID),
            [first, second],
        )
    }

    /// FMW-001-move_content_tab_to_window: row/menu/target/progress identifier는 stable typed ID만 사용한다.
    /// display title 변경이 UI automation identifier를 바꾸지 않는 추적 계약을 검증한다.
    /// - 검증 내용: 네 identifier의 정확한 문자열 형식.
    /// - 사전 조건: 고정 ContentTabID와 target window UUID가 있다.
    /// - 기대 결과: 요구된 prefix와 raw typed ID로 정확한 identifier가 생성된다.
    func testContentTabMoveAccessibilityIdentifiersAreStable() throws {
        let tabID = ContentTabID(rawValue: "tab-identifier")
        let windowID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000330"))

        XCTAssertEqual(ContentTabMoveProjection.rowIdentifier(tabID: tabID), "content-tab-tab-identifier")
        XCTAssertEqual(ContentTabMoveProjection.menuIdentifier(tabID: tabID), "content-tab-move-menu-tab-identifier")
        XCTAssertEqual(
            ContentTabMoveProjection.targetIdentifier(tabID: tabID, windowID: windowID),
            "content-tab-move-target-tab-identifier-00000000-0000-0000-0000-000000000330",
        )
        XCTAssertEqual(
            ContentTabMoveProjection.progressIdentifier(tabID: tabID),
            "content-tab-move-progress-tab-identifier",
        )
    }

    /// FMW-001-move_content_tab_to_window: Sidebar view는 projection과 stable identifier를 실제 context menu에 연결한다.
    /// 실행 가능한 SwiftUI inspection이 없는 패키지 환경에서 source-level wiring 계약을 고정한다.
    /// - 검증 내용: non-empty menu guard, injected-order ForEach, move-only disabled, row/menu/target/progress identifier
    /// 적용.
    /// - 사전 조건: package checkout의 canonical SidebarView.swift source를 읽을 수 있다.
    /// - 기대 결과: 요구된 wiring token이 모두 있고 view-side target sorting은 없다.
    func testContentTabMoveSidebarViewWiresMenuOrderPendingControlsAndIdentifiers() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = packageRoot.appendingPathComponent(
            "Sources/VoyagerPagesFileManager/Sidebar/Ui/SidebarView.swift",
        )
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("if !moveTargets.isEmpty"))
        XCTAssertTrue(source.contains(#"NSMenuItem(title: "Move to Window""#))
        XCTAssertTrue(source.contains("for target in moveTargets"))
        XCTAssertFalse(source.contains("moveTargets.sorted"))
        XCTAssertTrue(source.contains("moveItem.isEnabled = !isMovePending"))
        XCTAssertTrue(source.contains("targetItem.isEnabled = !isMovePending"))
        XCTAssertTrue(source.contains("setAccessibilityIdentifier(ContentTabMoveProjection.rowIdentifier"))
        XCTAssertTrue(source.contains("ContentTabMoveProjection.menuIdentifier(tabID: moveTargetsTabID)"))
        XCTAssertTrue(source.contains("ContentTabMoveProjection.targetIdentifier("))
        XCTAssertTrue(source.contains("ContentTabMoveProjection.progressIdentifier(tabID: item.id)"))
    }

    /// FMW-001-move_content_tab_to_window: 이동 실패 alert는 live main container가 단독 소유한다.
    /// 실행 가능한 SwiftUI inspection이 없는 패키지 환경에서 source-level alert hosting 계약을 고정한다.
    /// - 검증 내용: MainContainer의 alert/binding/dismiss/message mapping과 legacy WindowView alert 부재
    /// - 사전 조건: package checkout의 두 canonical window view source를 읽을 수 있다.
    /// - 기대 결과: live split layout 경로에만 content-tab move failure alert가 존재한다.
    func testContentTabMoveFailureAlertIsOwnedOnlyByLiveMainContainer() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let mainContainerSource = try String(
            contentsOf: packageRoot.appendingPathComponent(
                "Sources/VoyagerPagesFileManager/Window/Ui/FileManagerWindowMainContainerView.swift",
            ),
            encoding: .utf8,
        )
        let legacyWindowSource = try String(
            contentsOf: packageRoot.appendingPathComponent(
                "Sources/VoyagerPagesFileManager/Window/Ui/FileManagerWindowView.swift",
            ),
            encoding: .utf8,
        )

        XCTAssertTrue(mainContainerSource.contains(#".alert("#))
        XCTAssertTrue(mainContainerSource.contains("contentTabMoveFailureIsPresented"))
        XCTAssertTrue(mainContainerSource.contains("dismissContentTabMoveFailure"))
        XCTAssertTrue(mainContainerSource.contains("contentTabMoveFailureMessage"))
        XCTAssertTrue(mainContainerSource.contains(".view(.dismissContentTabMoveFailure(requestID: requestID))"))
        XCTAssertFalse(legacyWindowSource.contains(#".alert("#))
        XCTAssertFalse(legacyWindowSource.contains("contentTabMoveFailureIsPresented"))
    }

    /// FMW-001-move_content_tab_to_window: pending move는 다른 tab 선택 routing을 차단하지 않는다.
    /// 진행 중인 tab의 move control만 제한하고 일반 row navigation은 유지하는 계약을 검증한다.
    /// - 검증 내용: pending request가 있어도 다른 tab select delegate가 setCurrent와 selection collapse로 전달된다.
    /// - 사전 조건: 한 tab에 pending move가 있고 별도의 target tab이 존재한다.
    /// - 기대 결과: 다른 tab의 setCurrent와 collapseSelectionToActive action이 순서대로 방출된다.
    func testContentTabMovePendingPreservesUnrelatedTabSelection() async throws {
        let request = try makeContentTabMoveRequest()
        let otherTabID = ContentTabID(rawValue: "unrelated-tab")
        var state = FileManagerWindowState()
        state.sidebar.pendingContentTabMoveRequest = request
        state.contentTabs.tabs.append(ContentTabItem(
            id: otherTabID,
            page: .home,
            anchor: .homeDefault,
            isPinned: false,
            title: "Other",
            iconName: "house",
        ))
        state.tabContentStates[otherTabID] = FileManagerContentFeature.State.initialContent(
            for: .homeDefault,
            inheritingWindowContextFrom: state.content,
        )
        state.syncContentTabSidebarItems()
        let store = TestStore(initialState: state) {
            FileManagerWindowRoutingReducer()
        }

        await store.send(.sidebar(.delegate(.selectContentTab(otherTabID))))
        await store.receive(\.contentTabs.setCurrent, otherTabID)
        await store.receive(\.contentTabs.collapseSelectionToActive)
    }

    /// FMW-001-move_content_tab_to_window: drag payload는 version/source/tab locator만 round-trip한다.
    /// 외부 drop payload가 target/request/tab state를 권한 있는 값처럼 운반하지 않는 최소 계약을 검증한다.
    /// - 검증 내용: Codable round-trip의 exact field 보존과 top-level encoded key allowlist.
    /// - 사전 조건: 지원 schema version, source window UUID, ContentTabID가 있다.
    /// - 기대 결과: 세 값만 복원되고 target/request/state 관련 key는 존재하지 않는다.
    func testContentTabDragPayloadRoundTripUsesMinimalVersionedLocatorKeys() throws {
        let sourceWindowID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000351"))
        let payload = ContentTabDragPayload(
            schemaVersion: ContentTabDragPayload.supportedSchemaVersion,
            sourceWindowID: sourceWindowID,
            tabID: ContentTabID(rawValue: "drag-payload-tab"),
        )

        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(ContentTabDragPayload.self, from: data)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(decoded, payload)
        XCTAssertEqual(decoded.schemaVersion, ContentTabDragPayload.supportedSchemaVersion)
        XCTAssertEqual(decoded.sourceWindowID, sourceWindowID)
        XCTAssertEqual(decoded.tabID, ContentTabID(rawValue: "drag-payload-tab"))
        XCTAssertEqual(Set(object.keys), ["schemaVersion", "sourceWindowID", "tabID"])
        XCTAssertTrue(ContentTabDragPayload.isSupported(schemaVersion: decoded.schemaVersion))
        XCTAssertFalse(ContentTabDragPayload.isSupported(schemaVersion: decoded.schemaVersion + 1))
        for forbiddenKey in ["targetWindowID", "requestID", "title", "path", "anchor", "state", "workUnit"] {
            XCTAssertNil(object[forbiddenKey])
        }
    }

    /// FMW-001-move_content_tab_to_window: drag UTI는 안정적인 identifier와 JSON conformance를 함께 선언한다.
    /// Swift Transferable representation과 app bundle exported declaration이 공유할 code-side 계약을 검증한다.
    /// - 검증 내용: contentType identifier와 public.json conformance.
    /// - 사전 조건: ContentTabDragPayload의 custom exported UTType이 있다.
    /// - 기대 결과: identifier가 고정되고 UTType.json에 conform한다.
    func testContentTabDragContentTypeUsesExportedJSONContract() throws {
        XCTAssertEqual(
            ContentTabDragPayload.contentType.identifier,
            "com.voyager.app.content-tab-drag-payload",
        )

        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = packageRoot.appendingPathComponent(
            "Sources/VoyagerPagesFileManager/Sidebar/Model/ContentTabMove.swift",
        )
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("conformingTo: .json"))
    }

    /// FMW-001-move_content_tab_to_window: native drag writer는 generalized reorder와 cross-window move payload를 함께 광고한다.
    /// phase의 top-navigation reorder와 VOY-450 cross-window move가 하나의 AppKit drag session을 공유하는 계약을 검증한다.
    /// - 검증 내용: combined/reorder-only writable type과 두 JSON payload identity, local token ownership.
    /// - 사전 조건: 고정 reorder scope와 cross-window locator, Sidebar-local session store가 있다.
    /// - 기대 결과: Content Tab source는 세 type을, Location source는 reorder type만 광고한다.
    func testContentTabNativeDragWriterCombinesReorderAndCrossWindowMovePayloads() throws {
        let sourceWindowID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000356"))
        let tabID = ContentTabID(rawValue: "combined-drag-tab")
        let reorderPayload = try FileManagerTopNavigationReorderDragPayload(
            sourceID: .contentTab(tabID),
            dragScopeID: FileManagerTopNavigationReorderDragScopeID(
                rawValue: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000357")),
            ),
        )
        let movePayload = ContentTabDragPayload(
            schemaVersion: ContentTabDragPayload.supportedSchemaVersion,
            sourceWindowID: sourceWindowID,
            tabID: tabID,
        )
        let sessionStore = FileManagerTopNavigationReorderLocalSessionStore(nowNanoseconds: { 100 })
        let pasteboard = NSPasteboard(name: .init("fm.voyager.tests.combined-content-tab-drag"))
        defer { pasteboard.clearContents() }

        let combinedWriter = try FileManagerTopNavigationReorderPasteboardWriter(
            configuration: .init(
                payload: reorderPayload,
                sessionStore: sessionStore,
                movePayload: movePayload,
            ),
        )
        defer { combinedWriter.cleanupOwnedToken() }
        let expectedTypes: Set<NSPasteboard.PasteboardType> = [
            .fileManagerTopNavigationReorder,
            .fileManagerTopNavigationReorderLocal,
            .contentTabMove,
        ]
        XCTAssertEqual(Set(combinedWriter.writableTypes(for: pasteboard)), expectedTypes)
        let reorderData = try XCTUnwrap(combinedWriter.pasteboardPropertyList(
            forType: NSPasteboard.PasteboardType.fileManagerTopNavigationReorder,
        ) as? Data)
        let moveData = try XCTUnwrap(combinedWriter.pasteboardPropertyList(
            forType: NSPasteboard.PasteboardType.contentTabMove,
        ) as? Data)
        XCTAssertEqual(
            try JSONDecoder().decode(FileManagerTopNavigationReorderDragPayload.self, from: reorderData),
            reorderPayload,
        )
        XCTAssertEqual(try JSONDecoder().decode(ContentTabDragPayload.self, from: moveData), movePayload)

        let locationPayload = try FileManagerTopNavigationReorderDragPayload(
            sourceID: .location("home"),
            dragScopeID: FileManagerTopNavigationReorderDragScopeID(
                rawValue: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000360")),
                boundaryOwner: .topNavigation,
            ),
        )
        let reorderOnlyWriter = try FileManagerTopNavigationReorderPasteboardWriter(
            configuration: .init(payload: locationPayload, sessionStore: sessionStore),
        )
        defer { reorderOnlyWriter.cleanupOwnedToken() }
        XCTAssertEqual(
            Set(reorderOnlyWriter.writableTypes(for: pasteboard)),
            Set<NSPasteboard.PasteboardType>([
                .fileManagerTopNavigationReorder,
                .fileManagerTopNavigationReorderLocal,
            ]),
        )
    }

    /// FMW-001-move_content_tab_to_window: foreign-window combined drag는 same-window reorder slot이 가로채지 않는다.
    /// generalized reorder payload의 scope를 preview하여 target window의 viewport drop handler에 cross-window payload를 위임한다.
    /// - 검증 내용: same scope move 승인과 foreign scope 거부, move UTI가 reorder shape 검증을 깨지 않음.
    /// - 사전 조건: 동일 type set을 가진 same/foreign scope payload가 있다.
    /// - 기대 결과: same scope만 reorder boundary를 활성화하고 foreign scope는 빈 operation을 반환한다.
    func testContentTabReorderDestinationRejectsForeignCombinedDragScope() throws {
        let localScope = try FileManagerTopNavigationReorderDragScopeID(
            rawValue: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000358")),
        )
        let foreignScope = try FileManagerTopNavigationReorderDragScopeID(
            rawValue: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000359")),
        )
        let sourceID = FileManagerTopNavigationItemID.contentTab(.init(rawValue: "source"))
        let targetID = FileManagerTopNavigationItemID.contentTab(.init(rawValue: "target"))
        var activeBoundaryID: Int?
        let sessionStore = FileManagerTopNavigationReorderLocalSessionStore(nowNanoseconds: { 100 })
        let localPayload = FileManagerTopNavigationReorderDragPayload(
            sourceID: sourceID,
            dragScopeID: localScope,
        )
        let foreignPayload = FileManagerTopNavigationReorderDragPayload(
            sourceID: sourceID,
            dragScopeID: foreignScope,
        )
        sessionStore.begin(payload: localPayload)
        let view = FileManagerTopNavigationReorderDropDestinationView(configuration: .init(
            activeBoundaryID: Binding(
                get: { activeBoundaryID },
                set: { activeBoundaryID = $0 },
            ),
            boundary: .init(
                id: 1,
                owner: .unpinnedContentTabs,
                anchorID: targetID,
                placement: .before,
            ),
            dragScopeID: localScope,
            sessionStore: sessionStore,
            boundaryOwnerForItem: { _ in .unpinnedContentTabs },
            onReorder: { _ in },
            onDropValidationCompleted: { _ in },
        ))
        let types: Set<NSPasteboard.PasteboardType> = [
            .fileManagerTopNavigationReorder,
            .fileManagerTopNavigationReorderLocal,
            .contentTabMove,
        ]
        func item(payload: FileManagerTopNavigationReorderDragPayload) throws
            -> FileManagerTopNavigationReorderPasteboardItem
        {
            let data = try JSONEncoder().encode(payload)
            return FileManagerTopNavigationReorderPasteboardItem(types: types) { type in
                type == .fileManagerTopNavigationReorder ? data : nil
            }
        }

        XCTAssertEqual(try view.draggingEntered(pasteboardItems: [item(payload: localPayload)]), .move)
        XCTAssertEqual(activeBoundaryID, 1)
        view.draggingExited()
        sessionStore.begin(payload: foreignPayload)
        XCTAssertEqual(try view.draggingEntered(pasteboardItems: [item(payload: foreignPayload)]), [])
        XCTAssertNil(activeBoundaryID)
    }

    /// FMW-001-move_content_tab_to_window: target Sidebar는 unsupported/no-current/self/pending drop을 위임하지 않는다.
    /// decoded locator를 source-owned move pipeline에 넣기 전 target-local guard가 fail-safe인지 검증한다.
    /// - 검증 내용: 네 invalid state에서 state mutation과 delegate action이 모두 없다.
    /// - 사전 조건: unsupported payload, currentWindowID 없음, self payload, 기존 pending request를 각각 구성한다.
    /// - 기대 결과: 모든 action이 no-op으로 끝난다.
    func testContentTabDropRejectsUnsupportedMissingCurrentSelfAndPending() async throws {
        let sourceWindowID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000352"))
        let targetWindowID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000353"))
        let tabID = ContentTabID(rawValue: "drag-rejection-tab")
        let validPayload = ContentTabDragPayload(
            schemaVersion: ContentTabDragPayload.supportedSchemaVersion,
            sourceWindowID: sourceWindowID,
            tabID: tabID,
        )
        let unsupportedPayload = ContentTabDragPayload(
            schemaVersion: ContentTabDragPayload.supportedSchemaVersion + 1,
            sourceWindowID: sourceWindowID,
            tabID: tabID,
        )

        func assertRejected(
            _ payload: ContentTabDragPayload,
            state: FileManagerSidebarState,
        ) async {
            let store = TestStore(initialState: state) {
                FileManagerSidebarFeature()
            }
            await store.send(.view(.receiveContentTabDrag(payload)))
            await store.finish()
        }

        var unsupportedState = FileManagerSidebarState()
        unsupportedState.currentWindowID = targetWindowID
        await assertRejected(unsupportedPayload, state: unsupportedState)

        await assertRejected(validPayload, state: FileManagerSidebarState())

        var selfDropState = FileManagerSidebarState()
        selfDropState.currentWindowID = sourceWindowID
        await assertRejected(validPayload, state: selfDropState)

        var pendingState = FileManagerSidebarState()
        pendingState.currentWindowID = targetWindowID
        pendingState.pendingContentTabMoveRequest = ContentTabMoveRequest(
            requestID: UUID(),
            sourceWindowID: targetWindowID,
            tabID: ContentTabID(rawValue: "other-pending-tab"),
            targetWindowID: sourceWindowID,
        )
        await assertRejected(validPayload, state: pendingState)
    }

    /// FMW-001-move_content_tab_to_window: valid drop locator는 Sidebar와 FileManager delegate를 그대로 통과한다.
    /// target 계층이 request UUID나 target ID를 만들지 않고 untrusted locator를 상위 manager로 전달하는지 검증한다.
    /// - 검증 내용: Sidebar delegate와 FileManagerWindow delegate의 payload identity.
    /// - 사전 조건: source와 다른 current target window, 지원 schema payload, pending 없음.
    /// - 기대 결과: 두 delegate가 입력 payload와 정확히 같은 값을 한 번씩 방출한다.
    func testContentTabDropRoutesPayloadUnchangedThroughSidebarAndWindowDelegates() async throws {
        let sourceWindowID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000354"))
        let targetWindowID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000355"))
        let payload = ContentTabDragPayload(
            schemaVersion: ContentTabDragPayload.supportedSchemaVersion,
            sourceWindowID: sourceWindowID,
            tabID: ContentTabID(rawValue: "drag-routing-tab"),
        )
        var state = FileManagerWindowState()
        state.sidebar.currentWindowID = targetWindowID
        let store = TestStore(initialState: state) {
            FileManagerFeature()
        }

        await store.send(.sidebar(.view(.receiveContentTabDrag(payload))))
        await store.receive(\.sidebar.delegate.receiveContentTabDrag, payload)
        await store.receive(\.delegate.receiveContentTabDrag, payload)
        await store.finish()
    }

    /// FMW-001-move_content_tab_to_window: Sidebar source는 row drag와 move drop wiring을 함께 보존한다.
    /// source-level UI inspection 관례로 typed payload, move proposal, stable identifier와 menu fallback을 고정한다.
    /// - 검증 내용: conditional draggable, viewport onDrop, move/forbidden proposal, typed loadTransferable, 기존 menu/IDs.
    /// - 사전 조건: package checkout의 canonical SidebarView.swift source를 읽을 수 있다.
    /// - 기대 결과: move cursor용 DropDelegate wiring과 기존 Move to Window menu/pending control이 함께 유지된다.
    func testContentTabDragDropSidebarViewWiringPreservesMoveMenu() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = packageRoot.appendingPathComponent(
            "Sources/VoyagerPagesFileManager/Sidebar/Ui/SidebarView.swift",
        )
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("sidebarStore.pendingContentTabMoveRequest == nil"))
        XCTAssertTrue(source.contains("FileManagerTopNavigationReorderDragSourceConfiguration("))
        XCTAssertTrue(source.contains("movePayload: ContentTabDragPayload("))
        XCTAssertTrue(source.contains("private var contentTabsViewport: some View"))
        XCTAssertTrue(source.contains("GeometryReader"))
        XCTAssertTrue(source.contains("minHeight: proxy.size.height"))
        XCTAssertTrue(source.contains(".onDrop("))
        XCTAssertTrue(source.contains("of: [ContentTabDragPayload.contentType]"))
        XCTAssertTrue(source.contains("hasItemsConforming(to: [ContentTabDragPayload.contentType])"))
        XCTAssertTrue(source.contains("DropProposal(operation: .move)"))
        XCTAssertTrue(source.contains("DropProposal(operation: .forbidden)"))
        XCTAssertTrue(source.contains("loadTransferable(type: ContentTabDragPayload.self)"))
        XCTAssertFalse(source.contains(".dropDestination(for: ContentTabDragPayload.self)"))
        XCTAssertTrue(source.contains("ContentTabMoveProjection.dropZoneIdentifier"))
        XCTAssertEqual(ContentTabMoveProjection.dropZoneIdentifier, "content-tabs-drop-zone")
        XCTAssertTrue(source.contains(#"NSMenuItem(title: "Move to Window""#))
        XCTAssertTrue(source.contains("ContentTabMoveProjection.menuIdentifier(tabID: moveTargetsTabID)"))
        XCTAssertTrue(source.contains("ContentTabMoveProjection.targetIdentifier("))
        XCTAssertTrue(source.contains("ContentTabMoveProjection.progressIdentifier(tabID: item.id)"))
        XCTAssertTrue(source.contains("moveItem.isEnabled = !isMovePending"))
        XCTAssertTrue(source.contains("targetItem.isEnabled = !isMovePending"))
    }
}

private func makeContentTabMoveRequest() throws -> ContentTabMoveRequest {
    try ContentTabMoveRequest(
        requestID: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000340")),
        sourceWindowID: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000341")),
        tabID: ContentTabID(rawValue: "pending-tab"),
        targetWindowID: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000342")),
    )
}
