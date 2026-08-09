extension ContentTabTransfer {
    struct UnavailableTargetFallbackItem {
        let item: ContentTabItem
        let pinnedRecord: ContentTabPinnedRecord?
        let runtimePreservationRecord: ContentTabPinnedRecord?
    }

    static func unavailableTargetFallbackSource(
        source: FileManagerWindowState,
        projectedItems: [UnavailableTargetFallbackItem],
        shouldRetain: Bool,
    ) -> FileManagerWindowState? {
        guard shouldRetain else { return nil }
        var fallback = source
        let movedTabIDs = projectedItems.map(\.item.id)
        guard movedTabIDs.allSatisfy({ source.contentTabs.tabs[id: $0] != nil }) else { return nil }

        for tabID in movedTabIDs {
            guard let index = fallback.contentTabs.tabs.index(id: tabID) else { return nil }
            fallback.contentTabs.tabs.remove(at: index)
        }
        let insertionIndex = fallback.contentTabs.tabs.firstIndex(where: { !$0.isPinned })
            ?? fallback.contentTabs.tabs.endIndex
        fallback.contentTabs.tabs.insert(contentsOf: projectedItems.map(\.item), at: insertionIndex)

        for projectedItem in projectedItems {
            let tabID = projectedItem.item.id
            fallback.contentTabs.pinnedRecords[tabID] = projectedItem.pinnedRecord
            fallback.contentTabs.pendingPinnedRecordIDs.remove(tabID)
            fallback.pendingRuntimePreservationRecords[tabID] = projectedItem.runtimePreservationRecord
            fallback.suppressedPinnedTabIDs.remove(tabID)
        }
        fallback.syncContentTabSidebarItems()
        return fallback
    }
}
