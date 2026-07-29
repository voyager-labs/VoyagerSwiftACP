import ComposableArchitecture
import Foundation
import VoyagerPagesFileManager

struct WindowManagerTrackedSingletonWindow: Equatable {
    var requestID: UUID
    var windowID: UUID
    var terminalOutcomeEmitted = false
}

struct WindowManagerRetainedExternalOpenPlacementOwnership: Equatable {
    var batchID: UUID
    var newWindowIDs: [UUID]
}

struct WindowManagerInFlightPinnedRecordMutation: Equatable {
    let sourceWindowID: WindowManagerState.WindowID
    let request: FileManagerPinnedRecordPersistenceRequest
    let generation: ContentTabPinnedRecordMutationGeneration
}

@ObservableState
struct WindowManagerState: Equatable {
    typealias WindowID = WindowSessionState.ID

    var appPreferences: AppPreferencesFeature.State = .init()
    var windows: IdentifiedArrayOf<WindowSessionFeature.State> = []
    var focusedWindowID: WindowID?
    var pendingWindowOpenIDs: Set<WindowID> = []
    var closingWindowIDs: Set<WindowID> = []
    var invalidatingWindowIDs: Set<WindowID> = []
    var lastUsedWindowIDs: [WindowID] = []
    var defaultWindowBootstrapRequestID: UUID?
    var defaultWindowBootstrapWindowIDs: Set<WindowID> = []
    var externalWindowBatchIDs: [WindowID: UUID] = [:]
    var retainedExternalOpenPlacementOwnership: WindowManagerRetainedExternalOpenPlacementOwnership?
    var authorizedExternalOpenBatchID: UUID?
    var authorizedTrackedSingletonRequestID: UUID?
    var trackedSingletonWindow: WindowManagerTrackedSingletonWindow?
    var externalOpenActivationAttempt: ExternalOpenActivationAttempt?
    var inFlightPinnedRecordMutations: [UUID: WindowManagerInFlightPinnedRecordMutation] = [:]

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
