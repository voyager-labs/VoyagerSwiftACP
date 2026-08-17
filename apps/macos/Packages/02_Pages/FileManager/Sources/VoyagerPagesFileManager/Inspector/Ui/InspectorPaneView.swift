import ComposableArchitecture
import SwiftUI
import VoyagerEntitiesAi
import VoyagerFeaturesAiChat

struct InspectorPaneView: View {
    let store: StoreOf<FileManagerInspectorFeature>

    var body: some View {
        WithPerceptionTracking {
            VStack(alignment: .leading, spacing: 0) {
                header
                Divider()

                if store.activeMode == .chat {
                    AiChatView(
                        store: store.scope(state: \.aiChat, action: \.aiChat),
                        allowsAttachmentPicker: true,
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            .frame(maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var header: some View {
        HStack(spacing: store.aiChat.mode == .chat ? 4 : 8) {
            if store.aiChat.mode == .sessions {
                Text("Chat History")
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)

                Spacer(minLength: 0)

                Button {
                    store.send(.sessionHeaderNewChatTapped)
                } label: {
                    newChatButtonLabel
                }
                .buttonStyle(.borderless)
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .help("Start New Chat")
                .accessibilityLabel("Start New Chat")
            } else {
                Button {
                    store.send(.sessionHeaderBackTapped)
                } label: {
                    backButtonLabel
                }
                .buttonStyle(.borderless)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
                .help("Back to Chat History")
                .accessibilityLabel("Back to Chat History")

                Text(chatHeaderTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 0)
            }

            Button {
                store.send(.closeChat)
            } label: {
                closeButtonLabel
            }
            .buttonStyle(.borderless)
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
            .help("Close AI Chat")
            .accessibilityLabel("Close AI Chat")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, store.aiChat.mode == .chat ? 8 : 16)
        .padding(.trailing, 16)
        .frame(height: 40)
    }

    private var newChatButtonLabel: some View {
        ToolbarHoverPillButtonLabel(title: "New Chat", isEnabled: true)
    }

    private var chatHeaderTitle: String {
        if let selectedSessionID = store.aiChat.sessionList.selectedSessionID,
           let selectedSummary = store.aiChat.sessionList.allRows.first(where: { $0.sessionID == selectedSessionID })
        {
            return selectedSummary.title
        }

        if let sessionID = store.aiChat.sessionID,
           let currentSummary = store.aiChat.sessionList.allRows.first(where: { $0.sessionID == sessionID })
        {
            return currentSummary.title
        }

        if let firstUserMessage = store.aiChat.transcriptHistory.first(where: { $0.role == .user }) {
            let normalizedTitle = firstUserMessage.content
                .split(whereSeparator: \.isWhitespace)
                .joined(separator: " ")
            if !normalizedTitle.isEmpty {
                return String(normalizedTitle.prefix(80))
            }
        }

        return "New Chat"
    }

    private var backButtonLabel: some View {
        ToolbarHoverButtonLabel(
            systemName: "chevron.left",
            isEnabled: true,
            font: nil,
        )
    }

    private var closeButtonLabel: some View {
        ToolbarHoverButtonLabel(
            systemName: "sidebar.trailing",
            isEnabled: true,
            font: nil,
        )
    }
}
