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

    public struct LoadingTeardownScope: Equatable, Hashable {
        public let windowID: UUID?
        public let ownerID: UUID
    }

    public struct ComposerTeardownScope: Equatable, Hashable {
        public let ownerID: UUID
    }

    public struct TeardownIntent: Equatable {
        let tabID: ContentTabID
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

    public struct SuccessToken: Equatable {
        let sourceFingerprint: WindowSnapshotFingerprint
        let targetFingerprint: WindowSnapshotFingerprint
        let workUnits: [WorkUnit]
        let projectedSource: FileManagerWindowState
        let projectedTarget: FileManagerWindowState
        let sourceWindowID: UUID
        let targetWindowID: UUID
        let primaryTabID: ContentTabID
        public let rebindIntents: [RebindIntent]
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
    ) -> Result {
        switch preflight(
            source: source,
            target: target,
            orderedTabIDs: orderedTabIDs,
            primaryTabID: primaryTabID,
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
    ) -> Preflight {
        let windowIDs: WindowIDs
        switch validatedWindowIDs(source: source, target: target) {
        case let .success(value):
            windowIDs = value
        case let .failure(reason):
            return .rejected(reason)
        }
        if let reason = windowBusyRejection(
            source: source,
            target: target,
            orderedTabIDs: orderedTabIDs,
            primaryTabID: primaryTabID,
        ) {
            return .rejected(reason)
        }

        let workUnits: [WorkUnit]
        switch validatedWorkUnits(
            source: source,
            orderedTabIDs: orderedTabIDs,
            primaryTabID: primaryTabID,
        ) {
        case let .success(value):
            workUnits = value
        case let .failure(reason):
            return .rejected(reason)
        }

        let targetPreparation: TargetPreparation
        switch prepareTargetForInsertion(target, workUnits: workUnits) {
        case let .success(value):
            targetPreparation = value
        case let .failure(reason):
            return .rejected(reason)
        }
        if let reason = batchCollisionRejection(workUnits: workUnits, target: targetPreparation.state) {
            return .rejected(reason)
        }

        let context = PreflightContext(
            source: source,
            target: target,
            preparedTarget: targetPreparation.state,
            workUnits: workUnits,
            windowIDs: windowIDs,
            primaryTabID: primaryTabID,
        )
        return .success(makeSuccessToken(context))
    }

    public static func apply(_ token: SuccessToken) -> Result {
        let primaryRebind = token.rebindIntents.first { $0.tabID == token.primaryTabID }
            ?? token.rebindIntents[0]
        let postCommit = PostCommit(
            source: token.projectedSource,
            target: token.projectedTarget,
            rebind: primaryRebind,
            rebinds: token.rebindIntents,
            teardownIntents: token.teardownIntents,
        )
        return token.sourceIsEmpty
            ? .closeSourceWindow(postCommit: postCommit)
            : .moved(postCommit: postCommit)
    }
}

private extension ContentTabTransfer {
    struct WindowIDs {
        let source: UUID
        let target: UUID
    }

    struct TargetPreparation {
        let state: FileManagerWindowState
    }

    static func windowBusyRejection(
        source: FileManagerWindowState,
        target: FileManagerWindowState,
        orderedTabIDs: [ContentTabID],
        primaryTabID: ContentTabID,
    ) -> Rejection? {
        if source.isContentTabMoveBusy {
            switch validatedSourceRemovalIndices(
                source: source,
                orderedTabIDs: orderedTabIDs,
                primaryTabID: primaryTabID,
            ) {
            case .success:
                break
            case let .failure(reason):
                return reason
            }
            for tabID in orderedTabIDs {
                if let reason = sourceRejection(source: source, tabID: tabID) {
                    return reason
                }
            }
            return .ineligible(.windowBusy)
        }
        guard target.isContentTabMoveDestinationBusy else { return nil }
        switch target.destinationTransferEligibility() {
        case .eligible:
            return .ineligible(.windowBusy)
        case let .rejected(reason):
            return .ineligible(EligibilityRejection(reason))
        }
    }

    static func validatedWorkUnits(
        source: FileManagerWindowState,
        orderedTabIDs: [ContentTabID],
        primaryTabID: ContentTabID,
    ) -> Swift.Result<[WorkUnit], Rejection> {
        let removalIndices: [ContentTabID: Int]
        switch validatedSourceRemovalIndices(
            source: source,
            orderedTabIDs: orderedTabIDs,
            primaryTabID: primaryTabID,
        ) {
        case let .success(value):
            removalIndices = value
        case let .failure(reason):
            return .failure(reason)
        }
        for tabID in orderedTabIDs {
            if let reason = sourceRejection(source: source, tabID: tabID) {
                return .failure(reason)
            }
        }
        return makeWorkUnits(
            source: source,
            orderedTabIDs: orderedTabIDs,
            removalIndices: removalIndices,
        )
    }

    static func validatedWindowIDs(
        source: FileManagerWindowState,
        target: FileManagerWindowState,
    ) -> Swift.Result<WindowIDs, Rejection> {
        guard let sourceWindowID = source.windowID else { return .failure(.sourceWindowIdentityMissing) }
        guard let targetWindowID = target.windowID else { return .failure(.targetWindowIdentityMissing) }
        guard sourceWindowID != targetWindowID else { return .failure(.sameWindow) }
        return .success(WindowIDs(source: sourceWindowID, target: targetWindowID))
    }

    static func validatedSourceRemovalIndices(
        source: FileManagerWindowState,
        orderedTabIDs: [ContentTabID],
        primaryTabID: ContentTabID,
    ) -> Swift.Result<[ContentTabID: Int], Rejection> {
        guard !orderedTabIDs.isEmpty, orderedTabIDs.contains(primaryTabID) else {
            return .failure(.sourceTabMissing)
        }
        guard Set(orderedTabIDs).count == orderedTabIDs.count else {
            return .failure(.sourceTabAmbiguous)
        }

        var removalIndices: [ContentTabID: Int] = [:]
        for tabID in orderedTabIDs {
            let indices = source.contentTabs.tabs.indices.filter { source.contentTabs.tabs[$0].id == tabID }
            guard !indices.isEmpty else { return .failure(.sourceTabMissing) }
            guard indices.count == 1, let index = indices.first else {
                return .failure(.sourceTabAmbiguous)
            }
            removalIndices[tabID] = index
        }
        return .success(removalIndices)
    }

    static func sourceRejection(
        source: FileManagerWindowState,
        tabID: ContentTabID,
    ) -> Rejection? {
        switch source.transferEligibility(tabID: tabID) {
        case .eligible:
            if source.pendingDirectoryReloadTabIDs.contains(tabID) {
                .ineligible(.windowBusy)
            } else {
                source.hasValidPinParity(tabID: tabID) ? nil : .sourcePinParity
            }
        case let .rejected(reason):
            .ineligible(EligibilityRejection(reason))
        }
    }

    static func makeWorkUnits(
        source: FileManagerWindowState,
        orderedTabIDs: [ContentTabID],
        removalIndices: [ContentTabID: Int],
    ) -> Swift.Result<[WorkUnit], Rejection> {
        var workUnits: [WorkUnit] = []
        workUnits.reserveCapacity(orderedTabIDs.count)
        for tabID in orderedTabIDs {
            guard let removalIndex = removalIndices[tabID] else {
                return .failure(.sourceTabMissing)
            }
            switch makeWorkUnit(source: source, tabID: tabID, removalIndex: removalIndex) {
            case let .success(workUnit):
                workUnits.append(workUnit)
            case let .failure(reason):
                return .failure(reason)
            }
        }
        return .success(workUnits)
    }

    static func makeWorkUnit(
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
            runtimePreservationRecord: source.pendingRuntimePreservationRecords[tabID],
            content: content,
            inspector: inspector,
            backgroundContent: source.backgroundAiChatStates.filter { ownedSessionIDs.contains($0.key) },
            backgroundInspector: source.backgroundInspectorAiChatStates.filter { ownedSessionIDs.contains($0.key) },
            ownedSessionIDs: ownedSessionIDs,
        ))
    }

    static func prepareTargetForInsertion(
        _ target: FileManagerWindowState,
        workUnits: [WorkUnit],
    ) -> Swift.Result<TargetPreparation, Rejection> {
        guard !hasTargetOwnerCollision(target, workUnits: workUnits) else {
            return .failure(.targetOwnerCollision)
        }
        guard target.hasCompleteTransferOwnership else {
            return .failure(.targetMalformedOwnership)
        }
        switch target.destinationTransferEligibility() {
        case .eligible:
            break
        case let .rejected(reason):
            return .failure(.ineligible(EligibilityRejection(reason)))
        }

        let replacementIDs: Set<ContentTabID>
        switch validatedReplacementIDs(target: target, workUnits: workUnits) {
        case let .success(value):
            replacementIDs = value
        case let .failure(reason):
            return .failure(reason)
        }
        let effectiveCount = target.contentTabs.tabs.count - replacementIDs.count + workUnits.count
        guard effectiveCount <= ContentTabConstants.maxTabs else {
            return .failure(.targetCapacityExceeded)
        }

        var prepared = target
        for index in prepared.contentTabs.tabs.indices.reversed() {
            let tabID = prepared.contentTabs.tabs[index].id
            guard replacementIDs.contains(tabID) else { continue }
            prepared.contentTabs.tabs.remove(at: index)
            prepared.contentTabs.pinnedRecords[tabID] = nil
            prepared.pendingRuntimePreservationRecords[tabID] = nil
            prepared.tabContentStates[tabID] = nil
            prepared.tabInspectorStates[tabID] = nil
        }
        return .success(TargetPreparation(state: prepared))
    }

    static func hasTargetOwnerCollision(
        _ target: FileManagerWindowState,
        workUnits: [WorkUnit],
    ) -> Bool {
        workUnits.contains { workUnit in
            let tabID = workUnit.item.id
            return target.contentTabs.tabs[id: tabID] == nil
                && (target.tabContentStates[tabID] != nil || target.tabInspectorStates[tabID] != nil)
        }
    }

    static func validatedReplacementIDs(
        target: FileManagerWindowState,
        workUnits: [WorkUnit],
    ) -> Swift.Result<Set<ContentTabID>, Rejection> {
        var replacementIDs = Set<ContentTabID>()
        for workUnit in workUnits {
            let tabID = workUnit.item.id
            guard target.contentTabs.tabs[id: tabID] != nil else { continue }
            guard target.isPassivePinnedProjection(
                tabID: tabID,
                sourceRecord: workUnit.pinnedRecord,
            ) else {
                return .failure(.targetTabCollision)
            }
            replacementIDs.insert(tabID)
        }
        return .success(replacementIDs)
    }

    static func batchCollisionRejection(
        workUnits: [WorkUnit],
        target: FileManagerWindowState,
    ) -> Rejection? {
        var occupiedSessionIDs = target.transferOwnedAiChatSessionIDs
        var occupiedAnchorKeys = target.aiChatAnchorSessionKeys
        var occupiedPinnedRecords = target.contentTabs.pinnedRecords

        for workUnit in workUnits {
            let tabID = workUnit.item.id
            let anchorKey = workUnit.item.anchor.aiChatSessionKey
            if !workUnit.ownedSessionIDs.isDisjoint(with: occupiedSessionIDs)
                || anchorKey.map(occupiedAnchorKeys.contains) == true
            {
                return .targetSessionCollision
            }
            if occupiedPinnedRecords[tabID] != nil {
                return .targetPinCollision
            }
            if let pinnedRecord = workUnit.pinnedRecord,
               occupiedPinnedRecords.values.contains(where: { $0.id == pinnedRecord.id })
            {
                return .targetPinCollision
            }
            occupiedSessionIDs.formUnion(workUnit.ownedSessionIDs)
            if let anchorKey { occupiedAnchorKeys.insert(anchorKey) }
            occupiedPinnedRecords[tabID] = workUnit.pinnedRecord
        }
        return nil
    }
}

private extension ContentTabTransfer {
    struct PreflightContext {
        let source: FileManagerWindowState
        let target: FileManagerWindowState
        let preparedTarget: FileManagerWindowState
        let workUnits: [WorkUnit]
        let windowIDs: WindowIDs
        let primaryTabID: ContentTabID
    }

    struct BatchProjection {
        let source: FileManagerWindowState
        let target: FileManagerWindowState
        let targetOwner: OutgoingContentOwner?
        let rebindIntents: [RebindIntent]
        let teardownIntents: [TeardownIntent]
        let primaryOwner: OutgoingContentOwner
    }

    static func makeSuccessToken(_ context: PreflightContext) -> SuccessToken {
        let projection = makeBatchProjection(context)
        return SuccessToken(
            sourceFingerprint: makeFingerprint(context.source, windowID: context.windowIDs.source),
            targetFingerprint: makeFingerprint(context.target, windowID: context.windowIDs.target),
            workUnits: context.workUnits,
            projectedSource: projection.source,
            projectedTarget: projection.target,
            sourceWindowID: context.windowIDs.source,
            targetWindowID: context.windowIDs.target,
            primaryTabID: context.primaryTabID,
            rebindIntents: projection.rebindIntents,
            teardownIntents: projection.teardownIntents,
            sourceIsEmpty: projection.source.contentTabs.tabs.isEmpty,
            sourceOutgoingOwner: projection.primaryOwner,
            targetOutgoingOwner: projection.targetOwner,
        )
    }

    static func makeBatchProjection(_ context: PreflightContext) -> BatchProjection {
        let movedTabIDs = Set(context.workUnits.map(\.item.id))
        let sourceOwners = context.workUnits.map { workUnit in
            outgoingContentOwner(
                tabID: workUnit.item.id,
                content: workUnit.content,
                in: context.source,
                excludingSiblingTabIDs: movedTabIDs,
            )
        }
        let targetOwner = targetOutgoingContentOwner(in: context.target)
        let source = projectSource(context.source, workUnits: context.workUnits, movedTabIDs: movedTabIDs)
        let target = projectTarget(
            context.preparedTarget,
            originalTargetActiveID: context.target.contentTabs.activeTabID,
            workUnits: context.workUnits,
            primaryTabID: context.primaryTabID,
            targetWindowID: context.windowIDs.target,
        )
        let rebindContext = RebindContext(
            sourceBefore: context.source,
            projectedSource: source,
            projectedTarget: target,
            sourceWindowID: context.windowIDs.source,
            targetWindowID: context.windowIDs.target,
            primaryTabID: context.primaryTabID,
        )
        var teardownOwners = sourceOwners
        if let targetOwner { teardownOwners.append(targetOwner) }
        let primaryOwner = zip(context.workUnits, sourceOwners)
            .first(where: { $0.0.item.id == context.primaryTabID })?.1 ?? sourceOwners[0]
        return BatchProjection(
            source: source,
            target: target,
            targetOwner: targetOwner,
            rebindIntents: makeRebindIntents(
                workUnits: context.workUnits,
                sourceOutgoingOwners: sourceOwners,
                targetOutgoingOwner: targetOwner,
                context: rebindContext,
            ),
            teardownIntents: makeTeardownIntents(teardownOwners),
            primaryOwner: primaryOwner,
        )
    }

    static func projectSource(
        _ original: FileManagerWindowState,
        workUnits: [WorkUnit],
        movedTabIDs: Set<ContentTabID>,
    ) -> FileManagerWindowState {
        var source = original
        let originalDisplayOrder = original.contentTabSelectionOrderedIDs
        removeSourceWorkUnits(&source, workUnits: workUnits, movedTabIDs: movedTabIDs)

        let survivorIDs = Set(source.contentTabs.tabs.ids)
        let finalActiveID = sourceActiveFallback(
            original: original,
            originalDisplayOrder: originalDisplayOrder,
            survivorIDs: survivorIDs,
        )
        source.contentTabs.activeTabID = finalActiveID
        source.contentTabs.previousActiveTabID = original.contentTabs.previousActiveTabID.flatMap {
            survivorIDs.contains($0) && $0 != finalActiveID ? $0 : nil
        }

        var survivingSelection = original.contentTabs.selectedTabIDs.intersection(survivorIDs)
        if survivingSelection.isEmpty, let finalActiveID {
            survivingSelection = [finalActiveID]
        }
        source.contentTabs.selectedTabIDs = survivingSelection
        if survivingSelection.isEmpty {
            source.contentTabs.selectionAnchorID = nil
        } else if let anchorID = original.contentTabs.selectionAnchorID,
                  survivingSelection.contains(anchorID)
        {
            source.contentTabs.selectionAnchorID = anchorID
        } else {
            source.contentTabs.selectionAnchorID = originalDisplayOrder.first(where: survivingSelection.contains)
        }

        if let finalActiveID, let content = source.tabContentStates[finalActiveID] {
            source.content = content
            source.inspector = source.tabInspectorStates[finalActiveID] ?? .init()
        }
        source.syncContentTabSidebarItems()
        return source
    }

    static func removeSourceWorkUnits(
        _ source: inout FileManagerWindowState,
        workUnits: [WorkUnit],
        movedTabIDs: Set<ContentTabID>,
    ) {
        for index in source.contentTabs.tabs.indices.reversed() {
            let tabID = source.contentTabs.tabs[index].id
            guard movedTabIDs.contains(tabID) else { continue }
            if source.contentTabs.tabs[index].isPinned {
                source.suppressedPinnedTabIDs.insert(tabID)
            }
            source.contentTabs.tabs.remove(at: index)
            source.contentTabs.pinnedRecords[tabID] = nil
            source.pendingRuntimePreservationRecords[tabID] = nil
            source.tabContentStates[tabID] = nil
            source.tabInspectorStates[tabID] = nil
        }
        let removedSessionIDs = workUnits.reduce(into: Set<AiChatSessionID>()) {
            $0.formUnion($1.ownedSessionIDs)
        }
        for sessionID in removedSessionIDs {
            source.backgroundAiChatStates[sessionID] = nil
            source.backgroundInspectorAiChatStates[sessionID] = nil
        }
    }

    static func sourceActiveFallback(
        original: FileManagerWindowState,
        originalDisplayOrder: [ContentTabID],
        survivorIDs: Set<ContentTabID>,
    ) -> ContentTabID? {
        guard !survivorIDs.isEmpty else { return nil }
        if let activeTabID = original.contentTabs.activeTabID, survivorIDs.contains(activeTabID) {
            return activeTabID
        }
        if let previousActiveTabID = original.contentTabs.previousActiveTabID,
           survivorIDs.contains(previousActiveTabID)
        {
            return previousActiveTabID
        }
        guard let activeTabID = original.contentTabs.activeTabID,
              let activeIndex = originalDisplayOrder.firstIndex(of: activeTabID)
        else {
            return originalDisplayOrder.first(where: survivorIDs.contains)
        }
        if let right = originalDisplayOrder[(activeIndex + 1)...].first(where: survivorIDs.contains) {
            return right
        }
        return originalDisplayOrder[..<activeIndex].last(where: survivorIDs.contains)
    }

    static func projectTarget(
        _ prepared: FileManagerWindowState,
        originalTargetActiveID: ContentTabID?,
        workUnits: [WorkUnit],
        primaryTabID: ContentTabID,
        targetWindowID: UUID,
    ) -> FileManagerWindowState {
        var target = prepared
        var pinnedInsertionIndex = target.contentTabs.tabs.lastIndex(where: \.isPinned).map { $0 + 1 } ?? 0
        for workUnit in workUnits where workUnit.item.isPinned {
            target.contentTabs.tabs.insert(workUnit.item, at: pinnedInsertionIndex)
            pinnedInsertionIndex += 1
        }
        for workUnit in workUnits where !workUnit.item.isPinned {
            target.contentTabs.tabs.append(workUnit.item)
        }

        for workUnit in workUnits {
            let tabID = workUnit.item.id
            var movedContent = workUnit.content
            movedContent.applyTransferWindowContext(windowID: targetWindowID)
            target.suppressedPinnedTabIDs.remove(tabID)
            target.contentTabs.pinnedRecords[tabID] = workUnit.pinnedRecord
            target.pendingRuntimePreservationRecords[tabID] = workUnit.runtimePreservationRecord
                ?? workUnit.pinnedRecord
            target.tabContentStates[tabID] = movedContent
            target.tabInspectorStates[tabID] = workUnit.inspector
            target.insertBackgroundOwners(workUnit, targetWindowID: targetWindowID)
        }

        target.contentTabs.activeTabID = primaryTabID
        target.contentTabs.previousActiveTabID = originalTargetActiveID.flatMap {
            $0 != primaryTabID && target.contentTabs.tabs[id: $0] != nil ? $0 : nil
        }
        target.contentTabs.selectedTabIDs = Set(workUnits.map(\.item.id))
        target.contentTabs.selectionAnchorID = primaryTabID
        if let primaryContent = target.tabContentStates[primaryTabID] {
            target.content = primaryContent
            target.inspector = target.tabInspectorStates[primaryTabID] ?? .init()
        }
        target.syncContentTabSidebarItems()
        return target
    }
}

private extension ContentTabTransfer {
    struct RebindContext {
        let sourceBefore: FileManagerWindowState
        let projectedSource: FileManagerWindowState
        let projectedTarget: FileManagerWindowState
        let sourceWindowID: UUID
        let targetWindowID: UUID
        let primaryTabID: ContentTabID
    }

    static func makeRebindIntents(
        workUnits: [WorkUnit],
        sourceOutgoingOwners: [OutgoingContentOwner],
        targetOutgoingOwner: OutgoingContentOwner?,
        context: RebindContext,
    ) -> [RebindIntent] {
        let movedTabIDs = Set(workUnits.map(\.item.id))
        let sourceObservation = context.sourceBefore.contentTabs.activeTabID.flatMap {
            movedTabIDs.contains($0)
                ? activeNavigationObservation(
                    in: context.projectedSource,
                    windowID: context.sourceWindowID,
                )
                : nil
        }
        return zip(workUnits, sourceOutgoingOwners).map { workUnit, sourceOutgoingOwner in
            let tabID = workUnit.item.id
            let isPrimary = tabID == context.primaryTabID
            let navigationRoute = context.projectedTarget.tabContentStates[tabID]?.navigation.navigationState
                ?? workUnit.content.navigation.navigationState
            return RebindIntent(
                sourceWindowID: context.sourceWindowID,
                targetWindowID: context.targetWindowID,
                tabID: tabID,
                sourceOutgoingOwner: sourceOutgoingOwner,
                targetOutgoingOwner: isPrimary ? targetOutgoingOwner : nil,
                sourceActiveNavigationObservation: isPrimary ? sourceObservation : nil,
                targetActiveNavigationObservation: ActiveNavigationObservationRebind(
                    windowID: context.targetWindowID,
                    tabID: tabID,
                    navigationRoute: navigationRoute,
                ),
                rebindNavigationObservation: isPrimary,
                rebindUndoScope: true,
            )
        }
    }

    static func contentState(
        tabID: ContentTabID,
        in state: FileManagerWindowState,
    ) -> FileManagerContentFeature.State? {
        state.contentTabs.activeTabID == tabID ? state.content : state.tabContentStates[tabID]
    }

    static func ownedSessionIDs(
        item: ContentTabItem,
        content: FileManagerContentFeature.State,
        inspector: FileManagerInspectorFeature.State?,
    ) -> Set<AiChatSessionID> {
        var sessionIDs = content.aiChat.contentTabTransferSessionIDs
        if let inspector { sessionIDs.formUnion(inspector.aiChat.contentTabTransferSessionIDs) }
        if let anchorSessionID = item.anchor.aiChatSessionID { sessionIDs.insert(anchorSessionID) }
        return sessionIDs
    }

    static func targetOutgoingContentOwner(
        in target: FileManagerWindowState,
    ) -> OutgoingContentOwner? {
        guard let tabID = target.contentTabs.activeTabID,
              target.contentTabs.tabs[id: tabID] != nil
        else { return nil }
        return outgoingContentOwner(
            tabID: tabID,
            content: target.content,
            in: target,
            excludingSiblingTabIDs: [],
        )
    }

    static func outgoingContentOwner(
        tabID: ContentTabID,
        content: FileManagerContentFeature.State,
        in window: FileManagerWindowState,
        excludingSiblingTabIDs: Set<ContentTabID>,
    ) -> OutgoingContentOwner {
        let entryOperations = content.entryViewLayout.entryOperations
        let siblingContents: [FileManagerContentFeature.State] = window.contentTabs.tabs.ids
            .compactMap { siblingTabID in
                guard siblingTabID != tabID, !excludingSiblingTabIDs.contains(siblingTabID) else {
                    return nil
                }
                return contentState(tabID: siblingTabID, in: window)
            }
        let hasSharedLoadingOwner = siblingContents.contains { siblingContent in
            let siblingEntryOperations = siblingContent.entryViewLayout.entryOperations
            return siblingEntryOperations.windowID == entryOperations.windowID
                && siblingEntryOperations.loadingCancellationOwnerID == entryOperations.loadingCancellationOwnerID
        }
        let hasSharedComposerOwner = siblingContents.contains {
            $0.composer.cancellationOwnerID == content.composer.cancellationOwnerID
        }
        return OutgoingContentOwner(
            tabID: tabID,
            loadingWindowID: entryOperations.windowID,
            loadingOwnerID: entryOperations.loadingCancellationOwnerID,
            composerOwnerID: content.composer.cancellationOwnerID,
            canCancelLoadingExclusively: !hasSharedLoadingOwner,
            canCancelComposerExclusively: !hasSharedComposerOwner,
        )
    }

    static func activeNavigationObservation(
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

    static func makeTeardownIntents(_ owners: [OutgoingContentOwner]) -> [TeardownIntent] {
        var seenLoadingScopes = Set<LoadingTeardownScope>()
        var seenComposerScopes = Set<ComposerTeardownScope>()
        var intents: [TeardownIntent] = []

        for owner in owners {
            let loadingScope = LoadingTeardownScope(
                windowID: owner.loadingWindowID,
                ownerID: owner.loadingOwnerID,
            )
            let composerScope = owner.composerOwnerID.map { ComposerTeardownScope(ownerID: $0) }
            let uniqueLoadingScope = owner.canCancelLoadingExclusively
                && seenLoadingScopes.insert(loadingScope).inserted ? loadingScope : nil
            let uniqueComposerScope: ComposerTeardownScope? = if owner.canCancelComposerExclusively,
                                                                 let composerScope,
                                                                 seenComposerScopes.insert(composerScope).inserted
            {
                composerScope
            } else {
                nil
            }
            guard uniqueLoadingScope != nil || uniqueComposerScope != nil else { continue }
            intents.append(TeardownIntent(
                tabID: owner.tabID,
                loadingScope: uniqueLoadingScope,
                composerScope: uniqueComposerScope,
            ))
        }
        return intents
    }
}

private extension ContentTabTransfer {
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
