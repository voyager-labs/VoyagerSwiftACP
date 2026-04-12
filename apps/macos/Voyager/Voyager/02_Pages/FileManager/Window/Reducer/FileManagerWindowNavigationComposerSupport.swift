import ComposableArchitecture
import Foundation

func applyCollectionNavigationState(
    _ navigation: ContentPageCollectionNavigation,
    state: inout FileManagerWindowState,
) {
    state.content.composer.isPresented = false
    state.content.collectionContext = navigation.context
    state.content.composer.pendingSearchQuery = navigation.context.query.isEmpty ? nil : navigation.context.query
    state.content.entryViewLayout.entryArrangements.updateSortKey(navigation.sortKey)
    state.content.entryViewLayout.entryArrangements.updateSortOrder(navigation.sortOrder)
    state.content.entryViewLayout.mode = navigation.viewLayout

    switch navigation.kind {
    case .temporary:
        state.content.collectionSession.openedName = nil
        state.content.collectionSession.openedURL = nil
        state.content.collectionSession.originURL = nil
        state.content.collectionSession.baseline = nil
    case let .file(url, name):
        state.content.collectionSession.openedName = name
        state.content.collectionSession.openedURL = url
        state.content.collectionSession.originURL = url
        state.content.collectionSession.baseline = CollectionBaseline(context: navigation.context)
    }

    state.content.syncComposerCollectionState()
}

func configureCollectionNavigationComposer(
    _ navigation: ContentPageCollectionNavigation,
    state: inout FileManagerWindowState,
) {
    state.content.composer.text = {
        if case .file = navigation.kind { return "" }
        return navigation.context.query
    }()
    state.content.composer.scopes = navigation.context.scopes
    state.content.composer.conditions = navigation.context.conditions
    state.content.composer.propertyPicker = ConditionPropertyPickerFeature.State()
    state.content.composer.operatorPicker = OperatorPickerFeature.State()
    state.content.composer.valuePicker = ValuePickerFeature.State()
    state.content.composer.clearHistory()
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
