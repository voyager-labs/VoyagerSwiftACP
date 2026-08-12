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

    /// EVM-002-set_entries_view_as_list_table: hierarchy expand는 lexical parent edge와 rootPath를 순서대로 전달한다.
    /// 깊은 alias hierarchy를 확장할 때 canonical resolution 없이 lexical ancestor URL을 요청하는지 검증한다.
    /// - 검증 내용: depth-2 parentID chain이 root-to-leaf 순서로 request에 포함된다.
    /// - 사전 조건: /alias/parent/child 노드와 /alias rootPath가 준비돼 있다.
    /// - 기대 결과: ancestorPaths는 [/alias, /alias/parent]다.
    func testHierarchyExpandSendsOrderedLexicalAncestors() async {
        let rootID = "/alias"
        let parentID = "/alias/parent"
        let folderID = "/alias/parent/child"
        var state = FileManagerContentState()
        state.entryViewLayout.hierarchy = .init(
            rootPath: rootID,
            nodesByID: [
                parentID: .init(parentID: rootID),
                folderID: .init(parentID: parentID, generation: 3),
            ],
        )
        let store = TestStore(initialState: state) {
            FileManagerContentEntryOperationsBridgeReducer()
        }

        await store.send(.entryViewLayout(.delegate(.expandRequested(folderID))))
        await store.receive { action in
            guard case let .entryOperations(.loading(.loadFolderItems(request))) = action else { return false }
            return request.ancestorPaths == [rootID, parentID]
        }
    }

    /// EVM-002-set_entries_view_as_list_table: malformed parentID cycle은 ancestry 요청을 유한하게 만든다.
    /// 순환 parentID가 있어도 retry request가 중복 없이 종료되는지 검증한다.
    /// - 검증 내용: visited lexical ID set이 cycle 재방문을 차단한다.
    /// - 사전 조건: /cycle/a와 /cycle/b가 서로를 parentID로 가리킨다.
    /// - 기대 결과: request가 중복 ID 없이 발행되고 reducer가 종료된다.
    func testHierarchyRetryTerminatesOnMalformedParentCycle() async {
        let firstID = "/cycle/a"
        let secondID = "/cycle/b"
        var state = FileManagerContentState()
        state.entryViewLayout.hierarchy = .init(
            rootPath: "/cycle",
            nodesByID: [
                firstID: .init(parentID: secondID, generation: 4),
                secondID: .init(parentID: firstID),
            ],
        )
        let store = TestStore(initialState: state) {
            FileManagerContentEntryOperationsBridgeReducer()
        }

        await store.send(.entryViewLayout(.delegate(.retryRequested(firstID))))
        await store.receive { action in
            guard case let .entryOperations(.loading(.loadFolderItems(request))) = action else { return false }
            return request.ancestorPaths == ["/cycle", secondID]
        }
    }
}
