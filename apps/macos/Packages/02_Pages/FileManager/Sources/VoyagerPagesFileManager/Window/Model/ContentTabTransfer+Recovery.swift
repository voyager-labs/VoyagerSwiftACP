extension ContentTabTransfer {
    static func unavailableTargetFallbackSource(
        source: FileManagerWindowState,
        movedTabIDs: [ContentTabID],
        shouldRetain: Bool,
    ) -> FileManagerWindowState? {
        guard shouldRetain else { return nil }
        var fallback = source
        let movedItems = movedTabIDs.compactMap { tabID -> ContentTabItem? in
            guard var item = source.contentTabs.tabs[id: tabID] else { return nil }
            item.isPinned = false
            return item
        }
        guard movedItems.count == movedTabIDs.count else { return nil }

        for tabID in movedTabIDs {
            guard let index = fallback.contentTabs.tabs.index(id: tabID) else { return nil }
            fallback.contentTabs.tabs.remove(at: index)
        }
        let insertionIndex = fallback.contentTabs.tabs.firstIndex(where: { !$0.isPinned })
            ?? fallback.contentTabs.tabs.endIndex
        fallback.contentTabs.tabs.insert(contentsOf: movedItems, at: insertionIndex)

        for tabID in movedTabIDs {
            fallback.contentTabs.pinnedRecords[tabID] = nil
            fallback.contentTabs.pendingPinnedRecordIDs.remove(tabID)
            fallback.pendingRuntimePreservationRecords[tabID] = nil
            fallback.suppressedPinnedTabIDs.remove(tabID)
        }
        fallback.syncContentTabSidebarItems()
        return fallback
    }
}
