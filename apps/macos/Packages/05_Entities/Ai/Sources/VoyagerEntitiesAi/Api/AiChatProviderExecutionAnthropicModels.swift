import Foundation
import VoyagerShared

struct AnthropicMessagesCreateRequest: Encodable {
    let model: String
    let maxTokens: Int
    let messages: [AnthropicMessageInput]
    let system: String?
    let thinking: AnthropicThinkingRequest?
    let outputConfig: AnthropicOutputConfig?
    let tools: [AnthropicToolDefinition]?
    let toolChoice: AnthropicToolChoice?
    let stream: Bool

    init(payload: AiChatProviderRequestPayload) {
        model = payload.rawModelID
        maxTokens = 4096
        system = AnthropicContextPromptBuilder.makeSystemPrompt(from: payload)
        messages = AnthropicMessageInput.makeMessages(from: payload)
        thinking = AnthropicThinkingRequest(payload: payload.thinking)
        outputConfig = AnthropicOutputConfig(payload: payload.thinking)
        tools = payload.responseContract.map { [AnthropicToolDefinition(contract: $0)] }
        toolChoice = payload.responseContract.map(AnthropicToolChoice.init(contract:))
        stream = true
    }

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case messages
        case system
        case thinking
        case outputConfig = "output_config"
        case tools
        case toolChoice = "tool_choice"
        case stream
    }
}

struct AnthropicToolDefinition: Encodable {
    let name: String
    let description: String
    let inputSchema: [String: JSONValue]

    init(contract: AiChatProviderResponseContract) {
        name = contract.name
        description = "Return the structured response for this request."
        inputSchema = contract.schema
    }

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case inputSchema = "input_schema"
    }
}

struct AnthropicToolChoice: Encodable {
    let type = "tool"
    let name: String

    init(contract: AiChatProviderResponseContract) {
        name = contract.name
    }
}

struct AnthropicMessageInput: Encodable {
    let role: String
    let content: [AnthropicInputContent]

    init(role: String, text: String, appendedContent: [AnthropicInputContent] = []) {
        var content: [AnthropicInputContent] = []
        content.append(.text(text))
        content.append(contentsOf: appendedContent)
        self.role = role
        self.content = content
    }

    static func makeMessages(from payload: AiChatProviderRequestPayload) -> [AnthropicMessageInput] {
        let nativeAttachmentContent = nativeAttachmentContentBlocks(from: payload)
        let targetUserIndex = payload.messages.indices.reversed().first { payload.messages[$0].role == .user }

        return payload.messages.enumerated().compactMap { index, message -> AnthropicMessageInput? in
            switch message.role {
            case .user:
                return AnthropicMessageInput(
                    role: "user",
                    text: message.content,
                    appendedContent: index == targetUserIndex ? nativeAttachmentContent : [],
                )
            case .assistant:
                return AnthropicMessageInput(role: "assistant", text: message.content)
            case .system, .tool:
                return nil
            }
        }
    }

    private static func nativeAttachmentContentBlocks(from payload: AiChatProviderRequestPayload)
        -> [AnthropicInputContent]
    {
        payload.context.requestContext.parts.compactMap { part in
            nativeAttachmentContentBlock(from: part, payload: payload)
        }
    }

    private static func nativeAttachmentContentBlock(
        from part: AiChatLockedContextPartSnapshot,
        payload: AiChatProviderRequestPayload,
    ) -> AnthropicInputContent? {
        guard case let .providerNativeFile(kind, declaredMIMEType, metadata) = part.resolution else { return nil }

        let filename = preferredFilename(part: part, metadata: metadata)
        let capability = AiChatProviderFileCapability.lookup(.init(
            provider: payload.provider,
            rawModelID: payload.rawModelID,
            requestFamily: .anthropicMessages,
            fileExtension: preferredFileExtension(filename: filename, metadata: metadata),
            detectedMIMEType: declaredMIMEType,
            detectedContentTypeIdentifier: metadata["contentTypeIdentifier"],
            sizeBytes: preferredByteCount(part: part, metadata: metadata),
        ))
        guard case let .providerNativeUpload(capabilityKind, normalizedMIMEType) = capability.disposition,
              capabilityKind == kind
        else {
            return nil
        }

        let base64Data = preferredBase64Data(metadata: metadata)
        guard !base64Data.isEmpty else { return nil }

        switch kind {
        case .image:
            return .image(mediaType: normalizedMIMEType, data: base64Data)
        case .pdf, .plainTextDocument:
            return .document(mediaType: normalizedMIMEType, data: base64Data, title: filename)
        case .openAIDocument, .spreadsheet, .codexPathScope:
            return nil
        }
    }

    private static func preferredFilename(
        part: AiChatLockedContextPartSnapshot,
        metadata: [String: String],
    ) -> String {
        let candidates = [
            metadata["filename"],
            metadata["displayPath"],
            part.displayPath,
            part.displayTitle,
            metadata["path"],
            metadata["filePath"],
            part.canonicalPath,
        ]
        for candidate in candidates {
            if let filename = sanitizedFilename(candidate) {
                return filename
            }
        }
        return "attachment"
    }

    private static func preferredFileExtension(filename: String, metadata: [String: String]) -> String? {
        if let fileExtension = normalizedFileExtension(metadata["fileExtension"]) {
            return fileExtension
        }
        return normalizedFileExtension(URL(fileURLWithPath: filename).pathExtension)
    }

    private static func preferredByteCount(
        part: AiChatLockedContextPartSnapshot,
        metadata: [String: String],
    ) -> Int64 {
        if let byteCount = part.byteCount {
            return byteCount
        }
        if let metadataByteCount = metadata["byteCount"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           let parsed = Int64(metadataByteCount)
        {
            return parsed
        }
        if let sizeBytes = metadata["sizeBytes"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           let parsed = Int64(sizeBytes)
        {
            return parsed
        }
        return 0
    }

    private static func preferredBase64Data(metadata: [String: String]) -> String {
        for key in ["base64Data", "nativeBase64Data", "fileDataBase64"] {
            if let value = metadata[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                return value
            }
        }
        return ""
    }

    private static func sanitizedFilename(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        if value.hasPrefix("/") {
            let filename = URL(fileURLWithPath: value).lastPathComponent
            return filename.isEmpty ? nil : filename
        }
        return value
    }

    private static func normalizedFileExtension(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        let normalized = value.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return normalized.isEmpty ? nil : normalized
    }
}

enum AnthropicInputContent: Encodable {
    case text(String)
    case image(mediaType: String, data: String)
    case document(mediaType: String, data: String, title: String)

    enum CodingKeys: String, CodingKey {
        case type
        case text
        case source
        case title
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .text(text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case let .image(mediaType, data):
            try container.encode("image", forKey: .type)
            try container.encode(AnthropicBase64Source(mediaType: mediaType, data: data), forKey: .source)
        case let .document(mediaType, data, title):
            try container.encode("document", forKey: .type)
            try container.encode(title, forKey: .title)
            try container.encode(AnthropicBase64Source(mediaType: mediaType, data: data), forKey: .source)
        }
    }
}

struct AnthropicBase64Source: Encodable {
    let type = "base64"
    let mediaType: String
    let data: String

    enum CodingKeys: String, CodingKey {
        case type
        case mediaType = "media_type"
        case data
    }
}

struct AnthropicOutputConfig: Encodable {
    let effort: String

    init?(payload: AiChatProviderThinkingPayload?) {
        switch payload {
        case let .some(.effort(value)):
            effort = value.rawValue
        case let .some(.adaptive(defaultEffort)):
            guard let defaultEffort else { return nil }
            effort = defaultEffort.rawValue
        case .some(.disabled), .some(.tokenBudget), .some(.none), nil:
            return nil
        }
    }
}

struct AnthropicThinkingRequest: Encodable {
    let type: String
    let budgetTokens: Int?
    let display: String?

    init?(payload: AiChatProviderThinkingPayload?) {
        guard let payload else { return nil }

        switch payload {
        case .disabled:
            type = "disabled"
            budgetTokens = nil
            display = nil
        case let .tokenBudget(value):
            type = "enabled"
            budgetTokens = value
            display = "omitted"
        case .adaptive:
            type = "adaptive"
            budgetTokens = nil
            display = "omitted"
        case .none, .effort:
            return nil
        }
    }

    enum CodingKeys: String, CodingKey {
        case type
        case budgetTokens = "budget_tokens"
        case display
    }
}

struct AnthropicMessageResponse: Decodable {
    let content: [AnthropicContentBlock]

    var resolvedText: String? {
        let text = content
            .filter { $0.type == "text" }
            .compactMap(\.text)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty == false {
            return text
        }

        for block in content where block.type == "tool_use" {
            if let inputText = block.input?.jsonObjectString(), inputText.isEmpty == false {
                return inputText
            }
        }
        return nil
    }
}

struct AnthropicContentBlock: Decodable {
    let type: String
    let text: String?
    let input: JSONValue?
}

private extension JSONValue {
    func jsonObjectString() -> String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

struct AnthropicStreamEvent: Decodable {
    let type: String
    let index: Int?
    let delta: AnthropicStreamDelta?
    let message: AnthropicMessageResponse?
    let contentBlock: AnthropicContentBlock?
    let error: AnthropicStreamError?

    enum CodingKeys: String, CodingKey {
        case type
        case index
        case delta
        case message
        case contentBlock = "content_block"
        case error
    }
}

struct AnthropicStreamError: Decodable, Equatable {
    let type: String?
    let message: String?
}

enum AnthropicStreamParsingError: Error, Equatable {
    case invalidPayload
    case provider(AnthropicStreamError?)

    var failureReason: AiChatExecutionFailure {
        switch self {
        case .invalidPayload:
            return .invalidRequest
        case let .provider(error):
            switch error?.type {
            case "authentication_error", "permission_error":
                return .authentication
            case "not_found_error":
                return .modelUnavailable
            case "invalid_request_error":
                return .invalidRequest
            case "overloaded_error", "api_error":
                return .network
            case "rate_limit_error":
                return .rateLimited
            default:
                if let message = error?.message?.lowercased(),
                   message.contains("credit") || message.contains("quota") || message.contains("billing")
                   || message.contains("balance") || message.contains("payment")
                {
                    return .quotaExceeded
                }
                return .invalidRequest
            }
        }
    }
}

struct AnthropicStreamDelta: Decodable {
    let type: String?
    let text: String?
    let partialJSON: String?

    enum CodingKeys: String, CodingKey {
        case type
        case text
        case partialJSON = "partial_json"
    }
}
