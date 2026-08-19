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

    struct WorkPlan {
        let workUnits: [WorkUnit]
        let semantics: TransferSemantics
        let projectedWorkUnits: [ProjectedWorkUnit]
        let targetPreparation: TargetPreparation
    }

    struct PreflightInput {
        let source: FileManagerWindowState
        let target: FileManagerWindowState
        let orderedTabIDs: [ContentTabID]
        let primaryTabID: ContentTabID
        let sourceDomain: ContentTabDomain?
        let targetDomain: ContentTabDomain?
        let placement: ContentTabPlacement?
        let pinnedAt: Date?
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
        let input = PreflightInput(
            source: source,
            target: target,
            orderedTabIDs: orderedTabIDs,
            primaryTabID: primaryTabID,
            sourceDomain: sourceDomain,
            targetDomain: targetDomain,
            placement: placement,
            pinnedAt: pinnedAt,
        )
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

        let workPlan: WorkPlan
        switch resolveWorkPlan(input) {
        case let .success(value):
            workPlan = value
        case let .failure(reason):
            return .rejected(reason)
        }

        let context = PreflightContext(
            source: source,
            target: target,
            preparedTarget: workPlan.targetPreparation.state,
            workUnits: workPlan.workUnits,
            projectedWorkUnits: workPlan.projectedWorkUnits,
            semantics: workPlan.targetPreparation.semantics,
            pinnedAt: pinnedAt,
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

    static func resolveWorkPlan(_ input: PreflightInput) -> Swift.Result<WorkPlan, Rejection> {
        let workUnits: [WorkUnit]
        switch validatedWorkUnits(
            source: input.source,
            orderedTabIDs: input.orderedTabIDs,
            primaryTabID: input.primaryTabID,
        ) {
        case let .success(value):
            workUnits = value
        case let .failure(reason):
            return .failure(reason)
        }

        let semantics: TransferSemantics
        switch validatedSemantics(
            workUnits: workUnits,
            sourceDomain: input.sourceDomain,
            targetDomain: input.targetDomain,
            placement: input.placement,
        ) {
        case let .success(value):
            semantics = value
        case let .failure(reason):
            return .failure(reason)
        }

        let projectedWorkUnits: [ProjectedWorkUnit]
        switch makeProjectedWorkUnits(workUnits: workUnits, semantics: semantics, pinnedAt: input.pinnedAt) {
        case let .success(value):
            projectedWorkUnits = value
        case let .failure(reason):
            return .failure(reason)
        }

        let targetPreparation: TargetPreparation
        switch prepareTargetForInsertion(
            input.target,
            workUnits: projectedWorkUnits,
            semantics: semantics,
        ) {
        case let .success(value):
            targetPreparation = value
        case let .failure(reason):
            return .failure(reason)
        }
        if let reason = batchCollisionRejection(workUnits: projectedWorkUnits, target: targetPreparation.state) {
            return .failure(reason)
        }
        return .success(WorkPlan(
            workUnits: workUnits,
            semantics: semantics,
            projectedWorkUnits: projectedWorkUnits,
            targetPreparation: targetPreparation,
        ))
    }
}
