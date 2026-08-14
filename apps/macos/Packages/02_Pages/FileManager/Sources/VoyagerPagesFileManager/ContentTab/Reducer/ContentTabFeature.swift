import ComposableArchitecture
import Foundation
import VoyagerEntitiesCollection
import VoyagerShared

@Reducer
public struct ContentTabFeature {
    public typealias State = ContentTabState
    public typealias Action = ContentTabAction

    @Dependency(\.entryLoadingClient)
    var entryLoadingClient
    @Dependency(\.fileManagerIconClient)
    var fileManagerIconClient
    @Dependency(\.contentTabPinnedRecordClient)
    var contentTabPinnedRecordClient
    @Dependency(\.contentTabPinnedRecordPersistenceRouting)
    var pinnedRecordPersistenceRouting
    @Dependency(\.userDefaultsClient)
    var userDefaultsClient
    @Dependency(\.date)
    var date

    public init() {}

    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .delegate:
                return .none

            case let .open(anchor):
                return open(anchor: anchor, state: &state)

            case let .setCurrent(id):
                return setCurrent(id: id, state: &state)

            case let .toggleSelection(id):
                return toggleSelection(id: id, state: &state)

            case let .selectRange(targetID, orderedIDs):
                return selectRange(to: targetID, orderedIDs: orderedIDs, state: &state)

            case .collapseSelectionToActive:
                return collapseSelectionToActive(state: &state)

            case .requestClose:
                return .none

            case let .close(id):
                return commitClose(id: id, preservesLastTabIdentity: false, state: &state)

            case let .commitClose(id):
                return commitClose(id: id, preservesLastTabIdentity: true, state: &state)

            case .restore:
                return restore(state: &state)

            case let .duplicate(sourceID, duplicateID):
                return duplicate(sourceID: sourceID, duplicateID: duplicateID, state: &state)

            case let .duplicateSelected(requests):
                return duplicateSelected(requests: requests, state: &state)

            case let .reorder(sourceID, targetID, placement):
                return reorder(
                    orderedMovingIDs: [sourceID],
                    anchorID: targetID,
                    placement: placement,
                    state: &state,
                )

            case let .reorderGroup(orderedMovingIDs, anchorID, placement):
                return reorder(
                    orderedMovingIDs: orderedMovingIDs,
                    anchorID: anchorID,
                    placement: placement,
                    state: &state,
                )

            case let .pin(id, placement):
                return pin(id: id, dormantSlot: nil, placement: placement, state: &state)

            case let .pinUsingDormantSlot(id, dormantSlot):
                return pin(id: id, dormantSlot: dormantSlot, placement: nil, state: &state)

            case let .unpin(id, placement):
                return unpin(id: id, placement: placement, state: &state)

            case let .updateActivePageAnchor(id, newAnchor):
                return updateActivePageAnchor(id: id, newAnchor: newAnchor, state: &state)

            case let .updateRuntimePageAnchor(id, newAnchor):
                return updateRuntimePageAnchor(id: id, newAnchor: newAnchor, state: &state)

            case let .pinnedRecordSaveSucceeded(tabID, context):
                guard state.isCurrentPinnedRecordPersistenceIntent(tabID: tabID, intentID: context.intentID) else {
                    return .none
                }
                state.pendingPinnedRecordIDs.remove(tabID)
                state.pinnedRecordPersistenceError = nil
                return .none

            case let .pinnedRecordSaveFailed(
                tabID,
                context,
                rollback,
            ), let .pinnedRecordStoreUnavailable(
                tabID,
                context,
                _,
                rollback,
            ):
                guard state.isCurrentPinnedRecordPersistenceIntent(tabID: tabID, intentID: context.intentID) else {
                    return .none
                }
                restorePinnedRecordSnapshot(
                    tabID: tabID,
                    previousIsPinned: rollback.previousIsPinned,
                    previousPinnedRecord: rollback.previousPinnedRecord,
                    previousTabIndex: rollback.previousTabIndex,
                    state: &state,
                )
                state.pendingPinnedRecordIDs.remove(tabID)
                state.pinnedRecordPersistenceError = "pinned_record_save_failed"
                return .none

            case let .pinnedRecordSaveNotApplied(tabID, context, _, rollback):
                guard state.isCurrentPinnedRecordPersistenceIntent(tabID: tabID, intentID: context.intentID) else {
                    return .none
                }
                restorePinnedRecordSnapshot(
                    tabID: tabID,
                    previousIsPinned: rollback.previousIsPinned,
                    previousPinnedRecord: rollback.previousPinnedRecord,
                    previousTabIndex: rollback.previousTabIndex,
                    state: &state,
                )
                state.pendingPinnedRecordIDs.remove(tabID)
                state.pinnedRecordPersistenceError = nil
                return .none
            }
        }
    }
}

extension ContentTabFeature {
    // MARK: - CTM-001-select_content_tabs

    /// 유효한 target만 membership을 반전하고 deselect를 포함해 target을 anchor로 유지한다.
    private func toggleSelection(
        id: ContentTabID,
        state: inout ContentTabState,
    ) -> Effect<ContentTabAction> {
        guard state.tabs[id: id] != nil else { return .none }

        if state.selectedTabIDs.contains(id), state.activeTabID != id {
            state.selectedTabIDs.remove(id)
        } else {
            state.selectedTabIDs.insert(id)
        }
        state.selectionAnchorID = id
        return .none
    }

    /// pinned-first ordering의 anchor-target inclusive interval로 기존 선택을 교체한다.
    private func selectRange(
        to targetID: ContentTabID,
        orderedIDs: [ContentTabID],
        state: inout ContentTabState,
    ) -> Effect<ContentTabAction> {
        guard state.tabs[id: targetID] != nil else { return .none }

        guard let anchorID = state.selectionAnchorID,
              let anchorIndex = orderedIDs.firstIndex(of: anchorID),
              let targetIndex = orderedIDs.firstIndex(of: targetID)
        else {
            state.selectedTabIDs = [targetID]
            state.reconcileSelection()
            state.selectionAnchorID = targetID
            return .none
        }

        let lowerBound = min(anchorIndex, targetIndex)
        let upperBound = max(anchorIndex, targetIndex)
        state.selectedTabIDs = Set(orderedIDs[lowerBound ... upperBound])
        state.reconcileSelection()
        return .none
    }

    private func collapseSelectionToActive(state: inout ContentTabState) -> Effect<ContentTabAction> {
        state.collapseSelectionToActive()
        return .none
    }

    private func open(anchor: ContentTabPageAnchor, state: inout ContentTabState) -> Effect<ContentTabAction> {
        guard state.tabs.count < ContentTabConstants.maxTabs else {
            state.previousActiveTabID = nil
            return .none
        }

        let previousActiveTabID = state.activeTabID
        let item = ContentTabItem(
            id: ContentTabID(),
            page: page(for: anchor),
            anchor: anchor,
            isPinned: false,
            title: title(for: anchor),
            iconName: iconName(for: anchor),
        )
        state.tabs.append(item)
        state.previousActiveTabID = previousActiveTabID
        state.activeTabID = item.id
        return .none
    }

    private func setCurrent(id: ContentTabID, state: inout ContentTabState) -> Effect<ContentTabAction> {
        guard state.tabs[id: id] != nil else { return .none }
        guard state.activeTabID != id else {
            state.previousActiveTabID = nil
            return .none
        }
        state.previousActiveTabID = state.activeTabID
        state.activeTabID = id
        return .none
    }

    private func commitClose(
        id: ContentTabID,
        preservesLastTabIdentity: Bool,
        state: inout ContentTabState,
    ) -> Effect<ContentTabAction> {
        guard !state.pendingPinnedRecordIDs.contains(id) else { return .none }
        guard let tab = state.tabs[id: id] else {
            state.previousActiveTabID = nil
            return .none
        }

        if tab.isPinned {
            return unpin(id: id, placement: nil, state: &state)
        }

        if state.tabs.count == 1 {
            if case .aiChat = tab.anchor {
                let snapshot = ClosedContentTabSnapshot(
                    page: tab.page,
                    anchor: tab.anchor,
                    wasPinned: tab.isPinned,
                    closedAt: Date(),
                    title: tab.title,
                    iconName: tab.iconName,
                )
                state.recentlyClosed = snapshot
            }

            state.previousActiveTabID = id
            if preservesLastTabIdentity {
                state.tabs[id: id]?.page = .home
                state.tabs[id: id]?.anchor = .homeDefault
                state.tabs[id: id]?.title = "Home"
                state.tabs[id: id]?.iconName = "house"
                state.activeTabID = id
                return .none
            }

            let homeTab = ContentTabItem(
                id: ContentTabID(),
                page: .home,
                anchor: .homeDefault,
                isPinned: false,
                title: "Home",
                iconName: "house",
            )
            state.tabs.remove(id: id)
            state.tabs.append(homeTab)
            state.activeTabID = homeTab.id
            state.selectedTabIDs = [homeTab.id]
            state.selectionAnchorID = homeTab.id
            return .none
        }

        closeRemainingTab(id: id, tab: tab, state: &state)
        return .none
    }

    private func closeRemainingTab(
        id: ContentTabID,
        tab: ContentTabItem,
        state: inout ContentTabState,
    ) {
        state.recentlyClosed = ClosedContentTabSnapshot(
            page: tab.page,
            anchor: tab.anchor,
            wasPinned: tab.isPinned,
            closedAt: Date(),
            title: tab.title,
            iconName: tab.iconName,
        )
        let wasActive = state.activeTabID == id
        let fallbackTabID = fallbackTabID(afterClosing: id, state: state)
        state.tabs.remove(id: id)
        state.reconcileSelection()
        state.previousActiveTabID = wasActive ? id : nil
        if wasActive { state.activeTabID = fallbackTabID }
    }

    private func fallbackTabID(
        afterClosing id: ContentTabID,
        state: ContentTabState,
    ) -> ContentTabID? {
        guard let closingIndex = state.tabs.firstIndex(where: { $0.id == id }) else { return nil }
        if let previousID = state.previousActiveTabID,
           previousID != id,
           state.tabs[id: previousID] != nil
        {
            return previousID
        }
        if closingIndex + 1 < state.tabs.endIndex { return state.tabs[closingIndex + 1].id }
        if closingIndex > state.tabs.startIndex { return state.tabs[state.tabs.index(before: closingIndex)].id }
        return state.tabs.first?.id
    }

    private func restore(state: inout ContentTabState) -> Effect<ContentTabAction> {
        guard let snapshot = state.recentlyClosed else {
            state.previousActiveTabID = nil
            return .none
        }
        guard state.tabs.count < ContentTabConstants.maxTabs else {
            state.previousActiveTabID = nil
            return .none
        }

        let item = ContentTabItem(
            id: ContentTabID(),
            page: snapshot.page,
            anchor: snapshot.anchor,
            isPinned: false,
            title: snapshot.title ?? title(for: snapshot.anchor),
            iconName: snapshot.iconName ?? iconName(for: snapshot.anchor),
        )
        state.tabs.append(item)
        state.previousActiveTabID = state.activeTabID
        state.activeTabID = item.id
        state.recentlyClosed = nil
        return .none
    }

    private func duplicate(
        sourceID: ContentTabID,
        duplicateID: ContentTabID,
        state: inout ContentTabState,
    ) -> Effect<ContentTabAction> {
        guard state.tabs.count < ContentTabConstants.maxTabs,
              let source = state.tabs[id: sourceID],
              let duplicateItem = makeDuplicateItem(
                  source: source,
                  duplicateID: duplicateID,
                  existingIDs: Set(state.tabs.ids),
              )
        else {
            return .none
        }

        if source.isPinned {
            let boundaryIndex = state.tabs.firstIndex(where: { !$0.isPinned }) ?? state.tabs.endIndex
            state.tabs.insert(duplicateItem, at: boundaryIndex)
        } else {
            guard let sourceIndex = state.tabs.index(id: sourceID) else { return .none }
            state.tabs.insert(duplicateItem, at: sourceIndex + 1)
            state.previousActiveTabID = state.activeTabID
            state.activeTabID = duplicateID
        }

        return .none
    }

    private func duplicateSelected(
        requests: [ContentTabDuplicateRequest],
        state: inout ContentTabState,
    ) -> Effect<ContentTabAction> {
        let remainingCapacity = ContentTabConstants.maxTabs - state.tabs.count
        guard remainingCapacity > 0, !requests.isEmpty else { return .none }

        let existingIDs = Set(state.tabs.ids)
        var seenSourceIDs = Set<ContentTabID>()
        var seenDuplicateIDs = Set<ContentTabID>()
        var validRequests: [(source: ContentTabItem, duplicate: ContentTabItem)] = []

        for request in requests {
            guard !seenSourceIDs.contains(request.sourceID),
                  !seenDuplicateIDs.contains(request.duplicateID),
                  let source = state.tabs[id: request.sourceID],
                  let duplicate = makeDuplicateItem(
                      source: source,
                      duplicateID: request.duplicateID,
                      existingIDs: existingIDs,
                  )
            else {
                continue
            }

            seenSourceIDs.insert(request.sourceID)
            seenDuplicateIDs.insert(request.duplicateID)
            validRequests.append((source, duplicate))
        }

        let successfulRequests = Array(validRequests.prefix(remainingCapacity))
        guard !successfulRequests.isEmpty else { return .none }

        let preOperationActiveID = state.activeTabID
        var updatedTabs = Array(state.tabs)
        let pinnedSourceDuplicates = successfulRequests
            .filter(\.source.isPinned)
            .map(\.duplicate)
        if !pinnedSourceDuplicates.isEmpty {
            let boundaryIndex = updatedTabs.firstIndex(where: { !$0.isPinned }) ?? updatedTabs.endIndex
            updatedTabs.insert(contentsOf: pinnedSourceDuplicates, at: boundaryIndex)
        }
        for request in successfulRequests where !request.source.isPinned {
            guard let sourceIndex = updatedTabs.firstIndex(where: { $0.id == request.source.id }) else {
                continue
            }
            updatedTabs.insert(request.duplicate, at: sourceIndex + 1)
        }
        state.tabs = .init(uniqueElements: updatedTabs)
        state.previousActiveTabID = preOperationActiveID
        state.activeTabID = successfulRequests[0].duplicate.id
        state.reconcileSelection()
        return .none
    }

    private func makeDuplicateItem(
        source: ContentTabItem,
        duplicateID: ContentTabID,
        existingIDs: Set<ContentTabID>,
    ) -> ContentTabItem? {
        guard !existingIDs.contains(duplicateID),
              isValidDuplicate(page: source.page, anchor: source.anchor)
        else {
            return nil
        }

        return ContentTabItem(
            id: duplicateID,
            page: source.page,
            anchor: source.anchor,
            isPinned: false,
            title: source.title,
            iconName: source.iconName,
        )
    }

    static func reorderedTabs(
        _ tabs: IdentifiedArrayOf<ContentTabItem>,
        orderedMovingIDs: [ContentTabID],
        anchorID: ContentTabID,
        placement: FileManagerTopNavigationReorderPlacement,
    ) -> [ContentTabItem]? {
        let movingIDSet = Set(orderedMovingIDs)
        guard !orderedMovingIDs.isEmpty,
              movingIDSet.count == orderedMovingIDs.count,
              !movingIDSet.contains(anchorID),
              let anchor = tabs[id: anchorID],
              !anchor.isPinned,
              orderedMovingIDs.allSatisfy({ id in
                  guard let tab = tabs[id: id] else { return false }
                  return !tab.isPinned
              })
        else {
            return nil
        }

        let originalUnpinnedIDs = tabs.filter { !$0.isPinned }.map(\.id)
        var reducedUnpinnedIDs = originalUnpinnedIDs.filter { !movingIDSet.contains($0) }
        guard let anchorIndex = reducedUnpinnedIDs.firstIndex(of: anchorID) else {
            return nil
        }

        let insertionIndex = placement == .before ? anchorIndex : anchorIndex + 1
        reducedUnpinnedIDs.insert(contentsOf: orderedMovingIDs, at: insertionIndex)
        guard reducedUnpinnedIDs != originalUnpinnedIDs,
              reducedUnpinnedIDs.count == originalUnpinnedIDs.count,
              Set(reducedUnpinnedIDs) == Set(originalUnpinnedIDs)
        else {
            return nil
        }

        var reorderedUnpinnedIterator = reducedUnpinnedIDs.makeIterator()
        var result: [ContentTabItem] = []
        result.reserveCapacity(tabs.count)
        for tab in tabs {
            if tab.isPinned {
                result.append(tab)
                continue
            }

            guard let reorderedID = reorderedUnpinnedIterator.next(),
                  let reorderedTab = tabs[id: reorderedID]
            else {
                return nil
            }
            result.append(reorderedTab)
        }

        guard reorderedUnpinnedIterator.next() == nil,
              result.count == tabs.count,
              Set(result.map(\.id)) == Set(tabs.map(\.id))
        else {
            return nil
        }
        return result
    }

    private func reorder(
        orderedMovingIDs: [ContentTabID],
        anchorID: ContentTabID,
        placement: FileManagerTopNavigationReorderPlacement,
        state: inout ContentTabState,
    ) -> Effect<ContentTabAction> {
        guard let reorderedTabs = Self.reorderedTabs(
            state.tabs,
            orderedMovingIDs: orderedMovingIDs,
            anchorID: anchorID,
            placement: placement,
        ) else {
            return .none
        }
        state.tabs = .init(uniqueElements: reorderedTabs)
        return .none
    }

    private func isValidDuplicate(page: ContentTabPage, anchor: ContentTabPageAnchor) -> Bool {
        switch (page, anchor) {
        case (.home, .homeDefault):
            true
        case let (.directory, .directory(path)):
            UUID(uuidString: path) == nil
        case (.collection, .collectionFile):
            true
        case (.collection, .virtualCollection):
            true
        case let (.aiChat, .aiChat(sessionID)):
            UUID(uuidString: sessionID) != nil
        default:
            false
        }
    }

    private func pin(
        id: ContentTabID,
        dormantSlot: FileManagerTopNavigationOrderPolicy.DormantContentTabSlot?,
        placement: ContentTabPlacement?,
        state: inout ContentTabState,
    ) -> Effect<ContentTabAction> {
        let preflight: ContentTabPinMutationPreflight.PinContext
        switch ContentTabPinMutationPreflight.pin(id: id, placement: placement, state: state) {
        case let .valid(context):
            preflight = context
        case .incompatiblePageAnchor:
            state.pinnedRecordPersistenceError = nil
            return .none
        case .invalid:
            return .none
        }

        let pinnedRecord = ContentTabPinnedRecord(
            id: id.rawValue,
            page: preflight.tab.page,
            anchor: preflight.tab.anchor,
            title: preflight.tab.title,
            iconName: preflight.tab.iconName,
            pinnedAt: date(),
        )

        let selectedTabIDs = state.selectedTabIDs
        let selectionAnchorID = state.selectionAnchorID
        var pinnedTab = preflight.tab
        pinnedTab.isPinned = true
        state.tabs.remove(id: id)
        state.tabs.insert(pinnedTab, at: preflight.insertionIndex)
        state.selectedTabIDs = selectedTabIDs
        state.selectionAnchorID = selectionAnchorID
        state.pinnedRecords[id] = pinnedRecord
        state.pendingPinnedRecordIDs.insert(id)
        state.pinnedRecordPersistenceError = nil

        let intentID = state.markLatestPinnedRecordPersistenceIntent(for: id)
        let generation = contentTabPinnedRecordClient.reserveMutationGeneration(id)
        let request = ContentTabPinnedRecordPersistenceRequest(
            tabID: id,
            context: .init(intentID: intentID, generation: generation),
            rollback: .init(
                previousIsPinned: false,
                previousPinnedRecord: preflight.previousPinnedRecord,
                previousTabIndex: preflight.previousTabIndex,
            ),
            mutation: .upsert(
                record: pinnedRecord,
                dormantSlot: placement == nil ? dormantSlot : nil,
                placement: placement,
            ),
            persistenceScopeID: state.pinnedRecordPersistenceScopeID,
        )
        return persistPinnedRecord(request, state: state)
    }

    private func unpin(
        id: ContentTabID,
        placement: ContentTabPlacement?,
        state: inout ContentTabState,
    ) -> Effect<ContentTabAction> {
        guard let preflight = ContentTabPinMutationPreflight.unpin(
            id: id,
            placement: placement,
            state: state,
        ) else { return .none }

        let selectedTabIDs = state.selectedTabIDs
        let selectionAnchorID = state.selectionAnchorID

        var unpinnedTab = preflight.tab
        unpinnedTab.isPinned = false
        state.tabs.remove(id: id)
        state.tabs.insert(unpinnedTab, at: preflight.insertionIndex)
        state.selectedTabIDs = selectedTabIDs
        state.selectionAnchorID = selectionAnchorID
        state.pinnedRecords.removeValue(forKey: id)
        state.pendingPinnedRecordIDs.insert(id)
        state.pinnedRecordPersistenceError = nil

        let intentID = state.markLatestPinnedRecordPersistenceIntent(for: id)
        let generation = contentTabPinnedRecordClient.reserveMutationGeneration(id)
        let request = ContentTabPinnedRecordPersistenceRequest(
            tabID: id,
            context: .init(intentID: intentID, generation: generation),
            rollback: .init(
                previousIsPinned: true,
                previousPinnedRecord: preflight.previousPinnedRecord,
                previousTabIndex: preflight.previousTabIndex,
            ),
            mutation: .remove(recordID: id.rawValue),
            persistenceScopeID: state.pinnedRecordPersistenceScopeID,
        )
        return persistPinnedRecord(request, state: state)
    }

    private func updateRuntimePageAnchor(
        id: ContentTabID,
        newAnchor: ContentTabPageAnchor,
        state: inout ContentTabState,
    ) -> Effect<ContentTabAction> {
        state.previousActiveTabID = nil
        guard state.tabs[id: id] != nil else { return .none }
        state.tabs[id: id]?.anchor = newAnchor
        state.tabs[id: id]?.page = page(for: newAnchor)
        state.tabs[id: id]?.title = title(for: newAnchor)
        state.tabs[id: id]?.iconName = iconName(for: newAnchor)
        return .none
    }

    private func updateActivePageAnchor(
        id: ContentTabID,
        newAnchor: ContentTabPageAnchor,
        state: inout ContentTabState,
    ) -> Effect<ContentTabAction> {
        state.previousActiveTabID = nil
        guard let tab = state.tabs[id: id] else { return .none }
        state.tabs[id: id]?.anchor = newAnchor
        state.tabs[id: id]?.page = page(for: newAnchor)
        state.tabs[id: id]?.title = title(for: newAnchor)
        state.tabs[id: id]?.iconName = iconName(for: newAnchor)

        guard tab.isPinned else { return .none }

        let updatedRecord = ContentTabPinnedRecord(
            id: id.rawValue,
            page: page(for: newAnchor),
            anchor: newAnchor,
            title: title(for: newAnchor),
            iconName: iconName(for: newAnchor),
            pinnedAt: date(),
        )
        guard updatedRecord.isPageAnchorCompatible else {
            state.pinnedRecordPersistenceError = nil
            return .none
        }

        let previousPinnedRecord = state.pinnedRecords[id]
        state.pinnedRecords[id] = updatedRecord
        state.pendingPinnedRecordIDs.insert(id)
        state.pinnedRecordPersistenceError = nil

        let intentID = state.markLatestPinnedRecordPersistenceIntent(for: id)
        let generation = contentTabPinnedRecordClient.reserveMutationGeneration(id)
        let request = ContentTabPinnedRecordPersistenceRequest(
            tabID: id,
            context: .init(intentID: intentID, generation: generation),
            rollback: .init(
                previousIsPinned: true,
                previousPinnedRecord: previousPinnedRecord,
                previousTabIndex: nil,
            ),
            mutation: .upsert(record: updatedRecord, dormantSlot: nil),
            persistenceScopeID: state.pinnedRecordPersistenceScopeID,
        )
        return persistPinnedRecord(request, state: state)
    }

    private func persistPinnedRecord(
        _ request: ContentTabPinnedRecordPersistenceRequest,
        state: ContentTabState,
    ) -> Effect<ContentTabAction> {
        guard case let .local(discoveredLocationIDs) = pinnedRecordPersistenceRouting else {
            return .send(.delegate(.persistPinnedRecord(request)))
        }

        let client = contentTabPinnedRecordClient
        let defaults = userDefaultsClient
        let persistenceScopeID = state.pinnedRecordPersistenceScopeID
        return .run { send in
            await send(pinnedRecordPersistenceAction(
                request: request,
                discoveredLocationIDs: discoveredLocationIDs,
                client: client,
                defaults: defaults,
                persistenceScopeID: persistenceScopeID,
            ))
        }
        .cancellable(
            id: PinnedRecordPersistenceCancelID(
                scopeID: persistenceScopeID,
                tabID: request.tabID,
            ),
            cancelInFlight: true,
        )
    }
}

extension ContentTabFeature {
    private func title(for anchor: ContentTabPageAnchor) -> String {
        switch anchor {
        case .homeDefault:
            "Home"
        case let .directory(path):
            entryLoadingClient.displayName(path).nonEmpty ?? URL(fileURLWithPath: path).lastPathComponent
                .nonEmpty ?? path
        case let .collectionFile(url):
            CollectionFileUtils.displayName(url, fallback: url.lastPathComponent)
        case let .virtualCollection(id):
            id
        case .aiChat:
            "AI Chat"
        }
    }

    private func iconName(for anchor: ContentTabPageAnchor) -> String {
        switch anchor {
        case .homeDefault:
            "house"
        case let .directory(path):
            fileManagerIconClient.iconNameForURL(URL(fileURLWithPath: path), true, entryLoadingClient)
        case .collectionFile:
            "rectangle.stack"
        case let .virtualCollection(id):
            id == "Recents" ? "clock" : "folder"
        case .aiChat:
            "bubble.right"
        }
    }

    private func page(for anchor: ContentTabPageAnchor) -> ContentTabPage {
        switch anchor {
        case .homeDefault:
            .home
        case .directory:
            .directory
        case .collectionFile, .virtualCollection:
            .collection
        case .aiChat:
            .aiChat
        }
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
