import Foundation

enum OperationKind: Equatable, Hashable, Sendable {
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
    case pasteFile
    case rename
    case moveToTrash
    case deleteImmediately
    case putBack
    case compress
    case extract
    case setTags
}
