import Foundation
import VoyagerEntitiesAi
import VoyagerFeaturesAiChat
import VoyagerFeaturesContentPageNavigation

extension ContentTabTransfer {
    struct WindowIDs {
        let source: UUID
        let target: UUID
    }

    enum TransferSemantics: Equatable {
        case preserveDomain
        case explicitSameDomain(targetDomain: ContentTabDomain, placement: ContentTabPlacement)
        case explicitOppositeDomain(
            sourceDomain: ContentTabDomain,
            targetDomain: ContentTabDomain,
            placement: ContentTabPlacement,
        )
    }

    struct ProjectedWorkUnit: Equatable {
        let source: WorkUnit
        let item: ContentTabItem
        let pinnedRecord: ContentTabPinnedRecord?
        let runtimePreservationRecord: ContentTabPinnedRecord?

        var ownedSessionIDs: Set<AiChatSessionID> {
            source.ownedSessionIDs
        }
    }

    struct TargetPreparation {
        let state: FileManagerWindowState
        let semantics: TransferSemantics
    }

    static func validatedSemantics(
        workUnits: [WorkUnit],
        sourceDomain: ContentTabDomain?,
        targetDomain: ContentTabDomain?,
        placement: ContentTabPlacement?,
    ) -> Swift.Result<TransferSemantics, Rejection> {
        guard let targetDomain else { return .success(.preserveDomain) }
        guard let sourceDomain, let placement else {
            return .failure(.targetPlacementInvalid)
        }
        let sourceIsPinned = sourceDomain == .pinned
        guard workUnits.allSatisfy({ workUnit in
            workUnit.item.isPinned == sourceIsPinned && (workUnit.pinnedRecord != nil) == sourceIsPinned
        }) else {
            return .failure(.sourcePinParity)
        }
        if sourceDomain == targetDomain {
            return .success(.explicitSameDomain(targetDomain: targetDomain, placement: placement))
        }
        return .success(.explicitOppositeDomain(
            sourceDomain: sourceDomain,
            targetDomain: targetDomain,
            placement: placement,
        ))
    }

    static func makeProjectedWorkUnits(
        workUnits: [WorkUnit],
        semantics: TransferSemantics,
        pinnedAt: Date?,
    ) -> Swift.Result<[ProjectedWorkUnit], Rejection> {
        switch semantics {
        case .preserveDomain, .explicitSameDomain:
            .success(projectedPreservingUnits(workUnits))
        case let .explicitOppositeDomain(_, targetDomain, _):
            projectedOppositeDomainUnits(
                workUnits: workUnits,
                targetDomain: targetDomain,
                pinnedAt: pinnedAt,
            )
        }
    }

    private static func projectedPreservingUnits(_ workUnits: [WorkUnit]) -> [ProjectedWorkUnit] {
        workUnits.map { workUnit in
            let runtimePreservationRecord: ContentTabPinnedRecord? = if workUnit.item.isPinned {
                workUnit.runtimePreservationRecord ?? workUnit.pinnedRecord
            } else {
                nil
            }
            return ProjectedWorkUnit(
                source: workUnit,
                item: workUnit.item,
                pinnedRecord: workUnit.pinnedRecord,
                runtimePreservationRecord: runtimePreservationRecord,
            )
        }
    }

    private static func projectedOppositeDomainUnits(
        workUnits: [WorkUnit],
        targetDomain: ContentTabDomain,
        pinnedAt: Date?,
    ) -> Swift.Result<[ProjectedWorkUnit], Rejection> {
        let targetIsPinned = targetDomain == .pinned
        guard targetIsPinned else {
            return .success(projectedUnpinnedUnits(workUnits))
        }
        guard let resolvedPinnedAt = pinnedAt else {
            return .failure(.missingPinnedTimestamp)
        }
        let projectedUnits = try? workUnits.map { workUnit -> ProjectedWorkUnit in
            var item = workUnit.item
            item.isPinned = true
            let pinnedRecord: ContentTabPinnedRecord
            if let existing = workUnit.pinnedRecord ?? workUnit.runtimePreservationRecord {
                pinnedRecord = existing
            } else {
                let created = ContentTabPinnedRecord(
                    id: item.id.rawValue,
                    page: item.page,
                    anchor: item.anchor,
                    title: item.title,
                    iconName: item.iconName,
                    pinnedAt: resolvedPinnedAt,
                )
                guard created.isPageAnchorCompatible else { throw Rejection.sourcePinParity }
                pinnedRecord = created
            }
            return ProjectedWorkUnit(
                source: workUnit,
                item: item,
                pinnedRecord: pinnedRecord,
                runtimePreservationRecord: workUnit.runtimePreservationRecord ?? pinnedRecord,
            )
        }
        if let projectedUnits {
            return .success(projectedUnits)
        }
        return .failure(.sourcePinParity)
    }

    private static func projectedUnpinnedUnits(_ workUnits: [WorkUnit]) -> [ProjectedWorkUnit] {
        workUnits.map { workUnit in
            var item = workUnit.item
            item.isPinned = false
            return ProjectedWorkUnit(
                source: workUnit,
                item: item,
                pinnedRecord: nil,
                runtimePreservationRecord: nil,
            )
        }
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
        workUnits: [ProjectedWorkUnit],
        semantics: TransferSemantics,
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

        let prepared = removingPassiveProjections(replacementIDs, from: target)
        let normalizedSemantics: TransferSemantics
        switch validatedNormalizedSemantics(
            semantics,
            target: target,
            preparedTarget: prepared,
            replacementIDs: replacementIDs,
            orderedTabIDs: workUnits.map(\.item.id),
        ) {
        case let .success(value):
            normalizedSemantics = value
        case let .failure(reason):
            return .failure(reason)
        }
        return .success(TargetPreparation(state: prepared, semantics: normalizedSemantics))
    }

    static func hasTargetOwnerCollision(
        _ target: FileManagerWindowState,
        workUnits: [ProjectedWorkUnit],
    ) -> Bool {
        workUnits.contains { workUnit in
            let tabID = workUnit.item.id
            return target.contentTabs.tabs[id: tabID] == nil
                && (target.tabContentStates[tabID] != nil || target.tabInspectorStates[tabID] != nil)
        }
    }

    static func validatedReplacementIDs(
        target: FileManagerWindowState,
        workUnits: [ProjectedWorkUnit],
    ) -> Swift.Result<Set<ContentTabID>, Rejection> {
        var replacementIDs = Set<ContentTabID>()
        for workUnit in workUnits {
            let tabID = workUnit.item.id
            guard target.contentTabs.tabs[id: tabID] != nil else { continue }
            guard target.isPassivePinnedProjection(
                tabID: tabID,
                sourceRecord: workUnit.source.pinnedRecord,
            ) else {
                return .failure(.targetTabCollision)
            }
            replacementIDs.insert(tabID)
        }
        return .success(replacementIDs)
    }

    static func removingPassiveProjections(
        _ replacementIDs: Set<ContentTabID>,
        from target: FileManagerWindowState,
    ) -> FileManagerWindowState {
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
        return prepared
    }

    static func validatedNormalizedSemantics(
        _ semantics: TransferSemantics,
        target: FileManagerWindowState,
        preparedTarget: FileManagerWindowState,
        replacementIDs: Set<ContentTabID>,
        orderedTabIDs: [ContentTabID],
    ) -> Swift.Result<TransferSemantics, Rejection> {
        let targetDomain: ContentTabDomain
        let sourceDomain: ContentTabDomain?
        let placement: ContentTabPlacement
        switch semantics {
        case .preserveDomain:
            return .success(semantics)
        case let .explicitSameDomain(domain, value):
            (targetDomain, sourceDomain, placement) = (domain, nil, value)
        case let .explicitOppositeDomain(source, target, value):
            (targetDomain, sourceDomain, placement) = (target, source, value)
        }
        guard let placement = normalizedExplicitPlacement(
            in: target,
            replacementIDs: replacementIDs,
            targetDomain: targetDomain,
            placement: placement,
        ), hasValidExplicitPlacement(
            in: preparedTarget,
            orderedTabIDs: orderedTabIDs,
            targetDomain: targetDomain,
            placement: placement,
        ) else { return .failure(.targetPlacementInvalid) }
        guard let sourceDomain else {
            return .success(.explicitSameDomain(targetDomain: targetDomain, placement: placement))
        }
        return .success(.explicitOppositeDomain(
            sourceDomain: sourceDomain,
            targetDomain: targetDomain,
            placement: placement,
        ))
    }

    static func batchCollisionRejection(
        workUnits: [ProjectedWorkUnit],
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

    static func hasValidExplicitPlacement(
        in target: FileManagerWindowState,
        orderedTabIDs: [ContentTabID],
        targetDomain: ContentTabDomain,
        placement: ContentTabPlacement,
    ) -> Bool {
        switch placement {
        case let .before(anchorID), let .after(anchorID):
            guard !orderedTabIDs.contains(anchorID),
                  let anchor = target.contentTabs.tabs[id: anchorID],
                  ContentTabDomain.domain(isPinned: anchor.isPinned) == targetDomain,
                  (target.contentTabs.pinnedRecords[anchorID] != nil) == anchor.isPinned
            else { return false }
            return true
        case .empty:
            return !target.contentTabs.tabs.contains(where: {
                ContentTabDomain.domain(isPinned: $0.isPinned) == targetDomain
            })
        }
    }
}
