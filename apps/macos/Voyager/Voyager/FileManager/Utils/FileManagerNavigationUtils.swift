import ComposableArchitecture
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
        var context: FileManagerFeature.CollectionContext
        var sortKey: SortKey
        var sortOrder: SortOrder
        var viewLayout: FileManagerFeature.ViewLayout
    }

    static func navigateToState(_ navigationState: NavigationState) -> Effect<FileManagerFeature.Action> {
        switch navigationState {
        case .recents:
            .send(.fsItems(.loadRecentItems(showHidden: false)))
        case let .folder(path):
            .send(.fsItems(.loadItems(path: path)))
        case let .tags(tagName):
            .run { send in
                let taggedItems = await SidebarUtils.loadFilesWithTag(tagName, showHidden: false)
                await send(.fsItems(.itemsLoaded(taggedItems)))
            }
        case .computer:
            .send(.fsItems(.loadComputerItems))
        case let .collection(navigation):
            .send(.navigateToCollection(navigation))
        }
    }

    static func navigationStateFromPath(_ path: String) -> NavigationState {
        switch path {
        case "Recents":
            .recents
        default:
            if path == SidebarUtils.computerName {
                .computer
            } else if path.hasPrefix("/") {
                .folder(path)
            } else {
                .tags(path)
            }
        }
    }
}
