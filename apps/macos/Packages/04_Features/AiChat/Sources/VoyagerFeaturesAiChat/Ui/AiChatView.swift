import AppKit
import ComposableArchitecture
import Perception
import SwiftUI
import VoyagerEntitiesAi
import VoyagerShared

public struct AiChatView: View {
    let store: StoreOf<AiChatFeature>
    let centeredEmptyContent: AnyView?
    let onSessionSelected: ((AiChatSessionID) -> Void)?

    @Environment(\.colorScheme)
    var colorScheme

    @State private var isChatInputFocused = false
    @State private var chatInputTextHeight = Self.chatInputMinTextHeight
    @State private var isModelSelectorPopoverPresented = false
    @State private var isThinkingSelectorPresented = false
    @State private var transcriptScrollRestoreRequest: AiChatTranscriptScrollRestoreRequest?
    @State private var transcriptScrollRestoreSequence = 0
    @State private var transcriptSearchFocusRevision: UInt64 = 0
    @State private var shouldRestoreChatInputFocusAfterSearch = false
    @State private var lastNavigatedSearchTargetID: AiChatTranscriptMatchAnchor?
    @StateObject private var transcriptSearchProjection = AiChatTranscriptSearchProjectionModel()

    public init(
        store: StoreOf<AiChatFeature>,
        centeredEmptyContent: AnyView? = nil,
        onSessionSelected: ((AiChatSessionID) -> Void)? = nil,
    ) {
        self.store = store
        self.centeredEmptyContent = centeredEmptyContent
        self.onSessionSelected = onSessionSelected
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
        let searchRequest = transcriptSearchProjection.request(for: state)
        let searchContext = transcriptSearchProjection.renderContext(
            for: searchRequest,
            currentMatchOrdinal: state.transcriptSearch.currentMatchOrdinal,
        )
        let sessions = Self.sessionsDisplayModel(for: state)

        Group {
            if state.mode == .sessions {
                AiChatSessionsView(
                    store: store,
                    state: state,
                    displayModel: sessions,
                    onSessionSelected: onSessionSelected,
                )
            } else if let centeredEmptyContent, isCenteredEmptyChat(state: state) {
                centeredEmptyChatView(
                    centeredEmptyContent: centeredEmptyContent,
                    state: state,
                    skeleton: skeleton,
                    requestContext: requestContext,
                )
            } else {
                conversationView(
                    state: state,
                    skeleton: skeleton,
                    requestContext: requestContext,
                    searchPresentation: searchContext.presentation,
                    currentSearchMatch: searchContext.currentMatch,
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
            shouldRestoreChatInputFocusAfterSearch = isChatInputFocused
            transcriptSearchFocusRevision &+= 1
        }
    }

    private func conversationView(
        state: AiChatState,
        skeleton: AiChatSkeletonDisplayModel,
        requestContext: AiChatRequestContextDisplayModel,
        searchPresentation: AiChatTranscriptSearchPresentation,
        currentSearchMatch: AiChatRenderedTextMatchDescriptor?,
    ) -> some View {
        ScrollViewReader { scrollProxy in
            VStack(spacing: 0) {
                if state.transcriptSearch.isPresented {
                    transcriptSearchBar(state: state)
                        .padding(.horizontal, 10)
                        .padding(.top, 10)
                        .padding(.bottom, 2)
                }

                transcriptScrollView(
                    state: state,
                    skeleton: skeleton,
                    searchPresentation: searchPresentation,
                    currentSearchMatch: currentSearchMatch,
                )
                .onAppear {
                    requestTranscriptScrollOffsetRestore(for: state)
                }
                .onChange(of: state.sessionID) { _ in
                    requestTranscriptScrollOffsetRestore(for: state)
                }
                .onChange(of: state.transcriptAutoScrollVersion) { _ in
                    guard Self.shouldAutoScrollToBottom(transcriptSearch: state.transcriptSearch) else { return }
                    scrollTranscriptToBottom(scrollProxy)
                }
                .onChange(of: state.transcriptSearch.navigationRevision) { _ in
                    navigateToCurrentSearchMatch(
                        presentation: searchPresentation,
                        currentMatch: currentSearchMatch,
                        proxy: scrollProxy,
                    )
                }
                .onChange(of: state.transcriptSearch.query) { _ in
                    lastNavigatedSearchTargetID = nil
                }

                inputBar(
                    state: state,
                    input: skeleton.chatInput,
                    requestContext: requestContext,
                )
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private func transcriptScrollView(
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

    private func isCenteredEmptyChat(state: AiChatState) -> Bool {
        state.transcriptHistory.isEmpty
            && state.streamingAssistantDraft == nil
            && !state.executionPhase.isProcessing
            && state.sessionStatus != .restoring
    }

    private func centeredEmptyChatView(
        centeredEmptyContent: AnyView,
        state: AiChatState,
        skeleton: AiChatSkeletonDisplayModel,
        requestContext: AiChatRequestContextDisplayModel,
    ) -> some View {
        VStack(spacing: 0) {
            if state.transcriptSearch.isPresented {
                transcriptSearchBar(state: state)
                    .padding(.horizontal, 10)
                    .padding(.top, 10)
            }

            VStack(spacing: 20) {
                Spacer(minLength: 0)
                centeredEmptyContent
                compactConnectionCTA(for: skeleton.surface)
                inputBar(
                    state: state,
                    input: skeleton.chatInput,
                    requestContext: requestContext,
                )
                Spacer(minLength: 0)
            }
            .padding(.vertical, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                    .font(.system(size: 12))
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
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.primary.opacity(0.06)),
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1),
                    )
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.primary.opacity(0.045)),
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1),
        )
    }

    private func transcriptSearchBar(state: AiChatState) -> some View {
        AiChatTranscriptSearchBar(
            search: state.transcriptSearch,
            focusRevision: transcriptSearchFocusRevision,
            onQueryChanged: { store.send(.transcriptSearchQueryChanged($0)) },
            onPrevious: { store.send(.transcriptSearchPreviousTapped) },
            onNext: { store.send(.transcriptSearchNextTapped) },
            onClose: closeTranscriptSearch,
        )
    }

    private func closeTranscriptSearch() {
        let shouldRestoreChatInputFocus = shouldRestoreChatInputFocusAfterSearch
        shouldRestoreChatInputFocusAfterSearch = false
        lastNavigatedSearchTargetID = nil
        store.send(.transcriptSearchClosed)
        guard shouldRestoreChatInputFocus else { return }
        DispatchQueue.main.async {
            isChatInputFocused = true
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
            lastTargetID: lastNavigatedSearchTargetID,
        ) else { return }
        lastNavigatedSearchTargetID = target.id
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.18)) {
                proxy.scrollTo(target.scrollID, anchor: target.relativeAnchor)
            }
        }
    }

    static func searchNavigationTarget(
        presentation: AiChatTranscriptSearchPresentation,
        currentMatch: AiChatRenderedTextMatchDescriptor?,
        lastTargetID: AiChatTranscriptMatchAnchor?,
    ) -> AiChatTranscriptMatchScrollTarget? {
        guard let currentMatch,
              let target = presentation.scrollTarget(for: currentMatch),
              target.id != lastTargetID
        else { return nil }
        return target
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
        AiChatInputBar(
            store: store,
            state: state,
            input: input,
            requestContext: requestContext,
            colorScheme: colorScheme,
            isChatInputFocused: $isChatInputFocused,
            chatInputTextHeight: $chatInputTextHeight,
            isModelSelectorPopoverPresented: $isModelSelectorPopoverPresented,
            isThinkingSelectorPresented: $isThinkingSelectorPresented,
        )
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
    static let chatInputMinTextHeight: CGFloat = 46
    static let chatInputMaxTextHeight: CGFloat = 160
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

    func request(for state: AiChatState) -> AiChatTranscriptSearchProjectionRequest {
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

private struct AiChatTranscriptScrollRestoreRequest: Equatable {
    let sessionID: AiChatSessionID
    let offsetY: CGFloat
    let sequence: Int
}

private struct AiChatTranscriptScrollObserver: NSViewRepresentable {
    let sessionID: AiChatSessionID?
    let restoreRequest: AiChatTranscriptScrollRestoreRequest?
    let onScrollOffsetChanged: (CGFloat, AiChatSessionID?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            context.coordinator.attachScrollView(from: view)
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.sessionID = sessionID
        context.coordinator.onScrollOffsetChanged = onScrollOffsetChanged

        DispatchQueue.main.async {
            context.coordinator.attachScrollView(from: view)
            context.coordinator.applyRestoreRequestIfNeeded(restoreRequest)
            DispatchQueue.main.async {
                context.coordinator.attachScrollView(from: view)
                context.coordinator.applyRestoreRequestIfNeeded(restoreRequest)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    @MainActor
    final class Coordinator: NSObject {
        var sessionID: AiChatSessionID?
        var onScrollOffsetChanged: ((CGFloat, AiChatSessionID?) -> Void)?

        private weak var scrollView: NSScrollView?
        private weak var observedClipView: NSClipView?
        private var appliedRestoreSequence: Int?
        private var isApplyingRestore = false

        deinit {
            if let observedClipView {
                NotificationCenter.default.removeObserver(
                    self,
                    name: NSView.boundsDidChangeNotification,
                    object: observedClipView,
                )
            }
        }

        func attachScrollView(from view: NSView) {
            guard scrollView == nil else { return }
            guard let scrollView = view.enclosingScrollView ?? view.firstEnclosingScrollViewInSuperviewChain()
            else { return }

            self.scrollView = scrollView
            let clipView = scrollView.contentView
            observedClipView = clipView
            clipView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(boundsDidChange(_:)),
                name: NSView.boundsDidChangeNotification,
                object: clipView,
            )

            onScrollOffsetChanged?(clipView.bounds.origin.y, sessionID)
        }

        func applyRestoreRequestIfNeeded(_ request: AiChatTranscriptScrollRestoreRequest?) {
            guard let request, appliedRestoreSequence != request.sequence else { return }
            appliedRestoreSequence = request.sequence

            DispatchQueue.main.async { [weak self] in
                self?.restore(to: request.offsetY)
                DispatchQueue.main.async { [weak self] in
                    self?.restore(to: request.offsetY)
                }
            }
        }

        private func restore(to requestedOffsetY: CGFloat) {
            guard let scrollView else { return }

            let clipView = scrollView.contentView
            let documentHeight = scrollView.documentView?.bounds.height ?? 0
            let maxOffsetY = max(0, documentHeight - clipView.bounds.height)
            let offsetY = min(max(0, requestedOffsetY), maxOffsetY)

            isApplyingRestore = true
            clipView.scroll(to: NSPoint(x: clipView.bounds.origin.x, y: offsetY))
            scrollView.reflectScrolledClipView(clipView)
            onScrollOffsetChanged?(offsetY, sessionID)

            DispatchQueue.main.async { [weak self] in
                self?.isApplyingRestore = false
            }
        }

        @objc
        private func boundsDidChange(_ notification: Notification) {
            guard !isApplyingRestore,
                  let clipView = notification.object as? NSClipView
            else { return }

            onScrollOffsetChanged?(clipView.bounds.origin.y, sessionID)
        }
    }
}

private extension NSView {
    func firstEnclosingScrollViewInSuperviewChain() -> NSScrollView? {
        var current = superview
        while let view = current {
            if let scrollView = view as? NSScrollView {
                return scrollView
            }
            current = view.superview
        }
        return nil
    }
}
