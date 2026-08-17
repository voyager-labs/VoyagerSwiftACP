import AppKit
import ComposableArchitecture
import Perception
import SwiftUI
import VoyagerEntitiesAi
import VoyagerShared

private struct AiChatContentRenderValues {
    let skeleton: AiChatSkeletonDisplayModel
    let requestContext: AiChatRequestContextDisplayModel
    let searchPresentation: AiChatTranscriptSearchPresentation
    let currentSearchMatch: AiChatRenderedTextMatchDescriptor?
}

public struct AiChatView: View {
    let store: StoreOf<AiChatFeature>
    let centeredEmptyContent: AnyView?
    let onSessionSelected: ((AiChatSessionID) -> Void)?
    let allowsAttachmentPicker: Bool

    @Environment(\.colorScheme)
    var colorScheme
    @Environment(\.aiChatAccessibilityAnnouncementSink)
    private var accessibilityAnnouncementSink

    @State private var viewScope = AiChatViewScope()
    @StateObject private var inputFocusOwner = AiChatInputFocusOwner()
    @State private var chatInputTextHeight = Self.chatInputMinTextHeight
    @State private var transcriptScrollRestoreRequest: AiChatTranscriptScrollRestoreRequest?
    @State private var transcriptScrollRestoreSequence = 0
    @State private var shouldRestoreChatInputFocusAfterSearch = false
    @StateObject private var transcriptSearchProjection = AiChatTranscriptSearchProjectionModel()
    @StateObject private var assistantMarkdownRenderSession = AiChatAssistantMarkdownRenderSession()

    public init(
        store: StoreOf<AiChatFeature>,
        allowsAttachmentPicker: Bool,
        centeredEmptyContent: AnyView? = nil,
        onSessionSelected: ((AiChatSessionID) -> Void)? = nil,
    ) {
        self.store = store
        self.centeredEmptyContent = centeredEmptyContent
        self.onSessionSelected = onSessionSelected
        self.allowsAttachmentPicker = allowsAttachmentPicker
    }

    public var body: some View {
        WithPerceptionTracking {
            aiChatContent(state: store.state)
        }
    }

    @ViewBuilder
    private func aiChatContent(state: AiChatState) -> some View {
        let skeleton = state.skeletonDisplayModel
        let requestContext = AiChatStateDisplayModelBuilder(state: state).requestContextDisplayModel
        let search = makeTranscriptSearchRenderValues(state: state)
        let searchRequest = search.request
        let searchContext = search.context
        let sessions = Self.sessionsDisplayModel(for: state)
        let presentation = AiChatViewPresentation.resolve(
            state: state,
            hasCenteredEmptyContent: centeredEmptyContent != nil,
        )
        let composerIdentity = viewScope.composerIdentity(displayedSessionID: state.sessionID)

        Group {
            if presentation == .sessions {
                AiChatSessionsView(
                    store: store,
                    state: state,
                    displayModel: sessions,
                    onSessionSelected: onSessionSelected,
                )
            } else {
                chatView(
                    presentation: presentation,
                    centeredEmptyContent: centeredEmptyContent,
                    state: state,
                    renderValues: AiChatContentRenderValues(
                        skeleton: skeleton,
                        requestContext: requestContext,
                        searchPresentation: searchContext.presentation,
                        currentSearchMatch: searchContext.currentMatch,
                    ),
                )
            }
        }
        .onAppear {
            store.send(.onAppear)
        }
        .task(id: searchRequest) {
            await transcriptSearchProjection.update(searchRequest)
        }
        .onChange(of: searchContext.matchCountProjection) { projection in
            guard state.transcriptSearch.isPresented, let projection else { return }
            store.send(.transcriptSearchMatchCountChanged(projection))
        }
        .onChange(of: state.transcriptSearch.isPresented) { isPresented in
            guard isPresented else { return }
            shouldRestoreChatInputFocusAfterSearch = inputFocusOwner.isFocused(for: composerIdentity)
        }
    }

    private func makeTranscriptSearchRenderValues(
        state: AiChatState,
    ) -> (request: AiChatTranscriptSearchProjectionRequest, context: AiChatTranscriptSearchRenderContext) {
        assistantMarkdownRenderSession.prepareForTranscript(in: state)
        let request = transcriptSearchProjection.request(
            for: state,
            renderSession: assistantMarkdownRenderSession,
        )
        let context = transcriptSearchProjection.renderContext(
            for: request,
            currentMatchOrdinal: state.transcriptSearch.currentMatchOrdinal,
        )
        captureAssistantRenderContext(state: state, currentSearchMatch: context.currentMatch)
        return (request, context)
    }

    private func captureAssistantRenderContext(
        state: AiChatState,
        currentSearchMatch: AiChatRenderedTextMatchDescriptor?,
    ) {
        guard let sessionID = state.sessionID,
              let offset = state.transcriptScrollOffsets[sessionID]
        else { return }
        assistantMarkdownRenderSession.captureContext(
            outerScrollOffset: offset,
            currentSearchDescriptor: currentSearchMatch,
        )
    }

    private func chatView(
        presentation: AiChatViewPresentation,
        centeredEmptyContent: AnyView?,
        state: AiChatState,
        renderValues: AiChatContentRenderValues,
    ) -> some View {
        observeLifecycleAnnouncements(
            ScrollViewReader { scrollProxy in
                VStack(spacing: presentation == .centeredEmpty ? 20 : 0) {
                    if state.transcriptSearch.isPresented {
                        transcriptSearchBar(state: state)
                            .padding(.horizontal, 10)
                            .padding(.top, 10)
                            .padding(.bottom, presentation == .transcript ? 2 : 0)
                    }

                    if presentation == .centeredEmpty, let centeredEmptyContent {
                        Spacer(minLength: 0)
                        centeredEmptyContent
                        compactConnectionCTA(for: renderValues.skeleton.surface)
                    } else {
                        transcriptView(
                            state: state,
                            skeleton: renderValues.skeleton,
                            searchPresentation: renderValues.searchPresentation,
                            currentSearchMatch: renderValues.currentSearchMatch,
                            scrollProxy: scrollProxy,
                        )
                    }

                    inputBar(
                        state: state,
                        input: renderValues.skeleton.chatInput,
                        requestContext: renderValues.requestContext,
                    )
                    .padding(.horizontal, presentation == .transcript ? 10 : 0)
                    .padding(.top, presentation == .transcript ? 8 : 0)
                    .padding(.bottom, presentation == .transcript ? 10 : 0)

                    if presentation == .centeredEmpty {
                        Spacer(minLength: 0)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.vertical, presentation == .centeredEmpty ? 40 : 0)
            },
            announcement: AiChatLifecycleAnnouncement(state: state),
        )
    }

    private func transcriptView(
        state: AiChatState,
        skeleton: AiChatSkeletonDisplayModel,
        searchPresentation: AiChatTranscriptSearchPresentation,
        currentSearchMatch: AiChatRenderedTextMatchDescriptor?,
        scrollProxy: ScrollViewProxy,
    ) -> some View {
        transcriptScrollContent(
            state: state,
            skeleton: skeleton,
            searchPresentation: searchPresentation,
            currentSearchMatch: currentSearchMatch,
        )
        .overlayPreferenceValue(AiChatTimestampTooltipAnchorPreferenceKey.self) { anchor in
            timestampTooltipViewport(anchor)
        }
        .overlayPreferenceValue(AiChatAssistantMetadataAnchorPreferenceKey.self) { anchors in
            assistantMetadataViewport(
                (state.streamingAssistantDisplayModel?.requestID).flatMap { anchors[$0] },
            )
        }
        .onAppear {
            requestTranscriptScrollOffsetRestore(for: state)
        }
        .onChange(of: state.sessionID) { _ in
            requestTranscriptScrollOffsetRestore(for: state)
        }
        .onChange(of: state.transcriptAutoScrollVersion) { _ in
            guard Self.shouldAutoScrollToBottom(transcriptSearch: state.transcriptSearch),
                  !assistantMarkdownRenderSession.hasCapturedViewState
            else { return }
            scrollTranscriptToBottom(scrollProxy)
        }
        .onChange(of: state.transcriptHistoryMutationTracker.value) { _ in
            guard assistantMarkdownRenderSession.hasCapturedViewState else { return }
            requestTranscriptScrollOffsetRestore(for: state)
        }
        .onChange(of: state.transcriptSearch.navigationRevision) { _ in
            navigateToCurrentSearchMatch(
                presentation: searchPresentation,
                currentMatch: currentSearchMatch,
                proxy: scrollProxy,
            )
        }
    }

    private func transcriptScrollContent(
        state: AiChatState,
        skeleton: AiChatSkeletonDisplayModel,
        searchPresentation: AiChatTranscriptSearchPresentation,
        currentSearchMatch: AiChatRenderedTextMatchDescriptor?,
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                AiChatConversationSurface(
                    state: state,
                    skeleton: skeleton,
                    searchPresentation: searchPresentation,
                    currentSearchMatch: currentSearchMatch,
                    renderSession: assistantMarkdownRenderSession,
                    onOpenSettings: { store.send(.openSettingsTapped) },
                    onErrorRecovery: { store.send(.errorRecoveryTapped) },
                    onRegenerate: { store.send(.regenerateTapped) },
                    onRebindContext: { store.send(.rebindContextTapped) },
                    onStartNewChatFromRebind: { store.send(.startNewChatFromRebindTapped) },
                )
                Color.clear
                    .frame(height: 0)
                    .background(
                        AiChatTranscriptScrollObserver(
                            sessionID: state.sessionID,
                            restoreRequest: transcriptScrollRestoreRequest,
                            onScrollOffsetChanged: { offsetY, sessionID in
                                guard let sessionID else { return }
                                store.send(.transcriptScrollOffsetChanged(sessionID, offsetY))
                            },
                        ),
                    )

                Color.clear
                    .frame(height: 1)
                    .id(Self.transcriptBottomAnchorID)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 8)
        }
    }

    static let chatInputMinTextHeight: CGFloat = 46
    static let chatInputMaxTextHeight: CGFloat = 160
}

extension AiChatView {
    private func timestampTooltipViewport(_ anchor: AiChatTimestampTooltipAnchor?) -> some View {
        GeometryReader { proxy in
            if let anchor, let messageBounds = anchor.messageBounds {
                let geometry = AiChatTimestampTooltipGeometry.resolve(
                    viewportBounds: CGRect(origin: .zero, size: proxy.size),
                    messageBounds: proxy[messageBounds],
                    clockBounds: proxy[anchor.clockBounds],
                    preferredSize: AiChatTimestampTooltipSizing.resolve(
                        label: anchor.label,
                        availableWidth: proxy.size.width,
                    ),
                )
                AiChatTimestampTooltip(label: anchor.label, size: geometry.frame.size)
                    .position(x: geometry.frame.midX, y: geometry.frame.midY)
            }
        }
    }

    private func assistantMetadataViewport(_ anchor: AiChatAssistantMetadataAnchor?) -> some View {
        GeometryReader { proxy in
            if let anchor {
                let viewportBounds = CGRect(origin: .zero, size: proxy.size)
                let preferredSize = AiChatAssistantMetadataPanelSizing.resolve(
                    label: anchor.label,
                    availableWidth: proxy.size.width,
                )
                if let geometry = AiChatAssistantMetadataPanelGeometry.resolve(
                    viewportBounds: viewportBounds,
                    bodyBounds: proxy[anchor.bodyBounds],
                    preferredSize: preferredSize,
                ) {
                    AiChatAssistantMetadataPanel(label: anchor.label, size: geometry.frame.size)
                        .position(x: geometry.frame.midX, y: geometry.frame.midY)
                }
            }
        }
    }

    @ViewBuilder
    private func compactConnectionCTA(for surface: AiChatSkeletonSurfaceDisplayModel) -> some View {
        switch surface {
        case let .unconnected(connection):
            compactConnectionCTA(
                title: connection.title,
                detail: connection.detail,
                actionLabel: connection.fixLabel,
                action: { store.send(.openSettingsTapped) },
            )
        case let .error(connection):
            compactConnectionCTA(
                title: connection.title,
                detail: connection.detail,
                actionLabel: connection.fixLabel,
                action: { store.send(.errorRecoveryTapped) },
            )
        case .empty, .ready, .processing:
            EmptyView()
        }
    }

    private func compactConnectionCTA(
        title: String,
        detail: String,
        actionLabel: String,
        action: @escaping () -> Void,
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "bolt.horizontal.circle")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(VoyagerDS.Typography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Button(action: action) {
                Text(actionLabel)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: VoyagerDS.Radius.control, style: .continuous)
                            .fill(VoyagerDS.Surface.inputBackground(for: colorScheme)),
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: VoyagerDS.Radius.control, style: .continuous)
                            .strokeBorder(VoyagerDS.Surface.inputBorder(for: colorScheme), lineWidth: 1),
                    )
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
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

    private func transcriptSearchBar(state: AiChatState) -> some View {
        AiChatTranscriptSearchBar(
            search: state.transcriptSearch,
            focusRevision: state.transcriptSearch.focusRevision,
            onQueryChanged: { store.send(.transcriptSearchQueryChanged($0)) },
            onPrevious: { store.send(.transcriptSearchPreviousTapped) },
            onNext: { store.send(.transcriptSearchNextTapped) },
            onClose: closeTranscriptSearch,
        )
    }

    private func closeTranscriptSearch() {
        let shouldRestoreChatInputFocus = shouldRestoreChatInputFocusAfterSearch
        let composerIdentity = viewScope.composerIdentity(displayedSessionID: store.state.sessionID)
        shouldRestoreChatInputFocusAfterSearch = false
        store.send(.transcriptSearchClosed)
        guard shouldRestoreChatInputFocus else { return }
        Task { @MainActor [composerIdentity, inputFocusOwner] in
            inputFocusOwner.requestFocus(for: composerIdentity)
        }
    }

    private func navigateToCurrentSearchMatch(
        presentation: AiChatTranscriptSearchPresentation,
        currentMatch: AiChatRenderedTextMatchDescriptor?,
        proxy: ScrollViewProxy,
    ) {
        guard let target = Self.searchNavigationTarget(
            presentation: presentation,
            currentMatch: currentMatch,
        ) else { return }
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.18)) {
                proxy.scrollTo(target.scrollID, anchor: target.relativeAnchor)
            }
        }
    }

    static func searchNavigationTarget(
        presentation: AiChatTranscriptSearchPresentation,
        currentMatch: AiChatRenderedTextMatchDescriptor?,
    ) -> AiChatTranscriptMatchScrollTarget? {
        guard let currentMatch else { return nil }
        return presentation.scrollTarget(for: currentMatch)
    }

    private static func sessionsDisplayModel(for state: AiChatState) -> AiChatSessionsDisplayModel {
        AiChatSessionsDisplayModel(
            rows: state.sessionList.rows,
            now: Date(),
            query: state.sessionList.query,
            totalRowCount: state.sessionList.allRows.count,
            processingSessionID: state.executionPhase.processingSessionID,
            unreadCompletedSessionIDs: state.sessionList.unreadCompletedSessionIDs,
            hiddenSessionIDs: state.hiddenEmptyDraftSessionIDs,
        )
    }

    static func transcriptSearchCountText(_ search: AiChatTranscriptSearchState) -> String {
        "\(search.currentMatchOrdinal ?? 0)/\(search.matchCount ?? 0)"
    }

    static func shouldAutoScrollToBottom(transcriptSearch: AiChatTranscriptSearchState) -> Bool {
        !transcriptSearch.isPresented || transcriptSearch.navigationRevision == 0
    }

    private func inputBar(
        state: AiChatState,
        input: AiChatInputDisplayModel,
        requestContext: AiChatRequestContextDisplayModel,
    ) -> some View {
        let composerIdentity = viewScope.composerIdentity(displayedSessionID: state.sessionID)
        return AiChatInputBar(
            store: store,
            state: state,
            input: input,
            requestContext: requestContext,
            allowsAttachmentPicker: allowsAttachmentPicker,
            colorScheme: colorScheme,
            composerIdentity: composerIdentity,
            focusOwner: inputFocusOwner,
            chatInputTextHeight: $chatInputTextHeight,
        )
    }

    @ViewBuilder
    private func observeLifecycleAnnouncements(
        _ content: some View,
        announcement: AiChatLifecycleAnnouncement?,
    ) -> some View {
        if #available(macOS 14.0, *) {
            content.onChange(of: announcement, initial: false) { _, newAnnouncement in
                postLifecycleAnnouncement(newAnnouncement)
            }
        } else {
            content.onChange(of: announcement) { newAnnouncement in
                postLifecycleAnnouncement(newAnnouncement)
            }
        }
    }

    private func postLifecycleAnnouncement(_ announcement: AiChatLifecycleAnnouncement?) {
        guard let announcement else { return }
        accessibilityAnnouncementSink.post(announcement)
    }

    private func requestTranscriptScrollOffsetRestore(for state: AiChatState) {
        guard let sessionID = state.sessionID,
              let offsetY = store.withState({ $0.transcriptScrollOffsets[sessionID] })
        else { return }

        transcriptScrollRestoreSequence += 1
        transcriptScrollRestoreRequest = AiChatTranscriptScrollRestoreRequest(
            sessionID: sessionID,
            offsetY: offsetY,
            sequence: transcriptScrollRestoreSequence,
        )
    }

    private func scrollTranscriptToBottom(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.18)) {
                proxy.scrollTo(Self.transcriptBottomAnchorID, anchor: .bottom)
            }
        }
    }

    static let transcriptBottomAnchorID = "ai-chat-transcript-bottom"
}

enum AiChatViewPresentation: Equatable {
    case sessions
    case centeredEmpty
    case transcript

    static func resolve(state: AiChatState, hasCenteredEmptyContent: Bool) -> Self {
        guard state.mode == .chat else { return .sessions }
        guard hasCenteredEmptyContent,
              state.transcriptHistory.isEmpty,
              state.streamingAssistantDraft == nil,
              !state.isProcessing,
              state.sessionStatus != .restoring
        else { return .transcript }
        return .centeredEmpty
    }
}

struct AiChatTranscriptSearchButtonStyle {
    let size: CGFloat = 26
    let symbolSize: CGFloat = 11
    let symbolWeight: Font.Weight = .semibold
    let cornerRadius: CGFloat = VoyagerDS.Radius.control

    func hoverFill(
        isHovered: Bool,
        isEnabled: Bool,
        colorScheme: ColorScheme,
    ) -> Color? {
        guard isHovered, isEnabled else { return nil }
        return VoyagerDS.Interaction.controlHoverFill(for: colorScheme)
    }
}

private struct AiChatTranscriptSearchButtonLabel: View {
    let systemName: String

    @Environment(\.isEnabled)
    private var isEnabled
    @Environment(\.colorScheme)
    private var colorScheme
    @State private var isHovered = false

    private let style = AiChatTranscriptSearchButtonStyle()

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: style.symbolSize, weight: style.symbolWeight))
            .accessibilityHidden(true)
            .frame(width: style.size, height: style.size)
            .background {
                if let hoverFill = style.hoverFill(
                    isHovered: isHovered,
                    isEnabled: isEnabled,
                    colorScheme: colorScheme,
                ) {
                    RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
                        .fill(hoverFill)
                }
            }
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
    }
}

private struct AiChatTranscriptSearchBar: View {
    let search: AiChatTranscriptSearchState
    let focusRevision: UInt64
    let onQueryChanged: (String) -> Void
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onClose: () -> Void

    @FocusState private var isSearchFieldFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            searchField
            if !search.query.isEmpty {
                searchCount
            }
            searchButton(
                systemName: "chevron.up",
                accessibilityLabel: "Previous search result",
                isDisabled: search.status != .matches,
                action: onPrevious,
            )
            searchButton(
                systemName: "chevron.down",
                accessibilityLabel: "Next search result",
                isDisabled: search.status != .matches,
                action: onNext,
            )
            searchButton(
                systemName: "xmark",
                accessibilityLabel: "Close conversation search",
                isDisabled: false,
                action: onClose,
            )
        }
        .onAppear { isSearchFieldFocused = true }
        .onChange(of: focusRevision) { _ in isSearchFieldFocused = true }
        .onExitCommand(perform: onClose)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField(
                "Find in conversation",
                text: Binding(get: { search.query }, set: { onQueryChanged($0) }),
            )
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .focused($isSearchFieldFocused)
            .accessibilityLabel("Find in conversation")
            .onSubmit(onNext)
        }
        .padding(.horizontal, 9)
        .frame(minHeight: 28)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor)),
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1),
        )
    }

    private var searchCount: some View {
        let countText = AiChatView.transcriptSearchCountText(search)
        return VStack(alignment: .trailing, spacing: 1) {
            Text(countText)
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
            if search.status == .noResults {
                Text("No results")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Conversation search results")
        .accessibilityValue(search.status == .noResults ? "0 of 0, no results" : countText)
    }

    private func searchButton(
        systemName: String,
        accessibilityLabel: String,
        isDisabled: Bool,
        action: @escaping () -> Void,
    ) -> some View {
        Button(action: action) {
            AiChatTranscriptSearchButtonLabel(systemName: systemName)
        }
        .buttonStyle(.borderless)
        .disabled(isDisabled)
        .accessibilityLabel(accessibilityLabel)
        .help(accessibilityLabel)
    }
}

private struct AiChatTranscriptSearchRenderContext {
    let presentation: AiChatTranscriptSearchPresentation
    let currentMatch: AiChatRenderedTextMatchDescriptor?
    let matchCountProjection: AiChatTranscriptSearchMatchCountProjection?
}

@MainActor
private final class AiChatTranscriptSearchProjectionModel: ObservableObject {
    @Published private var projectionResult: AiChatTranscriptSearchProjectionResult?

    private let projector = AiChatTranscriptSearchProjector()
    private var requestCache = AiChatTranscriptSearchRequestCache()
    private var generation: UInt64 = 0

    func request(
        for state: AiChatState,
        renderSession: AiChatAssistantMarkdownRenderSession,
    ) -> AiChatTranscriptSearchProjectionRequest {
        requestCache.request(
            isPresented: state.transcriptSearch.isPresented,
            query: state.transcriptSearch.query,
            source: AiChatTranscriptSearchRequestSource(
                sessionToken: state.sessionID?.rawValue,
                messages: state.transcriptHistory,
                streamingAssistantContent: state.streamingAssistantDisplayModel?.content,
                transcriptRevision: state.transcriptHistoryMutationTracker.value,
                streamingRevision: state.streamingAssistantDraftMutationTracker.value,
            ),
            assistantRenderer: renderSession,
        )
    }

    func renderContext(
        for request: AiChatTranscriptSearchProjectionRequest,
        currentMatchOrdinal: Int?,
    ) -> AiChatTranscriptSearchRenderContext {
        let currentResult = projectionResult.flatMap { result in
            result.request == request ? result : nil
        }
        let presentation = currentResult?.presentation ?? .empty(query: request.query)
        return AiChatTranscriptSearchRenderContext(
            presentation: presentation,
            currentMatch: presentation.descriptor(atOrdinal: currentMatchOrdinal),
            matchCountProjection: currentResult?.presentation.matchCountProjection,
        )
    }

    func update(_ request: AiChatTranscriptSearchProjectionRequest) async {
        generation &+= 1
        let requestedGeneration = generation
        await projector.invalidate(generation: requestedGeneration)

        guard request.requiresWork else {
            projectionResult = nil
            _ = try? await projector.project(request, generation: requestedGeneration)
            return
        }

        do {
            let result = try await projector.project(request, generation: requestedGeneration)
            try Task.checkCancellation()
            guard requestedGeneration == generation,
                  result.isCurrent(request: request, generation: requestedGeneration)
            else { return }
            projectionResult = result
        } catch is CancellationError {
            // 대체된 projection은 결과를 게시하지 않고 종료합니다.
        } catch {
            // Projection 실패는 기존 검색 상태에 합성 오류를 추가하지 않습니다.
        }
    }
}
