import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi

extension AiChatFeature {
    func restoreSession(sessionID: AiChatSessionID, state: State) -> Effect<Action> {
        let context = AiChatRestoreContext(
            sessionID: sessionID,
            catalogRows: state.catalogRows,
            selectedHandle: state.selectedModelHandle,
            selectedThinking: state.selectedThinking,
        )

        return .run { [aiChatSessionPersistenceClient, uuid] send in
            do {
                if let snapshot = try await aiChatSessionPersistenceClient.loadSession(sessionID) {
                    await send(Self.restoreOutcomeAction(for: snapshot, context: context, uuid: uuid))
                } else {
                    await send(Self.missingRestoreAction(context: context, uuid: uuid))
                }
            } catch {
                await send(Self.corruptedRestoreAction(context: context, uuid: uuid))
            }
        }
        .cancellable(id: CancelID.restore, cancelInFlight: true)
    }

    static func restoreOutcomeAction(
        for snapshot: AiChatSessionSnapshot,
        context: AiChatRestoreContext,
        uuid: UUIDGenerator,
    ) -> Action {
        if snapshot.status == .rebindRequired {
            return rebindRequiredRestoreAction(context: context, uuid: uuid)
        }
        let normalizedSnapshot = normalizeRestoredSnapshot(snapshot, catalogRows: context.catalogRows)
        return .restoreOutcome(
            requestedSessionID: context.sessionID,
            .restored(snapshot: normalizedSnapshot),
            restoreFailure: nil,
        )
    }

    static func rebindRequiredRestoreAction(context: AiChatRestoreContext, uuid: UUIDGenerator) -> Action {
        if let fallbackSnapshot = makeNewSessionSnapshot(
            sessionID: AiChatSessionID(rawValue: uuid()),
            catalogRows: context.catalogRows,
            selectedHandle: context.selectedHandle,
            selectedThinking: context.selectedThinking,
        ) {
            return .restoreOutcome(
                requestedSessionID: context.sessionID,
                .newSession(snapshot: fallbackSnapshot),
                restoreFailure: .contextMismatch,
            )
        }
        return .restoreOutcome(
            requestedSessionID: context.sessionID,
            .failed(reason: .contextMismatch),
            restoreFailure: .contextMismatch,
        )
    }

    static func missingRestoreAction(context: AiChatRestoreContext, uuid: UUIDGenerator) -> Action {
        fallbackRestoreAction(context: context, uuid: uuid, failure: .missingRecord)
    }

    static func corruptedRestoreAction(context: AiChatRestoreContext, uuid: UUIDGenerator) -> Action {
        fallbackRestoreAction(context: context, uuid: uuid, failure: .corruptedRecord)
    }

    static func fallbackRestoreAction(
        context: AiChatRestoreContext,
        uuid: UUIDGenerator,
        failure: AiChatSessionRestoreFailure,
    ) -> Action {
        if let snapshot = makeFallbackRestoreSnapshot(
            uuid: uuid,
            catalogRows: context.catalogRows,
            selectedHandle: context.selectedHandle,
            selectedThinking: context.selectedThinking,
        ) {
            return .restoreOutcome(
                requestedSessionID: context.sessionID,
                .newSession(snapshot: snapshot),
                restoreFailure: failure,
            )
        }
        return .restoreOutcome(
            requestedSessionID: context.sessionID,
            .failed(reason: failure),
            restoreFailure: failure,
        )
    }

    static func makeFallbackRestoreSnapshot(
        uuid: UUIDGenerator,
        catalogRows: [AiModelCatalogRow],
        selectedHandle: AiModelHandle?,
        selectedThinking: AiThinkingSelection?,
    ) -> AiChatSessionSnapshot? {
        makeNewSessionSnapshot(
            sessionID: AiChatSessionID(rawValue: uuid()),
            catalogRows: catalogRows,
            selectedHandle: selectedHandle,
            selectedThinking: selectedThinking,
        )
    }

    func apply(setup: AiChatSetupState, to state: inout State) {
        applySetupSession(setup, to: &state)
        applySetupModelState(setup, to: &state)
        clearSetupRuntimeState(&state)
    }

    private func applySetupSession(_ setup: AiChatSetupState, to state: inout State) {
        state.restoreSessionID = setup.restoreSessionID
        state.restoreOutcome = nil
        state.restoreFailure = nil
        state.sessionID = setup.sessionID
        state.sessionStatus = setup.sessionStatus
        state.currentContext = setup.currentContext
        state.transcriptHistory = setup.transcriptHistory
        state.draftText = setup.draftText
        state.streamingAssistantDraft = nil
    }

    private func applySetupModelState(_ setup: AiChatSetupState, to state: inout State) {
        state.catalogRows = setup.catalogRows
        state.modelListState = State.modelListState(from: setup.catalogRows)
        state.selectedModelHandle = setup.selectedModelHandle
        state.selectedThinking = setup.selectedThinking
        state.unavailableSelectedModelHandle = nil
        state.lockedModelHandle = setup.lockedModelHandle
        state.lastExecutionFailure = setup.lastExecutionFailure
        state.executionPhase = .idle
    }

    private func clearSetupRuntimeState(_ state: inout State) {
        state.modelListRequestID = nil
        state.modelListProvider = nil
        state.modelListProviderOrder = []
        state.modelListPendingProviders = []
        state.modelListLoadedModelsByProvider = [:]
        state.modelListFailedProviders = [:]
    }

    func applyRestoreOutcome(
        _ result: AiChatSessionRestoreResult,
        restoreFailure: AiChatSessionRestoreFailure?,
        state: inout State,
    ) {
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
            state.sessionStatus = .failed
            state.restoreFailure = reason
            state.restoreOutcome = nil
        }

        normalizeSelectionIfNeeded(&state)
    }

    func applyRestoredSnapshot(_ snapshot: AiChatSessionSnapshot, state: inout State) {
        state.sessionID = snapshot.sessionID
        state.sessionStatus = .active
        state.transcriptHistory = snapshot.transcriptHistory
        state.streamingAssistantDraft = nil
        state.lockedModelHandle = nil
        state.lastExecutionFailure = nil
        state.executionPhase = .idle
        state.selectedModelHandle = snapshot.model
        state.selectedThinking = snapshot.selectedThinking
    }

    func applyNewSessionSnapshot(_ snapshot: AiChatSessionSnapshot, state: inout State) {
        state.sessionID = snapshot.sessionID
        state.sessionStatus = .idle
        state.transcriptHistory = []
        state.streamingAssistantDraft = nil
        state.lockedModelHandle = nil
        state.lastExecutionFailure = nil
        state.executionPhase = .idle
        state.selectedModelHandle = snapshot.model
        state.selectedThinking = snapshot.selectedThinking
    }

    static func normalizeRestoredSnapshot(
        _ snapshot: AiChatSessionSnapshot,
        catalogRows: [AiModelCatalogRow],
    ) -> AiChatSessionSnapshot {
        let selectedRow = catalogRows.first(where: { $0.handle == snapshot.model })
        return AiChatSessionSnapshot(
            sessionID: snapshot.sessionID,
            status: .active,
            provider: snapshot.provider,
            model: snapshot.model,
            selectedModelRow: selectedRow,
            selectedThinking: snapshot.selectedThinking,
            transcriptHistory: snapshot.transcriptHistory,
            lastRequestID: snapshot.lastRequestID,
            lastRunID: snapshot.lastRunID,
            updatedAtMs: snapshot.updatedAtMs,
        )
    }

    static func makeNewSessionSnapshot(
        sessionID: AiChatSessionID,
        catalogRows: [AiModelCatalogRow],
        selectedHandle: AiModelHandle?,
        selectedThinking: AiThinkingSelection?,
    ) -> AiChatSessionSnapshot? {
        guard let selectedHandle,
              let selectedRow = catalogRows.first(where: { $0.handle == selectedHandle })
        else {
            return nil
        }

        return AiChatSessionSnapshot(
            sessionID: sessionID,
            status: .idle,
            provider: selectedHandle.provider,
            model: selectedHandle,
            selectedModelRow: selectedRow,
            selectedThinking: selectedThinking,
            transcriptHistory: [],
            updatedAtMs: 0,
        )
    }
}

struct AiChatRestoreContext {
    var sessionID: AiChatSessionID
    var catalogRows: [AiModelCatalogRow]
    var selectedHandle: AiModelHandle?
    var selectedThinking: AiThinkingSelection?
}
