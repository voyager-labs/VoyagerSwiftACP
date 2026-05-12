import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi

extension AiChatFeature {
    // swiftlint:disable:next function_body_length
    func restoreSession(sessionID: AiChatSessionID, state: State) -> Effect<Action> {
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
                        await send(.restoreOutcome(
                            requestedSessionID: sessionID,
                            .newSession(snapshot: fallbackSnapshot),
                            restoreFailure: .contextMismatch
                        ))
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

                let snapshot = Self.makeFallbackRestoreSnapshot(
                    uuid: uuid,
                    catalogRows: catalogRows,
                    selectedHandle: selectedHandle
                )
                await send(.restoreOutcome(
                    requestedSessionID: sessionID,
                    .newSession(snapshot: snapshot),
                    restoreFailure: .missingRecord
                ))
            } catch {
                let snapshot = Self.makeFallbackRestoreSnapshot(
                    uuid: uuid,
                    catalogRows: catalogRows,
                    selectedHandle: selectedHandle
                )
                await send(.restoreOutcome(
                    requestedSessionID: sessionID,
                    .newSession(snapshot: snapshot),
                    restoreFailure: .corruptedRecord
                ))
            }
        }
        .cancellable(id: CancelID.restore, cancelInFlight: true)
    }

    static func makeFallbackRestoreSnapshot(
        uuid: UUIDGenerator,
        catalogRows: [AiModelCatalogRow],
        selectedHandle: AiModelHandle?
    ) -> AiChatSessionSnapshot {
        makeNewSessionSnapshot(
            sessionID: AiChatSessionID(rawValue: uuid()),
            catalogRows: catalogRows,
            selectedHandle: selectedHandle
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
        state.selectedModelHandle = setup.selectedModelHandle
        state.lockedModelHandle = setup.lockedModelHandle
        state.lastExecutionFailure = setup.lastExecutionFailure
        state.executionPhase = .idle
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
    }

    func applyNewSessionSnapshot(_ snapshot: AiChatSessionSnapshot, state: inout State) {
        state.sessionID = snapshot.sessionID
        state.sessionStatus = .idle
        state.transcriptHistory = []
        state.lockedModelHandle = nil
        state.lastExecutionFailure = nil
        state.executionPhase = .idle
        state.selectedModelHandle = snapshot.model
    }

    static func normalizeRestoredSnapshot(
        _ snapshot: AiChatSessionSnapshot,
        catalogRows: [AiModelCatalogRow]
    ) -> AiChatSessionSnapshot {
        let selectedRow: AiModelCatalogRow?
        if let row = snapshot.selectedModelRow,
           catalogRows.contains(where: { $0.handle == row.handle }) {
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

    static func makeNewSessionSnapshot(
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
}
