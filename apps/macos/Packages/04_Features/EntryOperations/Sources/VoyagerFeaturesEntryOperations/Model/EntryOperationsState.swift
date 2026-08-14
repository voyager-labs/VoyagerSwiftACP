import ComposableArchitecture
import Foundation
import IdentifiedCollections
import VoyagerEntitiesEntry
import VoyagerEntitiesTag

@ObservableState
public struct EntryOperationsState: Equatable {
    public var loadingContext: EntryLoadingContextState = .init()
    public var isLoading: Bool = false
    public var isReloading: Bool = false
    public var renamingItemId: EntryModel.ID?
    public var renamingText: String = ""
    public var renamingItem: EntryModel?

    public var windowID: UUID?
    public var loadingCancellationOwnerID: UUID
    public var undoOwnerID: UUID
    public var itemStates: [String: ItemOperationState] = [:]
    public var undoRecords: [EntryActionRecord] = []
    public var redoRecords: [EntryActionRecord] = []
    var pendingReplayRecordID: EntryActionRecord.ID?
    public var selectedEntryIDs: Set<EntryModel.ID> = []
    public var clipboardItems: [String] = []
    public var clipboardOperation: ClipboardOperation = .copy
    public var cutClearSession: EntryOperationsCutClearHeuristic.CutSession?
    public var pendingEmptyTrashItemCount: Int = 0
    public var emptyTrashCompletedCount: Int = 0
    public var restorableTrashPaths: Set<String> = []
    public var applicationsForItems: [String: [ApplicationInfo]] = [:]
    public var commonApplicationsForSelectedFiles: [ApplicationInfo] = []
    public var dropValidationResult: EntryDropValidationResult = .empty

    public init(
        loadingCancellationOwnerID: UUID = UUID(),
        undoOwnerID: UUID = UUID(),
    ) {
        self.loadingCancellationOwnerID = loadingCancellationOwnerID
        self.undoOwnerID = undoOwnerID
    }

    public mutating func rotateUndoOwner(to undoOwnerID: UUID) {
        self.undoOwnerID = undoOwnerID
        undoRecords = []
        redoRecords = []
        pendingReplayRecordID = nil
    }

    public mutating func resetForDuplicate(
        windowID: UUID,
        loadingCancellationOwnerID: UUID,
        undoOwnerID: UUID,
    ) {
        loadingContext = .init()
        isLoading = false
        isReloading = false
        renamingItemId = nil
        renamingText = ""
        renamingItem = nil
        self.windowID = windowID
        self.loadingCancellationOwnerID = loadingCancellationOwnerID
        self.undoOwnerID = undoOwnerID
        itemStates = [:]
        undoRecords = []
        redoRecords = []
        pendingReplayRecordID = nil
        selectedEntryIDs = []
        clipboardItems = []
        clipboardOperation = .copy
        cutClearSession = nil
        pendingEmptyTrashItemCount = 0
        emptyTrashCompletedCount = 0
        restorableTrashPaths = []
        applicationsForItems = [:]
        commonApplicationsForSelectedFiles = []
        dropValidationResult = .empty
    }

    public var hasSelectableEntries: Bool {
        guard !selectedEntryIDs.isEmpty else { return false }
        return loadingContext.items.contains { selectedEntryIDs.contains($0.id) }
    }

    public var latestUndoRecord: EntryActionRecord? {
        undoRecords.last
    }

    public var latestRedoRecord: EntryActionRecord? {
        redoRecords.last
    }

    public var canUndoEntryAction: Bool {
        guard let record = latestUndoRecord else { return false }
        return !isEntryActionBusy(record)
    }

    public var canRedoEntryAction: Bool {
        guard let record = latestRedoRecord else { return false }
        return !isEntryActionBusy(record)
    }

    public mutating func appendUndoRecord(_ record: EntryActionRecord) {
        undoRecords.append(record)
        redoRecords.removeAll()
        pendingReplayRecordID = nil
    }

    public func isEntryActionBusy(_ record: EntryActionRecord) -> Bool {
        let paths = record.targets
            .flatMap { [$0.beforePath, $0.afterPath] }
            .compactMap(\.self)
        return paths.contains { itemStates[$0]?.isBusy == true }
    }
}

public struct EntryLoadingContextState: Equatable, Sendable {
    public var items: IdentifiedArrayOf<EntryModel> = []
}

public extension EntryOperationsState {
    var items: IdentifiedArrayOf<EntryModel> {
        get { loadingContext.items }
        set { loadingContext.items = newValue }
    }
}

public struct ItemOperationState: Equatable {
    public var isBusy: Bool
    public var lastError: FileOpError?

    public init(isBusy: Bool = false, lastError: FileOpError? = nil) {
        self.isBusy = isBusy
        self.lastError = lastError
    }
}
