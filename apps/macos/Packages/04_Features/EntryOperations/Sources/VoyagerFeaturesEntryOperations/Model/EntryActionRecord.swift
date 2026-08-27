import Foundation

public struct EntryActionRecord: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let command: EntryCommandMetadata?
    public let operationKind: OperationKind
    public let timestamp: Date
    public let targets: [Target]
    public let failedCount: Int
    public let cancelledCount: Int
    /// 실제 성공 시도 수. targets는 undo 가능한 의미론적 변환 경로만 담으므로
    /// 비-undo 연산의 성공 집계는 이 값으로 별도 전달한다.
    public let succeededCount: Int

    public var attemptedCount: Int {
        succeededCount + failedCount + cancelledCount
    }

    public struct Target: Equatable, Sendable {
        public let beforePath: String?
        public let afterPath: String?
        public let beforeTags: [String]?
        public let afterTags: [String]?

        nonisolated public init(
            beforePath: String?,
            afterPath: String?,
            beforeTags: [String]? = nil,
            afterTags: [String]? = nil,
        ) {
            self.beforePath = beforePath
            self.afterPath = afterPath
            self.beforeTags = beforeTags
            self.afterTags = afterTags
        }
    }

    nonisolated public init(
        operationKind: OperationKind,
        targets: [Target],
        failedCount: Int = 0,
        succeededCount: Int? = nil,
        id: UUID = UUID(),
        timestamp: Date = Date(),
    ) {
        self.id = id
        command = nil
        self.operationKind = operationKind
        self.timestamp = timestamp
        self.targets = targets
        self.failedCount = max(0, failedCount)
        cancelledCount = 0
        // 의미론적 target 기반 연산은 성공 수가 targets 수와 일치한다.
        self.succeededCount = max(0, succeededCount ?? targets.count)
    }

    nonisolated public init(
        operationKind: OperationKind,
        targets: [Target],
        failedCount: Int,
        cancelledCount: Int,
        succeededCount: Int,
        id: UUID,
        timestamp: Date,
    ) {
        self.id = id
        command = nil
        self.operationKind = operationKind
        self.timestamp = timestamp
        self.targets = targets
        self.failedCount = max(0, failedCount)
        self.cancelledCount = max(0, cancelledCount)
        self.succeededCount = max(0, succeededCount)
    }

    nonisolated public func attaching(command: EntryCommandMetadata) -> Self {
        Self(
            command: command,
            operationKind: operationKind,
            targets: targets,
            failedCount: failedCount,
            cancelledCount: cancelledCount,
            succeededCount: succeededCount,
            timestamp: timestamp,
        )
    }

    nonisolated private init(
        command: EntryCommandMetadata,
        operationKind: OperationKind,
        targets: [Target],
        failedCount: Int,
        cancelledCount: Int,
        succeededCount: Int,
        timestamp: Date,
    ) {
        id = command.id
        self.command = command
        self.operationKind = operationKind
        self.timestamp = timestamp
        self.targets = targets
        self.failedCount = max(0, failedCount)
        self.cancelledCount = max(0, cancelledCount)
        self.succeededCount = max(0, succeededCount)
    }
}

public struct EntryCommandMetadata: Equatable, Sendable {
    public let id: UUID
    public let interaction: EntryInteractionIdentity
    public let source: EntryCommandSource

    public init(id: UUID, interaction: EntryInteractionIdentity, source: EntryCommandSource) {
        self.id = id
        self.interaction = interaction
        self.source = source
    }
}

public enum EntryCommandSource: String, Equatable, Sendable {
    case fileManagerContent = "file_manager_content"
    case contextMenu = "context_menu"
    case toolbar
    case keyboardShortcut = "keyboard_shortcut"
    case menuCommand = "menu_command"
    case dragAndDrop = "drag_and_drop"
}

public enum EntryInteractionIdentity: Hashable, Sendable {
    case openEntryWithDefaultApp
    case openEntryWithSelectedApp
    case quickLookEntry
    case getEntryInfo
    case shareEntries
    case revealEntriesInFinder
    case performService
    case copyEntries
    case cutEntries
    case pasteEntries
    case duplicateEntries
    case moveEntries
    case createEntryAlias
    case createNewFolder
    case deleteEntriesImmediately
    case emptyTrash
    case moveEntriesToTrash
    case putDeletedEntriesBack
    case editEntryTags
    case renameEntry
    case copyAbsolutePaths
    case copyURLs
    case compressEntries
    case extractEntries

    public var actionType: String {
        switch self {
        case .openEntryWithDefaultApp, .openEntryWithSelectedApp: "open"
        case .quickLookEntry: "quick_look"
        case .getEntryInfo: "get_info"
        case .shareEntries: "share"
        case .revealEntriesInFinder: "reveal_in_finder"
        case .performService: "perform_service"
        case .copyEntries, .pasteEntries, .duplicateEntries, .compressEntries, .extractEntries: "copy"
        case .cutEntries: "cut"
        case .moveEntries: "move"
        case .createEntryAlias, .createNewFolder: "create"
        case .deleteEntriesImmediately, .emptyTrash, .moveEntriesToTrash: "trash"
        case .putDeletedEntriesBack: "restore"
        case .editEntryTags: "tag"
        case .renameEntry: "rename"
        case .copyAbsolutePaths, .copyURLs: "copy_path"
        }
    }
}
