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
        XCTAssertEqual(session.openKind, .hydratedSnapshot)
        XCTAssertEqual(session.inflightStatus, .refreshingHydratedSnapshot)
        XCTAssertNotEqual(session.inflightStatus, .writingBackRefreshedSnapshot)

        session.phase = .opened(kind: .hydratedSnapshot, base: .stale, inflight: .writingBackRefreshedSnapshot)
        XCTAssertTrue(session.isStale)
        XCTAssertEqual(session.openKind, .hydratedSnapshot)
        XCTAssertNotEqual(session.inflightStatus, .refreshingHydratedSnapshot)
        XCTAssertEqual(session.inflightStatus, .writingBackRefreshedSnapshot)

        session.phase = .reopening(kind: .definition, base: .ready, inflight: .none)
        XCTAssertTrue(session.isOpening)
        XCTAssertFalse(session.isStale)
        XCTAssertNotEqual(session.openKind, .hydratedSnapshot)
        XCTAssertNotEqual(session.inflightStatus, .refreshingHydratedSnapshot)
        XCTAssertNotEqual(session.inflightStatus, .writingBackRefreshedSnapshot)
    }

    func testExplicitPhaseHelpersTranslateToPhaseTransitions() {
        var phase = CollectionSessionPhase.idle

        phase = phase.withBaseStatus(.stale)
        XCTAssertEqual(phase, .opened(kind: .definition, base: .stale, inflight: .none))

        phase = .opened(kind: .hydratedSnapshot, base: .stale, inflight: .none)
        XCTAssertEqual(phase, .opened(kind: .hydratedSnapshot, base: .stale, inflight: .none))

        phase = phase.withInflightStatus(.refreshingHydratedSnapshot)
        XCTAssertEqual(
            phase,
            .opened(kind: .hydratedSnapshot, base: .stale, inflight: .refreshingHydratedSnapshot),
        )

        phase = phase.withInflightStatus(.writingBackRefreshedSnapshot)
        XCTAssertEqual(
            phase,
            .opened(kind: .hydratedSnapshot, base: .stale, inflight: .writingBackRefreshedSnapshot),
        )

        phase = phase.withInflightStatus(.none)
        XCTAssertEqual(phase, .opened(kind: .hydratedSnapshot, base: .stale, inflight: .none))

        phase = phase.withBaseStatus(.ready)
        XCTAssertEqual(phase, .opened(kind: .hydratedSnapshot, base: .ready, inflight: .none))

        phase = .opened(kind: .definition, base: .ready, inflight: .none)
        XCTAssertEqual(phase, .opened(kind: .definition, base: .ready, inflight: .none))
    }

    func testReopeningPhaseIgnoresBaseKindAndInflightRewritesUntilOpenCompletes() {
        var phase: CollectionSessionPhase = .reopening(kind: .definition, base: .ready, inflight: .none)

        phase = phase.withBaseStatus(.ready)
        phase = phase.withInflightStatus(.none)
        XCTAssertEqual(phase, .reopening(kind: .definition, base: .ready, inflight: .none))

        phase = phase.finishedOpeningTransition()
        XCTAssertEqual(phase, .opened(kind: .definition, base: .ready, inflight: .none))
    }

    func testTransientRefreshStatusesReturnToStaleUntilExplicitlyCleared() {
        var session = CollectionDocumentSessionState()

        session.phase = .opened(kind: .hydratedSnapshot, base: .stale, inflight: .none)
        session.beginRefreshingStaleSession()
        XCTAssertEqual(
            session.phase,
            .opened(kind: .hydratedSnapshot, base: .stale, inflight: .refreshingHydratedSnapshot),
        )

        session.finishRefreshWithoutWriteBack()
        XCTAssertEqual(session.phase, .opened(kind: .hydratedSnapshot, base: .stale, inflight: .none))

        session.beginWriteBackAfterRefresh()
        XCTAssertEqual(
            session.phase,
            .opened(kind: .hydratedSnapshot, base: .stale, inflight: .writingBackRefreshedSnapshot),
        )

        session.finishRefreshWithoutWriteBack()
        XCTAssertEqual(session.phase, .opened(kind: .hydratedSnapshot, base: .stale, inflight: .none))
    }

    func testRefreshFailureBecomesExplicitFailedPhase() {
        var session = CollectionDocumentSessionState()

        session.phase = .opened(kind: .hydratedSnapshot, base: .stale, inflight: .refreshingHydratedSnapshot)
        session.failRefreshOrWriteBack()

        XCTAssertEqual(session.phase, .refreshFailed(kind: .hydratedSnapshot))
        XCTAssertTrue(session.isStale)
        XCTAssertEqual(session.openKind, .hydratedSnapshot)
        XCTAssertNotEqual(session.inflightStatus, .refreshingHydratedSnapshot)
        XCTAssertNotEqual(session.inflightStatus, .writingBackRefreshedSnapshot)
    }

    func testEqualityTracksPhaseIdentityDirectly() {
        var lhs = CollectionDocumentSessionState()
        var rhs = CollectionDocumentSessionState()

        lhs.phase = .refreshFailed(kind: .definition)
        rhs.phase = .opened(kind: .definition, base: .stale, inflight: .none)

        XCTAssertNotEqual(lhs, rhs)
    }

    func testReopeningPreservesHydrationAndStaleSignalsUntilOpenCommits() {
        var phase: CollectionSessionPhase = .reopening(kind: .definition, base: .ready, inflight: .none)

        phase = .reopening(kind: .hydratedSnapshot, base: .ready, inflight: .none)
        phase = phase.withBaseStatus(.stale)
        phase = phase.withInflightStatus(.refreshingHydratedSnapshot)

        XCTAssertEqual(
            phase,
            .reopening(kind: .hydratedSnapshot, base: .stale, inflight: .refreshingHydratedSnapshot),
        )

        phase = phase.finishedOpeningTransition()

        XCTAssertEqual(
            phase,
            .opened(kind: .hydratedSnapshot, base: .stale, inflight: .refreshingHydratedSnapshot),
        )
    }
}
