import AppKit
import ComposableArchitecture
import SwiftUI
import VoyagerEntitiesAi
import VoyagerFeaturesAiChat
import VoyagerFeaturesContentPageNavigation

/// AI Chat ContentPane 전용 페이지.
///
/// `FileManagerContentPaneView`에서 `activePageAnchor == .aiChat`일 때 렌더링된다.
/// - `mode == .chat`: thin header + AiChatView (빈 상태 시 Ask Voyager 오버레이)
/// - `mode == .sessions`: thin header + AiChatView이 내부적으로 AiChatSessionsView 렌더링
struct FileManagerAiChatPageView: View {
    let store: StoreOf<FileManagerContentFeature>
    let chromeProps: FileManagerContentChromeProps
    let onNavigationAction: (ContentPageNavigationAction.View) -> Void

    struct ViewState: Equatable {
        let mode: AiChatMode
        let sessionList: AiChatSessionListState
        let sessionID: AiChatSessionID?
        let firstUserMessageContent: String?
        let backHistoryItems: [ToolbarHistoryItem]
        let forwardHistoryItems: [ToolbarHistoryItem]
        let canGoBack: Bool
        let canGoForward: Bool
    }

    var body: some View {
        WithViewStore(
            store,
            observe: { state in
                let homePath = NSHomeDirectory()
                return ViewState(
                    mode: state.aiChat.mode,
                    sessionList: state.aiChat.sessionList,
                    sessionID: state.aiChat.sessionID,
                    firstUserMessageContent: state.aiChat.transcriptHistory.first(where: { $0.role == .user })?.content,
                    backHistoryItems: state.navigation.backHistory.map { snapshot in
                        historyItem(for: snapshot, homePath: homePath, sessionList: state.aiChat.sessionList)
                    },
                    forwardHistoryItems: state.navigation.forwardHistory.map { snapshot in
                        historyItem(for: snapshot, homePath: homePath, sessionList: state.aiChat.sessionList)
                    },
                    canGoBack: state.navigation.canGoBack,
                    canGoForward: state.navigation.canGoForward,
                )
            },
            content: { viewStore in
                WithPerceptionTracking {
                    VStack(spacing: 0) {
                        AiChatPageHeaderView(
                            viewState: viewStore.state,
                            store: store,
                            onNavigationAction: onNavigationAction,
                        )
                        .zIndex(1)

                        GeometryReader { proxy in
                            AiChatView(
                                store: store.scope(state: \.aiChat, action: \.aiChat),
                                centeredEmptyContent: AnyView(AiChatEmptyStateContent()),
                                onSessionSelected: { sessionID in
                                    store.send(.aiChat(.sessionRowTapped(sessionID)))
                                },
                            )
                            .padding(.horizontal, contentHorizontalPadding(for: proxy.size.width))
                            .frame(width: proxy.size.width, height: proxy.size.height)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .transaction { transaction in
                        transaction.animation = nil
                    }
                }
            },
        )
    }

    private func contentHorizontalPadding(for width: CGFloat) -> CGFloat {
        min(176, max(72, width * 0.12))
    }

    private func displayName(for path: String) -> String {
        if path == "/" {
            return chromeProps.computerName.isEmpty ? "Computer" : chromeProps.computerName
        }

        if let cached = chromeProps.pathDisplayNames[path], !cached.isEmpty {
            return cached
        }

        let fallback = URL(fileURLWithPath: path).lastPathComponent
        return fallback.isEmpty ? path : fallback
    }

    private func iconSystemName(forDirectoryPath path: String, homePath: String) -> String {
        if path == "/" {
            return "internaldrive"
        }
        if path == homePath {
            return "house"
        }
        if path.hasPrefix("/Volumes/") {
            return "externaldrive"
        }
        if let mapped = chromeProps.specialDirectoryIconNames[path] {
            return mapped
        }
        return "folder"
    }

    private func historyItem(
        for snapshot: ContentPageNavigationHistorySnapshot,
        homePath: String,
        sessionList: AiChatSessionListState,
    ) -> ToolbarHistoryItem {
        switch snapshot.navigationState {
        case .home:
            return ToolbarHistoryItem(iconSystemName: "house", title: "Home")
        case let .folder(path):
            return ToolbarHistoryItem(
                iconSystemName: iconSystemName(forDirectoryPath: path, homePath: homePath),
                title: displayName(for: path),
            )
        case .recents:
            return ToolbarHistoryItem(iconSystemName: "clock.arrow.circlepath", title: "Recents")
        case let .tags(tagName):
            return ToolbarHistoryItem(iconSystemName: "tag", title: tagName)
        case .computer:
            return ToolbarHistoryItem(
                iconSystemName: "internaldrive",
                title: chromeProps.computerName.isEmpty ? "Computer" : chromeProps.computerName,
            )
        case let .aiChat(sessionID):
            return ToolbarHistoryItem(
                iconSystemName: "bubble.left.and.text.bubble.right",
                title: aiChatHistoryTitle(for: sessionID, sessionList: sessionList),
            )
        case .aiChatSessions:
            return ToolbarHistoryItem(iconSystemName: "clock.arrow.circlepath", title: "Chat History")
        case let .collection(navigation):
            let title: String = switch navigation.kind {
            case .temporary:
                "New Collection"
            case let .file(_, name):
                name
            }
            return ToolbarHistoryItem(iconSystemName: "rectangle.stack", title: title)
        }
    }

    private func aiChatHistoryTitle(
        for sessionID: String,
        sessionList: AiChatSessionListState,
    ) -> String {
        guard let sessionUUID = UUID(uuidString: sessionID),
              let summary = sessionList.allRows.first(where: { $0.sessionID.rawValue == sessionUUID })
        else {
            return "Ask Voyager"
        }

        return normalizedAiChatTitle(summary.title)
    }

    private func normalizedAiChatTitle(_ title: String) -> String {
        title == "New Chat" ? "Ask Voyager" : title
    }
}

// MARK: - Header

private struct AiChatPageHeaderView: View {
    let viewState: FileManagerAiChatPageView.ViewState
    let store: StoreOf<FileManagerContentFeature>
    let onNavigationAction: (ContentPageNavigationAction.View) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ToolbarNavigationButtons(
                onNavigationAction: onNavigationAction,
                backHistoryItems: viewState.backHistoryItems,
                forwardHistoryItems: viewState.forwardHistoryItems,
                canGoBack: viewState.canGoBack,
                canGoForward: viewState.canGoForward,
                canGoToEnclosingDirectory: true,
                enclosingDirectorySystemName: viewState.mode == .sessions ? "bubble.right" : "clock.arrow.circlepath",
                enclosingDirectoryHelp: viewState.mode == .sessions ? "Return to chat" : "Show Chat History",
                enclosingDirectoryAction: aiChatToggleAction,
            )

            Text(headerTitle)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 0)

            if viewState.mode == .sessions {
                Button {
                    store.send(.aiChat(.newChatTapped))
                } label: {
                    newChatButtonLabel
                }
                .buttonStyle(.borderless)
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .help("Start New Chat")
                .accessibilityLabel("Start New Chat")
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 40)
        .contentShape(Rectangle())
        .background(.ultraThinMaterial)
        .overlay(
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 1)
                .allowsHitTesting(false),
            alignment: .bottom,
        )
    }

    private var aiChatToggleAction: () -> Void {
        {
            guard let sessionID = viewState.sessionID?.rawValue.uuidString else { return }
            switch viewState.mode {
            case .chat:
                onNavigationAction(.showAiChatSessions(sessionID))
            case .sessions:
                onNavigationAction(.showAiChat(sessionID))
            }
        }
    }

    private var headerTitle: String {
        switch viewState.mode {
        case .sessions:
            "Chat History"
        case .chat:
            chatHeaderTitle
        }
    }

    private var chatHeaderTitle: String {
        if let selectedSessionID = viewState.sessionList.selectedSessionID,
           let selectedSummary = viewState.sessionList.allRows.first(where: { $0.sessionID == selectedSessionID })
        {
            return normalizedAiChatTitle(selectedSummary.title)
        }

        if let sessionID = viewState.sessionID,
           let currentSummary = viewState.sessionList.allRows.first(where: { $0.sessionID == sessionID })
        {
            return normalizedAiChatTitle(currentSummary.title)
        }

        if let firstUserMessageContent = viewState.firstUserMessageContent {
            let normalizedTitle = firstUserMessageContent
                .split(whereSeparator: \.isWhitespace)
                .joined(separator: " ")
            if !normalizedTitle.isEmpty {
                return String(normalizedTitle.prefix(80))
            }
        }

        return "Ask Voyager"
    }

    private func normalizedAiChatTitle(_ title: String) -> String {
        title == "New Chat" ? "Ask Voyager" : title
    }

    private var newChatButtonLabel: some View {
        ToolbarHoverPillButtonLabel(title: "New Chat", isEnabled: true)
    }
}

// MARK: - Ask Voyager Empty State

private struct AiChatEmptyStateContent: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: voyagerIconImage)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)

            Text("Ask Voyager")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.primary)

            Text("Explore your files, collections, and ideas with Voyager.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
        }
        .frame(maxWidth: 300)
    }

    private var voyagerIconImage: NSImage {
        NSImage(named: "AppIcon") ?? NSApp.applicationIconImage
    }
}
