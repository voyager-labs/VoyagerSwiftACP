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
                    statusText: state.requestStatusText
                )
            case .processing:
                AiChatTranscriptSection(messages: state.transcriptHistory, isProcessing: true)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(messages.enumerated()), id: \.offset) { _, message in
                AiChatMessageRow(message: message)
            }

            if isProcessing {
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
        if aiChatMockAssistantBodyLines(from: message.content) != nil {
            AiChatAssistantCard(content: message.content, isProcessing: false)
        } else {
            Text(message.content)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct AiChatAssistantCard: View {
    let content: String?
    let isProcessing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            bodyLinesView
            progressRowsView

            if isProcessing {
                ProgressView()
                    .controlSize(.small)
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
        }
    }

    private var bodyLinesView: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(bodyLines.enumerated()), id: \.offset) { index, line in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(index + 1).")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(line)
                        .font(.system(size: 13))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var progressRowsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            progressRow(symbol: "checkmark", title: Self.progressRows[0], tint: .secondary)
            progressRow(symbol: "checkmark", title: Self.progressRows[1], tint: .secondary)
            progressRow(
                symbol: isProcessing ? "ellipsis" : "star.fill",
                title: Self.progressRows[2],
                tint: isProcessing ? .secondary : .primary
            )
        }
    }

    private var bodyLines: [String] {
        guard let content,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return Self.mockAssistantBodyLines
        }

        if let mockBodyLines = aiChatMockAssistantBodyLines(from: content) {
            return mockBodyLines
        }

        let lines = content
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return lines.isEmpty ? Self.mockAssistantBodyLines : lines
    }

    private func progressRow(symbol: String, title: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 12)

            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(tint)
        }
    }

    private static let assistantHeaderTitle = "Voyager AI"

    private static let mockAssistantBodyLines = [
        "Context checked.",
        "Plan ready.",
        "Provider later."
    ]

    private static let progressRows = [
        "✓ Context",
        "✓ Queued",
        "★ Mock ready"
    ]
}
