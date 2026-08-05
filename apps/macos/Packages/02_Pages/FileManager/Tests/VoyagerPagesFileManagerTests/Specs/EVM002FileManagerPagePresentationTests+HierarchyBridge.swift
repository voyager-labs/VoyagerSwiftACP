import ComposableArchitecture
@testable import VoyagerPagesFileManager
import XCTest

extension EVM002FileManagerPagePresentationTests {
    /// EVM-002-set_entries_view_as_list_table: 기본 arrangement는 metadata probe를 요청하지 않는다.
    /// - 검증 내용: Name 정렬과 No Group의 root metadata priority를 확인한다.
    /// - 사전 조건: metadata 기반 sort/group이 선택되지 않았다.
    /// - 기대 결과: priority가 `.none`이다.
    func testDefaultArrangementUsesNoMetadataPriority() {
        XCTAssertEqual(
            FileManagerContentEntryOpsCoordinator.rootMetadataPriority(sortKey: .name, groupKey: .none),
            .none,
        )
    }

    /// EVM-002-set_entries_view_as_list_table: hierarchy expand가 metadata 정렬 priority를 보존한다.
    /// - 검증 내용: expandRequested가 active Spotlight priority의 folder load를 발행한다.
    /// - 사전 조건: Kind 정렬과 generation이 있는 folder row가 준비돼 있다.
    /// - 기대 결과: loadFolderItems request가 `.active([.spotlight])`를 가진다.
    func testHierarchyExpandUsesArrangementMetadataPriority() async {
        let folderID = "/root/folder"
        var state = FileManagerContentState()
        state.entryArrangements.sortKey = .kind
        state.entryViewLayout.hierarchy.nodesByID[folderID] = .init(generation: 3)
        let store = TestStore(initialState: state) {
            FileManagerContentEntryOperationsBridgeReducer()
        }

        await store.send(.entryViewLayout(.delegate(.expandRequested(folderID))))
        await store.receive { action in
            guard case let .entryOperations(.loading(.loadFolderItems(request))) = action else { return false }
            return request.folderGeneration == 3 && request.priority == .active([.spotlight])
        }
    }

    /// EVM-002-set_entries_view_as_list_table: hierarchy retry가 metadata grouping priority를 보존한다.
    /// - 검증 내용: retryRequested가 active Tags priority의 folder load를 발행한다.
    /// - 사전 조건: Tags grouping과 failed folder generation이 준비돼 있다.
    /// - 기대 결과: loadFolderItems request가 `.active([.tags])`를 가진다.
    func testHierarchyRetryUsesArrangementMetadataPriority() async {
        let folderID = "/root/folder"
        var state = FileManagerContentState()
        state.entryArrangements.groupKey = .tags
        state.entryViewLayout.hierarchy.nodesByID[folderID] = .init(generation: 4)
        let store = TestStore(initialState: state) {
            FileManagerContentEntryOperationsBridgeReducer()
        }

        await store.send(.entryViewLayout(.delegate(.retryRequested(folderID))))
        await store.receive { action in
            guard case let .entryOperations(.loading(.loadFolderItems(request))) = action else { return false }
            return request.folderGeneration == 4 && request.priority == .active([.tags])
        }
    }
}
