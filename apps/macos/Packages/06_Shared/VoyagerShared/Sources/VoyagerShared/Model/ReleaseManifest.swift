import CryptoKit
import Foundation

public struct ReleaseIdentity: Equatable, Sendable {
    public let releasedAt: Date
    public let releasedAtString: String

    public init(releasedAt: String?, now: Date = .now) throws {
        guard let releasedAt, !releasedAt.isEmpty else {
            throw AppVersionInfo.ReleaseMetadataError.missingReleasedAt
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        guard let date = formatter.date(from: releasedAt) else {
            throw AppVersionInfo.ReleaseMetadataError.malformedReleasedAt
        }
        guard releasedAt.hasSuffix("Z") else {
            throw AppVersionInfo.ReleaseMetadataError.nonUTCReleasedAt
        }
        guard formatter.string(from: date) == releasedAt else {
            throw AppVersionInfo.ReleaseMetadataError.malformedReleasedAt
        }
        guard date <= now else {
            throw AppVersionInfo.ReleaseMetadataError.futureReleasedAt
        }

        self.releasedAt = date
        releasedAtString = releasedAt
    }
}

public struct ReleaseManifestArtifact: Codable, Equatable, Sendable {
    public let sha256: String
    public let sizeBytes: Int
    public let sparkleEd25519Signature: String
    public let url: String

    public init(
        sha256: String,
        sizeBytes: Int,
        sparkleEd25519Signature: String,
        url: String,
    ) {
        self.sha256 = sha256
        self.sizeBytes = sizeBytes
        self.sparkleEd25519Signature = sparkleEd25519Signature
        self.url = url
    }

    enum CodingKeys: String, CodingKey {
        case sha256
        case sizeBytes = "size_bytes"
        case sparkleEd25519Signature = "sparkle_ed25519_signature"
        case url
    }
}

public struct ReleaseManifest: Codable, Equatable, Sendable {
    public static let schemaVersion = 1
    public static let sparkleKeyID = "sparkle-ed25519-v1"
    public static let sparklePublicKey = "NomZB47jirICFt7N3J9K+ONptIwZig9UdpEnAiC1JJI="

    public let artifact: ReleaseManifestArtifact
    public let keyID: String
    public let releasedAt: String
    public let schemaVersion: Int
    public let signature: String
    public let version: String

    enum CodingKeys: String, CodingKey {
        case artifact
        case keyID = "key_id"
        case releasedAt = "released_at"
        case schemaVersion = "schema_version"
        case signature
        case version
    }

    public init(
        artifact: ReleaseManifestArtifact,
        releasedAt: String,
        signature: String,
        version: String,
        keyID: String = Self.sparkleKeyID,
        schemaVersion: Int = Self.schemaVersion,
    ) {
        self.artifact = artifact
        self.keyID = keyID
        self.releasedAt = releasedAt
        self.schemaVersion = schemaVersion
        self.signature = signature
        self.version = version
    }

    public func canonicalPayload() throws -> Data {
        try validateFields()
        let artifactChecksum = try Self.jsonString(artifact.sha256)
        let artifactSignature = try Self.jsonString(artifact.sparkleEd25519Signature)
        let artifactURL = try Self.jsonString(artifact.url)
        let manifestKeyID = try Self.jsonString(keyID)
        let manifestReleasedAt = try Self.jsonString(releasedAt)
        let manifestVersion = try Self.jsonString(version)
        let artifactPayload = [
            "{\"sha256\":\(artifactChecksum),\"size_bytes\":\(artifact.sizeBytes),",
            "\"sparkle_ed25519_signature\":\(artifactSignature),\"url\":\(artifactURL)}",
        ].joined()
        let payload = [
            "{\"artifact\":\(artifactPayload),\"key_id\":\(manifestKeyID),",
            "\"released_at\":\(manifestReleasedAt),\"schema_version\":\(schemaVersion),",
            "\"version\":\(manifestVersion)}",
        ].joined()
        return Data(payload.utf8)
    }

    public func verifiedReleaseIdentity(
        publicKey: String = Self.sparklePublicKey,
        now: Date = .now,
    ) throws -> ReleaseIdentity {
        let keyData = try Self.base64Data(publicKey, error: .invalidPublicKey)
        let signatureData = try Self.base64Data(signature, error: .missingOrInvalidSignature)
        let verifier = try Curve25519.Signing.PublicKey(rawRepresentation: keyData)
        let payload = try canonicalPayload()
        guard verifier.isValidSignature(signatureData, for: payload) else {
            throw ReleaseManifestError.invalidSignature
        }
        return try ReleaseIdentity(releasedAt: releasedAt, now: now)
    }

    private func validateFields() throws {
        guard schemaVersion == Self.schemaVersion else {
            throw ReleaseManifestError.unsupportedSchemaVersion
        }
        guard keyID == Self.sparkleKeyID else {
            throw ReleaseManifestError.unsupportedKeyID
        }
        guard artifact.sha256.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil else {
            throw ReleaseManifestError.invalidArtifactChecksum
        }
        guard artifact.sizeBytes >= 0 else {
            throw ReleaseManifestError.invalidArtifactSize
        }
        let sparkleSignature = try Self.base64Data(
            artifact.sparkleEd25519Signature,
            error: .invalidArtifactSignature,
        )
        guard sparkleSignature.count == 64 else {
            throw ReleaseManifestError.invalidArtifactSignature
        }
    }

    private static func jsonString(_ value: String) throws -> String {
        let data = try JSONSerialization.data(
            withJSONObject: [value],
            options: [.withoutEscapingSlashes],
        )
        guard let encoded = String(data: data, encoding: .utf8), encoded.count >= 2 else {
            throw ReleaseManifestError.invalidCanonicalPayload
        }
        return String(encoded.dropFirst().dropLast())
    }

    private static func base64Data(_ value: String, error: ReleaseManifestError) throws -> Data {
        guard let data = Data(base64Encoded: value) else {
            throw error
        }
        return data
    }
}

public enum ReleaseManifestError: Error, Equatable {
    case unsupportedSchemaVersion
    case unsupportedKeyID
    case invalidArtifactChecksum
    case invalidArtifactSize
    case invalidArtifactSignature
    case missingOrInvalidSignature
    case invalidPublicKey
    case invalidSignature
    case invalidCanonicalPayload
}
