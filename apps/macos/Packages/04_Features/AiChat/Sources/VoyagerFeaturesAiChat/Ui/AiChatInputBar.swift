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
    let allowsAttachmentPicker: Bool
    let colorScheme: ColorScheme
    let composerIdentity: AiChatComposerIdentity
    @ObservedObject var focusOwner: AiChatInputFocusOwner

    @Binding var chatInputTextHeight: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            requestContextRow

            chatInputTextField

            HStack(alignment: .bottom, spacing: 4) {
                if allowsAttachmentPicker {
                    Button {
                        store.send(.attachmentPickerTapped)
                    } label: {
                        AiChatHoverTextAffordance(
                            title: input.contextAffordanceLabel,
                            titleFontSize: 14,
                            titleWeight: .semibold,
                            hoverColor: .primary,
                        )
                        .fixedSize(horizontal: true, vertical: false)
                    }
                    .buttonStyle(.plain)
                    .disabled(input.isComposerEditingDisabled)
                    .accessibilityLabel("Add attachment")
                }
                HStack(alignment: .bottom, spacing: 8) {
                    AiChatModelSelectorButton(
                        store: store,
                        state: state,
                        isEditingDisabled: input.isComposerEditingDisabled,
                    )
                    AiChatThinkingSelectorButton(
                        store: store,
                        state: state,
                        input: input,
                    )
                }
                .layoutPriority(1)
                Spacer(minLength: 0)
                chatInputActionButton
            }
        }
        .padding(8)
        .onChange(of: state.isProcessing) { isProcessing in
            if !isProcessing, focusOwner.isFocused(for: composerIdentity) {
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
                measuredHeight: $chatInputTextHeight,
                composerIdentity: composerIdentity,
                focusOwner: focusOwner,
                isDisabled: input.isComposerEditingDisabled,
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
        Task { @MainActor [composerIdentity, focusOwner] in
            focusOwner.requestFocus(for: composerIdentity)
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
        let presentation = AiChatRequestContextRowPresentation(displayModel: requestContext)
        if !presentation.rows.isEmpty {
            AiChatRequestContextRow(
                store: store,
                state: state,
                displayModel: requestContext,
                presentation: presentation,
                isEditable: !input.isComposerEditingDisabled,
            )
        }
    }
}

struct AiChatRequestContextRowPresentation: Equatable {
    enum Kind: Hashable {
        case currentContext
        case attachments
    }

    let rows: [Kind]

    init(displayModel: AiChatRequestContextDisplayModel) {
        var rows: [Kind] = []
        if displayModel.currentContext != nil {
            rows.append(.currentContext)
        }
        if !displayModel.addedAttachments.isEmpty {
            rows.append(.attachments)
        }
        self.rows = rows
    }
}

private struct AiChatRequestContextRow: View {
    let store: StoreOf<AiChatFeature>
    let state: AiChatState
    let displayModel: AiChatRequestContextDisplayModel
    let presentation: AiChatRequestContextRowPresentation
    let isEditable: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(presentation.rows, id: \.self) { kind in
                contextRow(kind)
            }
        }
    }

    @ViewBuilder
    private func contextRow(_ kind: AiChatRequestContextRowPresentation.Kind) -> some View {
        let label = rowLabel(for: kind)
        HStack(alignment: .center, spacing: 8) {
            groupLabel(label)
            rowContent(kind)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }

    private func rowLabel(for kind: AiChatRequestContextRowPresentation.Kind) -> String {
        switch kind {
        case .currentContext:
            "Current context"
        case .attachments:
            "Attachments"
        }
    }

    private func rowContent(_ kind: AiChatRequestContextRowPresentation.Kind) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .center, spacing: 8) {
                switch kind {
                case .currentContext:
                    if let currentContext = displayModel.currentContext {
                        currentContextChip(
                            currentContext,
                            snapshot: state.currentContext,
                            destinationProvider: state.selectedModelHandle?.provider,
                            sourceLabel: "Current context",
                            isEditable: isEditable,
                        )
                    }
                case .attachments:
                    ForEach(displayModel.addedAttachments) { attachment in
                        attachmentChip(
                            attachment,
                            destinationProvider: state.selectedModelHandle?.provider,
                            sourceLabel: "Attachments",
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
            .accessibilityAddTraits(.isHeader)
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
            folderStructureMenuAccessibilityLabel: "Folder structure mode for current context",
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
            folderStructureMenuAccessibilityLabel: "Folder structure mode for \(chip.title)",
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
        folderStructureMenuAccessibilityLabel: String = "Folder structure mode",
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
            folderStructureMenuAccessibilityLabel: folderStructureMenuAccessibilityLabel,
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
    let folderStructureMenuAccessibilityLabel: String
    let selectFolderStructureMode: (AiChatFolderStructureMode) -> Void
    let isRemovable: Bool
    let accessibilityLabel: String
    let remove: () -> Void

    @Environment(\.colorScheme)
    private var colorScheme
    @State private var isHovering = false
    @State private var isFolderMenuHovering = false
    @Dependency(\.workspaceClient)
    private var workspaceClient
    @State private var isRemoveHovering = false
    @State private var resolvedFileIcon: NSImage?
    @State private var currentIconFilePath: String?
    @State private var iconLoadTask: Task<Void, Never>?
    @State private var iconLoadGeneration = 0

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
        .task(id: iconFilePath) {
            await resolveFileIcon(for: iconFilePath)
        }
        .onDisappear {
            cancelFileIconLoad()
        }
    }

    private var showsChipActions: Bool {
        isFolderStructureMenuEnabled || isRemovable
    }

    private var chipActions: some View {
        HStack(spacing: 2) {
            if isFolderStructureMenuEnabled {
                folderStructureModeMenu
            }

            if isRemovable {
                removeButton
            }
        }
    }

    private var folderStructureModeMenu: some View {
        let items = AiChatFolderStructureMenuItemDisplayModel.items(
            selectedMode: folderStructureMode ?? .currentFolderOnly,
        )
        let selectedItem = items.first(where: \.isSelected)

        return Menu {
            ForEach(items) { item in
                Button {
                    selectFolderStructureMode(item.mode)
                } label: {
                    folderStructureModeMenuItemLabel(item)
                }
                .disabled(!item.isEnabled)
                .accessibilityLabel(item.accessibilityLabel)
                .accessibilityValue(item.accessibilityValue)
                .accessibilityAddTraits(item.isSelected ? .isSelected : [])
            }
        } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 6.5, weight: .bold))
                .accessibilityHidden(true)
                .foregroundStyle(isFolderMenuHovering ? .primary : .secondary)
                .frame(width: 12, height: 12)
                .contentShape(Rectangle())
                .background(actionButtonBackground(isHighlighted: isFolderMenuHovering))
        }
        .menuIndicator(.hidden)
        .menuStyle(.borderlessButton)
        .onHover { isFolderMenuHovering = $0 }
        .accessibilityLabel(folderStructureMenuAccessibilityLabel)
        .accessibilityValue(selectedItem?.title ?? "Current folder only")
    }

    @ViewBuilder
    private func folderStructureModeMenuItemLabel(
        _ item: AiChatFolderStructureMenuItemDisplayModel,
    ) -> some View {
        if item.isSelected {
            Label(item.title, systemImage: "checkmark")
        } else {
            Text(item.title)
        }
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

    @ViewBuilder private var chipIcon: some View {
        if iconFilePath != nil {
            Group {
                if let resolvedFileIcon {
                    Image(nsImage: resolvedFileIcon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Color.clear
                }
            }
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

    @MainActor
    private func resolveFileIcon(for path: String?) async {
        iconLoadTask?.cancel()
        iconLoadGeneration += 1
        let generation = iconLoadGeneration
        currentIconFilePath = path
        resolvedFileIcon = nil
        guard let path else {
            iconLoadTask = nil
            return
        }

        let workspaceClient = workspaceClient
        let task = Task { @MainActor in
            let icon = await workspaceClient.iconForFileAsync(path)
            guard AiChatRequestContextIconResolution.shouldApply(
                capturedPath: path,
                currentPath: currentIconFilePath,
                capturedGeneration: generation,
                currentGeneration: iconLoadGeneration,
                isCancelled: Task.isCancelled,
            ) else { return }
            resolvedFileIcon = icon
        }
        iconLoadTask = task
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        if currentIconFilePath == path, iconLoadGeneration == generation {
            iconLoadTask = nil
        }
    }

    @MainActor
    private func cancelFileIconLoad() {
        iconLoadTask?.cancel()
        iconLoadTask = nil
        iconLoadGeneration += 1
        currentIconFilePath = nil
        resolvedFileIcon = nil
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

enum AiChatRequestContextIconResolution {
    static func shouldApply(
        capturedPath: String,
        currentPath: String?,
        capturedGeneration: Int,
        currentGeneration: Int,
        isCancelled: Bool,
    ) -> Bool {
        !isCancelled
            && currentPath == capturedPath
            && currentGeneration == capturedGeneration
    }
}
