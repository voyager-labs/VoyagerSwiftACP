public enum OperationKind: Equatable, Hashable, Sendable {
    case openDefault
    case openWithApp(String)
    case setDefaultApp(String)
    case quickLook
    case getInfo
    case share
    case performService(String)
    case revealInFinder
    case createFolder
    case createAlias
    case pasteFileCopy
    case pasteFileMove
    case pasteFileDuplicate
    case rename
    case moveToTrash
    case deleteImmediately
    case putBack
    case compress
    case extract
    case setTags

    public nonisolated var isUndoable: Bool {
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
             .deleteImmediately,
             .compress,
             .extract:
            false
        }
    }
}

public enum ClipboardOperation: Equatable, Sendable {
    case copy
    case cut
}
