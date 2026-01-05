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
                Text("Beta access flow will be implemented in Story 1.3.")
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
