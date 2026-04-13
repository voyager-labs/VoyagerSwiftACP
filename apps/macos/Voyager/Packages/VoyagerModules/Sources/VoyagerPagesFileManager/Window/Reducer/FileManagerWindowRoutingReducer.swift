import AppKit
import ComposableArchitecture
import Foundation

@Reducer
public struct FileManagerWindowRoutingReducer {
    public typealias State = FileManagerWindowState
    public typealias Action = FileManagerWindowAction

    public var body: some Reducer<State, Action> {
        Reduce { _, action in
            switch action {
            case let .sidebar(.delegate(.dropItemsToSidebarFolder(providers, targetURL))):
                .send(.content(.delegate(.dropItemsToSidebarFolder(
                    providers: providers,
                    targetURL: targetURL,
                ))))

            case let .sidebar(.delegate(.dropItemsToTag(providers, tagName))):
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
