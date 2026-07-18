import ComposableArchitecture
import CryptoKit
@testable import VoyagerFeaturesUpdateVersion
import VoyagerShared
import XCTest

@MainActor
final class UpdaterFeatureTests: XCTestCase {
    func testUpdaterCallsStartOnlyAfterAccessGrant() async {
        let calls = LockIsolated<[String]>([])
        let store = TestStore(initialState: UpdaterState()) {
            UpdaterFeature()
        } withDependencies: {
            $0.updaterClient.setAccessEligibility = { isEligible, _, _ in
                calls.withValue { $0.append("eligibility:\(isEligible)") }
            }
            $0.updaterClient.configure = {
                calls.withValue { $0.append("configure") }
            }
            $0.updaterClient.startAtLaunch = {
                calls.withValue { $0.append("start") }
            }
            $0.updaterClient.checkForUpdates = {
                calls.withValue { $0.append("check") }
            }
            $0.updaterClient.setAutomaticUpdate = { _ in
                calls.withValue { $0.append("automatic") }
            }
        }

        await store.send(.configureAtLaunch)
        await store.send(.startAtLaunch)
        await store.send(.checkForUpdates)
        XCTAssertTrue(calls.value.isEmpty)

        await store.send(.accessGranted(updateStatus: "active", updatesThrough: nil)) {
            $0.isAccessEligible = true
            $0.updateStatus = "active"
            $0.didConfigure = true
            $0.didStartAtLaunch = true
        }
        await store.finish()

        XCTAssertEqual(calls.value, ["eligibility:true", "configure", "automatic", "start"])
    }

    func testRepeatedAccessGrantRefreshesEligibilityWithoutRestartingUpdater() async {
        let calls = LockIsolated<[String]>([])
        let refreshedUpdatesThrough = Date(timeIntervalSince1970: 1_700_000_000)
        let store = TestStore(initialState: UpdaterState()) {
            UpdaterFeature()
        } withDependencies: {
            $0.updaterClient.setAccessEligibility = { isEligible, _, _ in
                calls.withValue { $0.append("eligibility:\(isEligible)") }
            }
            $0.updaterClient.configure = {
                calls.withValue { $0.append("configure") }
            }
            $0.updaterClient.startAtLaunch = {
                calls.withValue { $0.append("start") }
            }
            $0.updaterClient.setAutomaticUpdate = { _ in
                calls.withValue { $0.append("automatic") }
            }
        }

        await store.send(.accessGranted(updateStatus: "active", updatesThrough: nil)) {
            $0.isAccessEligible = true
            $0.updateStatus = "active"
            $0.didConfigure = true
            $0.didStartAtLaunch = true
        }
        await store.send(.accessGranted(updateStatus: "renewed", updatesThrough: refreshedUpdatesThrough)) {
            $0.updateStatus = "renewed"
            $0.updatesThrough = refreshedUpdatesThrough
        }
        await store.finish()

        XCTAssertEqual(
            calls.value,
            ["eligibility:true", "configure", "automatic", "start", "eligibility:true"],
        )
    }

    func testIneligibleCandidateUsesStableRecoveryReason() throws {
        XCTAssertThrowsError(try SparkleUpdateEligibilityGate.require(false)) { error in
            let error = error as NSError
            XCTAssertEqual(error.domain, "fm.voyager.update-eligibility")
            XCTAssertEqual(error.userInfo["recovery_reason"] as? String, "update_access_ineligible")
        }
    }

    func testCandidateBoundaryAllowsExactTimestampAndRejectsOneSecondLater() throws {
        let boundary = Date(timeIntervalSince1970: 1_700_000_000)
        let eligible = try ReleaseIdentity(releasedAt: "2023-11-14T22:13:20Z", now: boundary)
        let ineligible = try ReleaseIdentity(
            releasedAt: "2023-11-14T22:13:21Z",
            now: boundary.addingTimeInterval(1),
        )

        XCTAssertNoThrow(try SparkleUpdateEligibilityGate.requireCandidate(
            accessGranted: true,
            updateStatus: "expired",
            updatesThrough: boundary,
            candidate: eligible,
        ))
        XCTAssertThrowsError(try SparkleUpdateEligibilityGate.requireCandidate(
            accessGranted: true,
            updateStatus: "expired",
            updatesThrough: boundary,
            candidate: ineligible,
        )) { error in
            XCTAssertEqual((error as NSError).userInfo["recovery_reason"] as? String, "update_access_ineligible")
        }
    }

    func testCandidateBridgeVerifiesManifestAndArtifactBeforeEligibility() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let artifactURL =
            try XCTUnwrap(URL(string: "https://downloads.voyager.fm/releases/versions/0.8.2/Voyager-0.8.2.zip"))
        let privateKey = Curve25519.Signing.PrivateKey()
        let unsigned = ReleaseManifest(
            artifact: .init(
                sha256: String(repeating: "a", count: 64),
                sizeBytes: 1,
                sparkleEd25519Signature: Data(repeating: 0, count: 64).base64EncodedString(),
                url: artifactURL.absoluteString,
            ),
            releasedAt: "2023-11-14T22:13:20Z",
            signature: "",
            version: "0.8.2",
        )
        let signature = try privateKey.signature(for: unsigned.canonicalPayload()).base64EncodedString()
        let manifest = ReleaseManifest(
            artifact: unsigned.artifact,
            releasedAt: unsigned.releasedAt,
            signature: signature,
            version: unsigned.version,
        )
        let data = try JSONEncoder().encode(manifest)

        XCTAssertEqual(
            try VerifiedReleaseCandidate.verifiedIdentity(
                manifestData: data,
                artifactURL: artifactURL,
                now: now,
                publicKey: privateKey.publicKey.rawRepresentation.base64EncodedString(),
            ).releasedAt,
            now,
        )
        XCTAssertThrowsError(try VerifiedReleaseCandidate.verifiedIdentity(
            manifestData: data,
            artifactURL: XCTUnwrap(URL(string: "https://downloads.voyager.fm/releases/versions/0.8.2/other.zip")),
            now: now,
            publicKey: privateKey.publicKey.rawRepresentation.base64EncodedString(),
        ))
    }
}
