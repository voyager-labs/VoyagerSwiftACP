import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi
@testable import VoyagerFeaturesAiChat
import XCTest

// CBW-004 모델 선택 복구 회귀 테스트만 남긴다.

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
                        selectedRow: catalogRows[1],
                    ),
                    messages: [],
                ),
                selectedHandle: catalogRows[1].handle,
                selectedRow: catalogRows[1],
                assistantReplacementIndex: nil,
            )),
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
}
