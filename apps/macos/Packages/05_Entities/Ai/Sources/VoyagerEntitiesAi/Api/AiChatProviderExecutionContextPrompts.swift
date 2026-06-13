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
            || !requestContext.parts.isEmpty
        else {
            return nil
        }

        return [
            makeCurrentContextSection(
                from: requestContext.currentContext,
                resolvedParts: requestContext.parts.filter { $0.source == .currentContext },
            ),
            makeAddedAttachmentsSection(from: requestContext.addedAttachments),
            makeAttachmentTransmissionSection(from: requestContext.parts),
        ].joined(separator: "\n\n")
    }

    private static func makeCurrentContextSection(
        from context: AiChatCurrentContextSnapshot,
        resolvedParts: [AiChatLockedContextPartSnapshot],
    ) -> String {
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
        if !resolvedParts.isEmpty {
            lines.append("  resolved_parts:")
            lines.append(contentsOf: resolvedParts.flatMap { makeResolvedContextPartLines($0, indent: "    ") })
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
        from parts: [AiChatLockedContextPartSnapshot],
    ) -> String {
        let attachmentParts = parts.filter { $0.source == .attachment }
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
        let title = displayValue(title: reference.title, fallback: reference.identifier)
        var lines =
            [
                "    - [\(reference.kind.rawValue)] \(title)",
            ]
        if let subtitle = normalized(reference.subtitle) {
            lines.append("      subtitle: \(subtitle)")
        }
        lines.append(contentsOf: ContextPromptMetadataFormatting.metadataLines(reference.metadata, indent: "      "))
        return lines
    }

    private static func makeItemLines(_ item: AiChatContextItem) -> [String] {
        var lines = ["    - [\(item.kind.rawValue)] \(displayValue(title: item.title, fallback: item.identifier))"]
        if let subtitle = normalized(item.subtitle) {
            lines.append("      subtitle: \(subtitle)")
        }
        lines.append(contentsOf: ContextPromptMetadataFormatting.metadataLines(item.metadata, indent: "      "))
        if !item.references.isEmpty {
            lines.append("      references:")
            lines.append(contentsOf: item.references.map {
                "        - [\($0.kind.rawValue)] \(displayValue(title: $0.title, fallback: $0.identifier))"
            })
        }
        return lines
    }

    private static func makeContextAttachmentLines(_ attachment: AiChatContextAttachment) -> [String] {
        let title = displayValue(title: attachment.title, fallback: attachment.identifier)
        var lines =
            [
                "    - [\(attachment.kind.rawValue)] \(title)",
            ]
        if let subtitle = normalized(attachment.subtitle) {
            lines.append("      subtitle: \(subtitle)")
        }
        lines.append(contentsOf: ContextPromptMetadataFormatting.metadataLines(attachment.metadata, indent: "      "))
        return lines
    }

    private static func makeAttachmentTransmissionLines(_ part: AiChatLockedContextPartSnapshot) -> [String] {
        let transmission = ContextPromptTransmission.descriptor(for: part.resolution)
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
        lines.append(contentsOf: referenceResolutionMetadataLines(from: part.resolution, indent: "    "))
        return lines
    }

    private static func makeResolvedContextPartLines(
        _ part: AiChatLockedContextPartSnapshot,
        indent: String,
    ) -> [String] {
        let transmission = ContextPromptTransmission.descriptor(for: part.resolution)
        var lines = [
            "\(indent)- \(displayAttachmentTitle(part))",
            "\(indent)  state: \(transmission.state)",
            "\(indent)  status: \(transmission.status)",
            "\(indent)  note: \(transmission.note)",
            "\(indent)  kind: \(part.fileKind.rawValue)",
        ]
        if let displayPath = normalized(part.displayPath ?? contextPartMetadata(part.resolution)["displayPath"]) {
            lines.append("\(indent)  display_path: \(displayPath)")
        }
        lines.append(contentsOf: referenceResolutionMetadataLines(from: part.resolution, indent: "\(indent)  "))
        return lines
    }

    private static func referenceResolutionMetadataLines(
        from resolution: AiChatContextPartResolution,
        indent: String,
    ) -> [String] {
        switch resolution {
        case let .referenceOnly(metadata),
             let .collectionPathList(_, metadata):
            ContextPromptMetadataFormatting.metadataLines(metadata, indent: indent)
                + ContextPromptMetadataFormatting.collectionItemLines(from: metadata, indent: indent)
                + ContextPromptMetadataFormatting.folderStructureLines(from: metadata, indent: indent)
        case let .failure(_, metadata):
            ContextPromptMetadataFormatting.metadataLines(metadata, indent: indent)
        case .inlineText, .partialText, .providerNativeFile:
            []
        }
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
        if let filePath = promptSafeSourcePath(attachment.sourceLocation) {
            lines.append("    file_path: \(filePath)")
        }
        lines.append(contentsOf: addedAttachmentResolutionLines(
            for: attachment.resolutionResult,
            attachmentMetadata: attachment.metadata,
        ))
        return lines
    }

    private static func addedAttachmentResolutionLines(
        for result: AiChatAttachmentResolutionResult,
        attachmentMetadata: [String: String],
    ) -> [String] {
        switch result {
        case let .resolvedText(text, metadata):
            return attachmentTextLines(text: text, metadata: mergedMetadata(attachmentMetadata, metadata))
        case let .resolvedReference(metadata):
            return attachmentReferenceLines(metadata: mergedMetadata(attachmentMetadata, metadata))
        case let .resolvedPartial(text, truncated, metadata):
            return attachmentPartialLines(
                text: text,
                truncated: truncated,
                metadata: mergedMetadata(attachmentMetadata, metadata),
            )
        case let .failure(reason, metadata):
            var lines = ContextPromptMetadataFormatting.metadataLines(
                mergedMetadata(attachmentMetadata, metadata),
                indent: "    ",
            )
            lines.append("    note: not included: \(reason.rawValue)")
            return lines
        }
    }

    private static func attachmentTextLines(text: String, metadata: [String: String]) -> [String] {
        ContextPromptMetadataFormatting.metadataLines(metadata, indent: "    ")
            + ["    content:", "    ```text"]
            + codeBlockLines(text, indent: "    ")
            + ["    ```"]
    }

    private static func attachmentReferenceLines(metadata: [String: String]) -> [String] {
        ContextPromptMetadataFormatting.metadataLines(metadata, indent: "    ")
            + ContextPromptMetadataFormatting.collectionItemLines(from: metadata, indent: "    ")
            + ContextPromptMetadataFormatting.folderStructureLines(from: metadata, indent: "    ")
            + [referenceNoteLine(metadata: metadata)]
    }

    private static func attachmentPartialLines(
        text: String,
        truncated: Bool,
        metadata: [String: String],
    ) -> [String] {
        ContextPromptMetadataFormatting.metadataLines(metadata, indent: "    ")
            + [truncated ? "    truncated: true" : "    truncated: false", "    content:", "    ```text"]
            + codeBlockLines(text, indent: "    ")
            + ["    ```"]
    }

    private static func referenceNoteLine(metadata: [String: String]) -> String {
        ContextPromptMetadataFormatting.collectionItemPaths(from: metadata).isEmpty
            ? "    note: reference included; content not expanded."
            : "    note: collection references included; content not expanded."
    }

    private static func promptSafeSourcePath(_ sourceLocation: AiChatAttachmentSourceLocation) -> String? {
        if let filePath = normalized(sourceLocation.filePath) {
            return displayPath(for: filePath)
        }
        if let fileURL = sourceLocation.fileURL?.path(percentEncoded: false), !fileURL.isEmpty {
            return displayPath(for: fileURL)
        }
        return nil
    }

    private static func displayPath(for path: String) -> String {
        guard path.hasPrefix("/") else { return path }
        let filename = URL(fileURLWithPath: path).lastPathComponent
        return filename.isEmpty ? "redacted-path" : filename
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

    private static func displayValue(title: String?, fallback: String) -> String {
        normalized(title) ?? fallback
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
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
