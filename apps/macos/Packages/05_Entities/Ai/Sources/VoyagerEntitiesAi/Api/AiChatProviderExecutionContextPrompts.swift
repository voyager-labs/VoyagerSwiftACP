import Foundation

enum OpenAIContextPromptBuilder {
    static func makePrompt(from payload: AiChatProviderRequestPayload) -> String? {
        SharedContextPromptBuilder.makePrompt(from: payload.context.requestContext)
    }
}

enum AnthropicContextPromptBuilder {
    static func makeSystemPrompt(from payload: AiChatProviderRequestPayload) -> String? {
        var sections: [String] = []

        let contextText = SharedContextPromptBuilder.makePrompt(from: payload.context.requestContext)
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

private enum SharedContextPromptBuilder {
    static func makePrompt(from requestContext: AiChatLockedRequestContextSnapshot) -> String? {
        guard !isEmpty(requestContext.currentContext)
            || !requestContext.addedAttachments.isEmpty
            || requestContext.parts.contains(where: { $0.source == .attachment })
        else {
            return nil
        }

        return [
            makeCurrentContextSection(from: requestContext.currentContext),
            makeAddedAttachmentsSection(from: requestContext.addedAttachments),
            makeAttachmentTransmissionSection(from: requestContext.parts),
        ].joined(separator: "\n\n")
    }

    private static func makeCurrentContextSection(from context: AiChatCurrentContextSnapshot) -> String {
        var lines = ["current_context:"]

        if let summary = normalized(context.summary) {
            lines.append("  summary: \(summary)")
        }
        if !context.references.isEmpty {
            lines.append("  references:")
            lines.append(contentsOf: context.references.flatMap(makeReferenceLines))
        }
        if !context.items.isEmpty {
            lines.append("  items:")
            lines.append(contentsOf: context.items.flatMap(makeItemLines))
        }
        if !context.attachments.isEmpty {
            lines.append("  attachments:")
            lines.append(contentsOf: context.attachments.flatMap(makeContextAttachmentLines))
        }
        if lines.count == 1 {
            lines.append("  - none")
        }
        return lines.joined(separator: "\n")
    }

    private static func makeAddedAttachmentsSection(from attachments: [AiChatAttachmentSnapshot]) -> String {
        var lines = ["added_attachments:"]
        guard !attachments.isEmpty else {
            lines.append("  - none")
            return lines.joined(separator: "\n")
        }
        for attachment in attachments {
            lines.append(contentsOf: makeAddedAttachmentLines(attachment))
        }
        return lines.joined(separator: "\n")
    }

    private static func makeAttachmentTransmissionSection(
        from parts: [AiChatLockedContextPartSnapshot]
    ) -> String {
        let attachmentParts = parts.filter { part in
            switch part.resolution {
            case .providerNativeFile, .inlineText, .partialText, .referenceOnly, .collectionPathList, .failure:
                return true
            }
        }
        var lines = ["attachment_transmission:"]
        guard !attachmentParts.isEmpty else {
            lines.append("  - none")
            return lines.joined(separator: "\n")
        }
        for part in attachmentParts {
            lines.append(contentsOf: makeAttachmentTransmissionLines(part))
        }
        return lines.joined(separator: "\n")
    }

    private static func makeReferenceLines(_ reference: AiChatContextReference) -> [String] {
        var lines =
            [
                "    - [\(reference.kind.rawValue)] \(displayValue(title: reference.title, fallback: reference.identifier))",
            ]
        if let subtitle = normalized(reference.subtitle) {
            lines.append("      subtitle: \(subtitle)")
        }
        lines.append(contentsOf: metadataLines(reference.metadata, indent: "      "))
        return lines
    }

    private static func makeItemLines(_ item: AiChatContextItem) -> [String] {
        var lines = ["    - [\(item.kind.rawValue)] \(displayValue(title: item.title, fallback: item.identifier))"]
        if let subtitle = normalized(item.subtitle) {
            lines.append("      subtitle: \(subtitle)")
        }
        lines.append(contentsOf: metadataLines(item.metadata, indent: "      "))
        if !item.references.isEmpty {
            lines.append("      references:")
            lines.append(contentsOf: item.references.map {
                "        - [\($0.kind.rawValue)] \(displayValue(title: $0.title, fallback: $0.identifier))"
            })
        }
        return lines
    }

    private static func makeContextAttachmentLines(_ attachment: AiChatContextAttachment) -> [String] {
        var lines =
            [
                "    - [\(attachment.kind.rawValue)] \(displayValue(title: attachment.title, fallback: attachment.identifier))",
            ]
        if let subtitle = normalized(attachment.subtitle) {
            lines.append("      subtitle: \(subtitle)")
        }
        lines.append(contentsOf: metadataLines(attachment.metadata, indent: "      "))
        return lines
    }

    private static func makeAttachmentTransmissionLines(_ part: AiChatLockedContextPartSnapshot) -> [String] {
        let transmission = transmissionDescriptor(for: part.resolution)
        var lines = [
            "  - \(displayAttachmentTitle(part))",
            "    state: \(transmission.state)",
            "    status: \(transmission.status)",
            "    note: \(transmission.note)",
            "    kind: \(part.fileKind.rawValue)",
        ]
        if let mimeType = normalized(part.mimeType ?? contextPartMetadata(part.resolution)["mimeType"]) {
            lines.append("    mime_type: \(mimeType)")
        }
        if let displayPath = normalized(part.displayPath ?? contextPartMetadata(part.resolution)["displayPath"]) {
            lines.append("    display_path: \(displayPath)")
        }
        lines.append(contentsOf: collectionItemLines(from: contextPartMetadata(part.resolution), indent: "    "))
        return lines
    }

    private static func makeAddedAttachmentLines(_ attachment: AiChatAttachmentSnapshot) -> [String] {
        var lines = [
            "  - \(displayAttachmentTitle(attachment)) [\(resolutionLabel(for: attachment.resolutionResult))]",
            "    source: \(attachment.source.rawValue)",
            "    kind: \(attachment.kind.rawValue)",
        ]
        if let subtitle = normalized(attachment.subtitle) {
            lines.append("    subtitle: \(subtitle)")
        }
        if let filePath = normalized(attachment.sourceLocation.filePath) {
            lines.append("    file_path: \(filePath)")
        } else if let fileURL = attachment.sourceLocation.fileURL?.path(percentEncoded: false), !fileURL.isEmpty {
            lines.append("    file_path: \(fileURL)")
        }
        switch attachment.resolutionResult {
        case let .resolvedText(text, metadata):
            lines.append(contentsOf: metadataLines(mergedMetadata(attachment.metadata, metadata), indent: "    "))
            lines.append("    content:")
            lines.append("    ```text")
            lines.append(contentsOf: codeBlockLines(text, indent: "    "))
            lines.append("    ```")
        case let .resolvedReference(metadata):
            let mergedMetadata = mergedMetadata(attachment.metadata, metadata)
            lines.append(contentsOf: metadataLines(mergedMetadata, indent: "    "))
            lines.append(contentsOf: collectionItemLines(from: mergedMetadata, indent: "    "))
            lines.append(collectionItemPaths(from: mergedMetadata).isEmpty
                ? "    note: reference included; content not expanded."
                : "    note: collection references included; content not expanded.")
        case let .resolvedPartial(text, truncated, metadata):
            lines.append(contentsOf: metadataLines(mergedMetadata(attachment.metadata, metadata), indent: "    "))
            lines.append(truncated ? "    truncated: true" : "    truncated: false")
            lines.append("    content:")
            lines.append("    ```text")
            lines.append(contentsOf: codeBlockLines(text, indent: "    "))
            lines.append("    ```")
        case let .failure(reason, metadata):
            lines.append(contentsOf: metadataLines(mergedMetadata(attachment.metadata, metadata), indent: "    "))
            lines.append("    note: not included: \(reason.rawValue)")
        }
        return lines
    }

    private static func displayAttachmentTitle(_ part: AiChatLockedContextPartSnapshot) -> String {
        if let displayTitle = normalized(part.displayTitle) { return displayTitle }
        let metadata = contextPartMetadata(part.resolution)
        if let filename = normalized(metadata["filename"]) { return filename }
        if let displayPath = normalized(part.displayPath ?? metadata["displayPath"]) { return displayPath }
        return "attachment"
    }

    private static func displayAttachmentTitle(_ attachment: AiChatAttachmentSnapshot) -> String {
        if let displayTitle = normalized(attachment.displayTitle) { return displayTitle }
        if let filePath = normalized(attachment.sourceLocation.filePath) { return filePath }
        if let fileURL = attachment.sourceLocation.fileURL?.lastPathComponent, !fileURL.isEmpty { return fileURL }
        return attachment.id.rawValue
    }

    private static func resolutionLabel(for result: AiChatAttachmentResolutionResult) -> String {
        switch result {
        case .resolvedText: "resolvedText"
        case .resolvedReference: "resolvedReference"
        case .resolvedPartial: "resolvedPartial"
        case let .failure(reason, _): reason.rawValue
        }
    }

    private static func contextPartMetadata(_ resolution: AiChatContextPartResolution) -> [String: String] {
        switch resolution {
        case let .inlineText(_, metadata),
             let .partialText(_, _, metadata),
             let .referenceOnly(metadata),
             let .collectionPathList(_, metadata),
             let .providerNativeFile(_, _, metadata),
             let .failure(_, metadata):
            metadata
        }
    }

    private static func transmissionDescriptor(for resolution: AiChatContextPartResolution) -> (state: String, status: String, note: String) {
        switch resolution {
        case .inlineText:
            return ("included", "Included", "attachment included as text in provider context")
        case let .partialText(_, truncated, _):
            return truncated
                ? ("partial", "Partial", "attachment partially included as text in provider context")
                : ("included", "Included", "attachment included as text in provider context")
        case let .referenceOnly(metadata):
            return collectionItemPaths(from: metadata).isEmpty
                ? ("reference-only", "Reference only", "attachment referenced only; contents not included")
                : ("collection-paths", "Collection paths", "attachment represented as collection paths only; contents not included")
        case .collectionPathList:
            return ("collection-paths", "Collection paths", "attachment represented as collection paths only; contents not included")
        case let .providerNativeFile(kind, mimeType, _):
            return kind == .codexPathScope
                ? ("codex-path", "Codex path", "attachment exposed as Codex filesystem path; provider-native transfer not used")
                : ("provider-native", "Uploaded/native", "provider-native attachment included; uploaded natively as \(mimeType)")
        case let .failure(reason, _):
            return reason == .unsupportedType
                ? ("unsupported", "Unsupported", "attachment could not be included: unsupported type")
                : ("failed", "Failed", "attachment could not be included: \(reason.rawValue)")
        }
    }

    private static func displayValue(title: String?, fallback: String) -> String {
        normalized(title) ?? fallback
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }

    private static func metadataLines(_ metadata: [String: String], indent: String) -> [String] {
        let filtered = metadata
            .filter { $0.key != "collectionItemPaths" }
            .mapValues { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.key.isEmpty && !$0.value.isEmpty }
            .sorted { lhs, rhs in lhs.key < rhs.key }
        guard !filtered.isEmpty else { return [] }
        var lines = ["\(indent)metadata:"]
        lines.append(contentsOf: filtered.map { "\(indent)  \($0.key): \($0.value)" })
        return lines
    }

    private static func collectionItemLines(from metadata: [String: String], indent: String) -> [String] {
        let paths = collectionItemPaths(from: metadata)
        guard !paths.isEmpty else { return [] }

        var lines = ["\(indent)collection_items:"]
        lines.append(contentsOf: paths.map { "\(indent)  - \($0)" })
        if metadata["collectionItemsTruncated"]?.lowercased() == "true" {
            lines.append("\(indent)collection_items_truncated: true")
        }
        if let included = normalized(metadata["collectionItemsIncluded"]) {
            lines.append("\(indent)collection_items_included: \(included)")
        }
        if let count = normalized(metadata["collectionItemCount"]) {
            lines.append("\(indent)collection_item_count: \(count)")
        }
        return lines
    }

    private static func collectionItemPaths(from metadata: [String: String]) -> [String] {
        guard let rawPaths = metadata["collectionItemPaths"] else { return [] }
        return rawPaths
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func mergedMetadata(_ lhs: [String: String], _ rhs: [String: String]) -> [String: String] {
        lhs.merging(rhs) { _, new in new }
    }

    private static func codeBlockLines(_ value: String, indent: String) -> [String] {
        let lines = value.split(separator: "\n", omittingEmptySubsequences: false)
        guard !lines.isEmpty else { return [indent] }
        return lines.map { "\(indent)\($0)" }
    }

    private static func isEmpty(_ context: AiChatCurrentContextSnapshot) -> Bool {
        let summaryIsEmpty = context.summary?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
        return summaryIsEmpty && context.references.isEmpty && context.items.isEmpty && context.attachments.isEmpty
    }
}
