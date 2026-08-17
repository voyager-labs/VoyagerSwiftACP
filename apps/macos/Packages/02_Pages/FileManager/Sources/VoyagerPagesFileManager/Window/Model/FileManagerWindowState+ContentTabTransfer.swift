import Foundation
import VoyagerEntitiesAi
import VoyagerFeaturesAiChat
import VoyagerFeaturesContentPageNavigation

extension FileManagerWindowState {
    mutating func insertBackgroundOwners(
        _ payload: ContentTabTransfer.WorkUnit,
        targetWindowID: UUID,
    ) {
        for (sessionID, var contentState) in payload.backgroundContent {
            contentState.applyTransferWindowContext(windowID: targetWindowID)
            backgroundAiChatStates[sessionID] = contentState
        }
        for (sessionID, inspectorState) in payload.backgroundInspector {
            backgroundInspectorAiChatStates[sessionID] = inspectorState
        }
    }

    func hasValidPinParity(tabID: ContentTabID) -> Bool {
        guard let item = contentTabs.tabs[id: tabID] else { return false }
        let record = contentTabs.pinnedRecords[tabID]
        guard item.isPinned == (record != nil) else { return false }
        guard let record else { return true }
        return record.id == item.id.rawValue
    }

    func isPassivePinnedProjection(
        tabID: ContentTabID,
        sourceRecord: ContentTabPinnedRecord?,
    ) -> Bool {
        guard let item = contentTabs.tabs[id: tabID],
              item.isPinned,
              let sourceRecord,
              let targetRecord = contentTabs.pinnedRecords[tabID],
              sourceRecord.id == targetRecord.id,
              targetRecord.id == item.id.rawValue,
              targetRecord.page == item.page,
              targetRecord.anchor == item.anchor,
              targetRecord.title == item.title,
              targetRecord.iconName == item.iconName,
              !contentTabs.pendingPinnedRecordIDs.contains(tabID)
        else { return false }

        let targetContent = contentTabs.activeTabID == tabID ? content : tabContentStates[tabID]
        guard let targetContent else { return false }
        var passiveContent = FileManagerContentFeature.State.initialContent(
            for: item.anchor,
            inheritingWindowContextFrom: targetContent,
        )
        passiveContent.entryViewLayout.entryOperations.loadingCancellationOwnerID = targetContent
            .entryViewLayout.entryOperations.loadingCancellationOwnerID
        passiveContent.entryViewLayout.entryOperations.undoOwnerID = targetContent
            .entryViewLayout.entryOperations.undoOwnerID
        passiveContent.entryViewLayout.collectionWindowID = targetContent.entryViewLayout.collectionWindowID
        passiveContent.entryViewLayout.collectionLoadingCancellationOwnerID = targetContent
            .entryViewLayout.collectionLoadingCancellationOwnerID
        guard targetContent.isPassiveProjection(matching: passiveContent) else { return false }

        if supportsInspector(tabID: tabID) {
            let targetInspector = contentTabs.activeTabID == tabID ? inspector : tabInspectorStates[tabID]
            let passiveInspector = FileManagerInspectorFeature.State().tabSnapshot()
            guard let targetInspector,
                  !targetInspector.inspectorVisible,
                  !targetInspector.inspectorPaneExists,
                  targetInspector.inspectorWidth == FileManagerInspectorLayoutMetrics.defaultWidth,
                  targetInspector.activeMode == .chat,
                  targetInspector.aiChat.isPassiveContentTabProjection(matching: passiveInspector.aiChat)
            else { return false }
        }
        let ownedSessionIDs = targetContent.aiChat.contentTabTransferSessionIDs
            .union((contentTabs.activeTabID == tabID ? inspector : tabInspectorStates[tabID])?.aiChat
                .contentTabTransferSessionIDs ?? [])
        return ownedSessionIDs.isDisjoint(with: Set(backgroundAiChatStates.keys))
            && ownedSessionIDs.isDisjoint(with: Set(backgroundInspectorAiChatStates.keys))
    }

    var hasCompleteTransferOwnership: Bool {
        if contentTabs.tabs.isEmpty {
            return contentTabs.activeTabID == nil
                && contentTabs.previousActiveTabID == nil
                && tabContentStates.isEmpty
                && tabInspectorStates.isEmpty
        }
        guard let activeTabID = contentTabs.activeTabID,
              contentTabs.tabs[id: activeTabID] != nil
        else { return false }
        let tabIDs = Set(contentTabs.tabs.ids)
        guard Set(tabContentStates.keys).isSubset(of: tabIDs),
              Set(tabInspectorStates.keys).isSubset(of: tabIDs)
        else { return false }
        for tabID in contentTabs.tabs.ids {
            guard let cachedContent = tabContentStates[tabID] else { return false }
            if tabID == activeTabID, cachedContent != content { return false }
            if supportsInspector(tabID: tabID) {
                guard let cachedInspector = tabInspectorStates[tabID] else { return false }
                if tabID == activeTabID, cachedInspector != inspector.tabSnapshot() { return false }
            } else if tabInspectorStates[tabID] != nil {
                return false
            }
        }
        return true
    }

    var aiChatAnchorSessionKeys: Set<String> {
        Set(contentTabs.tabs.compactMap(\.anchor.aiChatSessionKey))
    }

    var transferOwnedAiChatSessionIDs: Set<AiChatSessionID> {
        var sessionIDs = Set(backgroundAiChatStates.keys)
        sessionIDs.formUnion(backgroundInspectorAiChatStates.keys)
        sessionIDs.formUnion(content.aiChat.contentTabTransferSessionIDs)
        sessionIDs.formUnion(inspector.aiChat.contentTabTransferSessionIDs)
        for state in tabContentStates.values {
            sessionIDs.formUnion(state.aiChat.contentTabTransferSessionIDs)
        }
        for state in tabInspectorStates.values {
            sessionIDs.formUnion(state.aiChat.contentTabTransferSessionIDs)
        }
        return sessionIDs
    }
}
