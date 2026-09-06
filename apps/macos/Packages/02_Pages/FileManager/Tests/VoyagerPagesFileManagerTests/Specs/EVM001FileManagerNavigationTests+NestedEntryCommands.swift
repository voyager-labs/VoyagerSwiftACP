import ComposableArchitecture
import VoyagerEntitiesEntry
import VoyagerFeaturesEntryOperations
@testable import VoyagerPagesFileManager
import VoyagerShared
import XCTest

@MainActor
extension EVM001FileManagerNavigationTests {
    /// EVM-001-route_entry_selection_commands: 중첩 child 선택은 AI Chat current context에 포함된다.
    /// - 검증 내용: selectionChanged bridge가 visible hierarchy child를 context item으로 전달한다.
    /// - 사전 조건: root folder가 펼쳐져 있고 root snapshot에 없는 child가 선택돼 있다.
    /// - 기대 결과: currentContextChanged의 item identifier가 선택한 child 경로다.
    func testNestedSelectionUpdatesAiChatCurrentContext() async {
        let root = EntryModel.temporaryFolder(id: "/root/folder", name: "folder")
        let child = EntryModel.temporaryFolder(id: "/root/folder/child", name: "child")
        var state = FileManagerContentState()
        state.navigation.navigationState = .folder("/root")
        state.entryViewLayout.entries = [root]
        state.entryViewLayout.hierarchy = .init(
            rootPath: "/root",
            nodesByID: [root.id: .init(children: [child], loadPhase: .loaded, generation: 0)],
        )
        state.entryViewLayout.hierarchy.setExpandedIDs([root.id])
        state.entryViewLayout.selectedIds = [child.id]
        let store = TestStore(initialState: state) {
            FileManagerContentEntryOperationsBridgeReducer()
        }

        await store.send(.entryViewLayout(.delegate(.selectionChanged)))
        await store.receive { action in
            guard case let .entryViewLayout(.entryOperations(.lifecycle(.syncSelectedEntryIDs(selectedIDs)))) = action
            else {
                return false
            }
            return selectedIDs == [child.id]
        }
        await store.receive { action in
            guard case let .delegate(.currentContextChanged(context)) = action else { return false }
            return context.items.map(\.identifier) == [child.id]
        }
        await store.receive { action in
            guard case let .entryViewLayout(.entryOperations(.open(.syncQuickLookSelection(paths, selectedIndex)))) =
                action
            else { return false }
            return paths == [child.fullPath] && selectedIndex == 0
        }
    }

    /// EVM-001-route_selection_commands: selectionChanged가 선택 순서를 유지한 Quick Look sync를 방출한다.
    /// - 검증 내용: 다중 선택이 display 순서대로 paths로 전달되고, lastSelectedId가 selectedIndex로 매핑된다.
    /// - 사전 조건: root entries [a, b, entryC]에서 b, entryC가 선택되고 lastSelectedId가 entryC다.
    /// - 기대 결과: syncQuickLookSelection paths == [b.fullPath, entryC.fullPath], selectedIndex == 1.
    func testSelectionChangedEmitsOrderedQuickLookSync() async {
        let a = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        let b = EntryModel.temporaryFolder(id: "/root/b", name: "b")
        let entryC = EntryModel.temporaryFolder(id: "/root/c", name: "c")
        var state = FileManagerContentState()
        state.navigation.navigationState = .folder("/root")
        state.entryViewLayout.entries = [a, b, entryC]
        state.entryViewLayout.entryOperations.items = [a, b, entryC]
        state.entryViewLayout.selectedIds = [b.id, entryC.id]
        state.entryViewLayout.lastSelectedId = entryC.id
        let store = TestStore(initialState: state) {
            FileManagerContentEntryOperationsBridgeReducer()
        }

        await store.send(.entryViewLayout(.delegate(.selectionChanged)))
        await store.receive { action in
            guard case let .entryViewLayout(.entryOperations(.lifecycle(.syncSelectedEntryIDs(selectedIDs)))) = action
            else { return false }
            return selectedIDs == [b.id, entryC.id]
        }
        await store.receive { action in
            guard case let .delegate(.currentContextChanged(context)) = action else { return false }
            return context.items.map(\.identifier) == [b.id, entryC.id]
        }
        await store.receive { action in
            guard case let .entryViewLayout(.entryOperations(.open(.syncQuickLookSelection(paths, selectedIndex)))) =
                action
            else { return false }
            return paths == [b.fullPath, entryC.fullPath] && selectedIndex == 1
        }
    }

    /// EVM-001-route_selection_commands: 빈 selection은 Quick Look sync를 방출하지 않는다 (frozen no-op).
    /// - 검증 내용: 선택이 비어 있으면 기존 두 effect(syncSelectedEntryIDs, currentContextChanged)만 방출한다.
    /// - 사전 조건: selectedIds가 비어 있다.
    /// - 기대 결과: Quick Look sync action이 없고, store exhaustivity로 추가 action 발생 시 실패한다.
    func testSelectionChangedEmptySelectionEmitsNoQuickLookSync() async {
        var state = FileManagerContentState()
        state.navigation.navigationState = .folder("/root")
        state.entryViewLayout.entries = [EntryModel.temporaryFolder(id: "/root/a", name: "a")]
        state.entryViewLayout.selectedIds = []
        let store = TestStore(initialState: state) {
            FileManagerContentEntryOperationsBridgeReducer()
        }

        await store.send(.entryViewLayout(.delegate(.selectionChanged)))
        await store.receive { action in
            guard case let .entryViewLayout(.entryOperations(.lifecycle(.syncSelectedEntryIDs(selectedIDs)))) = action
            else { return false }
            return selectedIDs.isEmpty
        }
        await store.receive { action in
            guard case let .delegate(.currentContextChanged(context)) = action else { return false }
            return context.items.isEmpty
        }
    }

    /// 중첩 행의 command context가 root snapshot 대신 가시 projection payload를 사용하는지 검증한다.
    func testNestedSelectionCommandUsesVisibleProjectionEntries() async {
        let root = EntryModel.temporaryFolder(id: "/root/folder", name: "folder")
        let child = EntryModel.temporaryFolder(id: "/root/folder/child", name: "child")
        var state = FileManagerContentState()
        state.navigation.navigationState = .folder("/root")
        state.entryViewLayout.entries = [root]
        state.entryViewLayout.hierarchy = .init(
            rootPath: "/root",
            nodesByID: [root.id: .init(children: [child], loadPhase: .loaded, generation: 0)],
        )
        state.entryViewLayout.hierarchy.setExpandedIDs([root.id])
        state.entryViewLayout.selectedIds = [child.id]
        let store = TestStore(initialState: state) {
            FileManagerContentEntryOperationsBridgeReducer()
        }
        store.exhaustivity = .off

        await store.send(.entryViewLayout(.delegate(.executeCommand(
            "navigation.openSelectedItem",
            source: .fileManagerContent,
        ))))
        await store.receive { action in
            guard case let .entryViewLayout(.entryOperations(.routing(.executeCommand(_, context, _)))) = action
            else { return false }
            XCTAssertEqual(context.selectedIds, [child.id])
            XCTAssertEqual(context.displayItems.map(\.id), [root.id, child.id])
            return true
        }
    }

    /// Return key rename이 expanded folder의 nested child를 command 대상으로 사용하는지 검증한다.
    func testRenameKeyCommandStartsRenameForNestedChild() async {
        let folder = EntryModel.temporaryFolder(id: "/root/folder", name: "folder")
        let child = EntryModel.temporaryFolder(id: "/root/folder/child", name: "child")
        var state = FileManagerContentState()
        state.navigation.navigationState = .folder("/root")
        state.entryViewLayout.entries = [folder]
        state.entryViewLayout.selectedIds = [child.id]
        state.entryViewLayout.hierarchy = .init(
            rootPath: "/root",
            nodesByID: [folder.id: .init(children: [child], loadPhase: .loaded, generation: 0)],
        )
        state.entryViewLayout.hierarchy.setExpandedIDs([folder.id])
        let command = KeyCommand(
            keyCode: 36,
            modifiers: [],
            characters: "\r",
            charactersIgnoringModifiers: "\r",
        )
        let store = TestStore(initialState: state) {
            Reduce<FileManagerContentState, FileManagerContentAction> { state, action in
                guard case let .view(.handleKeyCommand(command)) = action else { return .none }
                return FileManagerContentKeyCommandHandler.effect(for: command, state: state)
            }
        }

        await store.send(.view(.handleKeyCommand(command)))
        await store.receive { action in
            guard case let .entryViewLayout(.delegate(.startRename(item, text, source))) = action else {
                return false
            }
            return item == child && text == child.name && source == .keyboardShortcut
        }
    }

    /// EVM-001-route_entry_selection_commands: rename commit은 시작 source를 accepted metadata에 한 번 사용한다.
    /// - 검증 내용: pending context-menu source가 accepted rename metadata로 전달되고 commit에서 제거된다.
    /// - 사전 조건: 단일 child rename 세션이 `.contextMenu` source로 시작돼 있다.
    /// - 기대 결과: metadata source는 `.contextMenu`이고 state source는 nil이다.
    func testRenameCommitConsumesPendingSource() async {
        let entry = EntryModel.temporaryFolder(id: "/root/folder", name: "folder")
        var state = FileManagerContentState()
        state.navigation.navigationState = .folder("/root")
        state.entryViewLayout.entries = [entry]
        state.entryViewLayout.entryOperations.items = [entry]
        state.entryViewLayout.entryOperations.renamingItemId = entry.id
        state.entryViewLayout.entryOperations.renamingItem = entry
        state.entryViewLayout.entryOperations.renamingText = entry.name
        state.entryViewLayout.entryOperations.renamingCommandSource = .contextMenu
        let store = TestStore(initialState: state) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.date = .constant(Date())
            $0.entryFileOpsClient.renameFile = { _, _ in }
        }
        // store.exhaustivity = .off: parent composition의 부가 action보다 accepted metadata와 source 소비를 검증한다.
        store.exhaustivity = .off

        await store.send(.entryViewLayout(.view(.updateRenamingText("renamed"))))
        await store.send(.entryViewLayout(.delegate(.renameCommitted(
            itemID: entry.id,
            newName: "renamed",
        ))))
        await store.receive { action in
            guard case let .entryViewLayout(.entryOperations(.acceptedCommand(metadata, _))) = action else {
                return false
            }
            return metadata.source == .contextMenu
        }
        await store.finish()

        XCTAssertNil(store.state.entryViewLayout.entryOperations.renamingCommandSource)
    }

    /// EVM-001-route_entry_selection_commands: no-op rename은 시작 surface별 취소 terminal로 종료된다.
    /// - 검증 내용: 실제 start/commit route가 원래 ID/source의 cancelled record와 Product metric을 각각 한 건만 만든다.
    /// - 사전 조건: context menu, keyboard shortcut, file-manager content에서 unchanged/blank rename을 수용한다.
    /// - 기대 결과: 파일 작업, undo, reload 없이 각 명령의 empty-target cancelled terminal/metric이 정확히 한 건이다.
    func testAcceptedNoOpRenameRecordsSingleCancelledTerminalForEverySource() async {
        let entry = EntryModel.temporaryFolder(id: "/root/folder", name: "folder")
        await assertAcceptedNoOpRename(entry: entry, source: .contextMenu, draft: entry.name, id: UUID(6))
        await assertAcceptedNoOpRename(entry: entry, source: .keyboardShortcut, draft: "", id: UUID(7))
        await assertAcceptedNoOpRename(entry: entry, source: .fileManagerContent, draft: "   ", id: UUID(8))
    }

    private func assertAcceptedNoOpRename(
        entry: EntryModel,
        source: EntryCommandSource,
        draft: String,
        id: UUID,
    ) async {
        var state = FileManagerFeature.State()
        state.content.navigation.navigationState = .folder("/root")
        state.content.entryViewLayout.entries = [entry]
        state.content.entryViewLayout.entryOperations.items = [entry]
        let recorder = FileManagerProductMetricRecorder(makeOperationID: { id })
        let renameCallCount = LockIsolated(0)
        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.fileManagerProductMetricsClient = recorder.client
            $0.date = .constant(Date())
            $0.entryFileOpsClient.renameFile = { _, _ in
                renameCallCount.withValue { $0 += 1 }
            }
        }
        // store.exhaustivity = .off: parent composition 부가 action은 생략하고 실제 rename terminal을 직접 검증한다.
        store.exhaustivity = .off

        await store.send(.content(.entryViewLayout(.view(.startRename(
            item: entry,
            text: entry.name,
            source: source,
        )))))
        await store.send(.content(.entryViewLayout(.view(.commitRename(itemID: entry.id, newName: draft)))))
        await store.receive { action in
            guard case let .internal(.entryActionCompleted(_, record, _)) = action else { return false }
            return record.id == id
                && record.command?.source == source
                && record.targets.isEmpty
                && record.cancelledCount == 1
        }
        await store.finish()

        XCTAssertEqual(renameCallCount.value, 0)
        XCTAssertFalse(store.state.content.entryViewLayout.entryOperations.isReloading)
        XCTAssertTrue(store.state.content.entryViewLayout.entryOperations.undoRecords.isEmpty)
        XCTAssertEqual(recorder.metrics(), [
            .entryAction(
                result: .cancelled,
                identity: .renameEntry,
                source: source,
                operationID: id,
                aggregate: .init(attempted: 1, succeeded: 0, failed: 0, cancelled: 1),
            ),
        ])
    }

    /// empty trash command는 계층 projection과 무관하게 기존 root snapshot만 사용하는지 검증한다.
    func testEmptyTrashCommandKeepsRootSnapshotContext() async {
        let root = EntryModel.temporaryFolder(id: "/trash/folder", name: "folder")
        let child = EntryModel.temporaryFolder(id: "/trash/folder/child", name: "child")
        var state = FileManagerContentState()
        state.navigation.navigationState = .folder("/trash")
        state.entryViewLayout.entries = [root]
        state.entryViewLayout.hierarchy = .init(
            rootPath: "/trash",
            nodesByID: [root.id: .init(children: [child], loadPhase: .loaded, generation: 0)],
        )
        state.entryViewLayout.hierarchy.setExpandedIDs([root.id])
        let store = TestStore(initialState: state) {
            FileManagerContentEntryOperationsBridgeReducer()
        }
        store.exhaustivity = .off

        await store.send(.entryViewLayout(.delegate(.executeCommand(
            "mutation.emptyTrash",
            source: .fileManagerContent,
        ))))
        await store.receive { action in
            guard case let .entryViewLayout(.entryOperations(.routing(.executeCommand(_, context, _)))) = action
            else { return false }
            XCTAssertEqual(context.displayItems.map(\.id), [root.id])
            return true
        }
    }
}
