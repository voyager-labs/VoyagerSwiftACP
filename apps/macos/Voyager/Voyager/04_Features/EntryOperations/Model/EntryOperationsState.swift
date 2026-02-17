import ComposableArchitecture
import Foundation
import IdentifiedCollections

@ObservableState
struct EntryOperationsState: Equatable {
    var loadingContext: EntryLoadingContextState = .init()
    var isLoading: Bool = false
    var isReloading: Bool = false

    var windowID: UUID?
    var itemStates: [String: ItemOperationState] = [:]
    var undoRecords: [EntryActionRecord] = []
    var redoRecords: [EntryActionRecord] = []
    var clipboardItems: [String] = []
    var clipboardOperation: ClipboardOperation = .copy
    var pendingEmptyTrashItemCount: Int = 0
    var emptyTrashCompletedCount: Int = 0
    var applicationsForItems: [String: [ApplicationInfo]] = [:]
    var commonApplicationsForSelectedFiles: [ApplicationInfo] = []

    var displayItems: IdentifiedArrayOf<EntryModel> {
        loadingContext.isCollectionMode ? loadingContext.collectionItems : loadingContext.items
    }

    var displayOrderItems: [EntryModel] {
        Array(displayItems)
    }

    mutating func appendUndoRecord(_ record: EntryActionRecord) {
        undoRecords.append(record)
        redoRecords.removeAll()
    }

    var latestUndoRecord: EntryActionRecord? {
        undoRecords.last
    }

    var latestRedoRecord: EntryActionRecord? {
        redoRecords.last
    }

    var canUndoEntryAction: Bool {
        guard let record = latestUndoRecord else { return false }
        return !isEntryActionBusy(record)
    }

    var canRedoEntryAction: Bool {
        guard let record = latestRedoRecord else { return false }
        return !isEntryActionBusy(record)
    }

    func isEntryActionBusy(_ record: EntryActionRecord) -> Bool {
        let paths = record.targets
            .flatMap { [$0.beforePath, $0.afterPath] }
            .compactMap(\.self)
        return paths.contains { itemStates[$0]?.isBusy == true }
    }
}

struct EntryLoadingContextState: Equatable {
    var items: IdentifiedArrayOf<EntryModel> = []
    var collectionItems: IdentifiedArrayOf<EntryModel> = []
    var isCollectionMode: Bool = false
}

extension EntryOperationsState {
    var items: IdentifiedArrayOf<EntryModel> {
        get { loadingContext.items }
        set { loadingContext.items = newValue }
    }

    var collectionItems: IdentifiedArrayOf<EntryModel> {
        get { loadingContext.collectionItems }
        set { loadingContext.collectionItems = newValue }
    }

    var isCollectionMode: Bool {
        get { loadingContext.isCollectionMode }
        set { loadingContext.isCollectionMode = newValue }
    }
}

struct ItemOperationState: Equatable {
    var isBusy: Bool
    var lastError: FileOpError?

    init(isBusy: Bool = false, lastError: FileOpError? = nil) {
        self.isBusy = isBusy
        self.lastError = lastError
    }
}
