import AppKit
import ComposableArchitecture
import Foundation

@Reducer
struct SettingsFeature {
    @Dependency(\.entryClient)
    var entryClient: EntryClient
    @Dependency(\.userDefaultsClient)
    var userDefaultsClient: UserDefaultsClient

    @ObservableState
    struct State: Equatable {
        var selectedSection: SettingsSection = .general
        var generalSettings = GeneralSettingsFeature.State()
        var appearanceSettings = AppearanceSettingsFeature.State()
    }

    enum Action: Sendable {
        case onAppear
        case selectSection(SettingsSection)
        case closeWindow
        case general(GeneralSettingsFeature.Action)
        case appearance(AppearanceSettingsFeature.Action)
    }

    var body: some Reducer<State, Action> {
        Scope(state: \.generalSettings, action: \.general) {
            GeneralSettingsFeature()
        }
        Scope(state: \.appearanceSettings, action: \.appearance) {
            AppearanceSettingsFeature()
        }

        Reduce { state, action in
            if case .onAppear = action {
                return .merge(
                    .send(.general(.loadSettings)),
                    .send(.appearance(.loadSettings)),
                )
            }

            if case let .selectSection(section) = action {
                state.selectedSection = section
                return .none
            }

            if case .closeWindow = action {
                return .run { _ in
                    await MainActor.run {
                        NSApp.keyWindow?.close()
                    }
                }
            }

            return .none
        }
    }
}
