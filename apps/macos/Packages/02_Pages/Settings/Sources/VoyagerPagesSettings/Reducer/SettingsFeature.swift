import AppKit
import ComposableArchitecture
import Foundation
import VoyagerFeaturesAccountAccess

@Reducer
public struct SettingsFeature {
    public typealias State = SettingsState
    public typealias Action = SettingsAction

    @Dependency(\.accessStatusSnapshotClient)
    private var accessStatusSnapshotClient

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
            if case .onAppear = action {
                return .merge(
                    .send(.general(.loadSettings)),
                    .send(.appearance(.loadSettings)),
                    .send(.ai(.onAppear)),
                    .send(.account(.access(.onAppear))),
                    .run { [accessStatusSnapshotClient] send in
                        let snapshot = await accessStatusSnapshotClient.load()
                        await send(.accessStatusLoaded(snapshot?.status ?? .none))
                    },
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

            if case let .accessStatusLoaded(status) = action {
                state.accessStatus = status
                return .none
            }

            if case let .ai(.delegate(.connectionsFileUpdated(file))) = action {
                return .send(.delegate(.aiConnectionsFileUpdated(file)))
            }

            return .none
        }
    }
}
