import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi
@testable import VoyagerFeaturesAiChat
import XCTest

@MainActor
final class AiChatFeatureSelectionTests: XCTestCase {
    func testModelSelectionIsNextRequestOnlyAndSameModelIsNoOp() async {
        let catalogRows = makeCatalogRows()
        let summary = makeContextSnapshot()
        let placeholderRequest = AiChatRequest(
            context: makeRequestContext(
                sessionID: AiChatSessionID(rawValue: UUID()),
                requestID: AiChatRequestID(rawValue: UUID()),
                runID: AiChatRunID(rawValue: UUID()),
                model: catalogRows[0].handle,
                selectedRow: catalogRows[0],
            ),
            messages: [],
        )
        let placeholderLock = makeRequestLock(
            kind: .submit,
            request: placeholderRequest,
            selectedHandle: catalogRows[0].handle,
            selectedRow: catalogRows[0],
            assistantReplacementIndex: nil,
        )
        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            currentContext: summary,
            transcriptHistory: [AiChatMessage(role: .user, content: "Hello")],
            draftText: "Draft",
            streamDraftText: "",
            catalogRows: catalogRows,
            selectedModelHandle: catalogRows[0].handle,
            lockedModelHandle: catalogRows[0].handle,
            lastExecutionFailure: nil,
            executionPhase: .processing(placeholderLock),
        )) {
            AiChatFeature()
        }

        await store.send(.selectedModelChanged(catalogRows[0].handle))

        await store.send(.selectedModelChanged(catalogRows[1].handle)) { state in
            state.selectedModelHandle = catalogRows[1].handle
        }

        XCTAssertEqual(store.state.lockedModelHandle, catalogRows[0].handle)

        if case let .processing(processing, _, selectedModel) = store.state.surfaceState {
            XCTAssertEqual(processing.lockedModel.label.title, "GPT-4.1 Mini")
            XCTAssertEqual(selectedModel?.label.title, "Claude Sonnet 4")
        } else {
            XCTFail("Expected processing surface state")
        }

        await store.send(.cancelTapped) { state in
            state.lockedModelHandle = nil
            state.executionPhase = .cancelled(placeholderLock)
        }

        XCTAssertEqual(store.state.selectedModelHandle, catalogRows[1].handle)
    }

    func testSetupFallsBackToFirstCatalogRowWhenSelectedModelIsUnresolvable() async {
        let catalogRows = makeCatalogRows()
        let summary = makeContextSnapshot()
        let sessionID = AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111111111"))
        let unresolvableHandle = makeUnresolvableModelHandle()
        let store = TestStore(initialState: AiChatFeature.State()) {
            AiChatFeature()
        }

        await store.send(.setup(AiChatSetupState(
            sessionID: sessionID,
            sessionStatus: .active,
            currentContext: summary,
            transcriptHistory: [],
            draftText: "",
            catalogRows: catalogRows,
            selectedModelHandle: unresolvableHandle,
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
        ))) { state in
            state.sessionID = sessionID
            state.sessionStatus = .active
            state.currentContext = summary
            state.transcriptHistory = []
            state.draftText = ""
            state.streamDraftText = ""
            state.catalogRows = catalogRows
            state.selectedModelHandle = catalogRows.first?.handle
            state.lockedModelHandle = nil
            state.lastExecutionFailure = nil
            state.executionPhase = .idle
        }

        XCTAssertEqual(store.state.selectedModelHandle, catalogRows.first?.handle)
        XCTAssertEqual(store.state.modelCatalogState.selectedModel?.handle, catalogRows.first?.handle)

        if case let .empty(summaryDisplay, selectedModel) = store.state.surfaceState {
            XCTAssertFalse(summaryDisplay.isEmpty)
            XCTAssertEqual(selectedModel?.handle, catalogRows.first?.handle)
        } else {
            XCTFail("Expected initial empty surface state after fallback")
        }
    }
}
