import ComposableArchitecture
import Perception
import SwiftUI
import VoyagerEntitiesAi

public struct AiChatView: View {
    let store: StoreOf<AiChatFeature>

    @Environment(\.colorScheme)
    var colorScheme

    @State var isChatInputFocused = false
    @State var chatInputTextHeight = Self.chatInputMinTextHeight
    @State var isModelSelectorPopoverPresented = false
    @State var isThinkingSelectorPresented = false

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
                            AiChatConversationSurface(
                                state: state,
                                skeleton: skeleton,
                                onOpenSettings: { store.send(.openSettingsTapped) },
                                onErrorRecovery: { store.send(.errorRecoveryTapped) }
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
                    .onChange(of: transcriptScrollSignature(state: state)) { _ in
                        scrollTranscriptToBottom(scrollProxy)
                    }

                    AiChatInputBar(
                        store: store,
                        state: state,
                        input: skeleton.chatInput,
                        colorScheme: colorScheme,
                        isChatInputFocused: $isChatInputFocused,
                        chatInputTextHeight: $chatInputTextHeight,
                        isModelSelectorPopoverPresented: $isModelSelectorPopoverPresented,
                        isThinkingSelectorPresented: $isThinkingSelectorPresented
                    )
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
            state.streamingAssistantDisplayModel?.content ?? "",
            state.streamingAssistantDisplayModel?.failure?.displayMessage ?? "",
            String(state.isProcessing),
            state.requestStatusText ?? ""
        ].joined(separator: "|")
    }

    private func scrollTranscriptToBottom(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.18)) {
                proxy.scrollTo(Self.transcriptBottomAnchorID, anchor: .bottom)
            }
        }
    }

    static let transcriptBottomAnchorID = "ai-chat-transcript-bottom"
    static let chatInputMinTextHeight: CGFloat = 34
    static let chatInputMaxTextHeight: CGFloat = 96
}
