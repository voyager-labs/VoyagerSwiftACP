import ComposableArchitecture
import SwiftUI

struct WelcomeStepView: View {
    let store: StoreOf<WelcomeFeature>

    var body: some View {
        WithViewStore(store, observe: { $0 }) { _ in
            VStack(alignment: .leading, spacing: 12) {
                Text("Welcome")
                    .font(.system(size: 20, weight: .semibold))
                Text("Let's get Voyager ready for your first run.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct BetaAccessStepView: View {
    let store: StoreOf<BetaAccessFeature>

    var body: some View {
        WithViewStore(store, observe: { $0 }) { viewStore in
            VStack(alignment: .leading, spacing: 12) {
                Text("Beta Access")
                    .font(.system(size: 20, weight: .semibold))

                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Email")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        TextField(
                            "email@example.com",
                            text: viewStore.binding(
                                get: \.email,
                                send: { .emailChanged($0) },
                            ),
                        )
                        .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Token")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        SecureField(
                            "Paste your token here",
                            text: viewStore.binding(
                                get: \.token,
                                send: { .tokenChanged($0) },
                            ),
                        )
                        .textFieldStyle(.roundedBorder)
                    }

                    Text("Enter the email and token from your invitation email.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(viewStore.statusTitle)
                        .font(.system(size: 13, weight: .semibold))
                    if let message = viewStore.statusMessage {
                        Text(message)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .background(.ultraThinMaterial)
                .cornerRadius(8)

                HStack(spacing: 8) {
                    Button(viewStore.showsRetry ? "Retry" : "Check") {
                        viewStore.send(viewStore.showsRetry ? .retryTapped : .checkTapped)
                    }
                    .disabled(!viewStore.canSubmit)

                    if viewStore.isVerifying {
                        ProgressView()
                            .controlSize(.small)
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

struct PermissionsStepView: View {
    let store: StoreOf<PermissionsFeature>

    var body: some View {
        WithViewStore(store, observe: { $0 }) { viewStore in
            VStack(alignment: .leading, spacing: 12) {
                Text("Permissions")
                    .font(.system(size: 20, weight: .semibold))
                Text("Permission requests will be implemented in Story 1.4.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Toggle(
                    "Mark step as complete (placeholder)",
                    isOn: viewStore.binding(
                        get: { $0.isComplete },
                        send: { .setCompleted($0) },
                    ),
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct IndexingPresetStepView: View {
    let store: StoreOf<IndexingPresetFeature>

    var body: some View {
        WithViewStore(store, observe: { $0 }) { viewStore in
            VStack(alignment: .leading, spacing: 12) {
                Text("Indexing Preset")
                    .font(.system(size: 20, weight: .semibold))
                Text("Indexing preset UI will be implemented in Story 1.5.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Toggle(
                    "Mark step as complete (placeholder)",
                    isOn: viewStore.binding(
                        get: { $0.isComplete },
                        send: { .setCompleted($0) },
                    ),
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct CompleteStepView: View {
    let store: StoreOf<CompleteFeature>

    var body: some View {
        WithViewStore(store, observe: { $0 }) { viewStore in
            VStack(alignment: .leading, spacing: 12) {
                Text("Complete")
                    .font(.system(size: 20, weight: .semibold))
                Text("Final confirmation and post-onboarding actions land in Story 1.5.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Toggle(
                    "Mark step as complete (placeholder)",
                    isOn: viewStore.binding(
                        get: { $0.isComplete },
                        send: { .setCompleted($0) },
                    ),
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
