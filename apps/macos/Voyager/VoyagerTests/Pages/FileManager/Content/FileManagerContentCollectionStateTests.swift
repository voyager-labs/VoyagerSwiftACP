import Foundation
@testable import Voyager
import XCTest

@MainActor
final class FileManagerContentCollectionStateTests: XCTestCase {
    func testDirtyAndStaleStayIndependentIncludingInvalidLifecycleCombinations() {
        var state = FileManagerContentState()
        state.entryViewLayout.isCollectionMode = true

        let context = CollectionContext(query: "report", scopes: ["/tmp"], conditions: [])
        state.collectionContext = context
        state.collectionSession.baseline = .init(context: context)
        state.collectionSession.isStale = true
        state.collectionSession.staleReason = nil
        state.collectionSession.lastRefreshAt = .distantFuture

        XCTAssertFalse(state.isOpenedCollectionDirty)
        XCTAssertTrue(state.isOpenedCollectionStale)
        XCTAssertFalse(state.canSaveCollection)
        XCTAssertFalse(state.shouldRefreshOnOpen)

        state.collectionContext = CollectionContext(query: "updated", scopes: ["/tmp"], conditions: [])

        XCTAssertTrue(state.isOpenedCollectionDirty)
        XCTAssertTrue(state.isOpenedCollectionStale)
        XCTAssertTrue(state.canSaveCollection)
        XCTAssertNil(state.collectionSession.staleReason)
        XCTAssertEqual(state.collectionSession.lastRefreshAt, .distantFuture)
    }

    func testCanSaveCollectionStillTracksDirtyOnly() {
        var state = FileManagerContentState()
        state.entryViewLayout.isCollectionMode = true

        let baseline = CollectionContext(query: "report", scopes: ["/tmp"], conditions: [])
        state.collectionContext = CollectionContext(query: "updated", scopes: ["/tmp"], conditions: [])
        state.collectionSession.baseline = .init(context: baseline)
        state.collectionSession.isStale = true
        state.collectionSession.staleReason = .snapshotHydratedOnOpen

        XCTAssertTrue(state.isOpenedCollectionDirty)
        XCTAssertTrue(state.canSaveCollection)
        XCTAssertTrue(state.isOpenedCollectionStale)
    }

    func testShouldRefreshOnOpenRequiresHydratedStaleSnapshotWithoutRefresh() {
        var state = FileManagerContentState()

        XCTAssertFalse(state.shouldRefreshOnOpen)

        state.collectionSession.didHydrateSnapshotOnOpen = true
        XCTAssertEqual(
            state.collectionSession.phase,
            .opened(kind: .hydratedSnapshot, base: .ready, inflight: .none),
        )
        XCTAssertFalse(state.shouldRefreshOnOpen)

        state.collectionSession.isStale = true
        XCTAssertEqual(
            state.collectionSession.phase,
            .opened(kind: .hydratedSnapshot, base: .stale, inflight: .none),
        )
        XCTAssertTrue(state.shouldRefreshOnOpen)

        state.collectionSession.lastRefreshAt = nil

        XCTAssertTrue(state.shouldRefreshOnOpen)

        state.collectionSession.lastRefreshAt = Date()
        XCTAssertFalse(state.shouldRefreshOnOpen)

        state.collectionSession.lastRefreshAt = nil
        state.collectionSession.didHydrateSnapshotOnOpen = false
        XCTAssertEqual(
            state.collectionSession.phase,
            .opened(kind: .definition, base: .stale, inflight: .none),
        )
        XCTAssertFalse(state.shouldRefreshOnOpen)
    }

    func testRefreshMarkerDoesNotImplicitlyChangeDirtySemantics() {
        var state = FileManagerContentState()
        state.entryViewLayout.isCollectionMode = true

        let context = CollectionContext(query: "report", scopes: ["/tmp"], conditions: [])
        state.collectionContext = context
        state.collectionSession.baseline = .init(context: context)
        state.collectionSession.isStale = true
        state.collectionSession.staleReason = .invalidatedLocally
        state.collectionSession.didHydrateSnapshotOnOpen = true

        XCTAssertTrue(state.shouldRefreshOnOpen)
        XCTAssertFalse(state.canSaveCollection)

        state.collectionSession.lastRefreshAt = Date()

        XCTAssertFalse(state.shouldRefreshOnOpen)
        XCTAssertTrue(state.isOpenedCollectionStale)
        XCTAssertFalse(state.canSaveCollection)
    }

    func testRefreshBlockingReasonRequiresCleanSavedCollectionAndNoInflightWork() {
        var state = FileManagerContentState()
        state.entryViewLayout.isCollectionMode = true

        let context = CollectionContext(query: "report", scopes: ["/tmp"], conditions: [])
        state.collectionContext = context
        state.collectionSession.baseline = .init(context: context)
        state.collectionSession.openedURL = URL(fileURLWithPath: "/tmp/report.voycoll")
        state.collectionSession.isStale = true
        XCTAssertEqual(
            state.collectionSession.phase,
            .opened(kind: .definition, base: .stale, inflight: .none),
        )

        XCTAssertNil(state.refreshBlockingReason)

        state.collectionSession.isRefreshingHydratedSnapshot = true
        XCTAssertEqual(
            state.collectionSession.phase,
            .opened(kind: .definition, base: .stale, inflight: .refreshingHydratedSnapshot),
        )
        XCTAssertEqual(state.refreshBlockingReason, .refreshInFlight)

        state.collectionSession.isRefreshingHydratedSnapshot = false
        state.collectionSession.isWritingBackRefreshedSnapshot = true
        XCTAssertEqual(
            state.collectionSession.phase,
            .opened(kind: .definition, base: .stale, inflight: .writingBackRefreshedSnapshot),
        )
        XCTAssertEqual(state.refreshBlockingReason, .writeBackInFlight)

        state.collectionSession.isWritingBackRefreshedSnapshot = false
        state.collectionContext = CollectionContext(query: "updated", scopes: ["/tmp"], conditions: [])
        XCTAssertTrue(state.isOpenedCollectionDirty)
        XCTAssertEqual(state.refreshBlockingReason, .dirtyCollection)
    }

    func testRefreshBlockingReasonUsesDeterministicPriorityOrder() {
        var state = FileManagerContentState()

        XCTAssertEqual(state.refreshBlockingReason, .notInCollectionMode)

        state.entryViewLayout.isCollectionMode = true
        XCTAssertEqual(state.refreshBlockingReason, .notStale)

        let baseline = CollectionContext(query: "report", scopes: ["/tmp"], conditions: [])
        state.collectionSession.isStale = true
        state.collectionSession.openedURL = URL(fileURLWithPath: "/tmp/report.voycoll")
        state.collectionSession.baseline = .init(context: baseline)
        state.collectionContext = baseline

        XCTAssertNil(state.refreshBlockingReason)

        state.collectionContext = .init(query: "updated", scopes: ["/tmp"], conditions: [])
        state.collectionSession.isWritingBackRefreshedSnapshot = true
        state.collectionSession.openedURL = nil

        XCTAssertEqual(state.refreshBlockingReason, .dirtyCollection)

        state.collectionContext = baseline
        state.composer.isCollectionMode = true
        state.composer.isLoadingFilters = true
        XCTAssertEqual(state.refreshBlockingReason, .searchInFlight)

        state.composer.isLoadingFilters = false
        state.collectionSession.isWritingBackRefreshedSnapshot = false
        state.collectionSession.isRefreshingHydratedSnapshot = true
        XCTAssertEqual(state.refreshBlockingReason, .refreshInFlight)

        state.collectionSession.isRefreshingHydratedSnapshot = false
        state.collectionSession.isWritingBackRefreshedSnapshot = true
        XCTAssertEqual(state.refreshBlockingReason, .writeBackInFlight)

        state.collectionSession.isWritingBackRefreshedSnapshot = false
        XCTAssertEqual(state.refreshBlockingReason, .missingOpenedURL)

        state.collectionSession.openedURL = URL(fileURLWithPath: "/tmp/report.voycoll")
        state.collectionContext = nil
        XCTAssertEqual(state.refreshBlockingReason, .missingCollectionContext)

        state.collectionContext = baseline
        state.collectionSession.baseline = nil
        XCTAssertEqual(state.refreshBlockingReason, .missingBaseline)
    }
}
