import AppKit
import ComposableArchitecture
import SwiftUI
import UniformTypeIdentifiers
import VoyagerEntitiesAi
import VoyagerShared

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
                .disabled(input.isComposerEditingDisabled)
                .accessibilityLabel("Add attachment")
                HStack(alignment: .bottom, spacing: 8) {
                    AiChatModelSelectorButton(
                        store: store,
                        state: state,
                        isEditingDisabled: input.isComposerEditingDisabled,
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
            if !isProcessing, isChatInputFocused {
                restoreChatInputFocus()
            }
        }
        .background(
            RoundedRectangle(cornerRadius: VoyagerDS.Radius.composer, style: .continuous)
                .fill(chatInputBackground),
        )
        .overlay(
            RoundedRectangle(cornerRadius: VoyagerDS.Radius.composer, style: .continuous)
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
                isDisabled: input.isComposerEditingDisabled,
                maxVisibleHeight: AiChatView.chatInputMaxTextHeight,
                onSubmit: { submitAndRestoreInputFocus() },
                onAttachmentsDropped: { urls in
                    acceptDroppedAttachments(urls)
                },
            )
            .frame(height: boundedChatInputTextHeight)

            if state.draftText.isEmpty {
                Text(input.placeholder)
                    .font(VoyagerDS.Typography.body)
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
        VoyagerDS.Surface.chatInputBackground(for: colorScheme)
    }

    private var chatInputBorder: Color {
        VoyagerDS.Surface.inputBorder(for: colorScheme)
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

    private var attachmentDropTypeIdentifiers: [String] {
        [UTType.fileURL.identifier, UTType.url.identifier]
    }

    private func handleAttachmentDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !input.isComposerEditingDisabled else { return false }
        let supportedProviders = providers.filter { provider in
            provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
                || provider.hasItemConformingToTypeIdentifier(UTType.url.identifier)
        }
        guard !supportedProviders.isEmpty, let sessionID = state.sessionID else { return false }
        store.send(.attachmentDrop(
            sessionID,
            supportedProviders.map(AiChatAttachmentDropProvider.init(provider:)),
        ))
        restoreChatInputFocus()
        return true
    }

    private func acceptDroppedAttachments(_ urls: [URL]) {
        guard !input.isComposerEditingDisabled, let sessionID = state.sessionID else { return }
        store.send(.attachmentDropSelection(sessionID, urls))
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
                RoundedRectangle(cornerRadius: VoyagerDS.Radius.control, style: .continuous)
                    .fill(Color.primary),
            )
            .opacity(1)
            .accessibilityHidden(true)
    }
}

private extension AiChatInputBar {
    @ViewBuilder var requestContextRow: some View {
        let presentation = AiChatRequestContextRowPresentation(
            displayModel: requestContext,
            isNextMessageEditable: !input.isComposerEditingDisabled,
        )
        if !presentation.sections.isEmpty {
            AiChatRequestContextRow(store: store, state: state, presentation: presentation)
        }
    }
}

struct AiChatRequestContextRowPresentation: Equatable {
    enum Kind: Hashable {
        case currentResponse
        case nextMessage
    }

    struct Section: Equatable {
        let kind: Kind
        let label: String
        let section: AiChatRequestContextSectionDisplayModel
        let isEditable: Bool
    }

    let sections: [Section]

    init(
        currentResponse: AiChatRequestContextSectionDisplayModel?,
        nextMessage: AiChatRequestContextSectionDisplayModel,
        isNextMessageEditable: Bool,
    ) {
        var sections: [Section] = []
        if let currentResponse, !currentResponse.isEmpty {
            sections.append(Section(
                kind: .currentResponse,
                label: "Current response context",
                section: currentResponse,
                isEditable: false,
            ))
        }
        if !nextMessage.isEmpty {
            sections.append(Section(
                kind: .nextMessage,
                label: "Next message context",
                section: nextMessage,
                isEditable: isNextMessageEditable,
            ))
        }
        self.sections = sections
    }

    init(displayModel: AiChatRequestContextDisplayModel, isNextMessageEditable: Bool) {
        self.init(
            currentResponse: displayModel.currentResponse,
            nextMessage: AiChatRequestContextSectionDisplayModel(
                source: displayModel.source,
                currentContext: displayModel.currentContext,
                addedAttachments: displayModel.addedAttachments,
            ),
            isNextMessageEditable: isNextMessageEditable,
        )
    }
}

private struct AiChatRequestContextRow: View {
    let store: StoreOf<AiChatFeature>
    let state: AiChatState
    let presentation: AiChatRequestContextRowPresentation

    private var currentResponseLock: AiChatRequestLock? {
        state.executionPhase.lock
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(presentation.sections, id: \.kind) { section in
                contextSection(section)
            }
        }
    }

    private func contextSection(_ presentation: AiChatRequestContextRowPresentation.Section) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Text(presentation.label)
                .font(VoyagerDS.Typography.chip)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: true, vertical: false)
                .accessibilityAddTraits(.isHeader)

            contextRows(
                section: presentation.section,
                currentContextSnapshot: currentContextSnapshot(for: presentation.kind),
                destinationProvider: destinationProvider(for: presentation.kind),
                isEditable: presentation.isEditable,
                sectionLabel: presentation.label,
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(presentation.label)
    }

    private func currentContextSnapshot(
        for kind: AiChatRequestContextRowPresentation.Kind,
    ) -> AiChatCurrentContextSnapshot {
        switch kind {
        case .currentResponse:
            currentResponseLock?.context.requestContext.currentContext ?? .init()
        case .nextMessage:
            state.currentContext
        }
    }

    private func destinationProvider(for kind: AiChatRequestContextRowPresentation.Kind) -> AiProvider? {
        switch kind {
        case .currentResponse:
            currentResponseLock?.selectedModelHandle.provider
        case .nextMessage:
            state.selectedModelHandle?.provider
        }
    }

    private func contextRows(
        section: AiChatRequestContextSectionDisplayModel,
        currentContextSnapshot: AiChatCurrentContextSnapshot,
        destinationProvider: AiProvider?,
        isEditable: Bool,
        sectionLabel: String?,
    ) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .center, spacing: 8) {
                if let currentContext = section.currentContext {
                    groupLabel("Current context")
                    currentContextChip(
                        currentContext,
                        snapshot: currentContextSnapshot,
                        destinationProvider: destinationProvider,
                        sourceLabel: sectionLabel.map { "\($0) current context" } ?? "Current context",
                        isEditable: isEditable,
                    )
                }

                if !section.addedAttachments.isEmpty {
                    groupLabel("Attachments")
                    ForEach(section.addedAttachments) { attachment in
                        attachmentChip(
                            attachment,
                            destinationProvider: destinationProvider,
                            sourceLabel: sectionLabel.map { "\($0) attachments" } ?? "Attachments",
                            isEditable: isEditable,
                        )
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
    private func currentContextChip(
        _ chip: AiChatCurrentContextChipDisplayModel,
        snapshot: AiChatCurrentContextSnapshot,
        destinationProvider: AiProvider?,
        sourceLabel: String,
        isEditable: Bool,
    ) -> some View {
        let statusLabel = aiChatCurrentContextStatusLabel(
            for: snapshot,
            destinationProvider: destinationProvider,
        )
        let statusDetail = aiChatCurrentContextStatusDetail(
            for: snapshot,
            destinationProvider: destinationProvider,
        )
        let modeDetail = chip
            .folderStructureMode == .includeSubfolders ? "Includes subfolders · names and paths only" : nil
        let detail = [chip.detail, statusDetail, modeDetail].compactMap(\.self).joined(separator: " · ")
        let view = chipView(
            content: ChipContent(
                title: chip.title,
                help: aiChatRequestContextTooltipText(
                    sourceLabel: sourceLabel,
                    destinationLabel: destinationLabel(for: destinationProvider),
                    statusLabel: statusLabel,
                    statusDetail: detail.isEmpty ? chip.title : detail,
                ),
                accessibilityLabel: sourceLabel,
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
    private func attachmentChip(
        _ chip: AiChatAddedAttachmentChipDisplayModel,
        destinationProvider: AiProvider?,
        sourceLabel: String,
        isEditable: Bool,
    ) -> some View {
        let modeDetail = chip
            .folderStructureMode == .includeSubfolders ? "Includes subfolders · names and paths only" : nil
        let view = chipView(
            content: ChipContent(
                title: chip.title,
                help: aiChatRequestContextTooltipText(
                    sourceLabel: sourceLabel,
                    destinationLabel: destinationLabel(for: destinationProvider),
                    statusLabel: chip.statusLabel,
                    statusDetail: [chip.statusDetail, modeDetail].compactMap(\.self).joined(separator: " · "),
                ),
                accessibilityLabel: "Remove \(sourceLabel.lowercased())",
            ),
            icon: ChipIcon(systemName: chip.iconSystemName, assetName: chip.iconAssetName, filePath: chip.iconFilePath),
            isRemovable: isEditable && chip.isRemovable,
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

    private func destinationLabel(for provider: AiProvider?) -> String {
        provider.map(aiChatProviderSectionTitle(for:)) ?? "Selected provider"
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

    private var chipTitleFont: Font {
        VoyagerDS.Typography.chip
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

    @Environment(\.colorScheme)
    private var colorScheme
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
        .onChange(of: isFolderStructureMenuEnabled) { isEnabled in
            if !isEnabled {
                isFolderMenuPresented = false
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
            .fill(isHighlighted ? VoyagerDS.Interaction.controlHoverFill(for: colorScheme) : .clear)
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
                    .font(VoyagerDS.Typography.caption)
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
        VoyagerDS.Typography.chip
    }

    private var chipHorizontalPadding: CGFloat {
        8
    }

    private var chipVerticalPadding: CGFloat {
        4
    }

    private var chipBackground: some View {
        Capsule(style: .continuous)
            .fill(VoyagerDS.Surface.chipItemBackground(for: colorScheme))
    }

    private var chipBorder: some View {
        Capsule(style: .continuous)
            .strokeBorder(VoyagerDS.Surface.chipItemBorder(for: colorScheme), lineWidth: 1)
    }
}
