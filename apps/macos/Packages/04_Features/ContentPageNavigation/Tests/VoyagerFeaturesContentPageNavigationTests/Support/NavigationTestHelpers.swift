import ComposableArchitecture
@testable import VoyagerFeaturesContentPageNavigation

@MainActor
func makeNavigationStore(
    seedPath: String,
) -> TestStore<ContentPageNavigationFeature.State, ContentPageNavigationFeature.Action> {
    var state = ContentPageNavigationFeature.State()
    state.seedInitialFolderPath(seedPath)
    return TestStore(initialState: state) {
        ContentPageNavigationFeature()
    }
}
