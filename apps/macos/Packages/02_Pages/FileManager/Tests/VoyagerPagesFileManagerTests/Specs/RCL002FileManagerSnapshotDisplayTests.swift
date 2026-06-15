@_spi(Internals) import ComposableArchitecture
import Foundation
import VoyagerEntitiesCollection
import VoyagerFeaturesContentPageNavigation
@testable import VoyagerPagesFileManager
import VoyagerShared
import XCTest

@MainActor
final class RCL002FileManagerSnapshotDisplayTests: XCTestCase {
    // MARK: - RCL-002-show_restored_collection_snapshot

    /// RCL-002-show_restored_collection_snapshot: snapshot-bearing collection open은 저장 snapshot path를 content list에 적용함
    /// FileManager window open reducer가 hydrated snapshot payload를 entry view layout 검색 path 적용 action으로 라우팅하는지 검증한다.
    /// - 검증 내용: collection file load 후 collection navigation, collection mode, snapshot path 적용 action 수신
    /// - 사전 조건: snapshotMeta fingerprint가 현재 definition과 일치하는 `.voycoll` equivalent file load result
    /// - 기대 결과: snapshot-first display를 위해 `applyCollectionSearchPaths`가 저장된 snapshot path로 호출됨
    func testShowRestoredCollectionSnapshot_withHydratedLoadResult_appliesSnapshotPaths() async {
        let file = makeSnapshotFile()
        let loadResult = CollectionFileLoadResult(
            file: file,
            containerFormat: .package,
            compatibility: makeAllowedCompatibility(),
        )
        var initialState = FileManagerWindowState()
        initialState.content.collection.collectionSession.document = .init(
            url: URL(fileURLWithPath: "/VoyagerFixtures/Collections/snapshot.voycoll"),
            name: "snapshot",
            compatibility: makeAllowedCompatibility(),
        )

        let store = TestStore(initialState: initialState) {
            FileManagerNavigationActionReducer()
        } withDependencies: {
            $0.collectionAlertClient = .testValue
            $0.collectionStalenessClient = .testValue
            $0.registryClient = .testValue
        }
        // 이 suite는 window open effect의 라우팅을 검증하므로 composer/content child 내부 state diff는 제외한다.
        store.exhaustivity = .off

        await store.send(.navigation(.internal(.collectionFileLoaded(.success(loadResult)))))
        await store.receive(\.content.composer.view.setPresented)
        await store.receive(\.content.internal.requestNavigation)
        await store.receive(\.content.internal.applyNavigationState)
        await store.receive(\.content.entryViewLayout.internal.setCollectionMode)
        await store.receive(\.content.composer.internal.syncCollectionState)
        await store.receive(\.content.entryViewLayout.internal.applyCollectionSearchPaths)
        await store.receive(\.content.composer.internal.searchListApplied)
        await store.finish()
    }

    // MARK: - RCL-002-alert_unsaved_collection_filter_changes

    /// RCL-002-alert_unsaved_collection_filter_changes: dirty collection navigation은 unsaved alert로 라우팅됨
    /// 저장되지 않은 collection filter 변경이 있을 때 window navigation reducer가 alert action을 내보내는지 검증한다.
    /// - 검증 내용: goBack navigation request가 performNavigation 대신 showUnsavedNavigationAlert로 전환됨
    /// - 사전 조건: collection mode이며 현재 context가 baseline과 달라 저장 가능한 dirty 상태
    /// - 기대 결과: pending back navigation을 포함한 unsaved alert action이 수신됨
    func testAlertUnsavedCollectionFilterChanges_withDirtyCollection_routesToUnsavedAlert() async {
        let store = TestStore(initialState: makeDirtyWindowState()) {
            FileManagerNavigationActionReducer()
        } withDependencies: {
            $0.collectionAlertClient = .testValue
        }

        await store.send(.navigation(.view(.goBack)))
        await store.receive(\.navigation.internal.showUnsavedNavigationAlert)
        await store.receive(\.navigation.internal.unsavedNavigationAlertResponse)
        await store.finish()
    }

    private func makeSnapshotFile() -> VoyagerCollectionFile {
        let base = VoyagerCollectionFile(
            id: "rcl-filemanager-snapshot",
            name: "RCL FileManager Snapshot",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100),
            query: "design review",
            scopes: ["/VoyagerFixtures/Projects"],
            excludedScopes: [],
            includeSubfolders: true,
            includeDirectories: true,
            conditions: [],
            snapshot: CollectionPersistedSnapshot(items: [
                .string("/VoyagerFixtures/Projects/RCL/spec.md"),
                .string("/VoyagerFixtures/Projects/RCL/notes.txt"),
            ]),
            snapshotMeta: nil,
            appVersion: "VOY-346-test",
        )
        return VoyagerCollectionFile(
            id: base.id,
            name: base.name,
            createdAt: base.createdAt,
            updatedAt: base.updatedAt,
            query: base.query,
            scopes: base.scopes,
            excludedScopes: base.excludedScopes,
            includeSubfolders: base.includeSubfolders,
            includeDirectories: base.includeDirectories,
            conditions: base.conditions,
            snapshot: base.snapshot,
            snapshotMeta: CollectionSnapshotMeta(
                definitionFingerprint: CollectionSnapshotHydration.definitionFingerprint(file: base),
                capturedAt: Date(timeIntervalSince1970: 1_700_000_200),
                itemCount: 2,
                relevanceRoots: ["/VoyagerFixtures/Projects"],
            ),
            appVersion: base.appVersion,
        )
    }

    private func makeDirtyWindowState() -> FileManagerWindowState {
        let baseline = CollectionContext(query: "baseline", scopes: ["/VoyagerFixtures/Documents"], conditions: [])
        let current = CollectionContext(query: "changed", scopes: ["/VoyagerFixtures/Documents"], conditions: [])
        var state = FileManagerWindowState()
        state.content.entryViewLayout.isCollectionMode = true
        state.content.collection.collectionContext = current
        state.content.collection.collectionSession.document = .init(
            url: URL(fileURLWithPath: "/VoyagerFixtures/Collections/dirty.voycoll"),
            name: "dirty",
            compatibility: makeAllowedCompatibility(),
        )
        state.content.collection.collectionSession.metadata.baseline = .init(context: baseline)
        state.content.collection.collectionSession.phase = .opened(kind: .definition, base: .ready, inflight: .none)
        return state
    }

    private func makeAllowedCompatibility() -> CollectionFileCompatibilityMetadata {
        .init(
            sourceSchemaVersion: CollectionFileSchemaVersion.snapshotBearingCurrent,
            migrationPath: [.currentSchemaV2],
            warnings: [],
            usedDefinitionFallback: false,
            writeBackAllowed: true,
            writeBackReason: .allowed,
        )
    }
}
