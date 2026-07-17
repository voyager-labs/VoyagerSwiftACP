import ComposableArchitecture
@testable import VoyagerFeaturesAccountAccess
import VoyagerShared
import XCTest

@MainActor
final class ACC002UpdateEligibilityTests: XCTestCase {
    func testEvaluatorAllowsExactUpdatesThroughBoundary() throws {
        let releasedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let identity = try ReleaseIdentity(releasedAt: "2023-11-14T22:13:20Z", now: releasedAt)

        XCTAssertNil(UpdateEligibilityEvaluator.evaluate(
            releaseIdentity: identity,
            hasAccess: true,
            ownershipStatus: "owned",
            updateStatus: "expired",
            updatesThrough: releasedAt,
        ))
    }

    func testEvaluatorDeniesOneSecondAfterUpdatesThroughBoundary() throws {
        let releasedAt = Date(timeIntervalSince1970: 1_700_000_001)
        let identity = try ReleaseIdentity(releasedAt: "2023-11-14T22:13:21Z", now: releasedAt)
        let updatesThrough = releasedAt.addingTimeInterval(-1)

        XCTAssertEqual(
            UpdateEligibilityEvaluator.evaluate(
                releaseIdentity: identity,
                hasAccess: true,
                ownershipStatus: "owned",
                updateStatus: "expired",
                updatesThrough: updatesThrough,
            ),
            .buildReleasedAfterUpdatesThrough(releasedAt: releasedAt, updatesThrough: updatesThrough),
        )
    }

    func testEvaluatorAppliesCanonicalOwnershipUpdateMatrix() throws {
        let releasedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let identity = try ReleaseIdentity(releasedAt: "2023-11-14T22:13:20Z", now: releasedAt)

        let latestCases: [(String, String)] = [
            ("owned", "perpetual"),
            ("trial", "active"),
            ("owned", "active"),
        ]
        for (ownershipStatus, updateStatus) in latestCases {
            XCTAssertNil(UpdateEligibilityEvaluator.evaluate(
                releaseIdentity: identity,
                hasAccess: true,
                ownershipStatus: ownershipStatus,
                updateStatus: updateStatus,
                updatesThrough: nil,
            ))
        }
        XCTAssertEqual(
            UpdateEligibilityEvaluator.evaluate(
                releaseIdentity: nil,
                hasAccess: true,
                ownershipStatus: "owned",
                updateStatus: "active",
                updatesThrough: nil,
            ),
            .missingReleaseIdentity,
        )
        XCTAssertEqual(
            UpdateEligibilityEvaluator.evaluate(
                releaseIdentity: identity,
                hasAccess: true,
                ownershipStatus: "owned",
                updateStatus: "expired",
                updatesThrough: nil,
            ),
            .missingUpdatesThrough,
        )
        XCTAssertEqual(
            UpdateEligibilityEvaluator.evaluate(
                releaseIdentity: identity,
                hasAccess: true,
                ownershipStatus: "owned",
                updateStatus: "expired",
                updatesThrough: Date(timeIntervalSinceReferenceDate: .infinity),
            ),
            .invalidUpdatesThrough,
        )
        for ownershipStatus in ["refunded", "revoked", "none"] {
            XCTAssertEqual(
                UpdateEligibilityEvaluator.evaluate(
                    releaseIdentity: identity,
                    hasAccess: false,
                    ownershipStatus: ownershipStatus,
                    updateStatus: "none",
                    updatesThrough: nil,
                ),
                .invalidAccessTuple,
            )
        }
    }

    func testLegacyIncompleteResponseAndSnapshotsFailClosed() throws {
        let releasedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let identity = try ReleaseIdentity(releasedAt: "2023-11-14T22:13:20Z", now: releasedAt)
        let response = AccessStatusResponse(hasAccess: true, status: "active")
        let snapshot = AccessStatusSnapshot(status: .coreLicenseActive, fetchedAt: releasedAt)
        let fetchedSnapshot = AccessStatusSnapshot.fetchResult(
            status: .coreLicenseActive,
            fetchedAt: releasedAt,
        )

        XCTAssertNil(response.updatesThrough)
        XCTAssertNil(snapshot.updatesThrough)
        XCTAssertNil(fetchedSnapshot.updatesThrough)
        XCTAssertEqual(
            UpdateEligibilityEvaluator.evaluate(
                releaseIdentity: identity,
                hasAccess: response.hasAccess,
                ownershipStatus: response.ownershipStatus,
                updateStatus: response.updateStatus,
                updatesThrough: response.updatesThrough,
            ),
            .invalidAccessTuple,
        )
        XCTAssertEqual(
            UpdateEligibilityEvaluator.evaluate(
                releaseIdentity: identity,
                hasAccess: true,
                ownershipStatus: snapshot.ownershipStatus,
                updateStatus: snapshot.updateStatus,
                updatesThrough: snapshot.updatesThrough,
            ),
            .invalidAccessTuple,
        )
        XCTAssertEqual(
            UpdateEligibilityEvaluator.evaluate(
                releaseIdentity: identity,
                hasAccess: true,
                ownershipStatus: fetchedSnapshot.ownershipStatus,
                updateStatus: fetchedSnapshot.updateStatus,
                updatesThrough: fetchedSnapshot.updatesThrough,
            ),
            .invalidAccessTuple,
        )
    }

    func testCachedIneligibleSnapshotRequiresRecoveryWithoutUnlock() async {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let binding = UUID()
        let sessionExpiry = now.addingTimeInterval(3600)
        let snapshot = AccessStatusSnapshot(
            status: .coreLicenseActive,
            fetchedAt: now.addingTimeInterval(-60),
            sessionBindingID: binding,
            gatewayBinding: GatewayEnvironment(rawValue: "").binding,
            deviceID: "test-device-id",
            sessionExpiresAt: sessionExpiry,
            deviceBindingVerifiedAt: now.addingTimeInterval(-60),
            ownershipStatus: "owned",
            updateStatus: "expired",
            updatesThrough: now.addingTimeInterval(-1),
        )
        var state = AccountAccessFeature.State()
        state.hasAccountSession = true
        state.sessionExpiresAt = sessionExpiry
        state.sessionBindingID = binding
        state.syncGeneration = 1

        let store = TestStore(initialState: state) {
            AccountAccessFeature()
        } withDependencies: {
            $0.date = .constant(now)
            $0.releaseIdentityClient = ReleaseIdentityClient(resolve: { _ in
                try? ReleaseIdentity(releasedAt: "2023-11-14T22:13:20Z", now: now)
            })
        }

        await store.send(._cachedSnapshotRestored(
            generation: 1,
            binding: binding,
            snapshot: snapshot,
            validUntil: sessionExpiry,
        )) { state in
            state.status = .coreLicenseActive
            state.snapshot = snapshot
            state.errorMessage = "This Voyager version is newer than your update eligibility. "
                + "Download an eligible version to continue."
            state.updateEligibilityFailure = .buildReleasedAfterUpdatesThrough(
                releasedAt: now,
                updatesThrough: now.addingTimeInterval(-1),
            )
        }
        await store.receive(\.delegate.recoveryRequired)
        XCTAssertFalse(store.state.isComplete)
        await store.finish()
    }
}
