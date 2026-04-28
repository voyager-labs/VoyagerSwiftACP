import Foundation

enum ContentPageNavigationRoute: Equatable {
    case folder(String)
    case recents
    case tags(String)
    case computer
    case collection(ContentPageCollectionNavigation)

    var isCollection: Bool {
        if case .collection = self {
            return true
        }
        return false
    }

    static func fromPath(_ path: String, computerName: String) -> Self {
        switch path {
        case "Recents":
            .recents
        default:
            if path == computerName {
                .computer
            } else if path.hasPrefix("/") {
                .folder(path)
            } else {
                .tags(path)
            }
        }
    }
}

enum ContentPageCollectionKind: Equatable, Sendable {
    case temporary
    case file(url: URL, name: String)
}

struct ContentPageCollectionNavigation: Equatable, Sendable {
    var kind: ContentPageCollectionKind
    var context: CollectionContext
    var sortKey: SortKey
    var sortOrder: SortOrder
    var viewLayout: EntryViewLayoutState.Mode
    var compatibility: CollectionFileCompatibilityMetadata?
}
