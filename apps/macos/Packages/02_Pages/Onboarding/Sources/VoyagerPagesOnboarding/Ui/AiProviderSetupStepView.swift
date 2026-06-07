import ComposableArchitecture
import SwiftUI
import VoyagerEntitiesAi
import VoyagerFeaturesAiProviderConnection

struct AiProviderSetupStepView: View {
    let store: StoreOf<AiProviderSetupFeature>

    var body: some View {
        WithViewStore(store, observe: { $0 }, content: { viewStore in
            VStack(alignment: .leading, spacing: 16) {
                header

                if viewStore.bootstrapPhase == .loading {
                    ProgressView("Loading AI providers…")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let loadError = viewStore.loadError {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(loadError)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            Button("Retry") {
                                viewStore.send(.retryBootstrapTapped)
                            }
                            .buttonStyle(.borderedProminent)

                            Button("Set up later") {
                                viewStore.send(.setUpLaterTapped)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                } else {
                    VStack(spacing: 12) {
                        ForEach(viewStore.rows) { row in
                            rowCard(row: row, viewStore: viewStore)
                        }
                    }
                }

                HStack {
                    Spacer()
                    Button("Set up later") {
                        viewStore.send(.setUpLaterTapped)
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewStore.isComplete)
                }
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding(.vertical, 12)
            .onAppear {
                viewStore.send(.onAppear)
            }
        })
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AI Provider Setup")
                .font(.system(size: 24, weight: .semibold))
            Text("Connect a provider now or set it up later.")
                .foregroundStyle(.secondary)
        }
    }

    private func rowCard(
        row: AiConnectionRowState,
        viewStore: ViewStore<AiProviderSetupState, AiProviderSetupAction>,
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.displayName)
                        .font(.headline)
                    Text(row.authMethodLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                Text(statusText(for: row))
                    .font(.caption)
                    .foregroundStyle(statusColor(for: row))
            }

            if row.connectionState == .connectionFailed || row.connectionState == .unavailable {
                Text(reasonText(for: row.statusReason))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            rowActionArea(row: row, viewStore: viewStore)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.quaternary.opacity(0.35)),
        )
    }

    @ViewBuilder
    private func rowActionArea(
        row: AiConnectionRowState,
        viewStore: ViewStore<AiProviderSetupState, AiProviderSetupAction>,
    ) -> some View {
        switch row.connectionState {
        case .connected:
            EmptyView()

        case .connectInProgress:
            Button("Cancel") {
                viewStore.send(.row(.element(id: row.id, action: .cancelButtonTapped)))
            }
            .buttonStyle(.bordered)

        case .notVerified, .disconnected, .connectionFailed:
            if ProviderDescriptor.descriptor(for: row.provider)?.authMethod == .apiKey {
                HStack(spacing: 8) {
                    SecureField("API key", text: Binding(
                        get: { row.enteredKey },
                        set: { viewStore.send(.row(.element(id: row.id, action: .enteredKeyChanged($0)))) },
                    ))
                    .textFieldStyle(.roundedBorder)

                    Button(row.connectionState == .connectionFailed ? "Retry" : "Connect") {
                        viewStore.send(.row(.element(id: row.id, action: .submitAPIKey(row.enteredKey))))
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(row.enteredKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } else {
                Button(row.connectionState == .connectionFailed ? "Retry" : "Connect") {
                    viewStore.send(.row(.element(id: row.id, action: .connectButtonTapped)))
                }
                .buttonStyle(.borderedProminent)
            }

        case .checkingStatus, .disconnecting, .unavailable:
            EmptyView()
        }
    }

    private func statusText(for row: AiConnectionRowState) -> String {
        switch row.connectionState {
        case .notVerified, .disconnected:
            "Not connected"
        case .connectInProgress:
            "Connecting…"
        case .checkingStatus:
            "Checking status…"
        case .connected:
            "Connected"
        case .connectionFailed:
            "Failed"
        case .disconnecting:
            "Disconnecting…"
        case .unavailable:
            "Unavailable"
        }
    }

    private func statusColor(for row: AiConnectionRowState) -> Color {
        switch row.connectionState {
        case .connected:
            .green
        case .connectionFailed, .unavailable:
            .red
        case .connectInProgress, .checkingStatus, .disconnecting:
            .orange
        case .notVerified, .disconnected:
            .secondary
        }
    }

    // swiftlint:disable:next cyclomatic_complexity
    private func reasonText(for reason: ProviderStatusReason) -> String {
        switch reason {
        case .none:
            ""
        case .missingCredential:
            "Missing credential."
        case .invalidPayload:
            "Invalid credential payload."
        case .credentialKindMismatch:
            "Credential type mismatch."
        case .expired:
            "Credential expired."
        case .providerUnsupportedInBuild:
            "This provider is unavailable in the current build."
        case .networkUnavailable:
            "Network unavailable."
        case .verificationFailed:
            "Verification failed."
        case .oauthRejected:
            "OAuth rejected."
        case .invalidAPIKey:
            "Invalid API key."
        case .corruptedProviderRecord:
            "Corrupted provider record."
        case .unknown:
            "Unknown error."
        }
    }
}
