import Foundation
import VoyagerEntitiesAi
import VoyagerFeaturesAiChat
import VoyagerFeaturesContentPageNavigation

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
