import ComposableArchitecture
import VoyagerEntitiesAi

@ObservableState
struct AiProviderSetupState: Equatable {
    var didBootstrap = false
    var bootstrapPhase: AiProviderSetupBootstrapPhase = .idle
    var loadError: String?
    var choice: AiProviderSetupChoice = .none
    var status: AiProviderSetupStatus = .blocked
    var rows: IdentifiedArrayOf<AiProviderSetupRowState>

    init(rows: IdentifiedArrayOf<AiProviderSetupRowState>? = nil) {
        self.rows = rows ?? Self.catalogRows()
    }

    var isComplete: Bool {
        status == .complete || status == .skipped
    }

    var nextDisabledMessage: String? {
        isComplete ? nil : "Connect a provider or choose Set up later to continue."
    }

    mutating func refreshStatus() {
        if rows.contains(where: { $0.connectionState == .connected }) {
            choice = .providerConnected
            status = .complete
            loadError = nil
            return
        }

        if choice == .setUpLater {
            status = .skipped
            loadError = nil
            return
        }

        if loadError != nil {
            status = .error
            return
        }

        if bootstrapPhase == .loading
            || rows
            .contains(where: { $0.connectionState == .connectInProgress || $0.isVerifying || $0.flowState != .idle
            })
        {
            status = .pending
            return
        }

        status = .blocked
    }

    private static func catalogRows() -> IdentifiedArrayOf<AiProviderSetupRowState> {
        IdentifiedArrayOf(
            uniqueElements: ProviderDescriptor.v1Catalog
                .sorted(by: { $0.sortOrder < $1.sortOrder })
                .map { AiProviderSetupRowState(provider: $0.provider) },
        )
    }
}

enum AiProviderSetupBootstrapPhase: Equatable {
    case idle
    case loading
    case loaded
    case failed
}

enum AiProviderSetupChoice: String, Codable, Equatable {
    case none
    case providerConnected
    case setUpLater
}

enum AiProviderSetupStatus: String, Codable, Equatable {
    case pending
    case complete
    case blocked
    case error
    case skipped
}
