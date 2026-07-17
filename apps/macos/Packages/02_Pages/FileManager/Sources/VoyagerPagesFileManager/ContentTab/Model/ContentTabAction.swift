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

    // MARK: - CTM-001-select_content_tabs

    /// 유효한 Content Tab identity의 선택 membership을 반전한다.
    case toggleSelection(ContentTabID)
    /// 현재 anchor부터 target까지 pinned-first 표시 구간으로 선택을 교체한다.
    case selectRange(to: ContentTabID)
    /// 선택 membership과 range anchor를 함께 비운다.
    case clearSelection

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
