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

    /// EVM-002-replacement_reload_snapshot_retention: 활성 identity 전이 중 presentation reload도 snapshot을 유지한다.
    /// hidden/sort/group 변경으로 expanded folder를 다시 로드해도 진행 중 replacement의 before 선택과
    /// retained child가 새 세대의 첫 batch까지 사라지지 않아야 한다.
    /// - 검증 내용: identityReplacement가 활성인 hidden-files reload에서 complete child snapshot 보존
    /// - 사전 조건: expanded loaded folder와 활성 identity replacement가 있다.
    /// - 기대 결과: generation만 증가하고 children은 유지된 채 loadingCore로 전환
    func testIdentityReplacementPresentationReloadRetainsExpandedSnapshot() {
        let folder = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        let retainedChild = replacementReloadFile(id: "/root/a/retained", name: "retained")
        var state = replacementReloadState(folder: folder)
        state.hierarchy.nodesByID[folder.id] = .init(
            children: [retainedChild],
            loadPhase: .loaded,
            generation: 3,
        )
        state.hierarchy.setExpandedIDs([folder.id])
        state.identityReplacement = .init(plan: .init(
            transactionID: UUID(),
            rootPath: "/root",
            pairs: [.init(beforePath: retainedChild.id, afterPath: "/root/a/after")],
        ))

        _ = EntryListHierarchyReducer().reduce(
            into: &state,
            action: .hierarchy(.hiddenFilesSettingChanged),
        )

        let node = state.hierarchy.nodesByID[folder.id]
        XCTAssertEqual(node?.generation, 4)
        XCTAssertEqual(node?.loadPhase, .loadingCore)
        XCTAssertEqual(node?.folder.children, [retainedChild])
        XCTAssertTrue(node?.folder.retainsPreviousGenerationChildren ?? false)
    }

    /// EVM-002-toggle_directory_expansion_in_list: identity replacement action owns source staging inside
    /// EntryViewLayout.
    /// FileManager supplies only an immutable before/after plan; the widget installs/cancels the source hold
    /// without exposing hierarchy mutators to the page reducer.
    /// - 검증 내용: begin action이 source folder hold를 만들고 cancel action이 orphan 없이 정리하는지 확인한다.
    /// - 사전 조건: source/destination expanded folder와 source child identity pair가 있다.
    /// - 기대 결과: action 경계 뒤 source deferred replacement가 생성·정리되고 hierarchy snapshot은 유지된다.
    func testIdentityReplacementActionOwnsSourceHoldLifecycle() async {
        let source = EntryModel.temporaryFolder(id: "/root/source", name: "source")
        let destination = EntryModel.temporaryFolder(id: "/root/destination", name: "destination")
        let before = replacementReloadFile(id: "/root/source/before.txt", name: "before.txt")
        var state = EntryViewLayoutState()
        state.entries = [source, destination]
        state.hierarchy = .init(rootPath: "/root")
        state.hierarchy.nodesByID[source.id] = .init(
            folder: .init(children: [before]),
            expansionIntent: true,
            generation: 2,
            loadPhase: .loadingCore,
        )
        state.hierarchy.nodesByID[destination.id] = .init(
            expansionIntent: true,
            generation: 2,
            loadPhase: .loadingCore,
        )
        state.hierarchy.setExpandedIDs([source.id, destination.id])
        let transactionID = UUID()
        let plan = EntryIdentityReplacementPlan(
            transactionID: transactionID,
            rootPath: "/root",
            pairs: [
                .init(
                    beforePath: before.id,
                    afterPath: "/root/destination/after.txt",
                ),
            ],
        )
        let store = TestStore(initialState: state) { EntryViewLayoutFeature() }
        store.exhaustivity = .off

        await store.send(.identityReplacement(.begin(plan)))
        XCTAssertNotNil(store.state.hierarchy.deferredFolderReplacement(folderID: source.id))
        XCTAssertEqual(store.state.identityReplacement?.plan.transactionID, transactionID)

        await store.send(.identityReplacement(.cancel(id: transactionID, reason: .superseded)))
        XCTAssertNil(store.state.hierarchy.deferredFolderReplacement(folderID: source.id))
        XCTAssertNil(store.state.identityReplacement)
    }

    /// EVM-002-replacement_reload_snapshot_retention: replacement 재진입은 이전 selection을 정산한다.
    /// 기존 transaction의 source staging을 커밋한 뒤 새 plan으로 교체할 때 stale before 선택을
    /// 남기지 않고 `.superseded` cancel과 동일한 reconcile/delegate 경계를 사용해야 한다.
    /// - 검증 내용: 이전 staging 커밋 후 before selection 제거, 새 plan 설치, selectionChanged 발행
    /// - 사전 조건: source folder의 기존 replacement와 staged children, 선택된 before row가 있다.
    /// - 기대 결과: 새 transaction만 남고 stale before 선택은 제거된다.
    func testIdentityReplacementBeginSettlesExistingSelection() async {
        let source = EntryModel.temporaryFolder(id: "/root/source", name: "source")
        let before = replacementReloadFile(id: "/root/source/before.txt", name: "before.txt")
        let kept = replacementReloadFile(id: "/root/source/kept.txt", name: "kept.txt")
        var state = EntryViewLayoutState()
        state.entries = [source]
        state.hierarchy = .init(rootPath: "/root")
        state.hierarchy.nodesByID[source.id] = .init(
            folder: .init(children: [before], coreFinished: true, hasAppliedContentBatch: true),
            expansionIntent: true,
            generation: 2,
            loadPhase: .loaded,
        )
        state.hierarchy.setExpandedIDs([source.id])
        state.hierarchy.deferredFolderReplacements[source.id] = .init(
            untilEntryID: "/root/old/after.txt",
            stagedChildren: [kept],
            holdsUntilMigration: true,
        )
        state.selectedIds = [before.id]
        state.lastSelectedId = before.id
        state.rangeAnchorId = before.id
        let previousTransactionID = UUID()
        let nextTransactionID = UUID()
        state.identityReplacement = .init(
            plan: .init(
                transactionID: previousTransactionID,
                rootPath: "/root",
                pairs: [.init(beforePath: before.id, afterPath: "/root/old/after.txt")],
            ),
            sourceFolderIDs: [source.id],
        )
        let nextPlan = EntryIdentityReplacementPlan(
            transactionID: nextTransactionID,
            rootPath: "/root",
            pairs: [.init(beforePath: kept.id, afterPath: "/root/next/after.txt")],
        )
        let store = TestStore(initialState: state) { EntryViewLayoutFeature() }
        store.exhaustivity = .off

        await store.send(.identityReplacement(.begin(nextPlan)))
        await store.receive(\.delegate.selectionChanged)

        XCTAssertEqual(store.state.identityReplacement?.plan.transactionID, nextTransactionID)
        XCTAssertTrue(store.state.selectedIds.isEmpty, "이전 staging 커밋으로 사라진 before 선택은 정산된다")
        XCTAssertNotNil(store.state.hierarchy.deferredFolderReplacement(folderID: source.id))
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

    /// EVM-002-replacement_reload_snapshot_retention: deferred commit 뒤 재시작 실패는 partial snapshot을 보존하지 않는다.
    /// - 검증 내용: after 도착으로 staged children을 커밋한 직후 invalidation과 실패를 순서대로 적용한다.
    /// - 사전 조건: 이전 완전 snapshot을 retained한 generation 4가 deferred after batch를 수신한다.
    /// - 기대 결과: commit 시 current provenance로 전환되고 generation 5 실패 뒤 partial children은 남지 않는다.
    func testDeferredCommitRestartFailureDoesNotRetainPartialSnapshot() {
        let folder = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        let old = replacementReloadFile(id: "/root/a/old", name: "old")
        let partial = replacementReloadFile(id: "/root/a/partial", name: "partial")
        let after = replacementReloadFile(id: "/root/a/after", name: "after")
        var state = replacementReloadState(folder: folder)
        state.hierarchy.nodesByID[folder.id] = .init(
            children: [old], loadPhase: .loaded, generation: 3,
        )
        state.hierarchy.setExpandedIDs([folder.id])
        let reducer = EntryListHierarchyReducer()

        _ = reducer.reduce(
            into: &state,
            action: .hierarchy(.hierarchyInvalidated(affectedPaths: [folder.id], removedPrefixes: [])),
        )
        state.hierarchy.beginDeferredFolderReplacement(folderID: folder.id, untilEntryID: after.id)
        _ = reducer.reduce(
            into: &state,
            action: .hierarchy(.folderChildrenResponse(
                rootContextGeneration: 0,
                folderID: folder.id,
                folderGeneration: 4,
                .event(.coreBatch(items: [partial, after], batchIndex: 0)),
            )),
        )
        XCTAssertEqual(state.hierarchy.nodesByID[folder.id]?.folder.children, [partial, after])
        XCTAssertFalse(state.hierarchy.nodesByID[folder.id]?.folder.retainsPreviousGenerationChildren ?? true)

        _ = reducer.reduce(
            into: &state,
            action: .hierarchy(.hierarchyInvalidated(affectedPaths: [folder.id], removedPrefixes: [])),
        )
        _ = reducer.reduce(
            into: &state,
            action: .hierarchy(.folderChildrenResponse(
                rootContextGeneration: 0,
                folderID: folder.id,
                folderGeneration: 5,
                .failed(.permissionDenied),
            )),
        )

        XCTAssertEqual(state.hierarchy.nodesByID[folder.id]?.folder.children, [])
        XCTAssertEqual(state.hierarchy.nodesByID[folder.id]?.loadPhase, .failed(.permissionDenied))
    }

    /// EVM-002-replacement_reload_snapshot_retention: terminal deferred commit은 stale descendant cache를 제거한다.
    /// - 검증 내용: after가 필터링된 replacement를 coreFinished에서 확정한 뒤 제거된 subtree cache를 검사한다.
    /// - 사전 조건: retained child subtree와 after를 기다리는 generation 4 deferred replacement가 있다.
    /// - 기대 결과: authoritative kept child만 남고 제거된 child와 descendant node는 모두 사라진다.
    func testTerminalDeferredCommitReconcilesStaleDescendants() {
        let folder = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        let removed = EntryModel.temporaryFolder(id: "/root/a/removed", name: "removed")
        let descendant = replacementReloadFile(id: "/root/a/removed/child", name: "child")
        let kept = replacementReloadFile(id: "/root/a/kept", name: "kept")
        var state = replacementReloadState(folder: folder)
        state.hierarchy.nodesByID[folder.id] = .init(
            children: [removed], loadPhase: .loaded, generation: 3,
        )
        state.hierarchy.nodesByID[removed.id] = .init(
            children: [descendant], loadPhase: .loaded, generation: 2,
        )
        state.hierarchy.nodesByID[descendant.id] = .init(
            parentID: removed.id, generation: 1, loadPhase: .loaded,
        )
        state.hierarchy.setExpandedIDs([folder.id, removed.id])
        let reducer = EntryListHierarchyReducer()

        _ = reducer.reduce(
            into: &state,
            action: .hierarchy(.hierarchyInvalidated(affectedPaths: [folder.id], removedPrefixes: [])),
        )
        state.hierarchy.beginDeferredFolderReplacement(
            folderID: folder.id,
            untilEntryID: "/root/a/.hidden-after",
        )
        _ = reducer.reduce(
            into: &state,
            action: .hierarchy(.folderChildrenResponse(
                rootContextGeneration: 0,
                folderID: folder.id,
                folderGeneration: 4,
                .event(.coreBatch(items: [kept], batchIndex: 0)),
            )),
        )
        _ = reducer.reduce(
            into: &state,
            action: .hierarchy(.folderChildrenResponse(
                rootContextGeneration: 0,
                folderID: folder.id,
                folderGeneration: 4,
                .event(.coreFinished(batchCount: 1)),
            )),
        )

        XCTAssertEqual(state.hierarchy.nodesByID[folder.id]?.folder.children, [kept])
        XCTAssertNil(state.hierarchy.nodesByID[removed.id])
        XCTAssertNil(state.hierarchy.nodesByID[descendant.id])
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

    /// EVM-002-toggle_directory_expansion_in_list: canonical invalidation은 모든 lexical alias를 재로드한다.
    /// 같은 실폴더를 가리키는 expanded symlink alias가 하나의 canonical affected path를 공유해도
    /// 한 alias만 restart하면 다른 alias가 이전 세대에 남으므로 두 hierarchy key를 함께 올린다.
    /// - 검증 내용: canonical-equivalent A/B의 generation과 retained snapshot을 동시에 갱신
    /// - 사전 조건: A/B alias folder가 모두 expanded·loaded 상태임
    /// - 기대 결과: A/B 모두 generation +1 및 loadingCore 전환
    func testCanonicalInvalidationReloadsAllLexicalAliases() throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let targetURL = rootURL.appendingPathComponent("target", isDirectory: true)
        let aliasAURL = rootURL.appendingPathComponent("alias-a")
        let aliasBURL = rootURL.appendingPathComponent("alias-b")
        try FileManager.default.createDirectory(at: targetURL, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: aliasAURL, withDestinationURL: targetURL)
        try FileManager.default.createSymbolicLink(at: aliasBURL, withDestinationURL: targetURL)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let aliasA = EntryModel.temporaryFolder(id: aliasAURL.path, name: "alias-a")
        let aliasB = EntryModel.temporaryFolder(id: aliasBURL.path, name: "alias-b")
        let staleA = replacementReloadFile(id: aliasAURL.appendingPathComponent("stale-a").path, name: "stale-a")
        let staleB = replacementReloadFile(id: aliasBURL.appendingPathComponent("stale-b").path, name: "stale-b")
        var state = EntryViewLayoutState()
        state.entries = [aliasA, aliasB]
        state.hierarchy = .init(rootPath: rootURL.path)
        state.hierarchy.nodesByID[aliasA.id] = .init(
            children: [staleA],
            loadPhase: .loaded,
            generation: 2,
        )
        state.hierarchy.nodesByID[aliasB.id] = .init(
            children: [staleB],
            loadPhase: .loaded,
            generation: 2,
        )
        state.hierarchy.setExpandedIDs([aliasA.id, aliasB.id])

        _ = EntryListHierarchyReducer().reduce(
            into: &state,
            action: .hierarchy(.hierarchyInvalidated(
                affectedPaths: [targetURL.path],
                removedPrefixes: [],
            )),
        )

        for (id, staleChild) in [(aliasA.id, staleA), (aliasB.id, staleB)] {
            let node = state.hierarchy.nodesByID[id]
            XCTAssertEqual(node?.generation, 3)
            XCTAssertEqual(node?.loadPhase, .loadingCore)
            XCTAssertEqual(node?.folder.children, [staleChild])
            XCTAssertTrue(node?.folder.retainsPreviousGenerationChildren ?? false)
        }
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
