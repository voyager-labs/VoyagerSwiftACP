import ComposableArchitecture
import Foundation
@testable import Voyager
import VoyagerShared
import XCTest

@MainActor
final class FileManagerContentRefreshStaleTests: XCTestCase {
    func testRefreshStaleCollectionStartsRefreshingAndClearsWriteBackFlag() async {
        let store = makeRefreshStore(initialState: makeRefreshState())

        XCTAssertNil(store.state.refreshBlockingReason)

        await store.send(.view(.refreshStaleCollection)) {
            $0.collectionSession.phase = .opened(
                kind: .hydratedSnapshot,
                base: .stale,
                inflight: .refreshingHydratedSnapshot,
            )
        }
        XCTAssertEqual(store.state.refreshBlockingReason, .refreshInFlight)
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

    func testRefreshFailureClearsInflightFlagsButKeepsStaleLifecycle() async {
        struct RefreshError: Error {}

        let requestID = UUID()
        let store = makeHydratedRefreshStore(initialState: makeRefreshState(
            requestID: requestID,
            isRefreshing: true,
        ))

        await store.send(.composer(.internal(.filtersResponse(requestID, .failure(RefreshError()))))) {
            $0.collectionSession.phase = .refreshFailed(kind: .hydratedSnapshot)
        }
        await store.finish()

        XCTAssertTrue(store.state.collectionSession.isStale)
        XCTAssertNil(store.state.collectionSession.lastRefreshAt)
        XCTAssertNotEqual(store.state.collectionSession.inflightStatus, .refreshingHydratedSnapshot)
        XCTAssertNotEqual(store.state.collectionSession.inflightStatus, .writingBackRefreshedSnapshot)
        XCTAssertNil(store.state.refreshBlockingReason)
    }

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
            $0.collectionSession.phase = .opened(
                kind: .hydratedSnapshot,
                base: .stale,
                inflight: .writingBackRefreshedSnapshot,
            )
        }
        XCTAssertEqual(store.state.refreshBlockingReason, .writeBackInFlight)
    }

    private func makeRefreshState(
        requestID: UUID? = nil,
        isRefreshing: Bool = false,
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
        state.collectionSession.openedURL = URL(fileURLWithPath: "/tmp/voyager/sample.voycoll")
        state.collectionSession.openedName = "sample"
        state.collectionSession.phase = .opened(kind: .hydratedSnapshot, base: .stale, inflight: .none)
        state.collectionSession.phase = .opened(
            kind: .hydratedSnapshot,
            base: .stale,
            inflight: isRefreshing ? .refreshingHydratedSnapshot : .none,
        )
        state.collectionSession.openedCompatibility = makeAllowedCompatibility()
        state.collectionContext = makeReportContext()
        state.collectionSession.baseline = state.collectionContext.map(CollectionBaseline.init(context:))
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
            sourceSchemaVersion: 2,
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
