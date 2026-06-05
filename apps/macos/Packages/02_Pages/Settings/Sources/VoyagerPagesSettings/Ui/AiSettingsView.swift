import ComposableArchitecture
import SwiftUI
import VoyagerEntitiesAi
import VoyagerFeaturesAiProviderConnection

struct AiSettingsView: View {
    let store: StoreOf<AiSettingsFeature>

    var body: some View {
        Form {
            Section {
                if store.bootstrapPhase == .failed {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Failed to load AI connections.")
                        Button("Retry") {
                            store.send(.retryBootstrapTapped)
                        }
                    }
                } else {
                    ForEach(store.scope(state: \.rows, action: \.row)) { rowStore in
                        AiConnectionRowView(store: rowStore)
                    }
                }
            } header: {
                Text("AI Connections")
            } footer: {
                Text("Connect AI providers to enable intelligent features in Voyager.")
                    .font(.footnote)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Color(NSColor.controlBackgroundColor))
    }
}
