import ComposableArchitecture
import Foundation
import VoyagerShared

@Reducer
struct CollectionDocumentSessionFeature {
    typealias State = CollectionDocumentSessionState
    typealias Action = CollectionDocumentSessionAction

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .openRequested(url):
                state.isOpening = true
                return .send(.delegate(.loadFile(url)))

            case let .openLoaded(url: url, file: file):
                state.isOpening = false
                state.openedURL = url
                state.openedName = file.name
                state.baseline = .init(context: .init(
                    query: file.query,
                    scopes: file.scopes,
                    conditions: [],
                ))
                return .none

            case .openCancelled:
                state.isOpening = false
                return .none

            case let .draftRestoreRequested(baseline, isCollectionMode, isDirty, openedURL):
                guard let baseline, isCollectionMode, isDirty else {
                    return .none
                }

                return .send(.delegate(.restoreDraft(.init(
                    context: baseline.context,
                    openedURL: openedURL,
                ))))

            case let .refreshRequested(blockingReason, query):
                guard blockingReason == nil else {
                    return .none
                }
                state.beginRefreshingStaleSession()
                let trimmedQuery = query?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let trigger: CollectionRefreshTriggerPayload = trimmedQuery.isEmpty
                    ? .applyFilters
                    : .submit(trimmedQuery)
                return .send(.delegate(.triggerRefresh(trigger)))

            case .delegate:
                return .none
            }
        }
    }
}

extension CollectionDocumentSessionFeature {
    static func refreshBlockingReason(
        session: CollectionDocumentSessionState,
        isCollectionMode: Bool,
        isDirty: Bool,
        isSearching: Bool,
        hasCollectionContext: Bool,
    ) -> CollectionSessionRefreshBlockingReason? {
        if !isCollectionMode {
            return .notInCollectionMode
        }
        if !session.isStale {
            return .notStale
        }
        if isDirty {
            return .dirtyCollection
        }
        if isSearching {
            return .searchInFlight
        }
        if session.isRefreshingHydratedSnapshot {
            return .refreshInFlight
        }
        if session.isWritingBackRefreshedSnapshot {
            return .writeBackInFlight
        }
        if session.openedURL == nil {
            return .missingOpenedURL
        }
        if !hasCollectionContext {
            return .missingCollectionContext
        }
        if session.baseline == nil {
            return .missingBaseline
        }

        return nil
    }

    static func restoreDraftPayload(
        state: inout CollectionDocumentSessionState,
        baseline: CollectionBaseline?,
        isCollectionMode: Bool,
        isDirty: Bool,
    ) -> CollectionDraftRestorePayload? {
        guard let baseline, isCollectionMode, isDirty else {
            return nil
        }

        return .init(
            context: baseline.context,
            openedURL: state.openedURL,
        )
    }

    static func refreshIntentTrigger(
        state: inout CollectionDocumentSessionState,
        isCollectionMode: Bool,
        isDirty: Bool,
        isSearching: Bool,
        hasCollectionContext: Bool,
        query: String?,
    ) -> CollectionRefreshTriggerPayload? {
        let blockingReason = refreshBlockingReason(
            session: state,
            isCollectionMode: isCollectionMode,
            isDirty: isDirty,
            isSearching: isSearching,
            hasCollectionContext: hasCollectionContext,
        )
        guard blockingReason == nil else {
            return nil
        }
        state.beginRefreshingStaleSession()
        let trimmedQuery = query?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedQuery.isEmpty ? .applyFilters : .submit(trimmedQuery)
    }

    static func isEmptyCollectionDefinition(
        file: VoyagerCollectionFile,
        resolved: AppliedFiltersUtils.ResolutionResult,
    ) -> Bool {
        file.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && resolved.scopes.isEmpty
            && resolved.conditions.isEmpty
    }

    static func prepareOpenIntent(
        state: inout CollectionDocumentSessionState,
        url: URL,
        reopenContext: CollectionContext?,
        isAlreadyStale: Bool,
    ) {
        state.captureReopenContext(reopenContext)
        state.prepareForOpeningCollection(at: url)
        if isAlreadyStale {
            state.isStale = true
            state.staleReason = .invalidatedLocally
        }
    }

    static func loadedOpenPayload(
        state: inout CollectionDocumentSessionState,
        file: VoyagerCollectionFile,
        resolved: AppliedFiltersUtils.ResolutionResult,
        isStale: Bool,
        compatibility: CollectionFileCompatibilityMetadata?,
    ) -> CollectionOpenRestorationPayload {
        let trimmedQuery = file.query.trimmingCharacters(in: .whitespacesAndNewlines)
        let loadedContext = CollectionContext(
            query: trimmedQuery,
            scopes: resolved.scopes,
            conditions: resolved.conditions,
        )
        let restoredContext = if isStale,
                                 let reopenContext = state.reopenContext
        {
            reopenContext
        } else {
            loadedContext
        }

        let kind: CollectionSessionPhase.OpenKind = file.snapshotMeta == nil ? .definition : .hydratedSnapshot
        state.baseline = CollectionBaseline(context: restoredContext)
        state.openedCompatibility = compatibility
        state.completeOpen(kind: kind, isStale: isStale, compatibility: compatibility)

        let hydratedOpenPayload: CollectionHydratedOpenPayload?
        if let response = CollectionSnapshotHydration.syntheticSearchResponse(for: file),
           let items = response.items
        {
            let snapshotPaths = items.compactMap { item -> String? in
                guard case let .string(path) = item else {
                    return nil
                }
                return path
            }

            if snapshotPaths.count == items.count {
                hydratedOpenPayload = CollectionHydratedOpenPayload(
                    lastFiltersResponse: response,
                    lastSearchResponse: restoredContext.query.isEmpty ? nil : response,
                    snapshotPaths: snapshotPaths,
                )
            } else {
                hydratedOpenPayload = nil
            }
        } else {
            hydratedOpenPayload = nil
        }

        return CollectionOpenRestorationPayload(
            context: restoredContext,
            compatibility: compatibility,
            shouldRestoreStaleNavigation: isStale,
            queryTrigger: (!isStale && kind == .definition) ? queryTriggerPayload(query: trimmedQuery) : nil,
            hydratedOpenPayload: hydratedOpenPayload,
            isEmptyDefinition: isEmptyCollectionDefinition(file: file, resolved: resolved),
            unsupportedFilterKeys: resolved.unknownKeys,
        )
    }

    static func writeBackSuccessPayload(
        state: inout CollectionDocumentSessionState,
        completion: CollectionSaveCompletion,
        currentCollectionContext: CollectionContext?,
    ) -> CollectionWriteBackSuccessPayload {
        let url = completion.url
        let previousURL = state.openedURL
        let shouldAppendHistory = previousURL?.path != url.path
        let compatibility = VoyagerCollectionFileCompatibilityOwner.compatibilityForCurrentFile(completion.file)

        if completion.file.snapshotMeta != nil,
           state.didHydrateSnapshotOnOpen,
           previousURL?.standardizedFileURL.path == url.standardizedFileURL.path
        {
            let refreshedAt = completion.file.snapshotMeta?.capturedAt ?? completion.file.updatedAt
            state.completeWriteBackSuccess(at: refreshedAt)
        }

        state.openedURL = url
        state.openedName = url.deletingPathExtension().lastPathComponent
        state.originURL = url
        state.baseline = currentCollectionContext.map(CollectionBaseline.init(context:))
        state.openedCompatibility = compatibility

        return CollectionWriteBackSuccessPayload(
            url: url,
            name: state.openedName ?? url.deletingPathExtension().lastPathComponent,
            baseline: state.baseline,
            compatibility: compatibility,
            shouldAppendHistory: shouldAppendHistory,
        )
    }

    static func navigationStatePayload(
        state: inout CollectionDocumentSessionState,
        context: CollectionContext,
        compatibility: CollectionFileCompatibilityMetadata?,
        openedURL: URL?,
        openedName: String?,
    ) -> CollectionNavigationStatePayload {
        state.openedCompatibility = compatibility

        if let openedURL, let openedName {
            state.openedURL = openedURL
            state.openedName = openedName
            state.originURL = openedURL
            state.baseline = CollectionBaseline(context: context)
        } else {
            state.openedURL = nil
            state.openedName = nil
            state.originURL = nil
            state.baseline = nil
        }

        return CollectionNavigationStatePayload(
            context: context,
            compatibility: state.openedCompatibility,
            openedURL: state.openedURL,
            openedName: state.openedName,
            originURL: state.originURL,
            baseline: state.baseline,
            pendingSearchQuery: context.query.isEmpty ? nil : context.query,
            composerText: context.query,
            scopes: context.scopes,
            conditions: context.conditions,
        )
    }

    static func searchSuccessPayload(
        state: inout CollectionDocumentSessionState,
        query: String,
        scopes: [String],
        conditions: [Condition],
        previousNavigationIsCollection: Bool,
        nextNavigationDiffers: Bool,
    ) -> CollectionSearchResultPayload {
        let wasOpeningCollectionFile = state.isOpening
        state.isOpening = false

        let context = CollectionContext(
            query: query,
            scopes: scopes,
            conditions: conditions,
        )

        if wasOpeningCollectionFile, state.openedURL != nil {
            state.baseline = CollectionBaseline(context: context)
        }

        return CollectionSearchResultPayload(
            context: context,
            shouldAppendHistory: !wasOpeningCollectionFile && nextNavigationDiffers && !previousNavigationIsCollection,
            shouldLogDAU: !wasOpeningCollectionFile && !previousNavigationIsCollection,
        )
    }

    static func searchFailurePayload(
        state: inout CollectionDocumentSessionState,
    ) -> CollectionSearchFailurePayload {
        guard state.isOpening else {
            return .init(shouldResetSession: false)
        }
        state = .init()
        return .init(shouldResetSession: true)
    }

    static func refreshResponsePayload(
        state: inout CollectionDocumentSessionState,
        wasDirtyBeforeApplyingResponse: Bool,
        writeBackAllowed: Bool,
    ) -> CollectionRefreshResponsePayload {
        guard state.isRefreshingHydratedSnapshot else {
            return .init(shouldWriteBack: false, shouldKeepStale: false)
        }

        guard !wasDirtyBeforeApplyingResponse, writeBackAllowed else {
            state.finishRefreshWithoutWriteBack()
            return .init(shouldWriteBack: false, shouldKeepStale: true)
        }

        state.beginWriteBackAfterRefresh()
        return .init(shouldWriteBack: true, shouldKeepStale: true)
    }

    static func externalInvalidationPayload(
        state: inout CollectionDocumentSessionState,
        affectsCollection: Bool,
    ) -> CollectionExternalInvalidationPayload {
        guard affectsCollection else {
            return .init(
                isStale: state.isStale,
                staleReason: state.staleReason,
                lastRefreshAt: state.lastRefreshAt,
            )
        }

        state.isStale = true
        state.lastRefreshAt = nil
        if state.staleReason == nil {
            state.staleReason = .invalidatedLocally
        }

        return .init(
            isStale: state.isStale,
            staleReason: state.staleReason,
            lastRefreshAt: state.lastRefreshAt,
        )
    }

    static func resetPayload(
        state: inout CollectionDocumentSessionState,
    ) -> CollectionSessionResetPayload {
        state = .init()
        return .init(shouldReset: true)
    }

    static func openCancellationPayload(
        state: inout CollectionDocumentSessionState,
    ) -> CollectionOpenCancellationPayload {
        state.isOpening = false
        state.openedName = nil
        return .init(
            pendingSearchQuery: nil,
            isOpening: state.isOpening,
            openedName: state.openedName,
        )
    }

    static func queryTriggerPayload(
        query: String,
    ) -> CollectionQueryTriggerPayload {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedQuery.isEmpty ? .applyFilters : .submit(trimmedQuery)
    }
}
