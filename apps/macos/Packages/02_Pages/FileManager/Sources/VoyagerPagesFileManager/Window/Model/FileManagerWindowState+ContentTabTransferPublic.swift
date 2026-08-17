import Foundation
import VoyagerEntitiesAi
import VoyagerFeaturesAiChat
import VoyagerFeaturesContentPageNavigation

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
