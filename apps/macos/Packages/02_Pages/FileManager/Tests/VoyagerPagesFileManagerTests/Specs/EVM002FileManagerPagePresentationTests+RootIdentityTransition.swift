import ComposableArchitecture
import Foundation
import VoyagerEntitiesEntry
import VoyagerFeaturesContentPageNavigation
@testable import VoyagerFeaturesEntryOperations
@testable import VoyagerPagesFileManager
import XCTest

extension EVM002FileManagerPagePresentationTests {
    /// EVM-002-command_external_refresh_correlation: buffered root reload은 terminal commit 후에만 identity selection을 옮긴다.
    /// - 검증 내용: coreBatch의 candidate 축적 중에는 before 선택과 전이를 유지하고, streamFinished가 candidate를 commit한 뒤 after 선택으로 한 번
    /// 이동한다.
    /// - 사전 조건: before→after root 전이와 preserved directory reload candidate가 있다.
    /// - 기대 결과: coreBatch 후 before 선택 유지, streamFinished 후 after 선택 및 전이 소비.
    func testBufferedRootReloadMigratesIdentitySelectionAfterTerminalCommit() async {
        let rootPath = "/root"
        let before = EntryModel.temporaryFolder(id: "\(rootPath)/before", name: "before")
        let after = EntryModel.temporaryFolder(id: "\(rootPath)/after", name: "after")
        var state = rootTransitionState(rootPath: rootPath, before: before, afterPath: after.id)
        state.entryViewLayout.entryOperations.loadingContext.preservedDirectoryReloadItems = []
        let store = makeFileManagerContentFeatureStore(initialState: state)
        store.exhaustivity = .off

        await store.send(.entryViewLayout(.entryOperations(.loading(.streamEvent(.init(
            generation: 1,
            event: .coreBatch(items: [after], batchIndex: 0),
        ))))))
        XCTAssertEqual(store.state.entryViewLayout.selectedIds, [before.id])
        XCTAssertNotNil(store.state.pendingIdentityTransition)

        await store.send(.entryViewLayout(.entryOperations(.loading(.streamEvent(.init(
            generation: 1,
            event: .coreFinished(batchCount: 1),
        ))))))
        await store.send(.entryViewLayout(.entryOperations(.loading(.streamFinished(generation: 1)))))
        XCTAssertEqual(store.state.entryViewLayout.selectedIds, [after.id])
        XCTAssertNil(store.state.pendingIdentityTransition)
        await store.receive(\.entryViewLayout.delegate.selectionChanged)
    }

    /// EVM-002-command_external_refresh_correlation: partial root stream failure는 stale identity transition을 폐기한다.
    /// - 검증 내용: after-path 없는 current root coreBatch 뒤 streamFailed가 transition을 유지하지 않는다.
    /// - 사전 조건: before 선택과 current root generation identity transition이 있다.
    /// - 기대 결과: partial failure 후 pendingIdentityTransition이 nil이다.
    func testPartialRootStreamFailureDiscardsIdentityTransition() async {
        let rootPath = "/root"
        let before = EntryModel.temporaryFolder(id: "\(rootPath)/before", name: "before")
        let unrelated = EntryModel.temporaryFolder(id: "\(rootPath)/unrelated", name: "unrelated")
        let store = makeFileManagerContentFeatureStore(initialState: rootTransitionState(
            rootPath: rootPath,
            before: before,
            afterPath: "\(rootPath)/after",
        ))
        store.exhaustivity = .off

        await store.send(.entryViewLayout(.entryOperations(.loading(.streamEvent(.init(
            generation: 1,
            event: .coreBatch(items: [unrelated], batchIndex: 0),
        ))))))
        XCTAssertNotNil(store.state.pendingIdentityTransition)

        await store.send(.entryViewLayout(.entryOperations(.loading(.streamFailed(generation: 1)))))
        XCTAssertNil(store.state.pendingIdentityTransition)
        await store.receive(\.entryViewLayout.internal.reconcileHierarchySelection)
    }

    private func rootTransitionState(
        rootPath: String,
        before: EntryModel,
        afterPath: String,
    ) -> FileManagerContentState {
        var state = FileManagerContentState()
        state.navigation.seedInitialFolderPath(rootPath)
        state.entryViewLayout.hierarchy.replaceRoot(path: rootPath)
        state.entryViewLayout.entryOperations.items = [before]
        state.entryViewLayout.entries = [before]
        state.entryViewLayout.selectedIds = [before.id]
        state.entryViewLayout.lastSelectedId = before.id
        state.entryViewLayout.rangeAnchorId = before.id
        state.entryViewLayout.entryOperations.loadingContext.generation = 1
        state.entryViewLayout.entryOperations.isReloading = true
        state.pendingIdentityTransition = .init(
            recordID: UUID(),
            beforePath: before.id,
            afterPath: afterPath,
            rootPath: rootPath,
            refreshGeneration: 1,
        )
        return state
    }
}
