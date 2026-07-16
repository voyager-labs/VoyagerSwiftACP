import ComposableArchitecture
import Foundation

@CasePathable
public enum ContentTabAction: Sendable {
    case open(ContentTabPageAnchor)
    case setCurrent(ContentTabID)
    case requestClose(ContentTabID)
    case close(ContentTabID)
    case commitClose(ContentTabID)
    case restore
    case duplicate(sourceID: ContentTabID, duplicateID: ContentTabID)
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
