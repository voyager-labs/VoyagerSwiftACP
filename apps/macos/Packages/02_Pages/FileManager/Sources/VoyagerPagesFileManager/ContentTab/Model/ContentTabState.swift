import ComposableArchitecture
import Foundation
import IdentifiedCollections

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
}

@ObservableState
public struct ContentTabState: Equatable {
    public var tabs: IdentifiedArrayOf<ContentTabItem> = []
    public var activeTabID: ContentTabID?
    public var previousActiveTabID: ContentTabID?
    public var recentlyClosed: ClosedContentTabSnapshot?
    public var pinnedRecords: [ContentTabID: ContentTabPinnedRecord] = [:]
    public var pinnedRecordPersistenceError: String?

    public init(
        tabs: IdentifiedArrayOf<ContentTabItem> = [],
        activeTabID: ContentTabID? = nil,
        previousActiveTabID: ContentTabID? = nil,
        recentlyClosed: ClosedContentTabSnapshot? = nil,
        pinnedRecords: [ContentTabID: ContentTabPinnedRecord] = [:],
        pinnedRecordPersistenceError: String? = nil,
    ) {
        self.tabs = tabs
        self.activeTabID = activeTabID
        self.previousActiveTabID = previousActiveTabID
        self.recentlyClosed = recentlyClosed
        self.pinnedRecords = pinnedRecords
        self.pinnedRecordPersistenceError = pinnedRecordPersistenceError
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

        let state = ContentTabState(
            tabs: tabs,
            activeTabID: tabs[0].id,
            pinnedRecords: pinnedRecords,
        )

        return (state: state, didCompact: didCompact, droppedCount: totalExcluded)
    }
}
