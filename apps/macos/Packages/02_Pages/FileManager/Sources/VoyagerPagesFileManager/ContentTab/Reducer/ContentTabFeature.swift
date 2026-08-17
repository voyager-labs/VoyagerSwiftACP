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
        state.recordActivation(item.id)
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
        state.recordActivation(id)
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
            return closeLastTab(
                tab: tab,
                id: id,
                preservesLastTabIdentity: preservesLastTabIdentity,
                state: &state,
            )
        }

        let snapshot = ClosedContentTabSnapshot(
            page: tab.page,
            anchor: tab.anchor,
            wasPinned: tab.isPinned,
            closedAt: Date(),
            title: tab.title,
            iconName: tab.iconName,
        )
        state.recentlyClosed = snapshot

        let wasActive = state.activeTabID == id
        let fallbackTabID = fallbackTabID(forClosing: id, state: state)

        state.tabs.remove(id: id)
        state.reconcileSelection()

        if wasActive {
            state.previousActiveTabID = id
            if let fallbackTabID {
                state.recordActivation(fallbackTabID)
            }
            state.activeTabID = fallbackTabID
        } else {
            state.previousActiveTabID = nil
        }

        return .none
    }

    private func closeLastTab(
        tab: ContentTabItem,
        id: ContentTabID,
        preservesLastTabIdentity: Bool,
        state: inout ContentTabState,
    ) -> Effect<ContentTabAction> {
        if case .aiChat = tab.anchor {
            state.recentlyClosed = ClosedContentTabSnapshot(
                page: tab.page,
                anchor: tab.anchor,
                wasPinned: tab.isPinned,
                closedAt: Date(),
                title: tab.title,
                iconName: tab.iconName,
            )
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
        state.pruneRecentlyUsedTabIDs()
        state.recordActivation(homeTab.id)
        state.activeTabID = homeTab.id
        state.selectedTabIDs = [homeTab.id]
        state.selectionAnchorID = homeTab.id
        return .none
    }

    private func replaceLastTabWithHome(
        tab: ContentTabItem,
        id: ContentTabID,
        state: inout ContentTabState,
    ) -> Effect<ContentTabAction> {
        if case .aiChat = tab.anchor {
            state.recentlyClosed = ClosedContentTabSnapshot(
                page: tab.page,
                anchor: tab.anchor,
                wasPinned: tab.isPinned,
                closedAt: Date(),
                title: tab.title,
                iconName: tab.iconName,
            )
        }

        let homeTab = ContentTabItem(
            id: ContentTabID(),
            page: .home,
            anchor: .homeDefault,
            isPinned: false,
            title: "Home",
            iconName: "house",
        )
        state.previousActiveTabID = id
        state.tabs.remove(id: id)
        state.tabs.append(homeTab)
        state.activeTabID = homeTab.id
        return .none
    }

    private func fallbackTabID(
        forClosing id: ContentTabID,
        state: ContentTabState,
    ) -> ContentTabID? {
        guard let closingIndex = state.tabs.firstIndex(where: { $0.id == id }) else { return nil }
        if let previousID = state.previousActiveTabID,
           previousID != id,
           state.tabs[id: previousID] != nil
        {
            return previousID
        }
        if closingIndex + 1 < state.tabs.endIndex {
            return state.tabs[closingIndex + 1].id
        }
        if closingIndex > state.tabs.startIndex {
            return state.tabs[state.tabs.index(before: closingIndex)].id
        }
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
        state.recordActivation(item.id)
        state.activeTabID = item.id
        state.recentlyClosed = nil
        return .none
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

enum ContentTabPinMutationPreflight {
    struct PinContext {
        let tab: ContentTabItem
        let previousTabIndex: Int
        let insertionIndex: Int
        let previousPinnedRecord: ContentTabPinnedRecord?
    }

    struct UnpinContext {
        let tab: ContentTabItem
        let previousTabIndex: Int
        let insertionIndex: Int
        let previousPinnedRecord: ContentTabPinnedRecord?
    }

    enum PinResult {
        case valid(PinContext)
        case incompatiblePageAnchor
        case invalid
    }

    static func pin(
        id: ContentTabID,
        placement: ContentTabPlacement?,
        state: ContentTabState,
    ) -> PinResult {
        guard let tab = state.tabs[id: id], !tab.isPinned,
              let previousTabIndex = state.tabs.index(id: id),
              let insertionIndex = pinInsertionIndex(for: placement, sourceID: id, state: state)
        else { return .invalid }
        guard ContentTabPinnedRecord.isPageAnchorCompatible(page: tab.page, anchor: tab.anchor) else {
            return .incompatiblePageAnchor
        }
        return .valid(.init(
            tab: tab,
            previousTabIndex: previousTabIndex,
            insertionIndex: insertionIndex,
            previousPinnedRecord: state.pinnedRecords[id],
        ))
    }

    static func unpin(
        id: ContentTabID,
        placement: ContentTabPlacement?,
        state: ContentTabState,
    ) -> UnpinContext? {
        guard let tab = state.tabs[id: id], tab.isPinned,
              let previousTabIndex = state.tabs.index(id: id),
              let insertionIndex = unpinInsertionIndex(for: placement, sourceID: id, state: state)
        else { return nil }
        return .init(
            tab: tab,
            previousTabIndex: previousTabIndex,
            insertionIndex: insertionIndex,
            previousPinnedRecord: state.pinnedRecords[id],
        )
    }
}
