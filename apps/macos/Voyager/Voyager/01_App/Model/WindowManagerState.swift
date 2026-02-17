import ComposableArchitecture

@ObservableState
struct WindowManagerState: Equatable {
    typealias WindowID = WindowSessionState.ID

    var appPreferences: AppPreferencesState = .init()
    var windows: IdentifiedArrayOf<WindowSessionState> = []
    var focusedWindowID: WindowID?
}
