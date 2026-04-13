import ComposableArchitecture
import VoyagerPagesFileManager

@ObservableState
struct WindowManagerState: Equatable {
    typealias WindowID = WindowSessionState.ID

    var appPreferences: AppPreferencesFeature.State = .init()
    var windows: IdentifiedArrayOf<WindowSessionFeature.State> = []
    var focusedWindowID: WindowID?
}
