import ComposableArchitecture
import Foundation
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
    public var chatDefaultSettings: AiChatDefaultSettings
    public var chatModelsByProvider: [AiProvider: [AiProviderModel]]
    public var chatModelCatalogPhase: AiChatModelCatalogPhase
    public var chatModelRequestID: UUID?
    public var chatModelLoadError: String?

    public init(
        didBootstrap: Bool = false,
        bootstrapPhase: AiSettingsBootstrapPhase = .idle,
        rows: IdentifiedArrayOf<AiConnectionRowState>? = nil,
        collectionSearchSettings: CollectionSearchAISettings = .default,
        collectionSearchModelsByProvider: [AiProvider: [AiProviderModel]] = [:],
        collectionSearchLoadError: String? = nil,
        chatDefaultSettings: AiChatDefaultSettings = .default,
        chatModelsByProvider: [AiProvider: [AiProviderModel]] = [:],
        chatModelCatalogPhase: AiChatModelCatalogPhase = .idle,
        chatModelRequestID: UUID? = nil,
        chatModelLoadError: String? = nil,
    ) {
        self.didBootstrap = didBootstrap
        self.bootstrapPhase = bootstrapPhase
        self.rows = rows ?? Self.catalogRows()
        self.collectionSearchSettings = collectionSearchSettings
        self.collectionSearchModelsByProvider = collectionSearchModelsByProvider
        self.collectionSearchLoadError = collectionSearchLoadError
        self.chatDefaultSettings = chatDefaultSettings
        self.chatModelsByProvider = chatModelsByProvider
        self.chatModelCatalogPhase = chatModelCatalogPhase
        self.chatModelRequestID = chatModelRequestID
        self.chatModelLoadError = chatModelLoadError
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

    public var connectedProviderDescriptors: [ProviderDescriptor] {
        let connectedProviders = Set(rows.filter { $0.connectionState == .connected }.map(\.provider))
        return ProviderDescriptor.v1Catalog
            .filter { connectedProviders.contains($0.provider) }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    public var hasConnectedProviders: Bool {
        !connectedProviderDescriptors.isEmpty
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
            .some(AiThinkingSelection.none)
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

    public var chatSelectedProvider: AiProvider? {
        guard let rawValue = chatDefaultSettings.provider?.rawValue else { return nil }
        return AiProvider(rawValue: rawValue)
    }

    public var chatSelectedProviderIsAvailable: Bool {
        guard let provider = chatSelectedProvider else { return false }
        return rows[id: provider]?.connectionState == .connected
    }

    public var chatSelectedProviderIsUnavailable: Bool {
        chatDefaultSettings.provider != nil && !chatSelectedProviderIsAvailable
    }

    public var chatAvailableModels: [AiProviderModel] {
        guard let provider = chatSelectedProvider else { return [] }
        return chatModelsByProvider[provider] ?? []
    }

    public var chatSelectedModel: AiProviderModel? {
        guard let selection = chatDefaultSettings.model,
              selection.providerRawValue == chatDefaultSettings.provider?.rawValue,
              let provider = AiProvider(rawValue: selection.providerRawValue)
        else { return nil }

        return chatModelsByProvider[provider]?.first {
            $0.rawModelID == selection.modelRawValue || $0.id.rawValue == selection.modelRawValue
        }
    }

    public var chatSelectedModelIsUnavailable: Bool {
        chatDefaultSettings.model != nil && chatSelectedModel == nil
    }

    public var chatThinkingSelection: AiThinkingSelection? {
        switch chatDefaultSettings.thinking {
        case .providerDefault:
            nil
        case .none:
            .some(AiThinkingSelection.none)
        case let .effort(rawValue):
            AiThinkingEffort(rawValue: rawValue).map(AiThinkingSelection.effort)
        case let .tokenBudget(value):
            .tokenBudget(value)
        }
    }

    public var chatThinkingOptions: [AiThinkingOption] {
        guard let model = chatSelectedModel else {
            return [
                AiThinkingOption(selection: nil, title: "Provider default"),
            ]
        }

        let options = AiThinkingSelectionPolicy.options(
            capability: model.thinkingCapability,
            supportsNone: model.supportsThinkingNone,
        )
        if !options.isEmpty { return options }

        return [
            AiThinkingOption(
                selection: nil,
                title: AiThinkingSelectionPolicy.defaultLabel(for: model.thinkingCapability),
            ),
        ]
    }

    public var chatThinkingIsUnavailable: Bool {
        guard chatDefaultSettings.thinking != .providerDefault else { return false }
        guard let model = chatSelectedModel,
              let selection = chatThinkingSelection
        else { return true }

        return AiThinkingSelectionPolicy.normalize(
            selection,
            capability: model.thinkingCapability,
            supportsNone: model.supportsThinkingNone,
        ) != selection
    }
}

public enum AiChatModelCatalogPhase: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case failed
}

/// AI Settings bootstrap 단계 상태 머신.
///
/// 상태 전이표:
/// - `.idle`: bootstrap 미시작. rows는 `catalogRows()`로 즉시 채워지므로 UI는
///   spinner 없이 placeholder rows를 표시할 수 있음.
/// - `.loading`: bootstrap 진행 중. rows는 여전히 존재하며, file load 직후
///   `.bootstrapCompleted` 가 initial results를 row에 반영함.
/// - `.loaded`: initial results 반영 완료. verification pending은 row의
///   `connectionState`(예: `.checkingStatus`)로 표현.
/// - `.failed`: connections file load 실패. rows는 보존되고 retry로 복구.
///
/// 전이:
/// ```
/// .idle  ──onAppear──▶ .loading ──bootstrapCompleted──▶ .loaded
///                          │                                ▲
///                          └──bootstrapFailed──▶ .failed ──retry──▶ .loading
///                                                       │
///                                       bootstrapVerificationCompleted 는
///                                       row만 갱신하고 `.loaded` 유지
/// ```
public enum AiSettingsBootstrapPhase: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case failed
}
