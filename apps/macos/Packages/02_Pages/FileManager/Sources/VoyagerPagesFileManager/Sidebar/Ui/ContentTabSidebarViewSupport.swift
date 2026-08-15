import AppKit
import ComposableArchitecture
import HotSwiftUI
import SwiftUI
import UniformTypeIdentifiers
import VoyagerEntitiesTag
import VoyagerShared

enum FileManagerSidebarTopNavigationMoveDirection: Equatable {
    case previous
    case next
}

struct FileManagerSidebarTopNavigationMoveRequest: Equatable {
    let sourceID: FileManagerTopNavigationItemID
    let anchorID: FileManagerTopNavigationItemID
    let placement: FileManagerTopNavigationReorderPlacement
}

enum FileManagerSidebarTopNavigationMoveAdapter {
    static func request(
        sourceID: FileManagerTopNavigationItemID,
        direction: FileManagerSidebarTopNavigationMoveDirection,
        visibleItemIDs: [FileManagerTopNavigationItemID],
    ) -> FileManagerSidebarTopNavigationMoveRequest? {
        guard let sourceIndex = visibleItemIDs.firstIndex(of: sourceID) else { return nil }

        let anchorIndex: Int
        let placement: FileManagerTopNavigationReorderPlacement
        switch direction {
        case .previous:
            anchorIndex = sourceIndex - 1
            placement = .before
        case .next:
            anchorIndex = sourceIndex + 1
            placement = .after
        }
        guard visibleItemIDs.indices.contains(anchorIndex) else { return nil }

        return FileManagerSidebarTopNavigationMoveRequest(
            sourceID: sourceID,
            anchorID: visibleItemIDs[anchorIndex],
            placement: placement,
        )
    }
}

struct SidebarFixedLocationsSection<MenuContent: View>: View {
    let items: [FileManagerFixedLocationItem]
    let workspaceClient: WorkspaceClient
    let hoveredItemID: FileManagerFixedLocationItem.ID?
    let sidebarEntryDropTarget: FileManagerSidebarEntryDropTarget?
    let menuContent: () -> MenuContent
    let reorderDragSource: (FileManagerTopNavigationItemID) -> FileManagerTopNavigationReorderDragSourceConfiguration
    let reorderDropDestination: (FileManagerTopNavigationReorderDropBoundary)
        -> FileManagerTopNavigationReorderDropDestination
    let entryDropDelegate: (FileManagerSidebarEntryDropTarget, Bool) -> FileManagerSidebarEntryDropDelegate
    let onMove: (FileManagerTopNavigationItemID, FileManagerSidebarTopNavigationMoveDirection) -> Void
    let onSelect: (FileManagerFixedLocationItem.ID) -> Void
    let onHover: (FileManagerFixedLocationItem.ID?) -> Void

    var body: some View {
        if items.isEmpty {
            Color.clear
                .frame(height: fixedLocationGridVerticalPadding * 2 + fixedLocationCellHeight)
                .contentShape(Rectangle())
                .contextMenu { menuContent() }
                .padding(.horizontal, fixedLocationGridHorizontalPadding)
                .padding(.vertical, fixedLocationGridVerticalPadding)
                .padding(.bottom, fixedLocationGridBottomSpacing)
        } else {
            LazyVGrid(
                columns: [
                    GridItem(
                        .adaptive(minimum: fixedLocationMinimumCellWidth),
                        spacing: fixedLocationGridGap,
                        alignment: .center,
                    ),
                ],
                alignment: .leading,
                spacing: fixedLocationGridGap,
            ) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    let dropTarget = FileManagerSidebarEntryDropTarget.fixedLocation(item.id)
                    let itemID = FileManagerTopNavigationItemID.location(item.id)
                    FixedLocationButton(
                        item: item,
                        workspaceClient: workspaceClient,
                        height: fixedLocationCellHeight,
                        isHovered: hoveredItemID == item.id,
                        isDropTarget: sidebarEntryDropTarget == dropTarget,
                        reorderDragSource: reorderDragSource(itemID),
                        onSelect: {
                            onSelect(item.id)
                        },
                        onHover: { isHovered in
                            onHover(isHovered ? item.id : nil)
                        },
                    )
                    .overlay {
                        fixedLocationReorderDropOverlay(itemID: itemID, index: index)
                    }
                    .onDrop(
                        of: [.fileURL],
                        delegate: entryDropDelegate(dropTarget, item.kind != .trash),
                    )
                    .topNavigationMoveCommands(sourceID: itemID, onMove: onMove)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, fixedLocationGridHorizontalPadding)
            .padding(.vertical, fixedLocationGridVerticalPadding)
            .padding(.bottom, fixedLocationGridBottomSpacing)
            .animation(.easeInOut(duration: 0.15), value: items.map(\.id))
            .contentShape(Rectangle())
            .contextMenu { menuContent() }
        }
    }

    private var fixedLocationGridGap: CGFloat {
        8
    }

    private var fixedLocationGridHorizontalPadding: CGFloat {
        12
    }

    private var fixedLocationGridVerticalPadding: CGFloat {
        6
    }

    private var fixedLocationGridBottomSpacing: CGFloat {
        8
    }

    private var fixedLocationCellHeight: CGFloat {
        42
    }

    private var fixedLocationMinimumCellWidth: CGFloat {
        42
    }

    private func fixedLocationReorderDropOverlay(
        itemID: FileManagerTopNavigationItemID,
        index: Int,
    ) -> some View {
        HStack(spacing: 0) {
            fixedLocationReorderDropZone(FileManagerTopNavigationReorderDropBoundary(
                id: -(index * 2 + 1),
                owner: .topNavigation,
                anchorID: itemID,
                placement: .before,
            ))
            fixedLocationReorderDropZone(FileManagerTopNavigationReorderDropBoundary(
                id: -(index * 2 + 2),
                owner: .topNavigation,
                anchorID: itemID,
                placement: .after,
            ))
        }
    }

    private func fixedLocationReorderDropZone(
        _ boundary: FileManagerTopNavigationReorderDropBoundary,
    ) -> some View {
        reorderDropDestination(boundary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transaction { $0.animation = nil }
    }
}

struct SidebarContentTabSectionDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.12))
            .frame(height: 1)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
    }
}

struct SidebarNewContentTabRow: View {
    let isHovered: Bool
    let onHover: (Bool) -> Void
    let onOpen: () -> Void

    @Environment(\.colorScheme)
    private var colorScheme

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus")
                .symbolRenderingMode(.hierarchical)
                .foregroundColor(.accentColor)
                .frame(width: 16)
                .accessibilityHidden(true)
            Text("New Tab")
                .foregroundColor(.primary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: VoyagerDS.Radius.chipContainer)
                .fill(isHovered ? VoyagerDS.Interaction.hoverFill(for: colorScheme) : Color.clear),
        )
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .onHover(perform: onHover)
        .onTapGesture(perform: onOpen)
    }
}

enum FileManagerSidebarTopNavigationMoveKeyCommandClassifier {
    static func matches(_ modifierFlags: NSEvent.ModifierFlags) -> Bool {
        let expectedModifiers: NSEvent.ModifierFlags = [.option, .command]
        let userModifiers: NSEvent.ModifierFlags = [.command, .option, .shift, .control]
        return modifierFlags.intersection(userModifiers) == expectedModifiers
    }
}

struct FileManagerSidebarTopNavigationMoveCommandsModifier: ViewModifier {
    let sourceID: FileManagerTopNavigationItemID
    let onMove: (FileManagerTopNavigationItemID, FileManagerSidebarTopNavigationMoveDirection) -> Void

    func body(content: Content) -> some View {
        content
            .onMoveCommand { direction in
                guard let modifierFlags = NSApp.currentEvent?.modifierFlags,
                      FileManagerSidebarTopNavigationMoveKeyCommandClassifier.matches(modifierFlags)
                else { return }

                switch direction {
                case .up:
                    onMove(sourceID, .previous)
                case .down:
                    onMove(sourceID, .next)
                case .left, .right:
                    break
                @unknown default:
                    break
                }
            }
            .accessibilityAction(named: Text("Move Up")) {
                onMove(sourceID, .previous)
            }
            .accessibilityAction(named: Text("Move Down")) {
                onMove(sourceID, .next)
            }
    }
}

struct ContentTabDropDelegate: DropDelegate {
    @Binding var isTargeted: Bool
    let onPayload: @MainActor @Sendable (ContentTabDragPayload) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [ContentTabDragPayload.contentType])
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        validateDrop(info: info)
            ? DropProposal(operation: .move)
            : DropProposal(operation: .forbidden)
    }

    func dropEntered(info _: DropInfo) {
        isTargeted = true
    }

    func dropExited(info _: DropInfo) {
        isTargeted = false
    }

    func performDrop(info: DropInfo) -> Bool {
        isTargeted = false
        guard validateDrop(info: info) else { return false }
        let providers = info.itemProviders(for: [ContentTabDragPayload.contentType])
        guard providers.count == 1, let provider = providers.first else { return false }

        _ = provider.loadTransferable(type: ContentTabDragPayload.self) { result in
            guard case let .success(payload) = result else { return }
            Task { @MainActor in
                onPayload(payload)
            }
        }
        return true
    }
}

enum ContentTabSidebarTrailingCommand: Equatable {
    case unpin
    case close

    var systemName: String {
        switch self {
        case .unpin:
            "minus"
        case .close:
            "xmark"
        }
    }

    init(isPinned: Bool) {
        self = isPinned ? .unpin : .close
    }

    func viewAction(tabID: ContentTabID) -> FileManagerSidebarAction.View {
        switch self {
        case .unpin:
            .unpinContentTab(tabID)
        case .close:
            .closeContentTab(tabID)
        }
    }
}

struct ContentTabSidebarRow: View {
    let item: ContentTabProjection.ContentTabSidebarItem
    let reorderDragSource: FileManagerTopNavigationReorderDragSourceConfiguration?
    let moveTargets: [ContentTabMoveTarget]
    let moveTitle: String
    let isMovePending: Bool

    let isHovered: Bool
    let isDropTarget: Bool
    let isSelected: Bool
    let duplicatePresentation: ContentTabDuplicatePresentation
    let pinPresentation: ContentTabPinPresentation
    let closePresentation: ContentTabClosePresentation
    let onActivate: () -> Void
    let onToggleSelection: () -> Void
    let onSelectRange: () -> Void
    let onDuplicate: (() -> Void)?
    let onPin: (() -> Void)?
    let onUnpin: (() -> Void)?
    let onClose: () -> Void
    let onTrailingAction: () -> Void
    let onContextMenuClose: () -> Void
    let onMove: (UUID) -> Void
    let onHover: (Bool) -> Void

    @Environment(\.colorScheme)
    private var colorScheme

    @Environment(\.fileManagerKeyCommandFocusCoordinator)
    private var keyCommandFocusCoordinator

    @ObserveInjection private var injection

    var body: some View {
        let trailingAction = ContentTabSidebarTrailingCommand(isPinned: item.isPinned)
        ContentTabSidebarButtonHost(
            item: item,
            reorderDragSource: reorderDragSource,
            moveTargets: moveTargets,
            moveTitle: moveTitle,
            isMovePending: isMovePending,
            backgroundColor: backgroundColor,
            accessibilityStateValue: accessibilityStateValue,
            duplicateTitle: duplicatePresentation.title,
            duplicateAccessibilityIdentifier: duplicatePresentation.accessibilityIdentifier,
            isDuplicateEnabled: duplicatePresentation.isEnabled,
            pinTitle: pinPresentation.title,
            pinAccessibilityIdentifier: pinPresentation.accessibilityIdentifier,
            isPinEnabled: pinPresentation.isEnabled,
            closeTitle: closePresentation.title,
            closeAccessibilityIdentifier: closePresentation.accessibilityIdentifier,
            isCloseEnabled: closePresentation.isEnabled,
            usesUnpinCommand: pinPresentation.usesUnpinCommand,
            showsCloseCommand: !closePresentation.usesUnpinCommand,
            showsTrailingAction: isHovered,
            trailingActionSystemName: trailingAction.systemName,
            isTrailingActionEnabled: closePresentation.isEnabled,
            onActivate: handlePrimaryAction,
            onToggleSelection: handleToggleSelection,
            onSelectRange: handleSelectRange,
            onDuplicate: onDuplicate,
            onPin: onPin,
            onUnpin: onUnpin,
            onClose: onContextMenuClose,
            onTrailingAction: onTrailingAction,
            onMove: onMove,
        )
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
        .onHover(perform: onHover)
        .enableInjection()
    }

    private var accessibilityStateValue: String {
        switch (item.isActive, isSelected) {
        case (true, true):
            "Active, Selected"
        case (true, false):
            "Active, Not Selected"
        case (false, true):
            "Inactive, Selected"
        case (false, false):
            "Inactive, Not Selected"
        }
    }

    private func handlePrimaryAction() {
        onActivate()
        keyCommandFocusCoordinator?.requestFocus()
    }

    private func handleToggleSelection() {
        onToggleSelection()
        keyCommandFocusCoordinator?.requestFocus()
    }

    private func handleSelectRange() {
        onSelectRange()
        keyCommandFocusCoordinator?.requestFocus()
    }

    private var backgroundColor: Color {
        if isDropTarget {
            VoyagerDS.Interaction.hoverFill(for: colorScheme)
        } else if item.isActive, isSelected {
            adaptiveNeutralBackground(opacity: 0.16)
        } else if isSelected {
            adaptiveNeutralBackground(opacity: 0.04)
        } else if item.isActive {
            VoyagerDS.Surface.sidebarSelectionBackground(for: colorScheme)
        } else if isHovered {
            VoyagerDS.Interaction.hoverFill(for: colorScheme)
        } else {
            Color.clear
        }
    }

    private func adaptiveNeutralBackground(opacity: Double) -> Color {
        (colorScheme == .dark ? Color.white : Color.black).opacity(opacity)
    }
}

private struct ContentTabSidebarButtonHost: NSViewRepresentable {
    let item: ContentTabProjection.ContentTabSidebarItem
    let reorderDragSource: FileManagerTopNavigationReorderDragSourceConfiguration?
    let moveTargets: [ContentTabMoveTarget]
    let moveTitle: String
    let isMovePending: Bool

    let backgroundColor: Color
    let accessibilityStateValue: String
    let duplicateTitle: String
    let duplicateAccessibilityIdentifier: String
    let isDuplicateEnabled: Bool
    let pinTitle: String
    let pinAccessibilityIdentifier: String
    let isPinEnabled: Bool
    let closeTitle: String
    let closeAccessibilityIdentifier: String
    let isCloseEnabled: Bool
    let usesUnpinCommand: Bool
    let showsCloseCommand: Bool
    let showsTrailingAction: Bool
    let trailingActionSystemName: String
    let isTrailingActionEnabled: Bool
    let onActivate: () -> Void
    let onToggleSelection: () -> Void
    let onSelectRange: () -> Void
    let onDuplicate: (() -> Void)?
    let onPin: (() -> Void)?
    let onUnpin: (() -> Void)?
    let onClose: () -> Void
    let onTrailingAction: () -> Void
    let onMove: (UUID) -> Void

    func makeNSView(context _: Context) -> ContentTabSidebarButton {
        let button = ContentTabSidebarButton(frame: .zero)
        update(button)
        return button
    }

    func updateNSView(
        _ button: ContentTabSidebarButton,
        context _: Context,
    ) {
        update(button)
    }

    static func dismantleNSView(_ button: ContentTabSidebarButton, coordinator _: ()) {
        button.dismantle()
    }

    private func update(_ button: ContentTabSidebarButton) {
        button.update(configuration: ContentTabSidebarButton.Configuration(
            rootView: AnyView(hostedRoot),
            accessibilityLabel: item.title ?? "Untitled",
            accessibilityValue: accessibilityStateValue,
            tabID: item.id,
            duplicateAccessibilityIdentifier: duplicateAccessibilityIdentifier,
            isPinned: item.isPinned,
            isEnabled: true,
            reorderDragSource: reorderDragSource,
            moveTargets: moveTargets,
            moveTitle: moveTitle,
            isMovePending: isMovePending,
            onActivate: onActivate,
            onToggleSelection: onToggleSelection,
            onSelectRange: onSelectRange,
            onDuplicate: onDuplicate,
            onPin: onPin,
            onUnpin: onUnpin,
            onClose: onClose,
            onMove: onMove,
            duplicateTitle: duplicateTitle,
            isDuplicateEnabled: isDuplicateEnabled,
            pinTitle: pinTitle,
            pinAccessibilityIdentifier: pinAccessibilityIdentifier,
            isPinEnabled: isPinEnabled,
            closeTitle: closeTitle,
            closeAccessibilityIdentifier: closeAccessibilityIdentifier,
            isCloseEnabled: isCloseEnabled,
            usesUnpinCommand: usesUnpinCommand,
            showsCloseCommand: showsCloseCommand,
            showsTrailingAction: showsTrailingAction,
            trailingActionSystemName: trailingActionSystemName,
            isTrailingActionEnabled: isTrailingActionEnabled,
            onTrailingAction: onTrailingAction,
        ))
    }

    private var hostedRoot: ContentTabSidebarButtonRoot {
        ContentTabSidebarButtonRoot(
            item: item,
            backgroundColor: backgroundColor,
            isMovePending: isMovePending,
        )
    }
}

@MainActor
final class ContentTabSidebarTrailingActionButton: NSButton {
    var onContextMenuRequested: (NSEvent) -> Void = { _ in }
    private var isPointerHovered = false

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
        ))
    }

    override func mouseEntered(with _: NSEvent) {
        isPointerHovered = true
        updateHoverBackground()
    }

    override func mouseExited(with _: NSEvent) {
        isPointerHovered = false
        updateHoverBackground()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateHoverBackground()
    }

    override func mouseDown(with event: NSEvent) {
        guard event.buttonNumber == 0, event.modifierFlags.contains(.control) else {
            super.mouseDown(with: event)
            return
        }
        onContextMenuRequested(event)
    }

    func updateInteraction(isVisible: Bool, isEnabled: Bool) {
        isHidden = !isVisible
        self.isEnabled = isEnabled
        if !isVisible || !isEnabled {
            isPointerHovered = false
        }
        updateHoverBackground()
    }

    private func updateHoverBackground() {
        guard isPointerHovered, !isHidden, isEnabled else {
            layer?.backgroundColor = NSColor.clear.cgColor
            return
        }
        let color = switch effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) {
        case .darkAqua:
            NSColor.white.withAlphaComponent(0.08)
        default:
            NSColor.black.withAlphaComponent(0.06)
        }
        layer?.backgroundColor = color.cgColor
    }
}

final class ContentTabMoveMenuHandler: NSObject {
    let perform: () -> Void

    init(perform: @escaping () -> Void) {
        self.perform = perform
    }
}

private struct ContentTabSidebarButtonRoot: View {
    let item: ContentTabProjection.ContentTabSidebarItem
    let backgroundColor: Color
    let isMovePending: Bool

    var body: some View {
        HStack(spacing: 8) {
            leadingIcon
            Text(item.title ?? "Untitled")
                .foregroundColor(item.isActive ? .primary : VoyagerDS.SystemColor.secondaryLabel)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
            if isMovePending {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityIdentifier(ContentTabMoveProjection.progressIdentifier(tabID: item.id))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: VoyagerDS.Radius.chipContainer)
                .fill(backgroundColor),
        )
        .contentShape(Rectangle())
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder private var leadingIcon: some View {
        if let tagColorCode = item.tagColorCode {
            ColorDotView(nsColor: TagColor(colorCode: tagColorCode).nsColor, size: 8)
                .frame(width: 16)
                .accessibilityHidden(true)
        } else {
            SidebarSymbolIcon(
                systemName: item.iconName ?? "doc",
                size: 16,
                iconSize: 12,
                foregroundColor: item.isActive ? .accentColor : VoyagerDS.SystemColor.tertiaryLabel,
            )
            .symbolVariant(.fill)
        }
    }
}

@MainActor
final class ContentTabSidebarPresentationHostingView: NSHostingView<AnyView> {
    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }
}
