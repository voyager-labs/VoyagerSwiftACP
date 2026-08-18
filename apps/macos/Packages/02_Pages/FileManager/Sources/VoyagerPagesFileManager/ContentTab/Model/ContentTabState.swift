import ComposableArchitecture
import Foundation
import IdentifiedCollections
import VoyagerEntitiesCollection

public struct ContentTabID: Hashable, Sendable, Codable {
    public let rawValue: String

    public init() {
        rawValue = UUID().uuidString
    }

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public enum ContentTabPage: Equatable, Sendable, Codable {
    case home
    case directory
    case collection
    case aiChat
}

public enum ContentTabPageAnchor: Equatable, Sendable, Codable {
    case homeDefault
    case directory(path: String)
    case collectionFile(url: URL)
    case virtualCollection(id: String)
    case aiChat(sessionID: String)
}

public struct ContentTabItem: Equatable, Sendable, Identifiable {
    public let id: ContentTabID
    public var page: ContentTabPage
    public var anchor: ContentTabPageAnchor
    public var isPinned: Bool
    public var title: String?
    public var iconName: String?
}

public struct ClosedContentTabSnapshot: Equatable, Sendable, Codable {
    public var page: ContentTabPage
    public var anchor: ContentTabPageAnchor
    public var wasPinned: Bool
    public var closedAt: Date
    public var title: String?
    public var iconName: String?
}

@ObservableState
public struct ContentTabState: Equatable, Sendable {
    public var tabs: IdentifiedArrayOf<ContentTabItem> = [] {
        didSet { reconcileSelection() }
    }

    public var activeTabID: ContentTabID? {
        didSet { reconcileSelection() }
    }

    public var previousActiveTabID: ContentTabID?
    public internal(set) var recentlyUsedTabIDs: [ContentTabID]
    public var recentlyClosed: ClosedContentTabSnapshot?
    public var pinnedRecords: [ContentTabID: ContentTabPinnedRecord] = [:]
    public var pendingPinnedRecordIDs: Set<ContentTabID> = []
    public var pinnedRecordPersistenceError: String?
    let pinnedRecordPersistenceScopeID = UUID()
    public internal(set) var selectedTabIDs: Set<ContentTabID> = []
    var selectionAnchorID: ContentTabID?

    public var selectedTabCount: Int {
        orderedValidSelectedTabIDs.count
    }

    public var isBulkActionEnabled: Bool {
        selectedTabCount > 1
    }

    public var orderedValidSelectedTabIDs: [ContentTabID] {
        selectionOrderedTabIDs.filter(selectedTabIDs.contains)
    }

    var selectionOrderedTabIDs: [ContentTabID] {
        tabs.filter(\.isPinned).map(\.id) + tabs.filter { !$0.isPinned }.map(\.id)
    }

    public init(
        tabs: IdentifiedArrayOf<ContentTabItem> = [],
        activeTabID: ContentTabID? = nil,
        previousActiveTabID: ContentTabID? = nil,
        recentlyUsedTabIDs: [ContentTabID] = [],
        recentlyClosed: ClosedContentTabSnapshot? = nil,
        pinnedRecords: [ContentTabID: ContentTabPinnedRecord] = [:],
        pendingPinnedRecordIDs: Set<ContentTabID> = [],
        pinnedRecordPersistenceError: String? = nil,
    ) {
        self.tabs = tabs
        self.activeTabID = activeTabID
        self.previousActiveTabID = previousActiveTabID
        self.recentlyUsedTabIDs = recentlyUsedTabIDs
        self.recentlyClosed = recentlyClosed
        self.pinnedRecords = pinnedRecords
        self.pendingPinnedRecordIDs = pendingPinnedRecordIDs
        self.pinnedRecordPersistenceError = pinnedRecordPersistenceError
        reconcileSelection()
    }

    mutating func reconcileSelection() {
        let currentTabIDs = Set(tabs.ids)
        selectedTabIDs.formIntersection(currentTabIDs)
        if let selectionAnchorID, !currentTabIDs.contains(selectionAnchorID) {
            self.selectionAnchorID = nil
        }
    }

    mutating func recordActivation(_ tabID: ContentTabID) {
        guard tabs[id: tabID] != nil else { return }

        let candidates = [tabID, activeTabID].compactMap(\.self) + recentlyUsedTabIDs
        let liveTabIDs = Set(tabs.ids)
        var seenTabIDs = Set<ContentTabID>()
        recentlyUsedTabIDs = candidates.filter {
            liveTabIDs.contains($0) && seenTabIDs.insert($0).inserted
        }
    }

    mutating func pruneRecentlyUsedTabIDs() {
        let liveTabIDs = Set(tabs.ids)
        var seenTabIDs = Set<ContentTabID>()
        recentlyUsedTabIDs = recentlyUsedTabIDs.filter {
            liveTabIDs.contains($0) && seenTabIDs.insert($0).inserted
        }
    }

    mutating func projectActivation(
        activeTabID: ContentTabID?,
        recentlyUsedTabIDs: [ContentTabID],
    ) {
        self.activeTabID = activeTabID
        self.recentlyUsedTabIDs = recentlyUsedTabIDs
        pruneRecentlyUsedTabIDs()
        if let activeTabID {
            recordActivation(activeTabID)
        }
    }

    mutating func takeMostRecentlyUsedInactiveTabID() -> ContentTabID? {
        pruneRecentlyUsedTabIDs()
        return recentlyUsedTabIDs.first { $0 != activeTabID }
    }

    mutating func collapseSelectionToActive() {
        guard let activeTabID, tabs[id: activeTabID] != nil else {
            selectedTabIDs.removeAll()
            selectionAnchorID = nil
            return
        }
        selectedTabIDs = [activeTabID]
        selectionAnchorID = activeTabID
    }

    public func markLatestPinnedRecordPersistenceIntent(for tabID: ContentTabID) -> UUID {
        PinnedRecordPersistenceIntent.markLatest(
            scopeID: pinnedRecordPersistenceScopeID,
            tabID: tabID,
        )
    }

    public func isCurrentPinnedRecordPersistenceIntent(
        tabID: ContentTabID,
        intentID: UUID,
    ) -> Bool {
        PinnedRecordPersistenceIntent.isCurrent(
            scopeID: pinnedRecordPersistenceScopeID,
            tabID: tabID,
            intentID: intentID,
        )
    }
}

public extension ContentTabState {
    static func withHomeTab() -> ContentTabState {
        let id = ContentTabID()
        return ContentTabState(
            tabs: [
                ContentTabItem(
                    id: id,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
            ],
            activeTabID: id,
            previousActiveTabID: nil,
            recentlyUsedTabIDs: [id],
            recentlyClosed: nil,
        )
    }

    static func bootstrapping(
        restoredTabs: IdentifiedArrayOf<ContentTabItem> = [],
        activeTabID: ContentTabID? = nil,
        pinnedRecords: [ContentTabID: ContentTabPinnedRecord] = [:],
    ) -> ContentTabState {
        guard let first = restoredTabs.first else { return .withHomeTab() }

        let active: ContentTabID = if let activeTabID, restoredTabs[id: activeTabID] != nil {
            activeTabID
        } else {
            first.id
        }

        return ContentTabState(
            tabs: restoredTabs,
            activeTabID: active,
            previousActiveTabID: nil,
            recentlyUsedTabIDs: [active],
            recentlyClosed: nil,
            pinnedRecords: pinnedRecords,
        )
    }

    struct PinnedRecordRestoration: Equatable {
        public let state: ContentTabState
        public let didCompact: Bool
        public let droppedCount: Int
    }

    static func restoringPinnedRecords(
        from store: ContentTabPinnedRecordStore,
        maxTabs: Int = ContentTabConstants.maxTabs,
        isRestorableAnchor: (ContentTabPageAnchor) -> Bool = { _ in true },
    ) -> PinnedRecordRestoration {
        let collection = collectRestorableRecords(
            from: store,
            maxTabs: maxTabs,
            isRestorableAnchor: isRestorableAnchor,
        )

        guard !collection.records.isEmpty else {
            return PinnedRecordRestoration(
                state: .withHomeTab(),
                didCompact: collection.didCompact,
                droppedCount: collection.excludedCount,
            )
        }

        return PinnedRecordRestoration(
            state: makeRestoredState(from: collection),
            didCompact: collection.didCompact,
            droppedCount: collection.excludedCount,
        )
    }

    private static func makeRestoredState(from collection: RestoredRecordCollection) -> ContentTabState {
        var pinnedRecords: [ContentTabID: ContentTabPinnedRecord] = [:]
        var tabs: IdentifiedArrayOf<ContentTabItem> = []

        for (record, newID) in collection.records {
            let normalizedRecord = ContentTabPinnedRecord(
                id: newID.rawValue,
                page: record.page,
                anchor: record.anchor,
                title: record.title,
                iconName: record.iconName,
                pinnedAt: record.pinnedAt,
            )
            pinnedRecords[newID] = normalizedRecord

            let item = ContentTabItem(
                id: newID,
                page: record.page,
                anchor: record.anchor,
                isPinned: true,
                title: record.title,
                iconName: record.iconName,
            )
            tabs.append(item)
        }

        let homeID = ContentTabID()
        tabs.append(ContentTabItem(
            id: homeID,
            page: .home,
            anchor: .homeDefault,
            isPinned: false,
            title: "Home",
            iconName: "house",
        ))

        return ContentTabState(
            tabs: tabs,
            activeTabID: homeID,
            pinnedRecords: pinnedRecords,
        )
    }

    private static func collectRestorableRecords(
        from store: ContentTabPinnedRecordStore,
        maxTabs: Int,
        isRestorableAnchor: (ContentTabPageAnchor) -> Bool,
    ) -> RestoredRecordCollection {
        var collection = RestoredRecordCollection()
        var seenIDs = Set<String>()
        for record in store.records {
            if record.id.isEmpty {
                collection.didCompact = true
                collection.excludedCount += 1
                continue
            }

            guard record.isPageAnchorCompatible else {
                collection.didCompact = true
                collection.excludedCount += 1
                continue
            }

            guard record.isSupportedPinnedContentTab else {
                collection.didCompact = true
                collection.excludedCount += 1
                continue
            }

            guard isRestorableAnchor(record.anchor) else {
                collection.didCompact = true
                collection.excludedCount += 1
                continue
            }

            guard seenIDs.insert(record.id).inserted else {
                collection.didCompact = true
                collection.excludedCount += 1
                continue
            }

            guard collection.records.count < maxTabs else {
                collection.didCompact = true
                collection.excludedCount += 1
                continue
            }

            collection.records.append((record, ContentTabID(rawValue: record.id)))
        }
        return collection
    }
}

extension ContentTabItem {
    static func makeExternalReservation(
        id: ContentTabID,
        anchor: ContentTabPageAnchor,
    ) -> Self {
        let page: ContentTabPage
        let title: String
        let iconName: String
        switch anchor {
        case let .directory(path):
            page = .directory
            let lastPathComponent = URL(fileURLWithPath: path).lastPathComponent
            title = lastPathComponent.isEmpty ? path : lastPathComponent
            iconName = "folder"
        case let .collectionFile(url):
            page = .collection
            title = CollectionFileUtils.displayName(url, fallback: url.lastPathComponent)
            iconName = "rectangle.stack"
        case .homeDefault:
            page = .home
            title = "Home"
            iconName = "house"
        case let .virtualCollection(id):
            page = .collection
            title = id
            iconName = "folder"
        case .aiChat:
            page = .aiChat
            title = "AI Chat"
            iconName = "sparkles"
        }
        return Self(
            id: id,
            page: page,
            anchor: anchor,
            isPinned: false,
            title: title,
            iconName: iconName,
        )
    }
}

private struct RestoredRecordCollection {
    var records: [(record: ContentTabPinnedRecord, newID: ContentTabID)] = []
    var didCompact = false
    var excludedCount = 0
}
