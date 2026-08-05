import Foundation

public enum FileManagerTopNavigationMoveDestination: Equatable, Sendable {
    case before(FileManagerTopNavigationItemID)
    case after(FileManagerTopNavigationItemID)
}

public enum FileManagerTopNavigationOrderPolicy {
    public struct DormantContentTabSlot: Equatable, Sendable {
        public let id: ContentTabID
        public let before: FileManagerTopNavigationItemID?
        public let after: FileManagerTopNavigationItemID?

        public init(
            id: ContentTabID,
            before: FileManagerTopNavigationItemID?,
            after: FileManagerTopNavigationItemID?,
        ) {
            self.id = id
            self.before = before
            self.after = after
        }
    }

    public struct Projection: Equatable, Sendable {
        public let normalizedStore: ContentTabPinnedRecordStore
        public let durableOrder: FileManagerTopNavigationOrder
        public let runtimeOrder: FileManagerTopNavigationOrder
        public let visibleMixedTopOrder: FileManagerTopNavigationOrder

        public init(
            normalizedStore: ContentTabPinnedRecordStore,
            durableOrder: FileManagerTopNavigationOrder,
            runtimeOrder: FileManagerTopNavigationOrder,
            visibleMixedTopOrder: FileManagerTopNavigationOrder,
        ) {
            self.normalizedStore = normalizedStore
            self.durableOrder = durableOrder
            self.runtimeOrder = runtimeOrder
            self.visibleMixedTopOrder = visibleMixedTopOrder
        }
    }

    public static func normalize(
        store: ContentTabPinnedRecordStore,
        discoveredLocationIDs: [String],
        dormantContentTabSlots: [DormantContentTabSlot] = [],
    ) -> Projection {
        let validRecordIDs = Set(store.records.lazy.map(\.id).filter(FileManagerTopNavigationItemID.isValidRawID))
        let durableItems = normalizedDurableItems(
            store: store,
            discoveredLocationIDs: discoveredLocationIDs,
            validRecordIDs: validRecordIDs,
        )
        let durableOrder = FileManagerTopNavigationOrder(items: durableItems)
        let runtimeOrder = dormantContentTabSlots.reduce(into: durableOrder) { order, slot in
            guard FileManagerTopNavigationItemID.isValidRawID(slot.id.rawValue) else { return }
            order = insertingPinnedItem(slot.id, into: order, dormantSlot: slot)
        }
        let discoveredSet = Set(discoveredLocationIDs.filter(FileManagerTopNavigationItemID.isValidRawID))
        let visibleItems = runtimeOrder.items.filter { item in
            switch item {
            case let .location(id):
                discoveredSet.contains(id)
            case let .contentTab(id):
                validRecordIDs.contains(id.rawValue)
            }
        }
        var normalizedStore = store
        normalizedStore.schemaVersion = 2
        normalizedStore.topNavigationOrder = durableOrder
        return Projection(
            normalizedStore: normalizedStore,
            durableOrder: durableOrder,
            runtimeOrder: runtimeOrder,
            visibleMixedTopOrder: .init(items: visibleItems),
        )
    }

    public static func reconcilingDiscoveredLocations(
        in order: FileManagerTopNavigationOrder,
        discoveredLocationIDs: [String],
    ) -> FileManagerTopNavigationOrder {
        var items = order.items
        var itemSet = Set(items)
        insertMissingDiscoveredLocations(
            discoveredLocationIDs,
            into: &items,
            itemSet: &itemSet,
        )
        return .init(items: items)
    }

    public static func runtimeOrder(
        authoritativeOrder: FileManagerTopNavigationOrder,
        discoveredLocationIDs: [String],
        pinnedContentTabIDs: [ContentTabID],
        dormantContentTabSlots: [DormantContentTabSlot],
    ) -> FileManagerTopNavigationOrder {
        let pinnedIDSet = Set(pinnedContentTabIDs)
        let dormantIDSet = Set(dormantContentTabSlots.map(\.id))
        var seenItems = Set<FileManagerTopNavigationItemID>()
        var items = authoritativeOrder.items.filter { item in
            guard item.isSyntacticallyValid, seenItems.insert(item).inserted else { return false }
            guard case let .contentTab(id) = item else { return true }
            return pinnedIDSet.contains(id) || dormantIDSet.contains(id)
        }
        var itemSet = Set(items)
        appendMissingPinnedItems(from: pinnedContentTabIDs, to: &items, itemSet: &itemSet)
        insertMissingDiscoveredLocations(
            discoveredLocationIDs,
            into: &items,
            itemSet: &itemSet,
        )
        var runtimeOrder = FileManagerTopNavigationOrder(items: items)
        for slot in dormantContentTabSlots where !runtimeOrder.items.contains(.contentTab(slot.id)) {
            runtimeOrder = insertingPinnedItem(slot.id, into: runtimeOrder, dormantSlot: slot)
        }
        return runtimeOrder
    }

    public static func insertingPinnedItem(
        _ id: ContentTabID,
        into order: FileManagerTopNavigationOrder,
        dormantSlot: DormantContentTabSlot? = nil,
    ) -> FileManagerTopNavigationOrder {
        let item = FileManagerTopNavigationItemID.contentTab(id)
        guard FileManagerTopNavigationItemID.isValidRawID(id.rawValue) else { return order }
        var items = order.items.filter { $0 != item }
        guard let dormantSlot else {
            items.append(item)
            return .init(items: items)
        }

        if let before = dormantSlot.before,
           let beforeIndex = items.firstIndex(of: before)
        {
            items.insert(item, at: beforeIndex + 1)
        } else if let after = dormantSlot.after,
                  let afterIndex = items.firstIndex(of: after)
        {
            items.insert(item, at: afterIndex)
        } else {
            items.append(item)
        }
        return .init(items: items)
    }

    public static func moving(
        _ source: FileManagerTopNavigationItemID,
        to destination: FileManagerTopNavigationMoveDestination,
        in order: FileManagerTopNavigationOrder,
    ) -> FileManagerTopNavigationOrder {
        let anchor: FileManagerTopNavigationItemID
        let placesAfter: Bool
        switch destination {
        case let .before(item):
            anchor = item
            placesAfter = false
        case let .after(item):
            anchor = item
            placesAfter = true
        }
        guard source != anchor,
              order.items.contains(source),
              order.items.contains(anchor)
        else { return order }

        var items = order.items
        items.removeAll { $0 == source }
        guard let anchorIndex = items.firstIndex(of: anchor) else { return order }
        items.insert(source, at: placesAfter ? anchorIndex + 1 : anchorIndex)
        return items == order.items ? order : .init(items: items)
    }

    public static func movingPinnedContentTabs(
        _ orderedIDs: [ContentTabID],
        to destination: FileManagerTopNavigationMoveDestination,
        in order: FileManagerTopNavigationOrder,
    ) -> FileManagerTopNavigationOrder {
        guard !orderedIDs.isEmpty,
              Set(orderedIDs).count == orderedIDs.count,
              orderedIDs.allSatisfy({ FileManagerTopNavigationItemID.isValidRawID($0.rawValue) })
        else { return order }

        let movingItems = orderedIDs.map(FileManagerTopNavigationItemID.contentTab)
        let movingItemSet = Set(movingItems)
        let anchor: FileManagerTopNavigationItemID
        let placesAfter: Bool
        switch destination {
        case let .before(item):
            anchor = item
            placesAfter = false
        case let .after(item):
            anchor = item
            placesAfter = true
        }
        guard !movingItemSet.contains(anchor),
              order.items.contains(anchor),
              movingItems.allSatisfy(order.items.contains)
        else { return order }

        var items = order.items.filter { !movingItemSet.contains($0) }
        guard let anchorIndex = items.firstIndex(of: anchor) else { return order }
        items.insert(contentsOf: movingItems, at: placesAfter ? anchorIndex + 1 : anchorIndex)
        return items == order.items ? order : .init(items: items)
    }

    private static func normalizedDurableItems(
        store: ContentTabPinnedRecordStore,
        discoveredLocationIDs: [String],
        validRecordIDs: Set<String>,
    ) -> [FileManagerTopNavigationItemID] {
        var seenItems = Set<FileManagerTopNavigationItemID>()
        var items = store.topNavigationOrder.items.filter { item in
            guard seenItems.insert(item).inserted, item.isSyntacticallyValid else { return false }
            guard case let .contentTab(id) = item else { return true }
            return validRecordIDs.contains(id.rawValue)
        }
        var itemSet = Set(items)
        appendMissingPinnedItems(from: store.records, to: &items, itemSet: &itemSet)
        insertMissingDiscoveredLocations(
            discoveredLocationIDs,
            into: &items,
            itemSet: &itemSet,
        )
        return items
    }

    private static func appendMissingPinnedItems(
        from records: [ContentTabPinnedRecord],
        to items: inout [FileManagerTopNavigationItemID],
        itemSet: inout Set<FileManagerTopNavigationItemID>,
    ) {
        appendMissingPinnedItems(
            from: records.map { ContentTabID(rawValue: $0.id) },
            to: &items,
            itemSet: &itemSet,
        )
    }

    private static func appendMissingPinnedItems(
        from ids: [ContentTabID],
        to items: inout [FileManagerTopNavigationItemID],
        itemSet: inout Set<FileManagerTopNavigationItemID>,
    ) {
        for id in ids where FileManagerTopNavigationItemID.isValidRawID(id.rawValue) {
            let item = FileManagerTopNavigationItemID.contentTab(id)
            if itemSet.insert(item).inserted {
                items.append(item)
            }
        }
    }

    private static func insertMissingDiscoveredLocations(
        _ discoveredLocationIDs: [String],
        into items: inout [FileManagerTopNavigationItemID],
        itemSet: inout Set<FileManagerTopNavigationItemID>,
    ) {
        var seenLocationIDs = Set<String>()
        let locationItems = discoveredLocationIDs.compactMap { id -> FileManagerTopNavigationItemID? in
            guard FileManagerTopNavigationItemID.isValidRawID(id),
                  seenLocationIDs.insert(id).inserted
            else { return nil }
            return .location(id)
        }
        for item in locationItems where itemSet.insert(item).inserted {
            if let finalLocationIndex = items.lastIndex(where: { candidate in
                if case .location = candidate { true } else { false }
            }) {
                items.insert(item, at: finalLocationIndex + 1)
            } else {
                items.insert(item, at: items.startIndex)
            }
        }
    }
}
