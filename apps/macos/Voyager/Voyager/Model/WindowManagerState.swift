import ComposableArchitecture
import Foundation
import VoyagerPagesFileManager

struct WindowManagerTopNavigationPersistenceRequest: Equatable {
    let sourceWindowID: WindowManagerState.WindowID
    let token: FileManagerTopNavigationOperationToken
    let operation: Operation

    enum Operation: Equatable {
        case move(
            source: FileManagerTopNavigationItemID,
            destination: FileManagerTopNavigationMoveDestination,
            discoveredLocationIDs: [String],
        )
        case pinnedRecord(
            source: FileManagerPinnedRecordPersistenceSource,
            request: ContentTabPinnedRecordPersistenceRequest,
            discoveredLocationIDs: [String],
        )
    }
}

struct WindowManagerTopNavigationPersistenceResult: Equatable {
    let request: WindowManagerTopNavigationPersistenceRequest
    let terminal: FileManagerTopNavigationIntentTerminal
    let authoritativePinnedContentTabs: ContentTabState?
}

struct WindowManagerTrackedSingletonWindow: Equatable {
    var requestID: UUID
    var windowID: UUID
    var terminalOutcomeEmitted = false
}

struct WindowManagerRetainedExternalOpenPlacementOwnership: Equatable {
    var batchID: UUID
    var newWindowIDs: [UUID]
}

struct ContentTabMoveTerminalRecord: Equatable {
    enum Outcome: Equatable {
        case succeeded
        case rejected(ContentTabMoveFailurePresentation.Category)
    }

    let requestID: UUID
    let sourceWindowID: UUID
    let tabID: ContentTabID
    let targetWindowID: UUID
    let outcome: Outcome
}

struct ContentTabMoveActivationAttempt: Equatable {
    let requestID: UUID
    let targetWindowID: UUID
}

@ObservableState
struct WindowManagerState: Equatable {
    typealias WindowID = WindowSessionState.ID

    static let contentTabMoveTerminalLimit = 256

    var appPreferences: AppPreferencesFeature.State = .init()
    var windows: IdentifiedArrayOf<WindowSessionFeature.State> = []
    var focusedWindowID: WindowID?
    var pendingWindowOpenIDs: Set<WindowID> = []
    var closingWindowIDs: Set<WindowID> = []
    var deferredClosedWindowIDs: Set<WindowID> = []
    var invalidatingWindowIDs: Set<WindowID> = []
    var lastUsedWindowIDs: [WindowID] = []
    var defaultWindowBootstrapRequestID: UUID?
    var defaultWindowBootstrapWindowIDs: Set<WindowID> = []
    var externalWindowBatchIDs: [WindowID: UUID] = [:]
    var retainedExternalOpenPlacementOwnership: WindowManagerRetainedExternalOpenPlacementOwnership?
    var authorizedExternalOpenBatchID: UUID?
    var authorizedTrackedSingletonRequestID: UUID?
    var trackedSingletonWindow: WindowManagerTrackedSingletonWindow?
    var externalOpenActivationAttempt: ExternalOpenActivationAttempt?
    var topNavigationPersistenceQueue: [WindowManagerTopNavigationPersistenceRequest] = []
    var isTopNavigationPersistenceInFlight = false
    var contentTabMoveTerminalRecords: [UUID: ContentTabMoveTerminalRecord] = [:]
    var contentTabMoveTerminalRequestIDs: [UUID] = []
    var contentTabMoveActivationAttempts: [UUID: ContentTabMoveActivationAttempt] = [:]

    mutating func moveWindowToMRUFront(_ id: WindowID) {
        lastUsedWindowIDs.removeAll { $0 == id }
        lastUsedWindowIDs.insert(id, at: 0)
    }

    mutating func recordContentTabMoveTerminal(_ record: ContentTabMoveTerminalRecord) {
        guard contentTabMoveTerminalRecords[record.requestID] == nil else { return }
        contentTabMoveTerminalRecords[record.requestID] = record
        contentTabMoveTerminalRequestIDs.append(record.requestID)
        while contentTabMoveTerminalRequestIDs.count > Self.contentTabMoveTerminalLimit {
            contentTabMoveTerminalRecords[contentTabMoveTerminalRequestIDs.removeFirst()] = nil
        }
    }

    mutating func refreshContentTabMoveTargets() {
        var seen = Set<WindowID>()
        let orderedWindowIDs = (lastUsedWindowIDs + windows.ids).filter { id in
            guard seen.insert(id).inserted,
                  windows[id: id] != nil,
                  !closingWindowIDs.contains(id),
                  !pendingWindowOpenIDs.contains(id)
            else { return false }
            return true
        }
        let titles = Dictionary(uniqueKeysWithValues: orderedWindowIDs.map { id in
            (id, contentTabMoveTitle(for: id))
        })
        let duplicateTitles = Dictionary(grouping: titles.values, by: { $0 })
            .filter { $0.value.count > 1 }
            .keys

        for sourceWindowID in windows.ids {
            guard let sourceWindow = windows[id: sourceWindowID]?.window else { continue }
            let projectedTargets: [ContentTabMoveTarget] = orderedWindowIDs
                .enumerated()
                .compactMap { index, targetWindowID in
                    guard targetWindowID != sourceWindowID,
                          let title = titles[targetWindowID],
                          let targetWindow = windows[id: targetWindowID]?.window
                    else { return nil }
                    let acceptsNewTabs = targetWindow.contentTabs.tabs.count < ContentTabConstants.maxTabs
                    let replaceablePinnedTabIDs = acceptsNewTabs ? [] : Set(
                        sourceWindow.contentTabs.tabs.ids.filter { tabID in
                            targetWindow.canAcceptContentTabMove(
                                tabID: tabID,
                                sourcePinnedRecord: sourceWindow.contentTabs.pinnedRecords[tabID],
                            )
                        },
                    )
                    guard acceptsNewTabs || !replaceablePinnedTabIDs.isEmpty else { return nil }
                    let displayTitle = duplicateTitles.contains(title)
                        ? "\(title) — Window \(index + 1)"
                        : title
                    return ContentTabMoveTarget(
                        windowID: targetWindowID,
                        displayTitle: displayTitle,
                        acceptsNewTabs: acceptsNewTabs,
                        replaceablePinnedTabIDs: replaceablePinnedTabIDs,
                    )
                }
            windows[id: sourceWindowID]?.window.sidebar.currentWindowID = sourceWindowID
            windows[id: sourceWindowID]?.window.sidebar.contentTabMoveTargets = projectedTargets
        }
    }

    private func contentTabMoveTitle(for windowID: WindowID) -> String {
        guard let window = windows[id: windowID]?.window,
              let activeTabID = window.contentTabs.activeTabID,
              let title = window.contentTabs.tabs[id: activeTabID]?.title?
              .trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty
        else { return "Untitled Window" }
        return title
    }
}

@Reducer
struct WindowSessionFeature {
    typealias State = WindowSessionState
    typealias Action = WindowSessionAction

    var body: some Reducer<State, Action> {
        Scope(state: \.window, action: \.window) {
            FileManagerWindowFeature()
                .dependency(\.fileManagerPinnedRecordOwner, .windowManager)
        }

        Reduce { _, action in
            switch action {
            case .window:
                .none
            }
        }
    }
}
