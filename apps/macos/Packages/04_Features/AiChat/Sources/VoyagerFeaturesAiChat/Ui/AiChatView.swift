import AppKit
import ComposableArchitecture
import Perception
import SwiftUI
import VoyagerEntitiesAi

public struct AiChatView: View {
    let store: StoreOf<AiChatFeature>

    @Environment(\.colorScheme)
    var colorScheme

    @State private var isChatInputFocused = false
    @State private var chatInputTextHeight = Self.chatInputMinTextHeight
    @State private var isModelSelectorPopoverPresented = false
    @State private var isThinkingSelectorPresented = false
    @State private var transcriptScrollRestoreRequest: AiChatTranscriptScrollRestoreRequest?
    @State private var transcriptScrollRestoreSequence = 0

    public init(store: StoreOf<AiChatFeature>) {
        self.store = store
    }

    public var body: some View {
        WithPerceptionTracking {
            let state = store.state
            let builder = AiChatStateDisplayModelBuilder(state: state)
            let skeleton = state.skeletonDisplayModel
            let requestContext = builder.requestContextDisplayModel
            let sessions = AiChatSessionsDisplayModel(
                rows: state.sessionList.rows,
                now: Date(),
                query: state.sessionList.query,
                totalRowCount: state.sessionList.allRows.count,
                processingSessionID: state.executionPhase.processingSessionID,
                unreadCompletedSessionIDs: state.sessionList.unreadCompletedSessionIDs,
                hiddenSessionIDs: state.hiddenEmptyDraftSessionIDs,
            )

            Group {
                if state.mode == .sessions {
                    AiChatSessionsView(store: store, state: state, displayModel: sessions)
                } else {
                    ScrollViewReader { scrollProxy in
                        VStack(spacing: 0) {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 12) {
                                    AiChatConversationSurface(
                                        state: state,
                                        skeleton: skeleton,
                                        onOpenSettings: { store.send(.openSettingsTapped) },
                                        onErrorRecovery: { store.send(.errorRecoveryTapped) },
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
                            .onAppear {
                                requestTranscriptScrollOffsetRestore(for: state)
                            }
                            .onChange(of: state.sessionID) { _ in
                                requestTranscriptScrollOffsetRestore(for: state)
                            }
                            .onChange(of: state.transcriptAutoScrollVersion) { _ in
                                scrollTranscriptToBottom(scrollProxy)
                            }

                            AiChatInputBar(
                                store: store,
                                state: state,
                                input: skeleton.chatInput,
                                requestContext: requestContext,
                                colorScheme: colorScheme,
                                isChatInputFocused: $isChatInputFocused,
                                chatInputTextHeight: $chatInputTextHeight,
                                isModelSelectorPopoverPresented: $isModelSelectorPopoverPresented,
                                isThinkingSelectorPresented: $isThinkingSelectorPresented,
                            )
                            .padding(.horizontal, 10)
                            .padding(.top, 8)
                            .padding(.bottom, 10)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    }
                }
            }
            .onAppear {
                store.send(.onAppear)
            }
        }
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
    static let chatInputMinTextHeight: CGFloat = 34
    static let chatInputMaxTextHeight: CGFloat = 96
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
