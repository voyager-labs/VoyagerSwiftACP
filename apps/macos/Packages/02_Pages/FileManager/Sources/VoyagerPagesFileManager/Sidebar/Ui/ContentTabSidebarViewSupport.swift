import AppKit
import ComposableArchitecture
import HotSwiftUI
import SwiftUI
import UniformTypeIdentifiers
import VoyagerEntitiesTag
import VoyagerShared

struct ContentTabDuplicatePresentation: Equatable {
    enum Command: Equatable {
        case duplicateContentTab(ContentTabID)
        case duplicateSelectedContentTabs
    }

    let title: String
    let accessibilityIdentifier: String
    let isEnabled: Bool
    let command: Command

    init(
        clickedTabID: ContentTabID,
        selectedTabIDs: Set<ContentTabID>,
        currentTabIDs: [ContentTabID],
        tabCount: Int,
    ) {
        let validSelectedIDs = Set(currentTabIDs).intersection(selectedTabIDs)
        if validSelectedIDs.count > 1, validSelectedIDs.contains(clickedTabID) {
            title = "Duplicate \(validSelectedIDs.count) Tabs"
            accessibilityIdentifier = "duplicate-selected-content-tabs"
            command = .duplicateSelectedContentTabs
        } else {
            title = "Duplicate"
            accessibilityIdentifier = "duplicate-content-tab-\(clickedTabID)"
            command = .duplicateContentTab(clickedTabID)
        }
        isEnabled = tabCount < ContentTabConstants.maxTabs
    }

    var viewAction: FileManagerSidebarAction.View {
        switch command {
        case let .duplicateContentTab(tabID):
            .duplicateContentTab(tabID)
        case .duplicateSelectedContentTabs:
            .duplicateSelectedContentTabs
        }
    }
}

struct ContentTabPinPresentation: Equatable {
    enum Command: Equatable {
        case pinContentTab(ContentTabID)
        case unpinContentTab(ContentTabID)
        case setSelectedContentTabsPinned(target: SelectedContentTabPinMutationTargetState)
    }

    let title: String
    let accessibilityIdentifier: String
    let isEnabled: Bool
    let command: Command

    init(
        clickedTabID: ContentTabID,
        isPinned: Bool,
        validSelectedTabIDs: Set<ContentTabID>,
        isPinMutationEnabled: Bool,
        isSingleUnpinEnabled: Bool,
    ) {
        if validSelectedTabIDs.count > 1, validSelectedTabIDs.contains(clickedTabID) {
            let target: SelectedContentTabPinMutationTargetState = isPinned ? .unpinned : .pinned
            title = isPinned
                ? "Unpin \(validSelectedTabIDs.count) Tabs"
                : "Pin \(validSelectedTabIDs.count) Tabs"
            accessibilityIdentifier = isPinned
                ? "unpin-selected-content-tabs"
                : "pin-selected-content-tabs"
            isEnabled = isPinMutationEnabled
            command = .setSelectedContentTabsPinned(target: target)
        } else if isPinned {
            title = "Unpin"
            accessibilityIdentifier = "unpin-content-tab-\(clickedTabID)"
            isEnabled = isSingleUnpinEnabled
            command = .unpinContentTab(clickedTabID)
        } else {
            title = "Pin"
            accessibilityIdentifier = "pin-content-tab-\(clickedTabID)"
            isEnabled = true
            command = .pinContentTab(clickedTabID)
        }
    }

    var usesUnpinCommand: Bool {
        switch command {
        case .unpinContentTab,
             .setSelectedContentTabsPinned(target: .unpinned):
            true
        case .pinContentTab,
             .setSelectedContentTabsPinned(target: .pinned):
            false
        }
    }

    var viewAction: FileManagerSidebarAction.View {
        switch command {
        case let .pinContentTab(tabID):
            .pinContentTab(tabID)
        case let .unpinContentTab(tabID):
            .unpinContentTab(tabID)
        case let .setSelectedContentTabsPinned(target):
            .setSelectedContentTabsPinned(target: target)
        }
    }
}

struct ContentTabClosePresentation: Equatable {
    enum Command: Equatable {
        case closeContentTab(ContentTabID)
        case closeSelectedContentTabs
        case unpinContentTab(ContentTabID)
    }

    let title: String
    let accessibilityIdentifier: String
    let isEnabled: Bool
    let command: Command

    init(
        clickedTabID: ContentTabID,
        isPinned: Bool,
        validSelectedTabIDs: Set<ContentTabID>,
        isEnabled: Bool,
    ) {
        if validSelectedTabIDs.count > 1, validSelectedTabIDs.contains(clickedTabID) {
            title = "Close \(validSelectedTabIDs.count) Tabs"
            accessibilityIdentifier = "close-selected-content-tabs"
            command = .closeSelectedContentTabs
        } else if isPinned {
            title = "Unpin"
            accessibilityIdentifier = "unpin-content-tab-\(clickedTabID)"
            command = .unpinContentTab(clickedTabID)
        } else {
            title = "Close"
            accessibilityIdentifier = "close-content-tab-\(clickedTabID)"
            command = .closeContentTab(clickedTabID)
        }
        self.isEnabled = isEnabled
    }

    var usesUnpinCommand: Bool {
        if case .unpinContentTab = command { return true }
        return false
    }

    var viewAction: FileManagerSidebarAction.View {
        switch command {
        case let .closeContentTab(tabID):
            .closeContentTab(tabID)
        case .closeSelectedContentTabs:
            .closeSelectedContentTabs
        case let .unpinContentTab(tabID):
            .unpinContentTab(tabID)
        }
    }
}

struct ContentTabMoveMenuPresentation: Equatable {
    enum Command: Equatable {
        case moveContentTab(ContentTabID)
        case moveSelectedContentTabs(initiatingTabID: ContentTabID, orderedTabIDs: [ContentTabID])
    }

    let title: String
    let accessibilityIdentifier: String
    let orderedTabIDs: [ContentTabID]
    let command: Command

    init(
        clickedTabID: ContentTabID,
        validSelectedTabIDs: Set<ContentTabID>,
        displayedOrderedTabIDs: [ContentTabID],
    ) {
        let orderedSelectedTabIDs = displayedOrderedTabIDs.filter(validSelectedTabIDs.contains)
        if orderedSelectedTabIDs.count > 1, orderedSelectedTabIDs.contains(clickedTabID) {
            title = "Move \(orderedSelectedTabIDs.count) Tabs to Window"
            orderedTabIDs = orderedSelectedTabIDs
            command = .moveSelectedContentTabs(
                initiatingTabID: clickedTabID,
                orderedTabIDs: orderedSelectedTabIDs,
            )
        } else {
            title = "Move to Window"
            orderedTabIDs = [clickedTabID]
            command = .moveContentTab(clickedTabID)
        }
        accessibilityIdentifier = ContentTabMoveProjection.menuIdentifier(tabID: clickedTabID)
    }

    func viewAction(targetWindowID: UUID) -> FileManagerSidebarAction.View {
        switch command {
        case let .moveContentTab(tabID):
            .moveContentTab(tabID: tabID, targetWindowID: targetWindowID)
        case let .moveSelectedContentTabs(initiatingTabID, orderedTabIDs):
            .moveSelectedContentTabs(
                initiatingTabID: initiatingTabID,
                orderedTabIDs: orderedTabIDs,
                targetWindowID: targetWindowID,
            )
        }
    }
}

enum ContentTabMovePendingProjection {
    static func isPending(
        tabID: ContentTabID,
        request: ContentTabMoveRequest?,
    ) -> Bool {
        request?.orderedTabIDs.contains(tabID) == true
    }
}

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

final class ContentTabSidebarButton: NSButton, NSDraggingSource {
    private enum PointerRoute {
        case activate
        case toggleSelection
        case selectRange
        case contextMenu
    }

    private struct PointerTracking {
        let route: PointerRoute
        let localOrigin: NSPoint
        let dragSource: FileManagerTopNavigationReorderDragSourceConfiguration
    }

    private enum PointerState {
        case idle
        case tracking(PointerTracking)
        case dragging(FileManagerTopNavigationReorderPasteboardWriter)
    }

    private static let reorderDragThreshold: CGFloat = 4

    private let presentationView = ContentTabSidebarPresentationHostingView(rootView: AnyView(EmptyView()))
    private let trailingActionButton = ContentTabSidebarTrailingActionButton()
    private var pointerState = PointerState.idle
    private var pointerRoute: PointerRoute?
    private var reorderDragSource: FileManagerTopNavigationReorderDragSourceConfiguration?
    private var moveTargets: [ContentTabMoveTarget] = []
    private var moveTargetsTabID = ContentTabID(rawValue: "")
    private var moveTitle = "Move to Window"
    private var isMovePending = false
    private var onMove: (UUID) -> Void = { _ in }

    private var onActivate: () -> Void = {}
    private var onToggleSelection: () -> Void = {}
    private var onSelectRange: () -> Void = {}
    private var onDuplicate: (() -> Void)?
    private var onPin: (() -> Void)?
    private var onUnpin: (() -> Void)?
    private var onClose: () -> Void = {}
    private var onTrailingAction: () -> Void = {}
    private var duplicateTitle = "Duplicate"
    private var duplicateAccessibilityIdentifier = ""
    private var isDuplicateEnabled = true
    private var pinTitle = "Pin"
    private var pinAccessibilityIdentifier = ""
    private var isPinEnabled = true
    private var closeTitle = "Close"
    private var closeAccessibilityIdentifier = ""
    private var isCloseEnabled = true
    private var usesUnpinCommand = false
    private var showsCloseCommand = true
    private var isPinned = false

    var dragSessionStartOverride: (([NSDraggingItem], NSEvent) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureControl()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: presentationView.fittingSize.height)
    }

    struct Configuration {
        let rootView: AnyView
        let accessibilityLabel: String
        let accessibilityValue: String
        let tabID: ContentTabID?
        let duplicateAccessibilityIdentifier: String
        let isPinned: Bool
        let isEnabled: Bool
        let reorderDragSource: FileManagerTopNavigationReorderDragSourceConfiguration?
        let moveTargets: [ContentTabMoveTarget]
        let moveTitle: String
        let isMovePending: Bool
        let onActivate: () -> Void
        let onToggleSelection: () -> Void
        let onSelectRange: () -> Void
        let onDuplicate: (() -> Void)?
        let onPin: (() -> Void)?
        let onUnpin: (() -> Void)?
        let onClose: () -> Void
        let onMove: (UUID) -> Void
        let duplicateTitle: String
        let isDuplicateEnabled: Bool
        let pinTitle: String?
        let pinAccessibilityIdentifier: String
        let isPinEnabled: Bool?
        let closeTitle: String?
        let closeAccessibilityIdentifier: String
        let isCloseEnabled: Bool?
        let usesUnpinCommand: Bool?
        let showsCloseCommand: Bool?
        let showsTrailingAction: Bool
        let trailingActionSystemName: String
        let isTrailingActionEnabled: Bool
        let onTrailingAction: () -> Void

        init(
            rootView: AnyView,
            accessibilityLabel: String,
            accessibilityValue: String,
            tabID: ContentTabID? = nil,
            duplicateAccessibilityIdentifier: String,
            isPinned: Bool,
            isEnabled: Bool,
            reorderDragSource: FileManagerTopNavigationReorderDragSourceConfiguration? = nil,
            moveTargets: [ContentTabMoveTarget] = [],
            moveTitle: String = "Move to Window",
            isMovePending: Bool = false,
            onActivate: @escaping () -> Void = {},
            onToggleSelection: @escaping () -> Void = {},
            onSelectRange: @escaping () -> Void = {},
            onDuplicate: (() -> Void)? = nil,
            onPin: (() -> Void)? = nil,
            onUnpin: (() -> Void)? = nil,
            onClose: @escaping () -> Void = {},
            onMove: @escaping (UUID) -> Void = { _ in },
            duplicateTitle: String = "Duplicate",
            isDuplicateEnabled: Bool = true,
            pinTitle: String? = nil,
            pinAccessibilityIdentifier: String = "",
            isPinEnabled: Bool? = nil,
            closeTitle: String? = nil,
            closeAccessibilityIdentifier: String = "",
            isCloseEnabled: Bool? = nil,
            usesUnpinCommand: Bool? = nil,
            showsCloseCommand: Bool? = nil,
            showsTrailingAction: Bool = false,
            trailingActionSystemName: String = "xmark",
            isTrailingActionEnabled: Bool = true,
            onTrailingAction: @escaping () -> Void = {},
        ) {
            self.rootView = rootView
            self.accessibilityLabel = accessibilityLabel
            self.accessibilityValue = accessibilityValue
            self.tabID = tabID
            self.duplicateAccessibilityIdentifier = duplicateAccessibilityIdentifier
            self.isPinned = isPinned
            self.isEnabled = isEnabled
            self.reorderDragSource = reorderDragSource
            self.moveTargets = moveTargets
            self.moveTitle = moveTitle
            self.isMovePending = isMovePending
            self.onActivate = onActivate
            self.onToggleSelection = onToggleSelection
            self.onSelectRange = onSelectRange
            self.onDuplicate = onDuplicate
            self.onPin = onPin
            self.onUnpin = onUnpin
            self.onClose = onClose
            self.onMove = onMove
            self.duplicateTitle = duplicateTitle
            self.isDuplicateEnabled = isDuplicateEnabled
            self.pinTitle = pinTitle
            self.pinAccessibilityIdentifier = pinAccessibilityIdentifier
            self.isPinEnabled = isPinEnabled
            self.closeTitle = closeTitle
            self.closeAccessibilityIdentifier = closeAccessibilityIdentifier
            self.isCloseEnabled = isCloseEnabled
            self.usesUnpinCommand = usesUnpinCommand
            self.showsCloseCommand = showsCloseCommand
            self.showsTrailingAction = showsTrailingAction
            self.trailingActionSystemName = trailingActionSystemName
            self.isTrailingActionEnabled = isTrailingActionEnabled
            self.onTrailingAction = onTrailingAction
        }
    }

    func update(configuration: Configuration) {
        reorderDragSource = configuration.reorderDragSource
        moveTargets = configuration.moveTargets
        if let tabID = configuration.tabID { moveTargetsTabID = tabID }
        moveTitle = configuration.moveTitle
        isMovePending = configuration.isMovePending
        onMove = configuration.onMove
        onActivate = configuration.onActivate
        onToggleSelection = configuration.onToggleSelection
        onSelectRange = configuration.onSelectRange
        onDuplicate = configuration.onDuplicate
        onPin = configuration.onPin
        onUnpin = configuration.onUnpin
        onClose = configuration.onClose
        onTrailingAction = configuration.onTrailingAction
        duplicateTitle = configuration.duplicateTitle
        duplicateAccessibilityIdentifier = configuration.duplicateAccessibilityIdentifier
        isDuplicateEnabled = configuration.isDuplicateEnabled
        pinTitle = configuration.pinTitle ?? (configuration.isPinned ? "Unpin" : "Pin")
        pinAccessibilityIdentifier = configuration.pinAccessibilityIdentifier
        isPinEnabled = configuration.isPinEnabled ?? configuration.isEnabled
        closeTitle = configuration.closeTitle ?? (configuration.isPinned ? "Unpin" : "Close")
        closeAccessibilityIdentifier = configuration.closeAccessibilityIdentifier
        isCloseEnabled = configuration.isCloseEnabled ?? configuration.isEnabled
        usesUnpinCommand = configuration.usesUnpinCommand ?? configuration.isPinned
        showsCloseCommand = configuration.showsCloseCommand ?? !configuration.isPinned
        trailingActionButton.image = NSImage(
            systemSymbolName: configuration.trailingActionSystemName,
            accessibilityDescription: nil,
        )?.withSymbolConfiguration(.init(pointSize: 10, weight: .medium))
        trailingActionButton.updateInteraction(
            isVisible: configuration.showsTrailingAction,
            isEnabled: configuration.isTrailingActionEnabled,
        )
        isPinned = configuration.isPinned
        isEnabled = configuration.isEnabled
        presentationView.rootView = configuration.rootView
        setAccessibilityLabel(configuration.accessibilityLabel)
        setAccessibilityValue(configuration.accessibilityValue)
        if let tabID = configuration.tabID {
            setAccessibilityIdentifier(ContentTabMoveProjection.rowIdentifier(tabID: tabID))
        }
        let contextMenu = makeContextMenu()
        menu = contextMenu
        trailingActionButton.menu = contextMenu
        presentationView.invalidateIntrinsicContentSize()
        invalidateIntrinsicContentSize()
        presentationView.needsLayout = true
        trailingActionButton.needsLayout = true
        needsLayout = true
    }

    override func mouseDown(with event: NSEvent) {
        guard event.buttonNumber == 0 else {
            super.mouseDown(with: event)
            return
        }

        let route = route(for: event)
        if case .contextMenu = route {
            pointerRoute = route
            defer { pointerRoute = nil }
            super.mouseDown(with: event)
            return
        }
        guard isEnabled, let reorderDragSource else {
            pointerRoute = route
            defer { pointerRoute = nil }
            super.mouseDown(with: event)
            return
        }

        trackPointer(
            from: PointerTracking(
                route: route,
                localOrigin: convert(event.locationInWindow, from: nil),
                dragSource: reorderDragSource,
            ),
        )
    }

    func sourceOperationMask(for context: NSDraggingContext) -> NSDragOperation {
        switch context {
        case .withinApplication:
            .move
        case .outsideApplication:
            []
        @unknown default:
            []
        }
    }

    func draggingSession(
        _: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext,
    ) -> NSDragOperation {
        sourceOperationMask(for: context)
    }

    func draggingSession(
        _: NSDraggingSession,
        endedAt _: NSPoint,
        operation _: NSDragOperation,
    ) {
        cleanupDragging()
    }

    func ignoreModifierKeys(for _: NSDraggingSession) -> Bool {
        true
    }

    func dismantle() {
        cleanupDragging()
        cancelPointerTracking()
    }

    private func configureControl() {
        title = ""
        isBordered = false
        setButtonType(.momentaryPushIn)
        focusRingType = .none
        target = self
        action = #selector(handlePrimaryAction)
        sendAction(on: .leftMouseUp)
        setAccessibilityElement(true)
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        presentationView.translatesAutoresizingMaskIntoConstraints = false
        presentationView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        presentationView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(presentationView)

        trailingActionButton.translatesAutoresizingMaskIntoConstraints = false
        trailingActionButton.isBordered = false
        trailingActionButton.imagePosition = .imageOnly
        trailingActionButton.imageScaling = .scaleNone
        trailingActionButton.contentTintColor = .secondaryLabelColor
        trailingActionButton.focusRingType = .none
        trailingActionButton.wantsLayer = true
        trailingActionButton.layer?.cornerRadius = 4
        trailingActionButton.target = self
        trailingActionButton.action = #selector(performTrailingAction)
        trailingActionButton.onContextMenuRequested = { [weak self] event in
            guard let self, let menu = trailingActionButton.menu else { return }
            NSMenu.popUpContextMenu(menu, with: event, for: trailingActionButton)
        }
        trailingActionButton.setAccessibilityElement(true)
        addSubview(trailingActionButton)

        NSLayoutConstraint.activate([
            presentationView.leadingAnchor.constraint(equalTo: leadingAnchor),
            presentationView.trailingAnchor.constraint(equalTo: trailingAnchor),
            presentationView.topAnchor.constraint(equalTo: topAnchor),
            presentationView.bottomAnchor.constraint(equalTo: bottomAnchor),
            trailingActionButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            trailingActionButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            trailingActionButton.widthAnchor.constraint(equalToConstant: 18),
            trailingActionButton.heightAnchor.constraint(equalToConstant: 18),
        ])
    }

    private func trackPointer(from tracking: PointerTracking) {
        pointerState = .tracking(tracking)
        isHighlighted = true
        guard let window else {
            cancelPointerTracking()
            return
        }

        let eventMask: NSEvent.EventTypeMask = [.leftMouseDragged, .leftMouseUp]
        while case .tracking = pointerState {
            guard let event = window.nextEvent(
                matching: eventMask,
                until: .distantFuture,
                inMode: .eventTracking,
                dequeue: true,
            ) else {
                cancelPointerTracking()
                return
            }

            let localLocation = convert(event.locationInWindow, from: nil)
            switch event.type {
            case .leftMouseDragged:
                isHighlighted = bounds.contains(localLocation)
                if movement(from: tracking.localOrigin, to: localLocation)
                    >= Self.reorderDragThreshold
                {
                    startDragging(from: tracking, event: event)
                    return
                }
            case .leftMouseUp:
                finishPointerTracking(tracking, mouseUpLocation: localLocation)
                return
            default:
                break
            }
        }
    }

    private func finishPointerTracking(
        _ tracking: PointerTracking,
        mouseUpLocation: NSPoint,
    ) {
        pointerState = .idle
        isHighlighted = false
        guard isEnabled, bounds.contains(mouseUpLocation) else { return }

        pointerRoute = tracking.route
        defer { pointerRoute = nil }
        if let action {
            sendAction(action, to: target)
        }
    }

    private func startDragging(
        from tracking: PointerTracking,
        event: NSEvent,
    ) {
        do {
            let writer = try FileManagerTopNavigationReorderPasteboardWriter(
                configuration: tracking.dragSource,
            )
            let draggingItem = NSDraggingItem(pasteboardWriter: writer)
            draggingItem.setDraggingFrame(bounds, contents: draggingImage())
            pointerState = .dragging(writer)
            isHighlighted = false

            if let dragSessionStartOverride {
                dragSessionStartOverride([draggingItem], event)
            } else {
                beginDraggingSession(
                    with: [draggingItem],
                    event: event,
                    source: self,
                )
            }
        } catch {
            cancelPointerTracking()
        }
    }

    private func draggingImage() -> NSImage {
        let image = NSImage(size: bounds.size)
        guard let representation = bitmapImageRepForCachingDisplay(in: bounds) else {
            return image
        }
        cacheDisplay(in: bounds, to: representation)
        image.addRepresentation(representation)
        return image
    }

    private func movement(from origin: NSPoint, to location: NSPoint) -> CGFloat {
        hypot(location.x - origin.x, location.y - origin.y)
    }

    private func cleanupDragging() {
        guard case let .dragging(writer) = pointerState else { return }
        writer.cleanupOwnedToken()
        pointerState = .idle
        isHighlighted = false
    }

    private func cancelPointerTracking() {
        if case .tracking = pointerState {
            pointerState = .idle
        }
        pointerRoute = nil
        isHighlighted = false
    }

    private func route(for event: NSEvent) -> PointerRoute {
        let modifierFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifierFlags.contains(.control) {
            return .contextMenu
        }

        switch ContentTabSelectionInputClassifier.classify(KeyModifiers(modifierFlags)) {
        case .activate:
            return .activate
        case .toggleSelection:
            return .toggleSelection
        case .selectRange:
            return .selectRange
        }
    }

    @objc private func handlePrimaryAction() {
        let route = pointerRoute ?? .activate
        pointerRoute = nil

        switch route {
        case .activate:
            onActivate()
        case .toggleSelection:
            onToggleSelection()
        case .selectRange:
            onSelectRange()
        case .contextMenu:
            break
        }
    }

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let duplicateItem = menuItem(title: duplicateTitle, action: #selector(duplicate))
        duplicateItem.identifier = NSUserInterfaceItemIdentifier(duplicateAccessibilityIdentifier)
        duplicateItem.isEnabled = isDuplicateEnabled && onDuplicate != nil
        menu.addItem(duplicateItem)
        let pinItem = menuItem(
            title: pinTitle,
            action: usesUnpinCommand ? #selector(unpin) : #selector(pin),
        )
        pinItem.identifier = NSUserInterfaceItemIdentifier(pinAccessibilityIdentifier)
        pinItem.isEnabled = isPinEnabled && (usesUnpinCommand ? onUnpin != nil : onPin != nil)
        menu.addItem(pinItem)
        if showsCloseCommand {
            let closeItem = menuItem(title: closeTitle, action: #selector(close))
            closeItem.identifier = NSUserInterfaceItemIdentifier(closeAccessibilityIdentifier)
            closeItem.isEnabled = isCloseEnabled
            menu.addItem(closeItem)
        }
        if !moveTargets.isEmpty {
            let moveItem = NSMenuItem(title: moveTitle, action: nil, keyEquivalent: "")
            moveItem.identifier = NSUserInterfaceItemIdentifier(
                ContentTabMoveProjection.menuIdentifier(tabID: moveTargetsTabID),
            )
            moveItem.isEnabled = !isMovePending
            let submenu = NSMenu(title: moveTitle)
            submenu.autoenablesItems = false
            let frozenOnMove = onMove
            for target in moveTargets {
                let targetItem = menuItem(title: target.displayTitle, action: #selector(moveToWindow(_:)))
                targetItem.identifier = NSUserInterfaceItemIdentifier(
                    ContentTabMoveProjection.targetIdentifier(
                        tabID: moveTargetsTabID,
                        windowID: target.windowID,
                    ),
                )
                targetItem.representedObject = ContentTabMoveMenuHandler {
                    frozenOnMove(target.windowID)
                }
                targetItem.isEnabled = !isMovePending
                submenu.addItem(targetItem)
            }
            moveItem.submenu = submenu
            menu.addItem(moveItem)
        }
        return menu
    }

    private func menuItem(title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func duplicate() {
        guard isDuplicateEnabled else { return }
        onDuplicate?()
    }

    @objc private func pin() {
        guard isPinEnabled else { return }
        onPin?()
    }

    @objc private func unpin() {
        guard isPinEnabled else { return }
        onUnpin?()
    }

    @objc private func close() {
        guard isCloseEnabled else { return }
        onClose()
    }

    @objc
    private func performTrailingAction() {
        guard trailingActionButton.isEnabled else { return }
        onTrailingAction()
    }

    @objc private func moveToWindow(_ sender: NSMenuItem) {
        guard !isMovePending,
              let action = sender.representedObject as? ContentTabMoveMenuHandler
        else { return }
        action.perform()
    }
}

private final class ContentTabMoveMenuHandler: NSObject {
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
private final class ContentTabSidebarPresentationHostingView: NSHostingView<AnyView> {
    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }
}
