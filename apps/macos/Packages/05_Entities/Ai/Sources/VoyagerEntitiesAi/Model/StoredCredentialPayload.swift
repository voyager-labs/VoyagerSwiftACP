import Foundation

/// Persisted credential payload for a provider connection.
/// Uses a "kind" discriminator for JSON compatibility with the file schema.
public enum StoredCredentialPayload: Equatable, Sendable {
    case oauth(OAuthCredentialFile)
    case apiKey(APIKeyCredentialFile)
}

/// OAuth credential data persisted to the local config file.
public struct OAuthCredentialFile: Equatable, Sendable {
    public let accessToken: String
    public let refreshToken: String?
    public let idToken: String?
    public let tokenType: String?
    public let scopes: [String]
    public let expiresAtMs: Int64?
    public let chatGPTAccountId: String?

    public init(
        accessToken: String,
        refreshToken: String? = nil,
        idToken: String? = nil,
        tokenType: String? = nil,
        scopes: [String] = [],
        expiresAtMs: Int64? = nil,
        chatGPTAccountId: String? = nil
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.idToken = idToken
        self.tokenType = tokenType
        self.scopes = scopes
        self.expiresAtMs = expiresAtMs
        self.chatGPTAccountId = chatGPTAccountId
    }
}

/// API key credential data persisted to the local config file.
public struct APIKeyCredentialFile: Equatable, Sendable {
    public let secret: String

    public init(secret: String) {
        self.secret = secret
    }
}

// MARK: - Codable

extension StoredCredentialPayload: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        switch kind {
        case "oauth":
            self = try .oauth(OAuthCredentialFile(from: decoder))
        case "apiKey":
            self = try .apiKey(APIKeyCredentialFile(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: container,
                debugDescription: "Unknown credential kind: \(kind)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .oauth(credential):
            try container.encode("oauth", forKey: .kind)
            try credential.encode(to: encoder)
        case let .apiKey(credential):
            try container.encode("apiKey", forKey: .kind)
            try credential.encode(to: encoder)
        }
    }
}

extension OAuthCredentialFile: Codable {}
extension APIKeyCredentialFile: Codable {}

// MARK: - Redaction

public extension StoredCredentialPayload {
    /// Returns a redacted copy suitable for logging/debugging.
    /// Replaces all secret values with "****".
    var redacted: StoredCredentialPayload {
        switch self {
        case let .oauth(oauth):
            return .oauth(
                OAuthCredentialFile(
                    accessToken: "****",
                    refreshToken: oauth.refreshToken != nil ? "****" : nil,
                    idToken: oauth.idToken != nil ? "****" : nil,
                    tokenType: oauth.tokenType,
                    scopes: oauth.scopes,
                    expiresAtMs: oauth.expiresAtMs,
                    chatGPTAccountId: oauth.chatGPTAccountId
                )
            )
        case .apiKey:
            return .apiKey(APIKeyCredentialFile(secret: "****"))
        }
    }
}

extension StoredCredentialPayload: CustomDebugStringConvertible {
    public var debugDescription: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard
            let data = try? encoder.encode(redacted),
            let json = String(data: data, encoding: .utf8)
        else { return "StoredCredentialPayload(redaction-failed)" }
        return json
    }
}
