import Foundation
import VoyagerEntitiesAi
import VoyagerFeaturesAiChat
import VoyagerFeaturesContentPageNavigation

public enum ContentTabTransfer {
    public enum EligibilityRejection: Equatable, Sendable {
        case pendingContentTabClose
        case pendingPinnedRecordPersistence
        case pendingCollectionOperation
        case pendingAiChatOperation
        case malformedOwnership
    }

    public enum Rejection: Equatable, Error {
        case sameWindow
        case sourceWindowIdentityMissing
        case targetWindowIdentityMissing
        case sourceTabMissing
        case sourceTabAmbiguous
        case sourcePinParity
        case ineligible(EligibilityRejection)
        case targetCapacityExceeded
        case targetMalformedOwnership
        case targetTabCollision
        case targetOwnerCollision
        case targetSessionCollision
        case targetPinCollision
    }

    public struct ActiveNavigationObservationRebind: Equatable {
        public let windowID: UUID
        public let tabID: ContentTabID
        public let navigationRoute: ContentPageNavigationRoute
    }

    public struct RebindIntent: Equatable {
        public let sourceWindowID: UUID
        public let targetWindowID: UUID
        public let tabID: ContentTabID
        public let sourceLoadingOwnerID: UUID
        public let sourceComposerOwnerID: UUID?
        public let sourceActiveNavigationObservation: ActiveNavigationObservationRebind?
        public let targetActiveNavigationObservation: ActiveNavigationObservationRebind
        public let rebindNavigationObservation: Bool
        public let rebindUndoScope: Bool
    }

    public struct PostCommit: Equatable {
        public let source: FileManagerWindowState
        public let target: FileManagerWindowState
        public let rebind: RebindIntent
    }

    public enum Result: Equatable {
        case moved(postCommit: PostCommit)
        case closeSourceWindow(postCommit: PostCommit)
        case rejected(reason: Rejection)
    }

    enum Preflight: Equatable {
        case success(SuccessToken)
        case rejected(Rejection)
    }

    struct SuccessToken: Equatable {
        let source: FileManagerWindowState
        let target: FileManagerWindowState
        let payload: WorkUnit
        let sourceWindowID: UUID
        let targetWindowID: UUID
        let sourceRemovalIndex: Int
    }

    struct WorkUnit: Equatable {
        let item: ContentTabItem
        let pinnedRecord: ContentTabPinnedRecord?
        let content: FileManagerContentFeature.State
        let inspector: FileManagerInspectorFeature.State?
        let backgroundContent: [AiChatSessionID: FileManagerContentFeature.State]
        let backgroundInspector: [AiChatSessionID: FileManagerInspectorFeature.State]
        let ownedSessionIDs: Set<AiChatSessionID>
    }

    private struct WindowIDs {
        let source: UUID
        let target: UUID
    }

    public static func transfer(
        source: FileManagerWindowState,
        target: FileManagerWindowState,
        tabID: ContentTabID,
    ) -> Result {
        switch preflight(source: source, target: target, tabID: tabID) {
        case let .success(token):
            apply(token)
        case let .rejected(reason):
            .rejected(reason: reason)
        }
    }

    static func preflight(
        source: FileManagerWindowState,
        target: FileManagerWindowState,
        tabID: ContentTabID,
    ) -> Preflight {
        let windowIDs: WindowIDs
        switch validatedWindowIDs(source: source, target: target) {
        case let .success(value):
            windowIDs = value
        case let .failure(reason):
            return .rejected(reason)
        }

        let removalIndex: Int
        switch validatedSourceRemovalIndex(source: source, tabID: tabID) {
        case let .success(value):
            removalIndex = value
        case let .failure(reason):
            return .rejected(reason)
        }
        if let reason = sourceRejection(source: source, tabID: tabID) {
            return .rejected(reason)
        }

        let payload: WorkUnit
        switch makeWorkUnit(source: source, tabID: tabID, removalIndex: removalIndex) {
        case let .success(value):
            payload = value
        case let .failure(reason):
            return .rejected(reason)
        }
        let preparedTarget: FileManagerWindowState
        switch prepareTargetForInsertion(target, payload: payload) {
        case let .success(value):
            preparedTarget = value
        case let .failure(reason):
            return .rejected(reason)
        }
        if let reason = payloadCollisionRejection(payload: payload, target: preparedTarget) {
            return .rejected(reason)
        }
        return .success(SuccessToken(
            source: source,
            target: preparedTarget,
            payload: payload,
            sourceWindowID: windowIDs.source,
            targetWindowID: windowIDs.target,
            sourceRemovalIndex: removalIndex,
        ))
    }

    static func apply(_ token: SuccessToken) -> Result {
        let sourceWasLastTab = token.source.contentTabs.tabs.count == 1
        var source = applyingSourceRemoval(token)
        var target = applyingTargetInsertion(token)
        source.syncContentTabSidebarItems()
        target.syncContentTabSidebarItems()
        let postCommit = PostCommit(
            source: source,
            target: target,
            rebind: makeRebindIntent(token, source: source, target: target),
        )
        return sourceWasLastTab
            ? .closeSourceWindow(postCommit: postCommit)
            : .moved(postCommit: postCommit)
    }

    private static func validatedWindowIDs(
        source: FileManagerWindowState,
        target: FileManagerWindowState,
    ) -> Swift.Result<WindowIDs, Rejection> {
        guard let sourceWindowID = source.windowID else { return .failure(.sourceWindowIdentityMissing) }
        guard let targetWindowID = target.windowID else { return .failure(.targetWindowIdentityMissing) }
        guard sourceWindowID != targetWindowID else { return .failure(.sameWindow) }
        return .success(WindowIDs(source: sourceWindowID, target: targetWindowID))
    }

    private static func validatedSourceRemovalIndex(
        source: FileManagerWindowState,
        tabID: ContentTabID,
    ) -> Swift.Result<Int, Rejection> {
        let indices = source.contentTabs.tabs.indices.filter { source.contentTabs.tabs[$0].id == tabID }
        guard !indices.isEmpty else { return .failure(.sourceTabMissing) }
        guard indices.count == 1, let index = indices.first else { return .failure(.sourceTabAmbiguous) }
        return .success(index)
    }

    private static func sourceRejection(
        source: FileManagerWindowState,
        tabID: ContentTabID,
    ) -> Rejection? {
        switch source.transferEligibility(tabID: tabID) {
        case .eligible:
            source.hasValidPinParity(tabID: tabID) ? nil : .sourcePinParity
        case let .rejected(reason):
            .ineligible(EligibilityRejection(reason))
        }
    }

    private static func prepareTargetForInsertion(
        _ target: FileManagerWindowState,
        payload: WorkUnit,
    ) -> Swift.Result<FileManagerWindowState, Rejection> {
        let tabID = payload.item.id
        if target.contentTabs.tabs[id: tabID] == nil,
           target.tabContentStates[tabID] != nil || target.tabInspectorStates[tabID] != nil
        {
            return .failure(.targetOwnerCollision)
        }
        guard target.hasCompleteTransferOwnership else { return .failure(.targetMalformedOwnership) }
        switch target.destinationTransferEligibility() {
        case .eligible:
            break
        case let .rejected(reason):
            return .failure(.ineligible(EligibilityRejection(reason)))
        }

        if target.contentTabs.tabs[id: tabID] != nil {
            guard target.isPassivePinnedProjection(tabID: tabID, sourceRecord: payload.pinnedRecord) else {
                return .failure(.targetTabCollision)
            }
            var prepared = target
            guard let removalIndex = prepared.contentTabs.tabs.index(id: tabID) else {
                return .failure(.targetTabCollision)
            }
            let wasActive = prepared.contentTabs.activeTabID == tabID
            prepared.contentTabs.tabs.remove(at: removalIndex)
            prepared.contentTabs.pinnedRecords[tabID] = nil
            prepared.tabContentStates[tabID] = nil
            prepared.tabInspectorStates[tabID] = nil
            prepared.normalizeSelectionAfterRemoving(
                tabID: tabID,
                removalIndex: removalIndex,
                wasActive: wasActive,
            )
            return .success(prepared)
        }

        if target.contentTabs.tabs.count >= ContentTabConstants.maxTabs {
            return .failure(.targetCapacityExceeded)
        }
        if target.tabContentStates[tabID] != nil || target.tabInspectorStates[tabID] != nil {
            return .failure(.targetOwnerCollision)
        }
        return .success(target)
    }

    private static func makeWorkUnit(
        source: FileManagerWindowState,
        tabID: ContentTabID,
        removalIndex: Int,
    ) -> Swift.Result<WorkUnit, Rejection> {
        let item = source.contentTabs.tabs[removalIndex]
        let content: FileManagerContentFeature.State
        if source.contentTabs.activeTabID == tabID {
            content = source.content
        } else if let cachedContent = source.tabContentStates[tabID] {
            content = cachedContent
        } else {
            return .failure(.ineligible(.malformedOwnership))
        }

        let inspector: FileManagerInspectorFeature.State?
        if source.supportsInspector(tabID: tabID) {
            inspector = source.contentTabs.activeTabID == tabID
                ? source.inspector.tabSnapshot()
                : source.tabInspectorStates[tabID]
            guard inspector != nil else { return .failure(.ineligible(.malformedOwnership)) }
        } else {
            inspector = nil
        }
        let ownedSessionIDs = ownedSessionIDs(item: item, content: content, inspector: inspector)
        return .success(WorkUnit(
            item: item,
            pinnedRecord: source.contentTabs.pinnedRecords[tabID],
            content: content,
            inspector: inspector,
            backgroundContent: source.backgroundAiChatStates.filter { ownedSessionIDs.contains($0.key) },
            backgroundInspector: source.backgroundInspectorAiChatStates.filter { ownedSessionIDs.contains($0.key) },
            ownedSessionIDs: ownedSessionIDs,
        ))
    }

    private static func ownedSessionIDs(
        item: ContentTabItem,
        content: FileManagerContentFeature.State,
        inspector: FileManagerInspectorFeature.State?,
    ) -> Set<AiChatSessionID> {
        var sessionIDs = content.aiChat.contentTabTransferSessionIDs
        if let inspector { sessionIDs.formUnion(inspector.aiChat.contentTabTransferSessionIDs) }
        if let anchorSessionID = item.anchor.aiChatSessionID { sessionIDs.insert(anchorSessionID) }
        return sessionIDs
    }

    private static func payloadCollisionRejection(
        payload: WorkUnit,
        target: FileManagerWindowState,
    ) -> Rejection? {
        let hasAnchorCollision = payload.item.anchor.aiChatSessionKey
            .map(target.aiChatAnchorSessionKeys.contains) ?? false
        if !payload.ownedSessionIDs.isDisjoint(with: target.transferOwnedAiChatSessionIDs) || hasAnchorCollision {
            return .targetSessionCollision
        }
        return target.hasNoPinCollision(tabID: payload.item.id, pinnedRecord: payload.pinnedRecord)
            ? nil
            : .targetPinCollision
    }

    private static func applyingSourceRemoval(_ token: SuccessToken) -> FileManagerWindowState {
        var source = token.source
        let tabID = token.payload.item.id
        let sourceWasActive = source.contentTabs.activeTabID == tabID
        source.contentTabs.tabs.remove(at: token.sourceRemovalIndex)
        if token.payload.item.isPinned {
            source.suppressedPinnedTabIDs.insert(tabID)
        }
        source.contentTabs.pinnedRecords[tabID] = nil
        source.tabContentStates[tabID] = nil
        source.tabInspectorStates[tabID] = nil
        for sessionID in token.payload.ownedSessionIDs {
            source.backgroundAiChatStates[sessionID] = nil
            source.backgroundInspectorAiChatStates[sessionID] = nil
        }
        source.normalizeSelectionAfterRemoving(
            tabID: tabID,
            removalIndex: token.sourceRemovalIndex,
            wasActive: sourceWasActive,
        )
        return source
    }

    private static func applyingTargetInsertion(_ token: SuccessToken) -> FileManagerWindowState {
        var target = token.target
        let tabID = token.payload.item.id
        var movedContent = token.payload.content
        movedContent.applyTransferWindowContext(windowID: token.targetWindowID)
        let previousTargetActiveID = target.contentTabs.activeTabID.flatMap {
            target.contentTabs.tabs[id: $0] == nil ? nil : $0
        }
        target.suppressedPinnedTabIDs.remove(tabID)
        target.contentTabs.tabs.append(token.payload.item)
        target.contentTabs.activeTabID = tabID
        target.contentTabs.previousActiveTabID = previousTargetActiveID
        target.contentTabs.pinnedRecords[tabID] = token.payload.pinnedRecord
        target.tabContentStates[tabID] = movedContent
        target.tabInspectorStates[tabID] = token.payload.inspector
        target.content = movedContent
        target.inspector = token.payload.inspector ?? .init()
        target.insertBackgroundOwners(token.payload, targetWindowID: token.targetWindowID)
        return target
    }

    private static func makeRebindIntent(
        _ token: SuccessToken,
        source: FileManagerWindowState,
        target: FileManagerWindowState,
    ) -> RebindIntent {
        RebindIntent(
            sourceWindowID: token.sourceWindowID,
            targetWindowID: token.targetWindowID,
            tabID: token.payload.item.id,
            sourceLoadingOwnerID: token.payload.content.entryViewLayout.entryOperations.loadingCancellationOwnerID,
            sourceComposerOwnerID: token.payload.content.composer.cancellationOwnerID,
            sourceActiveNavigationObservation: activeNavigationObservation(
                in: source,
                windowID: token.sourceWindowID,
            ),
            targetActiveNavigationObservation: ActiveNavigationObservationRebind(
                windowID: token.targetWindowID,
                tabID: token.payload.item.id,
                navigationRoute: target.content.navigation.navigationState,
            ),
            rebindNavigationObservation: true,
            rebindUndoScope: true,
        )
    }

    private static func activeNavigationObservation(
        in state: FileManagerWindowState,
        windowID: UUID,
    ) -> ActiveNavigationObservationRebind? {
        guard let tabID = state.contentTabs.activeTabID,
              state.contentTabs.tabs[id: tabID] != nil
        else { return nil }
        return ActiveNavigationObservationRebind(
            windowID: windowID,
            tabID: tabID,
            navigationRoute: state.content.navigation.navigationState,
        )
    }
}

private extension FileManagerWindowState {
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

    func hasNoPinCollision(
        tabID: ContentTabID,
        pinnedRecord: ContentTabPinnedRecord?,
    ) -> Bool {
        guard contentTabs.pinnedRecords[tabID] == nil else { return false }
        guard let pinnedRecord else { return true }
        return !contentTabs.pinnedRecords.values.contains { $0.id == pinnedRecord.id }
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

    mutating func normalizeSelectionAfterRemoving(
        tabID: ContentTabID,
        removalIndex: Int,
        wasActive: Bool,
    ) {
        if contentTabs.tabs.isEmpty {
            contentTabs.activeTabID = nil
            contentTabs.previousActiveTabID = nil
            return
        }

        if wasActive {
            let previous = contentTabs.previousActiveTabID.flatMap {
                $0 != tabID && contentTabs.tabs[id: $0] != nil ? $0 : nil
            }
            let fallback: ContentTabID? = if let previous {
                previous
            } else if contentTabs.tabs.indices.contains(removalIndex) {
                contentTabs.tabs[removalIndex].id
            } else if contentTabs.tabs.indices.contains(removalIndex - 1) {
                contentTabs.tabs[removalIndex - 1].id
            } else {
                nil
            }
            contentTabs.activeTabID = fallback
            if let fallback, let contentState = tabContentStates[fallback] {
                content = contentState
                inspector = tabInspectorStates[fallback] ?? .init()
            }
        }
        contentTabs.previousActiveTabID = contentTabs.previousActiveTabID.flatMap {
            $0 != tabID && $0 != contentTabs.activeTabID && contentTabs.tabs[id: $0] != nil ? $0 : nil
        }
    }
}

public extension FileManagerWindowState {
    func canAcceptContentTabMove(
        tabID: ContentTabID,
        sourcePinnedRecord: ContentTabPinnedRecord?,
    ) -> Bool {
        contentTabs.tabs.count < ContentTabConstants.maxTabs
            || isPassivePinnedProjection(tabID: tabID, sourceRecord: sourcePinnedRecord)
    }
}

private extension FileManagerContentFeature.State {
    func isPassiveProjection(matching baseline: Self) -> Bool {
        navigation == baseline.navigation
            && entryViewLayout == baseline.entryViewLayout
            && composer == baseline.composer
            && collection == baseline.collection
            && aiChat.isPassiveContentTabProjection(matching: baseline.aiChat)
            && pendingSelectEntryID == baseline.pendingSelectEntryID
            && homeFavoriteItems == baseline.homeFavoriteItems
            && homeLocationItems == baseline.homeLocationItems
            && homeDirectoryItemCounts == baseline.homeDirectoryItemCounts
            && homeChatHistoryItems == baseline.homeChatHistoryItems
            && homeChatHistoryLoadFailed == baseline.homeChatHistoryLoadFailed
            && resetComposerOnNextDirectoryNavigation == baseline.resetComposerOnNextDirectoryNavigation
            && suppressAutomaticRefreshFeedback == baseline.suppressAutomaticRefreshFeedback
    }

    mutating func applyTransferWindowContext(windowID: UUID) {
        applyWindowContext(windowID: windowID)
        entryViewLayout.entryOperations.loadingCancellationOwnerID = windowID
    }
}

private extension ContentTabTransfer.EligibilityRejection {
    init(_ rejection: ContentTabTransferEligibilityRejection) {
        self = switch rejection {
        case .pendingContentTabClose:
            .pendingContentTabClose
        case .pendingPinnedRecordPersistence:
            .pendingPinnedRecordPersistence
        case .pendingCollectionOperation:
            .pendingCollectionOperation
        case .pendingAiChatOperation:
            .pendingAiChatOperation
        case .malformedOwnership:
            .malformedOwnership
        }
    }
}

private extension AiChatFeature.State {
    var contentTabTransferSessionIDs: Set<AiChatSessionID> {
        var sessionIDs = Set<AiChatSessionID>()
        if let sessionID { sessionIDs.insert(sessionID) }
        if let restoreSessionID { sessionIDs.insert(restoreSessionID) }
        if let pendingRequestStart { sessionIDs.insert(pendingRequestStart.sessionID) }
        sessionIDs.formUnion(backgroundPendingRequestStarts.values.map(\.sessionID))
        if let sessionID = executionPhase.lock?.context.sessionID { sessionIDs.insert(sessionID) }
        sessionIDs.formUnion(backgroundExecutionPhases.values.compactMap { $0.lock?.context.sessionID })
        return sessionIDs
    }
}

private extension ContentTabPageAnchor {
    var aiChatSessionKey: String? {
        guard case let .aiChat(sessionID) = self else { return nil }
        return sessionID
    }

    var aiChatSessionID: AiChatSessionID? {
        guard let aiChatSessionKey, let uuid = UUID(uuidString: aiChatSessionKey) else { return nil }
        return AiChatSessionID(rawValue: uuid)
    }
}
