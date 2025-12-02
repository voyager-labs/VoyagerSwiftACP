import ComposableArchitecture
import Foundation

enum FileManagerNavigationUtils {
    enum NavigationState: Equatable {
        case folder(String)
        case recents
        case tags(String)
        case computer
    }

    static func navigateToState(_ navigationState: NavigationState) -> Effect<FileManagerFeature.Action> {
        switch navigationState {
        case .recents:
            return .send(.fsItems(.loadRecentItems))
        case let .folder(path):
            return .send(.fsItems(.loadItems(path: path)))
        case let .tags(tagName):
            return .run { send in
                let taggedItems = await SidebarUtils.loadFilesWithTag(tagName)
                await send(.fsItems(.itemsLoaded(taggedItems)))
            }
        case .computer:
            return .send(.fsItems(.loadComputerItems))
        }
    }

    static func navigationStateFromPath(_ path: String) -> NavigationState {
        switch path {
        case "Recents":
            return .recents
        default:
            if path == SidebarUtils.computerName {
                return .computer
            } else if path.hasPrefix("/") {
                return .folder(path)
            } else {
                return .tags(path)
            }
        }
    }
}
