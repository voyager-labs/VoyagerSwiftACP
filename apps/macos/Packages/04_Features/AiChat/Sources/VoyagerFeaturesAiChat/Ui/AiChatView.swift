// swiftlint:disable file_length
import ComposableArchitecture
import Perception
import SwiftUI
import VoyagerEntitiesAi

// swiftlint:disable:next type_body_length
public struct AiChatView: View {
    let store: StoreOf<AiChatFeature>

    @Environment(\.colorScheme)
    private var colorScheme

    @State private var isChatInputFocused = false
    @State private var chatInputTextHeight = Self.chatInputMinTextHeight
    @State private var isModelSelectorPopoverPresented = false
    @State private var isThinkingSelectorPresented = false

    public init(store: StoreOf<AiChatFeature>) {
        self.store = store
    }

    public var body: some View {
        WithPerceptionTracking {
            let state = store.state
            let skeleton = state.skeletonDisplayModel

            ScrollViewReader { scrollProxy in
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            conversationSurface(state: state, skeleton: skeleton)
                            Color.clear
                                .frame(height: 1)
                                .id(Self.transcriptBottomAnchorID)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.top, 10)
                        .padding(.bottom, 8)
                    }
                    .onChange(of: transcriptScrollSignature(state: state)) { _ in
                        scrollTranscriptToBottom(scrollProxy)
                    }

                    chatInput(state: state, input: skeleton.chatInput)
                        .padding(.horizontal, 10)
                        .padding(.top, 8)
                        .padding(.bottom, 10)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
    }

    private func transcriptScrollSignature(state: AiChatState) -> String {
        let lastMessage = state.transcriptHistory.last
        return [
            String(state.transcriptHistory.count),
            lastMessage?.role.rawValue ?? "none",
            lastMessage?.content ?? "",
            String(state.isProcessing),
            state.requestStatusText ?? "",
        ].joined(separator: "|")
    }

    private func scrollTranscriptToBottom(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.18)) {
                proxy.scrollTo(Self.transcriptBottomAnchorID, anchor: .bottom)
            }
        }
    }

    @ViewBuilder
    private func conversationSurface(state: AiChatState, skeleton: AiChatSkeletonDisplayModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            switch skeleton.surface {
            case let .unconnected(connection):
                statusBanner(
                    title: connection.title,
                    detail: connection.detail,
                    actionLabel: connection.fixLabel,
                    action: { store.send(.openSettingsTapped) }
                )
            case let .error(connection):
                statusBanner(
                    title: connection.title,
                    detail: connection.detail,
                    actionLabel: connection.fixLabel,
                    action: { store.send(.errorRecoveryTapped) }
                )
            case .empty:
                EmptyView()
            case .ready:
                transcriptSection(
                    messages: state.transcriptHistory,
                    isProcessing: false,
                    statusText: state.requestStatusText
                )
            case .processing:
                transcriptSection(messages: state.transcriptHistory, isProcessing: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statusBanner(
        title: String,
        detail: String,
        actionLabel: String,
        action: (() -> Void)? = nil
    ) -> some View {
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
                Button {
                    action()
                } label: {
                    statusActionLabel(actionLabel)
                }
                .buttonStyle(.plain)
            } else {
                statusActionLabel(actionLabel)
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

    private func statusActionLabel(_ label: String) -> some View {
        Text(label)
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

    private func transcriptSection(
        messages: [AiChatMessage],
        isProcessing: Bool,
        statusText: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(messages.enumerated()), id: \.offset) { _, message in
                messageRow(message)
            }

            if isProcessing {
                assistantCard(content: nil, isProcessing: true)
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

    @ViewBuilder
    private func messageRow(_ message: AiChatMessage) -> some View {
        switch message.role {
        case .user:
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
        case .assistant:
            if aiChatMockAssistantBodyLines(from: message.content) != nil {
                assistantCard(content: message.content, isProcessing: false)
            } else {
                plainAssistantMessage(message.content)
            }
        case .system, .tool:
            Text(message.content)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)
        }
    }

    private func plainAssistantMessage(_ content: String) -> some View {
        Text(content)
            .font(.system(size: 13))
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func assistantCard(content: String?, isProcessing: Bool) -> some View {
        let bodyLines = assistantBodyLines(from: content)

        return VStack(alignment: .leading, spacing: 14) {
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

            VStack(alignment: .leading, spacing: 8) {
                progressRow(symbol: "checkmark", title: Self.progressRows[0], tint: .secondary)
                progressRow(symbol: "checkmark", title: Self.progressRows[1], tint: .secondary)
                progressRow(
                    symbol: isProcessing ? "ellipsis" : "star.fill",
                    title: Self.progressRows[2],
                    tint: isProcessing ? .secondary : .primary
                )
            }

            if isProcessing {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
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

    private func chatInput(state: AiChatState, input: AiChatInputDisplayModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            chatInputTextField(state: state, input: input)

            HStack(alignment: .bottom, spacing: 4) {
                HoverTextAffordance(
                    title: input.contextAffordanceLabel,
                    systemName: nil,
                    titleFontSize: 14,
                    titleWeight: .semibold,
                    hoverColor: .primary
                )
                .fixedSize(horizontal: true, vertical: false)
                modelSelectorButton(state: state, input: input)
                thinkingSelectorButton(state: state, input: input)
                Spacer(minLength: 2)
                chatInputActionButton(input: input)
            }
        }
        .padding(8)
        .onChange(of: state.isProcessing) { isProcessing in
            if !isProcessing {
                restoreChatInputFocus()
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(chatInputBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(chatInputBorder, lineWidth: 1)
        )
    }

    private func modelSelectorButton(state: AiChatState, input _: AiChatInputDisplayModel) -> some View {
        Button {
            isModelSelectorPopoverPresented.toggle()
            if isModelSelectorPopoverPresented {
                store.send(.modelSelectorTapped)
            } else {
                store.send(.modelSelectorDismissed)
            }
        } label: {
            HoverTextAffordance(title: Self.modelSelectorLabel(for: state), systemName: "chevron.down")
                .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isModelSelectorPopoverPresented, arrowEdge: .bottom) {
            modelSelectorDropdownContent(state: state)
                .onDisappear {
                    store.send(.modelSelectorDismissed)
                }
        }
        .onChange(of: state.modelSelectorIsDisabled) { isDisabled in
            guard isDisabled, isModelSelectorPopoverPresented else { return }
            isModelSelectorPopoverPresented = false
            store.send(.modelSelectorDismissed)
        }
        .disabled(modelSelectorIsDisabled(for: state))
        .accessibilityLabel("Model")
        .accessibilityValue(modelSelectorAccessibilityValue(for: state))
    }

    private func thinkingSelectorButton(state: AiChatState, input: AiChatInputDisplayModel) -> some View {
        let capability = state.resolvedSelectedModel?.thinkingCapability

        return Button {
            isThinkingSelectorPresented.toggle()
        } label: {
            HoverTextAffordance(
                title: thinkingSelectorLabel(for: state, input: input),
                systemName: "chevron.down"
            )
            .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isThinkingSelectorPresented, arrowEdge: .bottom) {
            selectorPopoverContainer {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(thinkingSelectorOptions(for: capability), id: \.id) { option in
                        thinkingSelectorRow(option, isSelected: state.selectedThinking == option.selection)
                    }
                }
            }
        }
        .disabled(thinkingSelectorIsDisabled(for: state))
        .accessibilityLabel("Thinking")
        .accessibilityValue(thinkingSelectorAccessibilityValue(for: state))
    }

    static func modelSelectorLabel(for state: AiChatState) -> String {
        if let selectedModel = state.selectedModelDisplayModel {
            return selectedModel.title
        }

        return switch state.modelListState {
        case .loading, .idle:
            "Loading"
        case .failed:
            "Unavailable"
        case .empty:
            "No models"
        case .loaded:
            "Model"
        }
    }

    static func modelSelectorUsesScrollableContent(for contentState: AiChatModelSelectorContentState) -> Bool {
        if case .loaded = contentState {
            return true
        }

        return false
    }

    private func thinkingSelectorLabel(for state: AiChatState, input: AiChatInputDisplayModel) -> String {
        guard let model = state.resolvedSelectedModel else {
            return "Thinking"
        }

        switch model.thinkingCapability {
        case .unsupported, .unknown:
            return "Unavailable"
        case .effort, .adaptive, .tokenBudget:
            return state.selectedThinking.map(AiChatState.thinkingLabel(for:)) ?? input.effortLabel
        }
    }

    private func thinkingSelectorAccessibilityValue(for state: AiChatState) -> String {
        guard let model = state.resolvedSelectedModel else { return "No selection" }

        switch model.thinkingCapability {
        case .unsupported, .unknown:
            return "Unavailable"
        case .effort, .adaptive, .tokenBudget:
            return state.selectedThinking.map(AiChatState.thinkingLabel(for:))
                ?? AiChatState.defaultThinkingLabel(for: model.thinkingCapability)
        }
    }

    private func thinkingSelectorIsDisabled(for state: AiChatState) -> Bool {
        guard let model = state.resolvedSelectedModel else { return true }

        switch model.thinkingCapability {
        case .unsupported, .unknown:
            return true
        case let .effort(values, _):
            return values.isEmpty
        case let .adaptive(effortValues, _):
            return effortValues.isEmpty
        case let .tokenBudget(min, max, _):
            return min > max
        }
    }

    private func thinkingSelectorOptions(for capability: AiModelThinkingCapability?) -> [ThinkingSelectorOption] {
        switch capability {
        case let .effort(values, _):
            return values.map { ThinkingSelectorOption(selection: AiThinkingSelection.effort($0), title: AiChatState.thinkingLabel(for: AiThinkingSelection.effort($0))) }
        case let .adaptive(effortValues, _):
            return effortValues.map { ThinkingSelectorOption(selection: AiThinkingSelection.effort($0), title: AiChatState.thinkingLabel(for: AiThinkingSelection.effort($0))) }
        case let .tokenBudget(min, max, defaultValue):
            let candidateValues = thinkingBudgetValues(min: min, max: max, defaultValue: defaultValue)
            return candidateValues.map { ThinkingSelectorOption(selection: AiThinkingSelection.tokenBudget($0), title: AiChatState.thinkingLabel(for: AiThinkingSelection.tokenBudget($0))) }
        case .unsupported, .unknown, nil:
            return []
        }
    }

    private func thinkingBudgetValues(min: Int, max: Int, defaultValue: Int?) -> [Int] {
        var values: [Int] = [min]
        if let defaultValue, defaultValue != min, defaultValue != max {
            values.append(defaultValue)
        }
        if max != min {
            values.append(max)
        }
        return values
    }

    @ViewBuilder
    private func thinkingSelectorRow(_ option: ThinkingSelectorOption, isSelected: Bool) -> some View {
        Button {
            store.send(.selectedThinkingChanged(option.selection))
            isThinkingSelectorPresented = false
        } label: {
            HStack(spacing: 8) {
                Text(option.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(.primary)

                Spacer(minLength: 8)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.primary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.primary.opacity(0.08) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.title)
    }

    private func modelSelectorIsDisabled(for state: AiChatState) -> Bool {
        state.modelSelectorIsDisabled
    }

    @ViewBuilder
    private func modelSelectorDropdownContent(state: AiChatState) -> some View {
        selectorPopoverContainer {
            switch state.modelSelectorContentState {
            case let .loaded(sections):
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                            if index > 0 {
                                Divider()
                                    .padding(.vertical, 4)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text(section.title)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 8)
                                    .padding(.top, index == 0 ? 0 : 2)

                                ForEach(section.rows) { row in
                                    modelSelectorRow(row)
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: Self.modelSelectorContentMaxHeight)

            case let .loading(status),
                 let .empty(status),
                 let .failed(status),
                 let .unsupported(status):
                modelSelectorStatusRow(status)
            }
        }
    }

    private func selectorPopoverContainer<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(8)
            .frame(width: Self.selectorPopoverWidth, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.16), radius: 12, x: 0, y: 6)
    }

    @ViewBuilder
    private func modelSelectorStatusRow(_ status: AiChatModelSelectorStatusDisplayModel) -> some View {
        Button {
            store.send(.modelSelectorTapped)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(status.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(status.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .disabled(true)
        .accessibilityLabel(status.title)
        .accessibilityValue(status.detail)
    }

    @ViewBuilder
    private func modelSelectorRow(_ row: AiChatModelCatalogRowDisplayModel) -> some View {
        Button {
            store.send(.selectedModelChanged(row.handle))
            store.send(.modelSelectorDismissed)
            isModelSelectorPopoverPresented = false
        } label: {
            HStack(spacing: 8) {
                Text(row.title)
                    .font(.system(size: 13, weight: row.isSelected ? .semibold : .regular))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if row.isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.primary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(row.isSelected ? Color.primary.opacity(0.08) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(row.title)
        .accessibilityHint(row.providerBadge ?? "")
    }

    private func modelSelectorAccessibilityValue(for state: AiChatState) -> String {
        switch state.modelSelectorContentState {
        case .loading:
            return "Loading"
        case .empty:
            return "No models"
        case .failed:
            return "Unavailable"
        case .unsupported:
            return "Unsupported"
        case .loaded:
            return state.selectedModelDisplayModel?.title ?? "No selection"
        }
    }

    private func chatInputTextField(state: AiChatState, input: AiChatInputDisplayModel) -> some View {
        ZStack(alignment: .topLeading) {
            AiChatInputTextView(
                text: Binding(
                    get: { state.draftText },
                    set: { store.send(.draftTextChanged($0)) }
                ),
                isFocused: $isChatInputFocused,
                measuredHeight: $chatInputTextHeight,
                isDisabled: state.isProcessing,
                maxVisibleHeight: Self.chatInputMaxTextHeight,
                onSubmit: { submitAndRestoreInputFocus() }
            )
            .frame(height: boundedChatInputTextHeight)

            if state.draftText.isEmpty {
                Text(input.placeholder)
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
                    .padding(.top, AiChatInputTextView.textVerticalInset)
                    .padding(.leading, AiChatInputTextView.textHorizontalInset)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: Self.chatInputMinTextHeight, alignment: .topLeading)
        .padding(.top, 2)
    }

    private var boundedChatInputTextHeight: CGFloat {
        min(
            max(chatInputTextHeight, Self.chatInputMinTextHeight),
            Self.chatInputMaxTextHeight
        )
    }

    private var chatInputBackground: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.06)
            : Color.black.opacity(0.025)
    }

    private var chatInputBorder: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.09)
            : Color.black.opacity(0.09)
    }

    private func chatInputActionButton(input: AiChatInputDisplayModel) -> some View {
        Group {
            if input.isStopVisible {
                Button {
                    store.send(.cancelTapped)
                } label: {
                    actionGlyph(symbol: "stop.fill")
                }
                .buttonStyle(.plain)
                .disabled(!input.canStop)
                .accessibilityLabel(input.stopAccessibilityLabel)
            } else {
                Button {
                    submitAndRestoreInputFocus()
                } label: {
                    actionGlyph(symbol: "arrow.up")
                }
                .buttonStyle(.plain)
                .disabled(!input.canSubmit)
                .accessibilityLabel(input.submitAccessibilityLabel)
            }
        }
    }

    private func submitAndRestoreInputFocus() {
        store.send(.submitTapped)
        restoreChatInputFocus()
    }

    private func restoreChatInputFocus() {
        Task { @MainActor in
            isChatInputFocused = true
        }
    }

    private func actionGlyph(symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 24, height: 24)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary)
            )
            .opacity(1)
    }

    private func assistantBodyLines(from content: String?) -> [String] {
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

    private static let assistantHeaderTitle = "Voyager AI"

    private static let transcriptBottomAnchorID = "ai-chat-transcript-bottom"

    private static let chatInputMinTextHeight: CGFloat = 34
    private static let chatInputMaxTextHeight: CGFloat = 96
    static let selectorPopoverWidth: CGFloat = 260
    static let modelSelectorContentMaxHeight: CGFloat = 280
    private static let mockAssistantBodyLines = [
        "Context checked.",
        "Plan ready.",
        "Provider later.",
    ]

    private static let progressRows = [
        "✓ Context",
        "✓ Queued",
        "★ Mock ready",
    ]

    private struct HoverTextAffordance: View {
        let title: String
        let systemName: String?
        var titleFontSize: CGFloat = 12
        var titleWeight: Font.Weight = .medium
        var hoverColor: Color = .primary

        @State private var isHovered = false

        var body: some View {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: titleFontSize, weight: titleWeight))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let systemName {
                    Image(systemName: systemName)
                        .font(.system(size: 9, weight: .semibold))
                }
            }
            .foregroundStyle(isHovered ? hoverColor : .secondary)
            .contentShape(Rectangle())
            .fixedSize(horizontal: true, vertical: false)
            .onHover { hovering in
                isHovered = hovering
            }
        }
    }

    private struct ThinkingSelectorOption: Identifiable {
        let selection: AiThinkingSelection
        let title: String

        var id: AiThinkingSelection { selection }
    }
}
