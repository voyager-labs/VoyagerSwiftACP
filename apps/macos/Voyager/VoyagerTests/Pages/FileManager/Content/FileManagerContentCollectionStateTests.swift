import Foundation
@testable import Voyager
import VoyagerEntitiesCollection
import VoyagerFeaturesComposer
@testable import VoyagerPagesFileManager
import XCTest

/// FileManager content의 collection 상태(dirty/stale/refresh) 계약을 검증한다.
@MainActor
final class FileManagerContentCollectionStateTests: XCTestCase {
    /// testDirtyAndStaleStayIndependent 시나리오가 FileManager 계약을 위반하지 않음을 검증한다.
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

    /// testCanSaveCollectionTracksDirtyOnly 시나리오가 FileManager 계약을 위반하지 않음을 검증한다.
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

    /// testHydratedStaleSessionRefreshBoundaryUsesPhaseAndTimestamp 시나리오가 FileManager 계약을 위반하지 않음을 검증한다.
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

    /// testRefreshBlockingReasonRequiresCleanSavedCollectionAndNoInflightWork 시나리오가 FileManager 계약을 위반하지 않음을 검증한다.
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

        assertRefreshBlockingReason(state, nil)

        state.collection.collectionSession.phase = .opened(
            kind: .definition,
            base: .stale,
            inflight: .refreshingHydratedSnapshot,
        )
        assertRefreshBlockingReason(state, .refreshInFlight)

        state.collection.collectionSession.phase = .opened(
            kind: .definition,
            base: .stale,
            inflight: .writingBackRefreshedSnapshot,
        )
        assertRefreshBlockingReason(state, .writeBackInFlight)

        state.collection.collectionSession.phase = .opened(kind: .definition, base: .stale, inflight: .none)
        state.collection.collectionContext = .init(query: "updated", scopes: ["/tmp"], conditions: [])
        assertRefreshBlockingReason(state, .dirtyCollection)
    }

    /// testRefreshBlockingReasonUsesPriorityOrder 시나리오가 FileManager 계약을 위반하지 않음을 검증한다.
    func testRefreshBlockingReasonUsesPriorityOrder() {
        var state = FileManagerContentState()

        assertRefreshBlockingReason(state, .notInCollectionMode)

        state.entryViewLayout.isCollectionMode = true
        assertRefreshBlockingReason(state, .notStale)

        let baseline = CollectionContext(query: "report", scopes: ["/tmp"], conditions: [])
        configureRefreshableCollectionState(&state, baseline: baseline)
        assertRefreshBlockingReason(state, nil)

        state.collection.collectionContext = .init(query: "updated", scopes: ["/tmp"], conditions: [])
        state.collection.collectionSession.phase = .opened(
            kind: .definition,
            base: .stale,
            inflight: .writingBackRefreshedSnapshot,
        )
        state.collection.collectionSession.document = nil
        assertRefreshBlockingReason(state, .dirtyCollection)

        state.collection.collectionContext = baseline
        state.composer.isCollectionMode = true
        state.composer.isLoadingFilters = true
        assertRefreshBlockingReason(state, .searchInFlight)

        state.composer.isLoadingFilters = false
        state.collection.collectionSession.phase = .opened(
            kind: .definition,
            base: .stale,
            inflight: .refreshingHydratedSnapshot,
        )
        assertRefreshBlockingReason(state, .refreshInFlight)

        state.collection.collectionSession.phase = .opened(
            kind: .definition,
            base: .stale,
            inflight: .writingBackRefreshedSnapshot,
        )
        assertRefreshBlockingReason(state, .writeBackInFlight)

        state.collection.collectionSession.phase = .opened(kind: .definition, base: .stale, inflight: .none)
        assertRefreshBlockingReason(state, .missingOpenedURL)

        state.collection.collectionSession.document = .init(
            url: URL(fileURLWithPath: "/tmp/report.voycoll"),
            name: "report",
            compatibility: nil,
        )
        state.collection.collectionContext = nil
        assertRefreshBlockingReason(state, .missingCollectionContext)

        state.collection.collectionContext = baseline
        state.collection.collectionSession.metadata.baseline = nil
        assertRefreshBlockingReason(state, .missingBaseline)
    }

    /// testResetComposerOnNextDirectoryNavigationDefaultsFalse 시나리오가 FileManager 계약을 위반하지 않음을 검증한다.
    func testResetComposerOnNextDirectoryNavigationDefaultsFalse() {
        let state = FileManagerContentState()
        XCTAssertFalse(state.resetComposerOnNextDirectoryNavigation)
    }

    /// testResetComposerOnNextDirectoryNavigationRoundTrips 시나리오가 FileManager 계약을 위반하지 않음을 검증한다.
    func testResetComposerOnNextDirectoryNavigationRoundTrips() {
        var state = FileManagerContentState()
        state.resetComposerOnNextDirectoryNavigation = true
        XCTAssertTrue(state.resetComposerOnNextDirectoryNavigation)
        state.resetComposerOnNextDirectoryNavigation = false
        XCTAssertFalse(state.resetComposerOnNextDirectoryNavigation)
    }

    /// testResetComposerOnNextDirectoryNavigationToleratesCollectionSessionMutation 시나리오가 FileManager 계약을 위반하지 않음을
    /// 검증한다.
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

@MainActor
private func configureRefreshableCollectionState(
    _ state: inout FileManagerContentState,
    baseline: CollectionContext,
) {
    state.collection.collectionSession.phase = .opened(kind: .definition, base: .stale, inflight: .none)
    state.collection.collectionSession.document = .init(
        url: URL(fileURLWithPath: "/tmp/report.voycoll"),
        name: "report",
        compatibility: nil,
    )
    state.collection.collectionSession.metadata.baseline = .init(context: baseline)
    state.collection.collectionContext = baseline
}

@MainActor
private func assertRefreshBlockingReason(
    _ state: FileManagerContentState,
    _ expected: CollectionSessionRefreshBlockingReason?,
    file: StaticString = #filePath,
    line: UInt = #line,
) {
    XCTAssertEqual(
        state.collection.refreshBlockingReason(
            isCollectionMode: state.isCollectionMode,
            isDirty: state.isOpenedCollectionDirty,
            isSearching: state.composer.isCollectionSearching,
        ),
        expected,
        file: file,
        line: line,
    )
}
