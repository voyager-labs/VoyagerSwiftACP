import ComposableArchitecture
import Foundation
import VoyagerEntitiesEntry
@testable import VoyagerWidgetsEntryViewLayout
import XCTest

extension EVM002ManageEntriesViewPresentationTests {
    // MARK: - EVM-002-single_render_transaction_multi_field_projection

    /// EVM-002-single_render_transaction_multi_field_projection: structural projection과 selection, clipboard, rename,
    /// scroll
    /// intent가 실제 render entry point의 한 render에서 최종 상태를 유지한다.
    /// - 검증 내용: processRender의 CATransaction 경로에서 구조 변경 reload 뒤 selection, cut presentation, rename target이 적용되고
    /// scroll intent가 소비된다.
    /// - 사전 조건: 이전 snapshot에는 old entry가 있고 현재 store에는 selected/renaming target과 scroll intent가 있는 새 entry가 있다.
    /// - 기대 결과: table selection은 새 target row를 가리키고 rename target은 유지되며 scroll intent는 reset된다.
    func testSingleRenderProjectionPreservesSelectionRenameAndScrollIntent() throws {
        let oldEntry = EntryModel.temporaryFolder(id: "/root/old", name: "old")
        let targetEntry = EntryModel.temporaryFolder(id: "/root/target", name: "target")
        var previousState = EntryViewLayoutState()
        previousState.entries = [oldEntry]

        var currentState = EntryViewLayoutState()
        currentState.entries = [targetEntry]
        currentState.selectedIds = [targetEntry.id]
        currentState.lastSelectedId = targetEntry.id
        currentState.entryOperations.clipboardItems = [targetEntry.fullPath]
        currentState.entryOperations.clipboardOperation = .cut
        currentState.entryOperations.renamingItemId = targetEntry.id
        currentState.shouldScrollToSelection = true

        let store = Store(initialState: currentState) { EntryViewLayoutFeature() }
        let coordinator = EntryListCoordinator(store: store)
        coordinator.bind(to: EntryListView(frame: .zero))
        coordinator.tableView.deselectAll(nil)
        coordinator.lastRenamingItemId = nil
        coordinator.lastRenderSnapshot = EntryListCoordinatorRenderSnapshot(state: previousState)

        coordinator.processRender(EntryListCoordinatorRenderSnapshot(state: currentState))

        let targetItem = try XCTUnwrap(coordinator.entryItemById[targetEntry.id])
        XCTAssertEqual(coordinator.tableView.row(forItem: targetItem), coordinator.tableView.selectedRow)
        XCTAssertEqual(coordinator.lastRenamingItemId, targetEntry.id)
        XCTAssertFalse(store.state.shouldScrollToSelection)
        XCTAssertTrue(coordinator.makeEntryCellConfiguration(
            entry: targetEntry,
            columnId: EntryListColumn.name.rawValue,
            columnWidth: 200,
            thumbnail: nil,
            isLoadingChildren: false,
        ).context.isCut)
        XCTAssertTrue(coordinator.makeEntryCellConfiguration(
            entry: targetEntry,
            columnId: EntryListColumn.name.rawValue,
            columnWidth: 200,
            thumbnail: nil,
            isLoadingChildren: false,
        ).context.isRenaming)
        XCTAssertEqual(coordinator.lastRenderSnapshot, EntryListCoordinatorRenderSnapshot(state: currentState))
    }

    /// EVM-002-single_render_transaction_multi_field_projection: 구조 변경과 함께 종료된 rename을 coordinator에 반영한다.
    /// retained row의 구조 갱신이 rename 종료 lifecycle을 건너뛰지 않는지 검증한다.
    /// - 검증 내용: processRender의 구조 rebuild 경로가 nil renamingItemId를 list coordinator에 동기화한다.
    /// - 사전 조건: 이전 snapshot의 retained entry가 rename 중이고 현재 snapshot에는 새 entry와 nil rename target이 있다.
    /// - 기대 결과: 구조 갱신 뒤 coordinator의 이전 rename target이 제거된다.
    func testStructuralRenderClearsRenameCoordinatorWhenStateEndsRename() {
        let retainedEntry = EntryModel.temporaryFolder(id: "/root/retained", name: "retained")
        let insertedEntry = EntryModel.temporaryFolder(id: "/root/inserted", name: "inserted")
        var previousState = EntryViewLayoutState()
        previousState.entries = [retainedEntry]
        previousState.entryOperations.renamingItemId = retainedEntry.id

        var currentState = EntryViewLayoutState()
        currentState.entries = [retainedEntry, insertedEntry]

        let store = Store(initialState: currentState) { EntryViewLayoutFeature() }
        let coordinator = EntryListCoordinator(store: store)
        coordinator.bind(to: EntryListView(frame: .zero))
        coordinator.lastRenamingItemId = retainedEntry.id
        coordinator.lastRenderSnapshot = EntryListCoordinatorRenderSnapshot(state: previousState)

        coordinator.processRender(EntryListCoordinatorRenderSnapshot(state: currentState))

        XCTAssertNil(coordinator.lastRenamingItemId)
    }

    // MARK: - EVM-002-toggle_directory_expansion_in_list

    /// EVM-002-toggle_directory_expansion_in_list: stale revision callback은 현재 hierarchy나 selection으로 전달되지 않는다.
    /// - 검증 내용: store revision과 다른 intent를 coordinator가 거부한다.
    /// - 사전 조건: revision 2가 현재 store 상태다.
    /// - 기대 결과: revision 1 expansion은 무시되고 revision 2 expansion만 반영된다.
    func testStaleProjectionIntentIsIgnored() {
        let folder = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        var state = EntryViewLayoutState()
        state.entries = [folder]
        state.hierarchy = .init(rootPath: "/root")
        state.outlineProjectionRevision = 2
        let store = Store(initialState: state) { EntryViewLayoutFeature() }
        let coordinator = EntryListCoordinator(store: store)

        coordinator.sendProjectionIntent(.disclosureExpand(folder.id, revision: 1))
        XCTAssertFalse(store.state.hierarchy.expandedFolderIDs.contains(folder.id))

        coordinator.sendProjectionIntent(.disclosureExpand(folder.id, revision: 2))
        XCTAssertTrue(store.state.hierarchy.expandedFolderIDs.contains(folder.id))
    }

    /// EVM-002-toggle_directory_expansion_in_list: projection 교체는 이전 revision item instance를 재사용하지 않는다.
    /// - 검증 내용: 동일 stable ID라도 revision별 graph item identity가 새로 생성된다.
    /// - 사전 조건: 같은 folder를 포함하는 revision 1과 revision 2 projection이 있다.
    /// - 기대 결과: revision 2 item은 revision 1 item과 동일 ID지만 다른 object identity다.
    func testProjectionReloadRebuildsOutlineItems() {
        let folder = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        let session = EntryListCoordinatorProjectionSession()
        var firstItem: EntryListOutlineItem?

        session.apply(outlineProjection(revision: 1, roots: [folder])) { _, items in
            firstItem = items.first
        }
        session.apply(outlineProjection(revision: 2, roots: [folder])) { _, items in
            XCTAssertEqual(items.first?.id, firstItem?.id)
            XCTAssertNotIdentical(items.first, firstItem)
        }
    }

    /// EVM-002-toggle_directory_expansion_in_list: 같은 revision의 구조 변경도 최신 projection을 적용한다.
    /// 정렬이나 metadata patch가 ID 집합을 유지한 채 sibling 순서만 바꾸는 경계를 검증한다.
    /// - 검증 내용: 동일 revision에서 root order가 바뀐 두 projection이 모두 apply된다.
    /// - 사전 조건: stable ID 두 개의 이름이 바뀌어 name sort 순서가 반전된다.
    /// - 기대 결과: 두 번째 projection의 root order가 perform callback에 전달된다.
    func testSameRevisionStructuralChangeReappliesProjection() {
        let first = EntryModel.temporaryFolder(id: "/root/first", name: "a")
        let second = EntryModel.temporaryFolder(id: "/root/second", name: "b")
        let renamedFirst = EntryModel.temporaryFolder(id: first.id, name: "z")
        let renamedSecond = EntryModel.temporaryFolder(id: second.id, name: "a")
        let session = EntryListCoordinatorProjectionSession()
        var appliedRootIDs: [[EntryListOutlineProjection.ItemID]] = []

        session.apply(outlineProjection(revision: 1, roots: [first, second])) { projection, _ in
            appliedRootIDs.append(projection.rootItemIDs)
        }
        session.apply(outlineProjection(revision: 1, roots: [renamedFirst, renamedSecond])) { projection, _ in
            appliedRootIDs.append(projection.rootItemIDs)
        }

        XCTAssertEqual(appliedRootIDs, [
            [.entry(first.id), .entry(second.id)],
            [.entry(second.id), .entry(first.id)],
        ])
    }

    /// EVM-002-toggle_directory_expansion_in_list: outline view delegate expand는 store에 folderExpansionRequested를 전달한다.
    /// 키보드 right-arrow가 NSOutlineView.expandItem을 호출하고 delegate callback이 coordinator를 통해 store action으로 전달되는 경로를 검증한다.
    /// - 검증 내용: outlineViewItemDidExpand가 hierarchy-enabled entry에서 store에 expansion request를 발생시킨다.
    /// - 사전 조건: /root/a folder가 렌더된 projection revision 1에 있고 hierarchy가 활성화돼 있다.
    /// - 기대 결과: delegate expand 후 store의 expandedFolderIDs에 /root/a가 추가된다.
    func testOutlineExpandDelegateRequestsFolderExpansion() {
        let folder = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        var state = EntryViewLayoutState()
        state.entries = [folder]
        state.hierarchy = .init(rootPath: "/root")
        state.outlineProjectionRevision = 1
        let store = Store(initialState: state) { EntryViewLayoutFeature() }
        let coordinator = EntryListCoordinator(store: store)
        coordinator.bind(to: EntryListView(frame: .zero))
        coordinator.applyStoreProjection(outlineProjection(revision: 1, roots: [folder]))

        guard let item = coordinator.entryItemById[folder.id] else {
            XCTFail("entryItemById should contain the folder after projection apply")
            return
        }
        let notification = Notification(
            name: NSOutlineView.itemDidExpandNotification,
            object: nil,
            userInfo: ["NSObject": item],
        )
        coordinator.outlineViewItemDidExpand(notification)

        XCTAssertTrue(store.state.hierarchy.expandedFolderIDs.contains(folder.id))
    }

    /// EVM-002-toggle_directory_expansion_in_list: 빈 child-list key가 있는 projection은 folder expansion을 적용한다.
    /// - 검증 내용: empty children topology가 incremental row update를 우회하고 full reload의 expansion 동기화를 실행하는지 검증한다.
    /// - 사전 조건: collapsed folder가 렌더된 뒤 해당 folder의 children이 빈 배열인 expanded projection이 도착한다.
    /// - 기대 결과: full reload 후 outline의 folder item이 물리적으로 expanded 상태가 된다.
    func testProjectionWithEmptyChildListKeyAppliesFolderExpansion() throws {
        let folder = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        var state = EntryViewLayoutState()
        state.entries = [folder]
        state.hierarchy = .init(rootPath: "/root")
        state.outlineProjectionRevision = 1
        let store = Store(initialState: state) { EntryViewLayoutFeature() }
        let coordinator = EntryListCoordinator(store: store)
        coordinator.bind(to: EntryListView(frame: .zero))

        coordinator.applyStoreProjection(outlineProjection(revision: 1, roots: [folder]))

        let item = try XCTUnwrap(coordinator.entryItemById[folder.id])
        XCTAssertTrue(coordinator.tableView.isItemExpanded(item))
    }

    /// EVM-002-toggle_directory_expansion_in_list: expanded empty topology에서 root-only projection으로 전환하면 folder를 물리적으로
    /// 접는다.
    /// - 검증 내용: 이전 projection의 children topology가 남아 있으면 새 projection의 visible row 수가 같아도 full reload와 collapse 동기화를
    /// 실행하는지 검증한다.
    /// - 사전 조건: 빈 children key를 가진 expanded folder projection이 적용된 뒤 같은 folder의 collapsed root-only projection이 도착한다.
    /// - 기대 결과: full reload 뒤 새로 reacquire한 outline item이 물리적으로 collapsed 상태다.
    func testExpandedEmptyTopologyCollapsesOnRootOnlyProjection() throws {
        let folder = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        var state = EntryViewLayoutState()
        state.entries = [folder]
        state.hierarchy = .init(rootPath: "/root")
        state.outlineProjectionRevision = 1
        let store = Store(initialState: state) { EntryViewLayoutFeature() }
        let coordinator = EntryListCoordinator(store: store)
        coordinator.bind(to: EntryListView(frame: .zero))

        coordinator.applyStoreProjection(outlineProjection(revision: 1, roots: [folder]))
        let expandedItem = try XCTUnwrap(coordinator.entryItemById[folder.id])
        XCTAssertTrue(coordinator.tableView.isItemExpanded(expandedItem))

        var collapsedHierarchy = EntryListHierarchyState(rootPath: "/root")
        collapsedHierarchy.setExpandedIDs([])
        let collapsedProjection = EntryListOutlineProjection(
            revision: 2,
            rootEntries: [folder],
            hierarchyState: collapsedHierarchy,
            context: .init(mode: .list, isNormalDirectoryPage: true, hasActiveGrouping: false),
            sortKey: .name,
            sortOrder: .ascending,
        )
        coordinator.applyStoreProjection(collapsedProjection)

        let collapsedItem = try XCTUnwrap(coordinator.entryItemById[folder.id])
        XCTAssertFalse(coordinator.tableView.isItemExpanded(collapsedItem))
    }

    /// EVM-002-toggle_directory_expansion_in_list: outline view delegate collapse는 store에 folderCollapseRequested를
    /// 전달한다.
    /// 키보드 left-arrow가 NSOutlineView.collapseItem을 호출하고 delegate callback이 coordinator를 통해 store action으로 전달되는 경로를
    /// 검증한다.
    /// - 검증 내용: outlineViewItemDidCollapse가 hierarchy-enabled entry에서 store에 collapse request를 발생시킨다.
    /// - 사전 조건: /root/a folder가 expanded 상태로 projection revision 1에 렌더돼 있다.
    /// - 기대 결과: delegate collapse 후 store의 expandedFolderIDs에서 /root/a가 제거된다.
    func testOutlineCollapseDelegateRequestsFolderCollapse() {
        let folder = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        var state = EntryViewLayoutState()
        state.entries = [folder]
        state.hierarchy = .init(rootPath: "/root")
        state.hierarchy.setExpandedIDs([folder.id])
        state.outlineProjectionRevision = 1
        let store = Store(initialState: state) { EntryViewLayoutFeature() }
        let coordinator = EntryListCoordinator(store: store)
        coordinator.bind(to: EntryListView(frame: .zero))
        coordinator.applyStoreProjection(outlineProjection(revision: 1, roots: [folder]))

        guard let item = coordinator.entryItemById[folder.id] else {
            XCTFail("entryItemById should contain the folder after projection apply")
            return
        }
        let notification = Notification(
            name: NSOutlineView.itemDidCollapseNotification,
            object: nil,
            userInfo: ["NSObject": item],
        )
        coordinator.outlineViewItemDidCollapse(notification)

        XCTAssertFalse(store.state.hierarchy.expandedFolderIDs.contains(folder.id))
    }

    /// EVM-002-toggle_directory_expansion_in_list: render settle 전 연속 expand/collapse 입력도 순서대로 반영한다.
    /// 사용자가 disclosure를 빠르게 두 번 조작해도 이전 rendered revision gate가 두 번째 입력을 버리지 않는지 검증한다.
    /// - 검증 내용: 같은 outline item의 expand callback 직후 collapse callback이 canonical view action 경계를 통과한다.
    /// - 사전 조건: revision 1의 collapsed folder가 렌더되어 있고 첫 callback 뒤 store revision만 먼저 증가한다.
    /// - 기대 결과: render loop가 새 projection을 적용하기 전에도 최종 hierarchy 상태는 collapsed다.
    func testRapidExpandThenCollapseBeforeRenderSettles() throws {
        let folder = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        var state = EntryViewLayoutState()
        state.entries = [folder]
        state.hierarchy = .init(rootPath: "/root")
        state.outlineProjectionRevision = 1
        let store = Store(initialState: state) { EntryViewLayoutFeature() }
        let coordinator = EntryListCoordinator(store: store)
        coordinator.bind(to: EntryListView(frame: .zero))

        let item = try XCTUnwrap(coordinator.entryItemById[folder.id])
        coordinator.outlineViewItemDidExpand(Notification(
            name: NSOutlineView.itemDidExpandNotification,
            object: nil,
            userInfo: ["NSObject": item],
        ))
        XCTAssertTrue(store.state.hierarchy.expandedFolderIDs.contains(folder.id))

        coordinator.outlineViewItemDidCollapse(Notification(
            name: NSOutlineView.itemDidCollapseNotification,
            object: nil,
            userInfo: ["NSObject": item],
        ))

        XCTAssertFalse(store.state.hierarchy.expandedFolderIDs.contains(folder.id))
    }

    /// EVM-002-toggle_directory_expansion_in_list: list로 시작한 뒤 첫 entries load가 도착하면 초기 rows를 렌더링한다.
    /// 사용자가 list mode로 앱을 열었을 때 첫 store emission과 entry load가 같은 main queue turn에 도착하는 경계를 검증한다.
    /// - 검증 내용: initial bind 직후 entries가 채워져도 coordinator가 첫 populated snapshot을 table rows로 반영한다.
    /// - 사전 조건: list와 collection mode가 활성화된 빈 state에 coordinator를 bind하고 즉시 한 entry를 전달한다.
    /// - 기대 결과: store와 table view 모두 한 entry를 보유하며 list가 빈 상태로 남지 않는다.
    func testListColdStartRendersFirstLoadedEntries() async {
        var state = EntryViewLayoutState()
        state.isCollectionMode = true
        let store = Store(initialState: state) {
            EntryViewLayoutFeature()
        }
        let coordinator = EntryListCoordinator(store: store)
        let view = EntryListView(frame: .zero)
        let entry = EntryModel.temporaryFolder(id: "/root/a", name: "a")

        coordinator.bind(to: view)
        store.send(.internal(.setCollectionItems([entry])))
        let renderSettled = expectation(description: "list render settled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            renderSettled.fulfill()
        }
        await fulfillment(of: [renderSettled], timeout: 1)

        XCTAssertEqual(store.withState { $0.entries.map(\.id) }, [entry.id])
        XCTAssertEqual(view.tableView.numberOfRows, 1)
    }

    /// EVM-002-toggle_directory_expansion_in_list: guarded programmatic apply 중 newest pending revision만 보관한다.
    /// - 검증 내용: reentrant update는 newest revision만 pending slot에 보관한다.
    /// - 사전 조건: revision 1 apply callback 안에서 revision 2와 stale revision 1을 요청한다.
    /// - 기대 결과: apply 중 guard가 활성화되고 종료 뒤 revision 2만 rendered 된다.
    func testProgrammaticApplyKeepsNewestPendingProjection() {
        let folder = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        let session = EntryListCoordinatorProjectionSession()
        var appliedRevisions: [Int] = []

        session.apply(outlineProjection(revision: 1, roots: [folder])) { projection, _ in
            appliedRevisions.append(projection.revision)
            XCTAssertTrue(session.isApplyingStoreProjection)
            session.apply(outlineProjection(revision: 2, roots: [folder])) { pendingProjection, _ in
                appliedRevisions.append(pendingProjection.revision)
            }
            session.apply(outlineProjection(revision: 1, roots: [folder])) { _, _ in
                XCTFail("older projection must not replace the pending revision")
            }
        }

        XCTAssertEqual(appliedRevisions, [1, 2])
        XCTAssertEqual(session.renderedProjectionRevision, 2)
        XCTAssertFalse(session.isApplyingStoreProjection)
        XCTAssertNil(session.pendingProjection)
    }

    // MARK: - EVM-002-flat_projection_session_coalescing

    /// EVM-002-flat_projection_session_coalescing: flat rebuild는 projection session revision을 유지한다.
    /// flat 구조 reload가 session reset을 우회하지 않고 동일한 revision gate를 사용하는지 검증한다.
    /// - 검증 내용: flat coordinator bind가 flat projection을 session에 적용하고 반복 rebuild가 동일 구조를 dedup한다.
    /// - 사전 조건: hierarchy가 비활성화된 list state에 두 root entry가 있다.
    /// - 기대 결과: bind와 반복 rebuild 뒤 rendered revision은 유지되고 두 번째 rebuild는 projection을 교체하지 않는다.
    func testFlatRebuildUsesProjectionSessionRevisionGate() {
        let first = EntryModel.temporaryFolder(id: "/root/first", name: "first")
        let second = EntryModel.temporaryFolder(id: "/root/second", name: "second")
        var state = EntryViewLayoutState()
        state.entries = [first, second]
        let store = Store(initialState: state) { EntryViewLayoutFeature() }
        let coordinator = EntryListCoordinator(store: store)

        coordinator.bind(to: EntryListView(frame: .zero))
        XCTAssertEqual(coordinator.renderedProjectionRevision, 0)
        let firstRenderedItem = coordinator.outlineItems.first

        coordinator.rebuildRowsAndReload()

        XCTAssertEqual(coordinator.renderedProjectionRevision, 0)
        XCTAssertIdentical(coordinator.outlineItems.first, firstRenderedItem)
    }

    /// EVM-002-flat_projection_session_coalescing: flat apply는 newest pending projection의 item payload를 함께 유지한다.
    /// - 검증 내용: flatItems overload의 reentrant apply가 revision 2와 concrete item identity를 보존하고 stale revision callback을
    /// 배제한다.
    /// - 사전 조건: revision 1 callback 중 revision 2 flat projection과 stale revision 1 flat projection이 순서대로 도착한다.
    /// - 기대 결과: callback revision은 [1, 2]이고 revision 2 item만 적용되며 rendered/pending 상태가 정리된다.
    func testFlatApplyKeepsNewestPendingItemsAndIgnoresStaleRevision() {
        let first = EntryModel.temporaryFolder(id: "/root/first", name: "first")
        let second = EntryModel.temporaryFolder(id: "/root/second", name: "second")
        let stale = EntryModel.temporaryFolder(id: "/root/stale", name: "stale")
        let session = EntryListCoordinatorProjectionSession()
        let firstItem = EntryListOutlineItem(kind: .entry(first))
        let secondItem = EntryListOutlineItem(kind: .entry(second))
        let staleItem = EntryListOutlineItem(kind: .entry(stale))
        var appliedRevisions: [Int] = []
        var appliedItemIDs: [[String]] = []

        session.apply(
            outlineProjection(revision: 1, roots: [first]),
            flatItems: [firstItem],
        ) { projection, items in
            appliedRevisions.append(projection.revision)
            appliedItemIDs.append(items.map(\.id))
            XCTAssertTrue(session.isApplyingStoreProjection)

            session.apply(
                outlineProjection(revision: 2, roots: [second]),
                flatItems: [secondItem],
            ) { pendingProjection, pendingItems in
                appliedRevisions.append(pendingProjection.revision)
                appliedItemIDs.append(pendingItems.map(\.id))
                XCTAssertIdentical(pendingItems.first, secondItem)
                XCTAssertEqual(pendingProjection.rootItemIDs, [.entry(second.id)])
            }
            session.apply(
                outlineProjection(revision: 1, roots: [stale]),
                flatItems: [staleItem],
            ) { _, _ in
                XCTFail("stale flat projection must not invoke its callback")
            }
        }

        XCTAssertEqual(appliedRevisions, [1, 2])
        XCTAssertEqual(appliedItemIDs, [[firstItem.id], [secondItem.id]])
        XCTAssertEqual(session.renderedProjectionRevision, 2)
        XCTAssertFalse(session.isApplyingStoreProjection)
        XCTAssertNil(session.pendingProjection)
    }

    /// EVM-002-toggle_directory_expansion_in_list: hierarchy render는 저장된 scroll 위치를 복원한다.
    /// flat render와 동일하게 outline projection 적용 뒤 saved offset restore가 실행되는지 검증한다.
    /// - 검증 내용: hierarchy-enabled initial bind의 scroll restore completion flag
    /// - 사전 조건: root entry와 savedScrollOffset이 있고 hierarchy root context가 활성화돼 있다.
    /// - 기대 결과: coordinator가 hierarchy projection 적용 후 scroll 복원을 완료한다.
    func testHierarchyProjectionRestoresSavedScrollPosition() {
        let folder = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        var state = EntryViewLayoutState()
        state.entries = [folder]
        state.hierarchy = .init(rootPath: "/root")
        state.savedScrollOffset = CGPoint(x: 0, y: 20)
        let coordinator = EntryListCoordinator(store: Store(initialState: state) {
            EntryViewLayoutFeature()
        })
        let view = EntryListView(frame: .zero)

        coordinator.bind(to: view)

        XCTAssertEqual(view.scrollView.contentView.bounds.origin, CGPoint(x: 0, y: 20))
    }

    // MARK: - EVM-002-entry_id_row_anchor_structural_reload

    /// EVM-002-entry_id_row_anchor_structural_reload: 구조 reload 뒤 동일 entry의 화면상 pixel offset을 보존한다.
    /// - 검증 내용: 새 row가 anchor 위에 삽입되어 기존 row index가 변해도 top visible entry ID와 pixel offset을 복원한다.
    /// - 사전 조건: 세 entry를 렌더한 뒤 중간 entry를 top visible anchor로 두고 앞에 새 entry를 삽입한다.
    /// - 기대 결과: 구조 변경 후에도 동일 entry가 같은 pixel offset에 남는다.
    func testStructuralReloadPreservesTopVisibleEntryAnchor() throws {
        let anchor = EntryModel.temporaryFolder(id: "/root/anchor", name: "anchor")
        let last = EntryModel.temporaryFolder(id: "/root/last", name: "last")
        let inserted = EntryModel.temporaryFolder(id: "/root/inserted", name: "inserted")
        var state = EntryViewLayoutState()
        state.entries = [anchor, last]
        state.entryOperations.items = [anchor, last]
        let store = Store(initialState: state) { EntryViewLayoutFeature() }
        let coordinator = EntryListCoordinator(store: store)
        let view = EntryListView(frame: NSRect(x: 0, y: 0, width: 400, height: 20))

        coordinator.bind(to: view)
        view.layoutSubtreeIfNeeded()
        let anchorItem = try XCTUnwrap(coordinator.entryItemById[anchor.id])
        let anchorRow = coordinator.tableView.row(forItem: anchorItem)
        let anchorRect = coordinator.tableView.rect(ofRow: anchorRow)
        coordinator.scrollView.contentView.setBoundsOrigin(NSPoint(x: 0, y: anchorRect.origin.y - 7))
        coordinator.tableView.layoutSubtreeIfNeeded()
        coordinator.tableView.scrollRowToVisible(anchorRow)
        coordinator.scrollView.contentView.setBoundsOrigin(NSPoint(
            x: 0,
            y: coordinator.tableView.rect(ofRow: anchorRow).origin.y - 7,
        ))
        let beforeRows = coordinator.tableView.rows(in: coordinator.scrollView.contentView.bounds)
        let beforeTopItem = try XCTUnwrap(coordinator.tableView
            .item(atRow: beforeRows.location) as? EntryListOutlineItem)
        guard case let .entry(beforeTopEntry) = beforeTopItem.kind else {
            return XCTFail("Top visible item must be an entry")
        }
        let beforeOffset = coordinator.tableView.rect(ofRow: beforeRows.location).origin.y
            - coordinator.scrollView.contentView.bounds.origin.y

        store.send(.internal(.setCollectionItems([anchor, inserted, last])))
        coordinator.processRender(EntryListCoordinatorRenderSnapshot(state: store.state))

        let afterRows = coordinator.tableView.rows(in: coordinator.scrollView.contentView.bounds)
        let afterTopItem = try XCTUnwrap(coordinator.tableView.item(atRow: afterRows.location) as? EntryListOutlineItem)
        guard case let .entry(afterTopEntry) = afterTopItem.kind else {
            return XCTFail("Top visible item must be an entry")
        }
        let afterOffset = coordinator.tableView.rect(ofRow: afterRows.location).origin.y
            - coordinator.scrollView.contentView.bounds.origin.y

        XCTAssertEqual(beforeTopEntry.id, anchor.id)
        XCTAssertEqual(afterTopEntry.id, anchor.id)
        XCTAssertEqual(afterOffset, beforeOffset, accuracy: 1)

        let beforeColumnReload = try XCTUnwrap(topVisibleEntryAndOffset(for: coordinator))
        var previousColumnState = state
        previousColumnState.listVisibleColumns = [.name, .size]
        coordinator.handleVisibleColumnsChange(
            previous: EntryListCoordinatorRenderSnapshot(state: previousColumnState),
            snapshot: EntryListCoordinatorRenderSnapshot(state: state),
        )
        let afterColumnReload = try XCTUnwrap(topVisibleEntryAndOffset(for: coordinator))
        XCTAssertEqual(afterColumnReload.id, beforeColumnReload.id)
        XCTAssertEqual(afterColumnReload.offset, beforeColumnReload.offset, accuracy: 1)

        var metricState = state
        metricState.listIconSize = 40
        metricState.listTextSize = 18
        let beforeMetricReload = try XCTUnwrap(topVisibleEntryAndOffset(for: coordinator))
        coordinator.updateListMetricsIfNeeded(
            previous: EntryListCoordinatorRenderSnapshot(state: state),
            snapshot: EntryListCoordinatorRenderSnapshot(state: metricState),
        )
        let afterMetricReload = try XCTUnwrap(topVisibleEntryAndOffset(for: coordinator))
        XCTAssertEqual(afterMetricReload.id, beforeMetricReload.id)
        XCTAssertEqual(afterMetricReload.offset, beforeMetricReload.offset, accuracy: 1)
    }

    /// EVM-002-entry_id_row_anchor_structural_reload: 제거된 anchor는 남은 첫 row로 안전하게 대체된다.
    /// - 검증 내용: 구조 변경으로 anchor entry가 없어질 때 stale row/item 접근 없이 남은 visible row를 사용한다.
    /// - 사전 조건: anchor가 top visible row이고 structural projection에서 anchor가 제거된다.
    /// - 기대 결과: 남은 entry가 table의 top visible row가 된다.
    func testStructuralReloadFallsBackWhenTopVisibleEntryIsRemoved() throws {
        let anchor = EntryModel.temporaryFolder(id: "/root/anchor", name: "anchor")
        let retained = EntryModel.temporaryFolder(id: "/root/retained", name: "retained")
        var state = EntryViewLayoutState()
        state.entries = [anchor, retained]
        state.hierarchy = .init(rootPath: "/root")
        state.outlineProjectionRevision = 1
        let store = Store(initialState: state) { EntryViewLayoutFeature() }
        let coordinator = EntryListCoordinator(store: store)
        let view = EntryListView(frame: NSRect(x: 0, y: 0, width: 400, height: 20))

        coordinator.bind(to: view)
        view.layoutSubtreeIfNeeded()
        let anchorItem = try XCTUnwrap(coordinator.entryItemById[anchor.id])
        coordinator.tableView.scrollRowToVisible(coordinator.tableView.row(forItem: anchorItem))
        coordinator.applyStoreProjection(outlineProjection(revision: 2, roots: [retained]))

        let rows = coordinator.tableView.rows(in: coordinator.scrollView.contentView.bounds)
        let topItem = try XCTUnwrap(coordinator.tableView.item(atRow: rows.location) as? EntryListOutlineItem)
        guard case let .entry(topEntry) = topItem.kind else {
            return XCTFail("Fallback row must be an entry")
        }
        XCTAssertEqual(topEntry.id, retained.id)
    }

    private func topVisibleEntryAndOffset(
        for coordinator: EntryListCoordinator,
    ) -> (id: EntryModel.ID, offset: CGFloat)? {
        let rows = coordinator.tableView.rows(in: coordinator.scrollView.contentView.bounds)
        guard rows.location != NSNotFound,
              rows.length > 0,
              let item = coordinator.tableView.item(atRow: rows.location) as? EntryListOutlineItem,
              case let .entry(entry) = item.kind
        else {
            return nil
        }
        let offset = coordinator.tableView.rect(ofRow: rows.location).origin.y
            - coordinator.scrollView.contentView.bounds.origin.y
        return (entry.id, offset)
    }

    /// EVM-002-toggle_directory_expansion_in_list: root 삭제는 남은 outline item identity를 보존한다.
    /// - 검증 내용: 이동 완료 후 단순 root 삭제가 전체 graph 교체 없이 기존 row 객체를 유지한다.
    /// - 사전 조건: 두 root entry가 렌더된 hierarchy projection에서 첫 entry만 제거된다.
    /// - 기대 결과: 남은 entry의 coordinator index가 삭제 전과 동일한 outline item을 가리킨다.
    func testRootRemovalPreservesRetainedOutlineItemIdentity() {
        let removed = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        let retained = EntryModel.temporaryFolder(id: "/root/b", name: "b")
        var state = EntryViewLayoutState()
        state.entries = [removed, retained]
        state.entryOperations.items = [removed, retained]
        state.hierarchy = .init(rootPath: "/root")
        state.hierarchy.setExpandedIDs([removed.id, retained.id])
        let coordinator = EntryListCoordinator(store: Store(initialState: state) {
            EntryViewLayoutFeature()
        })
        coordinator.bind(to: EntryListView(frame: .zero))
        let retainedItem = coordinator.entryItemById[retained.id]

        coordinator.applyStoreProjection(outlineProjection(revision: 1, roots: [retained]))

        XCTAssertNotNil(retainedItem)
        XCTAssertIdentical(coordinator.entryItemById[retained.id], retainedItem)
    }

    /// EVM-002-set_entries_view_as_icon_grid: 단순 root 삭제는 grid 전체 section reload를 요구하지 않는다.
    /// - 검증 내용: 이동 완료로 ID 하나만 제거된 snapshot이 incremental removal 경로로 분류된다.
    /// - 사전 조건: 동일한 ungrouped grid에서 [a, b]가 [b]로 바뀐다.
    /// - 기대 결과: coordinator가 전체 section rebuild를 선택하지 않는다.
    func testGridRootRemovalDoesNotRequireFullSectionReload() {
        let removed = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        let retained = EntryModel.temporaryFolder(id: "/root/b", name: "b")
        var previousState = EntryViewLayoutState()
        previousState.isCollectionMode = true
        previousState.entries = [removed, retained]
        let store = Store(initialState: previousState) {
            EntryViewLayoutFeature()
        }
        let coordinator = EntryGridCoordinator(store: store)
        let view = EntryGridView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        coordinator.bind(to: view)
        coordinator.isRenderObservationEnabled = false
        store.send(.internal(.setCollectionItems([retained])))
        let snapshot = EntryGridRenderSnapshot(state: store.state)

        XCTAssertFalse(coordinator.shouldRebuildSections(
            previous: EntryGridRenderSnapshot(state: previousState),
            snapshot: snapshot,
            changes: snapshot.presentation.changes(from: EntryGridRenderSnapshot(state: previousState).presentation),
        ))
        coordinator.handleSnapshotChanges(
            previous: EntryGridRenderSnapshot(state: previousState),
            snapshot: snapshot,
        )
        XCTAssertEqual(coordinator.sections.flatMap(\.items).map(\.id), [retained.id])
        XCTAssertEqual(view.collectionView.numberOfItems(inSection: 0), 1)
    }

    /// EVM-002-set_entries_view_as_icon_grid: payload-only 갱신은 grid section의 entry 모델도 교체한다.
    /// - 검증 내용: 같은 ID의 name 변경이 전체 reload 없이 coordinator section data source에 반영된다.
    /// - 사전 조건: collection mode grid에 old 이름의 entry가 렌더되어 있고 같은 ID의 새 payload가 도착한다.
    /// - 기대 결과: targeted item refresh 뒤 section이 새 이름을 제공한다.
    func testGridPayloadRefreshUpdatesSectionEntry() {
        let original = EntryModel.temporaryFolder(id: "/root/a", name: "old")
        let updated = EntryModel.temporaryFolder(id: original.id, name: "new")
        var state = EntryViewLayoutState()
        state.isCollectionMode = true
        state.entries = [original]
        let store = Store(initialState: state) {
            EntryViewLayoutFeature()
        }
        let coordinator = EntryGridCoordinator(store: store)
        coordinator.bind(to: EntryGridView(frame: NSRect(x: 0, y: 0, width: 320, height: 240)))
        coordinator.isRenderObservationEnabled = false
        let previous = EntryGridRenderSnapshot(state: state)

        store.send(.internal(.setCollectionItems([updated])))
        let snapshot = EntryGridRenderSnapshot(state: store.state)
        coordinator.reloadVisibleItemsForEntryContentChange(
            snapshot: snapshot,
            changes: snapshot.presentation.changes(from: previous.presentation),
        )

        XCTAssertEqual(coordinator.sections.first?.items.first?.name, updated.name)
    }

    /// EVM-002-switch_entries_view: grid와 list는 같은 grouped presentation section을 사용한다.
    /// - 검증 내용: 두 coordinator가 section 순서, 제목, 항목 순서를 공통 projection에서 읽는다.
    /// - 사전 조건: Folders와 Text 두 section이 state에 투영돼 있다.
    /// - 기대 결과: grid section과 list group row가 동일한 두 section을 표현한다.
    func testGridAndListConsumeSharedGroupedSections() {
        let folder = EntryModel.temporaryFolder(id: "/root/folder", name: "folder")
        let file = makePresentationFile(id: "/root/file.txt", name: "file.txt")
        var state = EntryViewLayoutState()
        state.entryArrangements.groupKey = .kind
        state.entries = [folder, file]
        state.entryArrangements.groupedItems = [
            .init(groupName: "Folders", items: [folder]),
            .init(groupName: "Text", items: [file]),
        ]
        let store = Store(initialState: state) { EntryViewLayoutFeature() }
        let grid = EntryGridCoordinator(store: store)
        let list = EntryListCoordinator(store: store)

        let gridSections = grid.makeSections(state: state)
        let listItems = list.makeOutlineItems(state: state)

        XCTAssertEqual(gridSections.compactMap(\.title), ["Folders", "Text"])
        XCTAssertEqual(listItems.compactMap(\.groupName), ["Folders", "Text"])
        XCTAssertEqual(gridSections.flatMap(\.items).map(\.id), [folder.id, file.id])
        XCTAssertEqual(listItems.flatMap { $0.flattenEntries().map(\.0) }, [folder.id, file.id])
    }

    /// EVM-002-switch_entries_view: 빈 groupName 섹션(groupKey .none)은 group header 없이 flat으로 렌더링된다.
    /// - 검증 내용: EntryArrangementsApplyReducer가 groupKey .none일 때 만드는 빈 이름 그룹이
    ///   presentation에서 title nil로 정규화되어 list/grid 모두 group row 없이 entry만 만든다.
    /// - 사전 조건: groupKey가 .none이고 groupedItems가 빈 이름 그룹 하나로 투영됐다 (컬렉션 검색 결과와 동일 구조).
    /// - 기대 결과: grid section title은 nil이고 list outline items는 group row 없이 entry row만 포함한다.
    func testEmptyGroupNameSectionRendersFlatWithoutGroupHeader() {
        let file = makePresentationFile(id: "/root/file.txt", name: "file.txt")
        var state = EntryViewLayoutState()
        state.entryArrangements.groupKey = .none
        state.entries = [file]
        state.entryArrangements.groupedItems = [
            .init(groupName: "", items: [file]),
        ]
        let store = Store(initialState: state) { EntryViewLayoutFeature() }

        XCTAssertNil(state.presentation.sections.first?.title)

        let gridSections = EntryGridCoordinator(store: store).makeSections(state: state)
        let listItems = EntryListCoordinator(store: store).makeOutlineItems(state: state)

        XCTAssertNil(gridSections.first?.title)
        XCTAssertTrue(listItems.allSatisfy { item in
            if case .entry = item.kind { return true }
            return false
        })
        XCTAssertEqual(listItems.flatMap { $0.flattenEntries().map(\.0) }, [file.id])
    }

    /// EVM-002-switch_entries_view: 접힌 group은 grid와 list에서 동일하게 숨겨진다.
    /// - 검증 내용: 공통 section의 collapse 상태가 두 coordinator의 child 가시성에 적용된다.
    /// - 사전 조건: Text section이 collapsed 상태다.
    /// - 기대 결과: grid item은 숨겨지고 list group은 collapsed 상태를 유지한다.
    func testCollapsedSharedSectionHidesItemsInBothLayouts() {
        let file = makePresentationFile(id: "/root/file.txt", name: "file.txt")
        var state = EntryViewLayoutState()
        state.entryArrangements.groupKey = .kind
        state.entryArrangements.collapsedGroups = ["Text"]
        state.entries = [file]
        state.entryArrangements.groupedItems = [
            .init(groupName: "Text", items: [file]),
        ]
        let store = Store(initialState: state) { EntryViewLayoutFeature() }
        let gridSection = EntryGridCoordinator(store: store).makeSections(state: state)[0]
        let listGroup = EntryListCoordinator(store: store).makeOutlineItems(state: state)[0]

        XCTAssertTrue(gridSection.isCollapsed)
        XCTAssertTrue(gridSection.items.isEmpty)
        guard case let .group(_, _, isCollapsed) = listGroup.kind else {
            return XCTFail("List projection must preserve a group row")
        }
        XCTAssertTrue(isCollapsed)
        XCTAssertEqual(listGroup.children.flatMap { $0.flattenEntries().map(\.0) }, [file.id])
    }

    /// EVM-002-open_with: grid와 list context menu는 같은 Open With application projection을 사용한다.
    /// - 검증 내용: 두 coordinator가 state에 투영된 application cache를 그대로 반환한다.
    /// - 사전 조건: TextEdit application 정보가 공통 presentation에 있다.
    /// - 기대 결과: grid와 list 모두 TextEdit 한 건을 반환한다.
    func testGridAndListConsumeProjectedOpenWithApplications() {
        let file = makePresentationFile(id: "/root/file.txt", name: "file.txt")
        let application = ApplicationInfo(
            id: "com.apple.TextEdit",
            name: "TextEdit",
            bundleID: "com.apple.TextEdit",
            isDefault: true,
        )
        var state = EntryViewLayoutState()
        state.entries = [file]
        state.entryOperations.commonApplicationsForSelectedFiles = [application]
        let store = Store(initialState: state) { EntryViewLayoutFeature() }

        XCTAssertEqual(
            EntryGridCoordinator(store: store).openWithApplications(selectedEntries: [file]),
            [application],
        )
        XCTAssertEqual(
            EntryListCoordinator(store: store).openWithApplications(selectedEntries: [file]),
            [application],
        )
    }

    /// EVM-002-switch_entries_view: 공통 change set은 구조, payload, selection, expansion 변화를 분리한다.
    /// - 검증 내용: 삽입/삭제/갱신 ID와 UI-only semantic flag가 독립적으로 계산된다.
    /// - 사전 조건: retained entry payload가 바뀌고 sibling이 교체되며 selection과 collapse가 바뀐다.
    /// - 기대 결과: 각 변화가 정확한 change-set field에 기록된다.
    func testPresentationChangeSetClassifiesSemanticChanges() {
        let removed = EntryModel.temporaryFolder(id: "/root/removed", name: "removed")
        let original = EntryModel.temporaryFolder(id: "/root/retained", name: "old")
        let updated = EntryModel.temporaryFolder(id: original.id, name: "new")
        let inserted = EntryModel.temporaryFolder(id: "/root/inserted", name: "inserted")
        let previous = EntryViewLayoutPresentation(
            sections: [
                .init(
                    id: "Folders",
                    title: "Folders",
                    colorCode: nil,
                    items: [removed, original],
                    isCollapsed: false,
                ),
            ],
            selectedIds: [removed.id],
            openWithApplications: [],
        )
        let current = EntryViewLayoutPresentation(
            sections: [
                .init(
                    id: "Folders",
                    title: "Folders",
                    colorCode: nil,
                    items: [updated, inserted],
                    isCollapsed: true,
                ),
            ],
            selectedIds: [updated.id],
            openWithApplications: [],
        )

        let changes = current.changes(from: previous)

        XCTAssertTrue(changes.sectionStructureChanged)
        XCTAssertEqual(changes.insertedEntryIDs, [inserted.id])
        XCTAssertEqual(changes.removedEntryIDs, [removed.id])
        XCTAssertEqual(changes.updatedEntryIDs, [updated.id])
        XCTAssertTrue(changes.selectionChanged)
        XCTAssertTrue(changes.groupExpansionChanged)
        XCTAssertFalse(changes.openWithApplicationsChanged)
    }

    // MARK: - EVM-002-rename_entry_inline

    /// EVM-002-rename_entry_inline: list inline rename 중 Escape는 rename-cancel delegate 경로를 사용한다.
    /// 기존 코드는 Escape에서 `.view(.updateSelection(...))`로 selection/scroll 상태를 재설정했지만,
    /// 수정 후에는 `.delegate(.renameCanceled)`만 방출하고 coordinator가 command를 소비한다.
    /// - 검증 내용: Escape가 true를 반환하고 store의 selection/scroll 상태를 변경하지 않는다.
    /// - 사전 조건: renamingItemId가 설정된 list 상태와 coordinator에 연결된 text field가 있다.
    /// - 기대 결과: cancelOperation command가 true를 반환하고 selectedIds/lastSelectedId/shouldScrollToSelection이 유지된다.
    func testEscapeDuringInlineRenameEmitsRenameCanceledDelegateAndConsumesCommand() {
        let renamingId = "/root/renaming"
        let renamingEntry = EntryModel.temporaryFolder(id: renamingId, name: "renaming")
        var state = EntryViewLayoutState()
        state.entries = [renamingEntry]
        state.selectedIds = [renamingId]
        state.lastSelectedId = renamingId
        state.rangeAnchorId = renamingId
        state.entryOperations.renamingItemId = renamingId
        state.shouldScrollToSelection = true

        let store = Store(initialState: state) { EntryViewLayoutFeature() }
        let coordinator = EntryListCoordinator(store: store)

        let textField = NSTextField()
        textField.delegate = coordinator
        textField.stringValue = "renaming"

        let handled = coordinator.control(
            textField,
            textView: NSTextView(),
            doCommandBy: #selector(NSResponder.cancelOperation(_:)),
        )

        XCTAssertTrue(handled)
        XCTAssertEqual(store.state.selectedIds, [renamingId])
        XCTAssertEqual(store.state.lastSelectedId, renamingId)
        XCTAssertTrue(store.state.shouldScrollToSelection)
    }
}

extension EVM002ManageEntriesViewPresentationTests {
    // MARK: - EVM-002-single_presentation_delta_per_render

    /// EVM-002-single_presentation_delta_per_render: grid 구조 렌더는 emission snapshot presentation을 한 번만 유도해 소비한다.
    /// 구조 rebuild가 live state를 다시 읽지 않고 전달된 snapshot.presentation에서 섹션을 재구성함을 diverged state로 검증한다.
    /// - 검증 내용: handleSnapshotChanges 구조 rebuild 결과 sections가 snapshot의 new entry만 반영하는지 확인
    /// - 사전 조건: store state가 snapshot과 다른 diverged entry를 갖고 previous/snapshot은 rename 형태(old→new)다.
    /// - 기대 결과: 최종 sections가 live state의 diverged entry가 아닌 snapshot의 renamed entry를 포함한다.
    func testGridStructuralRenameRenderConsumesSnapshotPresentationNotLiveState() {
        let old = EntryModel.temporaryFolder(id: "/root/old", name: "old")
        let renamed = EntryModel.temporaryFolder(id: "/root/new", name: "new")
        let diverged = EntryModel.temporaryFolder(id: "/root/diverged", name: "live-diverged")
        var previousState = EntryViewLayoutState()
        previousState.entries = [old]
        var snapshotState = EntryViewLayoutState()
        snapshotState.entries = [renamed]
        var liveState = EntryViewLayoutState()
        liveState.entries = [diverged]

        let store = Store(initialState: liveState) { EntryViewLayoutFeature() }
        let coordinator = EntryGridCoordinator(store: store)
        coordinator.bind(to: EntryGridView(frame: NSRect(x: 0, y: 0, width: 320, height: 240)))
        coordinator.isRenderObservationEnabled = false

        coordinator.handleSnapshotChanges(
            previous: EntryGridRenderSnapshot(state: previousState),
            snapshot: EntryGridRenderSnapshot(state: snapshotState),
        )

        XCTAssertEqual(coordinator.sections.flatMap(\.items).map(\.id), [renamed.id])
        XCTAssertEqual(coordinator.sections.flatMap(\.items).map(\.name), ["new"])
    }

    /// EVM-002-single_presentation_delta_per_render: grid payload-only 렌더는 공유 change set과 snapshot presentation을 소비한다.
    /// payload 재적용이 live state.presentation을 다시 유도하지 않음을 diverged state로 검증한다.
    /// - 검증 내용: payload-only 경로 뒤 섹션이 snapshot의 갱신된 이름을 반영하는지 확인
    /// - 사전 조건: 같은 ID의 payload 변화가 담긴 previous/snapshot과 이름이 다른 diverged live state가 있다.
    /// - 기대 결과: 섹션이 live state의 diverged 이름이 아닌 snapshot의 새 이름을 반영한다.
    func testGridPayloadOnlyRenderConsumesSnapshotPresentationNotLiveState() {
        let original = EntryModel.temporaryFolder(id: "/root/a", name: "old")
        let updated = EntryModel.temporaryFolder(id: "/root/a", name: "snapshot-new")
        let diverged = EntryModel.temporaryFolder(id: "/root/a", name: "live-diverged")
        var previousState = EntryViewLayoutState()
        previousState.entries = [original]
        var snapshotState = EntryViewLayoutState()
        snapshotState.entries = [updated]
        var liveState = EntryViewLayoutState()
        liveState.entries = [diverged]

        let store = Store(initialState: liveState) { EntryViewLayoutFeature() }
        let coordinator = EntryGridCoordinator(store: store)
        coordinator.bind(to: EntryGridView(frame: NSRect(x: 0, y: 0, width: 320, height: 240)))
        coordinator.isRenderObservationEnabled = false

        coordinator.handleSnapshotChanges(
            previous: EntryGridRenderSnapshot(state: previousState),
            snapshot: EntryGridRenderSnapshot(state: snapshotState),
        )

        XCTAssertEqual(coordinator.sections.first?.items.first?.name, "snapshot-new")
    }

    /// EVM-002-single_presentation_delta_per_render: list flat group expansion rebuild는 snapshot presentation을 직접 소비한다.
    /// groupExpansionChanged 경로가 새 RenderSnapshot/EntryListOutlineProjection 없이 전달된 snapshot.presentation으로
    /// row를 재구성함을 diverged state로 검증한다.
    /// - 검증 내용: groupExpansionChanged 뒤 Text 그룹이 접히고 row가 snapshot의 entry를 반영하는지 확인
    /// - 사전 조건: previous는 Text 그룹이 펼쳐져 있고 snapshot은 접힘 상태며 live state는 다른 payload의 펼침 상태다.
    /// - 기대 결과: Text 그룹은 접히고 row는 live state의 diverged payload가 아닌 snapshot의 file을 포함한다.
    func testListFlatGroupExpansionRebuildConsumesSnapshotPresentationNotLiveState() throws {
        let folder = EntryModel.temporaryFolder(id: "/root/folder", name: "folder")
        let file = makePresentationFile(id: "/root/file.txt", name: "file.txt")
        let divergedFile = makePresentationFile(id: "/root/diverged.txt", name: "live-diverged")
        var previousState = EntryViewLayoutState()
        previousState.entryArrangements.groupKey = .kind
        previousState.entryArrangements.groupedItems = [
            .init(groupName: "Folders", items: [folder]),
            .init(groupName: "Text", items: [file]),
        ]
        var snapshotState = previousState
        snapshotState.entryArrangements.collapsedGroups = ["Text"]
        var liveState = previousState
        liveState.entryArrangements.groupedItems = [
            .init(groupName: "Folders", items: [folder]),
            .init(groupName: "Text", items: [divergedFile]),
        ]

        let store = Store(initialState: liveState) { EntryViewLayoutFeature() }
        let coordinator = EntryListCoordinator(store: store)
        coordinator.bind(to: EntryListView(frame: .zero))
        coordinator.isRenderObservationEnabled = false

        coordinator.handleSnapshotChanges(
            previous: EntryListCoordinatorRenderSnapshot(state: previousState),
            snapshot: EntryListCoordinatorRenderSnapshot(state: snapshotState),
        )

        let textGroup = try XCTUnwrap(coordinator.groupItemByName["Text"])
        XCTAssertFalse(coordinator.tableView.isItemExpanded(textGroup))
        XCTAssertEqual(
            coordinator.outlineItems.flatMap { $0.flattenEntries().map(\.0) },
            [folder.id, file.id],
        )
    }

    /// EVM-002-single_presentation_delta_per_render: selection-only emission은 grid 구조 재유도를 유발하지 않는다.
    /// selectedIds만 바뀐 emission에서 어떤 렌더 헬퍼도 섹션 데이터 소스를 다시 만들지 않음을 sentinel로 검증한다.
    /// - 검증 내용: selection 차이만 있는 emission에서 sections가 재작성되지 않고 selection만 collection view에 동기화됨
    /// - 사전 조건: 두 entry를 렌더한 뒤 sections를 비운 sentinel 상태로 만들고 previous/snapshot이 selection만 다르다.
    /// - 기대 결과: sentinel sections가 유지되고 collection view 선택이 snapshot selection을 반영한다.
    func testGridSelectionOnlyRenderSkipsStructuralWorkAndSyncsSelection() {
        let first = EntryModel.temporaryFolder(id: "/root/first", name: "first")
        let second = EntryModel.temporaryFolder(id: "/root/second", name: "second")
        var base = EntryViewLayoutState()
        base.entries = [first, second]
        base.selectedIds = [second.id]
        var previousState = base
        previousState.selectedIds = []

        let store = Store(initialState: base) { EntryViewLayoutFeature() }
        let view = EntryGridView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        let coordinator = EntryGridCoordinator(store: store)
        coordinator.bind(to: view)
        coordinator.isRenderObservationEnabled = false
        // sentinel: 어떤 구조 헬퍼든 updateSections를 부르면 live state 내용으로 채워진다.
        coordinator.sections = []

        coordinator.handleSnapshotChanges(
            previous: EntryGridRenderSnapshot(state: previousState),
            snapshot: EntryGridRenderSnapshot(state: base),
        )

        XCTAssertTrue(coordinator.sections.isEmpty, "selection-only emission은 section 재유도를 유발하지 않아야 함")
        XCTAssertEqual(view.collectionView.selectionIndexPaths, [IndexPath(item: 1, section: 0)])
    }

    /// EVM-002-single_presentation_delta_per_render: selection-only emission은 list row 객체를 교체하지 않는다.
    /// - 검증 내용: selection 차이만 있는 emission에서 outline item identity가 유지되고 selection만 동기화됨
    /// - 사전 조건: 두 entry를 렌더한 flat list에 previous/snapshot이 selection만 다르게 주어진다.
    /// - 기대 결과: outline item 인스턴스가 동일하게 유지되고 첫 row가 선택된다.
    func testListSelectionOnlyRenderKeepsOutlineItemsAndSyncsSelection() {
        let first = EntryModel.temporaryFolder(id: "/root/first", name: "first")
        let second = EntryModel.temporaryFolder(id: "/root/second", name: "second")
        var base = EntryViewLayoutState()
        base.entries = [first, second]
        base.selectedIds = [first.id]
        var previousState = base
        previousState.selectedIds = []

        let store = Store(initialState: base) { EntryViewLayoutFeature() }
        let coordinator = EntryListCoordinator(store: store)
        coordinator.bind(to: EntryListView(frame: .zero))
        coordinator.isRenderObservationEnabled = false
        let boundItems = coordinator.outlineItems

        coordinator.handleSnapshotChanges(
            previous: EntryListCoordinatorRenderSnapshot(state: previousState),
            snapshot: EntryListCoordinatorRenderSnapshot(state: base),
        )

        XCTAssertEqual(coordinator.outlineItems.map(\.id), boundItems.map(\.id))
        for (rendered, bound) in zip(coordinator.outlineItems, boundItems) {
            XCTAssertIdentical(rendered, bound)
        }
        XCTAssertEqual(coordinator.tableView.selectedRowIndexes, IndexSet(integer: 0))
    }

    // MARK: - EVM-002-atomic_identity_swap

    /// EVM-002-atomic_identity_swap: Grid flat rename/move는 full reload 대신 하나의 incremental batch를 사용한다.
    /// - 검증 내용: before-path 한 건이 after-path로 교체된 change set의 rebuild 판정과 최종 selection을 확인한다.
    /// - 사전 조건: unaffected sibling과 선택된 after-path가 있는 단일 identity swap이다.
    /// - 기대 결과: shouldRebuildSections는 false이고 최종 Grid IDs/selection은 after-path다.
    func testGridFlatIdentitySwapUsesIncrementalBatchAndSelectsAfterPath() {
        for operationName in ["rename", "move"] {
            let before = EntryModel.temporaryFolder(id: "/root/\(operationName)-before", name: "before")
            let after = EntryModel.temporaryFolder(id: "/root/\(operationName)-after", name: "after")
            let unaffected = EntryModel.temporaryFolder(id: "/root/unaffected", name: "unaffected")
            var previousState = EntryViewLayoutState()
            previousState.entries = [before, unaffected]
            var currentState = EntryViewLayoutState()
            currentState.entries = [after, unaffected]
            currentState.selectedIds = [after.id]
            currentState.lastSelectedId = after.id

            let store = Store(initialState: currentState) { EntryViewLayoutFeature() }
            let view = EntryGridView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
            let coordinator = EntryGridCoordinator(store: store)
            coordinator.bind(to: view)
            coordinator.isRenderObservationEnabled = false
            let previous = EntryGridRenderSnapshot(state: previousState)
            let current = EntryGridRenderSnapshot(state: currentState)
            let changes = current.presentation.changes(from: previous.presentation)

            XCTAssertFalse(
                coordinator.shouldRebuildSections(previous: previous, snapshot: current, changes: changes),
                "\(operationName) identity swap는 하나의 Grid batch여야 한다",
            )
            coordinator.handleSnapshotChanges(previous: previous, snapshot: current)

            XCTAssertEqual(coordinator.sections.flatMap(\.items).map(\.id), [after.id, unaffected.id])
            XCTAssertEqual(view.collectionView.selectionIndexPaths, [IndexPath(item: 0, section: 0)])
        }
    }

    /// EVM-002-atomic_identity_swap: Grid identity swap과 같은 emission의 retained payload 갱신은 구조 배치 후 retained
    /// visible 항목을 다시 그려 화면의 이름을 갱신한다.
    /// - 검증 내용: 구조 batch 뒤 retained updated 항목의 보이는 cell이 새 payload로 reconfigure되는지 확인
    /// - 사전 조건: before→after identity swap과 동시에 retained entry payload가 old→new로 바뀐 단일 emission이 있다.
    /// - 기대 결과: full reload 없이 incremental 경로를 쓰며 retained visible cell의 표시 이름이 new가 된다.
    func testGridIdentitySwapReloadsRetainedUpdatedVisibleEntry() throws {
        let before = EntryModel.temporaryFolder(id: "/root/before", name: "before")
        let after = EntryModel.temporaryFolder(id: "/root/after", name: "after")
        let retainedOld = EntryModel.temporaryFolder(id: "/root/retained", name: "old")
        let retainedNew = EntryModel.temporaryFolder(id: retainedOld.id, name: "new")
        var previousState = EntryViewLayoutState()
        previousState.isCollectionMode = true
        previousState.entries = [retainedOld, before]
        var currentState = EntryViewLayoutState()
        currentState.isCollectionMode = true
        currentState.entries = [retainedNew, after]

        let store = Store(initialState: previousState) { EntryViewLayoutFeature() }
        let view = EntryGridView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        let coordinator = EntryGridCoordinator(store: store)
        coordinator.bind(to: view)
        coordinator.isRenderObservationEnabled = false
        view.layoutSubtreeIfNeeded()
        view.collectionView.layoutSubtreeIfNeeded()
        let previous = EntryGridRenderSnapshot(state: previousState)
        let current = EntryGridRenderSnapshot(state: currentState)
        let changes = current.presentation.changes(from: previous.presentation)

        XCTAssertFalse(
            coordinator.shouldRebuildSections(previous: previous, snapshot: current, changes: changes),
            "identity swap + retained payload 갱신은 하나의 Grid batch여야 한다",
        )
        XCTAssertEqual(changes.updatedEntryIDs, [retainedNew.id])

        let retainedIndexPath = try XCTUnwrap(coordinator.indexPathByEntryId[retainedOld.id])
        XCTAssertEqual(try displayedNameOfItem(at: retainedIndexPath, in: view), "old")

        coordinator.handleSnapshotChanges(previous: previous, snapshot: current)

        XCTAssertEqual(coordinator.sections.flatMap(\.items).map(\.id), [retainedNew.id, after.id])
        XCTAssertEqual(try displayedNameOfItem(at: retainedIndexPath, in: view), "new")
    }

    /// EVM-002-atomic_identity_swap: List flat rename/move는 한 row batch에서 교체하고 unaffected row identity를 유지한다.
    /// - 검증 내용: tryIncrementalFlatRowUpdate 결과와 retained OutlineItem object identity를 확인한다.
    /// - 사전 조건: 한 section에 before-path와 unaffected sibling이 있고 after-path로 교체된다.
    /// - 기대 결과: incremental update가 true이며 unaffected OutlineItem이 `===`로 유지된다.
    func testListFlatIdentitySwapUsesSingleBatchAndRetainsUnaffectedRow() throws {
        for operationName in ["rename", "move"] {
            let before = EntryModel.temporaryFolder(id: "/root/\(operationName)-before", name: "before")
            let after = EntryModel.temporaryFolder(id: "/root/\(operationName)-after", name: "after")
            let unaffected = EntryModel.temporaryFolder(id: "/root/unaffected", name: "unaffected")
            var previousState = EntryViewLayoutState()
            previousState.entries = [before, unaffected]
            var currentState = EntryViewLayoutState()
            currentState.entries = [after, unaffected]
            let store = Store(initialState: previousState) { EntryViewLayoutFeature() }
            let coordinator = EntryListCoordinator(store: store)
            coordinator.bind(to: EntryListView(frame: .zero))
            coordinator.isRenderObservationEnabled = false
            let retainedItem = try XCTUnwrap(coordinator.entryItemById[unaffected.id])
            let previous = EntryListCoordinatorRenderSnapshot(state: previousState)
            let current = EntryListCoordinatorRenderSnapshot(state: currentState)
            let changes = current.presentation.changes(from: previous.presentation)

            XCTAssertTrue(coordinator.tryIncrementalFlatRowUpdate(
                previous: previous.presentation,
                current: current.presentation,
                changes: changes,
            ))

            XCTAssertEqual(coordinator.outlineItems.flatMap { $0.flattenEntries().map(\.0) }, [after.id, unaffected.id])
            XCTAssertIdentical(coordinator.entryItemById[unaffected.id], retainedItem)
        }
    }

    /// EVM-002-atomic_identity_swap: expanded List child rename/move는 parent batch에서 교체하고 sibling identity를 유지한다.
    /// - 검증 내용: applyStoreProjection 뒤 after child/selection과 unaffected child object identity를 확인한다.
    /// - 사전 조건: expanded folder가 before child와 unaffected child를 완전 snapshot으로 표시한다.
    /// - 기대 결과: after child만 남고 selected row가 after이며 unaffected OutlineItem은 `===`다.
    func testExpandedListIdentitySwapRetainsUnaffectedChildAndSelectsAfterPath() throws {
        let folder = EntryModel.temporaryFolder(id: "/root/folder", name: "folder")
        let before = makePresentationFile(id: "/root/folder/before.txt", name: "before.txt")
        let after = makePresentationFile(id: "/root/folder/after.txt", name: "after.txt")
        let unaffected = makePresentationFile(id: "/root/folder/unaffected.txt", name: "unaffected.txt")
        var oldHierarchy = EntryListHierarchyState(rootPath: "/root")
        oldHierarchy.nodesByID[folder.id] = .init(
            children: [before, unaffected],
            loadPhase: .loaded,
            generation: 1,
            expectedBatchIndex: 1,
            coreFinished: true,
        )
        oldHierarchy.setExpandedIDs([folder.id])
        var newHierarchy = oldHierarchy
        newHierarchy.nodesByID[folder.id]?.folder.children = [after, unaffected]
        let oldProjection = EntryListOutlineProjection(
            revision: 1,
            rootEntries: [folder],
            hierarchyState: oldHierarchy,
            context: .init(mode: .list, isNormalDirectoryPage: true, hasActiveGrouping: false),
            sortKey: .name,
            sortOrder: .ascending,
        )
        let newProjection = EntryListOutlineProjection(
            revision: 2,
            rootEntries: [folder],
            hierarchyState: newHierarchy,
            context: .init(mode: .list, isNormalDirectoryPage: true, hasActiveGrouping: false),
            sortKey: .name,
            sortOrder: .ascending,
        )
        var state = EntryViewLayoutState()
        state.mode = .list
        state.entries = [folder]
        state.hierarchy = newHierarchy
        state.selectedIds = [after.id]
        state.lastSelectedId = after.id
        let store = Store(initialState: state) { EntryViewLayoutFeature() }
        let coordinator = EntryListCoordinator(store: store)
        coordinator.bind(to: EntryListView(frame: .zero))
        coordinator.isRenderObservationEnabled = false

        coordinator.applyStoreProjection(oldProjection)
        let retainedItem = try XCTUnwrap(coordinator.entryItemById[unaffected.id])
        coordinator.applyStoreProjection(newProjection)

        XCTAssertEqual(newProjection.visibleSelectableEntryIDs, [folder.id, after.id, unaffected.id])
        XCTAssertIdentical(coordinator.entryItemById[unaffected.id], retainedItem)
        let selectedItem = try XCTUnwrap(coordinator.entryItemById[after.id])
        XCTAssertEqual(coordinator.tableView.selectedRow, coordinator.tableView.row(forItem: selectedItem))
    }
}

private extension EntryListOutlineItem {
    var groupName: String? {
        guard case let .group(name, _, _) = kind else { return nil }
        return name
    }
}

@MainActor
private func displayedNameOfItem(at indexPath: IndexPath, in view: EntryGridView) throws -> String {
    let item = try XCTUnwrap(view.collectionView.item(at: indexPath), "index path의 grid item이 materialized 되어 있어야 함")
    let nameField = try XCTUnwrap(
        descendantView(
            withIdentifier: NSUserInterfaceItemIdentifier("entryGrid.nameField"),
            in: item.view,
        ) as? NSTextField,
    )
    return nameField.stringValue
}

@MainActor
private func descendantView(withIdentifier identifier: NSUserInterfaceItemIdentifier, in root: NSView) -> NSView? {
    if root.identifier == identifier { return root }
    for subview in root.subviews {
        if let found = descendantView(withIdentifier: identifier, in: subview) { return found }
    }
    return nil
}

private func makePresentationFile(id: String, name: String) -> EntryModel {
    EntryModel(
        name: name,
        fullPath: id,
        isFolder: false,
        isHidden: false,
        size: 1,
        modifiedDate: Date(timeIntervalSince1970: 0),
        fileExtension: "txt",
        facets: .init(
            createdDate: Date(timeIntervalSince1970: 0),
            addedDate: Date(timeIntervalSince1970: 0),
            lastOpenedDate: nil,
            kind: "Text",
            creatorApplication: nil,
            tags: nil,
            supplementaryMetadata: nil,
        ),
    )
}

private func outlineProjection(revision: Int, roots: [EntryModel]) -> EntryListOutlineProjection {
    var hierarchy = EntryListHierarchyState(rootPath: "/root")
    hierarchy.setExpandedIDs(Set(roots.filter(\.isFolder).map(\.id)))
    return EntryListOutlineProjection(
        revision: revision,
        rootEntries: roots,
        hierarchyState: hierarchy,
        context: .init(mode: .list, isNormalDirectoryPage: true, hasActiveGrouping: false),
        sortKey: .name,
        sortOrder: .ascending,
    )
}
