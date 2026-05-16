import Foundation
@testable import Voyager
@testable import VoyagerPagesFileManager
import VoyagerEntitiesCollection
import VoyagerFeaturesComposer
import XCTest

@MainActor
final class FileManagerContentCollectionStateTests: XCTestCase {
    func testDirtyAndStaleStayIndependent() {
        var state = FileManagerContentState()
        state.entryViewLayout.isCollectionMode = true

        let context = CollectionContext(query: "report", scopes: ["/tmp"], conditions: [])
        state.collection.collectionContext = context
        state.collection.collectionSession.metadata.baseline = .init(context: context)
        state.collection.collectionSession.phase = .opened(kind: .definition, base: .stale, inflight: .none)
        state.collection.collectionSession.metadata.lastRefreshAt = .distantFuture

        XCTAssertFalse(state.isOpenedCollectionDirty)
        XCTAssertTrue(state.isCollectionMode && state.collection.collectionSession.phase.isStale)
        XCTAssertFalse(state.canSaveCollection)

        state.collection.collectionContext = .init(query: "updated", scopes: ["/tmp"], conditions: [])

        XCTAssertTrue(state.isOpenedCollectionDirty)
        XCTAssertTrue(state.isCollectionMode && state.collection.collectionSession.phase.isStale)
        XCTAssertTrue(state.canSaveCollection)
        XCTAssertEqual(state.collection.collectionSession.metadata.lastRefreshAt, .distantFuture)
    }

    func testCanSaveCollectionTracksDirtyOnly() {
        var state = FileManagerContentState()
        state.entryViewLayout.isCollectionMode = true

        let baseline = CollectionContext(query: "report", scopes: ["/tmp"], conditions: [])
        state.collection.collectionContext = .init(query: "updated", scopes: ["/tmp"], conditions: [])
        state.collection.collectionSession.metadata.baseline = .init(context: baseline)
        state.collection.collectionSession.phase = .opened(kind: .definition, base: .stale, inflight: .none)

        XCTAssertTrue(state.isOpenedCollectionDirty)
        XCTAssertTrue(state.canSaveCollection)
        XCTAssertTrue(state.isCollectionMode && state.collection.collectionSession.phase.isStale)
    }

    func testHydratedStaleSessionRefreshBoundaryUsesPhaseAndTimestamp() {
        var state = FileManagerContentState()

        XCTAssertFalse(shouldRefreshOnOpen(state.collection.collectionSession))

        state.collection.collectionSession.phase = .opened(kind: .hydratedSnapshot, base: .ready, inflight: .none)
        XCTAssertFalse(shouldRefreshOnOpen(state.collection.collectionSession))

        state.collection.collectionSession.phase = .opened(kind: .hydratedSnapshot, base: .stale, inflight: .none)
        XCTAssertTrue(shouldRefreshOnOpen(state.collection.collectionSession))

        state.collection.collectionSession.metadata.lastRefreshAt = Date()
        XCTAssertFalse(shouldRefreshOnOpen(state.collection.collectionSession))

        state.collection.collectionSession.metadata.lastRefreshAt = nil
        state.collection.collectionSession.phase = .opened(kind: .definition, base: .stale, inflight: .none)
        XCTAssertFalse(shouldRefreshOnOpen(state.collection.collectionSession))
    }

    func testRefreshBlockingReasonRequiresCleanSavedCollectionAndNoInflightWork() {
        var state = FileManagerContentState()
        state.entryViewLayout.isCollectionMode = true

        let context = CollectionContext(query: "report", scopes: ["/tmp"], conditions: [])
        state.collection.collectionContext = context
        state.collection.collectionSession.metadata.baseline = .init(context: context)
        state.collection.collectionSession.document = .init(
            url: URL(fileURLWithPath: "/tmp/report.voycoll"),
            name: "report",
            compatibility: nil,
        )
        state.collection.collectionSession.phase = .opened(kind: .definition, base: .stale, inflight: .none)

        XCTAssertNil(state.collection.refreshBlockingReason(
            isCollectionMode: state.isCollectionMode,
            isDirty: state.isOpenedCollectionDirty,
            isSearching: state.composer.isCollectionSearching,
        ))

        state.collection.collectionSession.phase = .opened(
            kind: .definition,
            base: .stale,
            inflight: .refreshingHydratedSnapshot,
        )
        XCTAssertEqual(
            state.collection
                .refreshBlockingReason(isCollectionMode: state.isCollectionMode, isDirty: state.isOpenedCollectionDirty,
                                       isSearching: state.composer.isCollectionSearching),
            .refreshInFlight,
        )

        state.collection.collectionSession.phase = .opened(
            kind: .definition,
            base: .stale,
            inflight: .writingBackRefreshedSnapshot,
        )
        XCTAssertEqual(
            state.collection
                .refreshBlockingReason(isCollectionMode: state.isCollectionMode, isDirty: state.isOpenedCollectionDirty,
                                       isSearching: state.composer.isCollectionSearching),
            .writeBackInFlight,
        )

        state.collection.collectionSession.phase = .opened(kind: .definition, base: .stale, inflight: .none)
        state.collection.collectionContext = .init(query: "updated", scopes: ["/tmp"], conditions: [])
        XCTAssertEqual(state.collection.refreshBlockingReason(
            isCollectionMode: state.isCollectionMode,
            isDirty: state.isOpenedCollectionDirty,
            isSearching: state.composer.isCollectionSearching,
        ), .dirtyCollection)
    }

    func testRefreshBlockingReasonUsesPriorityOrder() {
        var state = FileManagerContentState()

        XCTAssertEqual(
            state.collection
                .refreshBlockingReason(isCollectionMode: state.isCollectionMode, isDirty: state.isOpenedCollectionDirty,
                                       isSearching: state.composer.isCollectionSearching),
            .notInCollectionMode,
        )

        state.entryViewLayout.isCollectionMode = true
        XCTAssertEqual(
            state.collection
                .refreshBlockingReason(isCollectionMode: state.isCollectionMode, isDirty: state.isOpenedCollectionDirty,
                                       isSearching: state.composer.isCollectionSearching),
            .notStale,
        )

        let baseline = CollectionContext(query: "report", scopes: ["/tmp"], conditions: [])
        state.collection.collectionSession.phase = .opened(kind: .definition, base: .stale, inflight: .none)
        state.collection.collectionSession.document = .init(
            url: URL(fileURLWithPath: "/tmp/report.voycoll"),
            name: "report",
            compatibility: nil,
        )
        state.collection.collectionSession.metadata.baseline = .init(context: baseline)
        state.collection.collectionContext = baseline
        XCTAssertNil(state.collection.refreshBlockingReason(
            isCollectionMode: state.isCollectionMode,
            isDirty: state.isOpenedCollectionDirty,
            isSearching: state.composer.isCollectionSearching,
        ))

        state.collection.collectionContext = .init(query: "updated", scopes: ["/tmp"], conditions: [])
        state.collection.collectionSession.phase = .opened(
            kind: .definition,
            base: .stale,
            inflight: .writingBackRefreshedSnapshot,
        )
        state.collection.collectionSession.document = nil
        XCTAssertEqual(
            state.collection
                .refreshBlockingReason(isCollectionMode: state.isCollectionMode, isDirty: state.isOpenedCollectionDirty,
                                       isSearching: state.composer.isCollectionSearching),
            .dirtyCollection,
        )

        state.collection.collectionContext = baseline
        state.composer.isCollectionMode = true
        state.composer.isLoadingFilters = true
        XCTAssertEqual(
            state.collection
                .refreshBlockingReason(isCollectionMode: state.isCollectionMode, isDirty: state.isOpenedCollectionDirty,
                                       isSearching: state.composer.isCollectionSearching),
            .searchInFlight,
        )

        state.composer.isLoadingFilters = false
        state.collection.collectionSession.phase = .opened(
            kind: .definition,
            base: .stale,
            inflight: .refreshingHydratedSnapshot,
        )
        XCTAssertEqual(
            state.collection
                .refreshBlockingReason(isCollectionMode: state.isCollectionMode, isDirty: state.isOpenedCollectionDirty,
                                       isSearching: state.composer.isCollectionSearching),
            .refreshInFlight,
        )

        state.collection.collectionSession.phase = .opened(
            kind: .definition,
            base: .stale,
            inflight: .writingBackRefreshedSnapshot,
        )
        XCTAssertEqual(state.collection.refreshBlockingReason(
            isCollectionMode: state.isCollectionMode,
            isDirty: state.isOpenedCollectionDirty,
            isSearching: state.composer.isCollectionSearching,
        ), .writeBackInFlight)

        state.collection.collectionSession.phase = .opened(kind: .definition, base: .stale, inflight: .none)
        XCTAssertEqual(
            state.collection
                .refreshBlockingReason(isCollectionMode: state.isCollectionMode, isDirty: state.isOpenedCollectionDirty,
                                       isSearching: state.composer.isCollectionSearching),
            .missingOpenedURL,
        )

        state.collection.collectionSession.document = .init(
            url: URL(fileURLWithPath: "/tmp/report.voycoll"),
            name: "report",
            compatibility: nil,
        )
        state.collection.collectionContext = nil
        XCTAssertEqual(
            state.collection
                .refreshBlockingReason(isCollectionMode: state.isCollectionMode, isDirty: state.isOpenedCollectionDirty,
                                       isSearching: state.composer.isCollectionSearching),
            .missingCollectionContext,
        )

        state.collection.collectionContext = baseline
        state.collection.collectionSession.metadata.baseline = nil
        XCTAssertEqual(
            state.collection
                .refreshBlockingReason(isCollectionMode: state.isCollectionMode, isDirty: state.isOpenedCollectionDirty,
                                       isSearching: state.composer.isCollectionSearching),
            .missingBaseline,
        )
    }

    func testResetComposerOnNextDirectoryNavigationDefaultsFalse() {
        let state = FileManagerContentState()
        XCTAssertFalse(state.resetComposerOnNextDirectoryNavigation)
    }

    func testResetComposerOnNextDirectoryNavigationRoundTrips() {
        var state = FileManagerContentState()
        state.resetComposerOnNextDirectoryNavigation = true
        XCTAssertTrue(state.resetComposerOnNextDirectoryNavigation)
        state.resetComposerOnNextDirectoryNavigation = false
        XCTAssertFalse(state.resetComposerOnNextDirectoryNavigation)
    }

    func testResetComposerOnNextDirectoryNavigationToleratesCollectionSessionMutation() {
        var state = FileManagerContentState()
        state.resetComposerOnNextDirectoryNavigation = true

        state.collection.collectionSession.phase = .opened(
            kind: .definition, base: .ready, inflight: .none,
        )
        XCTAssertTrue(state.resetComposerOnNextDirectoryNavigation)

        state.collection.collectionSession.document = .init(
            url: URL(fileURLWithPath: "/tmp/test.voycoll"),
            name: "test",
            compatibility: nil,
        )
        XCTAssertTrue(state.resetComposerOnNextDirectoryNavigation)

        state.collection = .init()
        XCTAssertTrue(state.resetComposerOnNextDirectoryNavigation)
    }
}

@MainActor
private func shouldRefreshOnOpen(_ session: CollectionDocumentSessionState) -> Bool {
    session.phase.openKind == .hydratedSnapshot && session.phase.isStale && session.metadata.lastRefreshAt == nil
}
