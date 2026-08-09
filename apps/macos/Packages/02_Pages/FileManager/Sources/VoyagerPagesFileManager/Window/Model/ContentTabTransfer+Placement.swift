extension ContentTabTransfer {
    static func durablePinnedPlacement(
        in target: FileManagerWindowState,
        movingTabIDs: [ContentTabID],
        placement: ContentTabPlacement,
    ) -> ContentTabPlacement {
        guard placement == .empty else { return placement }
        let movingIDs = Set(movingTabIDs)
        let anchorID: ContentTabID? = target.lastConfirmedTopNavigationOrder.items.reversed().lazy.compactMap { item in
            guard case let .contentTab(id) = item,
                  target.suppressedPinnedTabIDs.contains(id),
                  !movingIDs.contains(id)
            else { return nil }
            return id
        }.first
        return anchorID.map(ContentTabPlacement.after) ?? .empty
    }

    static func normalizedExplicitPlacement(
        in target: FileManagerWindowState,
        replacementIDs: Set<ContentTabID>,
        targetDomain: ContentTabDomain,
        placement: ContentTabPlacement,
    ) -> ContentTabPlacement? {
        let anchorID: ContentTabID
        switch placement {
        case let .before(value), let .after(value):
            anchorID = value
        case .empty:
            return .empty
        }
        guard replacementIDs.contains(anchorID) else { return placement }
        guard let anchor = target.contentTabs.tabs[id: anchorID],
              ContentTabDomain.domain(isPinned: anchor.isPinned) == targetDomain,
              let anchorIndex = target.contentTabs.tabs.index(id: anchorID)
        else { return nil }

        let followingAnchor = target.contentTabs.tabs[(anchorIndex + 1)...].first(where: {
            !replacementIDs.contains($0.id)
                && ContentTabDomain.domain(isPinned: $0.isPinned) == targetDomain
        })
        if let followingAnchor { return .before(followingAnchor.id) }

        let precedingAnchor = target.contentTabs.tabs[..<anchorIndex].last(where: {
            !replacementIDs.contains($0.id)
                && ContentTabDomain.domain(isPinned: $0.isPinned) == targetDomain
        })
        return precedingAnchor.map { .after($0.id) } ?? .empty
    }
}
