import ComposableArchitecture
import SwiftUI
import VoyagerEntitiesAi
import VoyagerFeaturesAiChat

struct InspectorPaneView: View {
    let store: StoreOf<FileManagerInspectorFeature>

    @Environment(\.colorScheme)
    private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if store.activeMode == .chat {
                AiChatView(store: store.scope(state: \.aiChat, action: \.aiChat))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(.thickMaterial)
        .overlay(inspectorMaterialTint)
    }

    private var header: some View {
        HStack(spacing: 8) {
            if store.aiChat.mode == .sessions {
                Text("Sessions")
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)

                Spacer(minLength: 0)

                Button("New Chat") {
                    store.send(.sessionHeaderNewChatTapped)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
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
                .help("Back to Sessions")
                .accessibilityLabel("Back to Sessions")

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
        .padding(.horizontal, 16)
        .frame(height: 40)
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

    @ViewBuilder private var inspectorMaterialTint: some View {
        if colorScheme == .dark {
            Color.white.opacity(0.06)
                .allowsHitTesting(false)
        } else {
            Color.clear
                .allowsHitTesting(false)
        }
    }
}
