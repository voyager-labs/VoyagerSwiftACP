import ComposableArchitecture
import VoyagerEntitiesAi
@testable import VoyagerFeaturesAiChat
import XCTest

@MainActor
final class AiChatFeatureHistoryTruncationTests: XCTestCase {
    func testHistoryTruncationStopsAtOversizedRecentTurnToKeepContiguousContext() async {
        let stream = AiChatExecutionStreamDriver()
        let catalogRows = makeCatalogRows()
        let fixedMs: Int64 = 1_700_000_001_000
        let olderUser = String(repeating: "o", count: 500)
        let olderAssistant = String(repeating: "p", count: 500)
        let oversizedRecentUser = String(repeating: "x", count: 11000)
        let oversizedRecentAssistant = String(repeating: "y", count: 11000)
        let latestUser = String(repeating: "u", count: 1700)
        let latestAssistant = String(repeating: "a", count: 1800)
        let draft = "Current prompt"

        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111111119")),
            sessionStatus: .active,
            currentContext: makeContextSnapshot(),
            transcriptHistory: [
                AiChatMessage(role: .user, content: olderUser),
                AiChatMessage(role: .assistant, content: olderAssistant),
                AiChatMessage(role: .user, content: oversizedRecentUser),
                AiChatMessage(role: .assistant, content: oversizedRecentAssistant),
                AiChatMessage(role: .user, content: latestUser),
                AiChatMessage(role: .assistant, content: latestAssistant),
            ],
            draftText: draft,
            catalogRows: catalogRows,
            selectedModelHandle: catalogRows[0].handle,
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
            executionPhase: .idle,
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(makeFixedDate(milliseconds: fixedMs))
            $0.aiChatExecutionClient = AiChatExecutionClient(execute: { request in
                stream.stream(for: request)
            })
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.submitTapped)
        await resolvePendingRequestContext(store) { state in
            state.draftText = ""
            state.lockedModelHandle = catalogRows[0].handle
        }

        guard let request = stream.requests.first,
              case let .processing(lock) = store.state.executionPhase
        else {
            return XCTFail("Expected frozen request lock")
        }

        XCTAssertEqual(request.messages, [
            AiChatMessage(role: .user, content: latestUser),
            AiChatMessage(role: .assistant, content: latestAssistant),
            AiChatMessage(role: .user, content: draft),
        ])
        XCTAssertFalse(request.messages.contains(AiChatMessage(role: .user, content: olderUser)))
        XCTAssertFalse(request.messages.contains(AiChatMessage(role: .assistant, content: olderAssistant)))
        XCTAssertEqual(lock.historyTruncation.includedMessageCount, 3)
        XCTAssertEqual(lock.historyTruncation.excludedMessageCount, 4)
        XCTAssertEqual(lock.historyTruncation.truncationReason, .characterBudgetExceeded)
    }
}
