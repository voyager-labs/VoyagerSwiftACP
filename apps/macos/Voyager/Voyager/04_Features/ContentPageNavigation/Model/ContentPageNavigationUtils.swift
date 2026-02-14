import Foundation

enum ContentPageNavigationUtils {
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

    // TODO: Collection 관련 구조로 이동
    enum CollectionKind: Equatable, Sendable {
        case temporary
        case file(url: URL, name: String)
    }

    // TODO: Collection 관련 구조로 이동
    struct CollectionNavigation: Equatable, Sendable {
        var kind: CollectionKind
        var context: CollectionContext
        var sortKey: SortKey
        var sortOrder: SortOrder
        var viewLayout: ContentViewLayout
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
