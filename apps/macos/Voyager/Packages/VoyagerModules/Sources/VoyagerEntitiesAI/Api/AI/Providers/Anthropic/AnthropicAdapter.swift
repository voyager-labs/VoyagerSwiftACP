// Portions adapted from Conduit (MIT License).
// Original: Sources/Conduit/Providers/Anthropic/AnthropicProvider.swift, AnthropicProvider+Streaming.swift
// Commit: bd57239663e63c3ad28647a73ae761a7aa46e123

import Foundation

/// Adapter for the direct Anthropic Messages API (api.anthropic.com).
///
/// Provides text generation, streaming, and tool calling against the official
/// Anthropic Messages API. Returns only Voyager-owned types
/// (``AIGenerationResult``, ``AIStreamEvent``).
///
/// ## Scope
/// Covers **only** the messages route (`/v1/messages`).
/// Does **not** include citations, server tools, beta-only features,
/// or batch API surfaces.
///
/// ## Usage
/// ```swift
/// let config = AnthropicConfiguration(apiKey: "sk-ant-...", model: AIModelID("claude-sonnet-4-20250514"))
/// let adapter = AnthropicAdapter(configuration: config)
/// let result = try await adapter.generate(messages: [.user("Hello")])
/// ```
public struct AnthropicAdapter: Sendable {
    public let configuration: AnthropicConfiguration
    public let capabilities: AIProviderCapability
    public let httpClient: AIHTTPClient

    public init(
        configuration: AnthropicConfiguration,
        capabilities: AIProviderCapability = AnthropicCapabilities.standard,
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
        let requestBody = buildAnthropicRequestBody(
            messages: messages,
            model: resolvedModel,
            tools: capabilities.contains(.toolCalling) ? tools : [],
            temperature: temperature,
            maxTokens: maxTokens ?? 4096,
            stream: false,
        )

        let data = try await httpClient.post(
            url: configuration.messagesURL,
            headers: configuration.requestHeaders,
            body: requestBody,
        )

        return try AIResponseNormalizer.normalizeAnthropic(data: data, modelID: resolvedModel)
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
                        continuation.finish(throwing: AnthropicAdapterError.streamingNotSupported)
                        return
                    }

                    let requestBody = buildAnthropicRequestBody(
                        messages: messages,
                        model: resolvedModel,
                        tools: caps.contains(.toolCalling) ? tools : [],
                        temperature: temperature,
                        maxTokens: maxTokens ?? 4096,
                        stream: true,
                    )

                    let bytes = try await client.stream(
                        url: config.messagesURL,
                        headers: config.requestHeaders,
                        body: requestBody,
                    )

                    var toolCallAccumulators: [Int: AnthropicToolCallAccumulator] = [:]

                    let sseReader = SSEStreamReader(bytes: bytes)
                    for try await sseEvent in sseReader {
                        guard !Task.isCancelled else { break }

                        if sseEvent.data == "[DONE]" {
                            flushAnthropicToolCalls(toolCallAccumulators, into: continuation)
                            continuation.finish()
                            break
                        }

                        if let event = AIResponseNormalizer.parseAnthropicSSELine("data: \(sseEvent.data)") {
                            let processedEvent = accumulateAnthropicToolCall(
                                event,
                                accumulators: &toolCallAccumulators,
                            )
                            if let processedEvent {
                                if case .finish = processedEvent {
                                    flushAnthropicToolCalls(toolCallAccumulators, into: continuation)
                                }
                                continuation.yield(processedEvent)
                            }
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

    // MARK: - Request Body

    private func buildAnthropicRequestBody(
        messages: [AIMessage],
        model: AIModelID,
        tools: [AIToolDefinition],
        temperature: Double?,
        maxTokens: Int,
        stream: Bool,
    ) -> AnthropicRequestBody {
        let (systemMessages, chatMessages) = splitSystemMessages(messages)

        let anthropicTools: [AnthropicTool]? = tools.isEmpty ? nil : tools.map { tool in
            AnthropicTool(
                name: tool.name,
                description: tool.description,
                inputSchema: tool.parameters ?? [:],
            )
        }

        return AnthropicRequestBody(
            model: model.rawValue,
            messages: chatMessages.map { AnthropicMessage.from($0) },
            system: systemMessages,
            maxTokens: maxTokens,
            temperature: temperature,
            stream: stream,
            tools: anthropicTools,
        )
    }

    private func splitSystemMessages(_ messages: [AIMessage]) -> (system: String?, chat: [AIMessage]) {
        let systemTexts = messages.compactMap { msg -> String? in
            guard msg.role == .system, case let .text(text) = msg.content else { return nil }
            return text
        }
        let chatMessages = messages.filter { $0.role != .system }
        let systemText = systemTexts.isEmpty ? nil : systemTexts.joined(separator: "\n\n")
        return (systemText, chatMessages)
    }

    // MARK: - Tool Call Accumulation

    private struct AnthropicToolCallAccumulator {
        var id: String
        var name: String?
        var arguments: String
    }

    private func accumulateAnthropicToolCall(
        _ event: AIStreamEvent,
        accumulators: inout [Int: AnthropicToolCallAccumulator],
    ) -> AIStreamEvent? {
        switch event {
        case let .toolCallDelta(id, name, argumentsDelta):
            let key = id.isEmpty ? accumulators.count : id.hashValue
            let acc = accumulators[key] ?? AnthropicToolCallAccumulator(
                id: id, name: name, arguments: "",
            )
            accumulators[key] = AnthropicToolCallAccumulator(
                id: acc.id.isEmpty ? id : acc.id,
                name: name ?? acc.name,
                arguments: acc.arguments + argumentsDelta,
            )
            if !argumentsDelta.isEmpty {
                return .toolCallDelta(id: id, name: name, argumentsDelta: argumentsDelta)
            }
            return nil
        default:
            return event
        }
    }

    private func flushAnthropicToolCalls(
        _ accumulators: [Int: AnthropicToolCallAccumulator],
        into continuation: AsyncThrowingStream<AIStreamEvent, Error>.Continuation,
    ) {
        for (_, acc) in accumulators {
            let toolCall = AIToolCall(
                id: acc.id,
                name: acc.name ?? "",
                arguments: acc.arguments.isEmpty ? "{}" : acc.arguments,
            )
            continuation.yield(.toolCallComplete(toolCall))
        }
    }
}

// MARK: - Anthropic Request DTOs

struct AnthropicRequestBody: Encodable, Sendable {
    let model: String
    let messages: [AnthropicMessage]
    let system: String?
    let maxTokens: Int
    let temperature: Double?
    let stream: Bool
    let tools: [AnthropicTool]?

    enum CodingKeys: String, CodingKey {
        case model, messages, system, maxTokens = "max_tokens", temperature, stream, tools
    }
}

struct AnthropicMessage: Encodable, Sendable, Equatable {
    let role: String
    let content: AnthropicMessageContent

    static func from(_ message: AIMessage) -> AnthropicMessage {
        switch message.content {
        case let .text(text):
            return AnthropicMessage(role: message.role.rawValue, content: .text(text))
        case let .parts(parts):
            let anthropicParts = parts.compactMap { part -> AnthropicContentPart? in
                switch part {
                case let .text(text): return .text(text)
                case let .toolCall(call):
                    return .toolResult(id: call.id, content: call.arguments)
                case let .toolResult(result):
                    return .toolResult(id: result.id, content: result.content)
                case .image: return nil
                }
            }
            return AnthropicMessage(role: message.role.rawValue, content: .parts(anthropicParts))
        }
    }
}

enum AnthropicMessageContent: Encodable, Equatable, Sendable {
    case text(String)
    case parts([AnthropicContentPart])

    func encode(to encoder: Encoder) throws {
        switch self {
        case let .text(text):
            var container = encoder.singleValueContainer()
            try container.encode(text)
        case let .parts(parts):
            var container = encoder.unkeyedContainer()
            try container.encode(contentsOf: parts)
        }
    }
}

enum AnthropicContentPart: Encodable, Equatable, Sendable {
    case text(String)
    case toolResult(id: String, content: String)

    private enum CodingKeys: String, CodingKey {
        case type, text, toolUseID = "tool_use_id", content
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .text(text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case let .toolResult(id, content):
            try container.encode("tool_result", forKey: .type)
            try container.encode(id, forKey: .toolUseID)
            try container.encode(content, forKey: .content)
        }
    }
}

struct AnthropicTool: Encodable, Sendable, Equatable {
    let name: String
    let description: String
    let inputSchema: [String: AnyCodableValue]

    enum CodingKeys: String, CodingKey {
        case name, description, inputSchema = "input_schema"
    }
}

/// Errors specific to the Anthropic adapter.
public enum AnthropicAdapterError: Error, Sendable, Equatable {
    case streamingNotSupported
    case invalidConfiguration(String)
}
