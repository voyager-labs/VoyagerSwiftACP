import Foundation

public struct AIProviderQuerySelectionContext: Equatable, Sendable {
    public let provider: AiProvider
    public let record: ProviderRecordFile
    public let credential: StoredCredentialPayload?

    public init(
        provider: AiProvider,
        record: ProviderRecordFile,
        credential: StoredCredentialPayload?,
    ) {
        self.provider = provider
        self.record = record
        self.credential = credential
    }
}

public enum AIProviderQuerySelectionError: Equatable, Sendable, Error {
    case notConfigured
    case invalidCredential(provider: AiProvider, expected: ProviderAuthMethod)
    case providerUnavailable(provider: AiProvider, reason: ProviderStatusReason)
}

public enum AIProviderQuerySelection {
    private enum SelectionState {
        case select(AIProviderQuerySelectionContext)
        case invalidCredential(AIProviderQuerySelectionError)
        case providerUnavailable(AIProviderQuerySelectionError)
        case skip
    }

    private struct SelectionCandidates {
        private(set) var invalidCredential: AIProviderQuerySelectionError?
        private(set) var providerUnavailable: AIProviderQuerySelectionError?

        mutating func recordInvalidCredential(_ error: AIProviderQuerySelectionError) {
            invalidCredential = invalidCredential ?? error
        }

        mutating func recordProviderUnavailable(_ error: AIProviderQuerySelectionError) {
            providerUnavailable = providerUnavailable ?? error
        }
    }

    public static func select(from file: AIConnectionsFile)
        -> Result<AIProviderQuerySelectionContext, AIProviderQuerySelectionError>
    {
        let catalog = ProviderDescriptor.v1Catalog.sorted { $0.sortOrder < $1.sortOrder }
        guard catalog.isEmpty == false else {
            return .failure(.notConfigured)
        }

        if let lastUsedProviderId = file.lastUsedProviderId,
           let selection = selection(for: lastUsedProviderId, file: file, catalog: catalog)
        {
            return selection
        }

        return firstCatalogSelection(file: file, catalog: catalog)
    }

    public static func select(
        provider providerId: AiProvider,
        from file: AIConnectionsFile,
    ) -> Result<AIProviderQuerySelectionContext, AIProviderQuerySelectionError> {
        let catalog = ProviderDescriptor.v1Catalog.sorted { $0.sortOrder < $1.sortOrder }
        guard catalog.isEmpty == false else {
            return .failure(.notConfigured)
        }

        guard let descriptor = catalog.first(where: { $0.provider == providerId }) else {
            return .failure(.providerUnavailable(provider: providerId, reason: .providerUnsupportedInBuild))
        }

        guard let record = file.providers[providerId.rawValue] else {
            return .failure(.providerUnavailable(provider: providerId, reason: .unknown))
        }

        switch explicitSelectionState(for: descriptor, record: record) {
        case let .select(context):
            return .success(context)
        case let .invalidCredential(error):
            return .failure(error)
        case let .providerUnavailable(error):
            return .failure(error)
        case .skip:
            return .failure(.providerUnavailable(provider: providerId, reason: .unknown))
        }
    }

    public static func autoCandidates(from file: AIConnectionsFile) -> [AIProviderQuerySelectionContext] {
        let catalog = ProviderDescriptor.v1Catalog.sorted { $0.sortOrder < $1.sortOrder }
        guard catalog.isEmpty == false else { return [] }

        var orderedProviders: [AiProvider] = []
        if let lastUsedProviderId = file.lastUsedProviderId {
            orderedProviders.append(lastUsedProviderId)
        }
        orderedProviders.append(contentsOf: catalog.map(\.provider).filter { $0 != file.lastUsedProviderId })

        var seenProviders: Set<AiProvider> = []
        var candidates: [AIProviderQuerySelectionContext] = []

        for provider in orderedProviders where seenProviders.insert(provider).inserted {
            guard let descriptor = catalog.first(where: { $0.provider == provider }),
                  let record = file.providers[provider.rawValue]
            else {
                continue
            }

            switch selectionState(for: descriptor, record: record) {
            case let .select(context):
                candidates.append(context)
            case .invalidCredential, .providerUnavailable, .skip:
                continue
            }
        }

        return candidates
    }

    private static func firstCatalogSelection(
        file: AIConnectionsFile,
        catalog: [ProviderDescriptor],
    ) -> Result<AIProviderQuerySelectionContext, AIProviderQuerySelectionError> {
        var candidates = SelectionCandidates()

        for descriptor in catalog {
            guard let record = file.providers[descriptor.provider.rawValue] else {
                continue
            }

            switch selectionState(for: descriptor, record: record) {
            case let .select(context):
                return .success(context)
            case let .invalidCredential(error):
                candidates.recordInvalidCredential(error)
            case let .providerUnavailable(error):
                candidates.recordProviderUnavailable(error)
            case .skip:
                continue
            }
        }

        if let invalidCredentialCandidate = candidates.invalidCredential {
            return .failure(invalidCredentialCandidate)
        }

        if let providerUnavailableCandidate = candidates.providerUnavailable {
            return .failure(providerUnavailableCandidate)
        }

        return .failure(.notConfigured)
    }

    private static func selection(
        for providerId: AiProvider,
        file: AIConnectionsFile,
        catalog: [ProviderDescriptor],
    ) -> Result<AIProviderQuerySelectionContext, AIProviderQuerySelectionError>? {
        guard let descriptor = catalog.first(where: { $0.provider == providerId }),
              let record = file.providers[providerId.rawValue]
        else {
            return nil
        }

        switch selectionState(for: descriptor, record: record) {
        case let .select(context):
            return .success(context)
        case let .invalidCredential(error):
            return .failure(error)
        case let .providerUnavailable(error):
            return .failure(error)
        case .skip:
            return nil
        }
    }

    private static func selectionState(
        for descriptor: ProviderDescriptor,
        record: ProviderRecordFile,
    ) -> SelectionState {
        switch record.snapshot.lastKnownStatus {
        case .connected:
            if descriptor.provider == .chatgptCodex {
                return .select(AIProviderQuerySelectionContext(
                    provider: descriptor.provider,
                    record: record,
                    credential: nil,
                ))
            }
            guard let credential = record.credential else {
                return .invalidCredential(.invalidCredential(
                    provider: descriptor.provider,
                    expected: descriptor.authMethod,
                ))
            }
            guard credentialMatches(credential, authMethod: descriptor.authMethod) else {
                return .invalidCredential(.invalidCredential(
                    provider: descriptor.provider,
                    expected: descriptor.authMethod,
                ))
            }
            return .select(AIProviderQuerySelectionContext(
                provider: descriptor.provider,
                record: record,
                credential: credential,
            ))

        case .unavailable:
            return .providerUnavailable(
                .providerUnavailable(
                    provider: descriptor.provider,
                    reason: record.snapshot.lastErrorCode == .none ? .providerUnsupportedInBuild : record.snapshot
                        .lastErrorCode,
                ),
            )

        case .connectionFailed,
             .disconnected,
             .notVerified,
             .connectInProgress,
             .checkingStatus,
             .disconnecting:
            return .skip
        }
    }

    private static func explicitSelectionState(
        for descriptor: ProviderDescriptor,
        record: ProviderRecordFile,
    ) -> SelectionState {
        switch record.snapshot.lastKnownStatus {
        case .connected:
            if descriptor.provider == .chatgptCodex {
                return .select(AIProviderQuerySelectionContext(
                    provider: descriptor.provider,
                    record: record,
                    credential: nil,
                ))
            }
            guard let credential = record.credential else {
                return .invalidCredential(.invalidCredential(
                    provider: descriptor.provider,
                    expected: descriptor.authMethod,
                ))
            }
            guard credentialMatches(credential, authMethod: descriptor.authMethod) else {
                return .invalidCredential(.invalidCredential(
                    provider: descriptor.provider,
                    expected: descriptor.authMethod,
                ))
            }
            return .select(AIProviderQuerySelectionContext(
                provider: descriptor.provider,
                record: record,
                credential: credential,
            ))

        case .unavailable:
            return .providerUnavailable(
                .providerUnavailable(
                    provider: descriptor.provider,
                    reason: record.snapshot.lastErrorCode == .none ? .providerUnsupportedInBuild : record.snapshot
                        .lastErrorCode,
                ),
            )

        case .connectionFailed,
             .disconnected,
             .notVerified,
             .connectInProgress,
             .checkingStatus,
             .disconnecting:
            return .providerUnavailable(
                .providerUnavailable(
                    provider: descriptor.provider,
                    reason: record.snapshot.lastErrorCode == .none ? .unknown : record.snapshot.lastErrorCode,
                ),
            )
        }
    }

    private static func credentialMatches(
        _ credential: StoredCredentialPayload,
        authMethod: ProviderAuthMethod,
    ) -> Bool {
        switch authMethod {
        case .oauth, .codexCLI:
            if case .oauth = credential { return true }
            return false
        case .apiKey:
            if case .apiKey = credential { return true }
            return false
        }
    }
}
