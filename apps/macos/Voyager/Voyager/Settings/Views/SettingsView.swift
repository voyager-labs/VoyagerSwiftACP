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
            set: { store.send(.selectSection($0)) },
        )) {
            GeneralSettingsView(store: store.scope(state: \.generalSettings, action: \.general))
                .tabItem {
                    Label("General", systemImage: "gear")
                }
                .tag(SettingsSection.general)

            AppearanceSettingsView(store: store.scope(state: \.appearanceSettings, action: \.appearance))
                .tabItem {
                    Label("Appearance", systemImage: SettingsSection.appearance.iconName)
                }
                .tag(SettingsSection.appearance)
        }
        .frame(width: 600, height: 400)
        .onAppear {
            store.send(.onAppear)
        }
        .background(
            Button("") {
                store.send(.closeWindow)
            }
            .keyboardShortcut("w", modifiers: .command)
            .hidden(),
        )
    }
}
