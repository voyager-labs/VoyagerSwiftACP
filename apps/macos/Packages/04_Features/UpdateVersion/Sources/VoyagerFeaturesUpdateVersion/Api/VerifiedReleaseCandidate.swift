import Foundation
import VoyagerShared

enum VerifiedReleaseCandidate {
    enum CandidateVerificationError: Error {
        case artifactMismatch
    }

    static func manifestURL(for artifactURL: URL) -> URL {
        artifactURL.deletingLastPathComponent().appendingPathComponent("release-manifest-v1.json")
    }

    static func verifiedIdentity(
        manifestData: Data,
        artifactURL: URL,
        now: Date,
        publicKey: String = ReleaseManifest.sparklePublicKey,
    ) throws -> ReleaseIdentity {
        let decoder = JSONDecoder()
        let manifest = try decoder.decode(ReleaseManifest.self, from: manifestData)
        guard manifest.artifact.url == artifactURL.absoluteString else {
            throw CandidateVerificationError.artifactMismatch
        }
        return try manifest.verifiedReleaseIdentity(publicKey: publicKey, now: now)
    }
}
