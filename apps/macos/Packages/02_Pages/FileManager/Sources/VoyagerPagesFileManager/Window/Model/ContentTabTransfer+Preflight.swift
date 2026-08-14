import Foundation
import VoyagerEntitiesAi

extension ContentTabTransfer {
    struct PreflightRequest {
        let source: FileManagerWindowState
        let target: FileManagerWindowState
        let orderedTabIDs: [ContentTabID]
        let primaryTabID: ContentTabID
        let sourceDomain: ContentTabDomain?
        let targetDomain: ContentTabDomain?
        let placement: ContentTabPlacement?
        let pinnedAt: Date?
    }

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

    struct TargetProjectionContext {
        let prepared: FileManagerWindowState
        let originalActiveID: ContentTabID?
        let workUnits: [ProjectedWorkUnit]
        let primaryTabID: ContentTabID
        let windowID: UUID
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
            return .success(workUnits.map {
                let runtimePreservationRecord: ContentTabPinnedRecord? = if $0.item.isPinned {
                    $0.runtimePreservationRecord ?? $0.pinnedRecord
                } else {
                    nil
                }
                return ProjectedWorkUnit(
                    source: $0,
                    item: $0.item,
                    pinnedRecord: $0.pinnedRecord,
                    runtimePreservationRecord: runtimePreservationRecord,
                )
            })
        case let .explicitOppositeDomain(_, targetDomain, _):
            let targetIsPinned = targetDomain == .pinned
            if targetIsPinned, pinnedAt == nil {
                return .failure(.missingPinnedTimestamp)
            }
            return makeOppositeDomainWorkUnits(
                workUnits: workUnits,
                targetIsPinned: targetIsPinned,
                pinnedAt: pinnedAt,
            )
        }
    }

    static func makeOppositeDomainWorkUnits(
        workUnits: [WorkUnit],
        targetIsPinned: Bool,
        pinnedAt: Date?,
    ) -> Swift.Result<[ProjectedWorkUnit], Rejection> {
        do {
            return try .success(workUnits.map { workUnit in
                try makeOppositeDomainWorkUnit(
                    workUnit: workUnit,
                    targetIsPinned: targetIsPinned,
                    pinnedAt: pinnedAt,
                )
            })
        } catch let rejection as Rejection {
            return .failure(rejection)
        } catch {
            return .failure(.sourcePinParity)
        }
    }

    static func makeOppositeDomainWorkUnit(
        workUnit: WorkUnit,
        targetIsPinned: Bool,
        pinnedAt: Date?,
    ) throws -> ProjectedWorkUnit {
        var item = workUnit.item
        item.isPinned = targetIsPinned
        let pinnedRecord: ContentTabPinnedRecord?
        if targetIsPinned {
            if let existing = workUnit.pinnedRecord ?? workUnit.runtimePreservationRecord {
                pinnedRecord = existing
            } else {
                guard let pinnedAt else { throw Rejection.missingPinnedTimestamp }
                let created = ContentTabPinnedRecord(
                    id: item.id.rawValue,
                    page: item.page,
                    anchor: item.anchor,
                    title: item.title,
                    iconName: item.iconName,
                    pinnedAt: pinnedAt,
                )
                guard created.isPageAnchorCompatible else { throw Rejection.sourcePinParity }
                pinnedRecord = created
            }
        } else {
            pinnedRecord = nil
        }
        return ProjectedWorkUnit(
            source: workUnit,
            item: item,
            pinnedRecord: pinnedRecord,
            runtimePreservationRecord: targetIsPinned
                ? workUnit.runtimePreservationRecord ?? pinnedRecord
                : nil,
        )
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

    static func preflight(_ request: PreflightRequest) -> Preflight {
        let windowIDs: WindowIDs
        switch validatedWindowIDs(source: request.source, target: request.target) {
        case let .success(value):
            windowIDs = value
        case let .failure(reason):
            return .rejected(reason)
        }
        if let reason = windowBusyRejection(
            source: request.source,
            target: request.target,
            orderedTabIDs: request.orderedTabIDs,
            primaryTabID: request.primaryTabID,
        ) {
            return .rejected(reason)
        }
        let workUnits: [WorkUnit]
        switch validatedWorkUnits(
            source: request.source,
            orderedTabIDs: request.orderedTabIDs,
            primaryTabID: request.primaryTabID,
        ) {
        case let .success(value):
            workUnits = value
        case let .failure(reason):
            return .rejected(reason)
        }
        let semantics: TransferSemantics
        switch validatedSemantics(
            workUnits: workUnits,
            sourceDomain: request.sourceDomain,
            targetDomain: request.targetDomain,
            placement: request.placement,
        ) {
        case let .success(value):
            semantics = value
        case let .failure(reason):
            return .rejected(reason)
        }
        return completePreflight(
            request: request,
            windowIDs: windowIDs,
            workUnits: workUnits,
            semantics: semantics,
        )
    }

    static func completePreflight(
        request: PreflightRequest,
        windowIDs: WindowIDs,
        workUnits: [WorkUnit],
        semantics: TransferSemantics,
    ) -> Preflight {
        let projectedWorkUnits: [ProjectedWorkUnit]
        switch makeProjectedWorkUnits(workUnits: workUnits, semantics: semantics, pinnedAt: request.pinnedAt) {
        case let .success(value):
            projectedWorkUnits = value
        case let .failure(reason):
            return .rejected(reason)
        }
        let targetPreparation: TargetPreparation
        switch prepareTargetForInsertion(request.target, workUnits: projectedWorkUnits, semantics: semantics) {
        case let .success(value):
            targetPreparation = value
        case let .failure(reason):
            return .rejected(reason)
        }
        if let reason = batchCollisionRejection(workUnits: projectedWorkUnits, target: targetPreparation.state) {
            return .rejected(reason)
        }
        return .success(makeSuccessToken(PreflightContext(
            source: request.source,
            target: request.target,
            preparedTarget: targetPreparation.state,
            workUnits: workUnits,
            projectedWorkUnits: projectedWorkUnits,
            semantics: targetPreparation.semantics,
            pinnedAt: request.pinnedAt,
            windowIDs: windowIDs,
            primaryTabID: request.primaryTabID,
        )))
    }
}
