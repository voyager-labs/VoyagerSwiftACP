import Foundation
@testable import Voyager
import XCTest

@MainActor
final class FileManagerContentCollectionStateTests: XCTestCase {
    func testDirtyAndStaleStayIndependent() {
        var state = FileManagerContentState()
        state.entryViewLayout.isCollectionMode = true

        let context = CollectionContext(query: "report", scopes: ["/tmp"], includeSubfolders: true, conditions: [])
        state.collectionContext = context
        state.collectionSession.metadata.baseline = .init(context: context)
        state.collectionSession.phase = .opened(kind: .definition, base: .stale, inflight: .none)
        state.collectionSession.metadata.lastRefreshAt = .distantFuture

        XCTAssertFalse(state.isOpenedCollectionDirty)
        XCTAssertTrue(state.isOpenedCollectionStale)
        XCTAssertFalse(state.canSaveCollection)

        state.collectionContext = .init(query: "updated", scopes: ["/tmp"], includeSubfolders: true, conditions: [])

        XCTAssertTrue(state.isOpenedCollectionDirty)
        XCTAssertTrue(state.isOpenedCollectionStale)
        XCTAssertTrue(state.canSaveCollection)
        XCTAssertEqual(state.collectionSession.metadata.lastRefreshAt, .distantFuture)
    }

    func testCanSaveCollectionTracksDirtyOnly() {
        var state = FileManagerContentState()
        state.entryViewLayout.isCollectionMode = true

        let baseline = CollectionContext(query: "report", scopes: ["/tmp"], includeSubfolders: true, conditions: [])
        state.collectionContext = .init(query: "updated", scopes: ["/tmp"], includeSubfolders: true, conditions: [])
        state.collectionSession.metadata.baseline = .init(context: baseline)
        state.collectionSession.phase = .opened(kind: .definition, base: .stale, inflight: .none)

        XCTAssertTrue(state.isOpenedCollectionDirty)
        XCTAssertTrue(state.canSaveCollection)
        XCTAssertTrue(state.isOpenedCollectionStale)
    }

    func testHydratedStaleSessionRefreshBoundaryUsesPhaseAndTimestamp() {
        var state = FileManagerContentState()

        XCTAssertFalse(shouldRefreshOnOpen(state.collectionSession))

        state.collectionSession.phase = .opened(kind: .hydratedSnapshot, base: .ready, inflight: .none)
        XCTAssertFalse(shouldRefreshOnOpen(state.collectionSession))

        state.collectionSession.phase = .opened(kind: .hydratedSnapshot, base: .stale, inflight: .none)
        XCTAssertTrue(shouldRefreshOnOpen(state.collectionSession))

        state.collectionSession.metadata.lastRefreshAt = Date()
        XCTAssertFalse(shouldRefreshOnOpen(state.collectionSession))

        state.collectionSession.metadata.lastRefreshAt = nil
        state.collectionSession.phase = .opened(kind: .definition, base: .stale, inflight: .none)
        XCTAssertFalse(shouldRefreshOnOpen(state.collectionSession))
    }

    func testRefreshBlockingReasonRequiresCleanSavedCollectionAndNoInflightWork() {
        var state = FileManagerContentState()
        state.entryViewLayout.isCollectionMode = true

        let context = CollectionContext(query: "report", scopes: ["/tmp"], includeSubfolders: true, conditions: [])
        state.collectionContext = context
        state.collectionSession.metadata.baseline = .init(context: context)
        state.collectionSession.document = .init(
            url: URL(fileURLWithPath: "/tmp/report.voycoll"),
            name: "report",
            compatibility: nil,
        )
        state.collectionSession.phase = .opened(kind: .definition, base: .stale, inflight: .none)

        XCTAssertNil(state.refreshBlockingReason)

        state.collectionSession.phase = .opened(kind: .definition, base: .stale, inflight: .refreshingHydratedSnapshot)
        XCTAssertEqual(state.refreshBlockingReason, .refreshInFlight)

        state.collectionSession.phase = .opened(
            kind: .definition,
            base: .stale,
            inflight: .writingBackRefreshedSnapshot,
        )
        XCTAssertEqual(state.refreshBlockingReason, .writeBackInFlight)

        state.collectionSession.phase = .opened(kind: .definition, base: .stale, inflight: .none)
        state.collectionContext = .init(query: "updated", scopes: ["/tmp"], includeSubfolders: true, conditions: [])
        XCTAssertEqual(state.refreshBlockingReason, .dirtyCollection)
    }

    func testRefreshBlockingReasonUsesPriorityOrder() {
        var state = FileManagerContentState()

        XCTAssertEqual(state.refreshBlockingReason, .notInCollectionMode)

        state.entryViewLayout.isCollectionMode = true
        XCTAssertEqual(state.refreshBlockingReason, .notStale)

        let baseline = CollectionContext(query: "report", scopes: ["/tmp"], includeSubfolders: true, conditions: [])
        state.collectionSession.phase = .opened(kind: .definition, base: .stale, inflight: .none)
        state.collectionSession.document = .init(
            url: URL(fileURLWithPath: "/tmp/report.voycoll"),
            name: "report",
            compatibility: nil,
        )
        state.collectionSession.metadata.baseline = .init(context: baseline)
        state.collectionContext = baseline
        XCTAssertNil(state.refreshBlockingReason)

        state.collectionContext = .init(query: "updated", scopes: ["/tmp"], includeSubfolders: true, conditions: [])
        state.collectionSession.phase = .opened(
            kind: .definition,
            base: .stale,
            inflight: .writingBackRefreshedSnapshot,
        )
        state.collectionSession.document = nil
        XCTAssertEqual(state.refreshBlockingReason, .dirtyCollection)

        state.collectionContext = baseline
        state.composer.isCollectionMode = true
        state.composer.isLoadingFilters = true
        XCTAssertEqual(state.refreshBlockingReason, .searchInFlight)

        state.composer.isLoadingFilters = false
        state.collectionSession.phase = .opened(kind: .definition, base: .stale, inflight: .refreshingHydratedSnapshot)
        XCTAssertEqual(state.refreshBlockingReason, .refreshInFlight)

        state.collectionSession.phase = .opened(
            kind: .definition,
            base: .stale,
            inflight: .writingBackRefreshedSnapshot,
        )
        XCTAssertEqual(state.refreshBlockingReason, .writeBackInFlight)

        state.collectionSession.phase = .opened(kind: .definition, base: .stale, inflight: .none)
        XCTAssertEqual(state.refreshBlockingReason, .missingOpenedURL)

        state.collectionSession.document = .init(
            url: URL(fileURLWithPath: "/tmp/report.voycoll"),
            name: "report",
            compatibility: nil,
        )
        state.collectionContext = nil
        XCTAssertEqual(state.refreshBlockingReason, .missingCollectionContext)

        state.collectionContext = baseline
        state.collectionSession.metadata.baseline = nil
        XCTAssertEqual(state.refreshBlockingReason, .missingBaseline)
    }
}

@MainActor
private func shouldRefreshOnOpen(_ session: CollectionDocumentSessionState) -> Bool {
    session.phase.openKind == .hydratedSnapshot && session.phase.isStale && session.metadata.lastRefreshAt == nil
}
