import ComposableArchitecture
import CryptoKit
@testable import VoyagerFeaturesUpdateVersion
import VoyagerShared
import XCTest

@MainActor
final class SET002ConfigureGeneralSettingsTests: XCTestCase {
    func testDevEnvironmentSkipsUpdateChecks() {
        XCTAssertTrue(SparkleUpdateEligibilityGate.shouldSkipUpdateChecks(
            appEnv: .dev,
            feedURL: "https://updates.voyager.fm/appcast.xml",
        ))
        XCTAssertFalse(SparkleUpdateEligibilityGate.shouldSkipUpdateChecks(
            appEnv: .prod,
            feedURL: "https://updates.voyager.fm/appcast.xml",
        ))
    }

    func testLaunchReadyConfiguresAndStartsWithoutAccountAccess() async {
        let calls = LockIsolated<[String]>([])
        let store = TestStore(initialState: UpdaterState()) {
            UpdaterFeature()
        } withDependencies: {
            $0.updaterClient.configure = { calls.withValue { $0.append("configure") } }
            $0.updaterClient.startAtLaunch = { calls.withValue { $0.append("start") } }
            $0.updaterClient.setAutomaticUpdate = { _ in calls.withValue { $0.append("automatic") } }
        }

        await store.send(.launchReady) {
            $0.didConfigure = true
            $0.didStartAtLaunch = true
        }
        await store.finish()

        XCTAssertEqual(calls.value, ["configure", "automatic", "start"])
    }

    func testLaunchReadyIsIdempotent() async {
        let calls = LockIsolated<[String]>([])
        let store = TestStore(initialState: UpdaterState()) {
            UpdaterFeature()
        } withDependencies: {
            $0.updaterClient.configure = { calls.withValue { $0.append("configure") } }
            $0.updaterClient.startAtLaunch = { calls.withValue { $0.append("start") } }
            $0.updaterClient.setAutomaticUpdate = { _ in calls.withValue { $0.append("automatic") } }
        }

        await store.send(.launchReady) {
            $0.didConfigure = true
            $0.didStartAtLaunch = true
        }
        await store.finish()
        await store.send(.launchReady)
        await store.finish()

        XCTAssertEqual(calls.value, ["configure", "automatic", "start"])
    }

    func testCheckAndAutomaticUpdateAreAvailableSignedOut() async {
        let calls = LockIsolated<[String]>([])
        let store = TestStore(initialState: UpdaterState()) {
            UpdaterFeature()
        } withDependencies: {
            $0.updaterClient.checkForUpdates = { calls.withValue { $0.append("check") } }
            $0.updaterClient.setAutomaticUpdate = { _ in calls.withValue { $0.append("automatic") } }
        }

        await store.send(.checkForUpdates)
        await store.send(.setAutomaticUpdate(true))
        await store.finish()

        XCTAssertEqual(calls.value, ["check", "automatic"])
    }

    func testTamperedManifestIsRejected() throws {
        let fixture = try makeManifestFixture()
        var tampered = fixture.manifest
        tampered = ReleaseManifest(
            artifact: tampered.artifact,
            releasedAt: tampered.releasedAt,
            signature: tampered.signature,
            version: "0.8.3",
        )

        XCTAssertThrowsError(try VerifiedReleaseCandidate.verifiedIdentity(
            manifestData: JSONEncoder().encode(tampered),
            artifactURL: fixture.artifactURL,
            now: fixture.now,
            publicKey: fixture.publicKey,
        ))
    }

    func testChecksumMismatchIsRejected() throws {
        let fixture = try makeManifestFixture()
        let invalid = ReleaseManifest(
            artifact: .init(
                sha256: "not-a-sha256",
                sizeBytes: fixture.manifest.artifact.sizeBytes,
                sparkleEd25519Signature: fixture.manifest.artifact.sparkleEd25519Signature,
                url: fixture.manifest.artifact.url,
            ),
            releasedAt: fixture.manifest.releasedAt,
            signature: fixture.manifest.signature,
            version: fixture.manifest.version,
        )

        XCTAssertThrowsError(try VerifiedReleaseCandidate.verifiedIdentity(
            manifestData: JSONEncoder().encode(invalid),
            artifactURL: fixture.artifactURL,
            now: fixture.now,
            publicKey: fixture.publicKey,
        )) { error in
            XCTAssertEqual(error as? ReleaseManifestError, .invalidArtifactChecksum)
        }
    }

    func testInvalidSignatureIsRejected() throws {
        let fixture = try makeManifestFixture()
        let invalid = ReleaseManifest(
            artifact: fixture.manifest.artifact,
            releasedAt: fixture.manifest.releasedAt,
            signature: Data(repeating: 0, count: 64).base64EncodedString(),
            version: fixture.manifest.version,
        )

        XCTAssertThrowsError(try VerifiedReleaseCandidate.verifiedIdentity(
            manifestData: JSONEncoder().encode(invalid),
            artifactURL: fixture.artifactURL,
            now: fixture.now,
            publicKey: fixture.publicKey,
        )) { error in
            XCTAssertEqual(error as? ReleaseManifestError, .invalidSignature)
        }
    }

    func testMalformedIdentityIsRejected() throws {
        let fixture = try makeManifestFixture(releasedAt: "2023-11-14T22:13:20+00:00")

        XCTAssertThrowsError(try VerifiedReleaseCandidate.verifiedIdentity(
            manifestData: fixture.data,
            artifactURL: fixture.artifactURL,
            now: fixture.now,
            publicKey: fixture.publicKey,
        )) { error in
            XCTAssertEqual(error as? AppVersionInfo.ReleaseMetadataError, .nonUTCReleasedAt)
        }
    }

    func testValidSignedOutCandidatePassesWithoutAccessMetadata() throws {
        let fixture = try makeManifestFixture()
        let identity = try VerifiedReleaseCandidate.verifiedIdentity(
            manifestData: fixture.data,
            artifactURL: fixture.artifactURL,
            now: fixture.now,
            publicKey: fixture.publicKey,
        )

        XCTAssertNoThrow(try SparkleUpdateEligibilityGate.requireCandidate(candidate: identity))
    }

    private struct ManifestFixture {
        let artifactURL: URL
        let data: Data
        let manifest: ReleaseManifest
        let now: Date
        let publicKey: String
    }

    private func makeManifestFixture(
        checksum: String = String(repeating: "a", count: 64),
        releasedAt: String = "2023-11-14T22:13:20Z",
    ) throws -> ManifestFixture {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let artifactURL =
            try XCTUnwrap(URL(string: "https://downloads.voyager.fm/releases/versions/0.8.2/Voyager-0.8.2.zip"))
        let privateKey = Curve25519.Signing.PrivateKey()
        let unsigned = ReleaseManifest(
            artifact: .init(
                sha256: checksum,
                sizeBytes: 1,
                sparkleEd25519Signature: Data(repeating: 0, count: 64).base64EncodedString(),
                url: artifactURL.absoluteString,
            ),
            releasedAt: releasedAt,
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
        return try ManifestFixture(
            artifactURL: artifactURL,
            data: JSONEncoder().encode(manifest),
            manifest: manifest,
            now: now,
            publicKey: privateKey.publicKey.rawRepresentation.base64EncodedString(),
        )
    }
}
