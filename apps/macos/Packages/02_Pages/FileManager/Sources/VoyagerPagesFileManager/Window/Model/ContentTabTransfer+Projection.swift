import Foundation
import VoyagerEntitiesAi
import VoyagerFeaturesAiChat
import VoyagerFeaturesContentPageNavigation

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
        let targetProjection = TargetProjectionContext(
            originalActiveID: context.target.contentTabs.activeTabID,
            primaryTabID: context.primaryTabID,
            windowID: context.windowIDs.target,
            semantics: context.semantics,
        )
        let target = projectTarget(
            context.preparedTarget,
            workUnits: context.projectedWorkUnits,
            projection: targetProjection,
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

    struct TargetProjectionContext {
        let originalActiveID: ContentTabID?
        let primaryTabID: ContentTabID
        let windowID: UUID
        let semantics: TransferSemantics
    }

    static func projectTarget(
        _ prepared: FileManagerWindowState,
        workUnits: [ProjectedWorkUnit],
        projection: TargetProjectionContext,
    ) -> FileManagerWindowState {
        var target = prepared
        let semantics = projection.semantics

        switch semantics {
        case .preserveDomain:
            var pinnedInsertionIndex = target.contentTabs.tabs.lastIndex(where: \.isPinned).map { $0 + 1 } ?? 0
            for workUnit in workUnits where workUnit.item.isPinned {
                target.contentTabs.tabs.insert(workUnit.item, at: pinnedInsertionIndex)
                pinnedInsertionIndex += 1
            }
            for workUnit in workUnits where !workUnit.item.isPinned {
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
            target.contentTabs.tabs.insert(contentsOf: workUnits.map(\.item), at: insertionIndex)
        }

        for workUnit in workUnits {
            let tabID = workUnit.item.id
            var movedContent = workUnit.source.content
            movedContent.applyTransferWindowContext(windowID: projection.windowID)
            target.suppressedPinnedTabIDs.remove(tabID)
            target.contentTabs.pinnedRecords[tabID] = workUnit.pinnedRecord
            target.pendingRuntimePreservationRecords[tabID] = workUnit.runtimePreservationRecord
            target.tabContentStates[tabID] = movedContent
            target.tabInspectorStates[tabID] = workUnit.source.inspector
            target.insertBackgroundOwners(workUnit.source, targetWindowID: projection.windowID)
        }

        target.contentTabs.activeTabID = projection.primaryTabID
        target.contentTabs.previousActiveTabID = projection.originalActiveID.flatMap {
            $0 != projection.primaryTabID && target.contentTabs.tabs[id: $0] != nil ? $0 : nil
        }
        target.contentTabs.selectedTabIDs = Set(workUnits.map(\.item.id))
        target.contentTabs.selectionAnchorID = projection.primaryTabID
        if let primaryContent = target.tabContentStates[projection.primaryTabID] {
            target.content = primaryContent
            target.inspector = target.tabInspectorStates[projection.primaryTabID] ?? .init()
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
