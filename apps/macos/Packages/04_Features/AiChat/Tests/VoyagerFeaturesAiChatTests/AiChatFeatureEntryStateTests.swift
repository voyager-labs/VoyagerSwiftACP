import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi
@testable import VoyagerFeaturesAiChat
import XCTest

@MainActor
final class AiChatFeatureEntryStateTests: XCTestCase {
    func testSetupBuildsUnconnectedEntryStateWithContextSummary() async {
        let store = TestStore(initialState: AiChatFeature.State()) {
            AiChatFeature()
        }

        let catalogRows = makeCatalogRows()
        let summary = makeContextSnapshot()

        await store.send(.setup(AiChatSetupState(
            sessionID: nil,
            sessionStatus: .idle,
            currentContext: summary,
            transcriptHistory: [],
            draftText: "",
            catalogRows: catalogRows,
            selectedModelHandle: nil,
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
        ))) { state in
            state.sessionID = nil
            state.sessionStatus = .idle
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

        await store.send(.onAppear)

        XCTAssertEqual(store.state.currentContextSummaryDisplayModel.title, "Four files selected")
        XCTAssertEqual(store.state.currentContextSummaryDisplayModel.detail, "1 reference · 1 item · 1 attachment")
        XCTAssertEqual(store.state.connectionState, .unconnected(.init(
            title: "No session connected",
            detail: "Start or open a session to continue from the current context.",
            fixLabel: "Open session",
        )))

        if case let .unconnected(connection, summaryDisplay) = store.state.surfaceState {
            XCTAssertEqual(connection.fixLabel, "Open session")
            XCTAssertEqual(summaryDisplay.title, "Four files selected")
        } else {
            XCTFail("Expected unconnected surface state")
        }

        XCTAssertEqual(store.state.modelFieldLabel, "Model")
        XCTAssertEqual(store.state.modelCatalogState.rows.first?.label.title, "GPT-4.1 Mini")
        XCTAssertEqual(
            store.state.modelCatalogState.rows.first?.label.subtitle,
            ProviderDescriptor.descriptor(for: catalogRows[0].handle.provider)?.displayName,
        )
        XCTAssertEqual(store.state.selectedModelHandle, catalogRows[0].handle)
    }

    // swiftlint:disable:next function_body_length
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
            streamDraftText: "",
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
            streamDraftText: "",
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
            streamDraftText: "",
            catalogRows: makeCatalogRows(),
            selectedModelHandle: selectedHandle,
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
            executionPhase: .idle,
        )
        XCTAssertEqual(emptyContextState.currentContextSummaryDisplayModel.title, "No current context")
        XCTAssertNil(emptyContextState.currentContextSummaryDisplayModel.detail)
    }

    func testProviderUnavailableSurfaceUsesSettingsFixtureAndDisablesSubmit() {
        let state = AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            currentContext: makeContextSnapshot(summary: "Documents", references: [], items: [], attachments: []),
            transcriptHistory: [],
            draftText: "Hello",
            streamDraftText: "",
            catalogRows: [],
            selectedModelHandle: nil,
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
            executionPhase: .idle,
        )

        XCTAssertEqual(state.connectionState, .error(.init(
            title: "No AI provider connected",
            detail: "Connect an AI provider in Settings to start chatting.",
            fixLabel: "Connect provider in Settings",
        )))
        XCTAssertFalse(state.canSubmit)

        if case let .error(connection, summary) = state.surfaceState {
            XCTAssertEqual(connection.title, "No AI provider connected")
            XCTAssertEqual(connection.detail, "Connect an AI provider in Settings to start chatting.")
            XCTAssertEqual(connection.fixLabel, "Connect provider in Settings")
            XCTAssertEqual(summary.title, "Documents")
        } else {
            XCTFail("Expected provider unavailable error surface")
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
            streamDraftText: "",
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
            streamDraftText: "",
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
