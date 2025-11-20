import ComposableArchitecture
import SwiftUI

struct SettingsView: View {
    let store: StoreOf<SettingsFeature>

    @MainActor
    init() {
        let state = SettingsFeature.State()
        store = Store(initialState: state) {
            SettingsFeature()
        }
    }

    var body: some View {
        TabView(selection: Binding(
            get: { store.selectedSection },
            set: { store.send(.selectSection($0)) }
        )) {
            GeneralSettingsView(store: store)
                .tabItem {
                    Label("General", systemImage: "gear")
                }
                .tag(SettingsSection.general)
        }
        .frame(width: 600, height: 400)
        .onAppear {
            store.send(.onAppear)
        }
    }
}
