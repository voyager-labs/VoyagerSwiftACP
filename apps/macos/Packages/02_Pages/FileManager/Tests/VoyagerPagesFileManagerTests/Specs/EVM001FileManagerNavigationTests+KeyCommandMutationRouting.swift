import ComposableArchitecture
import Foundation
import VoyagerEntitiesEntry
@testable import VoyagerFeaturesEntryOperations
@testable import VoyagerPagesFileManager
import XCTest

@MainActor
extension EVM001FileManagerNavigationTests {
    // MARK: - EVM-001-route_entry_selection_commands

    /// EVM-001-route_entry_selection_commands: Cmd+Delete는 부모와 하위 항목을 함께 선택해도 최상위 경로만 Trash 이동으로 계획한다.
    /// 키보드 삭제가 EntryOperationsCommandPlanner를 거쳐 parent+descendant 선택을 정규화하는지 검증한다.
    /// - 검증 내용: executeCommand mutation routing 뒤 moveToTrash payload가 부모 경로만 포함한다.
    /// - 사전 조건: /root/parent가 expanded이고 /root/parent/child와 부모가 함께 선택돼 있다.
    /// - 기대 결과: Cmd+Delete는 executeCommand(.mutation(.moveSelectedItemsToTrash))를 거쳐 부모 경로만 Trash 이동으로 계획한다.
    func testCommandDeletePlansOnlyTopmostSelectedPath() async {
        let parent = EntryModel.temporaryFolder(id: "/root/parent", name: "parent")
        let child = EntryModel.temporaryFolder(id: "/root/parent/child", name: "child")
        var state = FileManagerContentState()
        state.navigation.navigationState = .folder("/root")
        state.entryViewLayout.entries = [parent]
        state.entryViewLayout.selectedIds = [parent.id, child.id]
        state.entryViewLayout.hierarchy = .init(
            rootPath: "/root",
            nodesByID: [parent.id: .init(children: [child], loadPhase: .loaded, generation: 0)],
        )
        state.entryViewLayout.hierarchy.setExpandedIDs([parent.id])
        let store = TestStore(initialState: state) {
            FileManagerContentKeyCommandReducer()
        }

        await store.send(.view(.handleKeyCommand(.init(
            keyCode: 51,
            modifiers: [.command],
            characters: nil,
            charactersIgnoringModifiers: nil,
        ))))
        await store.receive(
            \.entryViewLayout.delegate.executeCommand,
            "mutation.moveSelectedItemsToTrash",
        )

        let outputs: [EntryOperationsCommandOutput] = EntryOperationsCommandPlanner.plan(
            command: .mutation(.moveSelectedItemsToTrash),
            context: .init(
                selectedIds: state.entryViewLayout.selectedIds,
                displayItems: state.entryViewLayout.visibleSelectableEntries(isNormalDirectoryPage: true),
                currentPath: state.navigation.currentPath,
            ),
        )
        XCTAssertEqual(outputs.count, 1)
        guard let output = outputs.first,
              case let .entryOperations(.trash(.moveToTrash(paths))) = output
        else {
            return XCTFail("Trash 이동 명령은 moveToTrash payload를 계획해야 합니다.")
        }
        XCTAssertEqual(paths, [parent.fullPath])
    }
}
