import Foundation
@testable import VoyagerEntitiesAI
import XCTest

final class AIProviderIDTests: XCTestCase {
    func testWellKnownProviderIDs_haveExpectedRawValues() {
        XCTAssertEqual(AIProviderID.openai.rawValue, "openai")
        XCTAssertEqual(AIProviderID.anthropic.rawValue, "anthropic")
        XCTAssertEqual(AIProviderID.openRouter.rawValue, "openRouter")
        XCTAssertEqual(AIProviderID.chatgptCodex.rawValue, "chatgptCodex")
    }

    func testCustomProviderID() {
        let custom = AIProviderID("custom-provider")
        XCTAssertEqual(custom.rawValue, "custom-provider")
    }

    func testEquality() {
        XCTAssertEqual(AIProviderID.openai, AIProviderID(rawValue: "openai"))
        XCTAssertNotEqual(AIProviderID.openai, AIProviderID.anthropic)
    }

    func testCodableRoundTrip() throws {
        let id = AIProviderID.openai
        let data = try JSONEncoder().encode(id)
        let decoded = try JSONDecoder().decode(AIProviderID.self, from: data)
        XCTAssertEqual(decoded, id)
    }

    func testDescription() {
        XCTAssertEqual(AIProviderID.anthropic.description, "anthropic")
    }

    func testHashable() {
        let set: Set<AIProviderID> = [.openai, .openai, .anthropic]
        XCTAssertEqual(set.count, 2)
    }
}

final class AIModelIDTests: XCTestCase {
    func testModelID_rawValue() {
        let id = AIModelID("gpt-4o")
        XCTAssertEqual(id.rawValue, "gpt-4o")
        XCTAssertEqual(id.description, "gpt-4o")
    }

    func testModelID_codableRoundTrip() throws {
        let id = AIModelID("claude-sonnet-4-20250514")
        let data = try JSONEncoder().encode(id)
        let decoded = try JSONDecoder().decode(AIModelID.self, from: data)
        XCTAssertEqual(decoded, id)
    }

    func testModelID_equality() {
        XCTAssertEqual(AIModelID("gpt-4o"), AIModelID(rawValue: "gpt-4o"))
        XCTAssertNotEqual(AIModelID("gpt-4o"), AIModelID("gpt-4o-mini"))
    }
}

final class AIFinishReasonTests: XCTestCase {
    func testAllFinishReasonsAreCaseIterable() {
        XCTAssertEqual(AIFinishReason.allCases.count, 7)
    }

    func testIsToolCallRequest() {
        XCTAssertTrue(AIFinishReason.toolCall.isToolCallRequest)
        XCTAssertFalse(AIFinishReason.stop.isToolCallRequest)
        XCTAssertFalse(AIFinishReason.length.isToolCallRequest)
    }

    func testIsSuccessful() {
        XCTAssertTrue(AIFinishReason.stop.isSuccessful)
        XCTAssertTrue(AIFinishReason.toolCall.isSuccessful)
        XCTAssertTrue(AIFinishReason.length.isSuccessful)
        XCTAssertFalse(AIFinishReason.error.isSuccessful)
        XCTAssertFalse(AIFinishReason.cancelled.isSuccessful)
    }

    func testFinishReason_coversAllProviders() {
        let reasons = Set(AIFinishReason.allCases)
        XCTAssertTrue(reasons.contains(.stop))
        XCTAssertTrue(reasons.contains(.toolCall))
        XCTAssertTrue(reasons.contains(.length))
        XCTAssertTrue(reasons.contains(.contentFilter))
        XCTAssertTrue(reasons.contains(.cancelled))
        XCTAssertTrue(reasons.contains(.error))
        XCTAssertTrue(reasons.contains(.other))
    }

    func testCodableRoundTrip() throws {
        for reason in AIFinishReason.allCases {
            let data = try JSONEncoder().encode(reason)
            let decoded = try JSONDecoder().decode(AIFinishReason.self, from: data)
            XCTAssertEqual(decoded, reason)
        }
    }
}

final class AIUsageTests: XCTestCase {
    func testTotalTokens() {
        let usage = AIUsage(promptTokens: 10, completionTokens: 20)
        XCTAssertEqual(usage.totalTokens, 30)
    }

    func testZero() {
        XCTAssertEqual(AIUsage.zero.totalTokens, 0)
        XCTAssertEqual(AIUsage.zero.promptTokens, 0)
        XCTAssertEqual(AIUsage.zero.completionTokens, 0)
    }

    func testCodableRoundTrip() throws {
        let usage = AIUsage(promptTokens: 100, completionTokens: 50)
        let data = try JSONEncoder().encode(usage)
        let decoded = try JSONDecoder().decode(AIUsage.self, from: data)
        XCTAssertEqual(decoded, usage)
        XCTAssertEqual(decoded.totalTokens, 150)
    }
}

final class AIToolCallTests: XCTestCase {
    func testToolCall_properties() {
        let call = AIToolCall(id: "call_123", name: "get_weather", arguments: """
        {"city": "Seoul"}
        """)
        XCTAssertEqual(call.id, "call_123")
        XCTAssertEqual(call.name, "get_weather")
        XCTAssertEqual(call.description, "AIToolCall(call_123, get_weather)")
    }

    func testToolCall_codableRoundTrip() throws {
        let call = AIToolCall(id: "call_abc", name: "search", arguments: "{\"q\": \"test\"}")
        let data = try JSONEncoder().encode(call)
        let decoded = try JSONDecoder().decode(AIToolCall.self, from: data)
        XCTAssertEqual(decoded, call)
    }

    func testToolCall_hashable() {
        let call1 = AIToolCall(id: "call_1", name: "fn", arguments: "{}")
        let call2 = AIToolCall(id: "call_2", name: "fn", arguments: "{}")
        let set: Set<AIToolCall> = [call1, call2, call1]
        XCTAssertEqual(set.count, 2)
    }
}

final class AIContentPartTests: XCTestCase {
    func testTextPart_textValue() {
        let part = AIContentPart.text("Hello")
        XCTAssertEqual(part.textValue, "Hello")
    }

    func testToolCallPart_textValue_isNil() {
        let call = AIToolCall(id: "c1", name: "fn", arguments: "{}")
        let part = AIContentPart.toolCall(call)
        XCTAssertNil(part.textValue)
    }

    func testTextPart_codableRoundTrip() throws {
        let part = AIContentPart.text("Hello world")
        let data = try JSONEncoder().encode(part)
        let decoded = try JSONDecoder().decode(AIContentPart.self, from: data)
        XCTAssertEqual(decoded, part)
    }

    func testToolCallPart_codableRoundTrip() throws {
        let call = AIToolCall(id: "c1", name: "search", arguments: "{\"q\":\"test\"}")
        let part = AIContentPart.toolCall(call)
        let data = try JSONEncoder().encode(part)
        let decoded = try JSONDecoder().decode(AIContentPart.self, from: data)
        XCTAssertEqual(decoded, part)
    }

    func testToolResultPart_codableRoundTrip() throws {
        let result = AIToolResult(id: "c1", content: "result text")
        let part = AIContentPart.toolResult(result)
        let data = try JSONEncoder().encode(part)
        let decoded = try JSONDecoder().decode(AIContentPart.self, from: data)
        XCTAssertEqual(decoded, part)
    }

    func testImagePart_codableRoundTrip() throws {
        let image = AIImageContent(base64Data: "AAAA", mimeType: "image/png")
        let part = AIContentPart.image(image)
        let data = try JSONEncoder().encode(part)
        let decoded = try JSONDecoder().decode(AIContentPart.self, from: data)
        XCTAssertEqual(decoded, part)
    }
}

final class AIMessageTests: XCTestCase {
    func testFactoryMethods() {
        let system = AIMessage.system("You are helpful")
        XCTAssertEqual(system.role, .system)
        XCTAssertEqual(system.content.textValue, "You are helpful")

        let user = AIMessage.user("Hello")
        XCTAssertEqual(user.role, .user)
        XCTAssertEqual(user.content.textValue, "Hello")

        let assistant = AIMessage.assistant("Hi there")
        XCTAssertEqual(assistant.role, .assistant)
        XCTAssertEqual(assistant.content.textValue, "Hi there")
    }

    func testAssistantWithParts() {
        let call = AIToolCall(id: "c1", name: "fn", arguments: "{}")
        let msg = AIMessage.assistant(parts: [.text("Thinking..."), .toolCall(call)])
        XCTAssertEqual(msg.role, .assistant)

        if case let .parts(parts) = msg.content {
            XCTAssertEqual(parts.count, 2)
            XCTAssertEqual(parts[0].textValue, "Thinking...")
        } else {
            XCTFail("Expected parts content")
        }
    }

    func testToolResultMessage() {
        let result = AIToolResult(id: "c1", content: "42")
        let msg = AIMessage.toolResult(result)
        XCTAssertEqual(msg.role, .tool)
    }

    func testTextContent_isEmpty() {
        XCTAssertTrue(AIMessage.user("").content.isEmpty)
        XCTAssertFalse(AIMessage.user("Hello").content.isEmpty)
    }

    func testRole_caseIterable() {
        XCTAssertEqual(AIMessage.Role.allCases.count, 4)
    }

    func testMessage_codableRoundTrip_textContent() throws {
        let msg = AIMessage.user("Hello")
        let data = try JSONEncoder().encode(msg)
        let decoded = try JSONDecoder().decode(AIMessage.self, from: data)
        XCTAssertEqual(decoded.role, msg.role)
        XCTAssertEqual(decoded.content.textValue, msg.content.textValue)
    }

    func testMessage_codableRoundTrip_partsContent() throws {
        let call = AIToolCall(id: "c1", name: "fn", arguments: "{}")
        let msg = AIMessage.assistant(parts: [.text("Hi"), .toolCall(call)])
        let data = try JSONEncoder().encode(msg)
        let decoded = try JSONDecoder().decode(AIMessage.self, from: data)
        XCTAssertEqual(decoded.role, .assistant)
        XCTAssertEqual(decoded.content, msg.content)
    }

    func testContent_textExtraction_fromParts() {
        let content = AIMessage.Content.parts([
            .text("Line 1"),
            .toolCall(AIToolCall(id: "c1", name: "fn", arguments: "{}")),
            .text("Line 2"),
        ])
        XCTAssertEqual(content.textValue, "Line 1\nLine 2")
    }
}

final class AIGenerationResultTests: XCTestCase {
    func testTextFactory() {
        let result = AIGenerationResult.text("Hello")
        XCTAssertEqual(result.text, "Hello")
        XCTAssertEqual(result.finishReason, .stop)
        XCTAssertTrue(result.toolCalls.isEmpty)
        XCTAssertFalse(result.hasToolCalls)
    }

    func testWithToolCalls() {
        let call = AIToolCall(id: "c1", name: "fn", arguments: "{}")
        let result = AIGenerationResult(
            text: "",
            finishReason: .toolCall,
            toolCalls: [call],
        )
        XCTAssertTrue(result.hasToolCalls)
        XCTAssertEqual(result.toolCalls.count, 1)
    }

    func testEquality() {
        let a = AIGenerationResult.text("Hello")
        let b = AIGenerationResult.text("Hello")
        XCTAssertEqual(a, b)

        let c = AIGenerationResult.text("World")
        XCTAssertNotEqual(a, c)
    }
}

final class AIStreamEventTests: XCTestCase {
    func testTextDelta_codableRoundTrip() throws {
        let event = AIStreamEvent.textDelta("Hello")
        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(AIStreamEvent.self, from: data)
        XCTAssertEqual(decoded, event)
    }

    func testToolCallDelta_codableRoundTrip() throws {
        let event = AIStreamEvent.toolCallDelta(id: "c1", name: "search", argumentsDelta: "{\"q")
        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(AIStreamEvent.self, from: data)
        XCTAssertEqual(decoded, event)
    }

    func testToolCallComplete_codableRoundTrip() throws {
        let call = AIToolCall(id: "c1", name: "search", arguments: "{\"q\":\"test\"}")
        let event = AIStreamEvent.toolCallComplete(call)
        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(AIStreamEvent.self, from: data)
        XCTAssertEqual(decoded, event)
    }

    func testFinish_codableRoundTrip() throws {
        let event = AIStreamEvent.finish(.stop, AIUsage(promptTokens: 10, completionTokens: 20))
        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(AIStreamEvent.self, from: data)
        XCTAssertEqual(decoded, event)
    }

    func testResponseMetadata_codableRoundTrip() throws {
        let event = AIStreamEvent.responseMetadata(responseID: "resp_123", modelID: AIModelID("gpt-4o"))
        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(AIStreamEvent.self, from: data)
        XCTAssertEqual(decoded, event)
    }

    func testError_codableRoundTrip() throws {
        let event = AIStreamEvent.error("Rate limit exceeded")
        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(AIStreamEvent.self, from: data)
        XCTAssertEqual(decoded, event)
    }

    func testWarning_codableRoundTrip() throws {
        let event = AIStreamEvent.warning("Deprecated model")
        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(AIStreamEvent.self, from: data)
        XCTAssertEqual(decoded, event)
    }

    func testStreamEvents_canRepresentOpenAIStyleDeltas() {
        let events: [AIStreamEvent] = [
            .responseMetadata(responseID: "chatcmpl-abc", modelID: AIModelID("gpt-4o")),
            .textDelta("Hello"),
            .textDelta(" world"),
            .finish(.stop, AIUsage(promptTokens: 5, completionTokens: 3)),
        ]
        XCTAssertEqual(events.count, 4)
    }

    func testStreamEvents_canRepresentAnthropicStyleDeltas() {
        let events: [AIStreamEvent] = [
            .responseMetadata(responseID: "msg_123", modelID: AIModelID("claude-sonnet-4-20250514")),
            .textDelta("I'll search"),
            .toolCallDelta(id: "toolu_1", name: "search", argumentsDelta: "{\"q\":"),
            .toolCallDelta(id: "toolu_1", name: nil, argumentsDelta: "\"test\"}"),
            .toolCallComplete(AIToolCall(id: "toolu_1", name: "search", arguments: "{\"q\":\"test\"}")),
            .finish(.toolCall, AIUsage(promptTokens: 20, completionTokens: 15)),
        ]
        XCTAssertEqual(events.count, 6)
    }

    func testStreamEvents_canRepresentOpenRouterStyleDeltas() {
        let events: [AIStreamEvent] = [
            .textDelta("Via OpenRouter"),
            .finish(.stop, AIUsage(promptTokens: 3, completionTokens: 3)),
        ]
        XCTAssertEqual(events.count, 2)
    }
}

final class AIProviderCapabilityTests: XCTestCase {
    func testBaseCapabilities() {
        XCTAssertTrue(AIProviderCapability.base.contains(.textGeneration))
        XCTAssertTrue(AIProviderCapability.base.contains(.usageReporting))
    }

    func testStreamingCapability() {
        let caps: AIProviderCapability = [.textGeneration, .streaming]
        XCTAssertTrue(caps.contains(.streaming))
        XCTAssertFalse(caps.contains(.toolCalling))
    }

    func testAllCapabilities() {
        XCTAssertTrue(AIProviderCapability.all.contains(.textGeneration))
        XCTAssertTrue(AIProviderCapability.all.contains(.streaming))
        XCTAssertTrue(AIProviderCapability.all.contains(.toolCalling))
        XCTAssertTrue(AIProviderCapability.all.contains(.structuredOutput))
        XCTAssertTrue(AIProviderCapability.all.contains(.multimodalInput))
        XCTAssertTrue(AIProviderCapability.all.contains(.reasoning))
        XCTAssertTrue(AIProviderCapability.all.contains(.parallelToolCalls))
        XCTAssertTrue(AIProviderCapability.all.contains(.usageReporting))
    }

    func testOptionSet_operations() {
        let caps: AIProviderCapability = [.streaming, .toolCalling]
        let extended = caps.union(.structuredOutput)
        XCTAssertTrue(extended.contains(.structuredOutput))

        let removed = caps.subtracting(.streaming)
        XCTAssertFalse(removed.contains(.streaming))
        XCTAssertTrue(removed.contains(.toolCalling))
    }

    func testCodableRoundTrip() throws {
        let caps: AIProviderCapability = [.streaming, .toolCalling, .usageReporting]
        let data = try JSONEncoder().encode(caps)
        let decoded = try JSONDecoder().decode(AIProviderCapability.self, from: data)
        XCTAssertEqual(decoded, caps)
    }
}
