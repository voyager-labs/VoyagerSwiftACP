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
            .send(.fsItems(.loadRecentItems))
        case let .folder(path):
            .send(.fsItems(.loadItems(path: path)))
        case let .tags(tagName):
            .run { send in
                let taggedItems = await SidebarUtils.loadFilesWithTag(tagName)
                await send(.fsItems(.itemsLoaded(taggedItems)))
            }
        case .computer:
            .send(.fsItems(.loadComputerItems))
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
