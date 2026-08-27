import ComposableArchitecture
import Foundation
import VoyagerEntitiesEntry
@testable import VoyagerWidgetsEntryViewLayout
import XCTest

extension EVM002ManageEntriesViewPresentationTests {
    /// EVM-002-replacement_reload_snapshot_retention: 완료된 폴더의 대체 재로드는 마지막 완전 스냅샷을 유지한다.
    /// - 검증 내용: startLoad가 loadingCore로 전환하되 완료 children을 보존하고 배치 추적만 초기화한다.
    /// - 사전 조건: /root/a가 children 2개를 가진 loaded 확장 폴더다.
    /// - 기대 결과: children은 그대로고 expectedBatchIndex는 0, coreFinished는 false다.
    func testReplacementReloadRetainsCompleteSnapshotUntilFirstNewBatch() {
        let folder = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        let old1 = replacementReloadFile(id: "/root/a/old-1", name: "old-1")
        let old2 = replacementReloadFile(id: "/root/a/old-2", name: "old-2")
        var state = replacementReloadState(folder: folder)
        state.hierarchy.nodesByID[folder.id as String] = .init(
            children: [old1, old2], loadPhase: .loaded, generation: 3,
        )
        state.hierarchy.setExpandedIDs([folder.id as String])

        _ = EntryListHierarchyReducer().reduce(
            into: &state,
            action: .hierarchy(.hierarchyInvalidated(affectedPaths: [folder.id as String], removedPrefixes: [])),
        )

        let node = state.hierarchy.nodesByID[folder.id as String]
        XCTAssertEqual(node?.folder.children, [old1, old2])
        XCTAssertEqual(node?.folder.expectedBatchIndex, 0)
        XCTAssertFalse(node?.folder.coreFinished ?? true)
        XCTAssertEqual(node?.loadPhase, .loadingCore)
        XCTAssertEqual(node?.generation, 4)
    }

    /// EVM-002-replacement_reload_snapshot_retention: 대체 재로드 재진입도 마지막 완전 스냅샷을 유지한다.
    /// - 검증 내용: 첫 재로드 뒤 같은 폴더를 다시 무효화해도 retained children과 선택을 보존한다.
    /// - 사전 조건: 선택된 child를 가진 완료 폴더가 첫 대체 재로드로 loadingCore 상태에 진입했다.
    /// - 기대 결과: 두 번째 세대 재시작 뒤에도 child와 선택은 유지되고 generation만 증가한다.
    func testReentrantReplacementReloadRetainsCompleteSnapshotAndSelection() {
        let folder = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        let retainedChild = replacementReloadFile(id: "/root/a/retained", name: "retained")
        var state = replacementReloadState(folder: folder)
        state.hierarchy.nodesByID[folder.id as String] = .init(
            children: [retainedChild], loadPhase: .loaded, generation: 3,
        )
        state.hierarchy.setExpandedIDs([folder.id as String])
        state.selectedIds = [retainedChild.id]
        let reducer = EntryListHierarchyReducer()

        _ = reducer.reduce(
            into: &state,
            action: .hierarchy(.hierarchyInvalidated(affectedPaths: [folder.id as String], removedPrefixes: [])),
        )
        _ = reducer.reduce(
            into: &state,
            action: .hierarchy(.hierarchyInvalidated(affectedPaths: [folder.id as String], removedPrefixes: [])),
        )

        let node = state.hierarchy.nodesByID[folder.id as String]
        XCTAssertEqual(node?.folder.children, [retainedChild])
        XCTAssertEqual(node?.folder.expectedBatchIndex, 0)
        XCTAssertFalse(node?.folder.hasAppliedContentBatch ?? true)
        XCTAssertEqual(node?.loadPhase, .loadingCore)
        XCTAssertEqual(node?.generation, 5)
        XCTAssertEqual(state.selectedIds, [retainedChild.id])
    }

    /// EVM-002-toggle_directory_expansion_in_list: canonical watcher path가 lexical hierarchy key를 다시 로드한다.
    /// symlink를 통해 연 folder가 실경로 이벤트를 받아도 expanded child cache가 stale로 남지 않는지 검증한다.
    /// - 검증 내용: `/private/var` affected path가 `/var` folder ID의 새 load request를 생성함
    /// - 사전 조건: 실제 symlink인 lexical `/var` folder가 expanded loaded 상태임
    /// - 기대 결과: lexical folder ID를 유지한 채 generation을 올리고 loading 상태로 전환함
    func testCanonicalInvalidationReloadsLexicalHierarchyFolder() async {
        let folder = EntryModel.temporaryFolder(id: "/var", name: "var")
        let staleChild = replacementReloadFile(id: "/var/stale.txt", name: "stale.txt")
        var state = EntryViewLayoutState()
        state.entries = [folder]
        state.hierarchy = .init(rootPath: "/")
        state.hierarchy.nodesByID = [
            folder.id: .init(children: [staleChild], loadPhase: .loaded, generation: 2),
        ]
        state.hierarchy.setExpandedIDs([folder.id])
        let store = TestStore(initialState: state) { EntryListHierarchyReducer() }

        await store.send(.hierarchy(.hierarchyInvalidated(
            affectedPaths: ["/private/var"],
            removedPrefixes: [],
        ))) {
            $0.hierarchy.nodesByID[folder.id as String] = FolderNodeState(
                folder: FolderSnapshot(
                    children: [staleChild],
                    retainsPreviousGenerationChildren: true,
                ),
                expansionIntent: true,
                generation: 3,
                loadPhase: .loadingCore,
            )
            $0.outlineProjectionRevision = 2
            $0.lastVisibleSelectableEntryIDs = [folder.id, staleChild.id]
            $0.lastReconciledOutlineProjection = $0.currentOutlineProjection()
        }
        await store.receive(\.delegate.expandRequested, folder.id)
    }

    /// EVM-002-toggle_directory_expansion_in_list: loading folder의 watcher invalidation은 stream을 재시작한다.
    /// 진행 중인 child snapshot이 외부 추가·삭제를 놓친 채 loaded로 고정되지 않는지 검증한다.
    /// - 검증 내용: loading parent의 generation 증가와 새 load request 생성
    /// - 사전 조건: expanded `/var` folder가 generation 2의 partial child stream을 로딩 중임
    /// - 기대 결과: 기존 children을 비우고 generation 3 load를 같은 lexical folder ID로 요청함
    func testInvalidationRestartsLoadingHierarchyFolder() async {
        let folder = EntryModel.temporaryFolder(id: "/var", name: "var")
        let partialChild = replacementReloadFile(id: "/var/partial.txt", name: "partial.txt")
        var state = EntryViewLayoutState()
        state.entries = [folder]
        state.hierarchy = .init(rootPath: "/")
        state.hierarchy.nodesByID = [
            folder.id: .init(
                children: [partialChild], loadPhase: .loadingCore, generation: 2, expectedBatchIndex: 1,
            ),
        ]
        state.hierarchy.setExpandedIDs([folder.id])
        let store = TestStore(initialState: state) { EntryListHierarchyReducer() }

        await store.send(.hierarchy(.hierarchyInvalidated(
            affectedPaths: ["/var/new.txt"],
            removedPrefixes: [],
        ))) {
            $0.hierarchy.nodesByID[folder.id as String] = .init(
                expansionIntent: true,
                generation: 3,
                loadPhase: .loadingCore,
            )
            $0.outlineProjectionRevision = 2
            $0.lastVisibleSelectableEntryIDs = [folder.id]
            $0.lastReconciledOutlineProjection = $0.currentOutlineProjection()
        }
        await store.receive(\.delegate.expandRequested, folder.id)
    }

    /// EVM-002-toggle_directory_expansion_in_list: coarse invalidation은 expanded descendant cache를 모두 재로드한다.
    /// ancestor path만 보고된 rescan에서도 중첩 folder snapshot이 stale로 남지 않는지 검증한다.
    /// - 검증 내용: cached folder 전체 generation 증가와 expanded A/B loading 전환
    /// - 사전 조건: A와 자식 B가 모두 expanded·loaded 상태임
    /// - 기대 결과: A/B children을 보존하고 각각 새 generation load를 시작함
    func testCoarseInvalidationReloadsExpandedDescendantCaches() async {
        let folderA = EntryModel.temporaryFolder(id: "/root/A", name: "A")
        let folderB = EntryModel.temporaryFolder(id: "/root/A/B", name: "B")
        let staleChild = replacementReloadFile(id: "/root/A/B/stale.txt", name: "stale.txt")
        var state = EntryViewLayoutState()
        state.entries = [folderA]
        state.hierarchy = .init(rootPath: "/root")
        state.hierarchy.nodesByID = [
            folderA.id: .init(
                folder: .init(children: [folderB], coreFinished: true),
                generation: 2,
                loadPhase: .loaded,
            ),
            folderB.id: .init(
                folder: .init(children: [staleChild], coreFinished: true),
                generation: 4,
                loadPhase: .loaded,
            ),
        ]
        state.hierarchy.setExpandedIDs([folderA.id, folderB.id])
        let store = TestStore(initialState: state) { EntryListHierarchyReducer() }
        store.exhaustivity = .off

        await store.send(.hierarchy(.coarseHierarchyInvalidated(
            removedPrefixes: [],
            retainsCompleteSnapshots: true,
        ))) {
            $0.hierarchy.nodesByID[folderA.id as String] = .init(
                folder: .init(children: [folderB], retainsPreviousGenerationChildren: true),
                expansionIntent: true,
                generation: 3,
                loadPhase: .loadingCore,
            )
            $0.hierarchy.nodesByID[folderB.id as String] = .init(
                folder: .init(children: [staleChild], retainsPreviousGenerationChildren: true),
                parentID: folderA.id,
                expansionIntent: true,
                generation: 5,
                loadPhase: .loadingCore,
            )
            $0.outlineProjectionRevision = 3
        }
        await store.skipReceivedActions()
        await store.finish()
    }

    private func replacementReloadState(folder: EntryModel) -> EntryViewLayoutState {
        var state = EntryViewLayoutState()
        state.entries = [folder]
        state.hierarchy = .init(rootPath: "/root")
        return state
    }

    private func replacementReloadFile(id: String, name: String) -> EntryModel {
        EntryModel(
            name: name,
            fullPath: id,
            isFolder: false,
            isHidden: false,
            size: 0,
            modifiedDate: Date(timeIntervalSince1970: 1_700_000_000),
            fileExtension: "txt",
            facets: .init(
                createdDate: Date(timeIntervalSince1970: 1_700_000_000),
                addedDate: Date(timeIntervalSince1970: 1_700_000_000),
                lastOpenedDate: nil,
                kind: "Text",
                creatorApplication: nil,
                tags: nil,
                supplementaryMetadata: nil,
            ),
        )
    }
}
