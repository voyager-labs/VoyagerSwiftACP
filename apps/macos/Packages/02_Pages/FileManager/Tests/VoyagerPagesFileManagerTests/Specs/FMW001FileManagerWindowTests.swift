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

    /// FMW-001-request_undo: Window responder와 EntryOperations는 서로 다른 UndoManager를 사용한다.
    /// responder에 더 늦게 등록된 foreign action이 Window Entry undo의 native top이 될 수 없는지 검증한다.
    /// - 검증 내용: manager identity 분리, Entry A undo 성공, foreign B 미호출과 responder history 보존
    /// - 사전 조건: Entry manager에 A를 등록한 뒤 responder manager에 B를 등록한다.
    /// - 기대 결과: Window Entry undo는 A만 실행하고 B는 responder manager에 남는다.
    func testEntryUndoManager_isolatedFromForeignResponderAction() async throws {
        let entryOperationsUndoManager = UndoManager()
        let windowID = UUID()
        let client = UndoManagerClient.live(undoManager: entryOperationsUndoManager)
        let coordinator = makeCoordinator(
            windowID: windowID,
            entryOperationsUndoManager: entryOperationsUndoManager,
            undoManagerClient: client,
        )
        let window = try XCTUnwrap(coordinator.window)
        let responderUndoManager = try XCTUnwrap(coordinator.windowWillReturnUndoManager(window))
        XCTAssertFalse(entryOperationsUndoManager === responderUndoManager)

        let ownerID = UUID()
        let record = EntryActionRecord(
            operationKind: .rename,
            targets: [.init(beforePath: "/entry/old", afterPath: "/entry/new")],
        )
        let expectedTarget = UndoManagerRecordIdentity(ownerID: ownerID, recordID: record.id)
        await client.registerUndo(windowID, ownerID, record)

        let foreignTarget = ForeignUndoTarget()
        responderUndoManager.registerUndo(withTarget: foreignTarget) { target in
            target.invocationCount += 1
        }

        let result = await client.undo(windowID, expectedTarget: expectedTarget)

        XCTAssertTrue(result.didInvoke)
        XCTAssertEqual(result.availability.redoTarget, expectedTarget)
        XCTAssertEqual(foreignTarget.invocationCount, 0)
        XCTAssertTrue(responderUndoManager.canUndo)
        XCTAssertTrue(entryOperationsUndoManager.canRedo)
        _ = await client.invalidateWindow(windowID)
    }

    /// FMW-001-request_undo: 등록되지 않은 Window ID의 Entry manager resolver는 fail-closed 처리한다.
    /// native key window나 first responder manager로 fallback하지 않는 factory 계약을 검증한다.
    /// - 검증 내용: undo/redo 모두 didInvoke=false이고 availability가 비어 있다.
    /// - 사전 조건: registry에 존재하지 않는 임의 Window ID와 expected target
    /// - 기대 결과: 어떤 native manager도 호출하지 않고 no-op으로 종료한다.
    func testFileManagerUndoManagerClient_missingWindowResolverIsNoOp() async {
        let client = makeFileManagerUndoManagerClientLive()
        let missingWindowID = UUID()
        let target = UndoManagerRecordIdentity(ownerID: UUID(), recordID: UUID())

        let undoResult = await client.undo(missingWindowID, expectedTarget: target)
        let redoResult = await client.redo(missingWindowID, expectedTarget: target)
        let availability = await client.availability(missingWindowID)

        XCTAssertFalse(undoResult.didInvoke)
        XCTAssertFalse(redoResult.didInvoke)
        XCTAssertEqual(undoResult.availability, .init())
        XCTAssertEqual(redoResult.availability, .init())
        XCTAssertEqual(availability, .init())
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
        entryOperationsUndoManager: UndoManager,
        undoManagerClient: UndoManagerClient,
    ) -> FileManagerWindowCoordinator {
        let store = Store(initialState: FileManagerFeature.State()) {
            FileManagerFeature()
        } withDependencies: {
            $0.undoManagerClient = undoManagerClient
        }
        return FileManagerWindowCoordinator(
            windowID: windowID,
            store: store,
            entryOperationsUndoManager: entryOperationsUndoManager,
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
