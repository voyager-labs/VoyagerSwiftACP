import Foundation
import VoyagerEntitiesAi

extension ContentTabTransfer {
    struct PreflightContext {
        let source: FileManagerWindowState
        let target: FileManagerWindowState
        let preparedTarget: FileManagerWindowState
        let workUnits: [WorkUnit]
        let projectedWorkUnits: [ProjectedWorkUnit]
        let semantics: TransferSemantics
        let pinnedAt: Date?
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
        let durablePinnedMutation = durablePinnedMutation(
            workUnits: context.workUnits,
            projectedWorkUnits: context.projectedWorkUnits,
            target: context.target,
            semantics: context.semantics,
        )
        return SuccessToken(
            sourceFingerprint: makeFingerprint(context.source, windowID: context.windowIDs.source),
            targetFingerprint: makeFingerprint(context.target, windowID: context.windowIDs.target),
            workUnits: context.workUnits,
            projectedSource: projection.source,
            projectedTarget: projection.target,
            unavailableTargetFallbackSource: unavailableTargetFallbackSource(
                source: context.source,
                projectedItems: context.projectedWorkUnits.map {
                    UnavailableTargetFallbackItem(
                        item: $0.item,
                        pinnedRecord: $0.pinnedRecord,
                        runtimePreservationRecord: $0.runtimePreservationRecord,
                    )
                },
                shouldRetain: durablePinnedMutation != nil,
            ),
            sourceWindowID: context.windowIDs.source,
            targetWindowID: context.windowIDs.target,
            primaryTabID: context.primaryTabID,
            rebindIntents: projection.rebindIntents,
            durablePinnedMutation: durablePinnedMutation,
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
        let target = projectTarget(TargetProjectionContext(
            prepared: context.preparedTarget,
            originalActiveID: context.target.contentTabs.activeTabID,
            workUnits: context.projectedWorkUnits,
            primaryTabID: context.primaryTabID,
            windowID: context.windowIDs.target,
            semantics: context.semantics,
        ))
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

    static func projectTarget(_ context: TargetProjectionContext) -> FileManagerWindowState {
        var target = context.prepared

        switch context.semantics {
        case .preserveDomain:
            var pinnedInsertionIndex = target.contentTabs.tabs.lastIndex(where: \.isPinned).map { $0 + 1 } ?? 0
            for workUnit in context.workUnits where workUnit.item.isPinned {
                target.contentTabs.tabs.insert(workUnit.item, at: pinnedInsertionIndex)
                pinnedInsertionIndex += 1
            }
            for workUnit in context.workUnits where !workUnit.item.isPinned {
                target.contentTabs.tabs.append(workUnit.item)
            }
        case let .explicitSameDomain(targetDomain, placement),
             let .explicitOppositeDomain(_, targetDomain, placement):
            guard let insertionIndex = explicitInsertionIndex(
                in: target,
                targetDomain: targetDomain,
                placement: placement,
            ) else {
                return target
            }
            target.contentTabs.tabs.insert(contentsOf: context.workUnits.map(\.item), at: insertionIndex)
        }

        for workUnit in context.workUnits {
            let tabID = workUnit.item.id
            var movedContent = workUnit.source.content
            movedContent.applyTransferWindowContext(windowID: context.windowID)
            target.suppressedPinnedTabIDs.remove(tabID)
            target.contentTabs.pinnedRecords[tabID] = workUnit.pinnedRecord
            target.pendingRuntimePreservationRecords[tabID] = workUnit.runtimePreservationRecord
            target.tabContentStates[tabID] = movedContent
            target.tabInspectorStates[tabID] = workUnit.source.inspector
            target.insertBackgroundOwners(workUnit.source, targetWindowID: context.windowID)
        }

        target.contentTabs.activeTabID = context.primaryTabID
        target.contentTabs.previousActiveTabID = context.originalActiveID.flatMap {
            $0 != context.primaryTabID && target.contentTabs.tabs[id: $0] != nil ? $0 : nil
        }
        target.contentTabs.selectedTabIDs = Set(context.workUnits.map(\.item.id))
        target.contentTabs.selectionAnchorID = context.primaryTabID
        if let primaryContent = target.tabContentStates[context.primaryTabID] {
            target.content = primaryContent
            target.inspector = target.tabInspectorStates[context.primaryTabID] ?? .init()
        }
        target.syncContentTabSidebarItems()
        return target
    }

    static func durablePinnedMutation(
        workUnits: [WorkUnit],
        projectedWorkUnits: [ProjectedWorkUnit],
        target: FileManagerWindowState,
        semantics: TransferSemantics,
    ) -> DurablePinnedBatchMutation? {
        let orderedTabIDs = projectedWorkUnits.map(\.item.id)
        switch semantics {
        case .preserveDomain:
            return nil
        case let .explicitSameDomain(targetDomain, placement):
            guard targetDomain == .pinned else { return nil }
            return DurablePinnedBatchMutation(
                recordsToUpsert: [],
                recordIDsToRemove: [],
                orderedTabIDs: orderedTabIDs,
                pinnedPlacement: durablePinnedPlacement(in: target, movingTabIDs: orderedTabIDs, placement: placement),
            )
        case let .explicitOppositeDomain(_, targetDomain, placement):
            if targetDomain == .pinned {
                return DurablePinnedBatchMutation(
                    recordsToUpsert: projectedWorkUnits.compactMap(\.pinnedRecord),
                    recordIDsToRemove: [],
                    orderedTabIDs: orderedTabIDs,
                    pinnedPlacement: durablePinnedPlacement(
                        in: target,
                        movingTabIDs: orderedTabIDs,
                        placement: placement,
                    ),
                )
            }
            return DurablePinnedBatchMutation(
                recordsToUpsert: [],
                recordIDsToRemove: workUnits.map(\.item.id.rawValue),
                orderedTabIDs: orderedTabIDs,
                pinnedPlacement: nil,
            )
        }
    }
}

extension ContentTabTransfer {
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
        var seenComposerOwnerIDs = Set<UUID>()
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
                                                                 seenComposerOwnerIDs.insert(composerScope.ownerID)
                                                                 .inserted
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
