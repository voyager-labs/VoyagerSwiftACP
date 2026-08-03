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

    @State private var topNavigationReorderDragScopeID = FileManagerTopNavigationReorderDragScopeID(
        boundaryOwner: .topNavigation,
    )
    @State private var unpinnedContentTabReorderDragScopeID = FileManagerTopNavigationReorderDragScopeID(
        boundaryOwner: .unpinnedContentTabs,
    )
    @State private var reorderSessionStore = FileManagerTopNavigationReorderLocalSessionStore()
    @State private var activeTopNavigationReorderBoundaryID: Int?
    @State private var activeUnpinnedReorderBoundaryID: Int?

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
        .alert(
            "Sidebar Arrangement",
            isPresented: Binding(
                get: { sidebarStore.topNavigationArrangementPresentation != nil },
                set: { isPresented in
                    if !isPresented {
                        sidebarStore.send(.view(.dismissTopNavigationPresentation))
                    }
                },
            ),
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(sidebarStore.topNavigationArrangementPresentation?.message ?? "")
        }
        .onDisappear {
            activeTopNavigationReorderBoundaryID = nil
            activeUnpinnedReorderBoundaryID = nil
            reorderSessionStore.clear()
        }
    }

    private var contentTabsViewport: some View {
        GeometryReader { proxy in
            ZStack {
                Color.clear

                ScrollView {
                    VStack(spacing: 0) {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            reorderablePinnedContentTabRows(pinnedTopNavigationItems)

                            if !pinnedTopNavigationItems.isEmpty,
                               !sidebarStore.unpinnedContentTabItems.isEmpty
                            {
                                contentTabSectionDivider
                            }

                            reorderableContentTabRows(sidebarStore.unpinnedContentTabItems)

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
                    .frame(
                        maxWidth: .infinity,
                        minHeight: proxy.size.height,
                        alignment: .top,
                    )
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

    private var contentTabSelectionPresentation: ContentTabSelectionPresentation {
        ContentTabSelectionPresentation(selectedTabIDs: contentTabStore.selectedTabIDs)
    }

    private var fixedLocationTopNavigationItems: [FileManagerFixedLocationItem] {
        sidebarStore.topNavigationItems.compactMap { item in
            guard case let .location(location) = item else { return nil }
            return location
        }
    }

    private var pinnedTopNavigationItems: [ContentTabProjection.ContentTabSidebarItem] {
        sidebarStore.topNavigationItems.compactMap { item in
            guard case let .contentTab(contentTab) = item else { return nil }
            return contentTab
        }
    }

    @ViewBuilder private var fixedLocationsGrid: some View {
        if fixedLocationTopNavigationItems.isEmpty {
            Color.clear
                .frame(height: fixedLocationGridVerticalPadding * 2 + fixedLocationCellHeight)
                .contentShape(Rectangle())
                .contextMenu { fixedLocationsVisibilityMenu }
                .padding(.horizontal, fixedLocationGridHorizontalPadding)
                .padding(.vertical, fixedLocationGridVerticalPadding)
                .padding(.bottom, fixedLocationGridBottomSpacing)
        } else {
            LazyVGrid(
                columns: [GridItem(
                    .adaptive(minimum: fixedLocationMinimumCellWidth),
                    spacing: fixedLocationGridGap,
                    alignment: .center,
                )],
                alignment: .leading,
                spacing: fixedLocationGridGap,
            ) {
                ForEach(Array(fixedLocationTopNavigationItems.enumerated()), id: \.element.id) { index, item in
                    let dropTarget = FileManagerSidebarEntryDropTarget.fixedLocation(item.id)
                    let itemID = FileManagerTopNavigationItemID.location(item.id)
                    FixedLocationButton(
                        item: item,
                        workspaceClient: workspaceClient,
                        height: fixedLocationCellHeight,
                        isHovered: fixedLocationHoveredItemID == item.id,
                        isDropTarget: sidebarEntryDropTarget == dropTarget,
                        reorderDragSource: reorderDragSource(for: itemID, owner: .topNavigation),
                        onSelect: {
                            sidebarStore.send(.delegate(.selectFixedLocation(item.id)))
                        },
                        onHover: { isHovered in
                            fixedLocationHoveredItemID = isHovered ? item.id : nil
                        },
                    )
                    .overlay {
                        fixedLocationReorderDropOverlay(itemID: itemID, index: index)
                    }
                    .onDrop(
                        of: [.fileURL],
                        delegate: entryDropDelegate(for: dropTarget, allowsCopy: item.kind != .trash),
                    )
                    .topNavigationMoveCommands(
                        sourceID: itemID,
                        onMove: sendTopNavigationMoveRequest,
                    )
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, fixedLocationGridHorizontalPadding)
            .padding(.vertical, fixedLocationGridVerticalPadding)
            .padding(.bottom, fixedLocationGridBottomSpacing)
            .animation(.easeInOut(duration: 0.15), value: fixedLocationTopNavigationItems.map(\.id))
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

                ForEach(sidebarStore.fixedLocationVisibilityMenuItems) { item in
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

    private var contentTabSectionDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.12))
            .frame(height: 1)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
    }

    @ViewBuilder
    private func reorderableContentTabRows(
        _ items: [ContentTabProjection.ContentTabSidebarItem],
    ) -> some View {
        if !items.isEmpty {
            let boundaries = FileManagerTopNavigationReorderDropBoundary.make(
                for: items.map { .contentTab($0.id) },
                owner: .unpinnedContentTabs,
            )

            VStack(alignment: .leading, spacing: 0) {
                fileManagerTopNavigationReorderDropSlot(boundaries[0])
                    .transaction { $0.animation = nil }

                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    reorderableContentTabRow(item)
                    fileManagerTopNavigationReorderDropSlot(boundaries[index + 1])
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
        owner: FileManagerTopNavigationReorderBoundaryOwner,
    ) -> FileManagerTopNavigationReorderDragSourceConfiguration? {
        guard let sourceWindowID = sidebarStore.currentWindowID,
              sidebarStore.pendingContentTabMoveRequest == nil
        else { return nil }
        return FileManagerTopNavigationReorderDragSourceConfiguration(
            payload: FileManagerTopNavigationReorderDragPayload(
                sourceID: .contentTab(item.id),
                dragScopeID: reorderDragScopeID(for: owner),
            ),
            sessionStore: reorderSessionStore,
            movePayload: ContentTabDragPayload(
                schemaVersion: ContentTabDragPayload.supportedSchemaVersion,
                sourceWindowID: sourceWindowID,
                tabID: item.id,
            ),
        )
    }

    private func reorderableContentTabRow(
        _ item: ContentTabProjection.ContentTabSidebarItem,
    ) -> some View {
        entryDroppableContentTabRow(
            item,
            reorderDragSource: contentTabDragSource(
                for: item,
                owner: .unpinnedContentTabs,
            ),
        )
    }

    private func fileManagerTopNavigationReorderDropSlot(
        _ boundary: FileManagerTopNavigationReorderDropBoundary,
    ) -> some View {
        Rectangle()
            .fill(Color.clear)
            .frame(height: 4)
            .frame(maxWidth: .infinity)
            .overlay {
                if activeReorderBoundaryID(for: boundary.owner) == boundary.id {
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(height: 2)
                        .allowsHitTesting(false)
                }
            }
            .padding(.horizontal, 8)
            .background {
                fileManagerTopNavigationReorderDropDestination(for: boundary)
            }
            .contentShape(Rectangle())
    }

    @ViewBuilder
    private func entryDroppableContentTabRow(
        _ item: ContentTabProjection.ContentTabSidebarItem,
        reorderDragSource: FileManagerTopNavigationReorderDragSourceConfiguration?,
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
        reorderDragSource: FileManagerTopNavigationReorderDragSourceConfiguration?,
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

    private func fileManagerTopNavigationReorderDropDestination(
        for boundary: FileManagerTopNavigationReorderDropBoundary,
    ) -> FileManagerTopNavigationReorderDropDestination {
        FileManagerTopNavigationReorderDropDestination(
            activeBoundaryID: activeReorderBoundaryIDBinding(for: boundary.owner),
            boundary: boundary,
            dragScopeID: reorderDragScopeID(for: boundary.owner),
            sessionStore: reorderSessionStore,
            boundaryOwnerForItem: { id in
                if sidebarStore.topNavigationItems.contains(where: { $0.id == id }) {
                    return .topNavigation
                }
                if sidebarStore.unpinnedContentTabItems.contains(where: { .contentTab($0.id) == id }) {
                    return .unpinnedContentTabs
                }
                return nil
            },
            onReorder: { result in
                sidebarStore.send(.view(.fileManagerTopNavigationReorderRequested(
                    sourceID: result.sourceID,
                    anchorID: result.anchorID,
                    placement: result.placement,
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

private extension SidebarView {
    @ViewBuilder
    private func reorderablePinnedContentTabRows(
        _ items: [ContentTabProjection.ContentTabSidebarItem],
    ) -> some View {
        if !items.isEmpty {
            let boundaries = FileManagerTopNavigationReorderDropBoundary.make(
                for: items.map { .contentTab($0.id) },
                owner: .topNavigation,
            )

            VStack(alignment: .leading, spacing: 0) {
                fileManagerTopNavigationReorderDropSlot(boundaries[0])
                    .transaction { $0.animation = nil }

                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    entryDroppableContentTabRow(
                        item,
                        reorderDragSource: contentTabDragSource(
                            for: item,
                            owner: .topNavigation,
                        ),
                    )
                    .topNavigationMoveCommands(
                        sourceID: .contentTab(item.id),
                        onMove: sendTopNavigationMoveRequest,
                    )
                    fileManagerTopNavigationReorderDropSlot(boundaries[index + 1])
                        .transaction { $0.animation = nil }
                }
            }
            .animation(.easeInOut(duration: 0.15), value: items.map(\.id))
        }
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
        fileManagerTopNavigationReorderDropDestination(for: boundary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transaction { $0.animation = nil }
    }

    private func activeReorderBoundaryID(
        for owner: FileManagerTopNavigationReorderBoundaryOwner,
    ) -> Int? {
        switch owner {
        case .topNavigation:
            activeTopNavigationReorderBoundaryID
        case .unpinnedContentTabs:
            activeUnpinnedReorderBoundaryID
        }
    }

    private func activeReorderBoundaryIDBinding(
        for owner: FileManagerTopNavigationReorderBoundaryOwner,
    ) -> Binding<Int?> {
        switch owner {
        case .topNavigation:
            $activeTopNavigationReorderBoundaryID
        case .unpinnedContentTabs:
            $activeUnpinnedReorderBoundaryID
        }
    }

    private func reorderDragSource(
        for sourceID: FileManagerTopNavigationItemID,
        owner: FileManagerTopNavigationReorderBoundaryOwner,
    ) -> FileManagerTopNavigationReorderDragSourceConfiguration {
        FileManagerTopNavigationReorderDragSourceConfiguration(
            payload: FileManagerTopNavigationReorderDragPayload(
                sourceID: sourceID,
                dragScopeID: reorderDragScopeID(for: owner),
            ),
            sessionStore: reorderSessionStore,
        )
    }

    private func reorderDragScopeID(
        for owner: FileManagerTopNavigationReorderBoundaryOwner,
    ) -> FileManagerTopNavigationReorderDragScopeID {
        switch owner {
        case .topNavigation:
            topNavigationReorderDragScopeID
        case .unpinnedContentTabs:
            unpinnedContentTabReorderDragScopeID
        }
    }

    private func sendTopNavigationMoveRequest(
        sourceID: FileManagerTopNavigationItemID,
        direction: FileManagerSidebarTopNavigationMoveDirection,
    ) {
        let visibleItemIDs: [FileManagerTopNavigationItemID] = switch sourceID {
        case .location:
            fixedLocationTopNavigationItems.map { .location($0.id) }
        case .contentTab:
            pinnedTopNavigationItems.map { .contentTab($0.id) }
        }
        guard let request = FileManagerSidebarTopNavigationMoveAdapter.request(
            sourceID: sourceID,
            direction: direction,
            visibleItemIDs: visibleItemIDs,
        ) else { return }

        sidebarStore.send(.view(.fileManagerTopNavigationReorderRequested(
            sourceID: request.sourceID,
            anchorID: request.anchorID,
            placement: request.placement,
        )))
    }
}

private extension View {
    func topNavigationMoveCommands(
        sourceID: FileManagerTopNavigationItemID,
        onMove: @escaping (
            FileManagerTopNavigationItemID,
            FileManagerSidebarTopNavigationMoveDirection,
        ) -> Void,
    ) -> some View {
        modifier(FileManagerSidebarTopNavigationMoveCommandsModifier(
            sourceID: sourceID,
            onMove: onMove,
        ))
    }
}

enum FileManagerSidebarTopNavigationMoveKeyCommandClassifier {
    static func matches(_ modifierFlags: NSEvent.ModifierFlags) -> Bool {
        let expectedModifiers: NSEvent.ModifierFlags = [.option, .command]
        let userModifiers: NSEvent.ModifierFlags = [.command, .option, .shift, .control]
        return modifierFlags.intersection(userModifiers) == expectedModifiers
    }
}

private struct FileManagerSidebarTopNavigationMoveCommandsModifier: ViewModifier {
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
    let reorderDragSource: FileManagerTopNavigationReorderDragSourceConfiguration?
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
    let reorderDragSource: FileManagerTopNavigationReorderDragSourceConfiguration?
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
    private var pointerState = PointerState.idle
    private var pointerRoute: PointerRoute?
    private var reorderDragSource: FileManagerTopNavigationReorderDragSourceConfiguration?
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
        reorderDragSource: FileManagerTopNavigationReorderDragSourceConfiguration?,
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
    let height: CGFloat
    let isHovered: Bool
    let isDropTarget: Bool
    let reorderDragSource: FileManagerTopNavigationReorderDragSourceConfiguration?
    let onSelect: () -> Void
    let onHover: (Bool) -> Void

    @Environment(\.colorScheme)
    private var colorScheme

    var body: some View {
        FixedLocationSidebarButtonHost(
            rootView: AnyView(tilePresentation),
            accessibilityLabel: item.accessibilityLabel,
            isEnabled: true,
            reorderDragSource: reorderDragSource,
            onActivate: onSelect,
        )
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
        .help("\(item.title)\n\(item.path)")
        .onHover(perform: onHover)
    }

    private var tilePresentation: some View {
        icon
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(backgroundColor),
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.primary.opacity(isHovered || isDropTarget ? 0.12 : 0.06), lineWidth: 1),
            )
    }

    private var icon: some View {
        let finalIcon = workspaceClient.cachedIconForFile(item.path)
            ?? workspaceClient.iconForFile(item.path)
        return Image(nsImage: finalIcon)
            .renderingMode(.original)
            .resizable()
            .interpolation(.high)
            .antialiased(true)
            .scaledToFit()
            .frame(width: 20, height: 20)
            .accessibilityHidden(true)
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
