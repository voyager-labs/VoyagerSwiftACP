import CryptoKit
import Foundation

/// PKCE verifier/challenge pair generated for a single OAuth flow.
public struct PKCECodes: Sendable, Equatable {
    public let verifier: String
    public let challenge: String
}

/// PKCE (Proof Key for Code Exchange) utilities for OAuth flows.
///
/// Uses `CryptoKit.SHA256` for challenge generation and `SystemRandomNumberGenerator`
/// for cryptographically-suitable random values.
public enum PKCE {
    /// Generate a complete PKCE verifier/challenge pair.
    public static func generate() -> PKCECodes {
        let verifier = generateVerifier()
        let challenge = generateChallenge(from: verifier)
        return PKCECodes(verifier: verifier, challenge: challenge)
    }

    /// Generate a PKCE code verifier — 32 random bytes, base64url-encoded (~43 chars).
    public static func generateVerifier() -> String {
        let bytes = randomBytes(count: 32)
        return Data(bytes).base64URLEncoded
    }

    /// Generate a PKCE code challenge by SHA-256 hashing the verifier and base64url-encoding.
    public static func generateChallenge(from verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncoded
    }

    /// Generate a random state parameter for CSRF protection.
    public static func generateState() -> String {
        let bytes = randomBytes(count: 32)
        return Data(bytes).base64URLEncoded
    }
}

// MARK: - Private

extension PKCE {
    private static func randomBytes(count: Int) -> [UInt8] {
        (0 ..< count).map { _ in UInt8.random(in: 0 ... 255) }
    }
}

// MARK: - Data + Base64URL

extension Data {
    /// Base64url encoding (RFC 4648 §5): no padding, `+` → `-`, `/` → `_`.
    var base64URLEncoded: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "="))
    }
}
