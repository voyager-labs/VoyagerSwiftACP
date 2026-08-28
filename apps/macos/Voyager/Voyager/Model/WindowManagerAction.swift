import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi
import VoyagerEntitiesCollection
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryArrangements
import VoyagerFeaturesEntryOperations
import VoyagerPagesFileManager
import VoyagerShared
import VoyagerWidgetsEntryViewLayout

struct ExternalOpenPlacementCompletion: Equatable {
    let batchID: UUID
    let result: Result<ExternalOpenPlacementPlan, ExternalOpenPlacementFailure>
}

enum ExternalOpenPlacementApplicationFailure: Error, Equatable {
    case validationFailed
}

struct ExternalOpenPlacementApplicationCompletion: Equatable {
    let batchID: UUID
    let result: Result<ExternalOpenPlacementPlan, ExternalOpenPlacementApplicationFailure>
}

enum ExternalOpenActivationFailure: Error, Equatable {
    case recoveryExhausted
}

struct ExternalOpenPlacementRequest: Equatable {
    let batchID: UUID
    let items: [Item]
    let preferredWindowIDs: [WindowManagerState.WindowID]
    let staleReplanCount: Int
    let pinnedFallbackCount: Int
    let excludedTabIDs: Set<ContentTabID>

    var itemIDs: [UUID] {
        items.map(\.itemID)
    }

    struct Item: Equatable {
        let itemID: UUID
        let anchor: ContentTabPageAnchor
        let pendingSelectEntryID: String?
    }

    init(
        batchID: UUID,
        items: [Item],
        preferredWindowIDs: [WindowManagerState.WindowID],
        staleReplanCount: Int = 0,
        pinnedFallbackCount: Int = 0,
        excludedTabIDs: Set<ContentTabID> = [],
    ) {
        self.batchID = batchID
        self.items = items
        self.preferredWindowIDs = preferredWindowIDs
        self.staleReplanCount = staleReplanCount
        self.pinnedFallbackCount = pinnedFallbackCount
        self.excludedTabIDs = excludedTabIDs
    }

    var retryRequest: Self? {
        guard staleReplanCount == 0 else { return nil }
        return .init(
            batchID: batchID,
            items: items,
            preferredWindowIDs: preferredWindowIDs,
            staleReplanCount: 1,
            pinnedFallbackCount: pinnedFallbackCount,
            excludedTabIDs: excludedTabIDs,
        )
    }

    func fallbackExcludingPinnedCandidates(_ tabIDs: Set<ContentTabID>) -> Self? {
        guard pinnedFallbackCount == 0 else { return nil }
        return .init(
            batchID: batchID,
            items: items,
            preferredWindowIDs: preferredWindowIDs,
            staleReplanCount: staleReplanCount,
            pinnedFallbackCount: 1,
            excludedTabIDs: excludedTabIDs.union(tabIDs),
        )
    }
}

struct ExternalOpenPlacementPlan: Equatable {
    let batchID: UUID
    let windows: [Window]
    let request: ExternalOpenPlacementRequest?

    init(
        batchID: UUID,
        windows: [Window],
        request: ExternalOpenPlacementRequest? = nil,
    ) {
        self.batchID = batchID
        self.windows = windows
        self.request = request
    }

    var orderedItems: [Item] {
        guard let request else { return windows.flatMap(\.items) }
        let itemsByID = Dictionary(uniqueKeysWithValues: windows.flatMap(\.items).map { ($0.itemID, $0) })
        return request.itemIDs.compactMap { itemsByID[$0] }
    }

    var reservationsByItemID: [UUID: ExternalContentTabReservation] {
        let lastItemsByTabID = orderedItems.reduce(into: [ContentTabID: Item]()) { result, item in
            result[item.tabID] = item
        }
        return orderedItems.reduce(into: [:]) { result, item in
            guard item.requiresReservation else { return }
            result[item.itemID] = .init(
                id: item.tabID,
                anchor: item.anchor,
                pendingSelectEntryID: lastItemsByTabID[item.tabID]?.pendingSelectEntryID,
            )
        }
    }

    struct Window: Equatable {
        let windowID: WindowManagerState.WindowID
        let isNewWindow: Bool
        let items: [Item]
    }

    struct Item: Equatable {
        let itemID: UUID
        let tabID: ContentTabID
        let anchor: ContentTabPageAnchor
        let pendingSelectEntryID: String?
        let requiresReservation: Bool
        let requiresPinnedAnchorReturn: Bool

        init(
            itemID: UUID,
            tabID: ContentTabID,
            anchor: ContentTabPageAnchor = .homeDefault,
            pendingSelectEntryID: String? = nil,
            requiresReservation: Bool = true,
            requiresPinnedAnchorReturn: Bool = false,
        ) {
            self.itemID = itemID
            self.tabID = tabID
            self.anchor = anchor
            self.pendingSelectEntryID = pendingSelectEntryID
            self.requiresReservation = requiresReservation
            self.requiresPinnedAnchorReturn = requiresPinnedAnchorReturn
        }
    }
}

struct ExternalOpenActivationAttempt: Equatable {
    let batchID: UUID
    let plan: ExternalOpenPlacementPlan
    let windowID: WindowManagerState.WindowID
    let excludedWindowIDs: Set<WindowManagerState.WindowID>
    /// pinned collection 복귀 성공 delegate를 수신한 tab set (commit 완료 확인)
    var settledPinnedReturnTabIDs: Set<ContentTabID> = []
}

enum ExternalOpenPlacementFailure: Error, Equatable {
    case duplicateItemID(UUID)
    case invalidExistingTabCount(windowID: WindowManagerState.WindowID, count: Int)
    case duplicateAllocatedID(UUID)
}

enum ExternalOpenPlacementPlanner {
    private typealias RouteAssignment = (anchor: ContentTabPageAnchor, match: RouteMatch?)

    private struct ExistingTarget {
        let windowID: WindowManagerState.WindowID
        let itemCount: Int
    }

    private struct RoutePlacement {
        let anchor: ContentTabPageAnchor
        let tabID: ContentTabID
    }

    private struct RouteMatch {
        let windowID: WindowManagerState.WindowID
        let tabID: ContentTabID
        let requiresPinnedAnchorReturn: Bool
    }

    static func make(
        _ request: ExternalOpenPlacementRequest,
        state: WindowManagerState,
        generateUUID: @autoclosure () -> UUID,
    ) -> Result<ExternalOpenPlacementPlan, ExternalOpenPlacementFailure> {
        if let duplicateItemID = firstDuplicate(in: request.itemIDs) {
            return .failure(.duplicateItemID(duplicateItemID))
        }
        guard !request.itemIDs.isEmpty else { return emptyPlan(request) }

        let routeAssignments = routeAssignments(
            for: request.items,
            state: state,
            excludedTabIDs: request.excludedTabIDs,
        )
        let uniqueNewItems = firstItemsWithoutRouteMatch(request.items, routeAssignments: routeAssignments)
        let targetResult = existingTarget(
            for: request,
            newItemCount: uniqueNewItems.count,
            state: state,
        )
        guard case let .success(target) = targetResult else {
            return failureEmptyPlan(targetResult, batchID: request.batchID, request: request)
        }

        var allocatedRawIDs = existingRawIDs(in: state)
        let placementsResult = allocateRoutePlacements(
            uniqueNewItems,
            generateUUID: generateUUID,
            allocatedRawIDs: &allocatedRawIDs,
        )
        guard case let .success(newPlacements) = placementsResult else {
            return failureEmptyPlan(placementsResult, batchID: request.batchID, request: request)
        }

        let existingItemCount = target?.itemCount ?? 0
        let overflowItemCount = newPlacements.count - existingItemCount
        let newWindowCount = (overflowItemCount + ContentTabConstants.maxTabs - 1) / ContentTabConstants.maxTabs
        let windowIDsResult = allocateWindowIDs(
            count: newWindowCount,
            generateUUID: generateUUID,
            allocatedRawIDs: &allocatedRawIDs,
        )
        guard case let .success(newWindowIDs) = windowIDsResult else {
            return windowIDsResult.map { _ in .init(batchID: request.batchID, windows: [], request: request) }
        }

        return .success(.init(
            batchID: request.batchID,
            windows: makeWindows(
                request: request,
                target: target,
                newPlacements: newPlacements,
                newWindowIDs: newWindowIDs,
                routeAssignments: routeAssignments,
            ),
            request: request,
        ))
    }

    private static func emptyPlan(
        _ request: ExternalOpenPlacementRequest,
    ) -> Result<ExternalOpenPlacementPlan, ExternalOpenPlacementFailure> {
        .success(.init(batchID: request.batchID, windows: [], request: request))
    }

    private static func failureEmptyPlan(
        _ result: Result<some Any, ExternalOpenPlacementFailure>,
        batchID: UUID,
        request: ExternalOpenPlacementRequest,
    ) -> Result<ExternalOpenPlacementPlan, ExternalOpenPlacementFailure> {
        result.map { _ in .init(batchID: batchID, windows: [], request: request) }
    }

    private static func firstDuplicate(in itemIDs: [UUID]) -> UUID? {
        var seen = Set<UUID>()
        return itemIDs.first { !seen.insert($0).inserted }
    }

    private static func existingTarget(
        for request: ExternalOpenPlacementRequest,
        newItemCount: Int,
        state: WindowManagerState,
    ) -> Result<ExistingTarget?, ExternalOpenPlacementFailure> {
        guard newItemCount > 0 else { return .success(nil) }
        let candidateWindowIDs: [WindowManagerState.WindowID]
        if request.preferredWindowIDs.isEmpty {
            var fallbackWindowIDs = state.lastUsedWindowIDs
            if let focusedWindowID = state.focusedWindowID {
                fallbackWindowIDs.insert(focusedWindowID, at: 0)
            }
            candidateWindowIDs = fallbackWindowIDs + state.windows.ids
        } else {
            let liveMRU = Set(state.lastUsedWindowIDs)
            candidateWindowIDs = request.preferredWindowIDs.filter(liveMRU.contains)
        }
        guard let windowID = candidateWindowIDs.first(where: {
            state.windows[id: $0]?.window.isExternalOpenRouteEligible == true
                && !state.closingWindowIDs.contains($0)
                && !state.pendingWindowOpenIDs.contains($0)
        }),
            let window = state.windows[id: windowID]
        else {
            return .success(nil)
        }

        let tabCount = window.window.contentTabs.tabs.count
        guard tabCount <= ContentTabConstants.maxTabs else {
            return .failure(.invalidExistingTabCount(windowID: windowID, count: tabCount))
        }
        return .success(.init(
            windowID: windowID,
            itemCount: min(newItemCount, ContentTabConstants.maxTabs - tabCount),
        ))
    }

    private static func firstItemsWithoutRouteMatch(
        _ items: [ExternalOpenPlacementRequest.Item],
        routeAssignments: [RouteAssignment],
    ) -> [ExternalOpenPlacementRequest.Item] {
        var anchors: [ContentTabPageAnchor] = []
        return items.filter { item in
            guard routeAssignments.first(where: { $0.anchor == item.anchor })?.match == nil,
                  !anchors.contains(item.anchor)
            else { return false }
            anchors.append(item.anchor)
            return true
        }
    }

    private static func runtimeMatch(
        for anchor: ContentTabPageAnchor,
        state: WindowManagerState,
        excludingTabIDs: Set<ContentTabID>,
    ) -> (WindowManagerState.WindowID, ContentTabID)? {
        let liveWindowIDs = orderedLiveWindowIDs(state: state)
        for activeOnly in [true, false] {
            for windowID in liveWindowIDs {
                guard let window = state.windows[id: windowID]?.window,
                      window.isExternalOpenRouteEligible
                else { continue }
                let contentTabs = window.contentTabs
                for tab in contentTabs.tabs where tab.anchor == anchor {
                    guard !excludingTabIDs.contains(tab.id) else { continue }
                    if !activeOnly || tab.id == contentTabs.activeTabID {
                        return (windowID, tab.id)
                    }
                }
            }
        }
        return nil
    }

    private static func routeMatch(
        for anchor: ContentTabPageAnchor,
        state: WindowManagerState,
        excludingTabIDs: Set<ContentTabID>,
    ) -> RouteMatch? {
        if let runtimeMatch = runtimeMatch(for: anchor, state: state, excludingTabIDs: excludingTabIDs) {
            return .init(
                windowID: runtimeMatch.0,
                tabID: runtimeMatch.1,
                requiresPinnedAnchorReturn: false,
            )
        }
        let liveWindowIDs = orderedLiveWindowIDs(state: state)
        for activeOnly in [true, false] {
            for windowID in liveWindowIDs {
                guard let window = state.windows[id: windowID]?.window,
                      window.isExternalOpenRouteEligible
                else { continue }
                let contentTabs = window.contentTabs
                for tab in contentTabs.tabs where tab.isPinned {
                    guard !excludingTabIDs.contains(tab.id),
                          !activeOnly || tab.id == contentTabs.activeTabID,
                          window.canReturnContentTabToPinnedLocation(tab.id, matching: anchor)
                    else { continue }
                    return .init(
                        windowID: windowID,
                        tabID: tab.id,
                        requiresPinnedAnchorReturn: true,
                    )
                }
            }
        }
        return nil
    }

    private static func routeAssignments(
        for items: [ExternalOpenPlacementRequest.Item],
        state: WindowManagerState,
        excludedTabIDs: Set<ContentTabID>,
    ) -> [RouteAssignment] {
        var assignments: [RouteAssignment] = []
        var assignedTabIDs = excludedTabIDs
        for item in items where !assignments.contains(where: { $0.anchor == item.anchor }) {
            let match = routeMatch(for: item.anchor, state: state, excludingTabIDs: assignedTabIDs)
            if let match { assignedTabIDs.insert(match.tabID) }
            assignments.append((anchor: item.anchor, match: match))
        }
        return assignments
    }

    private static func orderedLiveWindowIDs(state: WindowManagerState) -> [WindowManagerState.WindowID] {
        var result: [WindowManagerState.WindowID] = []
        let candidates = [state.focusedWindowID].compactMap(\.self) + state.lastUsedWindowIDs + state.windows.ids
        for windowID in candidates where !result.contains(windowID) {
            guard state.windows[id: windowID] != nil,
                  !state.closingWindowIDs.contains(windowID),
                  !state.pendingWindowOpenIDs.contains(windowID),
                  state.windows[id: windowID]?.window.isExternalOpenRouteEligible == true
            else { continue }
            result.append(windowID)
        }
        return result
    }

    private static func existingRawIDs(in state: WindowManagerState) -> Set<String> {
        var rawIDs = Set(state.windows.ids.map(\.uuidString))
        for window in state.windows {
            rawIDs.formUnion(window.window.contentTabs.tabs.map(\.id.rawValue))
        }
        return rawIDs
    }

    private static func allocateRoutePlacements(
        _ items: [ExternalOpenPlacementRequest.Item],
        generateUUID: () -> UUID,
        allocatedRawIDs: inout Set<String>,
    ) -> Result<[RoutePlacement], ExternalOpenPlacementFailure> {
        var placements: [RoutePlacement] = []
        placements.reserveCapacity(items.count)
        for item in items {
            let generatedID = generateUUID()
            guard allocatedRawIDs.insert(generatedID.uuidString).inserted else {
                return .failure(.duplicateAllocatedID(generatedID))
            }
            placements.append(.init(
                anchor: item.anchor,
                tabID: ContentTabID(rawValue: generatedID.uuidString),
            ))
        }
        return .success(placements)
    }

    private static func allocateWindowIDs(
        count: Int,
        generateUUID: () -> UUID,
        allocatedRawIDs: inout Set<String>,
    ) -> Result<[UUID], ExternalOpenPlacementFailure> {
        var windowIDs: [UUID] = []
        windowIDs.reserveCapacity(count)
        for _ in 0 ..< count {
            let generatedID = generateUUID()
            guard allocatedRawIDs.insert(generatedID.uuidString).inserted else {
                return .failure(.duplicateAllocatedID(generatedID))
            }
            windowIDs.append(generatedID)
        }
        return .success(windowIDs)
    }

    private static func makeWindows(
        request: ExternalOpenPlacementRequest,
        target: ExistingTarget?,
        newPlacements: [RoutePlacement],
        newWindowIDs: [UUID],
        routeAssignments: [RouteAssignment],
    ) -> [ExternalOpenPlacementPlan.Window] {
        var windows: [ExternalOpenPlacementPlan.Window] = []
        for requestItem in request.items {
            let matchedPlacement = routeAssignments.first(where: { $0.anchor == requestItem.anchor })?.match
            let newPlacementIndex = newPlacements.firstIndex(where: { $0.anchor == requestItem.anchor })
            guard matchedPlacement != nil || newPlacementIndex != nil else { continue }
            let windowID: UUID
            let tabID: ContentTabID
            let requiresReservation: Bool
            let requiresPinnedAnchorReturn: Bool
            if let matchedPlacement {
                windowID = matchedPlacement.windowID
                tabID = matchedPlacement.tabID
                requiresReservation = false
                requiresPinnedAnchorReturn = matchedPlacement.requiresPinnedAnchorReturn
            } else if let newPlacementIndex {
                tabID = newPlacements[newPlacementIndex].tabID
                if newPlacementIndex < (target?.itemCount ?? 0), let target {
                    windowID = target.windowID
                } else {
                    let overflowIndex = newPlacementIndex - (target?.itemCount ?? 0)
                    windowID = newWindowIDs[overflowIndex / ContentTabConstants.maxTabs]
                }
                requiresReservation = !windows.flatMap(\.items).contains(where: { $0.tabID == tabID })
                requiresPinnedAnchorReturn = false
            } else {
                continue
            }
            let item = ExternalOpenPlacementPlan.Item(
                itemID: requestItem.itemID,
                tabID: tabID,
                anchor: requestItem.anchor,
                pendingSelectEntryID: requestItem.pendingSelectEntryID,
                requiresReservation: requiresReservation,
                requiresPinnedAnchorReturn: requiresPinnedAnchorReturn,
            )
            if let index = windows.firstIndex(where: { $0.windowID == windowID }) {
                windows[index] = .init(
                    windowID: windows[index].windowID,
                    isNewWindow: windows[index].isNewWindow,
                    items: windows[index].items + [item],
                )
            } else {
                windows.append(.init(
                    windowID: windowID,
                    isNewWindow: newWindowIDs.contains(windowID),
                    items: [item],
                ))
            }
        }
        return windows
    }
}

enum ExternalOpenPlacementApplication {
    struct PinnedAnchorReturn: Equatable {
        let tabID: ContentTabID
        let pendingSelectEntryID: String?
    }

    struct ExistingWindowActivation {
        let windowID: WindowManagerState.WindowID
        let tabIDs: [ContentTabID]
        let activeTabID: ContentTabID
        let pinnedAnchorReturns: [PinnedAnchorReturn]
        let selectionChangedTabIDs: [ContentTabID]
        let directoryReloadTabIDs: [ContentTabID]
    }

    struct Result {
        let windows: IdentifiedArrayOf<WindowSessionFeature.State>
        let newWindowIDs: [WindowManagerState.WindowID]
        let existingWindowActivations: [ExistingWindowActivation]
    }

    static func apply(
        _ plan: ExternalOpenPlacementPlan,
        reservationsByItemID: [UUID: ExternalContentTabReservation],
        to state: WindowManagerState,
    ) -> Result? {
        guard reservationsAreValid(for: plan, reservationsByItemID: reservationsByItemID) else { return nil }

        var updatedWindows = state.windows
        var newWindowIDs: [WindowManagerState.WindowID] = []
        var existingWindowActivations: [ExistingWindowActivation] = []
        for placementWindow in plan.windows {
            guard !state.closingWindowIDs.contains(placementWindow.windowID),
                  !state.pendingWindowOpenIDs.contains(placementWindow.windowID)
            else { return nil }
            let reservations = placementWindow.items.compactMap { item in
                item.requiresReservation ? reservationsByItemID[item.itemID] : nil
            }

            if placementWindow.isNewWindow {
                guard appendNewWindow(
                    placementWindow,
                    reservations: reservations,
                    to: &updatedWindows,
                ) else { return nil }
                newWindowIDs.append(placementWindow.windowID)
            } else {
                guard let activation = updateExistingWindow(
                    placementWindow,
                    reservations: reservations,
                    in: &updatedWindows,
                ) else { return nil }
                existingWindowActivations.append(activation)
            }
        }
        return Result(
            windows: updatedWindows,
            newWindowIDs: newWindowIDs,
            existingWindowActivations: existingWindowActivations,
        )
    }

    static func lastSurvivingWindowID(
        for plan: ExternalOpenPlacementPlan,
        state: WindowManagerState,
        excluding excludedWindowIDs: Set<WindowManagerState.WindowID> = [],
    ) -> WindowManagerState.WindowID? {
        var lastMatch: WindowManagerState.WindowID?
        for item in plan.orderedItems {
            guard let placementWindow = plan.windows.first(where: { window in
                window.items.contains(where: { $0.itemID == item.itemID })
            }) else { continue }
            let isExcluded = excludedWindowIDs.contains(placementWindow.windowID)
            guard !state.closingWindowIDs.contains(placementWindow.windowID),
                  !state.pendingWindowOpenIDs.contains(placementWindow.windowID),
                  let window = state.windows[id: placementWindow.windowID]?.window
            else {
                guard plan.request == nil else { return nil }
                continue
            }
            if placementWindow.isNewWindow,
               state.externalWindowBatchIDs[placementWindow.windowID] != plan.batchID
            {
                continue
            }
            guard window.isExternalOpenActivationEligible(for: placementWindow.items) else { return nil }
            guard window.contentTabs.tabs[id: item.tabID] != nil else {
                guard plan.request == nil else { return nil }
                continue
            }
            guard window.stillMatchesExternalOpenItem(item) else { return nil }
            guard !isExcluded else { continue }
            lastMatch = placementWindow.windowID
        }
        return lastMatch
    }

    private static func reservationsAreValid(
        for plan: ExternalOpenPlacementPlan,
        reservationsByItemID: [UUID: ExternalContentTabReservation],
    ) -> Bool {
        let reservationItems = plan.windows.flatMap(\.items).filter(\.requiresReservation)
        guard reservationItems.count == reservationsByItemID.count,
              Set(reservationItems.map(\.itemID)) == Set(reservationsByItemID.keys)
        else { return false }
        return reservationItems.allSatisfy { item in
            reservationsByItemID[item.itemID] == .init(
                id: item.tabID,
                anchor: item.anchor,
                pendingSelectEntryID: plan.orderedItems.last(where: { $0.tabID == item.tabID })?.pendingSelectEntryID,
            )
        }
    }

    private static func appendNewWindow(
        _ placement: ExternalOpenPlacementPlan.Window,
        reservations: [ExternalContentTabReservation],
        to windows: inout IdentifiedArrayOf<WindowSessionFeature.State>,
    ) -> Bool {
        guard windows[id: placement.windowID] == nil,
              let window = FileManagerWindowFeature.State.makeExternalInitial(
                  reservations: reservations,
                  windowID: placement.windowID,
                  activeTabID: placement.items.last?.tabID,
              )
        else { return false }
        windows.append(.init(id: placement.windowID, window: window))
        return true
    }

    private static func updateExistingWindow(
        _ placement: ExternalOpenPlacementPlan.Window,
        reservations: [ExternalContentTabReservation],
        in windows: inout IdentifiedArrayOf<WindowSessionFeature.State>,
    ) -> ExistingWindowActivation? {
        guard var window = windows[id: placement.windowID]?.window,
              window.isExternalOpenRouteEligible,
              placement.items.filter({ !$0.requiresReservation }).allSatisfy(window.stillMatchesExternalOpenItem),
              reservations.isEmpty || window.reserveExternalContentTabs(reservations)
        else { return nil }
        for item in placement.items where !item.requiresPinnedAnchorReturn {
            guard window.applyExternalPendingSelection(
                item.pendingSelectEntryID,
                tabID: item.tabID,
                anchor: item.anchor,
            ) else { return nil }
        }
        windows[id: placement.windowID]?.window = window
        guard let activeItem = placement.items.last else { return nil }
        var pinnedAnchorReturns: [PinnedAnchorReturn] = []
        for item in placement.items where item.requiresPinnedAnchorReturn {
            let pinnedReturn = PinnedAnchorReturn(
                tabID: item.tabID,
                pendingSelectEntryID: placement.items.last(where: { $0.tabID == item.tabID })?.pendingSelectEntryID,
            )
            if let index = pinnedAnchorReturns.firstIndex(where: { $0.tabID == item.tabID }) {
                pinnedAnchorReturns[index] = pinnedReturn
            } else {
                pinnedAnchorReturns.append(pinnedReturn)
            }
        }
        return .init(
            windowID: placement.windowID,
            tabIDs: reservations.map(\.id),
            activeTabID: activeItem.tabID,
            pinnedAnchorReturns: pinnedAnchorReturns,
            selectionChangedTabIDs: selectionChangedTabIDs(for: placement.items, in: window),
            directoryReloadTabIDs: directoryReloadTabIDs(for: placement.items, in: window),
        )
    }

    private static func directoryReloadTabIDs(
        for items: [ExternalOpenPlacementPlan.Item],
        in window: FileManagerWindowState,
    ) -> [ContentTabID] {
        var tabIDs: [ContentTabID] = []
        for item in items {
            guard !item.requiresReservation,
                  !item.requiresPinnedAnchorReturn,
                  item.pendingSelectEntryID != nil,
                  case .directory = item.anchor
            else { continue }
            let content = item.tabID == window.contentTabs.activeTabID
                ? window.content
                : window.tabContentStates[item.tabID]
            guard content?.pendingSelectEntryID != nil,
                  !tabIDs.contains(item.tabID)
            else { continue }
            tabIDs.append(item.tabID)
        }
        return tabIDs
    }

    private static func selectionChangedTabIDs(
        for items: [ExternalOpenPlacementPlan.Item],
        in window: FileManagerWindowState,
    ) -> [ContentTabID] {
        var tabIDs: [ContentTabID] = []
        for item in items where item.pendingSelectEntryID != nil {
            let content = item.tabID == window.contentTabs.activeTabID
                ? window.content
                : window.tabContentStates[item.tabID]
            guard content?.pendingSelectEntryID == nil,
                  !(content?.entryViewLayout.selectedIds.isEmpty ?? true),
                  !tabIDs.contains(item.tabID)
            else { continue }
            tabIDs.append(item.tabID)
        }
        return tabIDs
    }
}

private extension FileManagerWindowState {
    var isExternalOpenLifecycleEligible: Bool {
        !isClosing
            && pendingSelectedContentTabClose == nil
            && pendingSelectedContentTabPinMutation == nil
            && pendingContentTabClose == nil
            && pendingContentTabTeardown == nil
            && pendingTopNavigationIntents.isEmpty
            && contentTabs.pendingPinnedRecordIDs.isEmpty
            && contentTabMoveParticipantRequestID == nil
    }

    var isExternalOpenRouteEligible: Bool {
        isExternalOpenLifecycleEligible && pendingCollectionOpenRequest == nil
    }

    func isExternalOpenActivationEligible(for items: [ExternalOpenPlacementPlan.Item]) -> Bool {
        guard isExternalOpenLifecycleEligible,
              let pendingCollectionOpenRequest
        else { return isExternalOpenLifecycleEligible }
        return items.contains { item in
            guard item.requiresPinnedAnchorReturn,
                  case let .collectionFile(expectedURL) = item.anchor
            else { return false }
            return pendingCollectionOpenRequest.url.standardizedFileURL == expectedURL.standardizedFileURL
        }
    }

    func stillMatchesExternalOpenItem(_ item: ExternalOpenPlacementPlan.Item) -> Bool {
        guard let tab = contentTabs.tabs[id: item.tabID] else { return false }
        if item.requiresPinnedAnchorReturn {
            return canReturnContentTabToPinnedLocation(item.tabID, matching: item.anchor)
        }
        // ponytail: legacy fixtures use .homeDefault + requiresReservation; production reserved tabs have real anchors
        if item.requiresReservation, item.anchor == .homeDefault {
            return true
        }
        return tab.anchor == item.anchor
    }
}

struct DefaultWindowBootstrapResult: Equatable {
    let contentTabs: ContentTabState
    let fixedLocationItems: [FileManagerFixedLocationItem]
    let topNavigationOrder: FileManagerTopNavigationOrder
    let arrangementAvailability: FileManagerTopNavigationArrangementAvailability
}

@CasePathable
enum WindowManagerAction: CasePathable {
    case delegate(Delegate)
    case lifecycle(Lifecycle)
    case file(FileCommand)
    case window(WindowCommand)
    case view(ViewCommand)
    case edit(EditCommand)
    case event(WindowEvent)
    case placement(PlacementCommand)
    case trackedSingleton(TrackedSingletonCommand)
    case trackedSingletonNativeOpenCompleted(requestID: UUID)
    case pinnedContentTabsStoreChanged
    case topNavigationMovePersistenceCompleted(
        sourceWindowID: WindowManagerState.WindowID,
        token: FileManagerTopNavigationOperationToken,
        terminal: FileManagerTopNavigationIntentTerminal,
    )
    case topNavigationPersistenceRequested(WindowManagerTopNavigationPersistenceRequest)
    case topNavigationPersistenceCompleted(WindowManagerTopNavigationPersistenceResult)
    case defaultWindowBootstrapCompleted(requestID: UUID, result: DefaultWindowBootstrapResult)
    case defaultWindowBootstrapFailed(requestID: UUID)
    case defaultWindowBootstrapRequested(id: WindowManagerState.WindowID)
    case windowReadyToOpen(id: WindowManagerState.WindowID)
    case windowOpenCompleted(
        id: WindowManagerState.WindowID,
        shouldBootstrapDefaultWindow: Bool,
        isRegistered: Bool,
    )
    case pendingWindowCloseFinalized(id: WindowManagerState.WindowID)
    case windowInvalidationFinished(id: WindowManagerState.WindowID, result: UndoManagerInvalidationResult)
    case finalizeDeferredWindowClosures
    case externalOpenActivationResult(
        attempt: ExternalOpenActivationAttempt,
        result: FileManagerWindowActivationResult,
    )
    case contentTabMoveRequest(ContentTabMoveRequest)
    case contentTabMoveLifecycleCompleted(request: ContentTabMoveRequest)
    case contentTabMoveWindowActionRequested(
        request: ContentTabMoveRequest,
        windowID: WindowManagerState.WindowID,
        action: FileManagerWindowAction,
    )
    case contentTabMoveNativeEffectsRequested(request: ContentTabMoveRequest)
    case contentTabMoveActivationResult(
        attempt: ContentTabMoveActivationAttempt,
        result: FileManagerWindowActivationResult,
    )
    case refreshContentTabMoveTargets
    case windows(IdentifiedActionOf<WindowSessionFeature>)

    @CasePathable
    enum Delegate {
        case openAISettings
        case externalOpenPlacementCompleted(ExternalOpenPlacementCompletion)
        case externalOpenApplyCompleted(ExternalOpenPlacementApplicationCompletion)
        case externalOpenActivationCompleted(batchID: UUID)
        case externalOpenActivationFailed(batchID: UUID, failure: ExternalOpenActivationFailure)
        case trackedSingletonCompleted(requestID: UUID)
    }

    @CasePathable
    enum TrackedSingletonCommand: CasePathable {
        case openInitialWindow(requestID: UUID)
        case openWindow(requestID: UUID, path: String, selectEntryID: String?)
        case revoke(requestID: UUID)
    }

    @CasePathable
    enum Lifecycle: CasePathable {
        case openInitialWindowIfNeeded
        case reopenWindowIfNeeded(hasVisibleWindows: Bool)
        case applyAppPreferences(AppPreferencesState)
        case aiConnectionsFileUpdated(AIConnectionsFile)
    }

    @CasePathable
    enum FileCommand: CasePathable {
        case newWindow(path: String? = nil, selectEntryID: String? = nil)
        case openCollectionFile(URL)
        case newTab
        case closeTab
        case togglePinTab
        case restoreLastClosedTab
        case duplicateTab
        case selectContentTab(position: Int)
        case presentContentTabSwitcher
        case selectMostRecentlyUsedContentTab
        case newFolder
        case open
        case quickLook
        case saveCollection
        case saveCollectionAs
    }

    @CasePathable
    enum WindowCommand: CasePathable {
        case closeFocusedWindow
        case closeAllWindows
        case goBack
        case goForward
        case goToEnclosingDirectory
        case toggleSidebar
        case toggleShowHiddenFiles
    }

    @CasePathable
    enum ViewCommand: CasePathable {
        case setViewLayout(EntryViewLayoutState.Mode)
        case setGroupKey(GroupKey)
        case setSortKey(SortKey)
        case setSortOrder(VoyagerShared.SortOrder)
    }

    @CasePathable
    enum EditCommand: CasePathable {
        case requestUndo
        case requestRedo
        case find
        case toggleComposer
        case openChat
        case showChatHistory
        case cut
        case copy
        case paste
        case duplicate
        case makeAlias
        case selectAll
        case copyAbsolutePaths
        case copyURLs
    }

    @CasePathable
    enum PlacementCommand: CasePathable {
        case plan(ExternalOpenPlacementRequest)
        case apply(
            plan: ExternalOpenPlacementPlan,
            reservationsByItemID: [UUID: ExternalContentTabReservation],
        )
        case activate(ExternalOpenPlacementPlan)
        case cancel(batchID: UUID)
    }

    @CasePathable
    enum WindowEvent: CasePathable {
        case focusWindow(path: String)
        case windowBecameKey(WindowManagerState.WindowID)
        case windowResignedKey(WindowManagerState.WindowID)
        case windowClosed(WindowManagerState.WindowID)
    }
}
