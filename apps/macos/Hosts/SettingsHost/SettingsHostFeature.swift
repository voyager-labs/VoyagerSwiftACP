import ComposableArchitecture
import Foundation
import VoyagerPagesSettings

@ObservableState
public struct SettingsHostState: Equatable {
    public var settings: SettingsState = .init()

    public init() {}

    /// preset-derived Settings 초기 상태 주입용. Host는 child internals를 직접 건드리지 않고
    /// `SettingsState.hostPreset(for:)` 팩토리에서 만들어진 인스턴스만 받는다.
    public init(settings: SettingsState) {
        self.settings = settings
    }
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
