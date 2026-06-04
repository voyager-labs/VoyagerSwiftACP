import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi
@testable import VoyagerFeaturesAiChat
import XCTest

@MainActor
final class AiChatFeatureRecoveryTests: XCTestCase {
    func testSelectedModelChangedClearsUnavailableSelectionWithoutMutatingLockedModel() async {
        let catalogRows = makeCatalogRows()
        let summary = makeContextSnapshot()
        let sessionID = AiChatSessionID(rawValue: makeUUID("22222222-2222-2222-2222-222222222222"))
        let unresolvableHandle = makeUnresolvableModelHandle()
        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: sessionID,
            sessionStatus: .active,
            currentContext: summary,
            transcriptHistory: [AiChatMessage(role: .user, content: "Hello")],
            draftText: "Draft",
            catalogRows: catalogRows,
            selectedModelHandle: catalogRows[1].handle,
            lockedModelHandle: catalogRows[1].handle,
            lastExecutionFailure: nil,
            executionPhase: .processing(makeRequestLock(
                kind: .submit,
                request: AiChatRequest(
                    context: makeRequestContext(
                        sessionID: sessionID,
                        requestID: AiChatRequestID(rawValue: UUID()),
                        runID: AiChatRunID(rawValue: UUID()),
                        model: catalogRows[1].handle,
                        selectedRow: catalogRows[1]
                    ),
                    messages: []
                ),
                selectedHandle: catalogRows[1].handle,
                selectedRow: catalogRows[1],
                assistantReplacementIndex: nil
            ))
        )) {
            AiChatFeature()
        }

        await store.send(.selectedModelChanged(unresolvableHandle)) { state in
            state.selectedModelHandle = nil
            state.unavailableSelectedModelHandle = nil
        }

        XCTAssertEqual(store.state.lockedModelHandle, catalogRows[1].handle)
        XCTAssertNil(store.state.selectedModelHandle)

        if case let .processing(processing, _, selectedModel) = store.state.surfaceState {
            XCTAssertEqual(processing.lockedModel.label.title, "Claude Sonnet 4")
            XCTAssertNil(selectedModel)
        } else {
            XCTFail("Expected processing surface state after clearing invalid selection")
        }
    }

    func testDraftTextChangeClearsStaleFailureAndResetStillClearsTranscript() async {
        let catalogRows = makeCatalogRows()
        let selectedHandle = catalogRows[0].handle
        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            currentContext: makeContextSnapshot(summary: "Documents", references: [], items: [], attachments: []),
            transcriptHistory: [AiChatMessage(role: .user, content: "Hello")],
            draftText: "Draft",
            catalogRows: catalogRows,
            selectedModelHandle: selectedHandle,
            lastExecutionFailure: .transportError,
            executionPhase: .failed(makeRequestLock(
                kind: .submit,
                request: AiChatRequest(
                    context: makeRequestContext(
                        sessionID: AiChatSessionID(rawValue: UUID()),
                        requestID: AiChatRequestID(rawValue: UUID()),
                        runID: AiChatRunID(rawValue: UUID()),
                        model: selectedHandle,
                        selectedRow: catalogRows[0]
                    ),
                    messages: []
                ),
                selectedHandle: selectedHandle,
                selectedRow: catalogRows[0],
                assistantReplacementIndex: nil
            ), .transportError)
        )) {
            AiChatFeature()
        }

        XCTAssertFalse(store.state.canSubmit)

        await store.send(.draftTextChanged("Updated")) { state in
            state.draftText = "Updated"
            state.lastExecutionFailure = nil
            state.executionPhase = .idle
        }

        XCTAssertTrue(store.state.canSubmit)

        await store.send(.resetTapped) { state in
            state.draftText = ""
            state.transcriptHistory = []
            state.lastExecutionFailure = nil
            state.lockedModelHandle = nil
            state.executionPhase = .idle
        }

        await store.finish()
    }

    func testSelectedModelChangeClearsStaleFailureAndRestoresSubmitEligibility() async {
        let catalogRows = makeCatalogRows()
        let firstHandle = catalogRows[0].handle
        let secondHandle = catalogRows[1].handle
        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            currentContext: makeContextSnapshot(summary: "Documents", references: [], items: [], attachments: []),
            transcriptHistory: [],
            draftText: "Retry me",
            catalogRows: catalogRows,
            selectedModelHandle: firstHandle,
            lastExecutionFailure: .transportError,
            executionPhase: .failed(makeRequestLock(
                kind: .submit,
                request: AiChatRequest(
                    context: makeRequestContext(
                        sessionID: AiChatSessionID(rawValue: UUID()),
                        requestID: AiChatRequestID(rawValue: UUID()),
                        runID: AiChatRunID(rawValue: UUID()),
                        model: firstHandle,
                        selectedRow: catalogRows[0]
                    ),
                    messages: []
                ),
                selectedHandle: firstHandle,
                selectedRow: catalogRows[0],
                assistantReplacementIndex: nil
            ), .transportError)
        )) {
            AiChatFeature()
        }

        XCTAssertFalse(store.state.canSubmit)

        await store.send(.selectedModelChanged(secondHandle)) { state in
            state.selectedModelHandle = secondHandle
            state.lastExecutionFailure = nil
            state.executionPhase = .idle
        }

        XCTAssertTrue(store.state.canSubmit)
        await store.finish()
    }
}
