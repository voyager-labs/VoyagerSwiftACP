import ComposableArchitecture
import SwiftUI
import VoyagerFeaturesAccess

struct UnlockAccessStepView: View {
    let store: StoreOf<UnlockAccessFeature>

    var body: some View {
        WithViewStore(store, observe: { $0 }, content: { viewStore in
            VStack(alignment: .leading, spacing: 12) {
                Picker("Method", selection: viewStore.binding(
                    get: \.claimMode,
                    send: { .claimModeChanged($0) },
                )) {
                    Text("License Key").tag(AccessClaimMode.licenseKey)
                    Text("Beta Code").tag(AccessClaimMode.betaCode)
                }
                .pickerStyle(.segmented)

                switch viewStore.claimMode {
                case .licenseKey:
                    VStack(alignment: .leading, spacing: 4) {
                        Text("License Key")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                        TextField(
                            "VOYAGER-CORE-VALID",
                            text: viewStore.binding(
                                get: \.licenseKey,
                                send: { .licenseKeyChanged($0) },
                            ),
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: .infinity)
                        .controlSize(.large)
                    }
                case .betaCode:
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Beta Code")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                        TextField(
                            "VOYAGER-BETA-TRIAL",
                            text: viewStore.binding(
                                get: \.betaCode,
                                send: { .betaCodeChanged($0) },
                            ),
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: .infinity)
                        .controlSize(.large)
                    }
                }

                Text("Enter your license key or beta code to activate Voyager.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    if let status = viewStore.status {
                        statusChip(
                            status.isActive ? "Active" : "Inactive",
                            tone: status.isActive ? .success : .error,
                        )
                    }
                    if let message = viewStore.errorMessage {
                        statusChip(message, tone: .neutral)
                    }
                    if let expiresAt = viewStore.trialExpiresAt {
                        statusChip("Expires \(formatDate(expiresAt))", tone: .neutral)
                    }
                }

                if viewStore.isSubmitting {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Activating...")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onAppear {
                viewStore.send(.onAppear)
            }
        })
    }

    private func statusChip(_ text: String, tone: ChipTone) -> some View {
        let colors = chipColors(for: tone)
        return Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(colors.foreground)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(colors.background),
            )
    }

    private enum ChipTone {
        case success
        case error
        case neutral
    }

    private func chipColors(for tone: ChipTone) -> (foreground: Color, background: Color) {
        switch tone {
        case .success:
            (foreground: .green, background: .green.opacity(0.18))
        case .error:
            (foreground: .red, background: .red.opacity(0.18))
        case .neutral:
            (foreground: .secondary, background: .primary.opacity(0.08))
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}
