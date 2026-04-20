import Foundation
@testable import Voyager
import XCTest

@MainActor
final class FileManagerContentCollectionStateTests: XCTestCase {
    func testDirtyAndStaleStayIndependent() {
        var state = FileManagerContentState()
        state.entryViewLayout.isCollectionMode = true

        let context = CollectionContext(query: "report", scopes: ["/tmp"], conditions: [])
        state.collectionContext = context
        state.collectionSession.baseline = .init(context: context)
        state.collectionSession.isStale = true
        state.collectionSession.staleReason = .invalidatedLocally

        XCTAssertFalse(state.isOpenedCollectionDirty)
        XCTAssertTrue(state.isOpenedCollectionStale)
        XCTAssertFalse(state.canSaveCollection)
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
        state.collectionSession.didHydrateSnapshotOnOpen = true
        state.collectionSession.isStale = true
        state.collectionSession.lastRefreshAt = nil

        XCTAssertTrue(state.shouldRefreshOnOpen)

        state.collectionSession.lastRefreshAt = Date()
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
}
