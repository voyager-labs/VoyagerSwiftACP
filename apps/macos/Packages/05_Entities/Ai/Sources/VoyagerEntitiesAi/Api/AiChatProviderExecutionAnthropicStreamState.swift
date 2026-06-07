import Foundation

struct AnthropicStreamConsumptionState {
    private var deltas: [String] = []
    private var finalText: String?
    private var toolInputFragmentsByIndex: [Int: String] = [:]
    private var completedToolInputs: [String] = []

    var response: ParsedAnthropicResponse {
        ParsedAnthropicResponse(
            deltas: deltas,
            finalText: finalText
                ?? (deltas.isEmpty ? nil : deltas.joined())
                ?? completedToolInputs.first
                ?? toolInputFragmentsByIndex.values.first(where: { !$0.isEmpty }),
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
        case let .startToolInput(index):
            toolInputFragmentsByIndex[index] = ""
            return nil
        case let .toolInputDelta(index, partialJSON):
            toolInputFragmentsByIndex[index, default: ""].append(partialJSON)
            return nil
        case let .finishToolInput(index):
            if let completedInput = toolInputFragmentsByIndex.removeValue(forKey: index), !completedInput.isEmpty {
                completedToolInputs.append(completedInput)
            }
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
    case startToolInput(Int)
    case toolInputDelta(index: Int, partialJSON: String)
    case finishToolInput(Int)
    case providerError(AnthropicStreamError?)
    case ignore
}

extension AnthropicStreamEvent {
    var consumptionResult: AnthropicStreamConsumptionResult {
        switch type {
        case "content_block_start":
            if contentBlock?.type == "tool_use", let index {
                return .startToolInput(index)
            }
            return nonEmptyText(contentBlock?.text).map(AnthropicStreamConsumptionResult.delta) ?? .ignore
        case "content_block_delta":
            switch delta?.type {
            case "text_delta":
                return nonEmptyText(delta?.text).map(AnthropicStreamConsumptionResult.delta) ?? .ignore
            case "input_json_delta":
                guard let index else { return .ignore }
                return .toolInputDelta(index: index, partialJSON: delta?.partialJSON ?? "")
            default:
                return .ignore
            }
        case "content_block_stop":
            return index.map(AnthropicStreamConsumptionResult.finishToolInput) ?? .ignore
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
