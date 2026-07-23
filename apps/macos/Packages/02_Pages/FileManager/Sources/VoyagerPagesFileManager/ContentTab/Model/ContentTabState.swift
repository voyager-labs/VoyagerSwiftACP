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
    public var recentlyClosed: ClosedContentTabSnapshot?
    public var pinnedRecords: [ContentTabID: ContentTabPinnedRecord] = [:]
    public var pendingPinnedRecordIDs: Set<ContentTabID> = []
    public var pinnedRecordPersistenceError: String?
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
        recentlyClosed: ClosedContentTabSnapshot? = nil,
        pinnedRecords: [ContentTabID: ContentTabPinnedRecord] = [:],
        pendingPinnedRecordIDs: Set<ContentTabID> = [],
        pinnedRecordPersistenceError: String? = nil,
    ) {
        self.tabs = tabs
        self.activeTabID = activeTabID
        self.previousActiveTabID = previousActiveTabID
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

    mutating func collapseSelectionToActive() {
        guard let activeTabID, tabs[id: activeTabID] != nil else {
            selectedTabIDs.removeAll()
            selectionAnchorID = nil
            return
        }
        selectedTabIDs = [activeTabID]
        selectionAnchorID = activeTabID
    }
}

public extension ContentTabState {
    static func withHomeTab() -> ContentTabState {
        let id = ContentTabID()
        return ContentTabState(
            tabs: [ContentTabItem(
                id: id,
                page: .home,
                anchor: .homeDefault,
                isPinned: false,
                title: "Home",
                iconName: "house",
            )],
            activeTabID: id,
            previousActiveTabID: nil,
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
            recentlyClosed: nil,
            pinnedRecords: pinnedRecords,
        )
    }

    static func restoringPinnedRecords(
        from store: ContentTabPinnedRecordStore,
        maxTabs: Int = ContentTabConstants.maxTabs,
        isRestorableAnchor: (ContentTabPageAnchor) -> Bool = { _ in true },
    ) -> (state: ContentTabState, didCompact: Bool, droppedCount: Int) {
        var seenIDs = Set<String>()
        var validRecords: [(record: ContentTabPinnedRecord, newID: ContentTabID)] = []
        var didCompact = false
        var totalExcluded = 0

        for record in store.records {
            if record.id.isEmpty {
                didCompact = true
                totalExcluded += 1
                continue
            }

            guard record.isPageAnchorCompatible else {
                didCompact = true
                totalExcluded += 1
                continue
            }

            guard isRestorableAnchor(record.anchor) else {
                didCompact = true
                totalExcluded += 1
                continue
            }

            guard seenIDs.insert(record.id).inserted else {
                didCompact = true
                totalExcluded += 1
                continue
            }

            guard validRecords.count < maxTabs else {
                didCompact = true
                totalExcluded += 1
                continue
            }

            let newID = ContentTabID(rawValue: record.id)
            validRecords.append((record, newID))
        }

        guard !validRecords.isEmpty else {
            return (state: .withHomeTab(), didCompact: didCompact, droppedCount: totalExcluded)
        }

        var pinnedRecords: [ContentTabID: ContentTabPinnedRecord] = [:]
        var tabs: IdentifiedArrayOf<ContentTabItem> = []

        for (record, newID) in validRecords {
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

        let state = ContentTabState(
            tabs: tabs,
            activeTabID: homeID,
            pinnedRecords: pinnedRecords,
        )

        return (state: state, didCompact: didCompact, droppedCount: totalExcluded)
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
