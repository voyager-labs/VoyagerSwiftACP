import ComposableArchitecture
import VoyagerEntitiesAi
import VoyagerEntitiesAppPreferences
import VoyagerFeaturesAiProviderConnection

@ObservableState
public struct AiSettingsState: Equatable {
    public var didBootstrap: Bool = false
    public var bootstrapPhase: AiSettingsBootstrapPhase = .idle
    public var rows: IdentifiedArrayOf<AiConnectionRowState>
    public var collectionSearchSettings: CollectionSearchAISettings
    public var collectionSearchModelsByProvider: [AiProvider: [AiProviderModel]]
    public var collectionSearchLoadError: String?

    public init(
        didBootstrap: Bool = false,
        bootstrapPhase: AiSettingsBootstrapPhase = .idle,
        rows: IdentifiedArrayOf<AiConnectionRowState>? = nil,
        collectionSearchSettings: CollectionSearchAISettings = .default,
        collectionSearchModelsByProvider: [AiProvider: [AiProviderModel]] = [:],
        collectionSearchLoadError: String? = nil,
    ) {
        self.didBootstrap = didBootstrap
        self.bootstrapPhase = bootstrapPhase
        self.rows = rows ?? Self.catalogRows()
        self.collectionSearchSettings = collectionSearchSettings
        self.collectionSearchModelsByProvider = collectionSearchModelsByProvider
        self.collectionSearchLoadError = collectionSearchLoadError
    }

    /// Builds initial row states from the v1 provider catalog with all providers `notVerified`.
    public static func catalogRows() -> IdentifiedArrayOf<AiConnectionRowState> {
        IdentifiedArrayOf(
            uniqueElements: ProviderDescriptor.v1Catalog
                .sorted { $0.sortOrder < $1.sortOrder }
                .map { descriptor in
                    AiConnectionRowState(provider: descriptor.provider)
                },
        )
    }

    public var collectionSearchSelectedProvider: AiProvider? {
        switch collectionSearchSettings.provider {
        case .auto:
            nil
        case let .specific(rawProvider):
            AiProvider(rawValue: rawProvider)
        }
    }

    public var collectionSearchSelectedModel: AiProviderModel? {
        guard case let .specific(providerRaw, modelRaw) = collectionSearchSettings.model,
              let provider = AiProvider(rawValue: providerRaw)
        else { return nil }

        return collectionSearchModelsByProvider[provider]?.first {
            $0.rawModelID == modelRaw || $0.id.rawValue == modelRaw
        }
    }

    public var collectionSearchThinkingSelection: AiThinkingSelection? {
        switch collectionSearchSettings.thinking {
        case .providerDefault:
            nil
        case .none:
            .some(.none)
        case let .effort(rawEffort):
            AiThinkingEffort(rawValue: rawEffort).map { .effort($0) }
        case let .tokenBudget(value):
            .tokenBudget(value)
        }
    }

    public var collectionSearchThinkingOptions: [CollectionSearchAIThinkingOption] {
        CollectionSearchAISelectionPolicy.thinkingOptions(for: collectionSearchSelectedModel)
    }

    public var collectionSearchHasLoadedModels: Bool {
        !collectionSearchModelsByProvider.isEmpty
    }
}

public enum AiSettingsBootstrapPhase: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case failed
}
