import VoyagerFeaturesContentPageNavigation

extension FileManagerContentFeature {
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
}
