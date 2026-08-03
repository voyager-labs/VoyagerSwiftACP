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

    var delegateAction: FileManagerSidebarAction.Delegate {
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

    var delegateAction: FileManagerSidebarAction.Delegate {
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

struct SidebarView: View {
    let sidebarStore: StoreOf<FileManagerSidebarFeature>
    let contentTabStore: StoreOf<ContentTabFeature>
    let interactionStore: Store<ContentTabRowInteractionSurface, FileManagerSidebarAction>
    let workspaceClient: WorkspaceClient

    @Environment(\.colorScheme)
    private var colorScheme

    @State private var contentTabHoveredItemID: ContentTabID?

    @State private var fixedLocationHoveredItemID: FileManagerFixedLocationItem.ID?

    @State private var isNewTabHovered = false

    @State private var sidebarEntryDropTarget: FileManagerSidebarEntryDropTarget?

    @State private var contentTabReorderDragScopeID = ContentTabReorderDragScopeID()
    @State private var contentTabReorderSessionStore = ContentTabReorderLocalSessionStore()
    @State private var activeContentTabReorderBoundaryID: Int?

    @State private var isContentTabsDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            if !sidebarStore.allFixedLocationItems.isEmpty {
                fixedLocationsGrid
                    .padding(.top, 50)
            }

            contentTabsViewport
        }
        .background(Color.clear)
        .navigationSplitViewColumnWidth(ideal: sidebarStore.sidebarWidth)
        .onDisappear {
            activeContentTabReorderBoundaryID = nil
        }
    }

    private var contentTabsViewport: some View {
        GeometryReader { proxy in
            ZStack {
                Color.clear

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if !sidebarStore.contentTabSidebarItems.isEmpty {
                            contentTabRows(pinnedContentTabSidebarItems)

                            if !pinnedContentTabSidebarItems.isEmpty,
                               !unpinnedContentTabSidebarItems.isEmpty
                            {
                                contentTabSectionDivider
                            }

                            reorderableContentTabRows(unpinnedContentTabSidebarItems)

                            Spacer()
                                .frame(height: 4)

                            newContentTabRow

                            Spacer()
                                .frame(height: 8)
                        }

                        Spacer(minLength: 0)
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                sidebarStore.send(.view(.collapseContentTabSelectionToActive))
                            }
                    }
                    .frame(minHeight: proxy.size.height, alignment: .top)
                }
            }
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: VoyagerDS.Radius.chipContainer)
                    .fill(
                        isContentTabsDropTargeted
                            ? VoyagerDS.Interaction.hoverFill(for: colorScheme)
                            : Color.clear,
                    ),
            )
            .accessibilityIdentifier(ContentTabMoveProjection.dropZoneIdentifier)
            .onDrop(
                of: [ContentTabDragPayload.contentType],
                delegate: ContentTabDropDelegate(
                    isTargeted: $isContentTabsDropTargeted,
                    onPayload: receiveContentTabDrag,
                ),
            )
            .clipped()
        }
    }

    private func receiveContentTabDrag(_ payload: ContentTabDragPayload) {
        guard ContentTabDragPayload.isSupported(schemaVersion: payload.schemaVersion),
              let currentWindowID = sidebarStore.currentWindowID,
              currentWindowID != payload.sourceWindowID,
              sidebarStore.pendingContentTabMoveRequest == nil
        else { return }
        sidebarStore.send(.view(.receiveContentTabDrag(payload)))
    }

    private var pinnedContentTabSidebarItems: [ContentTabProjection.ContentTabSidebarItem] {
        sidebarStore.contentTabSidebarItems.filter(\.isPinned)
    }

    private var unpinnedContentTabSidebarItems: [ContentTabProjection.ContentTabSidebarItem] {
        sidebarStore.contentTabSidebarItems.filter { !$0.isPinned }
    }

    private var contentTabSelectionPresentation: ContentTabSelectionPresentation {
        ContentTabSelectionPresentation(selectedTabIDs: contentTabStore.selectedTabIDs)
    }

    @ViewBuilder private var fixedLocationsGrid: some View {
        if sidebarStore.fixedLocationItems.isEmpty {
            Color.clear
                .frame(height: fixedLocationGridHeight(for: 1))
                .contentShape(Rectangle())
                .contextMenu { fixedLocationsVisibilityMenu }
                .padding(.horizontal, fixedLocationGridHorizontalPadding)
                .padding(.vertical, fixedLocationGridVerticalPadding)
                .padding(.bottom, fixedLocationGridBottomSpacing)
        } else {
            GeometryReader { proxy in
                let metrics = fixedLocationGridMetrics(for: proxy.size.width)

                LazyVGrid(columns: metrics.columns, alignment: .leading, spacing: fixedLocationGridGap) {
                    ForEach(sidebarStore.fixedLocationItems) { item in
                        let dropTarget = FileManagerSidebarEntryDropTarget.fixedLocation(item.id)
                        FixedLocationButton(
                            item: item,
                            workspaceClient: workspaceClient,
                            width: metrics.cellWidth,
                            height: fixedLocationCellHeight,
                            isHovered: fixedLocationHoveredItemID == item.id,
                            isDropTarget: sidebarEntryDropTarget == dropTarget,
                            onSelect: {
                                sidebarStore.send(.delegate(.selectFixedLocation(item.id)))
                            },
                            onHover: { isHovered in
                                fixedLocationHoveredItemID = isHovered ? item.id : nil
                            },
                        )
                        .onDrop(
                            of: [.fileURL],
                            delegate: entryDropDelegate(for: dropTarget, allowsCopy: item.kind != .trash),
                        )
                    }
                }
                .padding(.horizontal, fixedLocationGridHorizontalPadding)
                .padding(.vertical, fixedLocationGridVerticalPadding)
            }
            .frame(height: fixedLocationGridHeight(for: sidebarStore.fixedLocationItems.count))
            .padding(.bottom, fixedLocationGridBottomSpacing)
            .contentShape(Rectangle())
            .contextMenu { fixedLocationsVisibilityMenu }
        }
    }

    @ViewBuilder private var fixedLocationsVisibilityMenu: some View {
        if !sidebarStore.allFixedLocationItems.isEmpty {
            Section("Locations") {
                Button("Show All") {
                    sidebarStore.send(.view(.setAllFixedLocationVisibility(true)))
                }
                Button("Hide All") {
                    sidebarStore.send(.view(.setAllFixedLocationVisibility(false)))
                }

                Divider()

                ForEach(sidebarStore.allFixedLocationItems) { item in
                    Toggle(
                        isOn: Binding(
                            get: { !sidebarStore.hiddenFixedLocationItemIDs.contains(item.id) },
                            set: { isVisible in
                                sidebarStore.send(.view(.setFixedLocationVisibility(item.id, isVisible)))
                            },
                        ),
                    ) {
                        Label(item.title, systemImage: normalizedSidebarIconName(item.iconName))
                    }
                }
            }
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

    private func fixedLocationGridMetrics(for width: CGFloat) -> FixedLocationGridMetrics {
        let availableWidth = max(0, width - fixedLocationGridHorizontalPadding * 2)
        let columnCount = max(
            1,
            Int((availableWidth + fixedLocationGridGap) / (fixedLocationMinimumCellWidth + fixedLocationGridGap)),
        )
        let totalGapWidth = fixedLocationGridGap * CGFloat(max(0, columnCount - 1))
        let cellWidth = max(
            fixedLocationMinimumCellWidth,
            floor((availableWidth - totalGapWidth) / CGFloat(columnCount)),
        )

        return FixedLocationGridMetrics(
            columns: Array(
                repeating: GridItem(.fixed(cellWidth), spacing: fixedLocationGridGap, alignment: .center),
                count: columnCount,
            ),
            cellWidth: cellWidth,
        )
    }

    private func fixedLocationGridHeight(for itemCount: Int) -> CGFloat {
        let width = max(0, sidebarStore.sidebarWidth - fixedLocationGridHorizontalPadding * 2)
        let columnCount = max(
            1,
            Int((width + fixedLocationGridGap) / (fixedLocationMinimumCellWidth + fixedLocationGridGap)),
        )
        let rowCount = max(1, Int(ceil(Double(itemCount) / Double(columnCount))))
        return fixedLocationGridVerticalPadding * 2
            + CGFloat(rowCount) * fixedLocationCellHeight
            + CGFloat(max(0, rowCount - 1)) * fixedLocationGridGap
    }

    private var contentTabSectionDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.12))
            .frame(height: 1)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
    }

    private func contentTabRows(
        _ items: [ContentTabProjection.ContentTabSidebarItem],
    ) -> some View {
        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
            entryDroppableContentTabRow(
                item,
                reorderDragSource: contentTabDragSource(for: item, includesReorder: false),
            )

            if index < items.count - 1 {
                Spacer()
                    .frame(height: 4)
            }
        }
    }

    @ViewBuilder
    private func reorderableContentTabRows(
        _ items: [ContentTabProjection.ContentTabSidebarItem],
    ) -> some View {
        if !items.isEmpty {
            let boundaries = ContentTabReorderDropBoundary.make(for: items.map(\.id))

            VStack(alignment: .leading, spacing: 0) {
                contentTabReorderDropSlot(boundaries[0])
                    .transaction { $0.animation = nil }

                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    reorderableContentTabRow(item)
                    contentTabReorderDropSlot(boundaries[index + 1])
                        .transaction { $0.animation = nil }
                }
            }
            .animation(.easeInOut(duration: 0.15), value: items.map(\.id))
        }
    }

    private var newContentTabRow: some View {
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
                .fill(isNewTabHovered ? VoyagerDS.Interaction.hoverFill(for: colorScheme) : Color.clear),
        )
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .onHover { isNewTabHovered = $0 }
        .onTapGesture {
            sidebarStore.send(.delegate(.openContentTab))
        }
    }

    private func contentTabDragSource(
        for item: ContentTabProjection.ContentTabSidebarItem,
        includesReorder: Bool,
    ) -> ContentTabReorderDragSourceConfiguration? {
        guard let sourceWindowID = sidebarStore.currentWindowID,
              sidebarStore.pendingContentTabMoveRequest == nil
        else { return nil }
        let movePayload = ContentTabDragPayload(
            schemaVersion: ContentTabDragPayload.supportedSchemaVersion,
            sourceWindowID: sourceWindowID,
            tabID: item.id,
        )
        guard includesReorder else {
            return ContentTabReorderDragSourceConfiguration(
                movePayload: movePayload,
                sessionStore: contentTabReorderSessionStore,
            )
        }
        return ContentTabReorderDragSourceConfiguration(
            payload: ContentTabReorderDragPayload(
                sourceID: item.id,
                dragScopeID: contentTabReorderDragScopeID,
            ),
            sessionStore: contentTabReorderSessionStore,
            movePayload: movePayload,
        )
    }

    private func reorderableContentTabRow(
        _ item: ContentTabProjection.ContentTabSidebarItem,
    ) -> some View {
        entryDroppableContentTabRow(
            item,
            reorderDragSource: contentTabDragSource(for: item, includesReorder: true),
        )
    }

    private func contentTabReorderDropSlot(
        _ boundary: ContentTabReorderDropBoundary,
    ) -> some View {
        Rectangle()
            .fill(Color.clear)
            .frame(height: 4)
            .frame(maxWidth: .infinity)
            .overlay {
                if activeContentTabReorderBoundaryID == boundary.id {
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(height: 2)
                        .allowsHitTesting(false)
                }
            }
            .padding(.horizontal, 8)
            .background {
                contentTabReorderDropDestination(for: boundary)
            }
            .contentShape(Rectangle())
    }

    @ViewBuilder
    private func entryDroppableContentTabRow(
        _ item: ContentTabProjection.ContentTabSidebarItem,
        reorderDragSource: ContentTabReorderDragSourceConfiguration?,
    ) -> some View {
        if let dropTarget = FileManagerSidebarEntryDropDelegate.target(for: item) {
            contentTabSidebarRow(item, reorderDragSource: reorderDragSource)
                .onDrop(of: [.fileURL], delegate: entryDropDelegate(for: dropTarget))
        } else {
            contentTabSidebarRow(item, reorderDragSource: reorderDragSource)
        }
    }

    private func contentTabSidebarRow(
        _ item: ContentTabProjection.ContentTabSidebarItem,
        reorderDragSource: ContentTabReorderDragSourceConfiguration?,
    ) -> some View {
        let duplicatePresentation = ContentTabDuplicatePresentation(
            clickedTabID: item.id,
            selectedTabIDs: contentTabStore.selectedTabIDs,
            currentTabIDs: Array(contentTabStore.tabs.ids),
            tabCount: contentTabStore.tabs.count,
        )
        let pinPresentation = contentTabPinPresentation(for: item)
        let closePresentation = ContentTabClosePresentation(
            clickedTabID: item.id,
            isPinned: item.isPinned,
            validSelectedTabIDs: interactionStore.validSelectedTabIDs,
            isEnabled: interactionStore.isCloseEnabled,
        )
        return ContentTabSidebarRow(
            item: item,
            reorderDragSource: reorderDragSource,
            moveTargets: ContentTabMoveProjection.availableTargets(
                sidebarStore.contentTabMoveTargets,
                currentWindowID: sidebarStore.currentWindowID,
                tabID: item.id,
            ),
            isMovePending: sidebarStore.pendingContentTabMoveRequest?.tabID == item.id,
            isHovered: contentTabHoveredItemID == item.id,
            isDropTarget: sidebarEntryDropTarget == .contentTab(item.id),
            isSelected: contentTabSelectionPresentation.isSelected(item.id),
            duplicatePresentation: duplicatePresentation,
            pinPresentation: pinPresentation,
            closePresentation: closePresentation,
            onActivate: {
                sidebarStore.send(.delegate(.selectContentTab(item.id)))
            },
            onToggleSelection: {
                sidebarStore.send(.view(.toggleContentTabSelection(item.id)))
            },
            onSelectRange: {
                sidebarStore.send(.view(.selectContentTabRange(to: item.id)))
            },
            onDuplicate: duplicatePresentation.isEnabled ? {
                sidebarStore.send(.delegate(duplicatePresentation.delegateAction))
            } : nil,
            onPin: pinPresentation.isEnabled ? {
                sidebarStore.send(.view(pinPresentation.viewAction))
            } : nil,
            onUnpin: pinPresentation.isEnabled ? {
                sidebarStore.send(.view(pinPresentation.viewAction))
            } : nil,
            onClose: {
                sidebarStore.send(.delegate(.closeContentTab(item.id)))
            },
            onContextMenuClose: {
                sidebarStore.send(.delegate(closePresentation.delegateAction))
            },
            onMove: { targetWindowID in
                sidebarStore.send(.view(.moveContentTab(tabID: item.id, targetWindowID: targetWindowID)))
            },
            onHover: { isHovered in
                contentTabHoveredItemID = isHovered ? item.id : nil
            },
        )
    }

    private func contentTabPinPresentation(
        for item: ContentTabProjection.ContentTabSidebarItem,
    ) -> ContentTabPinPresentation {
        ContentTabPinPresentation(
            clickedTabID: item.id,
            isPinned: item.isPinned,
            validSelectedTabIDs: interactionStore.validSelectedTabIDs,
            isPinMutationEnabled: interactionStore.isPinMutationEnabled,
            isSingleUnpinEnabled: interactionStore.isCloseEnabled,
        )
    }

    private func contentTabReorderDropDestination(
        for boundary: ContentTabReorderDropBoundary,
    ) -> ContentTabReorderDropDestination {
        ContentTabReorderDropDestination(
            activeBoundaryID: $activeContentTabReorderBoundaryID,
            boundary: boundary,
            dragScopeID: contentTabReorderDragScopeID,
            sessionStore: contentTabReorderSessionStore,
            pinState: { id in
                sidebarStore.contentTabSidebarItems.first(where: { $0.id == id })?.isPinned
            },
            onReorder: { sourceID, targetID, placement in
                sidebarStore.send(.view(.contentTabReorderRequested(
                    sourceID: sourceID,
                    targetID: targetID,
                    placement: placement,
                )))
            },
        )
    }

    private func entryDropDelegate(
        for target: FileManagerSidebarEntryDropTarget,
        allowsCopy: Bool = true,
    ) -> FileManagerSidebarEntryDropDelegate {
        FileManagerSidebarEntryDropDelegate(
            dropTarget: $sidebarEntryDropTarget,
            target: target,
            allowsCopy: allowsCopy,
            onDrop: { request in
                sidebarStore.send(.view(.entryDropRequested(request)))
            },
        )
    }
}

private struct ContentTabDropDelegate: DropDelegate {
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

private struct ContentTabSidebarRow: View {
    let item: ContentTabProjection.ContentTabSidebarItem
    let reorderDragSource: ContentTabReorderDragSourceConfiguration?
    let moveTargets: [ContentTabMoveTarget]
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
    let onContextMenuClose: () -> Void
    let onMove: (UUID) -> Void
    let onHover: (Bool) -> Void

    @Environment(\.colorScheme)
    private var colorScheme

    @Environment(\.fileManagerKeyCommandFocusCoordinator)
    private var keyCommandFocusCoordinator

    @ObserveInjection private var injection

    var body: some View {
        ContentTabSidebarButtonHost(
            item: item,
            reorderDragSource: reorderDragSource,
            moveTargets: moveTargets,
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
            onActivate: handlePrimaryAction,
            onToggleSelection: handleToggleSelection,
            onSelectRange: handleSelectRange,
            onDuplicate: onDuplicate,
            onPin: onPin,
            onUnpin: onUnpin,
            onClose: onContextMenuClose,
            onMove: onMove,
        )
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
        .overlay(alignment: .trailing) {
            if isHovered {
                SidebarCloseButton(systemName: item.isPinned ? "minus" : "xmark", action: onClose)
                    .padding(.trailing, 14)
            }
        }
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
    let reorderDragSource: ContentTabReorderDragSourceConfiguration?
    let moveTargets: [ContentTabMoveTarget]
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
    let onActivate: () -> Void
    let onToggleSelection: () -> Void
    let onSelectRange: () -> Void
    let onDuplicate: (() -> Void)?
    let onPin: (() -> Void)?
    let onUnpin: (() -> Void)?
    let onClose: () -> Void
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
        button.update(
            rootView: AnyView(hostedRoot),
            accessibilityLabel: item.title ?? "Untitled",
            accessibilityValue: accessibilityStateValue,
            tabID: item.id,
            duplicateAccessibilityIdentifier: duplicateAccessibilityIdentifier,
            isPinned: item.isPinned,
            isEnabled: true,
            reorderDragSource: reorderDragSource,
            moveTargets: moveTargets,
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
        )
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
final class ContentTabSidebarButton: NSButton, NSDraggingSource {
    private enum PointerRoute {
        case activate
        case toggleSelection
        case selectRange
        case contextMenu
    }

    private struct PointerTracking {
        let mouseDownEvent: NSEvent
        let route: PointerRoute
        let localOrigin: NSPoint
        let dragSource: ContentTabReorderDragSourceConfiguration
    }

    private enum PointerState {
        case idle
        case tracking(PointerTracking)
        case dragging(ContentTabReorderPasteboardWriter)
    }

    private static let reorderDragThreshold: CGFloat = 4

    private let presentationView = ContentTabSidebarPresentationHostingView(rootView: AnyView(EmptyView()))
    private var pointerState = PointerState.idle
    private var pointerRoute: PointerRoute?
    private var reorderDragSource: ContentTabReorderDragSourceConfiguration?
    private var moveTargets: [ContentTabMoveTarget] = []
    private var moveTargetsTabID = ContentTabID(rawValue: "")
    private var isMovePending = false
    private var onMove: (UUID) -> Void = { _ in }
    private var onActivate: () -> Void = {}
    private var onToggleSelection: () -> Void = {}
    private var onSelectRange: () -> Void = {}
    private var onDuplicate: (() -> Void)?
    private var onPin: (() -> Void)?
    private var onUnpin: (() -> Void)?
    private var onClose: () -> Void = {}
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

    func update(
        rootView: AnyView,
        accessibilityLabel: String,
        accessibilityValue: String,
        tabID: ContentTabID? = nil,
        duplicateAccessibilityIdentifier: String,
        isPinned: Bool,
        isEnabled: Bool,
        reorderDragSource: ContentTabReorderDragSourceConfiguration?,
        moveTargets: [ContentTabMoveTarget] = [],
        isMovePending: Bool = false,
        onActivate: @escaping () -> Void,
        onToggleSelection: @escaping () -> Void,
        onSelectRange: @escaping () -> Void,
        onDuplicate: (() -> Void)?,
        onPin: (() -> Void)?,
        onUnpin: (() -> Void)?,
        onClose: @escaping () -> Void,
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
    ) {
        self.reorderDragSource = reorderDragSource
        self.moveTargets = moveTargets
        if let tabID { moveTargetsTabID = tabID }
        self.isMovePending = isMovePending
        self.onMove = onMove
        self.onActivate = onActivate
        self.onToggleSelection = onToggleSelection
        self.onSelectRange = onSelectRange
        self.onDuplicate = onDuplicate
        self.onPin = onPin
        self.onUnpin = onUnpin
        self.onClose = onClose
        self.duplicateTitle = duplicateTitle
        self.duplicateAccessibilityIdentifier = duplicateAccessibilityIdentifier
        self.isDuplicateEnabled = isDuplicateEnabled
        self.pinTitle = pinTitle ?? (isPinned ? "Unpin" : "Pin")
        self.pinAccessibilityIdentifier = pinAccessibilityIdentifier
        self.isPinEnabled = isPinEnabled ?? isEnabled
        self.closeTitle = closeTitle ?? (isPinned ? "Unpin" : "Close")
        self.closeAccessibilityIdentifier = closeAccessibilityIdentifier
        self.isCloseEnabled = isCloseEnabled ?? isEnabled
        self.usesUnpinCommand = usesUnpinCommand ?? isPinned
        self.showsCloseCommand = showsCloseCommand ?? !isPinned
        self.isPinned = isPinned
        self.isEnabled = isEnabled
        presentationView.rootView = rootView
        setAccessibilityLabel(accessibilityLabel)
        setAccessibilityValue(accessibilityValue)
        if let tabID {
            setAccessibilityIdentifier(ContentTabMoveProjection.rowIdentifier(tabID: tabID))
        }
        menu = makeContextMenu()
        presentationView.invalidateIntrinsicContentSize()
        invalidateIntrinsicContentSize()
        presentationView.needsLayout = true
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
                mouseDownEvent: event,
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
        NSLayoutConstraint.activate([
            presentationView.leadingAnchor.constraint(equalTo: leadingAnchor),
            presentationView.trailingAnchor.constraint(equalTo: trailingAnchor),
            presentationView.topAnchor.constraint(equalTo: topAnchor),
            presentationView.bottomAnchor.constraint(equalTo: bottomAnchor),
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
                    startDragging(from: tracking)
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

    private func startDragging(from tracking: PointerTracking) {
        do {
            let writer = try ContentTabReorderPasteboardWriter(
                configuration: tracking.dragSource,
            )
            let draggingItem = NSDraggingItem(pasteboardWriter: writer)
            draggingItem.setDraggingFrame(bounds, contents: draggingImage())
            pointerState = .dragging(writer)
            isHighlighted = false

            if let dragSessionStartOverride {
                dragSessionStartOverride([draggingItem], tracking.mouseDownEvent)
            } else {
                beginDraggingSession(
                    with: [draggingItem],
                    event: tracking.mouseDownEvent,
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
            let moveItem = NSMenuItem(title: "Move to Window", action: nil, keyEquivalent: "")
            moveItem.identifier = NSUserInterfaceItemIdentifier(
                ContentTabMoveProjection.menuIdentifier(tabID: moveTargetsTabID),
            )
            moveItem.isEnabled = !isMovePending
            let submenu = NSMenu(title: "Move to Window")
            submenu.autoenablesItems = false
            for target in moveTargets {
                let targetItem = menuItem(title: target.displayTitle, action: #selector(moveToWindow(_:)))
                targetItem.identifier = NSUserInterfaceItemIdentifier(
                    ContentTabMoveProjection.targetIdentifier(
                        tabID: moveTargetsTabID,
                        windowID: target.windowID,
                    ),
                )
                targetItem.representedObject = target.windowID.uuidString
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

    @objc private func moveToWindow(_ sender: NSMenuItem) {
        guard !isMovePending,
              let rawWindowID = sender.representedObject as? String,
              let windowID = UUID(uuidString: rawWindowID)
        else { return }
        onMove(windowID)
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

private func applicationsSidebarIcon() -> NSImage? {
    let appIcon = NSImage(
        contentsOfFile:
        "/System/Library/CoreServices/CoreTypes.bundle"
            + "/Contents/Resources/SidebarApplicationsFolder.icns",
    )
    appIcon?.isTemplate = true
    return appIcon
}

private struct FixedLocationGridMetrics {
    let columns: [GridItem]
    let cellWidth: CGFloat
}

private func normalizedSidebarIconName(_ iconName: String) -> String {
    iconName == "appstore" ? "folder.badge.gearshape" : iconName
}

private struct SidebarSymbolIcon: View {
    let systemName: String
    let size: CGFloat
    let iconSize: CGFloat
    var foregroundColor: Color = .accentColor

    var body: some View {
        Group {
            if isApplicationsIcon, let appIcon = applicationsSidebarIcon() {
                Image(nsImage: appIcon)
                    .renderingMode(.template)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFit()
                    .frame(width: applicationsIconSize, height: applicationsIconSize)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: normalizedSidebarIconName(systemName))
                    .font(.system(size: iconSize, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .accessibilityHidden(true)
            }
        }
        .foregroundColor(foregroundColor)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var applicationsIconSize: CGFloat {
        max(12, iconSize - 2)
    }

    private var isApplicationsIcon: Bool {
        systemName == "appstore" || systemName == "folder.badge.gearshape"
    }
}

private struct FixedLocationButton: View {
    let item: FileManagerFixedLocationItem
    let workspaceClient: WorkspaceClient
    let width: CGFloat
    let height: CGFloat
    let isHovered: Bool
    let isDropTarget: Bool
    let onSelect: () -> Void
    let onHover: (Bool) -> Void

    @Environment(\.colorScheme)
    private var colorScheme

    @State private var resolvedIcon: NSImage?

    var body: some View {
        Button(action: onSelect) {
            icon
                .frame(width: width, height: height)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(backgroundColor),
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.primary.opacity(isHovered || isDropTarget ? 0.12 : 0.06), lineWidth: 1),
                )
        }
        .buttonStyle(.plain)
        .help("\(item.title)\n\(item.path)")
        .accessibilityLabel(item.accessibilityLabel)
        .onHover(perform: onHover)
        .task(id: item.path) {
            resolvedIcon = nil
            let icon = await workspaceClient.iconForFileAsync(item.path)
            guard !Task.isCancelled else { return }
            resolvedIcon = icon
        }
    }

    @ViewBuilder private var icon: some View {
        if let resolvedIcon {
            Image(nsImage: resolvedIcon)
                .renderingMode(.original)
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .scaledToFit()
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)
        } else {
            Image(systemName: "folder")
                .font(.system(size: 16, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)
        }
    }

    private var backgroundColor: Color {
        isHovered || isDropTarget
            ? VoyagerDS.Interaction.hoverFill(for: colorScheme)
            : Color.primary.opacity(0.06)
    }
}

private struct SidebarCloseButton: View {
    let systemName: String
    let action: () -> Void

    @Environment(\.colorScheme)
    private var colorScheme

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .medium))
                .accessibilityHidden(true)
                .foregroundColor(.secondary)
                .frame(width: 18, height: 18)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isHovered ? VoyagerDS.Interaction.hoverFill(for: colorScheme) : Color.clear),
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
