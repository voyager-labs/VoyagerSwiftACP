import Foundation

extension AiChatProviderExecutionClient {
    static func httpResponse(from response: URLResponse) throws -> HTTPURLResponse {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AiHTTPError.networkError("Non-HTTP response")
        }
        return httpResponse
    }

    static func validateHTTPStatus(_ statusCode: Int, data: Data) throws {
        guard (200 ... 299).contains(statusCode) else {
            throw AiHTTPError.httpError(
                statusCode: statusCode,
                body: String(data: data, encoding: .utf8) ?? "",
            )
        }
    }

    static func parseOpenAIResponse(data: Data, response: HTTPURLResponse) throws -> ParsedOpenAIResponse {
        let contentType = response.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
        if contentType.contains("text/event-stream") || looksLikeSSE(data) {
            return try parseOpenAISSE(data: data)
        }
        return try parseOpenAIFinalJSON(data: data)
    }

    static func looksLikeSSE(_ data: Data) -> Bool {
        guard let text = String(data: data, encoding: .utf8) else { return false }
        return text.contains("data:") && text.contains("response.")
    }

    static func parseOpenAISSE(data: Data) throws -> ParsedOpenAIResponse {
        guard let text = String(data: data, encoding: .utf8) else {
            throw AiHTTPError.networkError("OpenAI stream was not valid UTF-8.")
        }

        var deltas: [String] = []
        var finalText: String?

        for payload in ssePayloads(from: text) {
            _ = try consumeOpenAIPayload(payload, deltas: &deltas, finalText: &finalText)
        }

        return ParsedOpenAIResponse(
            deltas: deltas,
            finalText: finalText ?? (deltas.isEmpty ? nil : deltas.joined()),
        )
    }

    static func parseOpenAIFinalJSON(data: Data) throws -> ParsedOpenAIResponse {
        let response = try JSONDecoder().decode(OpenAIResponsesFinalResponse.self, from: data)
        return ParsedOpenAIResponse(deltas: [], finalText: response.resolvedText)
    }

    static func parseAnthropicResponse(data: Data, response: HTTPURLResponse) throws -> ParsedAnthropicResponse {
        let contentType = response.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
        if contentType.contains("text/event-stream") || looksLikeAnthropicSSE(data) {
            return try parseAnthropicSSE(data: data)
        }
        return try parseAnthropicFinalJSON(data: data)
    }

    static func looksLikeAnthropicSSE(_ data: Data) -> Bool {
        guard let text = String(data: data, encoding: .utf8) else { return false }
        return text.contains("event: message_start") || text.contains("content_block_delta")
    }

    static func parseAnthropicSSE(data: Data) throws -> ParsedAnthropicResponse {
        guard let text = String(data: data, encoding: .utf8) else {
            throw AiHTTPError.networkError("Anthropic stream was not valid UTF-8.")
        }

        var state = AnthropicStreamConsumptionState()
        let decoder = JSONDecoder()
        for payload in ssePayloads(from: text) where payload != "[DONE]" {
            let event = try decodeAnthropicStreamEvent(payload, decoder: decoder)
            _ = try state.consume(event)
        }
        return state.response
    }

    static func parseAnthropicFinalJSON(data: Data) throws -> ParsedAnthropicResponse {
        let response = try JSONDecoder().decode(AnthropicMessageResponse.self, from: data)
        return ParsedAnthropicResponse(deltas: [], finalText: response.resolvedText)
    }

    static func ssePayloads(from text: String) -> [String] {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n\n")
            .compactMap { chunk in
                let dataLines = chunk
                    .components(separatedBy: "\n")
                    .filter { $0.hasPrefix("data:") }
                    .map { line in
                        String(line.dropFirst("data:".count)).trimmingCharacters(in: .whitespaces)
                    }
                guard !dataLines.isEmpty else { return nil }
                return dataLines.joined(separator: "\n")
            }
    }

    static func usesCustomURLProtocol(_ session: URLSession) -> Bool {
        session.configuration.protocolClasses?.isEmpty == false
    }

    static func consumeBufferedOpenAIResponse(
        request: URLRequest,
        session: URLSession,
        context: AiChatRequestContextSnapshot,
        continuation: AsyncThrowingStream<AiChatProviderExecutionEvent, Error>.Continuation,
    ) async throws -> String? {
        let (data, response) = try await session.data(for: request)
        let httpResponse = try httpResponse(from: response)
        try validateHTTPStatus(httpResponse.statusCode, data: data)
        let parsed = try parseOpenAIResponse(data: data, response: httpResponse)
        for delta in parsed.deltas where !delta.isEmpty {
            continuation.yield(.delta(context: context, text: delta))
        }
        return parsed.finalText
    }

    static func consumeBufferedAnthropicResponse(
        request: URLRequest,
        session: URLSession,
        context: AiChatRequestContextSnapshot,
        continuation: AsyncThrowingStream<AiChatProviderExecutionEvent, Error>.Continuation,
    ) async throws -> String? {
        let (data, response) = try await session.data(for: request)
        let httpResponse = try httpResponse(from: response)
        try validateHTTPStatus(httpResponse.statusCode, data: data)
        let parsed = try parseAnthropicResponse(data: data, response: httpResponse)
        for delta in parsed.deltas where !delta.isEmpty {
            continuation.yield(.delta(context: context, text: delta))
        }
        return parsed.finalText
    }

    static func validateStreamingHTTPStatus(_ statusCode: Int, bytes: URLSession.AsyncBytes) async throws {
        guard (200 ... 299).contains(statusCode) else {
            let data = try await collectData(bytes)
            throw AiHTTPError.httpError(
                statusCode: statusCode,
                body: String(data: data, encoding: .utf8) ?? "",
            )
        }
    }

    static func collectData(_ bytes: URLSession.AsyncBytes) async throws -> Data {
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
        }
        return data
    }

    static func isEventStream(_ response: HTTPURLResponse) -> Bool {
        let contentType = response.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
        return contentType.contains("text/event-stream")
    }

    static func consumeOpenAISSE<Lines: AsyncSequence>(
        _ lines: Lines,
        context: AiChatRequestContextSnapshot,
        continuation: AsyncThrowingStream<AiChatProviderExecutionEvent, Error>.Continuation,
    ) async throws -> String? where Lines.Element == String {
        var accumulator = SSEPayloadAccumulator()
        var deltas: [String] = []
        var finalText: String?

        for try await line in lines {
            try Task.checkCancellation()
            for payload in accumulator.consume(line) {
                if let delta = try consumeOpenAIPayload(payload, deltas: &deltas, finalText: &finalText),
                   !delta.isEmpty
                {
                    continuation.yield(.delta(context: context, text: delta))
                }
            }
        }

        if let payload = accumulator.finish(),
           let delta = try consumeOpenAIPayload(payload, deltas: &deltas, finalText: &finalText),
           !delta.isEmpty
        {
            continuation.yield(.delta(context: context, text: delta))
        }

        return finalText ?? (deltas.isEmpty ? nil : deltas.joined())
    }

    static func consumeOpenAIPayload(
        _ payload: String,
        deltas: inout [String],
        finalText: inout String?,
    ) throws -> String? {
        guard payload != "[DONE]" else { return nil }
        let event = try JSONDecoder().decode(OpenAIResponsesStreamEvent.self, from: Data(payload.utf8))
        switch event.type {
        case "response.output_text.delta":
            if let delta = event.delta, !delta.isEmpty {
                deltas.append(delta)
                return delta
            }
        case "response.output_text.done":
            if let text = event.text, !text.isEmpty {
                finalText = text
            }
        case "response.completed":
            if let completedText = event.resolvedText, !completedText.isEmpty {
                finalText = completedText
            }
        case "response.failed", "error":
            throw openAIStreamFailure(event)
        default:
            break
        }
        return nil
    }

    static func openAIStreamFailure(_ event: OpenAIResponsesStreamEvent) -> AiHTTPError {
        let message = event.error?.message
            ?? event.response?.resolvedText
            ?? "OpenAI stream emitted failure event: \(event.type)"
        return .httpError(statusCode: 400, body: message)
    }

    static func consumeAnthropicSSEBytes<Bytes: AsyncSequence>(
        _ bytes: Bytes,
        context: AiChatRequestContextSnapshot,
        continuation: AsyncThrowingStream<AiChatProviderExecutionEvent, Error>.Continuation,
    ) async throws -> String? where Bytes.Element == UInt8 {
        var accumulator = SSEByteFrameAccumulator()
        var state = AnthropicStreamConsumptionState()
        let decoder = JSONDecoder()

        for try await byte in bytes {
            try Task.checkCancellation()
            for payload in try accumulator.consume(byte) {
                if let delta = try consumeAnthropicPayload(
                    payload,
                    decoder: decoder,
                    state: &state,
                ), !delta.isEmpty {
                    continuation.yield(.delta(context: context, text: delta))
                }
            }
        }

        for payload in try accumulator.finish() {
            if let delta = try consumeAnthropicPayload(
                payload,
                decoder: decoder,
                state: &state,
            ), !delta.isEmpty {
                continuation.yield(.delta(context: context, text: delta))
            }
        }

        return state.response.finalText
    }

    static func consumeAnthropicSSE<Lines: AsyncSequence>(
        _ lines: Lines,
        context: AiChatRequestContextSnapshot,
        continuation: AsyncThrowingStream<AiChatProviderExecutionEvent, Error>.Continuation,
    ) async throws -> String? where Lines.Element == String {
        var accumulator = SSEPayloadAccumulator()
        var state = AnthropicStreamConsumptionState()
        let decoder = JSONDecoder()

        for try await line in lines {
            try Task.checkCancellation()
            for payload in accumulator.consume(line) {
                if let delta = try consumeAnthropicPayload(
                    payload,
                    decoder: decoder,
                    state: &state,
                ), !delta.isEmpty {
                    continuation.yield(.delta(context: context, text: delta))
                }
            }
        }

        if let payload = accumulator.finish(),
           let delta = try consumeAnthropicPayload(
               payload,
               decoder: decoder,
               state: &state,
           ), !delta.isEmpty
        {
            continuation.yield(.delta(context: context, text: delta))
        }

        return state.response.finalText
    }

    static func consumeAnthropicPayload(
        _ payload: String,
        decoder: JSONDecoder,
        state: inout AnthropicStreamConsumptionState,
    ) throws -> String? {
        guard payload != "[DONE]" else { return nil }
        let event = try decodeAnthropicStreamEvent(payload, decoder: decoder)
        return try state.consume(event)
    }

    static func decodeAnthropicStreamEvent(
        _ payload: String,
        decoder: JSONDecoder,
    ) throws -> AnthropicStreamEvent {
        do {
            return try decoder.decode(AnthropicStreamEvent.self, from: Data(payload.utf8))
        } catch {
            throw AnthropicStreamParsingError.invalidPayload
        }
    }

    static func mapURLSessionError(_ error: URLError) -> AiHTTPError {
        let description = error.localizedDescription.lowercased()
        if description.contains("timed out") {
            return .timeout
        }

        switch error.code {
        case .timedOut:
            return .timeout
        case .cancelled:
            return .cancelled
        case .networkConnectionLost, .notConnectedToInternet, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed,
             .cannotLoadFromNetwork:
            return .networkError("network")
        default:
            return .networkError(error.localizedDescription)
        }
    }

    nonisolated static func currentTimeMilliseconds() -> Int64 {
        Int64((Date().timeIntervalSince1970 * 1000.0).rounded())
    }
}
