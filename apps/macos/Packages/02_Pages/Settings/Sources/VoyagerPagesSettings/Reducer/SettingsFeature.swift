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

            return .none
        }
    }
}
