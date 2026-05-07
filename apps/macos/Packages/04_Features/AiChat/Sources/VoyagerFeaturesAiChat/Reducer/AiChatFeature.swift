import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi

@Reducer
public struct AiChatFeature {
    public typealias State = AiChatState
    public typealias Action = AiChatAction

    enum CancelID {
        case request
    }

    @Dependency(\.aiChatExecutionClient)
    var aiChatExecutionClient
    @Dependency(\.aiChatSessionPersistenceClient)
    var aiChatSessionPersistenceClient
    @Dependency(\.uuid)
    var uuid

    public init() {}

    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                normalizeSelectionIfNeeded(&state)
                return .none

            case let .setup(setup):
                apply(setup: setup, to: &state)
                normalizeSelectionIfNeeded(&state)
                guard let restoreSessionID = setup.restoreSessionID else { return .none }
                state.sessionStatus = .restoring
                return restoreSession(sessionID: restoreSessionID, state: state)

            case let .selectedModelChanged(handle):
                let resolvedHandle = resolvedSelectionHandle(handle, in: state.catalogRows)
                guard state.selectedModelHandle != resolvedHandle else { return .none }
                state.selectedModelHandle = resolvedHandle
                clearRetryBlockingFailureIfNeeded(&state)
                return .none

            case let .draftTextChanged(text):
                state.draftText = text
                clearRetryBlockingFailureIfNeeded(&state)
                return .none

            case .submitTapped:
                guard state.canSubmit else { return .none }
                return startRequest(kind: .submit, state: &state)

            case .regenerateTapped:
                return startRequest(kind: .regenerate, state: &state)

            case .cancelTapped:
                guard let lock = state.executionPhase.lock, state.executionPhase.isProcessing else { return .none }
                state.lockedModelHandle = nil
                state.streamDraftText = ""
                state.executionPhase = .cancelled(lock)
                return .cancel(id: CancelID.request)

            case .resetTapped:
                state.draftText = ""
                state.transcriptHistory = []
                state.streamDraftText = ""
                state.lastExecutionFailure = nil
                state.lockedModelHandle = nil
                state.executionPhase = .idle
                return .cancel(id: CancelID.request)

            case let .restoreOutcome(result, restoreFailure):
                applyRestoreOutcome(result, restoreFailure: restoreFailure, state: &state)
                return .none

            case let .executionEvent(event):
                return handleExecutionEvent(event, state: &state)

            case let .persistenceFailed(lock, failure):
                switch state.executionPhase {
                case let .completed(currentLock):
                    guard currentLock.requestID == lock.requestID else { return .none }
                case let .persistenceRecovery(currentLock, _):
                    guard currentLock.requestID == lock.requestID else { return .none }
                default:
                    return .none
                }

                state.executionPhase = .persistenceRecovery(lock, failure)
                state.lastExecutionFailure = failure
                return .none
            }
        }
    }
}
