import ComposableArchitecture
import Foundation
import VoyagerEntitiesAppPreferences
import VoyagerEntitiesCollection
import VoyagerFeaturesComposer
import VoyagerFeaturesEntryOperations
import VoyagerShared
import VoyagerWidgetsEntryViewLayout

@Reducer
struct FileManagerContentComposerReducer {
    typealias State = FileManagerContentState
    typealias Action = FileManagerContentAction

    @Dependency(\.collectionAlertClient)
    private var collectionAlertClient
    @Dependency(\.userDefaultsClient)
    private var userDefaultsClient
    @Dependency(\.metricsClient)
    private var metricsClient
    @Dependency(\.searchClient)
    private var searchClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            if case let .composer(composerAction) = action {
                return FileManagerContentComposerCoordinator.reduce(
                    composerAction,
                    state: &state,
                    dependencies: .init(
                        collectionAlertClient: collectionAlertClient,
                        metricsClient: metricsClient,
                        searchClient: searchClient,
                    ),
                )
            }

            switch action {
            case .view(.refreshStaleCollection):
                return handleRefreshStaleCollection(state: &state)

            case let .view(.changeLayout(layout)):
                return handleChangeLayout(layout: layout, state: &state)

            case .internal(.resetComposer):
                return resetComposerAndSyncEffect(state)

            case .internal(.resetComposerAfterDirectoryNavigation):
                return handleResetComposerAfterDirectoryNavigation(state: &state)

            default:
                return .none
            }
        }
    }

    // MARK: - Composer Query Lifecycle

    private func handleRefreshStaleCollection(state: inout State) -> Effect<Action> {
        guard state.collection.refreshBlockingReason(
            isCollectionMode: state.isCollectionMode,
            isDirty: state.collection.isDirty,
            isSearching: state.composer.isCollectionSearching
                || state.entryViewLayout.isCollectionContentLoading,
        ) == nil else {
            return .none
        }
        guard let collectionContext = state.collection.collectionContext else {
            return .none
        }
        state.suppressAutomaticRefreshFeedback = false
        let trimmedQuery = collectionContext
            .query
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedQuery.isEmpty {
            let hasSearchReadyCondition = collectionContext.conditions.contains(where: \.isExecutionReady)
            if hasSearchReadyCondition {
                state.composer.applyCollectionDraftRestorePayload(.init(
                    context: collectionContext,
                    openedURL: state.collection.collectionSession.document?.url,
                ))
            }
            return .concatenate(
                .send(.collection(.refreshRequested)),
                .send(.composer(.applyFilters)),
                hasSearchReadyCondition ? .none : .send(.collection(.refreshFailed)),
            )
        }

        return .concatenate(
            .send(.collection(.refreshRequested)),
            .send(.composer(.setText(trimmedQuery))),
            .send(.composer(.submit)),
        )
    }

    // MARK: - Layout Change → Composer Sync

    private func handleChangeLayout(layout: EntryViewLayoutState.Mode, state: inout State) -> Effect<Action> {
        let currentMode = state.entryViewLayout.mode
        let isModeChanging = currentMode != layout
        let hasActiveRename = state.entryViewLayout.entryOperations.renamingItemId != nil

        state.entryViewLayout.mode = layout
        userDefaultsClient.setString(layout.rawValue, SettingsKeys.viewLayout)
        return .concatenate(
            syncComposerCollectionStateEffect(state),
            isModeChanging && hasActiveRename
                ? .send(.entryViewLayout(.entryOperations(.edit(.cancelRename))))
                : .none,
        )
    }

    // MARK: - Composer Reset Lifecycle

    private func handleResetComposerAfterDirectoryNavigation(state: inout State) -> Effect<Action> {
        guard state.resetComposerOnNextDirectoryNavigation else {
            return .none
        }
        state.resetComposerOnNextDirectoryNavigation = false
        return resetComposerAndSyncEffect(state)
    }

    // MARK: - Effect Helpers

    private func syncComposerCollectionStateEffect(_ state: State) -> Effect<Action> {
        .send(.composer(.syncCollectionState(
            context: state.collection.collectionContext,
            url: state.collection.collectionSession.document?.url,
            compatibility: state.collection.collectionSession.document?.compatibility,
            isCollectionMode: state.isCollectionMode,
        )))
    }

    private func resetComposerAndSyncEffect(_ state: State) -> Effect<Action> {
        .send(.composer(.resetComposerAndSync(
            context: state.collection.collectionContext,
            url: state.collection.collectionSession.document?.url,
            compatibility: state.collection.collectionSession.document?.compatibility,
            isCollectionMode: state.isCollectionMode,
        )))
    }
}
