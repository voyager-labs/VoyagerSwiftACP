import ComposableArchitecture
import SwiftUI

struct AiChatInputBar: View {
    let store: StoreOf<AiChatFeature>
    let state: AiChatState
    let input: AiChatInputDisplayModel
    let colorScheme: ColorScheme

    @Binding var isChatInputFocused: Bool
    @Binding var chatInputTextHeight: CGFloat
    @Binding var isModelSelectorPopoverPresented: Bool
    @Binding var isThinkingSelectorPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            chatInputTextField

            HStack(alignment: .bottom, spacing: 4) {
                AiChatHoverTextAffordance(
                    title: input.contextAffordanceLabel,
                    systemName: nil,
                    titleFontSize: 14,
                    titleWeight: .semibold,
                    hoverColor: .primary
                )
                .fixedSize(horizontal: true, vertical: false)
                AiChatModelSelectorButton(
                    store: store,
                    state: state,
                    isPresented: $isModelSelectorPopoverPresented
                )
                AiChatThinkingSelectorButton(
                    store: store,
                    state: state,
                    input: input,
                    isPresented: $isThinkingSelectorPresented
                )
                Spacer(minLength: 2)
                chatInputActionButton
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

    private var chatInputTextField: some View {
        ZStack(alignment: .topLeading) {
            AiChatInputTextView(
                text: Binding(
                    get: { state.draftText },
                    set: { store.send(.draftTextChanged($0)) }
                ),
                isFocused: $isChatInputFocused,
                measuredHeight: $chatInputTextHeight,
                isDisabled: state.isProcessing,
                maxVisibleHeight: AiChatView.chatInputMaxTextHeight,
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
        .frame(minHeight: AiChatView.chatInputMinTextHeight, alignment: .topLeading)
        .padding(.top, 2)
    }

    private var boundedChatInputTextHeight: CGFloat {
        min(
            max(chatInputTextHeight, AiChatView.chatInputMinTextHeight),
            AiChatView.chatInputMaxTextHeight
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

    private var chatInputActionButton: some View {
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
}
