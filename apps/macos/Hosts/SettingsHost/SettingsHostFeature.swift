import ComposableArchitecture
import Foundation
import VoyagerPagesSettings

@ObservableState
public struct SettingsHostState: Equatable {
    public var settings: SettingsState = .init()
    public var notice: String?

    public init() {}

    /// 호스트 런타임이 시나리오 변경 직후 notice banner를 주입하기 위한 initializer.
    /// 프로덕션 SettingsFeature는 이 initializer를 사용하지 않는다 (host-only lifecycle).
    public init(notice: String?) {
        self.notice = notice
    }
}

@CasePathable
public enum SettingsHostAction: CasePathable, Sendable {
    case settings(SettingsAction)
    case dismissNotice
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

        Reduce { state, action in
            switch action {
            case .settings(.general(.checkForUpdates)):
                state.notice = "Updater is not available in the standalone Settings host."
                return .none

            case .settings(.general(.toggleAutomaticUpdate)):
                state.notice =
                    "Automatic update scheduling is disabled in the standalone Settings host. "
                        + "Preference is still persisted locally."
                return .none

            case .dismissNotice:
                state.notice = nil
                return .none

            case .settings:
                return .none
            }
        }
    }
}
