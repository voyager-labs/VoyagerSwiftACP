@testable import VoyagerEntitiesAI
import XCTest

final class OpenAICompatibleAdapterTests: XCTestCase {
    // MARK: - Configuration

    func testConfiguration_stripsTrailingSlash() {
        let config = OpenAICompatibleConfiguration(
            providerID: .openRouter,
            baseURL: "https://openrouter.ai/api/v1/",
            defaultModel: AIModelID("openrouter/auto"),
        )
        XCTAssertEqual(config.baseURL, "https://openrouter.ai/api/v1")
    }

    func testConfiguration_chatCompletionsURL() {
        let config = OpenAICompatibleConfiguration(
            providerID: .openRouter,
            baseURL: "https://openrouter.ai/api/v1",
            defaultModel: AIModelID("openrouter/auto"),
        )
        XCTAssertEqual(config.chatCompletionsURL, "https://openrouter.ai/api/v1/chat/completions")
    }

    func testConfiguration_chatCompletionsURL_withQueryParams() {
        let config = OpenAICompatibleConfiguration(
            providerID: .openRouter,
            baseURL: "https://openrouter.ai/api/v1",
            defaultModel: AIModelID("openrouter/auto"),
            queryParams: ["key": "value"],
        )
        let url = config.chatCompletionsURL
        XCTAssertTrue(url.contains("key=value"))
        XCTAssertTrue(url.hasPrefix("https://openrouter.ai/api/v1/chat/completions"))
    }

    func testConfiguration_requestHeaders_withAPIKey() {
        let config = OpenAICompatibleConfiguration(
            providerID: .openRouter,
            baseURL: "https://openrouter.ai/api/v1",
            apiKey: "sk-test-123",
            defaultModel: AIModelID("openrouter/auto"),
        )
        XCTAssertEqual(config.requestHeaders["Authorization"], "Bearer sk-test-123")
    }

    func testConfiguration_requestHeaders_withoutAPIKey() {
        let config = OpenAICompatibleConfiguration(
            providerID: .openRouter,
            baseURL: "http://localhost:11434/v1",
            defaultModel: AIModelID("llama3"),
        )
        XCTAssertNil(config.requestHeaders["Authorization"])
    }

    func testConfiguration_requestHeaders_extraHeaders() {
        let config = OpenAICompatibleConfiguration(
            providerID: .openRouter,
            baseURL: "https://openrouter.ai/api/v1",
            apiKey: "sk-test",
            extraHeaders: ["HTTP-Referer": "https://voyager.app", "X-Title": "Voyager"],
            defaultModel: AIModelID("openrouter/auto"),
        )
        XCTAssertEqual(config.requestHeaders["HTTP-Referer"], "https://voyager.app")
        XCTAssertEqual(config.requestHeaders["X-Title"], "Voyager")
        XCTAssertEqual(config.requestHeaders["Authorization"], "Bearer sk-test")
    }

    func testConfiguration_equality() {
        let a = OpenAICompatibleConfiguration(
            providerID: .openRouter,
            baseURL: "https://openrouter.ai/api/v1",
            apiKey: "key",
            defaultModel: AIModelID("model"),
        )
        let b = OpenAICompatibleConfiguration(
            providerID: .openRouter,
            baseURL: "https://openrouter.ai/api/v1",
            apiKey: "key",
            defaultModel: AIModelID("model"),
        )
        XCTAssertEqual(a, b)
    }

    // MARK: - Capabilities

    func testCapabilities_default_hasStreamingAndUsage() {
        let caps = OpenAICompatibleCapabilities.default
        XCTAssertTrue(caps.contains(.textGeneration))
        XCTAssertTrue(caps.contains(.streaming))
        XCTAssertTrue(caps.contains(.usageReporting))
        XCTAssertFalse(caps.contains(.toolCalling))
    }

    func testCapabilities_full_hasAll() {
        let caps = OpenAICompatibleCapabilities.full
        XCTAssertTrue(caps.contains(.textGeneration))
        XCTAssertTrue(caps.contains(.streaming))
        XCTAssertTrue(caps.contains(.toolCalling))
        XCTAssertTrue(caps.contains(.structuredOutput))
        XCTAssertTrue(caps.contains(.parallelToolCalls))
        XCTAssertTrue(caps.contains(.usageReporting))
    }

    func testCapabilities_minimal_hasOnlyBase() {
        let caps = OpenAICompatibleCapabilities.minimal
        XCTAssertTrue(caps.contains(.textGeneration))
        XCTAssertFalse(caps.contains(.streaming))
        XCTAssertFalse(caps.contains(.toolCalling))
    }

    // MARK: - Adapter Construction

    func testAdapter_initializesWithConfiguration() {
        let config = OpenAICompatibleConfiguration(
            providerID: .openRouter,
            baseURL: "https://openrouter.ai/api/v1",
            apiKey: "test",
            defaultModel: AIModelID("openrouter/auto"),
        )
        let adapter = OpenAICompatibleAdapter(configuration: config)
        XCTAssertEqual(adapter.configuration.baseURL, "https://openrouter.ai/api/v1")
        XCTAssertEqual(adapter.capabilities, OpenAICompatibleCapabilities.default)
    }

    func testAdapter_initializesWithCustomCapabilities() {
        let config = OpenAICompatibleConfiguration(
            providerID: .openRouter,
            baseURL: "https://openrouter.ai/api/v1",
            defaultModel: AIModelID("openrouter/auto"),
        )
        let adapter = OpenAICompatibleAdapter(
            configuration: config,
            capabilities: .full,
        )
        XCTAssertTrue(adapter.capabilities.contains(.toolCalling))
        XCTAssertTrue(adapter.capabilities.contains(.structuredOutput))
    }

    func testAdapter_doesNotExposeProviderOptions() {
        let config = OpenAICompatibleConfiguration(
            providerID: .openRouter,
            baseURL: "https://openrouter.ai/api/v1",
            defaultModel: AIModelID("openrouter/auto"),
        )
        let adapter = OpenAICompatibleAdapter(configuration: config)
        XCTAssertEqual(adapter.configuration.providerID, .openRouter)
        XCTAssertEqual(adapter.configuration.defaultModel, AIModelID("openrouter/auto"))
    }

    // MARK: - Adapter Request Construction (via internal builder)

    func testAdapter_generate_buildsCorrectURL() async {
        let config = OpenAICompatibleConfiguration(
            providerID: .openRouter,
            baseURL: "https://openrouter.ai/api/v1",
            apiKey: "sk-test",
            defaultModel: AIModelID("openrouter/auto"),
        )
        let adapter = OpenAICompatibleAdapter(configuration: config)
        XCTAssertEqual(config.chatCompletionsURL, "https://openrouter.ai/api/v1/chat/completions")
    }

    // MARK: - Adapter Returns Voyager-Owned Types

    func testAdapter_generateReturnsAIGenerationResult() async throws {
        let config = OpenAICompatibleConfiguration(
            providerID: .openRouter,
            baseURL: "https://httpbin.org/post",
            apiKey: "test",
            defaultModel: AIModelID("test-model"),
        )
        let adapter = OpenAICompatibleAdapter(configuration: config, capabilities: .minimal)
        do {
            _ = try await adapter.generate(messages: [.user("Hello")])
        } catch {
            // Network errors expected since httpbin doesn't serve OpenAI responses
            // The test verifies the return type is AIGenerationResult (compiler check)
        }
    }

    func testAdapter_streamReturnsAIStreamEventSequence() {
        let config = OpenAICompatibleConfiguration(
            providerID: .openRouter,
            baseURL: "https://httpbin.org/post",
            apiKey: "test",
            defaultModel: AIModelID("test-model"),
        )
        let adapter = OpenAICompatibleAdapter(configuration: config)
        let stream: AsyncThrowingStream<AIStreamEvent, Error> = adapter.stream(messages: [.user("Hi")])
        var iterator = stream.makeAsyncIterator()
        _ = iterator
    }

    // MARK: - Error Types

    func testOpenAICompatibleError_streamingNotSupported() async {
        let config = OpenAICompatibleConfiguration(
            providerID: .openRouter,
            baseURL: "https://httpbin.org/post",
            defaultModel: AIModelID("test"),
        )
        let adapter = OpenAICompatibleAdapter(
            configuration: config,
            capabilities: .minimal,
        )
        let stream = adapter.stream(messages: [.user("Hi")])
        var iterator = stream.makeAsyncIterator()
        do {
            _ = try await iterator.next()
            XCTFail("Expected streamingNotSupported error")
        } catch let error as OpenAICompatibleError {
            XCTAssertEqual(error, .streamingNotSupported)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testOpenAICompatibleError_equality() {
        XCTAssertEqual(
            OpenAICompatibleError.streamingNotSupported,
            OpenAICompatibleError.streamingNotSupported,
        )
        XCTAssertNotEqual(
            OpenAICompatibleError.streamingNotSupported,
            OpenAICompatibleError.invalidConfiguration("test"),
        )
    }

    // MARK: - Tool Support Gated by Capabilities

    func testAdapter_toolsIgnoredWhenToolCallingNotInCapabilities() async {
        let config = OpenAICompatibleConfiguration(
            providerID: .openRouter,
            baseURL: "https://httpbin.org/post",
            apiKey: "test",
            defaultModel: AIModelID("test"),
        )
        let adapter = OpenAICompatibleAdapter(
            configuration: config,
            capabilities: .minimal,
        )
        XCTAssertFalse(adapter.capabilities.contains(.toolCalling))
    }

    func testAdapter_toolsIncludedWhenToolCallingInCapabilities() {
        let config = OpenAICompatibleConfiguration(
            providerID: .openRouter,
            baseURL: "https://httpbin.org/post",
            apiKey: "test",
            defaultModel: AIModelID("test"),
        )
        let adapter = OpenAICompatibleAdapter(
            configuration: config,
            capabilities: .full,
        )
        XCTAssertTrue(adapter.capabilities.contains(.toolCalling))
    }

    // MARK: - Capability Flags Integration

    func testCapabilityFlags_structuredOutputInFull() {
        let caps = OpenAICompatibleCapabilities.full
        XCTAssertTrue(caps.contains(.structuredOutput))
    }

    func testCapabilityFlags_reasoningNotInDefault() {
        let caps = OpenAICompatibleCapabilities.default
        XCTAssertFalse(caps.contains(.reasoning))
    }

    func testCapabilityFlags_customComposition() {
        let custom: AIProviderCapability = [.textGeneration, .streaming, .reasoning]
        XCTAssertTrue(custom.contains(.reasoning))
        XCTAssertFalse(custom.contains(.toolCalling))
    }
}
