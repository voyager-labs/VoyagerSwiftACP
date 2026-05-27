import ComposableArchitecture
import Foundation
@testable import Voyager
import VoyagerEntitiesCollection
import VoyagerFeaturesComposer
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryArrangements
@testable import VoyagerPagesFileManager
import VoyagerShared
import XCTest

/// FileManager content에서 stale 상태 전환과 write-back 경계를 검증한다.
@MainActor
final class FileManagerContentRefreshStaleTests: XCTestCase {
    /// testRefreshStaleCollectionStartsRefreshingAndClearsWriteBackFlag 시나리오가 FileManager 계약을 위반하지 않음을 검증한다.
    func testRefreshStaleCollectionStartsRefreshingAndClearsWriteBackFlag() async {
        let store = makeRefreshStore(initialState: makeRefreshState())

        XCTAssertNil(store.state.collection.refreshBlockingReason(
            isCollectionMode: store.state.isCollectionMode,
            isDirty: store.state.isOpenedCollectionDirty,
            isSearching: store.state.composer.isCollectionSearching,
        ))

        await store.send(.view(.refreshStaleCollection)) {
            $0.collection.collectionSession.phase = .opened(
                kind: .hydratedSnapshot,
                base: .stale,
                inflight: .refreshingHydratedSnapshot,
            )
        }
        XCTAssertEqual(store.state.collection.refreshBlockingReason(
            isCollectionMode: store.state.isCollectionMode,
            isDirty: store.state.isOpenedCollectionDirty,
            isSearching: store.state.composer.isCollectionSearching,
        ), .refreshInFlight)
        await store.receive { action in
            guard case .composer(.view(.setText("report"))) = action else {
                return false
            }
            return true
        }
        await store.receive { action in
            guard case .composer(.view(.submit)) = action else {
                return false
            }
            return true
        }
    }

    /// testRefreshFailureClearsInflightFlagsButKeepsStaleLifecycle 시나리오가 FileManager 계약을 위반하지 않음을 검증한다.
    func testRefreshFailureClearsInflightFlagsButKeepsStaleLifecycle() async {
        struct RefreshError: Error {}

        let requestID = UUID()
        let store = makeHydratedRefreshStore(initialState: makeRefreshState(
            requestID: requestID,
            isRefreshing: true,
        ))

        await store.send(.composer(.internal(.filtersResponse(requestID, .failure(RefreshError()))))) {
            $0.collection.collectionSession.phase = .refreshFailed(kind: .hydratedSnapshot)
        }
        await store.finish()

        XCTAssertTrue(store.state.collection.collectionSession.phase.isStale)
        XCTAssertNil(store.state.collection.collectionSession.metadata.lastRefreshAt)
        XCTAssertNotEqual(store.state.collection.collectionSession.phase.inflightStatus, .refreshingHydratedSnapshot)
        XCTAssertNotEqual(store.state.collection.collectionSession.phase.inflightStatus, .writingBackRefreshedSnapshot)
        XCTAssertNil(store.state.collection.refreshBlockingReason(
            isCollectionMode: store.state.isCollectionMode,
            isDirty: store.state.isOpenedCollectionDirty,
            isSearching: store.state.composer.isCollectionSearching,
        ))
    }

    /// testRefreshSuccessTransitionsFromRefreshingToWriteBackBeforeSaveCompletes 시나리오가 FileManager 계약을 위반하지 않음을 검증한다.
    func testRefreshSuccessTransitionsFromRefreshingToWriteBackBeforeSaveCompletes() async {
        let requestID = UUID()
        let response = makeRefreshResponse()
        let store = makeHydratedRefreshStore(initialState: makeRefreshState(
            requestID: requestID,
            isRefreshing: true,
        ))

        await store.send(.composer(.internal(.filtersResponse(requestID, .success(response))))) {
            $0.composer.lastFiltersResponse = response
            $0.composer.isLoadingFilters = false
            $0.collection.collectionSession.phase = .opened(
                kind: .hydratedSnapshot,
                base: .stale,
                inflight: .writingBackRefreshedSnapshot,
            )
        }
        XCTAssertEqual(store.state.collection.refreshBlockingReason(
            isCollectionMode: store.state.isCollectionMode,
            isDirty: store.state.isOpenedCollectionDirty,
            isSearching: store.state.composer.isCollectionSearching,
        ), .writeBackInFlight)
    }

    private func makeRefreshState(
        requestID: UUID? = nil,
        isRefreshing _: Bool = false,
    ) -> FileManagerContentState {
        var state = FileManagerContentState()
        state.entryViewLayout.isCollectionMode = true
        state.navigation.navigationState = .collection(
            .init(
                kind: .temporary,
                context: makeReportContext(),
                sortKey: .name,
                sortOrder: .ascending,
                viewLayout: .list,
            ),
        )
        state.collection.collectionSession.document = .init(
            url: URL(fileURLWithPath: "/tmp/voyager/sample.voycoll"),
            name: "sample",
            compatibility: makeAllowedCompatibility(),
        )
        state.collection.collectionSession.metadata.baseline = state.collection.collectionContext
            .map { CollectionBaseline(context: $0) }
        state.composer.scopes = ["/tmp/voyager"]
        state.composer.conditions = []
        state.composer.pendingSearchQuery = "report"
        if let requestID {
            state.composer.lastAcceptedFiltersRequestID = requestID
        }
        return state
    }

    private func makeRefreshStore(
        initialState: FileManagerContentState,
    ) -> TestStore<FileManagerContentState, FileManagerContentAction> {
        let store = TestStore(initialState: initialState) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.searchClient = .testValue
        }
        store.exhaustivity = .off
        return store
    }

    private func makeHydratedRefreshStore(
        initialState: FileManagerContentState,
    ) -> TestStore<FileManagerContentState, FileManagerContentAction> {
        let store = TestStore(initialState: initialState) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.collectionAlertClient = .init(
                showUnsavedNavigationAlert: { .save },
                showCollectionOpenErrorAlert: { _, _ in },
            )
            $0.collectionFileClient = .testValue
            $0.collectionStalenessClient = .testValue
            $0.registryClient = .testValue
            $0.searchClient = .testValue
            $0.userDefaultsClient = .testValue
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        store.exhaustivity = .off
        return store
    }

    private func makeReportContext() -> CollectionContext {
        .init(query: "report", scopes: ["/tmp/voyager"], conditions: [])
    }

    private func makeAllowedCompatibility() -> CollectionFileCompatibilityMetadata {
        .init(
            sourceSchemaVersion: SchemaVersion(legacyInt: 2),
            migrationPath: [.currentSchemaV2],
            warnings: [],
            usedDefinitionFallback: false,
            writeBackAllowed: true,
            writeBackReason: .allowed,
        )
    }

    private func makeRefreshResponse() -> VoyagerShared.SearchResponsePayload {
        .init(
            itemCount: 1,
            appliedFilters: .init(scopes: ["/tmp/voyager"], conditions: []),
            items: [.object(["fullPath": .string("/tmp/voyager/report.txt")])],
            error: nil,
        )
    }
}
