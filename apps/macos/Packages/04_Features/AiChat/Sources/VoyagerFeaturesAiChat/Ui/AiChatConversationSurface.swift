import AppKit
import Foundation
import SwiftUI
import VoyagerEntitiesAi
import VoyagerShared

struct AiChatConversationSurface: View {
    let state: AiChatState
    let skeleton: AiChatSkeletonDisplayModel
    let searchPresentation: AiChatTranscriptSearchPresentation
    let currentSearchMatch: AiChatRenderedTextMatchDescriptor?
    let renderSession: AiChatAssistantMarkdownRenderSession
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
                    sessionID: state.sessionID,
                    messages: state.transcriptHistory,
                    searchPresentation: searchPresentation,
                    currentSearchMatch: currentSearchMatch,
                    renderSession: renderSession,
                    isProcessing: false,
                    canRegenerate: state.canRegenerate,
                    statusText: state.streamingAssistantDisplayModel == nil ? state.requestStatusText : nil,
                    streamingAssistant: state.streamingAssistantDisplayModel,
                    onRegenerate: onRegenerate,
                )
            case .processing:
                AiChatTranscriptSection(
                    sessionID: state.sessionID,
                    messages: state.transcriptHistory,
                    searchPresentation: searchPresentation,
                    currentSearchMatch: currentSearchMatch,
                    renderSession: renderSession,
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
                sessionID: state.sessionID,
                messages: state.transcriptHistory,
                searchPresentation: searchPresentation,
                currentSearchMatch: currentSearchMatch,
                renderSession: renderSession,
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

struct AiChatStoredMessageViewIdentity: Hashable {
    let sessionID: AiChatSessionID?
    let index: Int
    let role: String
    let content: String

    init(sessionID: AiChatSessionID?, index: Int, message: AiChatMessage) {
        self.sessionID = sessionID
        self.index = index
        role = message.role.rawValue
        content = message.content
    }
}

private struct AiChatTranscriptSection: View {
    let sessionID: AiChatSessionID?
    @Environment(\.locale)
    private var locale
    @Environment(\.timeZone)
    private var timeZone
    let messages: [AiChatMessage]
    let searchPresentation: AiChatTranscriptSearchPresentation
    let currentSearchMatch: AiChatRenderedTextMatchDescriptor?
    let renderSession: AiChatAssistantMarkdownRenderSession
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
                    transcriptRow: .message(index: row.id.index),
                    searchPresentation: searchPresentation,
                    currentSearchMatch: currentSearchMatch,
                    renderSession: renderSession,
                    showsRegenerateAction: canRegenerate && row.id.index == latestAssistantMessageIndex,
                    onRegenerate: onRegenerate,
                )
                .id(
                    AiChatStoredMessageViewIdentity(
                        sessionID: sessionID,
                        index: row.id.index,
                        message: row.message,
                    ),
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
                    searchPresentation: searchPresentation,
                    currentSearchMatch: currentSearchMatch,
                    renderSession: renderSession,
                )
            } else if isProcessing {
                AiChatAssistantCard(
                    title: "Assistant",
                    content: nil,
                    isProcessing: true,
                    searchPresentation: searchPresentation,
                    currentSearchMatch: currentSearchMatch,
                    renderSession: renderSession,
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
    let transcriptRow: AiChatTranscriptRowDiscriminator
    let searchPresentation: AiChatTranscriptSearchPresentation
    let currentSearchMatch: AiChatRenderedTextMatchDescriptor?
    let renderSession: AiChatAssistantMarkdownRenderSession
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
            Text(highlightedPlainText)
                .font(VoyagerDS.Typography.caption)
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)
                .overlay { matchAnchors(blockIndex: 0) }
        }
    }

    private func userMessage(timestampLabel: String?) -> some View {
        let blockID = userMessageBlockID
        renderSession.registerSelectionProjection(
            presentationID: blockID,
            plainText: row.message.content,
            searchText: row.message.content,
            transcriptRow: transcriptRow,
            blockIndex: 0,
        )
        return HStack(spacing: 8) {
            Spacer(minLength: 16)
            AiChatUserMessageBubble(
                blockID: blockID,
                attributedText: highlightedPlainNSAttributedText,
                rawMessageContent: row.message.content,
                renderSession: renderSession,
                transcriptRow: transcriptRow,
            )
            .overlay(alignment: .topLeading) {
                timestampControlOverlay(
                    timestampLabel: timestampLabel,
                    placement: .userLeadingGutter,
                )
            }
        }
        .overlay { matchAnchors(blockIndex: 0) }
    }

    private var highlightedPlainNSAttributedText: NSAttributedString {
        AiChatAssistantMarkdownAttributedText.make(
            text: row.message.content,
            inlineIntents: [],
            matchOffsets: searchPresentation.matchOffsets(
                transcriptRow: transcriptRow,
                blockIndex: 0,
            ),
            currentMatchOffsets: currentSearchMatchOffsets(blockIndex: 0),
            appliesHangulWordPriorityLineBreak: true,
        )
    }

    private var userMessageBlockID: AiChatMarkdownDocument.BlockID {
        switch transcriptRow {
        case let .message(index):
            AiChatMarkdownDocument.BlockID(rawValue: "user-message-\(index)")
        case .streamingAssistant:
            AiChatMarkdownDocument.BlockID(rawValue: "user-message-streaming")
        }
    }

    private func assistantMessage(timestampLabel: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            AiChatAssistantCard(
                title: "Assistant",
                content: row.message.content,
                isProcessing: false,
                headerPresentation: .completedHistorical,
                searchPresentation: searchPresentation,
                currentSearchMatch: currentSearchMatch,
                transcriptRow: transcriptRow,
                renderSession: renderSession,
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

    private var highlightedPlainText: AttributedString {
        AiChatRenderedTextHighlighter.highlight(
            AttributedString(row.message.content),
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
    let searchPresentation: AiChatTranscriptSearchPresentation
    let currentSearchMatch: AiChatRenderedTextMatchDescriptor?
    var transcriptRow: AiChatTranscriptRowDiscriminator = .streamingAssistant
    let renderSession: AiChatAssistantMarkdownRenderSession
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
            AiChatAssistantMarkdownText(
                content: content,
                transcriptRow: transcriptRow,
                searchPresentation: searchPresentation,
                currentSearchMatch: currentSearchMatch,
                renderSession: renderSession,
            )
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
