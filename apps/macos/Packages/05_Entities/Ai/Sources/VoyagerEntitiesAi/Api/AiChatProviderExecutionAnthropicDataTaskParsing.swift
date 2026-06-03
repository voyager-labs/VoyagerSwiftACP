import Foundation

extension AiChatProviderExecutionClient {
    static func consumeAnthropicDataTaskStream(
        request: URLRequest,
        session: URLSession,
        context: AiChatRequestContextSnapshot,
        continuation: AsyncThrowingStream<AiChatProviderExecutionEvent, Error>.Continuation,
    ) async throws -> String? {
        let streamingTask = AnthropicStreamingDataTask(request: request, configuration: session.configuration)
        return try await withTaskCancellationHandler {
            try await consumeAnthropicDataTaskEvents(
                streamingTask.events(),
                context: context,
                continuation: continuation,
            )
        } onCancel: {
            streamingTask.cancel()
        }
    }

    static func consumeAnthropicDataTaskEvents<Events: AsyncSequence>(
        _ events: Events,
        context: AiChatRequestContextSnapshot,
        continuation: AsyncThrowingStream<AiChatProviderExecutionEvent, Error>.Continuation,
    ) async throws -> String? where Events.Element == AnthropicStreamingDataTaskEvent {
        var accumulator = SSEByteFrameAccumulator()
        var state = AnthropicStreamConsumptionState()
        var errorData = Data()
        var isSuccessResponse = false
        var responseStatusCode: Int?
        let emitter = AnthropicPayloadEmitter(context: context, continuation: continuation)

        for try await event in events {
            try Task.checkCancellation()
            switch event.kind {
            case let .response(response):
                responseStatusCode = response.statusCode
                isSuccessResponse = (200 ... 299).contains(response.statusCode)
            case let .data(data):
                if isSuccessResponse {
                    try emitter.consume(data, accumulator: &accumulator, state: &state)
                } else {
                    errorData.append(data)
                }
            }
        }

        if let statusCode = responseStatusCode, !(200 ... 299).contains(statusCode) {
            throw AiHTTPError.httpError(
                statusCode: statusCode,
                body: String(data: errorData, encoding: .utf8) ?? "",
            )
        }

        try emitter.consume(accumulator.finish(), state: &state)
        return state.response.finalText
    }
}

struct AnthropicPayloadEmitter {
    let context: AiChatRequestContextSnapshot
    let continuation: AsyncThrowingStream<AiChatProviderExecutionEvent, Error>.Continuation
    private let decoder = JSONDecoder()

    func consume(
        _ data: Data,
        accumulator: inout SSEByteFrameAccumulator,
        state: inout AnthropicStreamConsumptionState,
    ) throws {
        for byte in data {
            try consume(accumulator.consume(byte), state: &state)
        }
    }

    func consume(
        _ payloads: [String],
        state: inout AnthropicStreamConsumptionState,
    ) throws {
        for payload in payloads {
            if let delta = try AiChatProviderExecutionClient.consumeAnthropicPayload(
                payload,
                decoder: decoder,
                state: &state,
            ), !delta.isEmpty {
                continuation.yield(.delta(context: context, text: delta))
            }
        }
    }
}
