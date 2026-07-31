import ComposableArchitecture
import Foundation
import VoyagerPagesFileManager

struct WindowManagerTopNavigationPersistenceRequest: Equatable {
    let sourceWindowID: WindowManagerState.WindowID
    let token: FileManagerTopNavigationOperationToken
    let operation: Operation

    enum Operation: Equatable {
        case move(
            source: FileManagerTopNavigationItemID,
            destination: FileManagerTopNavigationMoveDestination,
            discoveredLocationIDs: [String],
        )
        case pinnedRecord(
            source: FileManagerPinnedRecordPersistenceSource,
            request: ContentTabPinnedRecordPersistenceRequest,
            discoveredLocationIDs: [String],
        )
    }
}

struct WindowManagerTopNavigationPersistenceResult: Equatable {
    let request: WindowManagerTopNavigationPersistenceRequest
    let terminal: FileManagerTopNavigationIntentTerminal
    let authoritativePinnedContentTabs: ContentTabState?
}

struct WindowManagerTrackedSingletonWindow: Equatable {
    var requestID: UUID
    var windowID: UUID
    var terminalOutcomeEmitted = false
}

struct WindowManagerRetainedExternalOpenPlacementOwnership: Equatable {
    var batchID: UUID
    var newWindowIDs: [UUID]
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
    var topNavigationPersistenceQueue: [WindowManagerTopNavigationPersistenceRequest] = []
    var isTopNavigationPersistenceInFlight = false

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
                .dependency(\.fileManagerPinnedRecordOwner, .windowManager)
        }

        Reduce { _, action in
            switch action {
            case .window:
                .none
            }
        }
    }
}
