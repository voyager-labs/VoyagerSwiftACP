import ComposableArchitecture
import Foundation

@Reducer
struct ComposerFeature {
    @ObservableState
    struct State: Equatable {
        var isPresented: Bool = false
        var text: String = ""
        var scopes: [String] = []
    }

    enum Action: Sendable {
        case setPresented(Bool)
        case setText(String)
        case addScope(path: String)
        case removeScope(path: String)
        case updateScope(oldPath: String, newPath: String)
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .setPresented(isPresented):
                state.isPresented = isPresented
                if !isPresented {
                    state.text = ""
                }
                return .none

            case let .setText(text):
                state.text = text
                return .none

            case let .addScope(path):
                if !state.scopes.contains(path) {
                    state.scopes.append(path)
                }
                return .none

            case let .removeScope(path):
                state.scopes.removeAll { $0 == path }
                return .none

            case let .updateScope(oldPath, newPath):
                if let index = state.scopes.firstIndex(of: oldPath) {
                    state.scopes[index] = newPath
                }
                return .none
            }
        }
    }
}
