import ComposableArchitecture
import SwiftUI

struct BetaAccessStepView: View {
    let store: StoreOf<BetaAccessFeature>

    var body: some View {
        WithViewStore(store, observe: { $0 }) { viewStore in
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
                        SecureField(
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
                        Text("Click Check to verify with the server. Until verification succeeds, Next stays disabled.")
                        Text("Verification can fail due to input errors, expired tokens, or network/server issues.")
                        Text("If it fails, correct the input and Retry/Check.")
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 6) {
                    Text(viewStore.statusTitle)
                        .font(.system(size: 14, weight: .semibold))
                    if let message = viewStore.statusMessage {
                        Text(message)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .background(.ultraThinMaterial)
                .cornerRadius(8)
                .frame(maxWidth: .infinity, alignment: .leading)

                if viewStore.isVerifying {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Checking…")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onAppear {
                viewStore.send(.onAppear)
            }
        }
    }
}
