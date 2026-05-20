import ComposableArchitecture
import Foundation
@testable import Voyager
import VoyagerEntitiesCollection
@testable import VoyagerFeaturesComposer
import VoyagerShared
import XCTest

@MainActor
final class ComposerInternalActionTests: XCTestCase {
    // MARK: - applyCollectionDraftRestore

    /// testApplyCollectionDraftRestoreSetsFieldsFromPayload 테스트 동작을 검증한다.
    func testApplyCollectionDraftRestoreSetsFieldsFromPayload() async {
        let context = CollectionContext(query: "test query", scopes: ["/tmp"], conditions: [])
        let payload = CollectionDraftRestorePayload(context: context, openedURL: nil)

        let store = TestStore(initialState: ComposerState()) {
            ComposerFeature()
        }

        await store.send(ComposerAction.applyCollectionDraftRestore(payload)) {
            $0.pendingSearchQuery = "test query"
            $0.text = "test query"
            $0.scopes = ["/tmp"]
            $0.conditions = []
        }
    }

    /// testApplyCollectionDraftRestoreWithOpenedURLClearsText 테스트 동작을 검증한다.
    func testApplyCollectionDraftRestoreWithOpenedURLClearsText() async {
        let context = CollectionContext(query: "saved search", scopes: ["/Users"], conditions: [])
        let payload = CollectionDraftRestorePayload(
            context: context,
            openedURL: URL(fileURLWithPath: "/test.collection"),
        )

        let store = TestStore(initialState: ComposerState()) {
            ComposerFeature()
        }

        await store.send(ComposerAction.applyCollectionDraftRestore(payload)) {
            $0.pendingSearchQuery = "saved search"
            $0.text = ""
            $0.scopes = ["/Users"]
            $0.conditions = []
        }
    }

    /// testApplyCollectionDraftRestoreClearsHistory 테스트 동작을 검증한다.
    func testApplyCollectionDraftRestoreClearsHistory() async {
        var initialState = ComposerState()
        initialState.history = [FilterSnapshot(scopes: ["/old"], conditions: [], conditionDisplayByKey: [:])]
        initialState.redoHistory = [FilterSnapshot(scopes: ["/redo"], conditions: [], conditionDisplayByKey: [:])]

        let context = CollectionContext(query: "new query", scopes: ["/new"], conditions: [])
        let payload = CollectionDraftRestorePayload(context: context, openedURL: nil)

        let store = TestStore(initialState: initialState) {
            ComposerFeature()
        }

        await store.send(ComposerAction.applyCollectionDraftRestore(payload)) {
            $0.pendingSearchQuery = "new query"
            $0.text = "new query"
            $0.scopes = ["/new"]
            $0.conditions = []
            $0.history = []
            $0.redoHistory = []
        }
    }

    // MARK: - applyCollectionNavigationComposer

    /// testApplyCollectionNavigationComposerSetsFieldsFromPayload 테스트 동작을 검증한다.
    func testApplyCollectionNavigationComposerSetsFieldsFromPayload() async {
        let context = CollectionContext(query: "nav query", scopes: ["/nav"], conditions: [])
        let payload = CollectionNavigationStatePayload(
            context: context,
            document: nil,
            baseline: nil,
            composerText: "nav query",
            scopes: ["/nav"],
            conditions: [],
        )

        let store = TestStore(initialState: ComposerState()) {
            ComposerFeature()
        }

        await store.send(ComposerAction.applyCollectionNavigationComposer(payload)) {
            $0.pendingSearchQuery = "nav query"
            $0.text = "nav query"
            $0.scopes = ["/nav"]
            $0.conditions = []
        }
    }

    // MARK: - syncCollectionState

    /// testSyncCollectionStateSetsComposerFields 테스트 동작을 검증한다.
    func testSyncCollectionStateSetsComposerFields() async {
        let context = CollectionContext(query: "sync", scopes: [], conditions: [])
        let url = URL(fileURLWithPath: "/test.collection")
        let compatibility = CollectionFileCompatibilityMetadata(
            sourceSchemaVersion: CollectionFileSchemaVersion.current,
            migrationPath: [.currentSchemaV2],
            warnings: [],
            usedDefinitionFallback: false,
            writeBackAllowed: true,
            writeBackReason: .allowed,
        )

        let store = TestStore(initialState: ComposerState()) {
            ComposerFeature()
        }

        await store.send(ComposerAction.syncCollectionState(
            context: context,
            url: url,
            compatibility: compatibility,
            isCollectionMode: true,
        )) {
            $0.collectionContext = context
            $0.openedCollectionURL = url
            $0.openedCollectionCompatibility = compatibility
            $0.isCollectionMode = true
        }
    }

    // MARK: - updateLastFiltersResponse

    /// testUpdateLastFiltersResponseSetsResponse 테스트 동작을 검증한다.
    func testUpdateLastFiltersResponseSetsResponse() async {
        let response = VoyagerShared.SearchResponsePayload(
            itemCount: 42,
            appliedFilters: nil,
            items: nil,
            error: nil,
        )

        let store = TestStore(initialState: ComposerState()) {
            ComposerFeature()
        }

        await store.send(ComposerAction.updateLastFiltersResponse(response)) {
            $0.lastFiltersResponse = response
        }
    }

    // MARK: - clearPendingSearchQuery

    /// testClearPendingSearchQueryClearsQuery 테스트 동작을 검증한다.
    func testClearPendingSearchQueryClearsQuery() async {
        var initialState = ComposerState()
        initialState.pendingSearchQuery = "some pending query"

        let store = TestStore(initialState: initialState) {
            ComposerFeature()
        }

        await store.send(ComposerAction.clearPendingSearchQuery) {
            $0.pendingSearchQuery = nil
        }
    }

    // MARK: - setPendingSearchQuery

    /// testSetPendingSearchQuerySetsValue 테스트 동작을 검증한다.
    func testSetPendingSearchQuerySetsValue() async {
        let store = TestStore(initialState: ComposerState()) {
            ComposerFeature()
        }

        await store.send(ComposerAction.setPendingSearchQuery("new query")) {
            $0.pendingSearchQuery = "new query"
        }
    }

    /// testSetPendingSearchQueryClearsWithNil 테스트 동작을 검증한다.
    func testSetPendingSearchQueryClearsWithNil() async {
        var initialState = ComposerState()
        initialState.pendingSearchQuery = "existing query"

        let store = TestStore(initialState: initialState) {
            ComposerFeature()
        }

        await store.send(ComposerAction.setPendingSearchQuery(nil)) {
            $0.pendingSearchQuery = nil
        }
    }

    // MARK: - setLoadingFilters

    /// testSetLoadingFiltersTrue 테스트 동작을 검증한다.
    func testSetLoadingFiltersTrue() async {
        let store = TestStore(initialState: ComposerState()) {
            ComposerFeature()
        }

        await store.send(ComposerAction.setLoadingFilters(true)) {
            $0.isLoadingFilters = true
        }
    }

    /// testSetLoadingFiltersFalse 테스트 동작을 검증한다.
    func testSetLoadingFiltersFalse() async {
        var initialState = ComposerState()
        initialState.isLoadingFilters = true

        let store = TestStore(initialState: initialState) {
            ComposerFeature()
        }

        await store.send(ComposerAction.setLoadingFilters(false)) {
            $0.isLoadingFilters = false
        }
    }

    // MARK: - setInitialScope

    /// testSetInitialScopeSetsSingleScope 테스트 동작을 검증한다.
    func testSetInitialScopeSetsSingleScope() async {
        var initialState = ComposerState()
        initialState.scopes = ["/old1", "/old2"]

        let store = TestStore(initialState: initialState) {
            ComposerFeature()
        }

        await store.send(ComposerAction.setInitialScope("/new/path")) {
            $0.scopes = ["/new/path"]
        }
    }

    // MARK: - resetComposerAndSync

    /// testResetComposerAndSyncResetsStateAndAppliesSync 테스트 동작을 검증한다.
    func testResetComposerAndSyncResetsStateAndAppliesSync() async {
        var initialState = ComposerState()
        initialState.text = "old query"
        initialState.scopes = ["/old"]
        initialState.pendingSearchQuery = "pending"
        initialState.isLoadingSearch = true

        let context = CollectionContext(query: "synced", scopes: [], conditions: [])
        let url = URL(fileURLWithPath: "/synced.collection")
        let compatibility = CollectionFileCompatibilityMetadata(
            sourceSchemaVersion: CollectionFileSchemaVersion.current,
            migrationPath: [.currentSchemaV2],
            warnings: [],
            usedDefinitionFallback: false,
            writeBackAllowed: true,
            writeBackReason: .allowed,
        )

        let store = TestStore(initialState: initialState) {
            ComposerFeature()
        }

        await store.send(ComposerAction.resetComposerAndSync(
            context: context,
            url: url,
            compatibility: compatibility,
            isCollectionMode: true,
        )) {
            $0 = ComposerState()
            $0.collectionContext = context
            $0.openedCollectionURL = url
            $0.openedCollectionCompatibility = compatibility
            $0.isCollectionMode = true
        }
    }

    // MARK: - searchListApplied (기존 액션, 통과 확인)

    /// testSearchListAppliedTransitionsPhase 테스트 동작을 검증한다.
    func testSearchListAppliedTransitionsPhase() async {
        var initialState = ComposerState()
        initialState.queryRenderPhase = .chipsAppliedPendingList

        let store = TestStore(initialState: initialState) {
            ComposerFeature()
        }

        await store.send(ComposerAction.searchListApplied) {
            $0.queryRenderPhase = .listApplied
        }
    }
}
