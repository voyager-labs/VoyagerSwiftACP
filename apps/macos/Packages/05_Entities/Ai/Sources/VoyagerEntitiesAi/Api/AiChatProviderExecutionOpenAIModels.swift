import Foundation

struct ParsedOpenAIResponse: Equatable, Sendable {
    let deltas: [String]
    let finalText: String?
}

struct ParsedAnthropicResponse: Equatable, Sendable {
    let deltas: [String]
    let finalText: String?
}

struct OpenAIResponsesCreateRequest: Encodable, Sendable {
    let model: String
    let input: [OpenAIResponsesInputItem]
    let reasoning: OpenAIResponsesReasoning?
    let stream: Bool

    init(payload: AiChatProviderRequestPayload) {
        model = payload.rawModelID
        input = Self.makeInput(from: payload)
        reasoning = OpenAIResponsesReasoning(payload: payload.thinking)
        stream = true
    }

    private static func makeInput(from payload: AiChatProviderRequestPayload) -> [OpenAIResponsesInputItem] {
        var items: [OpenAIResponsesInputItem] = []

        if let contextText = OpenAIContextPromptBuilder.makePrompt(from: payload),
           !contextText.isEmpty
        {
            items.append(.init(role: .developer, text: contextText))
        }

        let nativeAttachmentContent = nativeAttachmentContentBlocks(from: payload)
        let targetUserIndex = payload.messages.indices.reversed().first { payload.messages[$0].role == .user }
        items.append(contentsOf: payload.messages.enumerated().map { index, message in
            OpenAIResponsesInputItem(
                role: .init(messageRole: message.role),
                text: message.content,
                appendedContent: index == targetUserIndex ? nativeAttachmentContent : []
            )
        })
        return items
    }

    private static func nativeAttachmentContentBlocks(from payload: AiChatProviderRequestPayload) -> [OpenAIResponsesInputContent] {
        payload.context.requestContext.parts.compactMap { part in
            nativeAttachmentContentBlock(from: part, payload: payload)
        }
    }

    private static func nativeAttachmentContentBlock(
        from part: AiChatLockedContextPartSnapshot,
        payload: AiChatProviderRequestPayload,
    ) -> OpenAIResponsesInputContent? {
        guard case let .providerNativeFile(kind, declaredMIMEType, metadata) = part.resolution else { return nil }

        let filename = preferredFilename(part: part, metadata: metadata)
        let capability = AiChatProviderFileCapability.lookup(.init(
            provider: payload.provider,
            rawModelID: payload.rawModelID,
            requestFamily: .openAIResponses,
            fileExtension: preferredFileExtension(filename: filename, metadata: metadata),
            detectedMIMEType: declaredMIMEType,
            detectedContentTypeIdentifier: metadata["contentTypeIdentifier"],
            sizeBytes: preferredByteCount(part: part, metadata: metadata)
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
            return .inputImage(imageURL: "data:\(normalizedMIMEType);base64,\(base64Data)")

        case .pdf, .plainTextDocument, .openAIDocument, .spreadsheet:
            return .inputFile(
                fileData: "data:\(normalizedMIMEType);base64,\(base64Data)",
                filename: filename
            )

        case .codexPathScope:
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
        if let metadataByteCount = metadata["byteCount"].flatMap(Int64.init) {
            return metadataByteCount
        }
        if let sizeBytes = metadata["sizeBytes"].flatMap(Int64.init) {
            return sizeBytes
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

struct OpenAIResponsesInputItem: Encodable, Sendable {
    let type = "message"
    let role: Role
    let content: Content

    init(role: Role, text: String, appendedContent: [OpenAIResponsesInputContent] = []) {
        self.role = role
        if appendedContent.isEmpty {
            content = .text(text)
        } else {
            var parts: [OpenAIResponsesInputContent] = []
            if !text.isEmpty {
                parts.append(.inputText(text))
            }
            parts.append(contentsOf: appendedContent)
            content = .parts(parts.isEmpty ? [.inputText("")] : parts)
        }
    }

    enum Content: Encodable, Sendable {
        case text(String)
        case parts([OpenAIResponsesInputContent])

        func encode(to encoder: Encoder) throws {
            switch self {
            case let .text(text):
                var container = encoder.singleValueContainer()
                try container.encode(text)
            case let .parts(parts):
                var container = encoder.singleValueContainer()
                try container.encode(parts)
            }
        }
    }

    enum Role: String, Encodable, Sendable {
        case developer
        case user
        case assistant

        init(messageRole: AiChatMessageRole) {
            switch messageRole {
            case .system:
                self = .developer
            case .user, .tool:
                self = .user
            case .assistant:
                self = .assistant
            }
        }
    }
}

enum OpenAIResponsesInputContent: Encodable, Sendable {
    case inputText(String)
    case inputImage(imageURL: String)
    case inputFile(fileData: String, filename: String)

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .inputText(text):
            try container.encode("input_text", forKey: .type)
            try container.encode(text, forKey: .text)
        case let .inputImage(imageURL):
            try container.encode("input_image", forKey: .type)
            try container.encode(OpenAIResponsesImageDetail.auto, forKey: .detail)
            try container.encode(imageURL, forKey: .imageURL)
        case let .inputFile(fileData, filename):
            try container.encode("input_file", forKey: .type)
            try container.encode(fileData, forKey: .fileData)
            try container.encode(filename, forKey: .filename)
        }
    }

    enum CodingKeys: String, CodingKey {
        case type
        case text
        case detail
        case imageURL = "image_url"
        case fileData = "file_data"
        case filename
    }

    enum FileDetail: String, Encodable, Sendable {
        case low
        case high
    }

    enum OpenAIResponsesImageDetail: String, Encodable, Sendable {
        case low
        case high
        case auto
        case original
    }
}

struct OpenAIResponsesReasoning: Encodable, Sendable {
    let effort: String?
    let budgetTokens: Int?

    init?(payload: AiChatProviderThinkingPayload?) {
        guard let payload else { return nil }

        switch payload {
        case .none:
            effort = "none"
            budgetTokens = nil
        case let .effort(value):
            effort = value.rawValue
            budgetTokens = nil
        case let .tokenBudget(value):
            effort = nil
            budgetTokens = value
        case let .adaptive(defaultEffort):
            effort = defaultEffort?.rawValue
            budgetTokens = nil
        case .disabled:
            return nil
        }
    }

    enum CodingKeys: String, CodingKey {
        case effort
        case budgetTokens = "budget_tokens"
    }
}

struct OpenAIResponsesFinalResponse: Decodable, Sendable {
    let outputText: String?
    let output: [OpenAIResponsesOutputItem]?

    enum CodingKeys: String, CodingKey {
        case outputText = "output_text"
        case output
    }

    var resolvedText: String? {
        if let outputText, !outputText.isEmpty {
            return outputText
        }

        let text = output?
            .compactMap(\.assistantText)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text?.isEmpty == false ? text : nil
    }
}

struct OpenAIResponsesOutputItem: Decodable, Sendable {
    let content: [OpenAIResponsesOutputContent]?

    var assistantText: String? {
        let text = content?
            .filter { $0.type == "output_text" }
            .compactMap(\.text)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text?.isEmpty == false ? text : nil
    }
}

struct OpenAIResponsesOutputContent: Decodable, Sendable {
    let type: String
    let text: String?
}

struct OpenAIResponsesStreamEvent: Decodable, Sendable {
    let type: String
    let delta: String?
    let text: String?
    let outputText: String?
    let output: [OpenAIResponsesOutputItem]?
    let response: OpenAIResponsesFinalResponse?
    let error: OpenAIResponsesStreamError?

    enum CodingKeys: String, CodingKey {
        case type
        case delta
        case text
        case outputText = "output_text"
        case output
        case response
        case error
    }

    var resolvedText: String? {
        if let responseText = response?.resolvedText {
            return responseText
        }

        if let outputText, !outputText.isEmpty {
            return outputText
        }

        let text = output?
            .compactMap(\.assistantText)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text?.isEmpty == false ? text : nil
    }
}

struct OpenAIResponsesStreamError: Decodable, Sendable {
    let message: String?
    let type: String?
    let code: String?
}
