import ComposableArchitecture
import Foundation

@Reducer
struct FileManagerContentKeyCommandReducer {
    typealias State = FileManagerContentState
    typealias Action = FileManagerContentAction

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .view(.handleKeyCommand(command)):
                FileManagerContentKeyCommandHandler.effect(for: command, state: state)

            case let .view(.handleTextInput(text)):
                FileManagerContentKeyCommandHandler.typeScrollEffect(for: text, state: state)

            default:
                .none
            }
        }
    }
}
