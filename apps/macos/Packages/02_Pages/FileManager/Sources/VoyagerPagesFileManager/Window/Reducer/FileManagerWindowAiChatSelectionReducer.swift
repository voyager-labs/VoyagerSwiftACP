import ComposableArchitecture
import VoyagerFeaturesAiChat

@Reducer
struct FileManagerWindowAiChatSelectionReducer {
    typealias State = FileManagerWindowState
    typealias Action = FileManagerWindowAction

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .tabContent(tabID, .aiChat(.selectedModelChanged)),
                 let .tabContent(tabID, .aiChat(.selectedThinkingChanged)):
                guard let contentState = fileManagerContentState(for: tabID, state: state) else { return .none }
                state.lastExplicitAiChatSelection = selection(from: contentState.aiChat)

            case .inspector(.aiChat(.selectedModelChanged)),
                 .inspector(.aiChat(.selectedThinkingChanged)):
                state.lastExplicitAiChatSelection = selection(from: state.inspector.aiChat)

            default:
                break
            }
            return .none
        }
    }

    private func selection(from state: AiChatFeature.State) -> FileManagerAiChatSelection? {
        state.selectedModelHandle.map {
            FileManagerAiChatSelection(modelHandle: $0, thinking: state.selectedThinking)
        }
    }
}
