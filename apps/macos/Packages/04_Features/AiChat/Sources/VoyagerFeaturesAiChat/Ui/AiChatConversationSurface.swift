// swiftlint:disable file_length
import SwiftUI
import VoyagerEntitiesAi

struct AiChatConversationSurface: View {
    let state: AiChatState
    let skeleton: AiChatSkeletonDisplayModel
    let onOpenSettings: () -> Void
    let onErrorRecovery: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch skeleton.surface {
            case let .unconnected(connection):
                AiChatStatusBanner(
                    title: connection.title,
                    detail: connection.detail,
                    actionLabel: connection.fixLabel,
                    action: onOpenSettings
                )
            case let .error(connection):
                AiChatStatusBanner(
                    title: connection.title,
                    detail: connection.detail,
                    actionLabel: connection.fixLabel,
                    action: onErrorRecovery
                )
            case .empty:
                EmptyView()
            case .ready:
                AiChatTranscriptSection(
                    messages: state.transcriptHistory,
                    isProcessing: false,
                    statusText: state.streamingAssistantDisplayModel == nil ? state.requestStatusText : nil,
                    streamingAssistant: state.streamingAssistantDisplayModel
                )
            case .processing:
                AiChatTranscriptSection(
                    messages: state.transcriptHistory,
                    isProcessing: true,
                    streamingAssistant: state.streamingAssistantDisplayModel
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AiChatStatusBanner: View {
    let title: String
    let detail: String
    let actionLabel: String
    let action: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "bolt.horizontal.circle")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            if let action {
                Button(action: action) {
                    statusActionLabel
                }
                .buttonStyle(.plain)
            } else {
                statusActionLabel
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private var statusActionLabel: some View {
        Text(actionLabel)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
    }
}

private struct AiChatTranscriptSection: View {
    let messages: [AiChatMessage]
    let isProcessing: Bool
    var statusText: String?
    var streamingAssistant: AiChatStreamingAssistantDisplayModel?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(messages.enumerated()), id: \.offset) { _, message in
                AiChatMessageRow(message: message)
            }

            if let streamingAssistant {
                AiChatAssistantCard(
                    content: streamingAssistant.content,
                    isProcessing: isProcessing,
                    failure: streamingAssistant.failure
                )
            } else if isProcessing {
                AiChatAssistantCard(content: nil, isProcessing: true)
            } else if let statusText {
                requestStatusRow(statusText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func requestStatusRow(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AiChatMessageRow: View {
    let message: AiChatMessage

    var body: some View {
        switch message.role {
        case .user:
            userMessage
        case .assistant:
            assistantMessage
        case .system, .tool:
            Text(message.content)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)
        }
    }

    private var userMessage: some View {
        HStack {
            Spacer(minLength: 40)
            Text(message.content)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                )
        }
    }

    @ViewBuilder
    private var assistantMessage: some View {
        AiChatAssistantMarkdownText(content: message.content)
            .padding(.vertical, 4)
    }
}

private struct AiChatAssistantCard: View {
    let content: String?
    let isProcessing: Bool
    var failure: AiChatExecutionFailure?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            bodyContentView

            if let failure {
                failureView(failure)
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.07))
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .frame(width: 28, height: 28)

            Text(Self.assistantHeaderTitle)
                .font(.system(size: 13, weight: .semibold))

            if isProcessing {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private var bodyContentView: some View {
        if let content = normalizedContent {
            AiChatAssistantMarkdownText(content: content)
        }
    }

    private func failureView(_ failure: AiChatExecutionFailure) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.red)
                .frame(width: 12)

            Text(failure.displayMessage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.red)
        }
    }

    private var normalizedContent: String? {
        guard let content else {
            return nil
        }

        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedContent.isEmpty ? nil : content
    }

    private static let assistantHeaderTitle = "Assistant"
}

private struct AiChatAssistantMarkdownText: View {
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var blocks: [AssistantMarkdownBlock] {
        AssistantMarkdownBlock.parse(content)
    }

    @ViewBuilder
    private func blockView(_ block: AssistantMarkdownBlock) -> some View {
        switch block {
        case let .heading(level, text):
            Text(inlineMarkdown(text))
                .font(.system(size: headingSize(for: level), weight: .semibold))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        case let .paragraph(text):
            Text(inlineMarkdown(text))
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        case let .bullet(text):
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text("•")
                    .font(.system(size: 13, weight: .semibold))
                Text(inlineMarkdown(text))
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case let .numbered(number, text):
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text("\(number).")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(inlineMarkdown(text))
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case let .code(text):
            Text(text)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.primary)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private func headingSize(for level: Int) -> CGFloat {
        switch level {
        case 1: 17
        case 2: 15
        default: 14
        }
    }

    private func inlineMarkdown(_ text: String) -> AttributedString {
        if let markdown = try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        ) {
            return markdown
        }
        return AttributedString(text)
    }
}

private enum AssistantMarkdownBlock: Equatable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case bullet(String)
    case numbered(number: Int, text: String)
    case code(String)

    // swiftlint:disable:next function_body_length
    static func parse(_ markdown: String) -> [AssistantMarkdownBlock] {
        var blocks: [AssistantMarkdownBlock] = []
        var paragraphLines: [String] = []
        var codeLines: [String] = []
        var isInCodeBlock = false

        func flushParagraph() {
            let paragraph = paragraphLines
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !paragraph.isEmpty {
                blocks.append(.paragraph(paragraph))
            }
            paragraphLines.removeAll()
        }

        func flushCode() {
            blocks.append(.code(codeLines.joined(separator: "\n")))
            codeLines.removeAll()
        }

        for rawLine in markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            let trimmedLine = rawLine.trimmingCharacters(in: .whitespaces)

            if trimmedLine.hasPrefix("```") {
                flushParagraph()
                if isInCodeBlock {
                    flushCode()
                }
                isInCodeBlock.toggle()
                continue
            }

            if isInCodeBlock {
                codeLines.append(rawLine)
                continue
            }

            if trimmedLine.isEmpty {
                flushParagraph()
                continue
            }

            if let heading = parseHeading(trimmedLine) {
                flushParagraph()
                blocks.append(heading)
                continue
            }

            if let bullet = parseBullet(trimmedLine) {
                flushParagraph()
                blocks.append(.bullet(bullet))
                continue
            }

            if let numbered = parseNumbered(trimmedLine) {
                flushParagraph()
                blocks.append(numbered)
                continue
            }

            paragraphLines.append(rawLine)
        }

        if isInCodeBlock {
            paragraphLines.append("```")
            paragraphLines.append(contentsOf: codeLines)
        } else if !codeLines.isEmpty {
            flushCode()
        }
        flushParagraph()

        return blocks.isEmpty ? [.paragraph(markdown)] : blocks
    }

    private static func parseHeading(_ line: String) -> AssistantMarkdownBlock? {
        let markerCount = line.prefix { $0 == "#" }.count
        guard (1 ... 6).contains(markerCount), line.dropFirst(markerCount).first == " " else {
            return nil
        }
        let text = line.dropFirst(markerCount + 1).trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : .heading(level: markerCount, text: text)
    }

    private static func parseBullet(_ line: String) -> String? {
        guard line.count > 2 else { return nil }
        let prefix = line.prefix(2)
        guard prefix == "- " || prefix == "* " else { return nil }
        let text = line.dropFirst(2).trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : text
    }

    private static func parseNumbered(_ line: String) -> AssistantMarkdownBlock? {
        guard let dotIndex = line.firstIndex(of: ".") else { return nil }
        let digits = line[..<dotIndex]
        guard !digits.isEmpty, digits.allSatisfy(\.isNumber) else { return nil }
        let textStart = line.index(after: dotIndex)
        guard textStart < line.endIndex, line[textStart] == " " else { return nil }
        let text = line[line.index(after: textStart)...].trimmingCharacters(in: .whitespaces)
        guard let number = Int(digits), !text.isEmpty else { return nil }
        return .numbered(number: number, text: text)
    }
}
