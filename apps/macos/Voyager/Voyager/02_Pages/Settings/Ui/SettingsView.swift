import ComposableArchitecture
import SwiftUI

struct SettingsView: View {
    let store: StoreOf<SettingsFeature>

    @MainActor
    init() {
        let state = SettingsState()
        store = Store(initialState: state) {
            SettingsFeature()
        }
    }

    var body: some View {
        WithViewStore(store, observe: { $0 }) { viewStore in
            TabView(selection: viewStore.binding(get: \.selectedSection, send: SettingsAction.selectSection)) {
                ForEach(SettingsSection.allCases) { section in
                    tabContent(for: section)
                        .tabItem {
                            Label(section.title, systemImage: section.iconName)
                        }
                        .tag(section)
                }
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

    @ViewBuilder
    private func tabContent(for section: SettingsSection) -> some View {
        switch section {
        case .general:
            GeneralSettingsView(store: store.scope(state: \ .generalSettings, action: \ .general))
        case .appearance:
            AppearanceSettingsView(store: store.scope(state: \ .appearanceSettings, action: \ .appearance))
        }
    }
}
