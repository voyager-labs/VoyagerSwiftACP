import ComposableArchitecture
import SwiftUI
import VoyagerFeaturesBetaAccess

struct BetaAccessStepView: View {
    let store: StoreOf<BetaAccessFeature>

    private enum ChipTone {
        case success
        case error
        case neutral
    }

    var body: some View {
        WithViewStore(store, observe: { $0 }, content: { viewStore in
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Email")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                        TextField(
                            "email@example.com",
                            text: viewStore.binding(
                                get: \.email,
                                send: { .emailChanged($0) },
                            ),
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: .infinity)
                        .controlSize(.large)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Token")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                        TextField(
                            "Paste your token here",
                            text: viewStore.binding(
                                get: \.token,
                                send: { .tokenChanged($0) },
                            ),
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: .infinity)
                        .controlSize(.large)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Enter the email and token from your invite.")
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    statusChip(viewStore.statusTitle, tone: statusTone(for: viewStore.status))
                    if let message = viewStore.statusMessage {
                        statusChip(message, tone: .neutral)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if viewStore.isVerifying {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Checking...")
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

    private func statusTone(for status: BetaAccessStatus) -> ChipTone {
        switch status {
        case .active:
            .success
        case .checkFailed:
            .error
        case .notActive:
            .neutral
        }
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
}
