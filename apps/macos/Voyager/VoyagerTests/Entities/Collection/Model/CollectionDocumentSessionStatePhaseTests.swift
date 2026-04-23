import Foundation
@testable import Voyager
import XCTest

@MainActor
final class CollectionDocumentSessionStatePhaseTests: XCTestCase {
    func testPhaseDerivesLegacyLifecycleBools() {
        var session = CollectionDocumentSessionState()

        session.phase = .opened(kind: .hydratedSnapshot, base: .stale, inflight: .refreshingHydratedSnapshot)
        XCTAssertFalse(session.isOpening)
        XCTAssertTrue(session.isStale)
        XCTAssertTrue(session.didHydrateSnapshotOnOpen)
        XCTAssertTrue(session.isRefreshingHydratedSnapshot)
        XCTAssertFalse(session.isWritingBackRefreshedSnapshot)

        session.phase = .opened(kind: .hydratedSnapshot, base: .stale, inflight: .writingBackRefreshedSnapshot)
        XCTAssertTrue(session.isStale)
        XCTAssertTrue(session.didHydrateSnapshotOnOpen)
        XCTAssertFalse(session.isRefreshingHydratedSnapshot)
        XCTAssertTrue(session.isWritingBackRefreshedSnapshot)

        session.phase = .reopening(kind: .definition, base: .ready, inflight: .none)
        XCTAssertTrue(session.isOpening)
        XCTAssertFalse(session.isStale)
        XCTAssertFalse(session.didHydrateSnapshotOnOpen)
        XCTAssertFalse(session.isRefreshingHydratedSnapshot)
        XCTAssertFalse(session.isWritingBackRefreshedSnapshot)
    }

    func testLegacyBoolBridgeSettersTranslateToPhaseTransitions() {
        var session = CollectionDocumentSessionState()

        session.isStale = true
        XCTAssertEqual(session.phase, .opened(kind: .definition, base: .stale, inflight: .none))

        session.didHydrateSnapshotOnOpen = true
        XCTAssertEqual(session.phase, .opened(kind: .hydratedSnapshot, base: .stale, inflight: .none))

        session.isRefreshingHydratedSnapshot = true
        XCTAssertEqual(
            session.phase,
            .opened(kind: .hydratedSnapshot, base: .stale, inflight: .refreshingHydratedSnapshot),
        )

        session.isWritingBackRefreshedSnapshot = true
        XCTAssertEqual(
            session.phase,
            .opened(kind: .hydratedSnapshot, base: .stale, inflight: .writingBackRefreshedSnapshot),
        )

        session.isWritingBackRefreshedSnapshot = false
        XCTAssertEqual(session.phase, .opened(kind: .hydratedSnapshot, base: .stale, inflight: .none))

        session.isStale = false
        XCTAssertEqual(session.phase, .opened(kind: .hydratedSnapshot, base: .ready, inflight: .none))

        session.didHydrateSnapshotOnOpen = false
        XCTAssertEqual(session.phase, .opened(kind: .definition, base: .ready, inflight: .none))
    }

    func testReopeningPhaseIgnoresLegacyBoolResetsUntilOpenCompletes() {
        var session = CollectionDocumentSessionState()

        session.isOpening = true
        XCTAssertEqual(session.phase, .reopening(kind: .definition, base: .ready, inflight: .none))

        session.isStale = false
        session.didHydrateSnapshotOnOpen = false
        session.isRefreshingHydratedSnapshot = false
        session.isWritingBackRefreshedSnapshot = false
        XCTAssertEqual(session.phase, .reopening(kind: .definition, base: .ready, inflight: .none))

        session.isOpening = false
        XCTAssertEqual(session.phase, .opened(kind: .definition, base: .ready, inflight: .none))
    }

    func testTransientRefreshStatusesReturnToStaleUntilExplicitlyCleared() {
        var session = CollectionDocumentSessionState()

        session.didHydrateSnapshotOnOpen = true
        session.isStale = true
        session.isRefreshingHydratedSnapshot = true
        XCTAssertEqual(
            session.phase,
            .opened(kind: .hydratedSnapshot, base: .stale, inflight: .refreshingHydratedSnapshot),
        )

        session.isRefreshingHydratedSnapshot = false
        XCTAssertEqual(session.phase, .opened(kind: .hydratedSnapshot, base: .stale, inflight: .none))

        session.isWritingBackRefreshedSnapshot = true
        XCTAssertEqual(
            session.phase,
            .opened(kind: .hydratedSnapshot, base: .stale, inflight: .writingBackRefreshedSnapshot),
        )

        session.isWritingBackRefreshedSnapshot = false
        XCTAssertEqual(session.phase, .opened(kind: .hydratedSnapshot, base: .stale, inflight: .none))
    }

    func testRefreshFailureBecomesExplicitFailedPhase() {
        var session = CollectionDocumentSessionState()

        session.didHydrateSnapshotOnOpen = true
        session.isStale = true
        session.isRefreshingHydratedSnapshot = true
        session.failRefreshOrWriteBack()

        XCTAssertEqual(session.phase, .refreshFailed(kind: .hydratedSnapshot))
        XCTAssertTrue(session.isStale)
        XCTAssertTrue(session.didHydrateSnapshotOnOpen)
        XCTAssertFalse(session.isRefreshingHydratedSnapshot)
        XCTAssertFalse(session.isWritingBackRefreshedSnapshot)
        XCTAssertEqual(session.staleReason, .snapshotHydratedOnOpen)
    }

    func testEqualityTracksPhaseIdentityDirectly() {
        var lhs = CollectionDocumentSessionState()
        var rhs = CollectionDocumentSessionState()

        lhs.phase = .refreshFailed(kind: .definition)
        rhs.phase = .opened(kind: .definition, base: .stale, inflight: .none)

        XCTAssertNotEqual(lhs, rhs)
    }

    func testReopeningPreservesHydrationAndStaleSignalsUntilOpenCommits() {
        var session = CollectionDocumentSessionState()

        session.isOpening = true
        session.didHydrateSnapshotOnOpen = true
        session.isStale = true
        session.isRefreshingHydratedSnapshot = true

        XCTAssertEqual(
            session.phase,
            .reopening(kind: .hydratedSnapshot, base: .stale, inflight: .refreshingHydratedSnapshot),
        )

        session.isOpening = false

        XCTAssertEqual(
            session.phase,
            .opened(kind: .hydratedSnapshot, base: .stale, inflight: .refreshingHydratedSnapshot),
        )
    }
}
