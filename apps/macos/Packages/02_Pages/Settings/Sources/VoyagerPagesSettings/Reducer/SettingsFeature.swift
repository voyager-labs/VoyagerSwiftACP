import AppKit
import ComposableArchitecture
import Foundation

@Reducer
public struct SettingsFeature {
    public typealias State = SettingsState
    public typealias Action = SettingsAction

    public init() {}

    public var body: some Reducer<State, Action> {
        Scope(state: \.generalSettings, action: \.general) {
            GeneralSettingsFeature()
        }
        Scope(state: \.appearanceSettings, action: \.appearance) {
            AppearanceSettingsFeature()
        }
        Scope(state: \.aiSettings, action: \.ai) {
            AiSettingsFeature()
        }
        Scope(state: \.accountSettings, action: \.account) {
            AccountSettingsFeature()
        }

        Reduce { state, action in
            if case .bootstrapLocalPreferences = action {
                return .merge(
                    .send(.general(.loadSettings)),
                    .send(.appearance(.loadSettings)),
                )
            }

            if case let .accountAccessPresentationUpdated(presentation) = action {
                state.accountSettings.presentation = presentation
                return .none
            }

            if case .onAppear = action {
                state.selectedSection = state.selectedSection == .account ? .general : state.selectedSection
                return .none
            }

            if case let .selectSection(section) = action {
                state.selectedSection = section == .account ? .general : section
                return .none
            }

            if case .closeWindow = action {
                state.selectedSection = .general
                return .run { _ in
                    await MainActor.run {
                        NSApp.keyWindow?.close()
                    }
                }
            }

            if case .resetSectionForFreshOpen = action {
                state.selectedSection = .general
                return .none
            }

            if case let .account(.delegate(delegate)) = action {
                return .send(.delegate(.account(delegate)))
            }

            if case let .ai(.delegate(.connectionsFileUpdated(file))) = action {
                return .send(.delegate(.aiConnectionsFileUpdated(file)))
            }

            return .none
        }
    }
}
