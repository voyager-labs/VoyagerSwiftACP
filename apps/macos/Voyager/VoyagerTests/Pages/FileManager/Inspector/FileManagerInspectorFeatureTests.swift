import ComposableArchitecture
import Foundation
@testable import Voyager
import VoyagerEntitiesAi
import VoyagerFeaturesAiChat
import XCTest

@MainActor
final class FileManagerInspectorFeatureTests: XCTestCase {
    func testOpenChatShowsInspectorAndAppliesSetup() async {
        let setup = makeSetup(
            sessionID: makeSessionID("00000000-0000-0000-0000-000000000001"),
            summary: "Documents · 2 selected",
        )

        let store = TestStore(initialState: FileManagerInspectorFeature.State()) {
            FileManagerInspectorFeature()
        }

        await store.send(.openChat(setup, .empty())) {
            $0.inspectorVisible = true
            $0.activeMode = .chat
        }

        await store.receive(\.aiChat.setup) {
            $0.aiChat.sessionID = setup.sessionID
            $0.aiChat.sessionStatus = setup.sessionStatus
            $0.aiChat.currentContext = setup.currentContext
            $0.aiChat.transcriptHistory = setup.transcriptHistory
            $0.aiChat.draftText = setup.draftText
            $0.aiChat.catalogRows = setup.catalogRows
            $0.aiChat.selectedModelHandle = setup.selectedModelHandle
            $0.aiChat.lockedModelHandle = setup.lockedModelHandle
            $0.aiChat.lastExecutionFailure = setup.lastExecutionFailure
            $0.aiChat.executionPhase = .idle
        }

        await store.receive(\.aiChat.providerConnectionsUpdated)

        XCTAssertTrue(store.state.inspectorVisible)
        XCTAssertEqual(store.state.activeMode, .chat)
        XCTAssertEqual(store.state.aiChat.currentContext.summary, "Documents · 2 selected")
    }

    func testCloseChatHidesInspectorPane() async {
        let store = TestStore(initialState: FileManagerInspectorFeature.State(
            inspectorVisible: true,
            inspectorPaneExists: true,
            activeMode: .chat,
        )) {
            FileManagerInspectorFeature()
        }

        await store.send(.closeChat) {
            $0.inspectorVisible = false
        }

        XCTAssertEqual(store.state.activeMode, .chat)
        XCTAssertTrue(store.state.inspectorPaneExists)
    }

    func testOpenChatAfterClosePreservesExistingConversationAndSelection() async {
        let existingSetup = makeSetup(
            sessionID: makeSessionID("00000000-0000-0000-0000-000000000030"),
            summary: "Documents · previous context",
        )
        let replacementSetup = makeSetup(
            sessionID: makeSessionID("00000000-0000-0000-0000-000000000040"),
            summary: "Desktop · replacement context",
        )
        var initialState = FileManagerInspectorFeature.State(
            inspectorVisible: false,
            inspectorPaneExists: true,
            activeMode: .chat,
            aiChat: AiChatFeature.State(
                sessionID: existingSetup.sessionID,
                sessionStatus: .active,
                currentContext: existingSetup.currentContext,
                transcriptHistory: [
                    AiChatMessage(role: .user, content: "Previous question"),
                    AiChatMessage(role: .assistant, content: "Previous answer"),
                ],
                draftText: "draft in progress",
                catalogRows: existingSetup.catalogRows,
                selectedModelHandle: existingSetup.selectedModelHandle,
                selectedThinking: .effort(.high),
                executionPhase: .completed(makeRequestLock(
                    sessionID: existingSetup.sessionID ?? makeSessionID("00000000-0000-0000-0000-000000000031"),
                    selectedRow: existingSetup.catalogRows[0],
                    promptSummary: "Previous question",
                )),
            ),
        )
        initialState.aiChat.modelListState = .loaded(existingSetup.catalogRows)

        let store = TestStore(initialState: initialState) {
            FileManagerInspectorFeature()
        }

        await store.send(.openChat(replacementSetup, .empty())) {
            $0.inspectorVisible = true
            $0.activeMode = .chat
        }

        XCTAssertEqual(store.state.aiChat.sessionID, existingSetup.sessionID)
        XCTAssertEqual(store.state.aiChat.currentContext.summary, "Documents · previous context")
        XCTAssertEqual(store.state.aiChat.transcriptHistory, initialState.aiChat.transcriptHistory)
        XCTAssertEqual(store.state.aiChat.draftText, "draft in progress")
        XCTAssertEqual(store.state.aiChat.selectedModelHandle, existingSetup.selectedModelHandle)
        XCTAssertEqual(store.state.aiChat.selectedThinking, .effort(.high))
    }

    func testAiChatOpenSettingsDelegateRoutesToInspectorDelegate() async {
        let store = TestStore(initialState: FileManagerInspectorFeature.State()) {
            FileManagerInspectorFeature()
        }

        await store.send(.aiChat(.delegate(.openAISettings)))
        await store.receive(.delegate(.openAISettings))
    }

    func testOpenChatWhileProcessingPreservesInFlightState() async {
        let existingSetup = makeSetup(
            sessionID: makeSessionID("00000000-0000-0000-0000-000000000010"),
            summary: "Documents · 1 selected",
        )
        let processingFixture = makeProcessingState(existingSetup: existingSetup)
        let replacementSetup = makeSetup(
            sessionID: makeSessionID("00000000-0000-0000-0000-000000000020"),
            summary: "Desktop · 3 selected",
        )

        let store = TestStore(initialState: processingFixture.state) {
            FileManagerInspectorFeature()
        }

        await store.send(.openChat(replacementSetup, .empty())) {
            $0.inspectorVisible = true
            $0.activeMode = .chat
        }

        XCTAssertEqual(store.state.aiChat.sessionID, existingSetup.sessionID)
        XCTAssertEqual(store.state.aiChat.currentContext.summary, "Documents · 1 selected")
        XCTAssertEqual(store.state.aiChat.transcriptHistory, [
            AiChatMessage(role: .user, content: "Hello"),
            AiChatMessage(role: .assistant, content: "Hi"),
        ])
        XCTAssertEqual(store.state.aiChat.executionPhase, .processing(processingFixture.inFlightLock))
    }

    private func makeProcessingState(
        existingSetup: AiChatSetupState,
    ) -> (state: FileManagerInspectorFeature.State, inFlightLock: AiChatRequestLock) {
        guard let existingSessionID = existingSetup.sessionID else {
            XCTFail("Missing sessionID in setup fixture")
            return (.init(), makeRequestLock(
                sessionID: makeSessionID("00000000-0000-0000-0000-000000000000"),
                selectedRow: makeCatalogRows()[0],
                promptSummary: "Fallback request",
            ))
        }
        let inFlightLock = makeRequestLock(
            sessionID: existingSessionID,
            selectedRow: existingSetup.catalogRows[0],
            promptSummary: "Existing request",
        )

        return (FileManagerInspectorFeature.State(
            inspectorVisible: false,
            inspectorPaneExists: false,
            activeMode: .chat,
            aiChat: AiChatFeature.State(
                sessionID: existingSetup.sessionID,
                sessionStatus: .active,
                currentContext: existingSetup.currentContext,
                transcriptHistory: [
                    AiChatMessage(role: .user, content: "Hello"),
                    AiChatMessage(role: .assistant, content: "Hi"),
                ],
                draftText: "",
                catalogRows: existingSetup.catalogRows,
                selectedModelHandle: existingSetup.selectedModelHandle,
                lockedModelHandle: existingSetup.lockedModelHandle,
                lastExecutionFailure: nil,
                executionPhase: .processing(inFlightLock),
            ),
        ), inFlightLock)
    }

    private func makeSetup(sessionID: AiChatSessionID, summary: String) -> AiChatSetupState {
        let catalogRows = makeCatalogRows()
        return AiChatSetupState(
            sessionID: sessionID,
            sessionStatus: .idle,
            currentContext: AiChatCurrentContextSnapshot(summary: summary),
            transcriptHistory: [],
            draftText: "",
            catalogRows: catalogRows,
            selectedModelHandle: catalogRows[0].handle,
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
        )
    }

    private func makeCatalogRows() -> [AiModelCatalogRow] {
        [
            AiModelCatalogRow(
                handle: AiModelHandle(provider: .openai, rawValue: "gpt-4.1-mini"),
                displayName: "GPT-4.1 Mini",
                authMethod: .apiKey,
                subtitle: nil,
                sortOrder: 10,
                isDefault: true,
                isRecommended: true,
            ),
        ]
    }

    private func makeRequestLock(
        sessionID: AiChatSessionID,
        selectedRow: AiModelCatalogRow,
        promptSummary: String,
    ) -> AiChatRequestLock {
        let requestID = AiChatRequestID(rawValue: makeUUID("10000000-0000-0000-0000-000000000001"))
        let runID = AiChatRunID(rawValue: makeUUID("20000000-0000-0000-0000-000000000001"))
        let context = AiChatRequestContextSnapshot(
            sessionID: sessionID,
            requestID: requestID,
            runID: runID,
            provider: selectedRow.handle.provider,
            model: selectedRow.handle,
            selectedModelRow: selectedRow,
            sessionStatus: .active,
            currentContext: AiChatCurrentContextSnapshot(summary: "Documents · 1 selected"),
            promptSummary: promptSummary,
            submittedAtMs: nil,
        )
        let request = AiChatRequest(
            context: context,
            messages: [AiChatMessage(role: .user, content: promptSummary)],
        )

        return AiChatRequestLock(
            kind: .submit,
            requestID: requestID,
            runID: runID,
            context: context,
            request: request,
            selectedModelHandle: selectedRow.handle,
            selectedModelRow: selectedRow,
            assistantReplacementIndex: nil,
        )
    }

    private func makeSessionID(_ rawValue: String) -> AiChatSessionID {
        AiChatSessionID(rawValue: makeUUID(rawValue))
    }

    private func makeUUID(_ rawValue: String) -> UUID {
        guard let uuid = UUID(uuidString: rawValue) else {
            XCTFail("Invalid UUID fixture: \(rawValue)")
            return UUID()
        }
        return uuid
    }
}
