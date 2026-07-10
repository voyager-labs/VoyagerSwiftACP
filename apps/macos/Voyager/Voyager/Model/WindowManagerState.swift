import ComposableArchitecture
import Foundation

@ObservableState
struct WindowManagerState: Equatable {
    typealias WindowID = WindowSessionState.ID

    var appPreferences: AppPreferencesFeature.State = .init()
    var windows: IdentifiedArrayOf<WindowSessionFeature.State> = []
    var focusedWindowID: WindowID?
    var defaultWindowBootstrapRequestID: UUID?
    var defaultWindowBootstrapWindowIDs: Set<WindowID> = []
}
