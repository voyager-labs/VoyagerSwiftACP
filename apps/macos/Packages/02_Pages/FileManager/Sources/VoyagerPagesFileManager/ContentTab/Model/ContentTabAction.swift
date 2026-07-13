import ComposableArchitecture
import Foundation

@CasePathable
public enum ContentTabAction: Sendable {
    case open(ContentTabPageAnchor)
    case setCurrent(ContentTabID)
    case close(ContentTabID)
    case restore
    case pin(ContentTabID)
    case unpin(ContentTabID)
    case updateActivePageAnchor(ContentTabID, ContentTabPageAnchor)
    case pinnedRecordSaveSucceeded
    case pinnedRecordSaveFailed(
        tabID: ContentTabID,
        previousIsPinned: Bool,
        previousPinnedRecord: ContentTabPinnedRecord?,
    )
}
