import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi
@testable import VoyagerFeaturesAiChat
import XCTest

@MainActor
final class AiChatFeatureSessionNavigationTests: XCTestCase {
    func testInitialModeDefaultsToSessions() {
        let store = TestStore(initialState: AiChatFeature.State()) {
            AiChatFeature()
        }

        XCTAssertEqual(store.state.mode, AiChatMode.sessions)
        XCTAssertEqual(store.state.sessionList, .init())
    }

    func testBackToSessionsPreservesActiveChatData() async {
        let sessionID = AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111111111"))
        let selectedSessionID = AiChatSessionID(rawValue: makeUUID("22222222-2222-2222-2222-222222222222"))
        let attachmentPath = "/tmp/Screenshot.png"
        let attachment = AiChatAttachmentDraft(
            id: AiChatAttachmentID(rawValue: attachmentPath),
            source: .file,
            displayTitle: "Screenshot.png",
            sourceLocation: AiChatAttachmentSourceLocation(
                fileURL: URL(fileURLWithPath: attachmentPath),
                filePath: attachmentPath
            )
        )
        let transcript = [
            AiChatMessage(role: .user, content: "Hello"),
            AiChatMessage(role: .assistant, content: "Hi there")
        ]

        let store = TestStore(initialState: AiChatFeature.State(
            mode: .chat,
            sessionList: .init(
                rows: [makeSessionSummary(sessionID: selectedSessionID)],
                query: "release",
                isLoading: false,
                errorMessage: nil,
                selectedSessionID: selectedSessionID
            ),
            sessionID: sessionID,
            sessionStatus: .active,
            currentContext: makeContextSnapshot(),
            addedAttachments: [attachment],
            transcriptHistory: transcript,
            draftText: "Draft reply"
        )) {
            AiChatFeature()
        }

        await store.send(.backToSessionsTapped) { state in
            state.mode = .sessions
        }

        XCTAssertEqual(store.state.sessionID, sessionID)
        XCTAssertEqual(store.state.sessionStatus, AiChatSessionStatus.active)
        XCTAssertEqual(store.state.transcriptHistory, transcript)
        XCTAssertEqual(store.state.draftText, "Draft reply")
        XCTAssertEqual(store.state.addedAttachments, [attachment])
        XCTAssertEqual(store.state.sessionList.selectedSessionID, selectedSessionID)
    }
}

private func makeSessionSummary(
    sessionID: AiChatSessionID,
    title: String = "Release notes follow-up",
    preview: String? = "Need the latest diff summary.",
    messageCount: Int = 2,
    contextTitle: String? = "Release docs",
    provider: AiProvider = .openai,
    model: AiModelHandle = AiModelHandle(provider: .openai, rawValue: "gpt-4.1-mini"),
    createdAtMs: Int64 = 1_000,
    updatedAtMs: Int64 = 2_000,
    status: AiChatSessionStatus = .active
) -> AiChatSessionSummary {
    AiChatSessionSummary(
        sessionID: sessionID,
        title: title,
        preview: preview,
        messageCount: messageCount,
        contextTitle: contextTitle,
        provider: provider,
        model: model,
        createdAtMs: createdAtMs,
        updatedAtMs: updatedAtMs,
        status: status
    )
}
