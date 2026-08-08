import AppKit
import ComposableArchitecture
import HotSwiftUI
import SwiftUI
import UniformTypeIdentifiers
import VoyagerEntitiesTag
import VoyagerShared

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
    @State private var reorderSessionStore = FileManagerTopNavigationReorderLocalSessionStore.shared
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
            // shared session store의 broad clear는 다른 창/최신 drag token을 덮어쓰므로 하지 않는다.
            // session entry는 drag source의 terminal(cleanupOwnedToken) 또는 consume/TTL이 정리한다.
            sidebarStore.send(.view(.teardownContentTabDragSource))
        }
    }

    private var contentTabsViewport: some View {
        GeometryReader { proxy in
            ZStack {
                Color.clear

                ScrollView {
                    VStack(spacing: 0) {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            if pinnedTopNavigationItems.isEmpty {
                                fileManagerTopNavigationReorderDropSlot(.empty(
                                    id: Int.min,
                                    owner: .topNavigation,
                                    domain: .pinned,
                                ))
                            }
                            reorderablePinnedContentTabRows(pinnedTopNavigationItems)

                            if !pinnedTopNavigationItems.isEmpty,
                               !sidebarStore.unpinnedContentTabItems.isEmpty
                            {
                                contentTabSectionDivider
                            }

                            reorderableContentTabRows(sidebarStore.unpinnedContentTabItems)
                            if sidebarStore.unpinnedContentTabItems.isEmpty {
                                fileManagerTopNavigationReorderDropSlot(.empty(
                                    id: Int.min + 1,
                                    owner: .unpinnedContentTabs,
                                    domain: .unpinned,
                                ))
                            }

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
        // 외부 창 Content Tab drop은 production adapter로 typed route를 구한 뒤 preserve-domain transfer만 dispatch한다.
        // 같은 창 명시 전환/배치 전송 의도는 later task가, Entry/File URL/Location은 기존 owner가 담당한다.
        let route = ContentTabDropRouteProjection.route(
            payload: payload,
            targetWindowID: currentWindowID,
            targetDomain: nil,
            placement: nil,
            targetSurface: .contentTabDomain,
        )
        guard route == .foreignPreserveDomainTransfer else { return }
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

    private var fixedLocationsGrid: some View {
        SidebarFixedLocationsSection(
            items: fixedLocationTopNavigationItems,
            workspaceClient: workspaceClient,
            hoveredItemID: fixedLocationHoveredItemID,
            sidebarEntryDropTarget: sidebarEntryDropTarget,
            menuContent: { fixedLocationsVisibilityMenu },
            reorderDragSource: { itemID in
                reorderDragSource(for: itemID, owner: .topNavigation)
            },
            reorderDropDestination: fileManagerTopNavigationReorderDropDestination,
            entryDropDelegate: { target, allowsCopy in
                entryDropDelegate(for: target, allowsCopy: allowsCopy)
            },
            onMove: sendTopNavigationMoveRequest,
            onSelect: { itemID in
                sidebarStore.send(.delegate(.selectFixedLocation(itemID)))
            },
            onHover: { itemID in
                fixedLocationHoveredItemID = itemID
            },
        )
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

    private var contentTabSectionDivider: some View {
        SidebarContentTabSectionDivider()
    }

    @ViewBuilder
    private func reorderableContentTabRows(
        _ items: [ContentTabProjection.ContentTabSidebarItem],
    ) -> some View {
        if !items.isEmpty {
            let boundaries = FileManagerTopNavigationReorderDropBoundary.make(
                for: items.map { .contentTab($0.id) },
                owner: .unpinnedContentTabs,
                contentTabDomain: .unpinned,
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
        SidebarNewContentTabRow(
            isHovered: isNewTabHovered,
            onHover: { isNewTabHovered = $0 },
            onOpen: {
                sidebarStore.send(.delegate(.openContentTab))
            },
        )
    }

    private func contentTabDragSource(
        for item: ContentTabProjection.ContentTabSidebarItem,
        owner: FileManagerTopNavigationReorderBoundaryOwner,
    ) -> FileManagerTopNavigationReorderDragSourceConfiguration? {
        guard sidebarStore.currentWindowID != nil,
              sidebarStore.pendingContentTabMoveRequest == nil,
              sidebarStore.contentTabDragSnapshot?.lifecycle != .inFlight
        else { return nil }
        return FileManagerTopNavigationReorderDragSourceConfiguration(
            payload: FileManagerTopNavigationReorderDragPayload(
                sourceID: .contentTab(item.id),
                dragScopeID: reorderDragScopeID(for: owner),
            ),
            sessionStore: reorderSessionStore,
            prepareMovePayload: {
                sidebarStore.send(.view(.prepareContentTabDrag(
                    initiatingTabID: item.id,
                    selectedTabIDs: contentTabStore.selectedTabIDs,
                )))
                guard let snapshot = sidebarStore.contentTabDragSnapshot,
                      snapshot.initiatingTabID == item.id,
                      snapshot.lifecycle == .prepared
                else { return nil }
                return snapshot.payload
            },
            onMovePayloadDidBegin: { payload in
                sidebarStore.send(.view(.beginContentTabDrag(payload)))
            },
            onMovePayloadDidEnd: { operationID in
                sidebarStore.send(.view(.contentTabDragTerminal(operationID: operationID)))
            },
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
        let movePresentation = ContentTabMoveMenuPresentation(
            clickedTabID: item.id,
            validSelectedTabIDs: interactionStore.validSelectedTabIDs,
            displayedOrderedTabIDs: sidebarStore.contentTabSelectionOrderedIDs,
        )
        let trailingAction = ContentTabSidebarTrailingCommand(isPinned: item.isPinned)
        return ContentTabSidebarRow(
            item: item,
            reorderDragSource: reorderDragSource,
            moveTargets: ContentTabMoveProjection.availableTargets(
                sidebarStore.contentTabMoveTargets,
                currentWindowID: sidebarStore.currentWindowID,
                orderedTabIDs: movePresentation.orderedTabIDs,
            ),
            moveTitle: movePresentation.title,
            isMovePending: ContentTabMovePendingProjection.isPending(
                tabID: item.id,
                request: sidebarStore.pendingContentTabMoveRequest,
            ),
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
            onTrailingAction: {
                sidebarStore.send(.delegate(trailingAction.delegateAction(tabID: item.id)))
            },
            onContextMenuClose: {
                sidebarStore.send(.delegate(closePresentation.delegateAction))
            },
            onMove: { targetWindowID in
                sidebarStore.send(.view(movePresentation.viewAction(targetWindowID: targetWindowID)))
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
            targetWindowID: sidebarStore.currentWindowID,
            contentTabIDsInDomain: { domain in
                switch domain {
                case .pinned: pinnedTopNavigationItems.map(\.id)
                case .unpinned: sidebarStore.unpinnedContentTabItems.map(\.id)
                }
            },
            onDomainTransition: { request in
                sidebarStore.send(.view(.contentTabDomainTransitionRequested(request)))
            },
            onForeignExplicitTransfer: { payload, targetDomain, placement in
                sidebarStore.send(.view(.receiveContentTabExplicitDomainDrag(
                    payload: payload,
                    targetDomain: targetDomain,
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

private extension SidebarView {
    @ViewBuilder
    private func reorderablePinnedContentTabRows(
        _ items: [ContentTabProjection.ContentTabSidebarItem],
    ) -> some View {
        if !items.isEmpty {
            let boundaries = FileManagerTopNavigationReorderDropBoundary.make(
                for: items.map { .contentTab($0.id) },
                owner: .topNavigation,
                contentTabDomain: .pinned,
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

extension View {
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
