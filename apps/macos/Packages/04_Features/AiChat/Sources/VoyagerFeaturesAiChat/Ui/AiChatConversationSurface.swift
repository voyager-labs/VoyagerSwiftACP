import AppKit
import Foundation
import SwiftUI
import VoyagerEntitiesAi
import VoyagerShared

struct AiChatTranscriptRowID: Hashable {
    let index: Int
    let role: AiChatMessageRole
    let createdAtMs: Int64?
    func hash(into hasher: inout Hasher) {
        hasher.combine(index)
        hasher.combine(role.rawValue)
        hasher.combine(createdAtMs)
    }
}

enum AiChatTranscriptTimestampStyle: Equatable { case dateTime, relative, shortTime }
struct AiChatTranscriptRowPresentation: Identifiable, Equatable {
    let id: AiChatTranscriptRowID
    let message: AiChatMessage
    let timestampStyle: AiChatTranscriptTimestampStyle?
    let timestampLabel, accessibilityTimestampLabel: String?
    let isTimestampVisuallySuppressed: Bool
    var hasTimestampMetadata: Bool {
        (message.role == .user || message.role == .assistant) && message.createdAtMs != nil
    }

    var showsTimestampAffordance: Bool {
        hasTimestampMetadata && !isTimestampVisuallySuppressed
    }
}

struct AiChatTimestampAffordancePresentation: Equatable {
    enum Placement: Equatable {
        case userLeadingGutter, assistantTopTrailing

        var horizontalOffset: CGFloat {
            let offset = AiChatTimestampAffordancePresentation.controlSize + 4
            return self == .userLeadingGutter ? -offset : offset
        }
    }

    static let controlSize: CGFloat = 24, assistantTrailingGutter = controlSize + 4
    static let tooltipMaximumWidth: CGFloat = 320
    static let tooltipHorizontalPadding: CGFloat = 10, tooltipVerticalPadding: CGFloat = 6
    let placement: Placement

    static func presentsTooltip(hasTimestampMetadata: Bool, isClockHovered: Bool, isClockFocused: Bool) -> Bool {
        hasTimestampMetadata && (isClockHovered || isClockFocused)
    }
}

struct AiChatTranscriptPresentation: Equatable {
    let rows: [AiChatTranscriptRowPresentation]
    init(messages: [AiChatMessage], now: Date, locale: Locale, timeZone: TimeZone) {
        rows = messages.enumerated().map { index, message in
            let timestamp = Self.timestampPresentation(
                createdAtMs: message.createdAtMs, now: now, locale: locale, timeZone: timeZone,
            )
            return AiChatTranscriptRowPresentation(
                id: AiChatTranscriptRowID(index: index, role: message.role, createdAtMs: message.createdAtMs),
                message: message,
                timestampStyle: timestamp?.style,
                timestampLabel: timestamp?.label,
                accessibilityTimestampLabel: timestamp?.label,
                isTimestampVisuallySuppressed: Self.suppressesTimestamp(
                    message, after: index > 0 ? messages[index - 1] : nil,
                ),
            )
        }
    }

    static func timestampPresentation(
        createdAtMs: Int64?,
        now: Date,
        locale: Locale,
        timeZone: TimeZone,
    ) -> (style: AiChatTranscriptTimestampStyle, label: String)? {
        guard let createdAtMs else { return nil }
        let createdAt = Date(timeIntervalSince1970: TimeInterval(createdAtMs) / 1000)
        if createdAt > now { return (.relative, "Just now") }
        var calendar = locale.calendar
        calendar.timeZone = timeZone
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = timeZone
        if calendar.isDate(createdAt, inSameDayAs: now) {
            let age = now.timeIntervalSince(createdAt)
            if age < 60 { return (.relative, "Just now") }
            if age < 60 * 60 {
                let relativeFormatter = RelativeDateTimeFormatter()
                relativeFormatter.locale = locale
                relativeFormatter.dateTimeStyle = .numeric
                return (.relative, relativeFormatter.localizedString(for: createdAt, relativeTo: now))
            }
            formatter.timeStyle = .short
            return (.shortTime, formatter.string(from: createdAt))
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(createdAt, inSameDayAs: yesterday)
        {
            formatter.doesRelativeDateFormatting = true
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
        } else {
            let includesYear = calendar.component(.year, from: createdAt) != calendar.component(.year, from: now)
            formatter.setLocalizedDateFormatFromTemplate(includesYear ? "yMMMdjm" : "MMMdjm")
        }
        return (.dateTime, formatter.string(from: createdAt))
    }

    private static func suppressesTimestamp(_ message: AiChatMessage, after previousMessage: AiChatMessage?) -> Bool {
        guard let previousMessage,
              previousMessage.role == message.role,
              let earlier = previousMessage.createdAtMs,
              let later = message.createdAtMs,
              later >= earlier
        else { return false }
        let (delta, overflow) = later.subtractingReportingOverflow(earlier)
        return !overflow && delta < 60000
    }
}

struct AiChatConversationSurface: View {
    let state: AiChatState
    let skeleton: AiChatSkeletonDisplayModel
    let onOpenSettings: () -> Void
    let onErrorRecovery: () -> Void
    let onRegenerate: () -> Void
    let onRebindContext: () -> Void
    let onStartNewChatFromRebind: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if state.sessionStatus == .rebindRequired {
                AiChatRebindRecoveryBanner(
                    onRebindContext: onRebindContext, onStartNewChat: onStartNewChatFromRebind,
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
                    isProcessing: false,
                    canRegenerate: state.canRegenerate,
                    statusText: state.streamingAssistantDisplayModel == nil ? state.requestStatusText : nil,
                    streamingAssistant: state.streamingAssistantDisplayModel,
                    onRegenerate: onRegenerate,
                )
            case .processing:
                AiChatTranscriptSection(
                    messages: state.transcriptHistory,
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
    @Environment(\.colorScheme)
    private var colorScheme
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
                        .font(VoyagerDS.Typography.caption)
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
            RoundedRectangle(cornerRadius: VoyagerDS.Radius.overlayCard, style: .continuous)
                .fill(VoyagerDS.Surface.overlayBackground(for: colorScheme)),
        )
        .overlay(
            RoundedRectangle(cornerRadius: VoyagerDS.Radius.overlayCard, style: .continuous)
                .strokeBorder(VoyagerDS.Surface.overlayBorder, lineWidth: 1),
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
                    .fill(VoyagerDS.Surface.inputBackground(for: colorScheme)),
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(VoyagerDS.Surface.inputBorder(for: colorScheme), lineWidth: 1),
            )
    }
}

private struct AiChatStatusBanner: View {
    @Environment(\.colorScheme)
    private var colorScheme
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
                        .font(VoyagerDS.Typography.caption)
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
            RoundedRectangle(cornerRadius: VoyagerDS.Radius.overlayCard, style: .continuous)
                .fill(VoyagerDS.Surface.overlayBackground(for: colorScheme)),
        )
        .overlay(
            RoundedRectangle(cornerRadius: VoyagerDS.Radius.overlayCard, style: .continuous)
                .strokeBorder(VoyagerDS.Surface.overlayBorder, lineWidth: 1),
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
                    .fill(VoyagerDS.Surface.inputBackground(for: colorScheme)),
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(VoyagerDS.Surface.inputBorder(for: colorScheme), lineWidth: 1),
            )
    }
}

private struct AiChatTranscriptSection: View {
    @Environment(\.locale)
    private var locale
    @Environment(\.timeZone)
    private var timeZone
    let messages: [AiChatMessage]
    let isProcessing: Bool
    let canRegenerate: Bool
    var statusText: String?
    var streamingAssistant: AiChatStreamingAssistantDisplayModel?
    let onRegenerate: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(transcriptPresentation.rows) { row in
                AiChatMessageRow(
                    row: row,
                    showsRegenerateAction: canRegenerate && row.id.index == latestAssistantMessageIndex,
                    onRegenerate: onRegenerate,
                )
            }
            if let streamingAssistant {
                AiChatAssistantCard(
                    requestID: streamingAssistant.requestID,
                    foregroundRequestID: streamingAssistant.requestID,
                    title: streamingAssistant.title,
                    thinkingLabel: streamingAssistant.thinkingLabel,
                    activityStatusLabel: streamingAssistant.activityStatusLabel,
                    content: streamingAssistant.content,
                    isProcessing: isProcessing,
                    failure: streamingAssistant.failure,
                    acceptedChunkRevision: streamingAssistant.acceptedChunkRevision,
                )
            } else if isProcessing {
                AiChatAssistantCard(
                    title: "Assistant",
                    content: nil,
                    isProcessing: true,
                )
            } else if let statusText {
                requestStatusRow(statusText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var transcriptPresentation: AiChatTranscriptPresentation {
        AiChatTranscriptPresentation(messages: messages, now: Date(), locale: locale, timeZone: timeZone)
    }

    private var latestAssistantMessageIndex: Int? {
        messages.indices.last { messages[$0].role == .assistant }
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
    let row: AiChatTranscriptRowPresentation
    let showsRegenerateAction: Bool
    let onRegenerate: () -> Void
    @Environment(\.colorScheme)
    private var colorScheme
    @Environment(\.locale)
    private var locale
    @Environment(\.timeZone)
    private var timeZone
    @State private var isMessageHovered = false
    @State private var isTimestampControlHovered = false
    @State private var isRegenerateActionHovered = false
    @FocusState private var isTimestampControlFocused: Bool
    var body: some View {
        TimelineView(.animation(minimumInterval: 1, paused: !shouldPresentTimestampTooltip)) { context in
            let timestampLabel = AiChatTranscriptPresentation.timestampPresentation(
                createdAtMs: row.message.createdAtMs, now: context.date, locale: locale, timeZone: timeZone,
            )?.label
            messageContent(timestampLabel: timestampLabel)
                .contentShape(Rectangle())
                .onHover { isMessageHovered = row.showsTimestampAffordance && $0 }
                .accessibilityElement(children: .contain)
                .modifier(AiChatTimestampAccessibilityValue(label: timestampLabel))
                .transformAnchorPreference(
                    key: AiChatTimestampTooltipAnchorPreferenceKey.self,
                    value: .bounds,
                ) { anchor, messageBounds in
                    anchor?.messageBounds = messageBounds
                }
        }
    }

    @ViewBuilder
    private func messageContent(timestampLabel: String?) -> some View {
        switch row.message.role {
        case .user:
            userMessage(timestampLabel: timestampLabel)
        case .assistant:
            assistantMessage(timestampLabel: timestampLabel)
        case .system, .tool:
            Text(row.message.content)
                .font(VoyagerDS.Typography.caption)
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)
        }
    }

    private func userMessage(timestampLabel: String?) -> some View {
        HStack(spacing: 8) {
            Spacer(minLength: 16)
            Text(row.message.content)
                .font(VoyagerDS.Typography.body)
                .foregroundStyle(.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    VoyagerDS.Surface.userMessageBubbleBackground(for: colorScheme),
                    in: RoundedRectangle(cornerRadius: VoyagerDS.Radius.userMessageBubble, style: .continuous),
                )
                .overlay(alignment: .topLeading) {
                    timestampControlOverlay(
                        timestampLabel: timestampLabel,
                        placement: .userLeadingGutter,
                    )
                }
        }
    }

    private func assistantMessage(timestampLabel: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            AiChatAssistantCard(
                title: "Assistant",
                content: row.message.content,
                isProcessing: false,
                headerPresentation: .completedHistorical,
            )
            .accessibilityElement(children: .contain)
            .accessibilityLabel(AiChatAssistantHeaderPresentation.completedHistorical.accessibilityRoleLabel ?? "")
            .overlay(alignment: .topTrailing) {
                timestampControlOverlay(
                    timestampLabel: timestampLabel,
                    placement: .assistantTopTrailing,
                )
            }
            .padding(.trailing, AiChatTimestampAffordancePresentation.assistantTrailingGutter)
            if showsRegenerateAction {
                regenerateAction
            }
        }
    }

    private var regenerateAction: some View {
        HStack(spacing: 6) {
            Button(action: onRegenerate) {
                ZStack {
                    Circle()
                        .fill(isRegenerateActionHovered
                            ? VoyagerDS.Interaction.controlHoverFill(for: colorScheme)
                            : .clear)
                    Circle()
                        .strokeBorder(
                            VoyagerDS.Surface.inputBorder(for: colorScheme)
                                .opacity(isRegenerateActionHovered ? 1 : 0),
                            lineWidth: 1,
                        )
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
                    .font(VoyagerDS.Typography.chip)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(
                        Capsule(style: .continuous)
                            .fill(VoyagerDS.Surface.popoverBackground(for: colorScheme)),
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(VoyagerDS.Surface.popoverBorder, lineWidth: 1),
                    )
            }
        }
        .onHover { isRegenerateActionHovered = $0 }
    }

    @ViewBuilder
    private func timestampControlOverlay(
        timestampLabel: String?,
        placement: AiChatTimestampAffordancePresentation.Placement,
    ) -> some View {
        if let timestampLabel, row.showsTimestampAffordance {
            Image(systemName: "clock")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(
                    width: AiChatTimestampAffordancePresentation.controlSize,
                    height: AiChatTimestampAffordancePresentation.controlSize,
                )
                .contentShape(Circle())
                .focusable()
                .focused($isTimestampControlFocused)
                .onHover { isTimestampControlHovered = $0 }
                .accessibilityHidden(true)
                .opacity(shouldRevealTimestampControl ? 1 : 0)
                .allowsHitTesting(shouldRevealTimestampControl)
                .offset(x: placement.horizontalOffset, y: 4)
                .anchorPreference(
                    key: AiChatTimestampTooltipAnchorPreferenceKey.self,
                    value: .bounds,
                ) { anchor in
                    shouldPresentTimestampTooltip
                        ? AiChatTimestampTooltipAnchor(
                            label: timestampLabel,
                            trigger: isTimestampControlHovered ? .hover : .focus,
                            clockBounds: anchor,
                        )
                        : nil
                }
        }
    }

    private var shouldRevealTimestampControl: Bool {
        row.showsTimestampAffordance && (isMessageHovered || shouldPresentTimestampTooltip)
    }

    private var shouldPresentTimestampTooltip: Bool {
        AiChatTimestampAffordancePresentation.presentsTooltip(
            hasTimestampMetadata: row.showsTimestampAffordance,
            isClockHovered: isTimestampControlHovered,
            isClockFocused: isTimestampControlFocused,
        )
    }
}

private struct AiChatTimestampAccessibilityValue: ViewModifier {
    let label: String?
    func body(content: Content) -> some View {
        if let label {
            content.accessibilityValue("Sent \(label)")
        } else {
            content
        }
    }
}

private struct AiChatAssistantCard: View {
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion
    @State private var isMetadataHovered = false
    @FocusState private var isMetadataFocused: Bool
    var requestID: AiChatRequestID?
    var foregroundRequestID: AiChatRequestID?
    let title: String
    var thinkingLabel: String?
    var activityStatusLabel: String?
    let content: String?
    let isProcessing: Bool
    var headerPresentation: AiChatAssistantHeaderPresentation = .full
    var failure: AiChatExecutionFailure?
    var acceptedChunkRevision: Int?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if bodyPresentation.showsInlineHeader {
                header
            }
            bodyContentView
            if let failure {
                failureView(failure)
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .focusable(bodyPresentation.isMetadataPanelEligible)
        .focused($isMetadataFocused)
        .onHover { isMetadataHovered = bodyPresentation.isMetadataPanelEligible && $0 }
        .modifier(AiChatAssistantMetadataAccessibilityValue(label: bodyPresentation.accessibilityMetadataLabel))
        .anchorPreference(
            key: AiChatAssistantMetadataAnchorPreferenceKey.self,
            value: .bounds,
        ) { bodyBounds in
            guard shouldPresentMetadataPanel, let requestID else { return [:] }
            return [
                requestID: AiChatAssistantMetadataAnchor(
                    requestID: requestID,
                    label: bodyPresentation.metadataPanelLabel,
                    bodyBounds: bodyBounds,
                ),
            ]
        }
        .onChange(of: requestID) { _ in
            clearMetadataInteraction()
        }
        .onChange(of: bodyPresentation.isMetadataPanelEligible) { isEligible in
            if !isEligible { clearMetadataInteraction() }
        }
        .onDisappear {
            clearMetadataInteraction()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            if let thinkingLabel {
                Text(thinkingLabel)
                    .font(VoyagerDS.Typography.chip)
                    .foregroundStyle(.secondary)
            }
            if let activityStatusLabel {
                Text(activityStatusLabel)
                    .font(VoyagerDS.Typography.chip)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(activityStatusLabel)
            }
        }
    }

    @ViewBuilder private var bodyContentView: some View {
        if let content = bodyPresentation.content {
            AiChatAssistantMarkdownText(content: content)
                .contentTransition(.opacity)
                .animation(
                    reduceMotion ? nil : .easeIn(duration: AiChatAssistantBodyPresentation.chunkFadeDuration),
                    value: acceptedChunkRevision,
                )
        } else if bodyPresentation.showsWaiting {
            AiChatWaitingIndicator()
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

    private var bodyPresentation: AiChatAssistantBodyPresentation {
        AiChatAssistantBodyPresentation(
            content: content,
            isProcessing: isProcessing,
            failure: failure,
            title: title,
            thinkingLabel: thinkingLabel,
            headerPresentation: headerPresentation,
            requestID: requestID,
            foregroundRequestID: foregroundRequestID,
        )
    }

    private var shouldPresentMetadataPanel: Bool {
        AiChatAssistantBodyPresentation.presentsMetadataPanel(
            bodyPresentation.isMetadataPanelEligible,
            isMetadataHovered,
            isMetadataFocused,
        )
    }

    private func clearMetadataInteraction() {
        isMetadataHovered = false
        isMetadataFocused = false
    }
}

private struct AiChatAssistantMetadataAccessibilityValue: ViewModifier {
    let label: String?

    func body(content: Content) -> some View {
        if let label {
            content.accessibilityValue(label)
        } else {
            content
        }
    }
}

private struct AiChatWaitingIndicator: View {
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion
    var body: some View {
        Group {
            if reduceMotion {
                Text(AiChatAssistantBodyPresentation.waitingText(step: 0, reduceMotion: true))
            } else {
                TimelineView(.periodic(from: .now, by: 0.4)) { context in
                    let step = Int(context.date.timeIntervalSinceReferenceDate / 0.4)
                    Text(AiChatAssistantBodyPresentation.waitingText(step: step, reduceMotion: false))
                }
            }
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(.secondary)
        .accessibilityLabel("Waiting for assistant response")
    }
}
