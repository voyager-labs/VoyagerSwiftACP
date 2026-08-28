import ComposableArchitecture
import Foundation
import IdentifiedCollections
import VoyagerEntitiesEntry
import VoyagerEntitiesTag

@ObservableState
public struct EntryOperationsState: Equatable {
    public var loadingContext: EntryLoadingContextState = .init()
    public var folderLoadingContexts: [EntryFolderLoadRequest.RequestID: EntryFolderLoadingContext] = [:]
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
    public var applicationsForTypes: [String: [ApplicationInfo]] = [:]
    public var openWithTypeRequestGenerations: [String: Int] = [:]
    public var openWithInFlightTypeIDs: Set<String> = []
    public var openWithCommonTypeGenerations: [String: Int] = [:]
    public var commonApplicationsForSelectedFiles: [ApplicationInfo] = []
    public var openWithCommonRequestGeneration: Int = 0
    public var dropValidationResult: EntryDropValidationResult = .empty
    public var activeExternalDrop: ExternalDropActiveSession?
    public var externalObjectImportStatus: ExternalObjectImportStatus?
    public var externalDropImportPlacement: ExternalDropImportPlacementState?

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
        folderLoadingContexts = [:]
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
        applicationsForTypes = [:]
        openWithTypeRequestGenerations = [:]
        openWithInFlightTypeIDs = []
        openWithCommonTypeGenerations = [:]
        commonApplicationsForSelectedFiles = []
        openWithCommonRequestGeneration = 0
        dropValidationResult = .empty
        activeExternalDrop = nil
        externalObjectImportStatus = nil
        externalDropImportPlacement = nil
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

public struct EntryFolderLoadRequest: Equatable, Sendable {
    public struct RequestID: Hashable, Sendable {
        public let rootContextGeneration: Int
        public let folderID: EntryModel.ID

        public init(rootContextGeneration: Int, folderID: EntryModel.ID) {
            self.rootContextGeneration = rootContextGeneration
            self.folderID = folderID
        }
    }

    public let id: RequestID
    public let folderGeneration: Int
    public let path: String
    public let showHidden: Bool
    public let priority: EntryMetadataPriority
    public let ancestorPaths: [String]

    public init(
        rootContextGeneration: Int,
        folderID: EntryModel.ID,
        folderGeneration: Int,
        path: String,
        showHidden: Bool,
        priority: EntryMetadataPriority,
        ancestorPaths: [String] = [],
    ) {
        id = .init(rootContextGeneration: rootContextGeneration, folderID: folderID)
        self.folderGeneration = folderGeneration
        self.path = path
        self.showHidden = showHidden
        self.priority = priority
        self.ancestorPaths = ancestorPaths
    }
}

public struct EntryFolderLoadingContext: Equatable, Sendable {
    public var request: EntryFolderLoadRequest
    public var expectedCoreBatchIndex = 0
    public var coreFinished = false
    public var terminal = false

    public init(request: EntryFolderLoadRequest) {
        self.request = request
    }
}

public struct EntryLoadingContextState: Equatable, Sendable {
    public var items: IdentifiedArrayOf<EntryModel> = []
    var preservedDirectoryReloadItems: IdentifiedArrayOf<EntryModel>?
    public var generation = 0
    public var expectedCoreBatchIndex = 0
    public var coreFinished = false
    public var acceptedCoreFinishedGeneration: Int?
    public var streamTerminal = false
    public var isIncomplete = false
    public var sourceKind: EntryLoadingSourceKind?
    var directoryPath: String?

    public var isBufferingPreservedDirectoryReload: Bool {
        preservedDirectoryReloadItems != nil
    }

    /// 동일 경로에 복원 가능한 committed snapshot이 있어 원자 reload buffering을 적용할 수 있는지 판단한다.
    /// isReloading 여부는 판단에서 제외되며, 경로가 다른 load는 후보 없이 progressive flow로 진행된다.
    func shouldBufferDirectoryReload(at path: String) -> Bool {
        sourceKind == .directory
            && directoryPath == path
            && (!items.isEmpty || coreFinished && streamTerminal)
    }

    mutating func begin(
        sourceKind: EntryLoadingSourceKind,
        preservesSnapshot: Bool,
        directoryPath: String? = nil,
    ) -> Int {
        generation &+= 1
        expectedCoreBatchIndex = 0
        coreFinished = false
        acceptedCoreFinishedGeneration = nil
        streamTerminal = false
        isIncomplete = false
        self.sourceKind = sourceKind
        self.directoryPath = sourceKind == .directory ? directoryPath : nil
        preservedDirectoryReloadItems = sourceKind == .directory && preservesSnapshot ? [] : nil
        if !preservesSnapshot {
            items = []
        }
        return generation
    }

    public mutating func invalidate() {
        generation &+= 1
        expectedCoreBatchIndex = 0
        coreFinished = false
        acceptedCoreFinishedGeneration = nil
        streamTerminal = false
        isIncomplete = false
        sourceKind = nil
        directoryPath = nil
        preservedDirectoryReloadItems = nil
    }
}

public enum EntryLoadingSourceKind: Equatable, Sendable {
    case directory
    case recents
    case tags
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

/// 외부 drop 획득 중인 단일 active 세션. destination/order 메타데이터는 불변이고,
/// 수신된 staged 파일만 획득 진행 중 누적된다.
public struct ExternalDropActiveSession: Equatable, Sendable {
    public let sessionID: ExternalDropSessionID
    public let destination: String
    public let orderedPromisedNames: [String]
    public let promisedOrdinals: [Int]
    public let forcedCopy: Bool
    public let stagingDirectory: String
    public let immediateURLPaths: [String]
    public let immediateOrdinals: [Int]
    public var receivedFiles: [ExternalDropReceivedFile]

    public init(request: ExternalDropAcceptedRequest) {
        sessionID = request.sessionID
        destination = request.destination
        orderedPromisedNames = request.orderedPromisedNames
        promisedOrdinals = request.promisedOrdinals
        forcedCopy = request.forcedCopy
        stagingDirectory = request.stagingDirectory
        immediateURLPaths = request.immediateURLPaths
        immediateOrdinals = request.immediateOrdinals
        receivedFiles = []
    }
}

/// 외부 object import의 종단 상태. Todo 1 PRODUCT 계약의
/// `external_object_import_pending`/`applied`/`partially_applied`/`failed`를 모델링한다.
public enum ExternalObjectImportStatus: Equatable, Sendable {
    case pending
    case applied
    case partiallyApplied
    case failed
}

/// placement(.applyImport)의 in-flight 추적 상태.
/// 모든 source 항목의 `operationFinished`를 수신해 정확히 한 번 종합 완료를 emit하기 위한 추적이다.
/// `destinationBySource`는 복사 배치가 `.pathsMutated([source, destination])`으로 보고한 실제
/// 목적지 경로를 기록해, 결과에 staging이 아닌 destination 경로가 담기도록 한다.
public struct ExternalDropImportPlacementState: Equatable, Sendable {
    public let sessionID: ExternalDropSessionID
    public let destination: String
    public var pendingPaths: Set<String>
    /// source(staging) 경로 → 실제 복사된 destination 경로 매핑.
    public var destinationBySource: [String: String]
    public var succeededPaths: [String]
    public var failedPaths: [String]

    public init(
        sessionID: ExternalDropSessionID,
        destination: String,
        pendingPaths: Set<String>,
    ) {
        self.sessionID = sessionID
        self.destination = destination
        self.pendingPaths = pendingPaths
        destinationBySource = [:]
        succeededPaths = []
        failedPaths = []
    }

    public var isComplete: Bool {
        pendingPaths.isEmpty
    }
}

/// all-promises 성공 시 reducer가 emit하는 import-placement 계획.
/// destination/order 메타데이터와 수신된 staged 파일(item/callback ordinal 순서 보존)을 담으며,
/// 실제 복사 배치는 Todo 7 seam(`.applyImport`)이 수행한다.
public struct ExternalDropImportPlan: Equatable, Sendable {
    public let sessionID: ExternalDropSessionID
    public let destination: String
    public let forcedCopy: Bool
    public let orderedPromisedNames: [String]
    public let promisedOrdinals: [Int]
    public let receivedFiles: [ExternalDropReceivedFile]
    /// promise/materialization 없이 즉시 복사 가능한 file URL 경로. staged 복사와 함께 배치된다.
    public let immediateURLPaths: [String]
    /// `immediateURLPaths`와 1:1 대응하는 pasteboard logical item 순번(코멘트 #3831133039).
    public let immediateOrdinals: [Int]

    public init(
        sessionID: ExternalDropSessionID,
        destination: String,
        forcedCopy: Bool,
        orderedPromisedNames: [String],
        promisedOrdinals: [Int],
        receivedFiles: [ExternalDropReceivedFile],
        immediateURLPaths: [String] = [],
        immediateOrdinals: [Int] = [],
    ) {
        self.sessionID = sessionID
        self.destination = destination
        self.forcedCopy = forcedCopy
        self.orderedPromisedNames = orderedPromisedNames
        self.promisedOrdinals = promisedOrdinals
        self.receivedFiles = receivedFiles
        self.immediateURLPaths = immediateURLPaths
        self.immediateOrdinals = immediateOrdinals
    }
}
