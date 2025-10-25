import ComposableArchitecture
import Foundation

enum FileManagerNavigationUtils {
    enum NavigationState: Equatable {
        case folder(String)
        case recents
        case shared
        case tags(String)
    }

    static func navigateToState(_ navigationState: NavigationState) -> Effect<FileManagerFeature.Action> {
        switch navigationState {
        case .recents:
            return .send(.fsItems(.loadRecentItems))
        case .shared:
            return .none
        case let .folder(path):
            return .send(.fsItems(.loadItems(path: path)))
        case let .tags(tagName):
            return .run { send in
                let taggedItems = await SidebarUtils.loadFilesWithTag(tagName)
                await send(.fsItems(.itemsLoaded(taggedItems)))
            }
        }
    }

    static func navigationStateFromPath(_ path: String) -> NavigationState {
        switch path {
        case "Recents":
            return .recents
        case "Shared":
            return .shared
        case let tagName where FSItemTagUtils.getTagNames().contains(tagName):
            return .tags(path)
        default:
            return .folder(path)
        }
    }
}
