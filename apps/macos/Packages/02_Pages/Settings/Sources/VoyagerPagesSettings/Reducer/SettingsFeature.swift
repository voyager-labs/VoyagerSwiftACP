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

        Reduce { state, action in
            if case .onAppear = action {
                return .merge(
                    .send(.general(.loadSettings)),
                    .send(.appearance(.loadSettings)),
                    .send(.ai(.onAppear))
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
