import ComposableArchitecture
import VoyagerEntitiesAi

@ObservableState
public struct AiSettingsState: Equatable {
    public var didBootstrap: Bool = false
    public var bootstrapPhase: AiSettingsBootstrapPhase = .idle
    public var rows: IdentifiedArrayOf<AiConnectionRowState>

    public init(
        didBootstrap: Bool = false,
        bootstrapPhase: AiSettingsBootstrapPhase = .idle,
        rows: IdentifiedArrayOf<AiConnectionRowState>? = nil
    ) {
        self.didBootstrap = didBootstrap
        self.bootstrapPhase = bootstrapPhase
        self.rows = rows ?? Self.catalogRows()
    }

    /// Builds initial row states from the v1 provider catalog with all providers `notVerified`.
    public static func catalogRows() -> IdentifiedArrayOf<AiConnectionRowState> {
        IdentifiedArrayOf(
            uniqueElements: ProviderDescriptor.v1Catalog
                .sorted { $0.sortOrder < $1.sortOrder }
                .map { descriptor in
                    AiConnectionRowState(provider: descriptor.provider)
                }
        )
    }
}

public enum AiSettingsBootstrapPhase: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case failed
}
