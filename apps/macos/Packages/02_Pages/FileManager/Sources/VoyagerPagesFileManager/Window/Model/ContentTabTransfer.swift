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
        case windowBusy
        case malformedOwnership
    }

    public enum Rejection: Equatable, Error {
        case sameWindow
        case sourceWindowIdentityMissing
        case targetWindowIdentityMissing
        case sourceTabMissing
        case sourceTabAmbiguous
        case sourcePinParity
        case missingPinnedTimestamp
        case ineligible(EligibilityRejection)
        case targetCapacityExceeded
        case targetMalformedOwnership
        case targetPlacementInvalid
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

    public struct LoadingTeardownScope: Equatable, Hashable {
        public let windowID: UUID?
        public let ownerID: UUID
    }

    public struct ComposerTeardownScope: Equatable, Hashable {
        public let ownerID: UUID
    }

    public struct TeardownIntent: Equatable {
        public let tabID: ContentTabID
        public let loadingScope: LoadingTeardownScope?
        public let composerScope: ComposerTeardownScope?
    }

    public struct RebindIntent: Equatable {
        public let sourceWindowID: UUID
        public let targetWindowID: UUID
        public let tabID: ContentTabID
        let sourceOutgoingOwner: OutgoingContentOwner
        let targetOutgoingOwner: OutgoingContentOwner?
        public let sourceActiveNavigationObservation: ActiveNavigationObservationRebind?
        public let targetActiveNavigationObservation: ActiveNavigationObservationRebind
        public let rebindNavigationObservation: Bool
        public let rebindUndoScope: Bool
    }

    public struct PostCommit: Equatable {
        public let source: FileManagerWindowState
        public let target: FileManagerWindowState
        public let unavailableTargetFallbackSource: FileManagerWindowState?
        public let unavailableTargetFallbackTeardownIntents: [TeardownIntent]
        let rebind: RebindIntent
        public let rebinds: [RebindIntent]
        public let teardownIntents: [TeardownIntent]
    }

    public enum Result: Equatable {
        case moved(postCommit: PostCommit)
        case closeSourceWindow(postCommit: PostCommit)
        case rejected(reason: Rejection)
    }

    public enum Preflight: Equatable {
        case success(SuccessToken)
        case rejected(Rejection)
    }

    public struct DurablePinnedBatchMutation: Equatable, Sendable {
        public let recordsToUpsert: [ContentTabPinnedRecord]
        public let recordIDsToRemove: [String]
        public let orderedTabIDs: [ContentTabID]
        public let pinnedPlacement: ContentTabPlacement?

        public init(
            recordsToUpsert: [ContentTabPinnedRecord],
            recordIDsToRemove: [String],
            orderedTabIDs: [ContentTabID],
            pinnedPlacement: ContentTabPlacement?,
        ) {
            self.recordsToUpsert = recordsToUpsert
            self.recordIDsToRemove = recordIDsToRemove
            self.orderedTabIDs = orderedTabIDs
            self.pinnedPlacement = pinnedPlacement
        }
    }

    public struct SuccessToken: Equatable {
        let sourceFingerprint: WindowSnapshotFingerprint
        let targetFingerprint: WindowSnapshotFingerprint
        let workUnits: [WorkUnit]
        let projectedSource: FileManagerWindowState
        let projectedTarget: FileManagerWindowState
        let unavailableTargetFallbackSource: FileManagerWindowState?
        let sourceWindowID: UUID
        let targetWindowID: UUID
        let primaryTabID: ContentTabID
        public let rebindIntents: [RebindIntent]
        public let durablePinnedMutation: DurablePinnedBatchMutation?
        let teardownIntents: [TeardownIntent]
        let sourceIsEmpty: Bool
        let sourceOutgoingOwner: OutgoingContentOwner
        let targetOutgoingOwner: OutgoingContentOwner?
    }

    struct OutgoingContentOwner: Equatable {
        let tabID: ContentTabID
        let loadingWindowID: UUID?
        let loadingOwnerID: UUID
        let composerOwnerID: UUID?
        let canCancelLoadingExclusively: Bool
        let canCancelComposerExclusively: Bool
    }

    struct ContentOwnerFingerprint: Equatable {
        let tabID: ContentTabID
        let item: ContentTabItem
        let pinnedRecord: ContentTabPinnedRecord?
        let runtimePreservationRecord: ContentTabPinnedRecord?
        let loadingWindowID: UUID?
        let loadingOwnerID: UUID
        let undoOwnerID: UUID
        let composerOwnerID: UUID?
        let ownedSessionIDs: Set<AiChatSessionID>
    }

    struct WindowSnapshotFingerprint: Equatable {
        let windowID: UUID
        let tabIDs: [ContentTabID]
        let activeTabID: ContentTabID?
        let previousActiveTabID: ContentTabID?
        let selectedTabIDs: Set<ContentTabID>
        let selectionAnchorID: ContentTabID?
        let owners: [ContentOwnerFingerprint]
    }

    struct WorkUnit: Equatable {
        let item: ContentTabItem
        let pinnedRecord: ContentTabPinnedRecord?
        let runtimePreservationRecord: ContentTabPinnedRecord?
        let content: FileManagerContentFeature.State
        let inspector: FileManagerInspectorFeature.State?
        let backgroundContent: [AiChatSessionID: FileManagerContentFeature.State]
        let backgroundInspector: [AiChatSessionID: FileManagerInspectorFeature.State]
        let ownedSessionIDs: Set<AiChatSessionID>
    }

    public static func transfer(
        source: FileManagerWindowState,
        target: FileManagerWindowState,
        tabID: ContentTabID,
    ) -> Result {
        transfer(
            source: source,
            target: target,
            orderedTabIDs: [tabID],
            primaryTabID: tabID,
        )
    }

    public static func transfer(
        source: FileManagerWindowState,
        target: FileManagerWindowState,
        orderedTabIDs: [ContentTabID],
        primaryTabID: ContentTabID,
        sourceDomain: ContentTabDomain? = nil,
        targetDomain: ContentTabDomain? = nil,
        placement: ContentTabPlacement? = nil,
        pinnedAt: Date? = nil,
    ) -> Result {
        switch preflight(
            source: source,
            target: target,
            orderedTabIDs: orderedTabIDs,
            primaryTabID: primaryTabID,
            sourceDomain: sourceDomain,
            targetDomain: targetDomain,
            placement: placement,
            pinnedAt: pinnedAt,
        ) {
        case let .success(token):
            apply(token)
        case let .rejected(reason):
            .rejected(reason: reason)
        }
    }

    public static func preflight(
        source: FileManagerWindowState,
        target: FileManagerWindowState,
        tabID: ContentTabID,
    ) -> Preflight {
        preflight(
            source: source,
            target: target,
            orderedTabIDs: [tabID],
            primaryTabID: tabID,
        )
    }

    public static func preflight(
        source: FileManagerWindowState,
        target: FileManagerWindowState,
        orderedTabIDs: [ContentTabID],
        primaryTabID: ContentTabID,
        sourceDomain: ContentTabDomain? = nil,
        targetDomain: ContentTabDomain? = nil,
        placement: ContentTabPlacement? = nil,
        pinnedAt: Date? = nil,
    ) -> Preflight {
        preflight(PreflightRequest(
            source: source,
            target: target,
            orderedTabIDs: orderedTabIDs,
            primaryTabID: primaryTabID,
            sourceDomain: sourceDomain,
            targetDomain: targetDomain,
            placement: placement,
            pinnedAt: pinnedAt,
        ))
    }

    public static func apply(_ token: SuccessToken) -> Result {
        let primaryRebind = token.rebindIntents.first { $0.tabID == token.primaryTabID }
            ?? token.rebindIntents[0]
        let postCommit = PostCommit(
            source: token.projectedSource,
            target: token.projectedTarget,
            unavailableTargetFallbackSource: token.unavailableTargetFallbackSource,
            unavailableTargetFallbackTeardownIntents: token.unavailableTargetFallbackSource == nil
                ? []
                : token.targetOutgoingOwner.map { makeTeardownIntents([$0]) } ?? [],
            rebind: primaryRebind,
            rebinds: token.rebindIntents,
            teardownIntents: token.teardownIntents,
        )
        return token.sourceIsEmpty
            ? .closeSourceWindow(postCommit: postCommit)
            : .moved(postCommit: postCommit)
    }
}

extension ContentTabTransfer {
    static func makeFingerprint(
        _ state: FileManagerWindowState,
        windowID: UUID,
    ) -> WindowSnapshotFingerprint {
        let owners = state.contentTabs.tabs.compactMap { item -> ContentOwnerFingerprint? in
            guard let content = contentState(tabID: item.id, in: state) else { return nil }
            let inspector = inspectorState(tabID: item.id, in: state)
            let entryOperations = content.entryViewLayout.entryOperations
            return ContentOwnerFingerprint(
                tabID: item.id,
                item: item,
                pinnedRecord: state.contentTabs.pinnedRecords[item.id],
                runtimePreservationRecord: state.pendingRuntimePreservationRecords[item.id],
                loadingWindowID: entryOperations.windowID,
                loadingOwnerID: entryOperations.loadingCancellationOwnerID,
                undoOwnerID: entryOperations.undoOwnerID,
                composerOwnerID: content.composer.cancellationOwnerID,
                ownedSessionIDs: ownedSessionIDs(item: item, content: content, inspector: inspector),
            )
        }
        return WindowSnapshotFingerprint(
            windowID: windowID,
            tabIDs: Array(state.contentTabs.tabs.ids),
            activeTabID: state.contentTabs.activeTabID,
            previousActiveTabID: state.contentTabs.previousActiveTabID,
            selectedTabIDs: state.contentTabs.selectedTabIDs,
            selectionAnchorID: state.contentTabs.selectionAnchorID,
            owners: owners,
        )
    }

    static func inspectorState(
        tabID: ContentTabID,
        in state: FileManagerWindowState,
    ) -> FileManagerInspectorFeature.State? {
        state.contentTabs.activeTabID == tabID ? state.inspector.tabSnapshot() : state.tabInspectorStates[tabID]
    }
}

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

public extension FileManagerWindowState {
    func canAcceptContentTabMove(
        tabID: ContentTabID,
        sourcePinnedRecord: ContentTabPinnedRecord?,
    ) -> Bool {
        contentTabs.tabs.count < ContentTabConstants.maxTabs
            || canReplacePassivePinnedContentTab(
                tabID: tabID,
                sourcePinnedRecord: sourcePinnedRecord,
            )
    }

    func canReplacePassivePinnedContentTab(
        tabID: ContentTabID,
        sourcePinnedRecord: ContentTabPinnedRecord?,
    ) -> Bool {
        isPassivePinnedProjection(tabID: tabID, sourceRecord: sourcePinnedRecord)
    }
}

extension FileManagerContentFeature.State {
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
        entryViewLayout.entryOperations.windowID = windowID
    }
}

extension ContentTabTransfer.EligibilityRejection {
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

extension AiChatFeature.State {
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

extension ContentTabPageAnchor {
    var aiChatSessionKey: String? {
        guard case let .aiChat(sessionID) = self else { return nil }
        return sessionID
    }

    var aiChatSessionID: AiChatSessionID? {
        guard let aiChatSessionKey, let uuid = UUID(uuidString: aiChatSessionKey) else { return nil }
        return AiChatSessionID(rawValue: uuid)
    }
}
