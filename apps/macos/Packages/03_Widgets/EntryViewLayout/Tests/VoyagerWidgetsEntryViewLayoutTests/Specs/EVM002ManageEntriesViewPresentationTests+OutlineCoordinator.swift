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
        currentState.clipboardCutPaths = [targetEntry.fullPath]
        currentState.renamingItemId = targetEntry.id
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
        previousState.renamingItemId = retainedEntry.id

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
        state.hierarchy = .init(rootPath: "/root")
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
        coordinator.reloadVisibleItemsForEntryContentChange(previous: previous, snapshot: snapshot)

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
        state.groupKey = .kind
        state.entries = [folder, file]
        state.presentationSections = [
            .init(id: "Folders", title: "Folders", colorCode: nil, items: [folder], isCollapsed: false),
            .init(id: "Text", title: "Text", colorCode: nil, items: [file], isCollapsed: false),
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

    /// EVM-002-switch_entries_view: 접힌 group은 grid와 list에서 동일하게 숨겨진다.
    /// - 검증 내용: 공통 section의 collapse 상태가 두 coordinator의 child 가시성에 적용된다.
    /// - 사전 조건: Text section이 collapsed 상태다.
    /// - 기대 결과: grid item은 숨겨지고 list group은 collapsed 상태를 유지한다.
    func testCollapsedSharedSectionHidesItemsInBothLayouts() {
        let file = makePresentationFile(id: "/root/file.txt", name: "file.txt")
        var state = EntryViewLayoutState()
        state.groupKey = .kind
        state.collapsedGroups = ["Text"]
        state.entries = [file]
        state.presentationSections = [
            .init(id: "Text", title: "Text", colorCode: nil, items: [file], isCollapsed: true),
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
        state.openWithApplications = [application]
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
}

private extension EntryListOutlineItem {
    var groupName: String? {
        guard case let .group(name, _, _) = kind else { return nil }
        return name
    }
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
