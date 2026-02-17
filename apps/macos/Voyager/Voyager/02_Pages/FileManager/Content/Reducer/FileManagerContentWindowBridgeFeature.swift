import ComposableArchitecture
import Foundation
import SwiftUI

@Reducer
struct FileManagerContentWindowBridgeFeature {
    typealias State = FileManagerContentState
    typealias Action = FileManagerContentAction

    @Dependency(\.fileManagerWindowClient)
    var fileManagerWindowClient
    @Dependency(\.userDefaultsClient)
    var userDefaultsClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .handleKeyCommand(command):
                return FileManagerContentKeyCommandHandler.effect(for: command, state: state)

            case let .openPathInNewWindow(path):
                return .run { [fileManagerWindowClient] _ in
                    await fileManagerWindowClient.openPathInNewWindow(path)
                }

            case .emptyTrashCompleted:
                return .send(.closeWindow)

            case let .changeLayout(layout):
                state.viewLayout = layout
                state.syncComposerCollectionState()
                userDefaultsClient.setString(layout.rawValue, SettingsKeys.viewLayout)
                return .none

            case let .saveScrollOffset(offset, forPath: path):
                state.navigation.scrollPositions[path] = offset
                return .none

            default:
                return .none
            }
        }
    }
}
