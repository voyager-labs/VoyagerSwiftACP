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

private struct ContentTabRecordValidationResult {
    let records: [(record: ContentTabPinnedRecord, newID: ContentTabID)]
    let didCompact: Bool
    let droppedCount: Int
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
        let validation = validateRestorableRecords(
            store.records,
            maxTabs: maxTabs,
            isRestorableAnchor: isRestorableAnchor,
        )

        guard !validation.records.isEmpty else {
            return (
                state: .withHomeTab(),
                didCompact: validation.didCompact,
                droppedCount: validation.droppedCount,
            )
        }

        let state = makeRestoredState(from: validation.records)

        return (
            state: state,
            didCompact: validation.didCompact,
            droppedCount: validation.droppedCount,
        )
    }

    private static func validateRestorableRecords(
        _ records: [ContentTabPinnedRecord],
        maxTabs: Int,
        isRestorableAnchor: (ContentTabPageAnchor) -> Bool,
    ) -> ContentTabRecordValidationResult {
        var seenIDs = Set<String>()
        var validRecords: [(record: ContentTabPinnedRecord, newID: ContentTabID)] = []
        var didCompact = false
        var droppedCount = 0

        for record in records {
            guard !record.id.isEmpty,
                  record.isPageAnchorCompatible,
                  isRestorableAnchor(record.anchor),
                  seenIDs.insert(record.id).inserted,
                  validRecords.count < maxTabs
            else {
                didCompact = true
                droppedCount += 1
                continue
            }
            validRecords.append((record, ContentTabID(rawValue: record.id)))
        }
        return ContentTabRecordValidationResult(
            records: validRecords,
            didCompact: didCompact,
            droppedCount: droppedCount,
        )
    }

    private static func makeRestoredState(
        from records: [(record: ContentTabPinnedRecord, newID: ContentTabID)],
    ) -> ContentTabState {
        var pinnedRecords: [ContentTabID: ContentTabPinnedRecord] = [:]
        var tabs: IdentifiedArrayOf<ContentTabItem> = []
        for validRecord in records {
            let record = validRecord.record
            let newID = validRecord.newID
            pinnedRecords[newID] = ContentTabPinnedRecord(
                id: newID.rawValue,
                page: record.page,
                anchor: record.anchor,
                title: record.title,
                iconName: record.iconName,
                pinnedAt: record.pinnedAt,
            )
            tabs.append(ContentTabItem(
                id: newID,
                page: record.page,
                anchor: record.anchor,
                isPinned: true,
                title: record.title,
                iconName: record.iconName,
            ))
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
        return ContentTabState(tabs: tabs, activeTabID: homeID, pinnedRecords: pinnedRecords)
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
