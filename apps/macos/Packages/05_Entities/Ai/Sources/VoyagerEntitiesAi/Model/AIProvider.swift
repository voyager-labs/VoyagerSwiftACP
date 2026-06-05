import Foundation

/// Locked v1 provider set for AI connections.
/// Only three providers are supported: ChatGPT Codex (OAuth), OpenAI (API key), Anthropic (API key).
public enum AiProvider: String, CaseIterable, Codable, Sendable, Equatable, Hashable {
    case chatgptCodex
    case openai
    case anthropic
}

/// Credential semantics for a provider — what *kind* of credential is stored.
/// `.codexCLI` is retained for backward-compatible decoding only; new writes emit `.oauth`.
public enum ProviderAuthMethod: String, Codable, Sendable, Equatable, Hashable {
    case oauth
    case apiKey
    case codexCLI
}

/// How the user originally connected to a provider.
/// This is metadata only and does not drive verification logic.
public enum ProviderConnectPath: String, Codable, Sendable, Equatable, Hashable {
    case browserLogin
    case deviceAuth
    case legacyImport
}

public struct ProviderDescriptor: Equatable, Sendable {
    public let provider: AiProvider
    public let displayName: String
    public let authMethod: ProviderAuthMethod
    public let sortOrder: Int
    public let browserLoginAvailable: Bool
    public let deviceAuthAvailable: Bool

    public init(
        provider: AiProvider,
        displayName: String,
        authMethod: ProviderAuthMethod,
        sortOrder: Int,
        browserLoginAvailable: Bool = true,
        deviceAuthAvailable: Bool = false
    ) {
        self.provider = provider
        self.displayName = displayName
        self.authMethod = authMethod
        self.sortOrder = sortOrder
        self.browserLoginAvailable = browserLoginAvailable
        self.deviceAuthAvailable = deviceAuthAvailable
    }

    public var primaryConnectPath: ProviderConnectPath {
        switch provider {
        case .chatgptCodex: .browserLogin
        case .openai, .anthropic: .browserLogin
        }
    }

    public var secondaryConnectPaths: [ProviderConnectPath] {
        switch provider {
        case .chatgptCodex: [.deviceAuth, .legacyImport]
        case .openai, .anthropic: []
        }
    }

    public static let v1Catalog: [ProviderDescriptor] = [
        ProviderDescriptor(
            provider: .chatgptCodex,
            displayName: "ChatGPT Codex",
            authMethod: .oauth,
            sortOrder: 0,
            deviceAuthAvailable: false
        ),
        ProviderDescriptor(
            provider: .openai,
            displayName: "OpenAI",
            authMethod: .apiKey,
            sortOrder: 1
        ),
        ProviderDescriptor(
            provider: .anthropic,
            displayName: "Anthropic",
            authMethod: .apiKey,
            sortOrder: 2
        ),
    ]

    public static let supportedProviders: Set<AiProvider> = Set(v1Catalog.map(\.provider))

    public static func descriptor(for provider: AiProvider) -> ProviderDescriptor? {
        v1Catalog.first { $0.provider == provider }
    }
}
