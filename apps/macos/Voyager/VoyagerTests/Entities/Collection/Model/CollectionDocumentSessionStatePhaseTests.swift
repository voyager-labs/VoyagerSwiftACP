import Foundation
@testable import Voyager
import VoyagerEntitiesCollection
import XCTest

/// 컬렉션 문서 세션 페이즈 — 전환 헬퍼와 상태 변환을 검증.
@MainActor
final class CollectionDocumentSessionStatePhaseTests: XCTestCase {
    /// testPhaseDerivesLegacyLifecycleBools 테스트 동작을 검증한다.
    func testPhaseDerivesLegacyLifecycleBools() {
        var session = CollectionDocumentSessionState()

        session.phase = .opened(kind: .hydratedSnapshot, base: .stale, inflight: .refreshingHydratedSnapshot)
        XCTAssertFalse(session.phase.isOpening)
        XCTAssertTrue(session.phase.isStale)
        XCTAssertEqual(session.phase.openKind, .hydratedSnapshot)
        XCTAssertEqual(session.phase.inflightStatus, .refreshingHydratedSnapshot)
        XCTAssertNotEqual(session.phase.inflightStatus, .writingBackRefreshedSnapshot)

        session.phase = .opened(kind: .hydratedSnapshot, base: .stale, inflight: .writingBackRefreshedSnapshot)
        XCTAssertTrue(session.phase.isStale)
        XCTAssertEqual(session.phase.openKind, .hydratedSnapshot)
        XCTAssertNotEqual(session.phase.inflightStatus, .refreshingHydratedSnapshot)
        XCTAssertEqual(session.phase.inflightStatus, .writingBackRefreshedSnapshot)

        session.phase = .reopening(kind: .definition, base: .ready, inflight: .none)
        XCTAssertTrue(session.phase.isOpening)
        XCTAssertFalse(session.phase.isStale)
        XCTAssertNotEqual(session.phase.openKind, .hydratedSnapshot)
        XCTAssertNotEqual(session.phase.inflightStatus, .refreshingHydratedSnapshot)
        XCTAssertNotEqual(session.phase.inflightStatus, .writingBackRefreshedSnapshot)
    }

    /// testExplicitPhaseHelpersTranslateToPhaseTransitions 테스트 동작을 검증한다.
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

    /// testReopeningPhaseIgnoresBaseKindAndInflightRewritesUntilOpenCompletes 테스트 동작을 검증한다.
    func testReopeningPhaseIgnoresBaseKindAndInflightRewritesUntilOpenCompletes() {
        var phase: CollectionSessionPhase = .reopening(kind: .definition, base: .ready, inflight: .none)

        phase = phase.withBaseStatus(.ready)
        phase = phase.withInflightStatus(.none)
        XCTAssertEqual(phase, .reopening(kind: .definition, base: .ready, inflight: .none))

        phase = phase.finishedOpeningTransition()
        XCTAssertEqual(phase, .opened(kind: .definition, base: .ready, inflight: .none))
    }

    /// testTransientRefreshStatusesReturnToStaleUntilExplicitlyCleared 테스트 동작을 검증한다.
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

    /// testRefreshFailureBecomesExplicitFailedPhase 테스트 동작을 검증한다.
    func testRefreshFailureBecomesExplicitFailedPhase() {
        var session = CollectionDocumentSessionState()

        session.phase = .opened(kind: .hydratedSnapshot, base: .stale, inflight: .refreshingHydratedSnapshot)
        session.failRefreshOrWriteBack()

        XCTAssertEqual(session.phase, .refreshFailed(kind: .hydratedSnapshot))
        XCTAssertTrue(session.phase.isStale)
        XCTAssertEqual(session.phase.openKind, .hydratedSnapshot)
        XCTAssertNotEqual(session.phase.inflightStatus, .refreshingHydratedSnapshot)
        XCTAssertNotEqual(session.phase.inflightStatus, .writingBackRefreshedSnapshot)
    }

    /// testEqualityTracksPhaseIdentityDirectly 테스트 동작을 검증한다.
    func testEqualityTracksPhaseIdentityDirectly() {
        var lhs = CollectionDocumentSessionState()
        var rhs = CollectionDocumentSessionState()

        lhs.phase = .refreshFailed(kind: .definition)
        rhs.phase = .opened(kind: .definition, base: .stale, inflight: .none)

        XCTAssertNotEqual(lhs, rhs)
    }

    /// testReopeningPreservesHydrationAndStaleSignalsUntilOpenCommits 테스트 동작을 검증한다.
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
