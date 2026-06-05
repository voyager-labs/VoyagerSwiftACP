import ComposableArchitecture
import Foundation
import VoyagerShared

@Reducer
public struct CollectionFeature {
    public typealias State = CollectionState
    public typealias Action = CollectionAction

    public init() {}

    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .openRequested(url, reopenContext, isAlreadyStale):
                state.collectionSession.captureReopenContext(reopenContext)
                state.collectionSession.prepareForOpeningCollection(at: url)
                if isAlreadyStale {
                    state.collectionSession.markInvalidatedLocally()
                }
                return .none

            case .draftDiscardRequested:
                guard let baseline = state.collectionSession.metadata.baseline else {
                    return .none
                }
                state.collectionContext = baseline.context
                return .send(.delegate(.draftRestorePrepared(.init(
                    context: baseline.context,
                    openedURL: state.collectionSession.document?.url,
                ))))

            case .refreshRequested:
                state.collectionSession.beginRefreshingStaleSession()
                return .none

            case .openSearchPresentationCancelled:
                state.cancelOpenSearchPresentation()
                return .none

            case let .temporaryContextResetRequested(rootScopePath):
                state.resetToTemporaryCollectionContext(rootScopePath: rootScopePath)
                return .none

            case let .navigationStateApplied(payload):
                state.applyNavigationStatePayload(payload)
                return .none

            case let .refreshResponseReceived(_, wasDirtyBeforeApplyingResponse):
                _ = state.applyRefreshResponse(
                    wasDirtyBeforeApplyingResponse: wasDirtyBeforeApplyingResponse,
                )
                return .none

            case .refreshFailed:
                guard state.collectionSession.phase.isInflightRefresh else {
                    return .none
                }
                state.collectionSession.failRefreshOrWriteBack()
                return .none

            case let .externalPathsChanged(paths):
                let affectsCollection: Bool = if let context = state.collectionContext {
                    collectionChangeIsRelevant(
                        changedPaths: paths,
                        scopes: context.scopes,
                        excludedScopes: context.excludedScopes,
                        includeSubfolders: context.includeSubfolders,
                    )
                } else {
                    !paths.isEmpty
                }
                guard affectsCollection else {
                    return .none
                }
                state.collectionSession.markInvalidatedLocally()
                return .none

            case let .searchSucceeded(context, _, previousNavigationIsCollection, nextNavigationDiffers):
                let wasOpeningCollectionFile = state.collectionSession.phase.isOpening
                state.collectionSession.finishOpeningTransition()
                state.collectionContext = context
                if wasOpeningCollectionFile, state.collectionSession.document?.url != nil {
                    state.collectionSession.metadata.baseline = .init(context: context)
                }
                return .send(.delegate(.searchResultPrepared(.init(
                    navigation: state.makeNavigationPresentationPayload(context: context),
                    shouldAppendHistory: !wasOpeningCollectionFile && nextNavigationDiffers &&
                        !previousNavigationIsCollection,
                    shouldLogDAU: !wasOpeningCollectionFile && !previousNavigationIsCollection,
                ))))

            case .searchFailed:
                if state.collectionSession.phase.isOpening {
                    state.resetSession()
                }
                return .none

            case .sessionResetRequested:
                state.resetSession()
                return .none

            case let .writeBackCompleted(completion):
                let payload = state.completeWriteBack(completion)
                return .send(.delegate(.writeBackNavigationPrepared(payload)))

            case .writeBackFailed:
                state.collectionSession.failRefreshOrWriteBack()
                return .none

            case .delegate,
                 .saveRequested,
                 .saveToExisting,
                 .savePanelResponse,
                 .saveCompleted:
                return .none
            }
        }
        CollectionSavePipelineReducer()
    }
}
