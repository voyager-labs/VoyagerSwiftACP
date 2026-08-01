import SwiftUI
import VoyagerEntitiesAi

struct AiChatConversationSurface: View {
    let state: AiChatState
    let skeleton: AiChatSkeletonDisplayModel
    let searchPresentation: AiChatTranscriptSearchPresentation
    let currentSearchMatch: AiChatRenderedTextMatchDescriptor?
    let onOpenSettings: () -> Void
    let onErrorRecovery: () -> Void
    let onRegenerate: () -> Void
    let onRebindContext: () -> Void
    let onStartNewChatFromRebind: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if state.sessionStatus == .rebindRequired {
                AiChatRebindRecoveryBanner(
                    onRebindContext: onRebindContext,
                    onStartNewChat: onStartNewChatFromRebind,
                )
            }

            switch skeleton.surface {
            case let .unconnected(connection):
                AiChatStatusBanner(
                    title: connection.title,
                    detail: connection.detail,
                    actionLabel: connection.fixLabel,
                    action: onOpenSettings,
                )
                transcriptSectionIfNeeded(isProcessing: false, canRegenerate: state.canRegenerate)
            case let .error(connection):
                AiChatStatusBanner(
                    title: connection.title,
                    detail: connection.detail,
                    actionLabel: connection.fixLabel,
                    action: onErrorRecovery,
                )
                transcriptSectionIfNeeded(isProcessing: false, canRegenerate: state.canRegenerate)
            case .empty:
                EmptyView()
            case .ready:
                AiChatTranscriptSection(
                    messages: state.transcriptHistory,
                    searchPresentation: searchPresentation,
                    currentSearchMatch: currentSearchMatch,
                    isProcessing: false,
                    canRegenerate: state.canRegenerate,
                    statusText: state.streamingAssistantDisplayModel == nil ? state.requestStatusText : nil,
                    streamingAssistant: state.streamingAssistantDisplayModel,
                    onRegenerate: onRegenerate,
                )
            case .processing:
                AiChatTranscriptSection(
                    messages: state.transcriptHistory,
                    searchPresentation: searchPresentation,
                    currentSearchMatch: currentSearchMatch,
                    isProcessing: true,
                    canRegenerate: false,
                    streamingAssistant: state.streamingAssistantDisplayModel,
                    onRegenerate: onRegenerate,
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func transcriptSectionIfNeeded(isProcessing: Bool, canRegenerate: Bool) -> some View {
        if !state.transcriptHistory.isEmpty {
            AiChatTranscriptSection(
                messages: state.transcriptHistory,
                searchPresentation: searchPresentation,
                currentSearchMatch: currentSearchMatch,
                isProcessing: isProcessing,
                canRegenerate: canRegenerate,
                statusText: state.streamingAssistantDisplayModel == nil ? state.requestStatusText : nil,
                streamingAssistant: state.streamingAssistantDisplayModel,
                onRegenerate: onRegenerate,
            )
        }
    }
}

private struct AiChatRebindRecoveryBanner: View {
    let onRebindContext: () -> Void
    let onStartNewChat: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.triangle.2.circlepath.circle")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Rebind required")

                VStack(alignment: .leading, spacing: 4) {
                    Text("Session needs rebind")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Reconnect this chat to the current context, or start a clean chat.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                Button(action: onRebindContext) {
                    recoveryActionLabel("Rebind context")
                }
                .buttonStyle(.plain)

                Button(action: onStartNewChat) {
                    recoveryActionLabel("Start new chat")
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor)),
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1),
        )
    }

    private func recoveryActionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor)),
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1),
            )
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
                    .accessibilityLabel("Connection status")

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
                .fill(Color(nsColor: .controlBackgroundColor)),
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1),
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
                    .fill(Color(nsColor: .windowBackgroundColor)),
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1),
            )
    }
}

struct AiChatTranscriptRenderPlan: Equatable {
    let messageIndices: Range<Int>
    let latestAssistantMessageIndex: Int?
    let latestAssistantInspectionCount: Int

    static func make(messages: [AiChatMessage]) -> Self {
        var latestAssistantMessageIndex: Int?
        var inspectionCount = 0
        for index in messages.indices.reversed() {
            inspectionCount += 1
            if messages[index].role == .assistant {
                latestAssistantMessageIndex = index
                break
            }
        }
        return Self(
            messageIndices: messages.indices,
            latestAssistantMessageIndex: latestAssistantMessageIndex,
            latestAssistantInspectionCount: inspectionCount,
        )
    }
}

private struct AiChatTranscriptSection: View {
    let messages: [AiChatMessage]
    let searchPresentation: AiChatTranscriptSearchPresentation
    let currentSearchMatch: AiChatRenderedTextMatchDescriptor?
    let isProcessing: Bool
    let canRegenerate: Bool
    var statusText: String?
    var streamingAssistant: AiChatStreamingAssistantDisplayModel?
    let onRegenerate: () -> Void

    var body: some View {
        let renderPlan = AiChatTranscriptRenderPlan.make(messages: messages)
        return VStack(alignment: .leading, spacing: 14) {
            ForEach(renderPlan.messageIndices, id: \.self) { index in
                let message = messages[index]
                AiChatMessageRow(
                    message: message,
                    transcriptRow: .message(index: index),
                    searchPresentation: searchPresentation,
                    currentSearchMatch: currentSearchMatch,
                    showsRegenerateAction: canRegenerate && index == renderPlan.latestAssistantMessageIndex,
                    onRegenerate: onRegenerate,
                )
            }

            if let streamingAssistant {
                AiChatAssistantCard(
                    content: streamingAssistant.content,
                    isProcessing: isProcessing,
                    failure: streamingAssistant.failure,
                    searchPresentation: searchPresentation,
                    currentSearchMatch: currentSearchMatch,
                )
            } else if isProcessing {
                AiChatAssistantCard(
                    content: nil,
                    isProcessing: true,
                    searchPresentation: searchPresentation,
                    currentSearchMatch: currentSearchMatch,
                )
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
    let transcriptRow: AiChatTranscriptRowDiscriminator
    let searchPresentation: AiChatTranscriptSearchPresentation
    let currentSearchMatch: AiChatRenderedTextMatchDescriptor?
    let showsRegenerateAction: Bool
    let onRegenerate: () -> Void

    @State private var isRegenerateActionHovered = false

    var body: some View {
        switch message.role {
        case .user:
            userMessage
        case .assistant:
            assistantMessage
        case .system, .tool:
            Text(highlightedPlainText)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)
                .overlay { matchAnchors(blockIndex: 0) }
        }
    }

    private var userMessage: some View {
        HStack {
            Spacer(minLength: 16)
            Text(highlightedPlainText)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor)),
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1),
                )
        }
        .overlay { matchAnchors(blockIndex: 0) }
    }

    private var assistantMessage: some View {
        VStack(alignment: .leading, spacing: 8) {
            AiChatAssistantMarkdownText(
                content: message.content,
                transcriptRow: transcriptRow,
                searchPresentation: searchPresentation,
                currentSearchMatch: currentSearchMatch,
            )

            if showsRegenerateAction {
                HStack(spacing: 6) {
                    Button(action: onRegenerate) {
                        ZStack {
                            Circle()
                                .fill(Color.primary.opacity(isRegenerateActionHovered ? 0.08 : 0))
                            Circle()
                                .strokeBorder(Color.primary.opacity(isRegenerateActionHovered ? 0.10 : 0), lineWidth: 1)
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 28, height: 28)
                        .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Regenerate response")
                    .accessibilityLabel("Regenerate response")

                    if isRegenerateActionHovered {
                        Text("Regenerate response")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .padding(.horizontal, 8)
                            .frame(height: 24)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color(nsColor: .controlBackgroundColor)),
                            )
                            .overlay(
                                Capsule(style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1),
                            )
                    }
                }
                .onHover { isRegenerateActionHovered = $0 }
            }
        }
        .padding(.vertical, 4)
    }

    private var highlightedPlainText: AttributedString {
        AiChatRenderedTextHighlighter.highlight(
            AttributedString(message.content),
            matchOffsets: searchPresentation.matchOffsets(
                transcriptRow: transcriptRow,
                blockIndex: 0,
            ),
            currentMatchOffsets: currentSearchMatchOffsets(blockIndex: 0),
        )
    }

    private func matchAnchors(blockIndex: Int) -> some View {
        AiChatTranscriptMatchAnchors(
            descriptors: searchPresentation.matchDescriptors(
                transcriptRow: transcriptRow,
                blockIndex: blockIndex,
            ),
        )
    }

    private func currentSearchMatchOffsets(blockIndex: Int) -> Range<Int>? {
        guard currentSearchMatch?.transcriptRow == transcriptRow,
              currentSearchMatch?.blockIndex == blockIndex
        else { return nil }
        return currentSearchMatch?.characterOffsets
    }
}

struct AiChatTranscriptMatchAnchors: View {
    let descriptors: [AiChatRenderedTextMatchDescriptor]

    var targetIDs: [AiChatTranscriptBlockAnchor] {
        guard let descriptor = descriptors.first else { return [] }
        let targetID = AiChatTranscriptBlockAnchor(
            transcriptRow: descriptor.transcriptRow,
            blockIndex: descriptor.blockIndex,
        )
        return [targetID]
    }

    var body: some View {
        ZStack {
            ForEach(targetIDs, id: \.self) { targetID in
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .id(targetID)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct AiChatAssistantCard: View {
    let content: String?
    let isProcessing: Bool
    var failure: AiChatExecutionFailure?
    let searchPresentation: AiChatTranscriptSearchPresentation
    let currentSearchMatch: AiChatRenderedTextMatchDescriptor?

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
                Image(systemName: "bubble.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .accessibilityHidden(true)
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

    @ViewBuilder private var bodyContentView: some View {
        if let content = normalizedContent {
            AiChatAssistantMarkdownText(
                content: content,
                transcriptRow: .streamingAssistant,
                searchPresentation: searchPresentation,
                currentSearchMatch: currentSearchMatch,
            )
        }
    }

    private func failureView(_ failure: AiChatExecutionFailure) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.red)
                .frame(width: 12)
                .accessibilityLabel("Error")

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
    let transcriptRow: AiChatTranscriptRowDiscriminator
    let searchPresentation: AiChatTranscriptSearchPresentation
    let currentSearchMatch: AiChatRenderedTextMatchDescriptor?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { blockIndex, block in
                blockView(block, blockIndex: blockIndex)
                    .overlay {
                        AiChatTranscriptMatchAnchors(
                            descriptors: searchPresentation.matchDescriptors(
                                transcriptRow: transcriptRow,
                                blockIndex: blockIndex,
                            ),
                        )
                    }
                    .accessibilityValue(
                        isCurrentSearchBlock(blockIndex) ? "Current search result" : "",
                    )
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var blocks: [AssistantMarkdownBlock] {
        AssistantMarkdownBlock.parse(content)
    }

    @ViewBuilder
    private func blockView(_ block: AssistantMarkdownBlock, blockIndex: Int) -> some View {
        switch block {
        case let .heading(level, text):
            Text(highlightedInlineMarkdown(text, blockIndex: blockIndex))
                .font(.system(size: headingSize(for: level), weight: .semibold))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        case let .paragraph(text):
            Text(highlightedInlineMarkdown(text, blockIndex: blockIndex))
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        case let .bullet(text):
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text("•")
                    .font(.system(size: 13, weight: .semibold))
                Text(highlightedInlineMarkdown(text, blockIndex: blockIndex))
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case let .numbered(number, text):
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text("\(number).")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(highlightedInlineMarkdown(text, blockIndex: blockIndex))
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case let .code(text):
            Text(highlightedCode(text, blockIndex: blockIndex))
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

    private func highlightedInlineMarkdown(_ text: String, blockIndex: Int) -> AttributedString {
        AiChatRenderedTextHighlighter.highlight(
            inlineMarkdown(text),
            matchOffsets: searchPresentation.matchOffsets(
                transcriptRow: transcriptRow,
                blockIndex: blockIndex,
            ),
            currentMatchOffsets: currentSearchMatchOffsets(blockIndex: blockIndex),
        )
    }

    private func highlightedCode(_ text: String, blockIndex: Int) -> AttributedString {
        AiChatRenderedTextHighlighter.highlight(
            AttributedString(text),
            matchOffsets: searchPresentation.matchOffsets(
                transcriptRow: transcriptRow,
                blockIndex: blockIndex,
            ),
            currentMatchOffsets: currentSearchMatchOffsets(blockIndex: blockIndex),
        )
    }

    private func currentSearchMatchOffsets(blockIndex: Int) -> Range<Int>? {
        guard currentSearchMatch?.transcriptRow == transcriptRow,
              currentSearchMatch?.blockIndex == blockIndex
        else { return nil }
        return currentSearchMatch?.characterOffsets
    }

    private func isCurrentSearchBlock(_ blockIndex: Int) -> Bool {
        currentSearchMatch?.transcriptRow == transcriptRow
            && currentSearchMatch?.blockIndex == blockIndex
    }

    private func inlineMarkdown(_ text: String) -> AttributedString {
        if let markdown = try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace,
            ),
        ) {
            return markdown
        }
        return AttributedString(text)
    }
}
