import ComposableArchitecture
import Foundation
import VoyagerEntitiesCollection
import VoyagerFeaturesComposer
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryArrangements
import VoyagerFeaturesEntryOperations
import VoyagerShared

enum FileManagerContentComposerCoordinator {
    struct Dependencies {
        let collectionAlertClient: CollectionAlertClient
        let metricsClient: MetricsClient
        let searchClient: SearchClient
    }

    private static let composerOpenMetricName = "voyager_composer_open"

    static func reduce(
        _ action: ComposerFeature.Action,
        state: inout FileManagerContentState,
        dependencies: Dependencies,
    ) -> Effect<FileManagerContentAction> {
        if let effect = handleComposerLifecycleAction(action, state: &state, dependencies: dependencies) {
            return effect
        }

        if let effect = handleComposerDelegateAction(action) {
            return effect
        }

        return .none
    }

    private static func handleComposerLifecycleAction(
        _ action: ComposerFeature.Action,
        state: inout FileManagerContentState,
        dependencies: Dependencies,
    ) -> Effect<FileManagerContentAction>? {
        if let effect = handleComposerSearchResponseAction(action, state: &state, dependencies: dependencies) {
            return effect
        }

        switch action {
        case let .view(.setPresented(isPresented)):
            return handleSetPresented(isPresented, state: &state, dependencies: dependencies)

        case .view(.applyFilters):
            guard state.composer.conditions.contains(where: \.isSearchReady) else {
                return .none
            }
            return .send(.composer(.setLoadingFilters(true)))

        case let .view(.setText(text)):
            return handleSetText(text, state: &state, dependencies: dependencies)

        case .view(.cancelSearch):
            return .concatenate(
                .send(.composer(.clearPendingSearchQuery)),
                .send(.collection(.openSearchPresentationCancelled)),
            )

        case .view(.clearAll):
            if state.isCollectionMode {
                return .concatenate(
                    .send(.composer(.clearPendingSearchQuery)),
                    .send(.collection(.temporaryContextResetRequested(rootScopePath: ComposerScopeUtils
                            .rootScopePath))),
                )
            }
            return .send(.internal(.exitCollectionMode))

        default:
            return nil
        }
    }

    private static func handleComposerDelegateAction(
        _ action: ComposerFeature.Action,
    ) -> Effect<FileManagerContentAction>? {
        guard case let .delegate(delegateAction) = action else {
            return nil
        }
        switch delegateAction {
        case let .saveRequested(payload):
            return .send(.collection(.saveRequested(payload)))
        case let .saveToExisting(payload, url):
            return .send(.collection(.saveToExisting(payload, url)))
        }
    }

    private static func handleSetPresented(
        _ isPresented: Bool,
        state: inout FileManagerContentState,
        dependencies: Dependencies,
    ) -> Effect<FileManagerContentAction> {
        guard isPresented else {
            if state.composer.isFilteringInFlight {
                return .none
            }

            let shouldCommitScopeEditorChanges = state.composer.scopeEditor.isPresented
                && state.composer.scopeEditor.hasPendingScopeRuleChanges
                && state.composer.shouldAutoApplyScopeChange

            if shouldCommitScopeEditorChanges {
                return .none
            }

            state.composer.pendingSearchQuery = nil
            return .send(.collection(.openSearchPresentationCancelled))
        }

        dependencies.metricsClient.logMetric(
            composerOpenMetricName,
            1,
            nil,
        )

        let warmupEffect = warmUpAIModelCatalogEffect(searchClient: dependencies.searchClient)

        guard case let .folder(path) = state.navigation.navigationState else {
            return warmupEffect
        }

        if state.composer.scopeEditor.selection.isRootOnly,
           state.composer.conditions.isEmpty,
           state.composer.text.isEmpty
        {
            return .merge(
                .send(.composer(.scopeEditorSeedCurrentPath(path))),
                warmupEffect,
            )
        }

        return warmupEffect
    }

    private static func warmUpAIModelCatalogEffect(
        searchClient: SearchClient,
    ) -> Effect<FileManagerContentAction> {
        .run { _ in
            try? await searchClient.warmUpAIModelCatalog()
        }
    }

    private static func handleSetText(
        _ text: String,
        state: inout FileManagerContentState,
        dependencies _: Dependencies,
    ) -> Effect<FileManagerContentAction> {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        state.composer.pendingSearchQuery = query.isEmpty ? nil : query
        if query.isEmpty, state.composer.conditions.isEmpty, state.composer.isSemanticallyRootOnly {
            return .concatenate(
                .send(.composer(.setPendingSearchQuery(nil))),
                .send(.internal(.exitCollectionMode)),
            )
        }
        return .send(.composer(.setPendingSearchQuery(query.isEmpty ? nil : query)))
    }
}
