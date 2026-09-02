import ComposableArchitecture
import VoyagerFeaturesContentPageNavigation

extension FileManagerContentFeature {
    func handleProductBrowsingNavigation(
        _ action: ContentPageNavigationAction.View,
        state: inout State,
    ) -> Effect<Action> {
        guard shouldBeginProductBrowsing(action, navigation: state.navigation) else {
            state.pendingProductBrowsingSource = nil
            return .none
        }
        switch action {
        case .navigateToPath,
             .goBack,
             .goForward,
             .goToHistoryIndex,
             .goToEnclosingDirectory,
             .showRecents,
             .showComputer,
             .showTag:
            state.pendingProductBrowsingSource = .fileManagerContent
        default:
            state.pendingProductBrowsingSource = nil
        }
        return .none
    }

    func shouldBeginProductBrowsing(
        _ action: ContentPageNavigationAction.View,
        navigation: ContentPageNavigationState,
    ) -> Bool {
        switch action {
        case let .navigateToPath(path):
            navigation.navigationState != .folder(path)
        case .goBack, .goForward, .goToHistoryIndex, .goToEnclosingDirectory:
            shouldBeginHistoryBrowsing(action, navigation: navigation)
        case .showRecents, .showComputer, .showTag:
            shouldBeginCollectionBrowsing(action, navigation: navigation)
        default:
            false
        }
    }

    private func shouldBeginHistoryBrowsing(
        _ action: ContentPageNavigationAction.View,
        navigation: ContentPageNavigationState,
    ) -> Bool {
        switch action {
        case .goBack:
            !navigation.backHistory.isEmpty
        case .goForward:
            !navigation.forwardHistory.isEmpty
        case let .goToHistoryIndex(index, isBackHistory):
            (isBackHistory ? navigation.backHistory : navigation.forwardHistory).indices.contains(index)
        case .goToEnclosingDirectory:
            navigation.enclosingDirectoryPath != nil
        default:
            false
        }
    }

    private func shouldBeginCollectionBrowsing(
        _ action: ContentPageNavigationAction.View,
        navigation: ContentPageNavigationState,
    ) -> Bool {
        switch (action, navigation.navigationState) {
        case (.showRecents, .recents), (.showComputer, .computer):
            false
        case let (.showTag(tagName), .tags(currentTagName)):
            tagName != currentTagName
        default:
            true
        }
    }

    static func isRootCompletion(_ action: Action, state: inout State) -> Bool {
        switch action {
        case let .entryViewLayout(.entryOperations(.loading(.itemsLoaded(generation, _)))):
            guard generation == state.entryViewLayout.entryOperations.loadingContext.generation else { return false }
            return true
        case let .entryViewLayout(.entryOperations(.loading(.streamEvent(streamEvent)))):
            guard case .coreFinished = streamEvent.event,
                  state.entryViewLayout.entryOperations.loadingContext.acceptedCoreFinishedGeneration == streamEvent
                  .generation,
                  !state.entryViewLayout.entryOperations.loadingContext.isBufferingPreservedDirectoryReload
            else { return false }
            state.entryViewLayout.entryOperations.loadingContext.acceptedCoreFinishedGeneration = nil
            return true
        case let .entryViewLayout(.entryOperations(.loading(.streamFinished(generation)))):
            guard state.entryViewLayout.entryOperations.loadingContext.acceptedCoreFinishedGeneration == generation
            else { return false }
            state.entryViewLayout.entryOperations.loadingContext.acceptedCoreFinishedGeneration = nil
            return true
        default:
            return false
        }
    }
}
