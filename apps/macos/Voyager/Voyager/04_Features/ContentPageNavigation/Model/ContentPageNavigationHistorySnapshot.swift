struct ContentPageNavigationHistorySnapshot: Equatable {
    let navigationState: ContentPageNavigationRoute
    let composerSnapshot: ComposerFeature.State
}
