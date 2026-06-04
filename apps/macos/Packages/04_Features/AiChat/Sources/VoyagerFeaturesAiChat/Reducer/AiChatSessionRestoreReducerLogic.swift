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
            } catch is CancellationError {
                return
            } catch {
                await send(Self.corruptedRestoreAction(context: context, uuid: uuid))
            }
        }
        .cancellable(id: CancelID.restore, cancelInFlight: true)
    }

    static func restoreOutcomeAction(
        for snapshot: AiChatSessionSnapshot,
        context: AiChatRestoreContext,
        uuid _: UUIDGenerator,
    ) -> Action {
        let normalizedSnapshot = normalizeRestoredSnapshot(snapshot, catalogRows: context.catalogRows)
        if snapshot.status == .rebindRequired {
            return .restoreOutcome(
                requestedSessionID: context.sessionID,
                .rebindRequired(snapshot: normalizedSnapshot),
                restoreFailure: .contextMismatch,
            )
        }
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
        state.currentSessionCustomTitle = nil
        state.currentContext = setup.currentContext
        state.lastRequestContext = nil
        state.lastRequestContextModelHandle = nil
        state.transcriptHistory = setup.transcriptHistory
        state.draftText = setup.draftText
        state.streamingAssistantDraft = nil
        state.addedAttachments = []
        state.currentContextFolderStructureModes = [:]
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
            applyRestoredSnapshot(snapshot, state: &state)
            state.sessionStatus = .rebindRequired
            state.restoreOutcome = result
            state.restoreFailure = restoreFailure ?? .contextMismatch

        case let .failed(reason):
            state.sessionStatus = .failed
            state.restoreFailure = reason
            state.restoreOutcome = nil
        }

        normalizeSelectionIfNeeded(&state)
    }

    func applyRestoredSnapshot(_ snapshot: AiChatSessionSnapshot, state: inout State) {
        let preservedExecutionPhase = preservedNavigationExecutionPhase(for: snapshot.sessionID, state: state)
        state.sessionID = snapshot.sessionID
        state.sessionStatus = .active
        state.currentSessionCustomTitle = snapshot.customTitle
        state.transcriptHistory = snapshot.transcriptHistory
        state.streamingAssistantDraft = nil
        state.lockedModelHandle = nil
        state.lastExecutionFailure = nil
        state.lastRequestContext = snapshot.lastRequestContext
        state.lastRequestContextModelHandle = snapshot.lastRequestContext == nil ? nil : snapshot.model
        state.addedAttachments = []
        state.currentContextFolderStructureModes = [:]
        state.executionPhase = preservedExecutionPhase ?? .idle
        state.selectedModelHandle = snapshot.model
        state.selectedThinking = snapshot.selectedThinking
    }

    private func preservedNavigationExecutionPhase(
        for _: AiChatSessionID,
        state: State,
    ) -> AiChatExecutionPhase? {
        switch state.executionPhase {
        case let .processing(lock):
            .processing(lock)
        case let .failed(lock, failure):
            .failed(lock, failure)
        case .idle, .completed, .cancelled, .persistenceRecovery:
            nil
        }
    }

    func applyNewSessionSnapshot(_ snapshot: AiChatSessionSnapshot, state: inout State) {
        let preservedExecutionPhase = preservedNavigationExecutionPhase(for: snapshot.sessionID, state: state)
        state.sessionID = snapshot.sessionID
        state.sessionStatus = .idle
        state.currentSessionCustomTitle = snapshot.customTitle
        state.transcriptHistory = []
        state.streamingAssistantDraft = nil
        state.lockedModelHandle = nil
        state.lastExecutionFailure = nil
        state.lastRequestContext = nil
        state.lastRequestContextModelHandle = nil
        state.addedAttachments = []
        state.currentContextFolderStructureModes = [:]
        state.executionPhase = preservedExecutionPhase ?? .idle
        state.selectedModelHandle = snapshot.model
        state.selectedThinking = snapshot.selectedThinking
    }

    static func normalizeRestoredSnapshot(
        _ snapshot: AiChatSessionSnapshot,
        catalogRows: [AiModelCatalogRow],
    ) -> AiChatSessionSnapshot {
        let selectedRow = snapshot.model.flatMap { model in catalogRows.first(where: { $0.handle == model }) }
        return AiChatSessionSnapshot(
            sessionID: snapshot.sessionID,
            status: .active,
            customTitle: snapshot.customTitle,
            provider: snapshot.provider,
            model: snapshot.model,
            selectedModelRow: selectedRow,
            selectedThinking: snapshot.selectedThinking,
            transcriptHistory: snapshot.transcriptHistory,
            lastRequestID: snapshot.lastRequestID,
            lastRunID: snapshot.lastRunID,
            lastRequestContext: snapshot.lastRequestContext,
            updatedAtMs: snapshot.updatedAtMs,
        )
    }

    static func makeNewSessionSnapshot(
        sessionID: AiChatSessionID,
        catalogRows: [AiModelCatalogRow],
        selectedHandle: AiModelHandle?,
        selectedThinking: AiThinkingSelection?,
    ) -> AiChatSessionSnapshot? {
        let selectedRow = selectedHandle.flatMap { handle in catalogRows.first(where: { $0.handle == handle }) }

        return AiChatSessionSnapshot(
            sessionID: sessionID,
            status: .idle,
            customTitle: nil,
            provider: selectedHandle?.provider,
            model: selectedHandle,
            selectedModelRow: selectedRow,
            selectedThinking: selectedHandle == nil ? nil : selectedThinking,
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
