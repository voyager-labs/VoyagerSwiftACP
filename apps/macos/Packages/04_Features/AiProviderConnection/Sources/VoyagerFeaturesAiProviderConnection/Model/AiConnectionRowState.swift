import ComposableArchitecture
import VoyagerEntitiesAi

/// Per-provider row state for the Settings AI connection list.
/// Each row maps to exactly one `AiProvider` from the v1 catalog.
@ObservableState
public struct AiConnectionRowState: Equatable, Identifiable {
    public let provider: AiProvider
    public var connectionState: ProviderConnectionState
    public var statusReason: ProviderStatusReason
    public var flowState: AiConnectionFlowState
    public var enteredKey: String
    public var isVerifying: Bool
    public var isShowingDisconnectConfirmation: Bool

    public var id: AiProvider {
        provider
    }

    /// Convenience: true while the disconnect effect is in flight.
    public var isDisconnecting: Bool {
        flowState == .disconnecting
    }

    public init(
        provider: AiProvider,
        connectionState: ProviderConnectionState = .notVerified,
        statusReason: ProviderStatusReason = .none,
        flowState: AiConnectionFlowState = .idle,
        enteredKey: String = "",
        isVerifying: Bool = false,
        isShowingDisconnectConfirmation: Bool = false,
    ) {
        self.provider = provider
        self.connectionState = connectionState
        self.statusReason = statusReason
        self.flowState = flowState
        self.enteredKey = enteredKey
        self.isVerifying = isVerifying
        self.isShowingDisconnectConfirmation = isShowingDisconnectConfirmation
    }

    public var displayName: String {
        ProviderDescriptor.descriptor(for: provider)?.displayName ?? provider.rawValue
    }

    public var authMethodLabel: String {
        let method = ProviderDescriptor.descriptor(for: provider)?.authMethod ?? .apiKey
        switch method {
        case .oauth: return "OAuth"
        case .apiKey: return "API Key"
        case .codexCLI: return "Legacy"
        }
    }

    public var primaryAction: ProviderRowAction {
        connectionState.primaryAction
    }
}

/// Tracks in-progress connection flows (connect/disconnect) for a single row.
/// Separate from `ProviderConnectionState` to keep state-machine purity.
public enum AiConnectionFlowState: Equatable, Sendable {
    case idle
    case connecting
    case disconnecting
    case browserLoginInProgress
    case deviceAuthInProgress
}
