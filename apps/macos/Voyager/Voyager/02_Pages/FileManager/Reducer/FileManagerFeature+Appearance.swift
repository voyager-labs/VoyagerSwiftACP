import ComposableArchitecture

extension FileManagerFeature {
    static func applyShowHiddenFilesChange(state: inout State) -> Effect<Action> {
        switch state.navigationState {
        case .recents:
            .merge(
                .send(.entries(.setShowHidden(state.showHiddenFiles))),
                .send(.entries(.loadRecentItems(showHidden: state.showHiddenFiles))),
            )
        case let .tags(tagName):
            .merge(
                .send(.entries(.setShowHidden(state.showHiddenFiles))),
                .send(.entries(.loadTagItems(tagName: tagName, showHidden: state.showHiddenFiles))),
            )
        case .computer:
            .merge(
                .send(.entries(.setShowHidden(state.showHiddenFiles))),
                .send(.entries(.loadComputerItems)),
            )
        case .folder, .collection:
            .merge(
                .send(.entries(.setShowHidden(state.showHiddenFiles))),
                .send(.entries(.loadItems(path: state.currentPath))),
            )
        }
    }
}
