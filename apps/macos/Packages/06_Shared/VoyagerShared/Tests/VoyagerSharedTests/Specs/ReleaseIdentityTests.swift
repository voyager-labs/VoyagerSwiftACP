import CryptoKit
import Foundation
@testable import VoyagerShared
import XCTest

final class ReleaseIdentityTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_784_203_201)
    private let releasedAt = "2026-07-16T12:00:00Z"

    func testReleaseIdentityDecodesStrictUTCInstant() throws {
        let identity = try ReleaseIdentity(releasedAt: releasedAt, now: now)

        XCTAssertEqual(identity.releasedAtString, releasedAt)
        XCTAssertEqual(identity.releasedAt, ISO8601DateFormatter().date(from: releasedAt))
    }

    func testReleaseIdentityRejectsInvalidMetadataWithTypedFailures() {
        XCTAssertThrowsError(try ReleaseIdentity(releasedAt: nil, now: now)) {
            XCTAssertEqual($0 as? AppVersionInfo.ReleaseMetadataError, .missingReleasedAt)
        }
        XCTAssertThrowsError(try ReleaseIdentity(releasedAt: "not-a-date", now: now)) {
            XCTAssertEqual($0 as? AppVersionInfo.ReleaseMetadataError, .malformedReleasedAt)
        }
        XCTAssertThrowsError(try ReleaseIdentity(releasedAt: "2026-07-16T12:00:00+09:00", now: now)) {
            XCTAssertEqual($0 as? AppVersionInfo.ReleaseMetadataError, .nonUTCReleasedAt)
        }
        XCTAssertThrowsError(try ReleaseIdentity(releasedAt: "2026-07-16T12:00:02Z", now: now)) {
            XCTAssertEqual($0 as? AppVersionInfo.ReleaseMetadataError, .futureReleasedAt)
        }
    }

    func testManifestVerifiesCompactSortedKeyPayloadWithSameReleaseTimestamp() throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let artifact = ReleaseManifestArtifact(
            sha256: String(repeating: "a", count: 64),
            sizeBytes: 42,
            sparkleEd25519Signature: Data(repeating: 0, count: 64).base64EncodedString(),
            url: "https://downloads.voyager.fm/releases/versions/0.8.2/Voyager-0.8.2.zip",
        )
        let unsignedManifest = ReleaseManifest(
            artifact: artifact,
            releasedAt: releasedAt,
            signature: "",
            version: "0.8.2",
        )
        let signature = try privateKey.signature(for: unsignedManifest.canonicalPayload()).base64EncodedString()
        let manifest = ReleaseManifest(
            artifact: artifact,
            releasedAt: releasedAt,
            signature: signature,
            version: "0.8.2",
        )

        let canonicalPayload = try manifest.canonicalPayload()
        let expectedPayload = [
            "{\"artifact\":{\"sha256\":\"\(String(repeating: "a", count: 64))\",\"size_bytes\":42,",
            "\"sparkle_ed25519_signature\":\"\(Data(repeating: 0, count: 64).base64EncodedString())\",",
            "\"url\":\"https://downloads.voyager.fm/releases/versions/0.8.2/Voyager-0.8.2.zip\"},",
            "\"key_id\":\"sparkle-ed25519-v1\",\"released_at\":\"2026-07-16T12:00:00Z\",",
            "\"schema_version\":1,\"version\":\"0.8.2\"}",
        ].joined()
        XCTAssertEqual(try XCTUnwrap(String(data: canonicalPayload, encoding: .utf8)), expectedPayload)
        XCTAssertEqual(
            try manifest.verifiedReleaseIdentity(
                publicKey: privateKey.publicKey.rawRepresentation.base64EncodedString(),
                now: now,
            ).releasedAtString,
            releasedAt,
        )
    }

    func testManifestRejectsTamperingAndInvalidContractFields() throws {
        let manifest = ReleaseManifest(
            artifact: .init(
                sha256: String(repeating: "a", count: 64),
                sizeBytes: 1,
                sparkleEd25519Signature: Data(repeating: 0, count: 64).base64EncodedString(),
                url: "https://downloads.voyager.fm/Voyager.zip",
            ),
            releasedAt: releasedAt,
            signature: Data(repeating: 0, count: 64).base64EncodedString(),
            version: "0.8.2",
        )

        XCTAssertThrowsError(try manifest.verifiedReleaseIdentity(now: now)) {
            XCTAssertEqual($0 as? ReleaseManifestError, .invalidSignature)
        }
        let invalidChecksum = ReleaseManifest(
            artifact: .init(
                sha256: "uppercase-is-not-canonical",
                sizeBytes: 1,
                sparkleEd25519Signature: Data(repeating: 0, count: 64).base64EncodedString(),
                url: "https://downloads.voyager.fm/Voyager.zip",
            ),
            releasedAt: releasedAt,
            signature: "",
            version: "0.8.2",
        )
        XCTAssertThrowsError(try invalidChecksum.canonicalPayload()) {
            XCTAssertEqual($0 as? ReleaseManifestError, .invalidArtifactChecksum)
        }
    }
}
