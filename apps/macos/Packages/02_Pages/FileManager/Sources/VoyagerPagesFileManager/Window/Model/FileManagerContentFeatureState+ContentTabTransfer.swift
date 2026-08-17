import Foundation
import VoyagerEntitiesAi
import VoyagerFeaturesAiChat
import VoyagerFeaturesContentPageNavigation

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
