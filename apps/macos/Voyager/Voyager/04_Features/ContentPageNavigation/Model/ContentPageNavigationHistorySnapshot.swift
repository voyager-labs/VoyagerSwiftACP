struct ContentPageNavigationHistorySnapshot: Equatable {
    let navigationState: ContentPageNavigationUtils.NavigationState
    let composerSnapshot: ComposerFeature.State
}
