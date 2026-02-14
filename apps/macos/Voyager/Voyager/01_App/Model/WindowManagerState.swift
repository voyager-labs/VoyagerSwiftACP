import ComposableArchitecture

@ObservableState
struct WindowManagerState: Equatable {
    typealias WindowID = WindowSessionState.ID

    var windows: IdentifiedArrayOf<WindowSessionState> = []
    var focusedWindowID: WindowID?
}
