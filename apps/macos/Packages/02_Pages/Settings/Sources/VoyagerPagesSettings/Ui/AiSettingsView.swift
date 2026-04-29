import ComposableArchitecture
import SwiftUI
import VoyagerEntitiesAi

struct AiSettingsView: View {
    let store: StoreOf<AiSettingsFeature>

    var body: some View {
        Form {
            Section {
                ForEach(store.scope(state: \.rows, action: \.row)) { rowStore in
                    AiConnectionRowView(store: rowStore)
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
