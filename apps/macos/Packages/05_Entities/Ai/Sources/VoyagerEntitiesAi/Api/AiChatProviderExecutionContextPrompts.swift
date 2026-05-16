import Foundation

enum OpenAIContextPromptBuilder {
    static func makePrompt(from context: AiChatCurrentContextSnapshot) -> String? {
        var lines: [String] = []

        if let summary = context.summary?.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty {
            lines.append("Current context summary: \(summary)")
        }
        if !context.references.isEmpty {
            lines.append("References:")
            lines.append(contentsOf: context.references.map(makeReferenceLine))
        }
        if !context.items.isEmpty {
            lines.append("Items:")
            lines.append(contentsOf: context.items.map(makeItemLine))
        }
        if !context.attachments.isEmpty {
            lines.append("Attachments:")
            lines.append(contentsOf: context.attachments.map(makeAttachmentLine))
        }

        guard !lines.isEmpty else { return nil }
        lines.append("Use this context when answering the user.")
        return lines.joined(separator: "\n")
    }

    static func makeReferenceLine(_ reference: AiChatContextReference) -> String {
        let title = reference.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let resolved = title.isEmpty ? reference.identifier : title
        return "- [\(reference.kind.rawValue)] \(resolved)"
    }

    static func makeItemLine(_ item: AiChatContextItem) -> String {
        let title = item.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let resolved = title.isEmpty ? item.identifier : title
        return "- [\(item.kind.rawValue)] \(resolved)"
    }

    static func makeAttachmentLine(_ attachment: AiChatContextAttachment) -> String {
        let title = attachment.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let resolved = title.isEmpty ? attachment.identifier : title
        return "- \(resolved)"
    }
}

enum AnthropicContextPromptBuilder {
    static func makeSystemPrompt(from payload: AiChatProviderRequestPayload) -> String? {
        var sections: [String] = []

        let contextText = OpenAIContextPromptBuilder.makePrompt(from: payload.context.currentContext)
        if let contextText, !contextText.isEmpty {
            sections.append(contextText)
        }

        let systemMessages = payload.messages
            .filter { $0.role == .system }
            .map(\.content)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        if !systemMessages.isEmpty {
            sections.append(systemMessages.joined(separator: "\n\n"))
        }

        guard !sections.isEmpty else { return nil }
        return sections.joined(separator: "\n\n")
    }
}
