import ComposableArchitecture
import SwiftUI
import VoyagerEntitiesAi

struct AiConnectionRowView: View {
    @State private var keyText: String = ""

    let store: StoreOf<AiConnectionRowReducer>

    private static let checkingStatusRawValue = "checkingStatus"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerRow

            if showsAPIKeyEntry {
                apiKeyEntryRow
            }

            if showsProgress {
                progressRow
            }

            if store.connectionState == .connectionFailed, store.statusReason != .none {
                Text(statusReasonDescription)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .padding(.vertical, 4)
        .confirmationDialog(
            "Disconnect \(store.displayName)?",
            isPresented: Binding(
                get: { store.isShowingDisconnectConfirmation },
                set: { _ in store.send(.disconnectCancel) }
            ),
            titleVisibility: .visible
        ) {
            Button("Disconnect", role: .destructive) {
                store.send(.disconnectConfirm)
            }
            Button("Cancel", role: .cancel) {
                store.send(.disconnectCancel)
            }
        } message: {
            Text("Stored credentials for \(store.displayName) will be removed.")
        }
    }

    @ViewBuilder
    private var headerRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(store.displayName)
                    .font(.body)
                Text(store.authMethodLabel)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            statusBadge

            actionButton
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(connectionStateColor)
                .frame(width: 8, height: 8)
            Text(connectionStateLabel)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var connectionStateColor: Color {
        if store.connectionState.rawValue == Self.checkingStatusRawValue {
            return .blue
        }

        switch store.connectionState {
        case .connected:
            return .green
        case .connectionFailed:
            return .red
        case .connectInProgress, .disconnecting:
            return .blue
        case .notVerified, .disconnected:
            return .gray
        case .unavailable:
            return .gray.opacity(0.5)
        default:
            return .gray
        }
    }

    private var connectionStateLabel: String {
        if store.connectionState.rawValue == Self.checkingStatusRawValue {
            return "Checking status\u{2026}"
        }

        switch store.connectionState {
        case .notVerified:
            return "Not connected"
        case .connectInProgress:
            return "Connecting\u{2026}"
        case .connected:
            return "Connected"
        case .connectionFailed:
            return "Failed"
        case .disconnecting:
            return "Disconnecting\u{2026}"
        case .disconnected:
            return "Disconnected"
        case .unavailable:
            return "Unavailable"
        default:
            return "Not connected"
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        if showsAPIKeyEntry {
            EmptyView()
        } else {
            switch store.primaryAction {
            case .connect:
                Button("Sign in") {
                    store.send(.connectButtonTapped)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

            case .retry:
                Button("Retry") {
                    store.send(.retryButtonTapped)
                }
                .controlSize(.small)

            case .disconnect:
                Button("Disconnect") {
                    store.send(.disconnectButtonTapped)
                }
                .controlSize(.small)

            case .cancel:
                Button("Cancel") {
                    store.send(.cancelButtonTapped)
                }
                .controlSize(.small)

            case .disabled:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private var apiKeyEntryRow: some View {
        HStack {
            SecureField("Enter API key", text: $keyText)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)

            Button("Submit") {
                let trimmed = keyText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                store.send(.submitAPIKey(trimmed))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(keyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var showsAPIKeyEntry: Bool {
        guard let descriptor = ProviderDescriptor.descriptor(for: store.provider),
              descriptor.authMethod == .apiKey
        else { return false }

        return (store.connectionState == .notVerified
            || store.connectionState == .disconnected
            || store.connectionState == .connectionFailed)
            && store.flowState == .idle
    }

    @ViewBuilder
    private var progressRow: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(progressLabel)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var showsProgress: Bool {
        store.isVerifying
            || store.connectionState.rawValue == Self.checkingStatusRawValue
            || store.flowState == .connecting
            || store.flowState == .browserLoginInProgress
            || store.flowState == .deviceAuthInProgress
            || store.flowState == .disconnecting
    }

    private var progressLabel: String {
        if store.connectionState.rawValue == Self.checkingStatusRawValue {
            return "Checking status\u{2026}"
        }

        switch store.flowState {
        case .connecting:
            return "Verifying\u{2026}"
        case .browserLoginInProgress, .deviceAuthInProgress:
            return "Waiting for authentication\u{2026}"
        case .disconnecting:
            return "Disconnecting\u{2026}"
        default:
            return "Verifying\u{2026}"
        }
    }

    private var statusReasonDescription: String {
        switch store.statusReason {
        case .none: ""
        case .missingCredential: "Credential is missing."
        case .invalidPayload: "Invalid response from provider."
        case .credentialKindMismatch: "Credential type mismatch."
        case .expired: "Credential has expired."
        case .providerUnsupportedInBuild: "Provider is not supported in this build."
        case .networkUnavailable: "Network is unavailable."
        case .verificationFailed: "Verification failed."
        case .oauthRejected: "OAuth authentication was rejected."
        case .invalidAPIKey: "Invalid API key."
        case .corruptedProviderRecord: "Provider record is corrupted."
        case .unknown: "Unknown error."
        }
    }
}
