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

    private func clearRetryBlockingFailureIfNeeded(_ state: inout State) {
        state.lastExecutionFailure = nil

        switch state.executionPhase {
        case .failed, .persistenceRecovery:
            state.executionPhase = .idle
        default:
            break
        }
    }

    private func restoreSession(sessionID: AiChatSessionID, state: State) -> Effect<Action> {
        let catalogRows = state.catalogRows
        let selectedHandle = resolvedSelectedModelRow(in: state)?.handle ?? state.selectedModelHandle

        return .run { [aiChatSessionPersistenceClient, uuid] send in
            do {
                if let snapshot = try await aiChatSessionPersistenceClient.loadSession(sessionID) {
                    if snapshot.status == .rebindRequired {
                        let fallbackSnapshot = Self.makeNewSessionSnapshot(
                            sessionID: AiChatSessionID(rawValue: uuid()),
                            catalogRows: catalogRows,
                            selectedHandle: selectedHandle
                        )
                        await send(.restoreOutcome(.newSession(snapshot: fallbackSnapshot), restoreFailure: .contextMismatch))
                    } else {
                        let result = AiChatSessionRestoreResult.restored(snapshot: Self.normalizeRestoredSnapshot(snapshot, catalogRows: catalogRows))
                        await send(.restoreOutcome(result, restoreFailure: nil))
                    }
                    return
                }

                let newSessionID = AiChatSessionID(rawValue: uuid())
                let snapshot = Self.makeNewSessionSnapshot(
                    sessionID: newSessionID,
                    catalogRows: catalogRows,
                    selectedHandle: selectedHandle
                )
                await send(.restoreOutcome(.newSession(snapshot: snapshot), restoreFailure: .missingRecord))
            } catch {
                let newSessionID = AiChatSessionID(rawValue: uuid())
                let snapshot = Self.makeNewSessionSnapshot(
                    sessionID: newSessionID,
                    catalogRows: catalogRows,
                    selectedHandle: selectedHandle
                )
                await send(.restoreOutcome(.newSession(snapshot: snapshot), restoreFailure: .corruptedRecord))
            }
        }
    }

    private func startRequest(kind: AiChatRequestKind, state: inout State) -> Effect<Action> {
        guard !state.isProcessing else { return .none }
        guard let sessionID = state.sessionID else { return .none }
        guard let selectedRow = resolvedSelectedModelRow(in: state) else { return .none }

        let prompt: String
        let messages: [AiChatMessage]
        let assistantReplacementIndex: Int?

        switch kind {
        case .submit:
            let trimmed = state.draftText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return .none }
            prompt = trimmed
            messages = state.transcriptHistory + [AiChatMessage(role: .user, content: trimmed)]
            assistantReplacementIndex = nil

        case .regenerate:
            guard let lastUserPrompt = lastUserPrompt(in: state.transcriptHistory) else { return .none }
            prompt = lastUserPrompt
            if state.transcriptHistory.last?.role == .assistant {
                messages = Array(state.transcriptHistory.dropLast())
                assistantReplacementIndex = state.transcriptHistory.count - 1
            } else {
                messages = state.transcriptHistory
                assistantReplacementIndex = nil
            }
        }

        let requestID = AiChatRequestID(rawValue: uuid())
        let runID = AiChatRunID(rawValue: uuid())
        let selectedHandle = selectedRow.handle
        let context = AiChatRequestContextSnapshot(
            sessionID: sessionID,
            requestID: requestID,
            runID: runID,
            provider: selectedHandle.provider,
            model: selectedHandle,
            selectedModelRow: selectedRow,
            sessionStatus: .active,
            currentContext: state.currentContext,
            promptSummary: prompt,
            submittedAtMs: nil
        )
        let request = AiChatRequest(context: context, messages: messages)
        let lock = AiChatRequestLock(
            kind: kind,
            requestID: requestID,
            runID: runID,
            context: context,
            request: request,
            selectedModelHandle: selectedHandle,
            selectedModelRow: selectedRow,
            assistantReplacementIndex: assistantReplacementIndex
        )

        state.selectedModelHandle = selectedHandle
        state.lockedModelHandle = selectedHandle
        state.lastExecutionFailure = nil
        state.streamDraftText = ""
        state.executionPhase = .processing(lock)
        state.sessionStatus = .active

        if kind == .submit {
            state.transcriptHistory.append(AiChatMessage(role: .user, content: prompt))
            state.draftText = ""
        }

        return .run { [aiChatExecutionClient] send in
            for await event in aiChatExecutionClient.execute(request) {
                await send(.executionEvent(event))
            }
        }
        .cancellable(id: CancelID.request, cancelInFlight: true)
    }

    private func handleExecutionEvent(_ event: AiChatEvent, state: inout State) -> Effect<Action> {
        switch event {
        case .started:
            return .none

        case let .streamChunk(context, delta):
            guard case let .processing(lock) = state.executionPhase,
                  matches(lock: lock, context: context)
            else {
                return .none
            }

            state.streamDraftText += delta
            return .none

        case let .final(response):
            guard case let .processing(lock) = state.executionPhase,
                  matches(lock: lock, context: response.context)
            else {
                return .none
            }

            applyFinal(response: response, lock: lock, state: &state)
            let snapshot = makeSessionSnapshot(state: state, lock: lock)

            return .merge(
                .run { [aiChatSessionPersistenceClient] send in
                    do {
                        try await aiChatSessionPersistenceClient.saveSession(snapshot)
                    } catch {
                        await send(.persistenceFailed(lock, .unknown))
                    }
                },
                .cancel(id: CancelID.request)
            )

        case let .failed(context, reason):
            guard case let .processing(lock) = state.executionPhase,
                  matches(lock: lock, context: context)
            else {
                return .none
            }

            state.streamDraftText = ""
            state.lockedModelHandle = nil
            state.lastExecutionFailure = reason
            state.executionPhase = .failed(lock, reason)
            return .cancel(id: CancelID.request)
        }
    }

    private func applyFinal(response: AiChatResponse, lock: AiChatRequestLock, state: inout State) {
        if let index = lock.assistantReplacementIndex,
           state.transcriptHistory.indices.contains(index),
           state.transcriptHistory[index].role == .assistant
        {
            state.transcriptHistory[index] = response.assistantMessage
        } else {
            state.transcriptHistory.append(response.assistantMessage)
        }

        state.streamDraftText = ""
        state.lockedModelHandle = nil
        state.lastExecutionFailure = nil
        state.executionPhase = .completed(lock)
    }

    private func makeSessionSnapshot(state: State, lock: AiChatRequestLock) -> AiChatSessionSnapshot {
        guard let sessionID = lock.context.sessionID ?? state.sessionID else {
            preconditionFailure("Missing session ID for finalized request")
        }

        return AiChatSessionSnapshot(
            sessionID: sessionID,
            status: state.sessionStatus,
            provider: lock.selectedModelHandle.provider,
            model: lock.selectedModelHandle,
            selectedModelRow: lock.selectedModelRow,
            transcriptHistory: state.transcriptHistory,
            lastRequestID: lock.requestID,
            lastRunID: lock.runID,
            updatedAtMs: 0
        )
    }

    private func matches(lock: AiChatRequestLock, context: AiChatRequestContextSnapshot) -> Bool {
        lock.requestID == context.requestID && lock.runID == context.runID
    }

    private func lastUserPrompt(in transcriptHistory: [AiChatMessage]) -> String? {
        transcriptHistory.reversed().first(where: { $0.role == .user })?.content
    }

    private func apply(setup: AiChatSetupState, to state: inout State) {
        state.restoreSessionID = setup.restoreSessionID
        state.restoreOutcome = nil
        state.restoreFailure = nil
        state.sessionID = setup.sessionID
        state.sessionStatus = setup.sessionStatus
        state.currentContext = setup.currentContext
        state.transcriptHistory = setup.transcriptHistory
        state.draftText = setup.draftText
        state.catalogRows = setup.catalogRows
        state.selectedModelHandle = setup.selectedModelHandle
        state.lockedModelHandle = setup.lockedModelHandle
        state.lastExecutionFailure = setup.lastExecutionFailure
        state.streamDraftText = ""
        state.executionPhase = .idle
    }

    private func applyRestoreOutcome(_ result: AiChatSessionRestoreResult, restoreFailure: AiChatSessionRestoreFailure?, state: inout State) {
        switch result {
        case let .restored(snapshot):
            applyRestoredSnapshot(snapshot, state: &state)
            state.restoreOutcome = result
            state.restoreFailure = restoreFailure

        case let .newSession(snapshot):
            applyNewSessionSnapshot(snapshot, state: &state)
            state.restoreOutcome = result
            state.restoreFailure = restoreFailure

        case let .rebindRequired(snapshot):
            applyNewSessionSnapshot(snapshot, state: &state)
            state.restoreOutcome = .newSession(snapshot: snapshot)
            state.restoreFailure = restoreFailure ?? .contextMismatch

        case let .failed(reason):
            state.restoreFailure = reason
            state.restoreOutcome = nil
        }

        normalizeSelectionIfNeeded(&state)
    }

    private func applyRestoredSnapshot(_ snapshot: AiChatSessionSnapshot, state: inout State) {
        state.sessionID = snapshot.sessionID
        state.sessionStatus = .active
        state.transcriptHistory = snapshot.transcriptHistory
        state.streamDraftText = ""
        state.lockedModelHandle = nil
        state.lastExecutionFailure = nil
        state.executionPhase = .idle
        state.selectedModelHandle = snapshot.model
    }

    private func applyNewSessionSnapshot(_ snapshot: AiChatSessionSnapshot, state: inout State) {
        state.sessionID = snapshot.sessionID
        state.sessionStatus = .idle
        state.transcriptHistory = []
        state.streamDraftText = ""
        state.lockedModelHandle = nil
        state.lastExecutionFailure = nil
        state.executionPhase = .idle
        state.selectedModelHandle = snapshot.model
    }

    private static func normalizeRestoredSnapshot(_ snapshot: AiChatSessionSnapshot, catalogRows: [AiModelCatalogRow]) -> AiChatSessionSnapshot {
        let selectedRow: AiModelCatalogRow?
        if let row = snapshot.selectedModelRow,
           catalogRows.contains(where: { $0.handle == row.handle })
        {
            selectedRow = row
        } else if let matchingRow = catalogRows.first(where: { $0.handle == snapshot.model }) {
            selectedRow = matchingRow
        } else {
            selectedRow = catalogRows.first
        }

        let model = selectedRow?.handle ?? snapshot.model
        return AiChatSessionSnapshot(
            sessionID: snapshot.sessionID,
            status: .active,
            provider: model.provider,
            model: model,
            selectedModelRow: selectedRow,
            transcriptHistory: snapshot.transcriptHistory,
            lastRequestID: snapshot.lastRequestID,
            lastRunID: snapshot.lastRunID,
            updatedAtMs: snapshot.updatedAtMs
        )
    }

    private static func makeNewSessionSnapshot(
        sessionID: AiChatSessionID,
        catalogRows: [AiModelCatalogRow],
        selectedHandle: AiModelHandle?
    ) -> AiChatSessionSnapshot {
        let selectedRow = catalogRows.first(where: { $0.handle == selectedHandle }) ?? catalogRows.first
        let model = selectedRow?.handle ?? selectedHandle ?? AiModelHandle(provider: .openai, rawValue: "unknown")

        return AiChatSessionSnapshot(
            sessionID: sessionID,
            status: .idle,
            provider: model.provider,
            model: model,
            selectedModelRow: selectedRow,
            transcriptHistory: [],
            updatedAtMs: 0
        )
    }

    private func normalizeSelectionIfNeeded(_ state: inout State) {
        guard !state.catalogRows.isEmpty else {
            state.selectedModelHandle = nil
            return
        }

        if let selectedHandle = state.selectedModelHandle,
           state.catalogRows.contains(where: { $0.handle == selectedHandle })
        {
            return
        }

        state.selectedModelHandle = state.catalogRows.first?.handle
    }

    private func resolvedSelectionHandle(_ handle: AiModelHandle?, in rows: [AiModelCatalogRow]) -> AiModelHandle? {
        guard !rows.isEmpty else { return nil }
        if let handle, rows.contains(where: { $0.handle == handle }) {
            return handle
        }
        return rows.first?.handle
    }

    private func resolvedSelectedModelRow(in state: State) -> AiModelCatalogRow? {
        if let handle = state.selectedModelHandle,
           let row = state.catalogRows.first(where: { $0.handle == handle })
        {
            return row
        }

        return state.catalogRows.first
    }
}
