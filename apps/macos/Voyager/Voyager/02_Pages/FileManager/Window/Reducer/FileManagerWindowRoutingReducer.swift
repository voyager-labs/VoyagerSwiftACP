import AppKit
import ComposableArchitecture
import Foundation

@Reducer
struct FileManagerWindowRoutingReducer {
    typealias State = FileManagerWindowState
    typealias Action = FileManagerWindowAction

    var body: some Reducer<State, Action> {
        Reduce { _, action in
            switch action {
            case let .sidebar(.view(.dropItemsToSidebarFolder(providers, targetURL))):
                .send(.content(.delegate(.dropItemsToSidebarFolder(
                    providers: providers,
                    targetURL: targetURL,
                ))))

            case let .sidebar(.view(.dropItemsToTag(providers, tagName))):
                .send(.content(.delegate(.dropItemsToTag(
                    providers: providers,
                    tagName: tagName,
                ))))

            case .content(.delegate(.closeWindow)):
                .send(.closeWindow)

            case .closeWindow:
                .run { _ in
                    await MainActor.run {
                        NSApp.keyWindow?.close()
                    }
                }

            default:
                .none
            }
        }
    }
}
