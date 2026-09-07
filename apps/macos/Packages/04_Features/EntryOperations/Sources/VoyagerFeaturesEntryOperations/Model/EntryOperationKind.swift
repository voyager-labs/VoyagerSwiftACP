public enum OperationKind: Equatable, Hashable, Sendable {
    case openDefault
    case openWithApp(String)
    case setDefaultApp(String)
    case quickLook
    case getInfo
    case share
    case performService(String)
    case revealInFinder
    case copyPath
    case createFolder
    case createAlias
    case pasteFileCopy
    case pasteFileMove
    case pasteFileDuplicate
    case externalObjectImportItem
    case rename
    case moveToTrash
    case deleteImmediately
    case putBack
    case compress
    case extract
    case setTags

    nonisolated public var isUndoable: Bool {
        switch self {
        case .createFolder,
             .createAlias,
             .pasteFileCopy,
             .pasteFileMove,
             .pasteFileDuplicate,
             .rename,
             .moveToTrash,
             .putBack,
             .setTags:
            true

        case .openDefault,
             .openWithApp,
             .setDefaultApp,
             .quickLook,
             .getInfo,
             .share,
             .performService,
             .revealInFinder,
             .copyPath,
             .deleteImmediately,
             .compress,
             .extract,
             .externalObjectImportItem:
            false
        }
    }
}

public enum ClipboardOperation: Equatable, Sendable {
    case copy
    case cut
}
