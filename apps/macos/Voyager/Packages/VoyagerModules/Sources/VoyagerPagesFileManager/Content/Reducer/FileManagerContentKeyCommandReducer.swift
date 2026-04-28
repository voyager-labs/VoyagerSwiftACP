import ComposableArchitecture
import Foundation

import VoyagerEntitiesEntry
import VoyagerFeaturesEntryOperations

@Reducer
public struct FileManagerContentKeyCommandReducer {
    public typealias State = FileManagerContentState
    public typealias Action = FileManagerContentAction

    public init() {}

    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .view(.handleKeyCommand(command)):
                FileManagerContentKeyCommandHandler.effect(for: command, state: state)

            default:
                .none
            }
        }
    }
}
