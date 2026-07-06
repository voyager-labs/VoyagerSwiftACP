import AppKit
import ComposableArchitecture
import Foundation
import VoyagerFeaturesAccountAccess

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
            // ponytail: launch 해당만 수행. AppRoot가
            //   .bootstrapLocalPreferences (General/Appearance load)
            //   .appLifecycleAccessSnapshotReady (accessStatus/Account snapshot)
            // 로 1회씩 전달한다. onAppear는 UI lifecycle 전용.
            if case .bootstrapLocalPreferences = action {
                return .merge(
                    .send(.general(.loadSettings)),
                    .send(.appearance(.loadSettings)),
                )
            }

            if case let .appLifecycleAccessSnapshotReady(snapshot) = action {
                state.accessStatus = snapshot.status
                return .send(.account(.access(.hydrateLaunchSnapshot(snapshot))))
            }

            if case .onAppear = action {
                return .none
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

            if case let .account(.access(.delegate(.unlocked(snapshot)))) = action {
                state.accessStatus = snapshot.status
                return .none
            }

            if case .account(.access(.delegate(.signedOut))) = action {
                state.accessStatus = .none
                return .none
            }

            if case let .ai(.delegate(.connectionsFileUpdated(file))) = action {
                return .send(.delegate(.aiConnectionsFileUpdated(file)))
            }

            return .none
        }
    }
}
