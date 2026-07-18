import ComposableArchitecture
import Foundation
import VoyagerPagesFileManager

@ObservableState
struct WindowManagerState: Equatable {
    typealias WindowID = WindowSessionState.ID

    var appPreferences: AppPreferencesFeature.State = .init()
    var windows: IdentifiedArrayOf<WindowSessionFeature.State> = []
    var focusedWindowID: WindowID?
    var lastUsedWindowIDs: [WindowID] = []
    var defaultWindowBootstrapRequestID: UUID?
    var defaultWindowBootstrapWindowIDs: Set<WindowID> = []
    var externalWindowBatchIDs: [WindowID: UUID] = [:]
    var authorizedExternalOpenBatchID: UUID?
    var externalOpenActivationAttempt: ExternalOpenActivationAttempt?

    mutating func moveWindowToMRUFront(_ id: WindowID) {
        lastUsedWindowIDs.removeAll { $0 == id }
        lastUsedWindowIDs.insert(id, at: 0)
    }
}

@Reducer
struct WindowSessionFeature {
    typealias State = WindowSessionState
    typealias Action = WindowSessionAction

    var body: some Reducer<State, Action> {
        Scope(state: \.window, action: \.window) {
            FileManagerWindowFeature()
        }

        Reduce { _, action in
            switch action {
            case .window:
                .none
            }
        }
    }
}
