// Portions adapted from Swift AI SDK (Apache-2.0).
// Original: Sources/OpenAICompatibleProvider/OpenAICompatibleProvider.swift
// Commit: 88225c3fa3544e30fe361ca4aa03c4a60c7444ec

import Foundation

/// Adapter for any OpenAI-compatible chat completions API.
///
/// Targets custom base URLs with injected headers, returning only
/// Voyager-owned result/event types (``AIGenerationResult``, ``AIStreamEvent``).
///
/// Delegates HTTP transport to ``AIHTTPClient``, request construction to
/// ``AIRequestBuilder``, response parsing to ``AIResponseNormalizer``, and
/// streaming to ``SSEStreamReader`` + ``ServerSentEventParser``.
public struct OpenAICompatibleAdapter: Sendable {
    public let configuration: OpenAICompatibleConfiguration
    public let capabilities: AIProviderCapability
    public let httpClient: AIHTTPClient

    public init(
        configuration: OpenAICompatibleConfiguration,
        capabilities: AIProviderCapability = OpenAICompatibleCapabilities.default,
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
            apiKey: configuration.apiKey ?? "",
            model: resolvedModel.rawValue,
            messages: messages,
            tools: capabilities.contains(.toolCalling) ? tools : [],
            temperature: temperature,
            maxTokens: maxTokens,
            stream: false,
        )

        let mergedHeaders = request.headers.merging(configuration.extraHeaders) { _, extra in extra }
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
                        continuation.finish(throwing: OpenAICompatibleError.streamingNotSupported)
                        return
                    }

                    let request = try AIRequestBuilder.shared.buildChatRequest(
                        url: config.chatCompletionsURL,
                        apiKey: config.apiKey ?? "",
                        model: resolvedModel.rawValue,
                        messages: messages,
                        tools: caps.contains(.toolCalling) ? tools : [],
                        temperature: temperature,
                        maxTokens: maxTokens,
                        stream: true,
                    )

                    let mergedHeaders = request.headers.merging(config.extraHeaders) { _, extra in extra }
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

/// Errors specific to OpenAI-compatible adapter operations.
public enum OpenAICompatibleError: Error, Sendable, Equatable {
    case streamingNotSupported
    case invalidConfiguration(String)
}
