// Portions adapted from Conduit (MIT License).
// Original: Sources/Conduit/Providers/OpenAI/OpenAIProvider.swift, OpenAIProvider+Streaming.swift
// Commit: bd57239663e63c3ad28647a73ae761a7aa46e123

import Foundation

/// Adapter for the direct OpenAI chat completions API (api.openai.com).
///
/// Provides text generation, streaming, and tool calling against the official
/// OpenAI API. Returns only Voyager-owned types (``AIGenerationResult``,
/// ``AIStreamEvent``).
///
/// Delegates HTTP transport to ``AIHTTPClient``, request construction to
/// ``AIRequestBuilder``, response parsing to ``AIResponseNormalizer``, and
/// streaming to ``SSEStreamReader`` + ``ServerSentEventParser``.
///
/// ## Scope
/// This adapter covers **only** the chat completions route (`/chat/completions`).
/// It does **not** include embeddings, images, speech, transcription, or the
/// responses API surface.
///
/// ## Usage
/// ```swift
/// let config = OpenAIConfiguration(apiKey: "sk-...", defaultModel: AIModelID("gpt-4o"))
/// let adapter = OpenAIAdapter(configuration: config)
/// let result = try await adapter.generate(messages: [.user("Hello")])
/// ```
public struct OpenAIAdapter: Sendable {
    public let configuration: OpenAIConfiguration
    public let capabilities: AIProviderCapability
    public let httpClient: AIHTTPClient

    public init(
        configuration: OpenAIConfiguration,
        capabilities: AIProviderCapability = OpenAICapabilities.standard,
        httpClient: AIHTTPClient = AIHTTPClient(),
    ) {
        self.configuration = configuration
        self.capabilities = capabilities
        self.httpClient = httpClient
    }

    // MARK: - Generate (non-streaming)

    public func generate(
        messages: [AIMessage],
        model: AIModelID? = nil,
        tools: [AIToolDefinition] = [],
        temperature: Double? = nil,
        maxTokens: Int? = nil,
    ) async throws -> AIGenerationResult {
        let resolvedModel = model ?? configuration.defaultModel
        let request = try AIRequestBuilder.shared.buildChatRequest(
            url: configuration.chatCompletionsURL,
            apiKey: configuration.apiKey,
            model: resolvedModel.rawValue,
            messages: messages,
            tools: capabilities.contains(.toolCalling) ? tools : [],
            temperature: temperature,
            maxTokens: maxTokens,
            stream: false,
        )

        let mergedHeaders = request.headers.merging(configuration.requestHeaders) { _, config in config }
        let data = try await httpClient.post(
            url: request.url,
            headers: mergedHeaders,
            body: request.body,
        )

        return try AIResponseNormalizer.normalizeOpenAI(data: data, modelID: resolvedModel)
    }

    // MARK: - Stream

    public func stream(
        messages: [AIMessage],
        model: AIModelID? = nil,
        tools: [AIToolDefinition] = [],
        temperature: Double? = nil,
        maxTokens: Int? = nil,
    ) -> AsyncThrowingStream<AIStreamEvent, Error> {
        let config = configuration
        let caps = capabilities
        let client = httpClient
        let resolvedModel = model ?? config.defaultModel

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard caps.contains(.streaming) else {
                        continuation.finish(throwing: OpenAIAdapterError.streamingNotSupported)
                        return
                    }

                    let request = try AIRequestBuilder.shared.buildChatRequest(
                        url: config.chatCompletionsURL,
                        apiKey: config.apiKey,
                        model: resolvedModel.rawValue,
                        messages: messages,
                        tools: caps.contains(.toolCalling) ? tools : [],
                        temperature: temperature,
                        maxTokens: maxTokens,
                        stream: true,
                    )

                    let mergedHeaders = request.headers.merging(config.requestHeaders) { _, cfg in cfg }
                    let bytes = try await client.stream(
                        url: request.url,
                        headers: mergedHeaders,
                        body: request.body,
                    )

                    var toolCallAccumulators: [Int: ToolCallAccumulator] = [:]

                    let sseReader = SSEStreamReader(bytes: bytes)
                    for try await sseEvent in sseReader {
                        guard !Task.isCancelled else { break }

                        if let event = AIResponseNormalizer.parseOpenAISSELine("data: \(sseEvent.data)") {
                            let processedEvent = accumulateToolCall(event, accumulators: &toolCallAccumulators)
                            if let processedEvent {
                                continuation.yield(processedEvent)
                            }
                        }

                        if sseEvent.data == "[DONE]" {
                            flushToolCallAccumulators(toolCallAccumulators, into: continuation)
                            let finishEvent = AIStreamEvent.finish(.stop, AIUsage.zero)
                            continuation.yield(finishEvent)
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    // MARK: - Tool Call Accumulation

    private struct ToolCallAccumulator {
        var id: String
        var name: String?
        var arguments: String
    }

    private func accumulateToolCall(
        _ event: AIStreamEvent,
        accumulators: inout [Int: ToolCallAccumulator],
    ) -> AIStreamEvent? {
        switch event {
        case let .toolCallDelta(id, name, argumentsDelta):
            let index = id.isEmpty ? accumulators.count : id.hashValue
            let acc = accumulators[index] ?? ToolCallAccumulator(
                id: id, name: name, arguments: "",
            )
            accumulators[index] = ToolCallAccumulator(
                id: acc.id.isEmpty ? id : acc.id,
                name: name ?? acc.name,
                arguments: acc.arguments + argumentsDelta,
            )
            return .toolCallDelta(id: id, name: name, argumentsDelta: argumentsDelta)
        default:
            return event
        }
    }

    private func flushToolCallAccumulators(
        _ accumulators: [Int: ToolCallAccumulator],
        into continuation: AsyncThrowingStream<AIStreamEvent, Error>.Continuation,
    ) {
        for (_, acc) in accumulators {
            let toolCall = AIToolCall(
                id: acc.id,
                name: acc.name ?? "",
                arguments: acc.arguments,
            )
            continuation.yield(.toolCallComplete(toolCall))
        }
    }
}

/// Errors specific to the OpenAI adapter.
public enum OpenAIAdapterError: Error, Sendable, Equatable {
    case streamingNotSupported
    case invalidConfiguration(String)
}
