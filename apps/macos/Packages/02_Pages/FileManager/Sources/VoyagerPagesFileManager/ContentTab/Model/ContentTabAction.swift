import ComposableArchitecture
import Foundation

public enum FileManagerTopNavigationReorderPlacement: Equatable, Sendable {
    case before
    case after
}

public struct ContentTabDuplicateRequest: Equatable, Sendable {
    public let sourceID: ContentTabID
    public let duplicateID: ContentTabID

    public init(sourceID: ContentTabID, duplicateID: ContentTabID) {
        self.sourceID = sourceID
        self.duplicateID = duplicateID
    }
}

public enum ContentTabPinnedRecordSaveNonAppliedReason: Equatable, Sendable {
    case superseded
    case cancelled
}

public struct ContentTabPinnedRecordRollbackSnapshot: Equatable, Sendable {
    public let previousIsPinned: Bool
    public let previousPinnedRecord: ContentTabPinnedRecord?
    public let previousTabIndex: Int?

    public init(
        previousIsPinned: Bool,
        previousPinnedRecord: ContentTabPinnedRecord?,
        previousTabIndex: Int?,
    ) {
        self.previousIsPinned = previousIsPinned
        self.previousPinnedRecord = previousPinnedRecord
        self.previousTabIndex = previousTabIndex
    }
}

public struct ContentTabPinnedRecordTerminalContext: Equatable, Sendable {
    public let intentID: UUID
    public let generation: ContentTabPinnedRecordMutationGeneration

    public init(
        intentID: UUID,
        generation: ContentTabPinnedRecordMutationGeneration,
    ) {
        self.intentID = intentID
        self.generation = generation
    }
}

public enum ContentTabPinnedRecordPersistenceMutation: Equatable, Sendable {
    case upsert(
        record: ContentTabPinnedRecord,
        dormantSlot: FileManagerTopNavigationOrderPolicy.DormantContentTabSlot?,
    )
    case remove(recordID: String)
}

public struct ContentTabPinnedRecordPersistenceRequest: Equatable, Sendable {
    public let tabID: ContentTabID
    public let context: ContentTabPinnedRecordTerminalContext
    public let rollback: ContentTabPinnedRecordRollbackSnapshot
    public let mutation: ContentTabPinnedRecordPersistenceMutation

    public init(
        tabID: ContentTabID,
        context: ContentTabPinnedRecordTerminalContext,
        rollback: ContentTabPinnedRecordRollbackSnapshot,
        mutation: ContentTabPinnedRecordPersistenceMutation,
    ) {
        self.tabID = tabID
        self.context = context
        self.rollback = rollback
        self.mutation = mutation
    }
}

public enum ContentTabPinnedRecordPersistenceRouting: Equatable, Sendable {
    case local(discoveredLocationIDs: [String])
    case delegate
}

extension ContentTabPinnedRecordPersistenceRouting: DependencyKey {
    public static let liveValue: Self = .local(discoveredLocationIDs: [])
    public static let testValue: Self = .local(discoveredLocationIDs: [])
    public static let previewValue: Self = .local(discoveredLocationIDs: [])
}

public extension DependencyValues {
    var contentTabPinnedRecordPersistenceRouting: ContentTabPinnedRecordPersistenceRouting {
        get { self[ContentTabPinnedRecordPersistenceRouting.self] }
        set { self[ContentTabPinnedRecordPersistenceRouting.self] = newValue }
    }
}

@CasePathable
public enum ContentTabAction: Sendable {
    case delegate(Delegate)
    case open(ContentTabPageAnchor)
    case setCurrent(ContentTabID)

    // MARK: - CTM-001-select_content_tabs

    /// 유효한 Content Tab identity의 선택 membership을 반전한다.
    case toggleSelection(ContentTabID)
    /// 현재 anchor부터 target까지 pinned-first 표시 구간으로 선택을 교체한다.
    case selectRange(to: ContentTabID, orderedIDs: [ContentTabID])
    /// 선택 membership과 range anchor를 현재 active tab 하나로 축소한다.
    case collapseSelectionToActive

    case requestClose(ContentTabID)
    case close(ContentTabID)
    case commitClose(ContentTabID)
    case restore
    case duplicate(sourceID: ContentTabID, duplicateID: ContentTabID)
    case duplicateSelected([ContentTabDuplicateRequest])
    case reorder(
        sourceID: ContentTabID,
        targetID: ContentTabID,
        placement: FileManagerTopNavigationReorderPlacement,
    )
    case pin(ContentTabID)
    case pinUsingDormantSlot(
        ContentTabID,
        FileManagerTopNavigationOrderPolicy.DormantContentTabSlot?,
    )
    case unpin(ContentTabID)
    case updateActivePageAnchor(ContentTabID, ContentTabPageAnchor)
    case updateRuntimePageAnchor(ContentTabID, ContentTabPageAnchor)
    case pinnedRecordSaveSucceeded(
        tabID: ContentTabID,
        context: ContentTabPinnedRecordTerminalContext,
    )
    case pinnedRecordSaveFailed(
        tabID: ContentTabID,
        context: ContentTabPinnedRecordTerminalContext,
        rollback: ContentTabPinnedRecordRollbackSnapshot,
    )
    case pinnedRecordStoreUnavailable(
        tabID: ContentTabID,
        context: ContentTabPinnedRecordTerminalContext,
        failure: FileManagerTopNavigationArrangementLoadFailure,
        rollback: ContentTabPinnedRecordRollbackSnapshot,
    )
    case pinnedRecordSaveNotApplied(
        tabID: ContentTabID,
        context: ContentTabPinnedRecordTerminalContext,
        reason: ContentTabPinnedRecordSaveNonAppliedReason,
        rollback: ContentTabPinnedRecordRollbackSnapshot,
    )

    @CasePathable
    public enum Delegate: Sendable {
        case persistPinnedRecord(ContentTabPinnedRecordPersistenceRequest)
    }
}
