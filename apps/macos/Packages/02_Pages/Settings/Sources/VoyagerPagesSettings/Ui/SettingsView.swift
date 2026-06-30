import ComposableArchitecture
import SwiftUI

public struct SettingsView: View {
    public let store: StoreOf<SettingsFeature>

    public init(store: StoreOf<SettingsFeature>) {
        self.store = store
    }

    public var body: some View {
        WithViewStore(store, observe: { $0 }, content: { viewStore in
            Group {
                if viewStore.isContentLocked {
                    VStack(spacing: 12) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(.secondary)
                        Text("Settings are locked")
                            .font(.headline)
                        Text("Active license required.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    TabView(selection: viewStore.binding(get: \.selectedSection, send: SettingsAction.selectSection)) {
                        ForEach(SettingsSection.allCases) { section in
                            tabContent(for: section)
                                .tabItem {
                                    Label(section.title, systemImage: section.iconName)
                                }
                                .tag(section)
                        }
                    }
                }
            }
            .frame(width: 600, height: 400)
            .onAppear {
                store.send(.onAppear)
            }
            .onDisappear {
                store.send(.resetSectionForFreshOpen)
            }
            .background(
                Button("") {
                    store.send(.closeWindow)
                }
                .keyboardShortcut("w", modifiers: .command)
                .hidden(),
            )
        })
    }

    @ViewBuilder
    private func tabContent(for section: SettingsSection) -> some View {
        switch section {
        case .general:
            GeneralSettingsView(store: store.scope(state: \.generalSettings, action: \.general))
        case .appearance:
            AppearanceSettingsView(store: store.scope(state: \.appearanceSettings, action: \.appearance))
        case .ai:
            AiSettingsView(store: store.scope(state: \.aiSettings, action: \.ai))
        case .account:
            AccountSettingsView(store: store.scope(state: \.accountSettings, action: \.account))
        }
    }
}
