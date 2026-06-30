import ComposableArchitecture
import Foundation
import VoyagerPagesSettings

@ObservableState
public struct SettingsHostState: Equatable {
    public var settings: SettingsState = .init()

    public init() {}
}

@CasePathable
public enum SettingsHostAction: CasePathable, Sendable {
    case settings(SettingsAction)
}

@Reducer
public struct SettingsHostFeature {
    public typealias State = SettingsHostState
    public typealias Action = SettingsHostAction

    public init() {}

    public var body: some Reducer<State, Action> {
        Scope(state: \.settings, action: \.settings) {
            SettingsFeature()
        }
    }
}
