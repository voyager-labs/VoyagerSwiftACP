import AppKit
import ComposableArchitecture
import SwiftUI
import UniformTypeIdentifiers
import VoyagerEntitiesAi

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
                        hoverColor: .primary,
                    )
                    .fixedSize(horizontal: true, vertical: false)
                }
                .buttonStyle(.plain)
                HStack(alignment: .bottom, spacing: 8) {
                    AiChatModelSelectorButton(
                        store: store,
                        state: state,
                        isPresented: $isModelSelectorPopoverPresented,
                    )
                    AiChatThinkingSelectorButton(
                        store: store,
                        state: state,
                        input: input,
                        isPresented: $isThinkingSelectorPresented,
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
                .fill(chatInputBackground),
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(chatInputBorder, lineWidth: 1),
        )
        .onDrop(of: attachmentDropTypeIdentifiers, isTargeted: nil) { providers in
            handleAttachmentDrop(providers)
        }
    }

    private var chatInputTextField: some View {
        ZStack(alignment: .topLeading) {
            AiChatInputTextView(
                text: Binding(
                    get: { state.draftText },
                    set: { store.send(.draftTextChanged($0)) },
                ),
                isFocused: $isChatInputFocused,
                measuredHeight: $chatInputTextHeight,
                isDisabled: state.isProcessing,
                maxVisibleHeight: AiChatView.chatInputMaxTextHeight,
                onSubmit: { submitAndRestoreInputFocus() },
                onAttachmentsDropped: { urls in
                    acceptDroppedAttachments(urls)
                },
            )
            .frame(height: boundedChatInputTextHeight)
            .accessibilityLabel(input.inputAccessibilityLabel)
            .accessibilityHint(input.inputAccessibilityHint)

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
            AiChatView.chatInputMaxTextHeight,
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
                .help(input.actionHelp)
                .accessibilityLabel(input.stopAccessibilityLabel)
                .accessibilityHint(input.actionHelp)
            } else {
                Button {
                    submitAndRestoreInputFocus()
                } label: {
                    actionGlyph(symbol: "arrow.up")
                }
                .buttonStyle(.plain)
                .disabled(!input.canSubmit)
                .help(input.actionHelp)
                .accessibilityLabel(input.submitAccessibilityLabel)
                .accessibilityHint(input.actionHelp)
            }
        }
    }

    private func submitAndRestoreInputFocus() {
        store.send(.submitTapped)
        restoreChatInputFocus()
    }

    private var attachmentDropTypeIdentifiers: [String] {
        [UTType.fileURL.identifier, UTType.url.identifier]
    }

    private func handleAttachmentDrop(_ providers: [NSItemProvider]) -> Bool {
        let supportedProviders = providers.filter { provider in
            provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
                || provider.hasItemConformingToTypeIdentifier(UTType.url.identifier)
        }
        guard !supportedProviders.isEmpty else { return false }
        store.send(.attachmentDrop(supportedProviders.map(AiChatAttachmentDropProvider.init(provider:))))
        restoreChatInputFocus()
        return true
    }

    private func acceptDroppedAttachments(_ urls: [URL]) {
        store.send(.attachmentDropSelection(urls))
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
                    .fill(Color.primary),
            )
            .opacity(1)
            .accessibilityHidden(true)
    }
}

private extension AiChatInputBar {
    @ViewBuilder var requestContextRow: some View {
        if !requestContext.isEmpty {
            AiChatRequestContextRow(store: store, state: state, displayModel: requestContext)
        }
    }
}

private struct AiChatRequestContextRow: View {
    let store: StoreOf<AiChatFeature>
    let state: AiChatState
    let displayModel: AiChatRequestContextDisplayModel

    private var destinationProvider: AiProvider? {
        state.executionPhase.lock?.selectedModelHandle.provider ?? state.selectedModelHandle?.provider
    }

    private var currentContextSnapshot: AiChatCurrentContextSnapshot {
        state.executionPhase.lock?.context.requestContext.currentContext ?? state.currentContext
    }

    private var destinationLabel: String {
        destinationProvider.map(aiChatProviderSectionTitle(for:)) ?? "Selected provider"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let currentContext = displayModel.currentContext {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .center, spacing: 8) {
                        groupLabel("Current context")
                        currentContextChip(currentContext, isEditable: displayModel.source == .draft)
                    }
                }
            }

            if !displayModel.addedAttachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .center, spacing: 8) {
                        groupLabel("Attachments")
                        ForEach(displayModel.addedAttachments) { attachment in
                            attachmentChip(attachment, isEditable: displayModel.source == .draft)
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

    @ViewBuilder
    private func currentContextChip(_ chip: AiChatCurrentContextChipDisplayModel, isEditable: Bool) -> some View {
        let statusLabel = aiChatCurrentContextStatusLabel(
            for: currentContextSnapshot,
            destinationProvider: destinationProvider,
        )
        let statusDetail = aiChatCurrentContextStatusDetail(
            for: currentContextSnapshot,
            destinationProvider: destinationProvider,
        )
        let modeDetail = chip
            .folderStructureMode == .includeSubfolders ? "Includes subfolders · names and paths only" : nil
        let detail = [chip.detail, statusDetail, modeDetail].compactMap(\.self).joined(separator: " · ")
        let view = chipView(
            content: ChipContent(
                title: chip.title,
                help: aiChatRequestContextTooltipText(
                    sourceLabel: "Current context",
                    destinationLabel: destinationLabel,
                    statusLabel: statusLabel,
                    statusDetail: detail.isEmpty ? chip.title : detail,
                ),
                accessibilityLabel: "Current context",
            ),
            icon: ChipIcon(systemName: chip.iconSystemName, assetName: chip.iconAssetName, filePath: chip.iconFilePath),
            isRemovable: false,
            remove: {},
            trailingAccessorySystemName: chip
                .folderStructureMode == .includeSubfolders ? "square.stack.3d.down.right" : nil,
            folderStructureMode: chip.folderStructureMode,
            isFolderStructureMenuEnabled: isEditable && chip.supportsFolderStructureMode,
            selectFolderStructureMode: { mode in
                store.send(.folderStructureModeChanged(.currentContext, mode))
            },
        )
        view
    }

    @ViewBuilder
    private func attachmentChip(_ chip: AiChatAddedAttachmentChipDisplayModel, isEditable: Bool) -> some View {
        let modeDetail = chip
            .folderStructureMode == .includeSubfolders ? "Includes subfolders · names and paths only" : nil
        let view = chipView(
            content: ChipContent(
                title: chip.title,
                help: aiChatRequestContextTooltipText(
                    sourceLabel: "Attachments",
                    destinationLabel: destinationLabel,
                    statusLabel: chip.statusLabel,
                    statusDetail: [chip.statusDetail, modeDetail].compactMap(\.self).joined(separator: " · "),
                ),
                accessibilityLabel: "Remove attachment",
            ),
            icon: ChipIcon(systemName: chip.iconSystemName, assetName: chip.iconAssetName, filePath: chip.iconFilePath),
            isRemovable: chip.isRemovable,
            remove: {
                store.send(.removeAddedAttachment(chip.attachmentID))
            },
            trailingAccessorySystemName: chip
                .folderStructureMode == .includeSubfolders ? "square.stack.3d.down.right" : nil,
            folderStructureMode: chip.folderStructureMode,
            isFolderStructureMenuEnabled: isEditable && chip.source == .folder,
            selectFolderStructureMode: { mode in
                store.send(.folderStructureModeChanged(.attachment(chip.attachmentID), mode))
            },
        )
        view
    }

    private struct ChipContent {
        let title: String
        let help: String
        let accessibilityLabel: String
    }

    private struct ChipIcon {
        let systemName: String?
        let assetName: String?
        let filePath: String?
    }

    private func chipView(
        content: ChipContent,
        icon: ChipIcon,
        isRemovable: Bool,
        remove: @escaping () -> Void,
        trailingAccessorySystemName: String? = nil,
        folderStructureMode: AiChatFolderStructureMode? = nil,
        isFolderStructureMenuEnabled: Bool = false,
        selectFolderStructureMode: @escaping (AiChatFolderStructureMode) -> Void = { _ in },
    ) -> some View {
        AiChatRemovableRequestContextChip(
            title: content.title,
            help: content.help,
            iconSystemName: icon.systemName,
            iconAssetName: icon.assetName,
            iconFilePath: icon.filePath,
            trailingAccessorySystemName: trailingAccessorySystemName,
            folderStructureMode: folderStructureMode,
            isFolderStructureMenuEnabled: isFolderStructureMenuEnabled,
            selectFolderStructureMode: selectFolderStructureMode,
            isRemovable: isRemovable,
            accessibilityLabel: content.accessibilityLabel,
            remove: remove,
        )
    }

    private func chipIconSystemName(_ systemName: String) -> String {
        systemName == "folder" ? "folder.fill" : systemName
    }

    private func chipIconSystemSize(for systemName: String) -> CGFloat {
        systemName == "folder" ? 10 : 9
    }

    private func chipIconForegroundStyle(for systemName: String) -> Color {
        systemName == "folder" ? Color(nsColor: .systemBlue) : .secondary
    }

    private var chipTitleFont: Font {
        .system(size: 11, weight: .medium)
    }
}

private struct AiChatRemovableRequestContextChip: View {
    let title: String
    let help: String
    let iconSystemName: String?
    let iconAssetName: String?
    let iconFilePath: String?
    let trailingAccessorySystemName: String?
    let folderStructureMode: AiChatFolderStructureMode?
    let isFolderStructureMenuEnabled: Bool
    let selectFolderStructureMode: (AiChatFolderStructureMode) -> Void
    let isRemovable: Bool
    let accessibilityLabel: String
    let remove: () -> Void

    @State private var isHovering = false
    @State private var isFolderMenuPresented = false
    @State private var isFolderMenuHovering = false
    @State private var isRemoveHovering = false

    var body: some View {
        HStack(spacing: 4) {
            chipIcon
            Text(title)
                .font(chipTitleFont)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)

            if let trailingAccessorySystemName {
                Image(systemName: trailingAccessorySystemName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 12, height: 12)
                    .accessibilityHidden(true)
            }

            if showsChipActions {
                chipActions
            }
        }
        .padding(.horizontal, chipHorizontalPadding)
        .padding(.vertical, chipVerticalPadding)
        .background(chipBackground)
        .overlay(chipBorder)
        .clipShape(Capsule(style: .continuous))
        .help(help)
        .onHover { hovering in
            isHovering = hovering
            if !hovering {
                isFolderMenuHovering = false
                isRemoveHovering = false
            }
        }
    }

    private var showsChipActions: Bool {
        isFolderStructureMenuEnabled || isRemovable
    }

    private var chipActions: some View {
        HStack(spacing: 2) {
            if isFolderStructureMenuEnabled {
                folderStructureModeMenuButton
            }

            if isRemovable {
                removeButton
            }
        }
    }

    private var folderStructureModeMenuButton: some View {
        Button {
            isFolderMenuPresented.toggle()
        } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 6.5, weight: .bold))
                .foregroundStyle(isFolderMenuHovering || isFolderMenuPresented ? .primary : .secondary)
                .frame(width: 12, height: 12)
                .contentShape(Rectangle())
                .background(actionButtonBackground(isHighlighted: isFolderMenuHovering || isFolderMenuPresented))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isFolderMenuPresented, arrowEdge: .bottom) {
            folderStructureModeMenuContent
        }
        .onHover { isFolderMenuHovering = $0 }
        .accessibilityLabel("Folder structure mode")
    }

    private var removeButton: some View {
        Button(action: remove) {
            Image(systemName: "xmark")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(isRemoveHovering ? .primary : .secondary)
                .frame(width: 12, height: 12)
                .contentShape(Rectangle())
                .background(actionButtonBackground(isHighlighted: isRemoveHovering))
        }
        .buttonStyle(.plain)
        .onHover { isRemoveHovering = $0 }
        .accessibilityLabel(accessibilityLabel)
    }

    private func actionButtonBackground(isHighlighted: Bool) -> some View {
        Circle()
            .fill(isHighlighted ? Color.primary.opacity(0.08) : Color.clear)
    }

    private var folderStructureModeMenuContent: some View {
        let selectedMode = folderStructureMode ?? .currentFolderOnly

        return VStack(alignment: .leading, spacing: 2) {
            folderStructureModeButton(
                title: "Current folder only",
                mode: .currentFolderOnly,
                selectedMode: selectedMode,
            )
            folderStructureModeButton(
                title: "Include subfolders",
                mode: .includeSubfolders,
                selectedMode: selectedMode,
            )
        }
        .padding(6)
        .fixedSize(horizontal: true, vertical: false)
    }

    private func folderStructureModeButton(
        title: String,
        mode: AiChatFolderStructureMode,
        selectedMode: AiChatFolderStructureMode,
    ) -> some View {
        Button {
            selectFolderStructureMode(mode)
            isFolderMenuPresented = false
        } label: {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 12))
                if selectedMode == mode {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .accessibilityLabel("Selected")
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var chipIcon: some View {
        if let iconFilePath {
            Image(nsImage: NSWorkspace.shared.icon(forFile: iconFilePath))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 11, height: 11)
                .accessibilityHidden(true)
        } else if let iconAssetName {
            Image(iconAssetName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 11, height: 11)
                .accessibilityHidden(true)
        } else if let iconSystemName {
            Image(systemName: chipIconSystemName(iconSystemName))
                .font(.system(size: chipIconSystemSize(for: iconSystemName), weight: .medium))
                .foregroundStyle(chipIconForegroundStyle(for: iconSystemName))
                .accessibilityHidden(true)
        }
    }

    private func chipIconSystemName(_ systemName: String) -> String {
        systemName == "folder" ? "folder.fill" : systemName
    }

    private func chipIconSystemSize(for systemName: String) -> CGFloat {
        systemName == "folder" ? 10 : 9
    }

    private func chipIconForegroundStyle(for systemName: String) -> Color {
        systemName == "folder" ? Color(nsColor: .systemBlue) : .secondary
    }

    private var chipTitleFont: Font {
        .system(size: 11, weight: .medium)
    }

    private var chipHorizontalPadding: CGFloat {
        8
    }

    private var chipVerticalPadding: CGFloat {
        4
    }

    private var chipBackground: some View {
        Capsule(style: .continuous)
            .fill(Color(nsColor: .controlBackgroundColor))
    }

    private var chipBorder: some View {
        Capsule(style: .continuous)
            .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
    }
}
