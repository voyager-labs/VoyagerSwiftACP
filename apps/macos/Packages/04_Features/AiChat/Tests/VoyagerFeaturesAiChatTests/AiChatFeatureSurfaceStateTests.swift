import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi
@testable import VoyagerFeaturesAiChat
import XCTest

@MainActor
final class AiChatFeatureSurfaceStateTests: XCTestCase {
    // swiftlint:disable:next function_body_length
    func testSurfaceStateCoversEmptyReadyProcessingAndError() {
        let catalogRows = makeCatalogRows()
        let summary = makeContextSnapshot()
        let selectedHandle = catalogRows[0].handle

        let emptyState = AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            currentContext: .init(),
            transcriptHistory: [],
            draftText: "",
            streamDraftText: "",
            catalogRows: catalogRows,
            selectedModelHandle: selectedHandle,
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
            executionPhase: .idle
        )

        if case let .empty(summaryDisplay, selectedModel) = emptyState.surfaceState {
            XCTAssertTrue(summaryDisplay.isEmpty)
            XCTAssertEqual(selectedModel?.label.title, "GPT-4.1 Mini")
        } else {
            XCTFail("Expected empty surface state")
        }
        if case let .empty(emptyDisplay) = emptyState.skeletonSurfaceDisplayModel {
            XCTAssertEqual(emptyDisplay.title, "Ask about this context")
            XCTAssertEqual(emptyDisplay.detail, "Send a message to start a contextual chat.")
        } else {
            XCTFail("Expected skeleton empty surface state")
        }

        let currentContextInitialState = AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            currentContext: summary,
            transcriptHistory: [],
            draftText: "What changed?",
            streamDraftText: "",
            catalogRows: catalogRows,
            selectedModelHandle: selectedHandle,
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
            executionPhase: .idle
        )

        if case let .empty(summaryDisplay, selectedModel) = currentContextInitialState.surfaceState {
            XCTAssertFalse(summaryDisplay.isEmpty)
            XCTAssertEqual(summaryDisplay.title, "Four files selected")
            XCTAssertEqual(selectedModel?.label.title, "GPT-4.1 Mini")
        } else {
            XCTFail("Expected current-context draft to keep empty surface state")
        }
        XCTAssertTrue(currentContextInitialState.canSubmit)
        XCTAssertEqual(currentContextInitialState.chatInputDisplayModel.placeholder, "Ask anything…")
        XCTAssertEqual(currentContextInitialState.chatInputDisplayModel.modelLabel, "GPT-4.1 Mini")
        XCTAssertEqual(currentContextInitialState.chatInputDisplayModel.effortLabel, "xhigh")
        XCTAssertTrue(currentContextInitialState.chatInputDisplayModel.canSubmit)
        XCTAssertTrue(currentContextInitialState.chatInputDisplayModel.isSubmitVisible)
        XCTAssertFalse(currentContextInitialState.chatInputDisplayModel.isStopVisible)

        let readyState = AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            currentContext: summary,
            transcriptHistory: [AiChatMessage(role: .user, content: "Hello")],
            draftText: "Draft",
            streamDraftText: "",
            catalogRows: catalogRows,
            selectedModelHandle: selectedHandle,
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
            executionPhase: .idle
        )

        if case let .ready(summaryDisplay, selectedModel) = readyState.surfaceState {
            XCTAssertFalse(summaryDisplay.isEmpty)
            XCTAssertEqual(selectedModel?.label.title, "GPT-4.1 Mini")
        } else {
            XCTFail("Expected ready surface state")
        }
        if case .ready = readyState.skeletonSurfaceDisplayModel {
        } else {
            XCTFail("Expected ready skeleton surface state")
        }

        let processingState = AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            currentContext: summary,
            transcriptHistory: [AiChatMessage(role: .user, content: "Hello")],
            draftText: "Draft",
            streamDraftText: "Streaming",
            catalogRows: catalogRows,
            selectedModelHandle: selectedHandle,
            lockedModelHandle: catalogRows[1].handle,
            lastExecutionFailure: nil,
            executionPhase: .processing(makeRequestLock(
                kind: .submit,
                request: AiChatRequest(
                    context: makeRequestContext(
                        sessionID: AiChatSessionID(rawValue: UUID()),
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
        )

        if case let .processing(processing, _, selectedModel) = processingState.surfaceState {
            XCTAssertEqual(processing.lockedModel.label.title, "Claude Sonnet 4")
            XCTAssertEqual(processing.cancelAffordance.title, "Cancel request")
            XCTAssertEqual(selectedModel?.label.title, "GPT-4.1 Mini")
        } else {
            XCTFail("Expected processing surface state")
        }
        if case let .processing(processing) = processingState.skeletonSurfaceDisplayModel {
            XCTAssertEqual(processing.lockedModel.label.title, "Claude Sonnet 4")
        } else {
            XCTFail("Expected processing skeleton surface state")
        }
        XCTAssertFalse(processingState.canSubmit)
        XCTAssertTrue(processingState.chatInputDisplayModel.isStopVisible)
        XCTAssertFalse(processingState.chatInputDisplayModel.isSubmitVisible)
        XCTAssertTrue(processingState.chatInputDisplayModel.canStop)

        let refreshedProcessingState = AiChatFeature.State(
            sessionID: processingState.sessionID,
            sessionStatus: .active,
            currentContext: summary,
            transcriptHistory: processingState.transcriptHistory,
            draftText: processingState.draftText,
            streamDraftText: processingState.streamDraftText,
            catalogRows: [],
            selectedModelHandle: nil,
            lockedModelHandle: catalogRows[1].handle,
            lastExecutionFailure: nil,
            executionPhase: processingState.executionPhase
        )

        if case let .processing(processing, _, selectedModel) = refreshedProcessingState.surfaceState {
            XCTAssertEqual(processing.lockedModel.label.title, "Claude Sonnet 4")
            XCTAssertNil(selectedModel)
        } else {
            XCTFail("Expected processing surface state to survive model refresh")
        }
        XCTAssertTrue(refreshedProcessingState.isProcessing)
        XCTAssertTrue(refreshedProcessingState.chatInputDisplayModel.isStopVisible)
        XCTAssertTrue(refreshedProcessingState.chatInputDisplayModel.canStop)

        let errorState = AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .failed,
            currentContext: summary,
            transcriptHistory: [],
            draftText: "",
            streamDraftText: "",
            catalogRows: catalogRows,
            selectedModelHandle: selectedHandle,
            lockedModelHandle: nil,
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
        )

        if case let .ready(_, selectedModel) = errorState.surfaceState {
            XCTAssertEqual(selectedModel?.label.title, "GPT-4.1 Mini")
        } else {
            XCTFail("Expected terminal failure to remain in message-area ready surface")
        }
        if case .ready = errorState.skeletonSurfaceDisplayModel {
        } else {
            XCTFail("Expected terminal failure skeleton to remain in ready surface")
        }
        XCTAssertEqual(errorState.requestStatusText, "The chat service is temporarily unavailable.")
    }

    func testTerminalSurfaceReflectsDisconnectedProvider() {
        let catalogRows = makeCatalogRows()
        let selectedHandle = catalogRows[0].handle
        let request = AiChatRequest(
            context: makeRequestContext(
                sessionID: AiChatSessionID(rawValue: UUID()),
                requestID: AiChatRequestID(rawValue: UUID()),
                runID: AiChatRunID(rawValue: UUID()),
                model: selectedHandle,
                selectedRow: catalogRows[0]
            ),
            messages: []
        )
        let lock = makeRequestLock(
            kind: .submit,
            request: request,
            selectedHandle: selectedHandle,
            selectedRow: catalogRows[0],
            assistantReplacementIndex: nil
        )
        let disconnectedState = AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            currentContext: makeContextSnapshot(),
            transcriptHistory: [
                AiChatMessage(role: .user, content: "Hello"),
                AiChatMessage(role: .assistant, content: "Hi")
            ],
            draftText: "Follow up",
            streamDraftText: "",
            catalogRows: [],
            selectedModelHandle: selectedHandle,
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
            executionPhase: .completed(lock)
        )

        if case let .unconnected(connection, summary) = disconnectedState.surfaceState {
            XCTAssertEqual(connection.title, "Connect an AI provider")
            XCTAssertEqual(connection.fixLabel, "Open Settings")
            XCTAssertFalse(summary.isEmpty)
        } else {
            XCTFail("Expected completed session to surface provider disconnection")
        }
        if case let .unconnected(connection) = disconnectedState.skeletonSurfaceDisplayModel {
            XCTAssertEqual(connection.fixLabel, "Open Settings")
        } else {
            XCTFail("Expected skeleton surface to expose provider disconnection")
        }
        XCTAssertFalse(disconnectedState.canSubmit)
        XCTAssertFalse(disconnectedState.chatInputDisplayModel.canSubmit)
    }

}
