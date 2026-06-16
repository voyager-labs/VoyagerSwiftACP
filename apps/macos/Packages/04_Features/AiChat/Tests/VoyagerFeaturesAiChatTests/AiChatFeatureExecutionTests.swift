import Foundation
import VoyagerEntitiesAi
@testable import VoyagerFeaturesAiChat
import XCTest

// CBW-001 spec-owner suite로 옮기지 않은 provider execution adapter 회귀 테스트만 남긴다.

@MainActor
final class AiChatFeatureExecutionTests: XCTestCase {
    /// live execution adapter가 final 전 raw Anthropic delta를 먼저 방출하는지 검증
    func testLiveExecutionClientEmitsRawAnthropicDeltaBeforeFinal() async {
        let catalogRows = makeCatalogRows()
        let selectedHandle = catalogRows[1].handle
        let requestContext = makeRequestContext(
            sessionID: AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111111121")),
            requestID: AiChatRequestID(rawValue: makeUUID("00000000-0000-0000-0000-000000000122")),
            runID: AiChatRunID(rawValue: makeUUID("00000000-0000-0000-0000-000000000123")),
            model: selectedHandle,
            selectedRow: catalogRows[1],
        )
        let request = AiChatRequest(context: requestContext, messages: [AiChatMessage(role: .user, content: "Hello")])
        let largeDelta = "Anthropic can sometimes deliver a large text delta that would otherwise paint in one frame."
        let providerClient = AiChatProviderExecutionClient(execute: { request, _ in
            AsyncThrowingStream { continuation in
                continuation.yield(.started(context: request.context))
                continuation.yield(.delta(context: request.context, text: largeDelta))
                continuation.yield(.final(response: AiChatResponse(
                    context: request.context,
                    assistantMessage: AiChatMessage(role: .assistant, content: largeDelta),
                    completedAtMs: 0,
                )))
                continuation.finish()
            }
        })
        let client = AiChatExecutionClient.live(providerExecutionClient: providerClient)

        var events: [AiChatEvent] = []
        for await event in client.execute(request, nil) {
            events.append(event)
        }

        let deltaTexts = events.compactMap { event -> String? in
            if case let .delta(_, text) = event { return text }
            return nil
        }
        XCTAssertEqual(deltaTexts, [largeDelta])
        XCTAssertEqual(events.last?.isFinalResponse, true)
    }
}

private extension AiChatEvent {
    var isFinalResponse: Bool {
        if case .final = self { return true }
        return false
    }
}
