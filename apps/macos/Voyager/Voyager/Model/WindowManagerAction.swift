import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi
import VoyagerEntitiesCollection
import VoyagerFeaturesEntryArrangements
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

struct ExternalOpenPlacementRequest: Equatable {
    let batchID: UUID
    let itemIDs: [UUID]
    let preferredWindowIDs: [WindowManagerState.WindowID]
}

struct ExternalOpenPlacementPlan: Equatable {
    let batchID: UUID
    let windows: [Window]

    struct Window: Equatable {
        let windowID: WindowManagerState.WindowID
        let isNewWindow: Bool
        let items: [Item]
    }

    struct Item: Equatable {
        let itemID: UUID
        let tabID: ContentTabID
    }
}

struct ExternalOpenActivationAttempt: Equatable {
    let batchID: UUID
    let plan: ExternalOpenPlacementPlan
    let windowID: WindowManagerState.WindowID
    let excludedWindowIDs: Set<WindowManagerState.WindowID>
}

enum ExternalOpenPlacementFailure: Error, Equatable {
    case duplicateItemID(UUID)
    case invalidExistingTabCount(windowID: WindowManagerState.WindowID, count: Int)
    case duplicateAllocatedID(UUID)
}

enum ExternalOpenPlacementPlanner {
    private struct ExistingTarget {
        let windowID: WindowManagerState.WindowID
        let itemCount: Int
    }

    static func make(
        _ request: ExternalOpenPlacementRequest,
        state: WindowManagerState,
        generateUUID: @autoclosure () -> UUID,
    ) -> Result<ExternalOpenPlacementPlan, ExternalOpenPlacementFailure> {
        if let duplicateItemID = firstDuplicate(in: request.itemIDs) {
            return .failure(.duplicateItemID(duplicateItemID))
        }
        guard !request.itemIDs.isEmpty else {
            return .success(.init(batchID: request.batchID, windows: []))
        }

        let targetResult = existingTarget(for: request, state: state)
        guard case let .success(target) = targetResult else {
            return targetResult.map { _ in .init(batchID: request.batchID, windows: []) }
        }

        var allocatedRawIDs = existingRawIDs(in: state)
        let itemsResult = allocateItems(
            request.itemIDs,
            generateUUID: generateUUID,
            allocatedRawIDs: &allocatedRawIDs,
        )
        guard case let .success(items) = itemsResult else {
            return itemsResult.map { _ in .init(batchID: request.batchID, windows: []) }
        }

        let existingItemCount = target?.itemCount ?? 0
        let overflowItemCount = items.count - existingItemCount
        let newWindowCount = (overflowItemCount + ContentTabConstants.maxTabs - 1)
            / ContentTabConstants.maxTabs
        let windowIDsResult = allocateWindowIDs(
            count: newWindowCount,
            generateUUID: generateUUID,
            allocatedRawIDs: &allocatedRawIDs,
        )
        guard case let .success(newWindowIDs) = windowIDsResult else {
            return windowIDsResult.map { _ in .init(batchID: request.batchID, windows: []) }
        }

        return .success(.init(
            batchID: request.batchID,
            windows: makeWindows(target: target, items: items, newWindowIDs: newWindowIDs),
        ))
    }

    private static func firstDuplicate(in itemIDs: [UUID]) -> UUID? {
        var seen = Set<UUID>()
        return itemIDs.first { !seen.insert($0).inserted }
    }

    private static func existingTarget(
        for request: ExternalOpenPlacementRequest,
        state: WindowManagerState,
    ) -> Result<ExistingTarget?, ExternalOpenPlacementFailure> {
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
        guard let windowID = candidateWindowIDs.first(where: { state.windows[id: $0] != nil }),
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
            itemCount: min(request.itemIDs.count, ContentTabConstants.maxTabs - tabCount),
        ))
    }

    private static func existingRawIDs(in state: WindowManagerState) -> Set<String> {
        var rawIDs = Set(state.windows.ids.map(\.uuidString))
        for window in state.windows {
            rawIDs.formUnion(window.window.contentTabs.tabs.map(\.id.rawValue))
        }
        return rawIDs
    }

    private static func allocateItems(
        _ itemIDs: [UUID],
        generateUUID: () -> UUID,
        allocatedRawIDs: inout Set<String>,
    ) -> Result<[ExternalOpenPlacementPlan.Item], ExternalOpenPlacementFailure> {
        var items: [ExternalOpenPlacementPlan.Item] = []
        items.reserveCapacity(itemIDs.count)
        for itemID in itemIDs {
            let generatedID = generateUUID()
            guard allocatedRawIDs.insert(generatedID.uuidString).inserted else {
                return .failure(.duplicateAllocatedID(generatedID))
            }
            items.append(.init(
                itemID: itemID,
                tabID: ContentTabID(rawValue: generatedID.uuidString),
            ))
        }
        return .success(items)
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
        target: ExistingTarget?,
        items: [ExternalOpenPlacementPlan.Item],
        newWindowIDs: [UUID],
    ) -> [ExternalOpenPlacementPlan.Window] {
        let existingItemCount = target?.itemCount ?? 0
        var windows: [ExternalOpenPlacementPlan.Window] = []
        if let target, target.itemCount > 0 {
            windows.append(.init(
                windowID: target.windowID,
                isNewWindow: false,
                items: Array(items.prefix(target.itemCount)),
            ))
        }

        var overflowItems = items.dropFirst(existingItemCount)
        for windowID in newWindowIDs {
            let chunk = Array(overflowItems.prefix(ContentTabConstants.maxTabs))
            windows.append(.init(windowID: windowID, isNewWindow: true, items: chunk))
            overflowItems = overflowItems.dropFirst(chunk.count)
        }
        return windows
    }
}

enum ExternalOpenPlacementApplication {
    struct ExistingWindowActivation {
        let windowID: WindowManagerState.WindowID
        let tabIDs: [ContentTabID]
        let activeTabID: ContentTabID
    }

    struct Result {
        let windows: IdentifiedArrayOf<WindowSessionFeature.State>
        let newWindowIDs: [WindowManagerState.WindowID]
        let existingWindowActivations: [ExistingWindowActivation]
    }

    static func apply(
        _ plan: ExternalOpenPlacementPlan,
        reservationsByItemID: [UUID: ExternalContentTabReservation],
        to windows: IdentifiedArrayOf<WindowSessionFeature.State>,
    ) -> Result? {
        let plannedItems = plan.windows.flatMap(\.items)
        guard plannedItems.count == reservationsByItemID.count,
              Set(plannedItems.map(\.itemID)) == Set(reservationsByItemID.keys)
        else { return nil }

        var updatedWindows = windows
        var newWindowIDs: [WindowManagerState.WindowID] = []
        var existingWindowActivations: [ExistingWindowActivation] = []
        for placementWindow in plan.windows {
            let reservations = placementWindow.items.compactMap { item -> ExternalContentTabReservation? in
                guard let reservation = reservationsByItemID[item.itemID],
                      reservation.id == item.tabID
                else { return nil }
                return reservation
            }
            guard reservations.count == placementWindow.items.count else { return nil }

            if placementWindow.isNewWindow {
                guard updatedWindows[id: placementWindow.windowID] == nil,
                      let window = FileManagerWindowFeature.State.makeExternalInitial(
                          reservations: reservations,
                          windowID: placementWindow.windowID,
                      )
                else { return nil }
                updatedWindows.append(.init(id: placementWindow.windowID, window: window))
                newWindowIDs.append(placementWindow.windowID)
            } else {
                guard var window = updatedWindows[id: placementWindow.windowID]?.window,
                      window.reserveExternalContentTabs(reservations)
                else { return nil }
                updatedWindows[id: placementWindow.windowID]?.window = window
                guard let activeReservation = reservations.last else { return nil }
                existingWindowActivations.append(.init(
                    windowID: placementWindow.windowID,
                    tabIDs: reservations.map(\.id),
                    activeTabID: activeReservation.id,
                ))
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
        for placementWindow in plan.windows.reversed() {
            guard !excludedWindowIDs.contains(placementWindow.windowID),
                  let window = state.windows[id: placementWindow.windowID]?.window
            else { continue }
            if placementWindow.isNewWindow,
               state.externalWindowBatchIDs[placementWindow.windowID] != plan.batchID
            {
                continue
            }
            if placementWindow.items.reversed().contains(where: {
                window.contentTabs.tabs[id: $0.tabID] != nil
            }) {
                return placementWindow.windowID
            }
        }
        return nil
    }
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
    case defaultWindowBootstrapCompleted(requestID: UUID, contentTabs: ContentTabState)
    case defaultWindowBootstrapFailed(requestID: UUID)
    case externalOpenActivationResult(
        attempt: ExternalOpenActivationAttempt,
        result: FileManagerWindowActivationResult,
    )
    case windows(IdentifiedActionOf<WindowSessionFeature>)

    @CasePathable
    enum Delegate {
        case openAISettings
        case externalOpenPlacementCompleted(ExternalOpenPlacementCompletion)
        case externalOpenApplyCompleted(ExternalOpenPlacementApplicationCompletion)
        case externalOpenActivationCompleted(batchID: UUID)
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
