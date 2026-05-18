import AppKit
import ComposableArchitecture
import SwiftUI

struct AiChatInputBar: View {
    let store: StoreOf<AiChatFeature>
    let state: AiChatState
    let input: AiChatInputDisplayModel
    let requestContext: AiChatRequestContextDisplayModel
    let colorScheme: ColorScheme

    @Binding var isChatInputFocused: Bool
    @Binding var chatInputTextHeight: CGFloat
    @Binding var isModelSelectorPopoverPresented: Bool
    @Binding var isThinkingSelectorPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            requestContextRow

            chatInputTextField

            HStack(alignment: .bottom, spacing: 4) {
                Button {
                    store.send(.attachmentPickerTapped)
                } label: {
                    AiChatHoverTextAffordance(
                        title: input.contextAffordanceLabel,
                        systemName: nil,
                        titleFontSize: 14,
                        titleWeight: .semibold,
                        hoverColor: .primary
                    )
                    .fixedSize(horizontal: true, vertical: false)
                }
                .buttonStyle(.plain)
                HStack(alignment: .bottom, spacing: 8) {
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
                }
                .layoutPriority(1)
                Spacer(minLength: 0)
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
                    .lineLimit(1)
                    .truncationMode(.tail)
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
            .font(.system(size: 8, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 24, height: 24)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary)
            )
            .opacity(1)
    }
}

private extension AiChatInputBar {
    @ViewBuilder var requestContextRow: some View {
        if !requestContext.isEmpty {
            AiChatRequestContextRow(store: store, displayModel: requestContext)
        }
    }
}

private struct AiChatRequestContextRow: View {
    let store: StoreOf<AiChatFeature>
    let displayModel: AiChatRequestContextDisplayModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let currentContext = displayModel.currentContext {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .center, spacing: 8) {
                        groupLabel("Current context")
                        currentContextChip(currentContext)
                    }
                }
            }

            if !displayModel.addedAttachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .center, spacing: 8) {
                        groupLabel("Attachments")
                        ForEach(displayModel.addedAttachments) { attachment in
                            attachmentChip(attachment)
                        }
                    }
                }
            }
        }
    }

    private func groupLabel(_ title: String) -> some View {
        Text(title)
            .font(chipTitleFont)
            .foregroundStyle(.secondary)
    }

    private func currentContextChip(_ chip: AiChatCurrentContextChipDisplayModel) -> some View {
        removableChip(
            title: chip.title,
            help: chip.detail ?? chip.title,
            iconSystemName: chip.iconSystemName,
            iconAssetName: chip.iconAssetName,
            iconFilePath: chip.iconFilePath,
            isRemovable: false,
            accessibilityLabel: "Current context"
        ) {}
    }

    private func attachmentChip(_ chip: AiChatAddedAttachmentChipDisplayModel) -> some View {
        removableChip(
            title: chip.title,
            help: chip.statusLabel.isEmpty ? chip.title : "\(chip.title) · \(chip.statusLabel)",
            iconSystemName: chip.iconSystemName,
            iconAssetName: chip.iconAssetName,
            iconFilePath: chip.iconFilePath,
            isRemovable: chip.isRemovable,
            accessibilityLabel: "Remove attachment"
        ) {
            store.send(.removeAddedAttachment(chip.attachmentID))
        }
    }

    private func removableChip(
        title: String,
        help: String,
        iconSystemName: String?,
        iconAssetName: String?,
        iconFilePath: String?,
        isRemovable: Bool,
        accessibilityLabel: String,
        remove: @escaping () -> Void
    ) -> some View {
        AiChatRemovableRequestContextChip(
            title: title,
            help: help,
            iconSystemName: iconSystemName,
            iconAssetName: iconAssetName,
            iconFilePath: iconFilePath,
            isRemovable: isRemovable,
            accessibilityLabel: accessibilityLabel,
            remove: remove
        )
    }

    private var chipTitleFont: Font { .system(size: 11, weight: .medium) }
}

private struct AiChatRemovableRequestContextChip: View {
    let title: String
    let help: String
    let iconSystemName: String?
    let iconAssetName: String?
    let iconFilePath: String?
    let isRemovable: Bool
    let accessibilityLabel: String
    let remove: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 4) {
            chipIcon
            Text(title)
                .font(chipTitleFont)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)

            if isRemovable {
                Button(action: remove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(isHovering ? .primary : .secondary)
                        .frame(width: 14, height: 14)
                        .background(
                            Circle()
                                .fill(isHovering ? Color.primary.opacity(0.08) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(accessibilityLabel)
            }
        }
        .padding(.horizontal, chipHorizontalPadding)
        .padding(.vertical, chipVerticalPadding)
        .background(chipBackground)
        .overlay(chipBorder)
        .clipShape(Capsule(style: .continuous))
        .help(help)
        .onHover { isHovering = $0 }
    }

    @ViewBuilder private var chipIcon: some View {
        if let iconFilePath {
            Image(nsImage: NSWorkspace.shared.icon(forFile: iconFilePath))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 11, height: 11)
        } else if let iconAssetName {
            Image(iconAssetName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 11, height: 11)
        } else if let iconSystemName {
            Image(systemName: iconSystemName)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private var chipTitleFont: Font { .system(size: 11, weight: .medium) }
    private var chipHorizontalPadding: CGFloat { 8 }
    private var chipVerticalPadding: CGFloat { 4 }

    private var chipBackground: some View {
        Capsule(style: .continuous)
            .fill(Color(nsColor: .controlBackgroundColor))
    }

    private var chipBorder: some View {
        Capsule(style: .continuous)
            .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
    }
}
