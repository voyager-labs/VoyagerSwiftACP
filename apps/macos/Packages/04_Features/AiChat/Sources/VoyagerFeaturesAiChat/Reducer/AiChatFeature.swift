import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi

@Reducer
public struct AiChatFeature {
    public typealias State = AiChatState
    public typealias Action = AiChatAction

    enum CancelID: Hashable, Sendable {
        case request
        case restore
    }

    @Dependency(\.aiChatExecutionClient)
    var aiChatExecutionClient
    @Dependency(\.aiChatSessionPersistenceClient)
    var aiChatSessionPersistenceClient
    @Dependency(\.aiChatSettingsClient)
    var aiChatSettingsClient
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
                guard let restoreSessionID = setup.restoreSessionID else { return .cancel(id: CancelID.restore) }
                state.sessionStatus = .restoring
                return restoreSession(sessionID: restoreSessionID, state: state)

            case let .availableModelsUpdated(catalogRows, selectedModelHandle):
                let currentSelectedModelHandle = state.selectedModelHandle
                state.catalogRows = catalogRows
                if let currentSelectedModelHandle,
                   catalogRows.contains(where: { $0.handle == currentSelectedModelHandle }) {
                    state.selectedModelHandle = currentSelectedModelHandle
                } else {
                    state.selectedModelHandle = resolvedSelectionHandle(selectedModelHandle, in: catalogRows)
                }
                normalizeSelectionIfNeeded(&state)
                clearRetryBlockingFailureIfNeeded(&state)
                return .none

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

            case .openSettingsTapped:
                guard case .unconnected = state.connectionState else { return .none }
                let openSettingsWindow = aiChatSettingsClient.openSettingsWindow
                return .run { _ in
                    await MainActor.run {
                        _ = openSettingsWindow()
                    }
                }

            case .submitTapped:
                guard state.canSubmit else { return .none }
                return startRequest(kind: .submit, state: &state)

            case .regenerateTapped:
                return startRequest(kind: .regenerate, state: &state)

            case .cancelTapped:
                guard let lock = state.executionPhase.lock, state.executionPhase.isProcessing else { return .none }
                state.lockedModelHandle = nil
                state.executionPhase = .cancelled(lock)
                return .cancel(id: CancelID.request)

            case .resetTapped:
                state.draftText = ""
                state.transcriptHistory = []
                state.lastExecutionFailure = nil
                state.lockedModelHandle = nil
                state.executionPhase = .idle
                return .cancel(id: CancelID.request)

            case let .restoreOutcome(requestedSessionID, result, restoreFailure):
                guard state.restoreSessionID == requestedSessionID else { return .none }
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
