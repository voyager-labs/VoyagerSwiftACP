import Foundation

enum FileManagerNavigationUtils {
    enum NavigationState: Equatable {
        case folder(String)
        case recents
        case tags(String)
        case computer
        case collection(CollectionNavigation)

        var isCollection: Bool {
            if case .collection = self {
                return true
            }
            return false
        }
    }

    enum CollectionKind: Equatable, Sendable {
        case temporary
        case file(url: URL, name: String)
    }

    struct CollectionNavigation: Equatable, Sendable {
        var kind: CollectionKind
        var context: CollectionContext
        var sortKey: SortKey
        var sortOrder: SortOrder
        var viewLayout: FileManagerFeature.ViewLayout
    }

    static func navigationStateFromPath(_ path: String, computerName: String) -> NavigationState {
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
