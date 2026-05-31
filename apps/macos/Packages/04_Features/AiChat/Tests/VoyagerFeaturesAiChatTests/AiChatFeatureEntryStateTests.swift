import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi
@testable import VoyagerFeaturesAiChat
import XCTest

// swiftlint:disable:next type_body_length
@MainActor
final class AiChatFeatureEntryStateTests: XCTestCase {
    func testCurrentContextSummaryFixturesMatchInspectorContract() {
        let selectedHandle = makeCatalogRows()[0].handle

        let selectedEntriesState = AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            currentContext: makeContextSnapshot(
                summary: "Documents · 2 selected",
                references: [],
                items: [],
                attachments: [],
            ),
            transcriptHistory: [],
            draftText: "",
            catalogRows: makeCatalogRows(),
            selectedModelHandle: selectedHandle,
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
            executionPhase: .idle,
        )
        XCTAssertEqual(selectedEntriesState.currentContextSummaryDisplayModel.title, "Documents · 2 selected")
        XCTAssertNil(selectedEntriesState.currentContextSummaryDisplayModel.detail)

        let locationOnlyState = AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            currentContext: makeContextSnapshot(summary: "Documents", references: [], items: [], attachments: []),
            transcriptHistory: [],
            draftText: "",
            catalogRows: makeCatalogRows(),
            selectedModelHandle: selectedHandle,
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
            executionPhase: .idle,
        )
        XCTAssertEqual(locationOnlyState.currentContextSummaryDisplayModel.title, "Documents")
        XCTAssertNil(locationOnlyState.currentContextSummaryDisplayModel.detail)

        let emptyContextState = AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            currentContext: .init(),
            transcriptHistory: [],
            draftText: "",
            catalogRows: makeCatalogRows(),
            selectedModelHandle: selectedHandle,
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
            executionPhase: .idle,
        )
        XCTAssertEqual(emptyContextState.currentContextSummaryDisplayModel.title, "No current selection")
        XCTAssertNil(emptyContextState.currentContextSummaryDisplayModel.detail)
    }

    func testProviderUnavailableSurfaceUsesFixedBannerAndEmptyComposerModelLabel() {
        let state = AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            currentContext: makeContextSnapshot(summary: "Documents", references: [], items: [], attachments: []),
            transcriptHistory: [],
            draftText: "Hello",
            catalogRows: [],
            selectedModelHandle: nil,
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
            executionPhase: .idle,
        )

        XCTAssertEqual(state.connectionState, .connected)
        XCTAssertFalse(state.canSubmit)
        XCTAssertEqual(state.chatInputDisplayModel.modelLabel, "No models available")
        XCTAssertEqual(state.chatInputDisplayModel.effortLabel, "No models available")

        if case let .empty(summary, selectedModel) = state.surfaceState {
            XCTAssertNil(selectedModel)
            XCTAssertEqual(summary.title, "Documents")
        } else {
            XCTFail("Expected empty surface with no loaded models")
        }
    }

    func testCanSubmitDisallowsRetryWhileFailureSurfaceExists() {
        let catalogRows = makeCatalogRows()
        let state = AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            currentContext: makeContextSnapshot(summary: "Documents", references: [], items: [], attachments: []),
            transcriptHistory: [],
            draftText: "Retry after failure",
            catalogRows: catalogRows,
            selectedModelHandle: catalogRows[0].handle,
            lockedModelHandle: nil,
            lastExecutionFailure: .transportError,
            executionPhase: .idle,
        )
        let store = TestStore(initialState: state) {
            AiChatFeature()
        }
        XCTAssertFalse(store.state.canSubmit)
    }

    func testSubmitTappedIsNoOpWhenCanSubmitIsFalse() async {
        final class ExecutionRequestSpy: @unchecked Sendable {
            private(set) var requests: [AiChatRequest] = []

            func append(_ request: AiChatRequest) {
                requests.append(request)
            }
        }

        let requestSpy = ExecutionRequestSpy()
        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            currentContext: makeContextSnapshot(summary: "Documents", references: [], items: [], attachments: []),
            transcriptHistory: [],
            draftText: "Hello",
            catalogRows: [],
            selectedModelHandle: nil,
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
            executionPhase: .idle,
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.aiChatExecutionClient = AiChatExecutionClient(execute: { request in
                requestSpy.append(request)
                return AsyncStream { continuation in
                    continuation.finish()
                }
            })
        }

        XCTAssertFalse(store.state.canSubmit)

        await store.send(.submitTapped)

        XCTAssertTrue(requestSpy.requests.isEmpty)
        XCTAssertEqual(store.state.draftText, "Hello")
        XCTAssertEqual(store.state.executionPhase, .idle)
        XCTAssertNil(store.state.lockedModelHandle)

        await store.finish()
    }
}
