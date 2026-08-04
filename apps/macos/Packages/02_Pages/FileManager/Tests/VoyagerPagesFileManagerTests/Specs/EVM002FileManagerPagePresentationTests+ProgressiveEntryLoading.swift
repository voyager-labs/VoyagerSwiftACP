import AppKit
import ComposableArchitecture
import VoyagerEntitiesEntry
@testable import VoyagerPagesFileManager
@testable import VoyagerWidgetsEntryViewLayout
import XCTest

@MainActor
extension EVM002FileManagerPagePresentationTests {
    // MARK: - EVM-002-progressive_entry_loading

    /// EVM-002-progressive_entry_loading: 일반 디렉터리 첫 로드는 list outline projection revision을 갱신한다.
    /// hierarchy list가 이미 빈 revision을 렌더한 뒤 entries가 도착해도 새 projection을 적용할 수 있어야 한다.
    /// - 검증 내용: itemsLoaded 동기화가 entries를 갱신하고 hierarchy selection reconciliation을 전달한다.
    /// - 사전 조건: list mode와 hierarchy root가 활성화된 빈 일반 디렉터리
    /// - 기대 결과: loaded entry가 표시 상태에 반영되고 outlineProjectionRevision과 AppKit row가 갱신된다.
    func testOrdinaryListLoadAdvancesOutlineProjectionRevision() async {
        let rootPath = "/root"
        let entry = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        var state = FileManagerContentState()
        state.navigation.seedInitialFolderPath(rootPath)
        state.entryViewLayout.mode = .list
        state.entryViewLayout.hierarchy.replaceRoot(path: rootPath)
        let initialRevision = state.entryViewLayout.outlineProjectionRevision
        let store = Store(initialState: state) {
            FileManagerContentFeature()
        }
        let coordinator = EntryListCoordinator(store: store.scope(
            state: \.entryViewLayout,
            action: \.entryViewLayout,
        ))
        let view = EntryListView(frame: .zero)
        coordinator.bind(to: view)

        store.send(.entryOperations(.loading(.itemsLoaded([entry]))))
        let renderSettled = expectation(description: "ordinary list render settled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            renderSettled.fulfill()
        }
        await fulfillment(of: [renderSettled], timeout: 1)

        store.withState {
            XCTAssertEqual($0.entryViewLayout.entries.map(\.id), [entry.id])
            XCTAssertGreaterThan($0.entryViewLayout.outlineProjectionRevision, initialRevision)
        }
        XCTAssertEqual(view.tableView.numberOfRows, 1)
    }

    /// EVM-002-toggle_directory_expansion_in_list: File Manager composition이 disclosure child stream을 실제 outline row로
    /// 반영한다.
    /// package reducer 상태가 아니라 scoped coordinator와 parent bridge를 함께 실행해 사용자가 보는 행 변화를 검증한다.
    /// - 검증 내용: NSOutlineView expand callback → staged child load → folderChildrenResponse → row graph → collapse
    /// callback 전체 경로
    /// - 사전 조건: `/root` list에 collapsed `/root/folder`가 있고 child stream은 `/root/folder/child`를 반환한다.
    /// - 기대 결과: expand 후 두 행, collapse 후 한 행이며 child는 parent 아래에 표시된다.
    func testFolderDisclosureLoadsAndCollapsesRowsThroughFileManagerComposition() async throws {
        let rootPath = "/root"
        let folder = EntryModel.temporaryFolder(id: "/root/folder", name: "folder")
        let child = EntryModel.temporaryFolder(id: "/root/folder/child", name: "child")
        var state = FileManagerContentState()
        state.navigation.seedInitialFolderPath(rootPath)
        state.entryOperations.items = [folder]
        state.entryViewLayout.entries = [folder]
        state.entryViewLayout.mode = .list
        state.entryViewLayout.hierarchy.replaceRoot(path: rootPath)
        let store = Store(initialState: state) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.entryLoadingClient.stagedLoadItems = { url, _, _ in
                XCTAssertEqual(url.path, folder.fullPath)
                return AsyncThrowingStream { continuation in
                    continuation.yield(.coreBatch(items: [child], batchIndex: 0))
                    continuation.yield(.coreFinished(batchCount: 1))
                    continuation.finish()
                }
            }
        }
        let coordinator = EntryListCoordinator(store: store.scope(
            state: \.entryViewLayout,
            action: \.entryViewLayout,
        ))
        let view = EntryListView(frame: .zero)
        coordinator.bind(to: view)
        let folderItem = try XCTUnwrap(view.tableView.item(atRow: 0) as? EntryListOutlineItem)
        XCTAssertEqual(view.tableView.outlineTableColumn?.identifier.rawValue, EntryListColumn.name.rawValue)
        XCTAssertTrue(view.tableView.isExpandable(folderItem))
        XCTAssertFalse(view.tableView.frameOfOutlineCell(atRow: 0).isEmpty)

        coordinator.outlineViewItemDidExpand(Notification(
            name: NSOutlineView.itemDidExpandNotification,
            object: view.tableView,
            userInfo: ["NSObject": folderItem],
        ))
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(view.tableView.numberOfRows, 2)
        XCTAssertEqual(outlineEntryIDs(in: view.tableView), [folder.id, child.id])

        let expandedFolderItem = try XCTUnwrap(coordinator.entryItemById[folder.id])
        coordinator.outlineViewItemDidCollapse(Notification(
            name: NSOutlineView.itemDidCollapseNotification,
            object: view.tableView,
            userInfo: ["NSObject": expandedFolderItem],
        ))
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(view.tableView.numberOfRows, 1)
    }

    /// EVM-002-update_entry_selection: expanded child row의 AppKit 선택은 FileManager content state에 유지된다.
    /// 마우스 또는 native 상하 방향키가 NSOutlineView selection을 바꾼 뒤 root-only 동기화가 child ID를 지우지 않는지 검증한다.
    /// - 검증 내용: coordinator selection callback과 FileManagerContentFeature 전체 sync chain
    /// - 사전 조건: /root/folder 아래 /root/folder/child가 보이는 expanded list projection
    /// - 기대 결과: child row 선택 뒤 selectedIds, lastSelectedId, rangeAnchorId가 child ID를 유지한다.
    func testExpandedChildRowSelectionSurvivesFileManagerSynchronization() async {
        let rootPath = "/root"
        let folder = EntryModel.temporaryFolder(id: "/root/folder", name: "folder")
        let child = EntryModel.temporaryFolder(id: "/root/folder/child", name: "child")
        var state = FileManagerContentState()
        state.navigation.seedInitialFolderPath(rootPath)
        state.entryOperations.items = [folder]
        state.entryViewLayout.entries = [folder]
        state.entryViewLayout.hierarchy = .init(
            rootPath: rootPath,
            expandedFolderIDs: [folder.id],
            foldersByID: [folder.id: .init(children: [child], phase: .loaded, generation: 1)],
        )
        let store = Store(initialState: state) {
            FileManagerContentFeature()
        }
        let coordinator = EntryListCoordinator(store: store.scope(
            state: \.entryViewLayout,
            action: \.entryViewLayout,
        ))
        let view = EntryListView(frame: .zero)
        coordinator.bind(to: view)
        XCTAssertEqual(view.tableView.numberOfRows, 2)

        view.tableView.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        coordinator.outlineViewSelectionDidChange(Notification(name: NSOutlineView.selectionDidChangeNotification))
        let selectionSettled = expectation(description: "nested selection settled")
        DispatchQueue.main.async {
            selectionSettled.fulfill()
        }
        await fulfillment(of: [selectionSettled], timeout: 1)

        store.withState {
            XCTAssertEqual($0.entryViewLayout.selectedIds, [child.id])
            XCTAssertEqual($0.entryViewLayout.lastSelectedId, child.id)
            XCTAssertEqual($0.entryViewLayout.rangeAnchorId, child.id)
        }
    }

    /// EVM-002-update_entry_selection: key-command overlay의 아래 방향키는 expanded child 선택을 유지한다.
    /// 전체 FileManager effect chain이 root 다음 visible child를 선택한 뒤 다시 빈 selection으로 덮지 않는지 검증한다.
    /// - 검증 내용: handleKeyCommand → applySelectionOffset → selectionChanged → outline selection 동기화
    /// - 사전 조건: root folder가 선택돼 있고 child row가 펼쳐진 두 번째 visible row다.
    /// - 기대 결과: content state와 NSOutlineView가 모두 child를 선택한다.
    func testGlobalDownArrowKeepsExpandedChildSelected() async {
        let folder = EntryModel.temporaryFolder(id: "/root/folder", name: "folder")
        let child = EntryModel.temporaryFolder(id: "/root/folder/child", name: "child")
        let store = Store(initialState: nestedSelectionState(folder: folder, child: child)) {
            FileManagerContentFeature()
        }
        let coordinator = EntryListCoordinator(store: store.scope(
            state: \.entryViewLayout,
            action: \.entryViewLayout,
        ))
        let view = EntryListView(frame: .zero)
        coordinator.bind(to: view)

        store.send(.view(.handleKeyCommand(.init(
            keyCode: 125,
            modifiers: [],
            characters: nil,
            charactersIgnoringModifiers: nil,
        ))))
        await waitForNestedSelectionRender()

        store.withState {
            XCTAssertEqual($0.entryViewLayout.selectedIds, [child.id])
            XCTAssertEqual($0.entryViewLayout.lastSelectedId, child.id)
        }
        XCTAssertEqual(view.tableView.selectedRowIndexes, IndexSet(integer: 1))
    }

    /// EVM-002-update_entry_selection: NSOutlineView의 native 아래 방향키는 expanded child 선택을 유지한다.
    /// 마우스로 outline에 focus한 뒤 native keyDown이 child row를 선택하고 store projection이 같은 행을 유지하는지 검증한다.
    /// - 검증 내용: EntryListTableView.keyDown → outline selection callback → FileManager sync → selected row
    /// - 사전 조건: root row가 선택돼 있고 바로 다음 row가 expanded child다.
    /// - 기대 결과: content state와 NSOutlineView가 모두 child를 선택한다.
    func testNativeDownArrowKeepsExpandedChildSelected() async throws {
        let folder = EntryModel.temporaryFolder(id: "/root/folder", name: "folder")
        let child = EntryModel.temporaryFolder(id: "/root/folder/child", name: "child")
        let store = Store(initialState: nestedSelectionState(folder: folder, child: child)) {
            FileManagerContentFeature()
        }
        let coordinator = EntryListCoordinator(store: store.scope(
            state: \.entryViewLayout,
            action: \.entryViewLayout,
        ))
        let view = EntryListView(frame: .zero)
        coordinator.bind(to: view)
        XCTAssertEqual(view.tableView.selectedRowIndexes, IndexSet(integer: 0))
        let event = try XCTUnwrap(try NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: String(Character(XCTUnwrap(UnicodeScalar(NSDownArrowFunctionKey)))),
            charactersIgnoringModifiers: String(Character(XCTUnwrap(UnicodeScalar(NSDownArrowFunctionKey)))),
            isARepeat: false,
            keyCode: 125,
        ))

        view.tableView.keyDown(with: event)
        await waitForNestedSelectionRender()

        store.withState {
            XCTAssertEqual($0.entryViewLayout.selectedIds, [child.id])
            XCTAssertEqual($0.entryViewLayout.lastSelectedId, child.id)
        }
        XCTAssertEqual(view.tableView.selectedRowIndexes, IndexSet(integer: 1))
    }

    /// EVM-002-progressive_entry_loading: 첫 core batch 뒤에는 모든 source가 interactive entries 정책으로 전환된다.
    /// ordinary directory와 saved collection이 first-batch 완료 후 뒤따르는 batch나 metadata 동안 추가 진행 UI 없이 기존 엔트리 조작을 허용한다.
    /// - 검증 내용: source-owned loading flags가 해제된 다음 `.entries`의 hit testing, accessibility, keyboard dispatch 정책
    /// - 사전 조건: ordinary directory 또는 collection의 first core batch가 적용되어 blocking/replacement flags가 false
    /// - 기대 결과: 두 source 모두 `.entries`이며 entry interaction과 keyboard dispatch가 가능하고 accessibility에서 숨겨지지 않는다.
    func testFirstBatchCompletionMakesOrdinaryAndCollectionEntriesInteractive() {
        let policies = [
            ContentPagePresentationPolicy.resolve(
                isCollectionSearching: false,
                isCollectionContentLoading: false,
                isEntryLoading: false,
                isCollectionMode: false,
            ),
            ContentPagePresentationPolicy.resolve(
                isCollectionSearching: false,
                isCollectionContentLoading: false,
                isEntryLoading: false,
                isCollectionMode: true,
            ),
        ]

        for policy in policies {
            XCTAssertEqual(policy, .entries)
            XCTAssertFalse(policy.replacesEntriesWithLoading)
            XCTAssertFalse(policy.showsInputBlocker)
            XCTAssertTrue(policy.allowsEntryInteraction)
            XCTAssertFalse(policy.hidesEntriesFromAccessibility)
            XCTAssertTrue(policy.allowsKeyboardCommandDispatch)
        }
    }

    /// EVM-002-progressive_entry_loading: host preset은 성공과 부분 실패 progressive QA 축을 제공한다.
    /// FileManagerHost가 기본/session-lapse preset을 유지한 채 deterministic progressive-entry-loading 시나리오를 선택할 수 있어야 한다.
    /// - 검증 내용: named preset 목록과 scenario mapping의 progressive loading 축
    /// - 사전 조건: FileManagerHostPreset의 전체 preset 조합
    /// - 기대 결과: success/failure preset이 모두 존재하고 각각 success 및 partial-failure scenario로 해석된다.
    func testProgressiveHostPresetsExposeSuccessAndPartialFailureScenarios() {
        XCTAssertEqual(
            Set(FileManagerHostPreset.allCases.map(\.rawValue)),
            [
                "default",
                "session-lapse-guard",
                "session-lapse-sign-in-failed",
                "progressive-entry-loading",
                "progressive-entry-loading-failure",
            ],
        )
        XCTAssertEqual(FileManagerHostPreset.default.scenario.sessionLapse, .none)
        XCTAssertEqual(FileManagerHostPreset.sessionLapseGuard.scenario.sessionLapse, .active)
        XCTAssertEqual(FileManagerHostPreset.sessionLapseSignInFailed.scenario.sessionLapse, .signInFailed)
        XCTAssertEqual(FileManagerHostPreset.progressiveEntryLoading.scenario.progressiveEntryLoading, .success)
        XCTAssertEqual(
            FileManagerHostPreset.progressiveEntryLoadingFailure.scenario.progressiveEntryLoading,
            .partialFailure,
        )
    }

    private func nestedSelectionState(
        folder: EntryModel,
        child: EntryModel,
    ) -> FileManagerContentState {
        var state = FileManagerContentState()
        state.navigation.seedInitialFolderPath("/root")
        state.entryOperations.items = [folder]
        state.entryViewLayout.entries = [folder]
        state.entryViewLayout.selectedIds = [folder.id]
        state.entryViewLayout.lastSelectedId = folder.id
        state.entryViewLayout.rangeAnchorId = folder.id
        state.entryViewLayout.hierarchy = .init(
            rootPath: "/root",
            expandedFolderIDs: [folder.id],
            foldersByID: [folder.id: .init(children: [child], phase: .loaded, generation: 1)],
        )
        return state
    }

    private func waitForNestedSelectionRender() async {
        let renderSettled = expectation(description: "nested selection render settled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            renderSettled.fulfill()
        }
        await fulfillment(of: [renderSettled], timeout: 1)
    }

    private func outlineEntryIDs(in tableView: NSOutlineView) -> [EntryModel.ID] {
        (0 ..< tableView.numberOfRows).compactMap { row in
            guard let item = tableView.item(atRow: row) as? EntryListOutlineItem,
                  case let .entry(entry) = item.kind
            else { return nil }
            return entry.id
        }
    }
}
