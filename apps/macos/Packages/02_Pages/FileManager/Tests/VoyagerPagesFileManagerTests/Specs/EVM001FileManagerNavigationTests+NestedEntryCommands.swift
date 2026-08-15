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

        await store.send(.entryViewLayout(.delegate(.executeCommand("navigation.openSelectedItem"))))
        await store.receive { action in
            guard case let .entryViewLayout(.entryOperations(.routing(.executeCommand(_, context)))) = action
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
            guard case let .entryViewLayout(.delegate(.startRename(item, text))) = action else { return false }
            return item == child && text == child.name
        }
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

        await store.send(.entryViewLayout(.delegate(.executeCommand("mutation.emptyTrash"))))
        await store.receive { action in
            guard case let .entryViewLayout(.entryOperations(.routing(.executeCommand(_, context)))) = action
            else { return false }
            XCTAssertEqual(context.displayItems.map(\.id), [root.id])
            return true
        }
    }
}
