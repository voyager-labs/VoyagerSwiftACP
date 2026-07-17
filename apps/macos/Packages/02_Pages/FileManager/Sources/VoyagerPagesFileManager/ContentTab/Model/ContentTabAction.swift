import ComposableArchitecture
import Foundation

public enum ContentTabReorderPlacement: Equatable, Sendable {
    case before
    case after
}

@CasePathable
public enum ContentTabAction: Sendable {
    case open(ContentTabPageAnchor)
    case setCurrent(ContentTabID)
    case requestClose(ContentTabID)
    case close(ContentTabID)
    case commitClose(ContentTabID)
    case restore
    case duplicate(sourceID: ContentTabID, duplicateID: ContentTabID)
    case reorder(
        sourceID: ContentTabID,
        targetID: ContentTabID,
        placement: ContentTabReorderPlacement,
    )
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
