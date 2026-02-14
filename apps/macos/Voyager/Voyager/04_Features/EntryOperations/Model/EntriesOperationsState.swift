import ComposableArchitecture
import Foundation

// TODO(voy-142): 타입명과 맞추기 위해 파일명을 EntryOperationsState.swift로 변경 필요.
@ObservableState
struct EntryOperationsState: Equatable {
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

struct ItemOperationState: Equatable {
    var isBusy: Bool
    var lastError: FileOpError?

    init(isBusy: Bool = false, lastError: FileOpError? = nil) {
        self.isBusy = isBusy
        self.lastError = lastError
    }
}
