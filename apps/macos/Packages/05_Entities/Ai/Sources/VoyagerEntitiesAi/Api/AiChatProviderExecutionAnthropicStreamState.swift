import Foundation

struct AnthropicStreamConsumptionState {
    private var deltas: [String] = []
    private var finalText: String?

    var response: ParsedAnthropicResponse {
        ParsedAnthropicResponse(
            deltas: deltas,
            finalText: finalText ?? (deltas.isEmpty ? nil : deltas.joined()),
        )
    }

    mutating func consume(_ event: AnthropicStreamEvent) throws -> String? {
        switch event.consumptionResult {
        case let .delta(text):
            deltas.append(text)
            return text
        case let .final(text):
            finalText = text
            return nil
        case let .providerError(error):
            throw AnthropicStreamParsingError.provider(error)
        case .ignore:
            return nil
        }
    }
}

enum AnthropicStreamConsumptionResult {
    case delta(String)
    case final(String)
    case providerError(AnthropicStreamError?)
    case ignore
}

extension AnthropicStreamEvent {
    var consumptionResult: AnthropicStreamConsumptionResult {
        switch type {
        case "content_block_start":
            return nonEmptyText(contentBlock?.text).map(AnthropicStreamConsumptionResult.delta) ?? .ignore
        case "content_block_delta":
            guard delta?.type == "text_delta" else { return .ignore }
            return nonEmptyText(delta?.text).map(AnthropicStreamConsumptionResult.delta) ?? .ignore
        case "message_stop":
            return nonEmptyText(message?.resolvedText).map(AnthropicStreamConsumptionResult.final) ?? .ignore
        case "error":
            return .providerError(error)
        default:
            return .ignore
        }
    }

    private func nonEmptyText(_ text: String?) -> String? {
        guard let text, !text.isEmpty else { return nil }
        return text
    }
}
