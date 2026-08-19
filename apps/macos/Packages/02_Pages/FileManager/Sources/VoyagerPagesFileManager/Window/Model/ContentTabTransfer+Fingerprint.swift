import Foundation
import VoyagerEntitiesAi
import VoyagerFeaturesAiChat
import VoyagerFeaturesContentPageNavigation

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
