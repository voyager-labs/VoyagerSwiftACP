import ComposableArchitecture
import Foundation

func applyCollectionNavigationState(
    _ navigation: ContentPageCollectionNavigation,
    state: inout FileManagerWindowState,
) {
    let openedURL: URL?
    let openedName: String?
    switch navigation.kind {
    case .temporary:
        openedURL = nil
        openedName = nil
    case let .file(url, name):
        openedURL = url
        openedName = name
    }

    let payload = CollectionDocumentSessionFeature.navigationStatePayload(
        state: &state.content.collectionSession,
        context: navigation.context,
        compatibility: navigation.compatibility,
        openedURL: openedURL,
        openedName: openedName,
    )

    state.content.composer.isPresented = false
    state.content.collectionContext = payload.context
    state.content.entryViewLayout.entryArrangements.updateSortKey(navigation.sortKey)
    state.content.entryViewLayout.entryArrangements.updateSortOrder(navigation.sortOrder)
    state.content.entryViewLayout.mode = navigation.viewLayout
    state.content.composer.applyCollectionNavigationComposerPayload(payload)

    state.content.syncComposerCollectionState()
}

func handleNavigationDelegate(
    _ delegateAction: ContentPageNavigationAction.Delegate,
    state: inout FileManagerWindowState,
    computerName: String,
) -> Effect<FileManagerWindowAction> {
    switch delegateAction {
    case let .navigateToState(navigationState):
        syncSidebarSelection(state: &state, computerName: computerName)
        return handleNavigateToState(navigationState, state: &state)

    case let .logDAUNavigation(previous, next):
        logContentPageNavigationDAUIfNeeded(previous: previous, next: next)
        return .none

    case .resetComposer:
        let exitEffect = exitCollectionMode(
            state: &state.content,
            computerName: computerName,
        )
        state.content.resetComposer()
        return exitEffect.map(FileManagerWindowAction.content)
    }
}
