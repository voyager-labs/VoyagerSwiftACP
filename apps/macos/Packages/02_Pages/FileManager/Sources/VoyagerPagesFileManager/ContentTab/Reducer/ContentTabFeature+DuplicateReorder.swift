import ComposableArchitecture
import Foundation
import VoyagerEntitiesCollection
import VoyagerShared

extension ContentTabFeature {
    func duplicate(
        sourceID: ContentTabID,
        duplicateID: ContentTabID,
        state: inout ContentTabState,
    ) -> Effect<ContentTabAction> {
        guard state.tabs.count < ContentTabConstants.maxTabs,
              let source = state.tabs[id: sourceID],
              let duplicateItem = makeDuplicateItem(
                  source: source,
                  duplicateID: duplicateID,
                  existingIDs: Set(state.tabs.ids),
              )
        else {
            return .none
        }

        if source.isPinned {
            let boundaryIndex = state.tabs.firstIndex(where: { !$0.isPinned }) ?? state.tabs.endIndex
            state.tabs.insert(duplicateItem, at: boundaryIndex)
        } else {
            guard let sourceIndex = state.tabs.index(id: sourceID) else { return .none }
            state.tabs.insert(duplicateItem, at: sourceIndex + 1)
            state.previousActiveTabID = state.activeTabID
            state.recordActivation(duplicateID)
            state.activeTabID = duplicateID
        }

        return .none
    }

    func duplicateSelected(
        requests: [ContentTabDuplicateRequest],
        state: inout ContentTabState,
    ) -> Effect<ContentTabAction> {
        let remainingCapacity = ContentTabConstants.maxTabs - state.tabs.count
        guard remainingCapacity > 0, !requests.isEmpty else { return .none }

        let existingIDs = Set(state.tabs.ids)
        var seenSourceIDs = Set<ContentTabID>()
        var seenDuplicateIDs = Set<ContentTabID>()
        var validRequests: [(source: ContentTabItem, duplicate: ContentTabItem)] = []

        for request in requests {
            guard !seenSourceIDs.contains(request.sourceID),
                  !seenDuplicateIDs.contains(request.duplicateID),
                  let source = state.tabs[id: request.sourceID],
                  let duplicate = makeDuplicateItem(
                      source: source,
                      duplicateID: request.duplicateID,
                      existingIDs: existingIDs,
                  )
            else {
                continue
            }

            seenSourceIDs.insert(request.sourceID)
            seenDuplicateIDs.insert(request.duplicateID)
            validRequests.append((source, duplicate))
        }

        let successfulRequests = Array(validRequests.prefix(remainingCapacity))
        guard !successfulRequests.isEmpty else { return .none }

        let preOperationActiveID = state.activeTabID
        var updatedTabs = Array(state.tabs)
        let pinnedSourceDuplicates = successfulRequests
            .filter(\.source.isPinned)
            .map(\.duplicate)
        if !pinnedSourceDuplicates.isEmpty {
            let boundaryIndex = updatedTabs.firstIndex(where: { !$0.isPinned }) ?? updatedTabs.endIndex
            updatedTabs.insert(contentsOf: pinnedSourceDuplicates, at: boundaryIndex)
        }
        for request in successfulRequests where !request.source.isPinned {
            guard let sourceIndex = updatedTabs.firstIndex(where: { $0.id == request.source.id }) else {
                continue
            }
            updatedTabs.insert(request.duplicate, at: sourceIndex + 1)
        }
        state.tabs = .init(uniqueElements: updatedTabs)
        state.previousActiveTabID = preOperationActiveID
        state.recordActivation(successfulRequests[0].duplicate.id)
        state.activeTabID = successfulRequests[0].duplicate.id
        state.reconcileSelection()
        return .none
    }

    func makeDuplicateItem(
        source: ContentTabItem,
        duplicateID: ContentTabID,
        existingIDs: Set<ContentTabID>,
    ) -> ContentTabItem? {
        guard !existingIDs.contains(duplicateID),
              isValidDuplicate(page: source.page, anchor: source.anchor)
        else {
            return nil
        }

        return ContentTabItem(
            id: duplicateID,
            page: source.page,
            anchor: source.anchor,
            isPinned: false,
            title: source.title,
            iconName: source.iconName,
        )
    }

    static func reorderedTabs(
        _ tabs: IdentifiedArrayOf<ContentTabItem>,
        orderedMovingIDs: [ContentTabID],
        anchorID: ContentTabID,
        placement: FileManagerTopNavigationReorderPlacement,
    ) -> [ContentTabItem]? {
        let movingIDSet = Set(orderedMovingIDs)
        guard !orderedMovingIDs.isEmpty,
              movingIDSet.count == orderedMovingIDs.count,
              !movingIDSet.contains(anchorID),
              let anchor = tabs[id: anchorID],
              !anchor.isPinned,
              orderedMovingIDs.allSatisfy({ id in
                  guard let tab = tabs[id: id] else { return false }
                  return !tab.isPinned
              })
        else {
            return nil
        }

        let originalUnpinnedIDs = tabs.filter { !$0.isPinned }.map(\.id)
        var reducedUnpinnedIDs = originalUnpinnedIDs.filter { !movingIDSet.contains($0) }
        guard let anchorIndex = reducedUnpinnedIDs.firstIndex(of: anchorID) else {
            return nil
        }

        let insertionIndex = placement == .before ? anchorIndex : anchorIndex + 1
        reducedUnpinnedIDs.insert(contentsOf: orderedMovingIDs, at: insertionIndex)
        guard reducedUnpinnedIDs != originalUnpinnedIDs,
              reducedUnpinnedIDs.count == originalUnpinnedIDs.count,
              Set(reducedUnpinnedIDs) == Set(originalUnpinnedIDs)
        else {
            return nil
        }

        var reorderedUnpinnedIterator = reducedUnpinnedIDs.makeIterator()
        var result: [ContentTabItem] = []
        result.reserveCapacity(tabs.count)
        for tab in tabs {
            if tab.isPinned {
                result.append(tab)
                continue
            }

            guard let reorderedID = reorderedUnpinnedIterator.next(),
                  let reorderedTab = tabs[id: reorderedID]
            else {
                return nil
            }
            result.append(reorderedTab)
        }

        guard reorderedUnpinnedIterator.next() == nil,
              result.count == tabs.count,
              Set(result.map(\.id)) == Set(tabs.map(\.id))
        else {
            return nil
        }
        return result
    }

    func reorder(
        orderedMovingIDs: [ContentTabID],
        anchorID: ContentTabID,
        placement: FileManagerTopNavigationReorderPlacement,
        state: inout ContentTabState,
    ) -> Effect<ContentTabAction> {
        guard let reorderedTabs = Self.reorderedTabs(
            state.tabs,
            orderedMovingIDs: orderedMovingIDs,
            anchorID: anchorID,
            placement: placement,
        ) else {
            return .none
        }
        state.tabs = .init(uniqueElements: reorderedTabs)
        return .none
    }

    func isValidDuplicate(page: ContentTabPage, anchor: ContentTabPageAnchor) -> Bool {
        switch (page, anchor) {
        case (.home, .homeDefault):
            true
        case let (.directory, .directory(path)):
            UUID(uuidString: path) == nil
        case (.collection, .collectionFile):
            true
        case (.collection, .virtualCollection):
            true
        case let (.aiChat, .aiChat(sessionID)):
            UUID(uuidString: sessionID) != nil
        default:
            false
        }
    }
}
