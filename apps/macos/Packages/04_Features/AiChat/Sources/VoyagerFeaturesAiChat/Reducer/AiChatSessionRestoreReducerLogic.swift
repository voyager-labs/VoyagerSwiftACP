import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi

extension AiChatFeature {
    // swiftlint:disable:next function_body_length
    func restoreSession(sessionID: AiChatSessionID, state: State) -> Effect<Action> {
        let catalogRows = state.catalogRows
        let selectedHandle = state.selectedModelHandle
        let selectedThinking = state.selectedThinking

        return .run { [aiChatSessionPersistenceClient, uuid] send in
            do {
                if let snapshot = try await aiChatSessionPersistenceClient.loadSession(sessionID) {
                    if snapshot.status == .rebindRequired {
                        if let fallbackSnapshot = Self.makeNewSessionSnapshot(
                            sessionID: AiChatSessionID(rawValue: uuid()),
                            catalogRows: catalogRows,
                            selectedHandle: selectedHandle,
                            selectedThinking: selectedThinking
                        ) {
                            await send(.restoreOutcome(
                                requestedSessionID: sessionID,
                                .newSession(snapshot: fallbackSnapshot),
                                restoreFailure: .contextMismatch
                            ))
                        } else {
                            await send(.restoreOutcome(
                                requestedSessionID: sessionID,
                                .failed(reason: .contextMismatch),
                                restoreFailure: .contextMismatch
                            ))
                        }
                    } else {
                        let normalizedSnapshot = Self.normalizeRestoredSnapshot(snapshot, catalogRows: catalogRows)
                        let result = AiChatSessionRestoreResult.restored(snapshot: normalizedSnapshot)
                        await send(.restoreOutcome(
                            requestedSessionID: sessionID,
                            result,
                            restoreFailure: nil
                        ))
                    }
                    return
                }

                if let snapshot = Self.makeFallbackRestoreSnapshot(
                    uuid: uuid,
                    catalogRows: catalogRows,
                    selectedHandle: selectedHandle,
                    selectedThinking: selectedThinking
                ) {
                    await send(.restoreOutcome(
                        requestedSessionID: sessionID,
                        .newSession(snapshot: snapshot),
                        restoreFailure: .missingRecord
                    ))
                } else {
                    await send(.restoreOutcome(
                        requestedSessionID: sessionID,
                        .failed(reason: .missingRecord),
                        restoreFailure: .missingRecord
                    ))
                }
            } catch {
                if let snapshot = Self.makeFallbackRestoreSnapshot(
                    uuid: uuid,
                    catalogRows: catalogRows,
                    selectedHandle: selectedHandle,
                    selectedThinking: selectedThinking
                ) {
                    await send(.restoreOutcome(
                        requestedSessionID: sessionID,
                        .newSession(snapshot: snapshot),
                        restoreFailure: .corruptedRecord
                    ))
                } else {
                    await send(.restoreOutcome(
                        requestedSessionID: sessionID,
                        .failed(reason: .corruptedRecord),
                        restoreFailure: .corruptedRecord
                    ))
                }
            }
        }
        .cancellable(id: CancelID.restore, cancelInFlight: true)
    }

    static func makeFallbackRestoreSnapshot(
        uuid: UUIDGenerator,
        catalogRows: [AiModelCatalogRow],
        selectedHandle: AiModelHandle?,
        selectedThinking: AiThinkingSelection?
    ) -> AiChatSessionSnapshot? {
        makeNewSessionSnapshot(
            sessionID: AiChatSessionID(rawValue: uuid()),
            catalogRows: catalogRows,
            selectedHandle: selectedHandle,
            selectedThinking: selectedThinking
        )
    }

    func apply(setup: AiChatSetupState, to state: inout State) {
        state.restoreSessionID = setup.restoreSessionID
        state.restoreOutcome = nil
        state.restoreFailure = nil
        state.sessionID = setup.sessionID
        state.sessionStatus = setup.sessionStatus
        state.currentContext = setup.currentContext
        state.transcriptHistory = setup.transcriptHistory
        state.draftText = setup.draftText
        state.catalogRows = setup.catalogRows
        state.modelListState = State.modelListState(from: setup.catalogRows)
        state.selectedModelHandle = setup.selectedModelHandle
        state.selectedThinking = setup.selectedThinking
        state.unavailableSelectedModelHandle = nil
        state.lockedModelHandle = setup.lockedModelHandle
        state.lastExecutionFailure = setup.lastExecutionFailure
        state.executionPhase = .idle
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
        state: inout State
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
        state.lockedModelHandle = nil
        state.lastExecutionFailure = nil
        state.executionPhase = .idle
        state.selectedModelHandle = snapshot.model
        state.selectedThinking = snapshot.selectedThinking
    }

    static func normalizeRestoredSnapshot(
        _ snapshot: AiChatSessionSnapshot,
        catalogRows: [AiModelCatalogRow]
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
            updatedAtMs: snapshot.updatedAtMs
        )
    }

    static func makeNewSessionSnapshot(
        sessionID: AiChatSessionID,
        catalogRows: [AiModelCatalogRow],
        selectedHandle: AiModelHandle?,
        selectedThinking: AiThinkingSelection?
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
            updatedAtMs: 0
        )
    }
}
