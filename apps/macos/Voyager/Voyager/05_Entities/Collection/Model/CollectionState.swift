import ComposableArchitecture
import Foundation
import VoyagerShared

@ObservableState
struct CollectionState: Equatable {
    var pendingSave: CollectionSaveSnapshot?
    var isSaving: Bool = false

    var collectionSession: CollectionDocumentSessionState = .init()
    var collectionContext: CollectionContext?
}

extension CollectionState {
    mutating func cancelOpenSearchPresentation() {
        collectionSession.finishOpeningTransition()
        collectionSession.document = nil
    }

    mutating func resetSession() {
        collectionSession = .init()
        collectionContext = nil
    }

    mutating func resetToTemporaryCollectionContext(rootScopePath: String) {
        collectionContext = CollectionContext(
            query: "",
            scopes: [rootScopePath],
            conditions: [],
        )
    }

    mutating func applyRefreshResponse(wasDirtyBeforeApplyingResponse: Bool) -> Bool {
        let writeBackAllowed = collectionSession.document?.compatibility?.writeBackAllowed != false
        guard collectionSession.phase.inflightStatus == .refreshingHydratedSnapshot else {
            return false
        }
        if wasDirtyBeforeApplyingResponse || !writeBackAllowed {
            collectionSession.finishRefreshWithoutWriteBack()
            return false
        }
        collectionSession.beginWriteBackAfterRefresh()
        return true
    }

    func refreshBlockingReason(
        isCollectionMode: Bool,
        isDirty: Bool,
        isSearching: Bool,
    ) -> CollectionSessionRefreshBlockingReason? {
        if !isCollectionMode {
            return .notInCollectionMode
        }
        if !collectionSession.phase.isStale {
            return .notStale
        }
        if isDirty {
            return .dirtyCollection
        }
        if isSearching {
            return .searchInFlight
        }
        if collectionSession.phase.inflightStatus == .refreshingHydratedSnapshot {
            return .refreshInFlight
        }
        if collectionSession.phase.inflightStatus == .writingBackRefreshedSnapshot {
            return .writeBackInFlight
        }
        if collectionSession.document?.url == nil {
            return .missingOpenedURL
        }
        if collectionContext == nil {
            return .missingCollectionContext
        }
        if collectionSession.metadata.baseline == nil {
            return .missingBaseline
        }

        return nil
    }

    mutating func applyNavigationStatePayload(_ payload: CollectionNavigationStatePayload) {
        collectionContext = payload.context
        collectionSession.document = payload.document
        collectionSession.metadata.baseline = payload.baseline
    }

    func makeNavigationPresentationPayload(
        context: CollectionContext? = nil,
        compatibility: CollectionFileCompatibilityMetadata? = nil,
    ) -> CollectionNavigationPresentationPayload {
        let resolvedContext = context ?? collectionContext ?? CollectionContext(query: "", scopes: [], conditions: [])
        let resolvedCompatibility = compatibility ?? collectionSession.document?.compatibility
        let kind: CollectionNavigationKindPayload
        if let url = collectionSession.document?.url {
            let name = collectionSession.document?.name ?? url.deletingPathExtension().lastPathComponent
            kind = .file(url: url, name: name)
        } else {
            kind = .temporary
        }
        return CollectionNavigationPresentationPayload(
            kind: kind,
            context: resolvedContext,
            compatibility: resolvedCompatibility,
        )
    }

    func makeBaselineHistoryNavigationPresentationPayload() -> CollectionNavigationPresentationPayload? {
        guard let baseline = collectionSession.metadata.baseline,
              let previousURL = collectionSession.document?.url
        else {
            return nil
        }

        let name = collectionSession.document?.name
            ?? previousURL.deletingPathExtension().lastPathComponent
        return CollectionNavigationPresentationPayload(
            kind: .file(url: previousURL, name: name),
            context: baseline.context,
            compatibility: collectionSession.document?.compatibility,
        )
    }

    mutating func completeWriteBack(_ completion: CollectionSaveCompletion) -> CollectionWriteBackNavigationPayload {
        let previousURL = collectionSession.document?.url
        let previousHistoryNavigation = makeBaselineHistoryNavigationPresentationPayload()
        let shouldAppendHistory = previousURL?.path != completion.url.path
        let compatibility = VoyagerCollectionFileCompatibilityOwner.compatibilityForCurrentFile(completion.file)

        if completion.file.snapshotMeta != nil,
           collectionSession.phase.openKind == .hydratedSnapshot,
           collectionSession.document?.url.standardizedFileURL.path == completion.url.standardizedFileURL.path
        {
            let refreshedAt = completion.file.snapshotMeta?.capturedAt ?? completion.file.updatedAt
            collectionSession.completeWriteBackSuccess(at: refreshedAt)
        }

        if collectionSession.document == nil {
            collectionSession.document = .init(
                url: completion.url,
                name: completion.url.deletingPathExtension().lastPathComponent,
                compatibility: compatibility,
            )
        } else {
            collectionSession.document?.url = completion.url
            collectionSession.document?.name = completion.url.deletingPathExtension().lastPathComponent
            collectionSession.document?.compatibility = compatibility
        }
        collectionSession.metadata.baseline = collectionContext.map(CollectionBaseline.init(context:))

        return CollectionWriteBackNavigationPayload(
            nextNavigation: makeNavigationPresentationPayload(compatibility: compatibility),
            previousHistoryNavigation: previousHistoryNavigation,
            shouldAppendHistory: shouldAppendHistory,
        )
    }

    mutating func makeOpenRestorationPayload(
        file: VoyagerCollectionFile,
        resolved: AppliedFiltersUtils.ResolutionResult,
        isStale: Bool,
        compatibility: CollectionFileCompatibilityMetadata,
    ) -> CollectionOpenRestorationPayload {
        let trimmedQuery = file.query.trimmingCharacters(in: .whitespacesAndNewlines)
        let restoredContext = restoredOpenContext(
            trimmedQuery: trimmedQuery,
            resolved: resolved,
            isStale: isStale,
            includeSubfolders: file.includeSubfolders,
        )
        let kind: CollectionSessionPhase.OpenKind = file.snapshotMeta == nil ? .definition : .hydratedSnapshot

        collectionSession.metadata.baseline = CollectionBaseline(context: restoredContext)
        refreshOpenedDocumentForRestoration(fileName: file.name, compatibility: compatibility)
        collectionSession.completeOpen(kind: kind, isStale: isStale, compatibility: compatibility)
        collectionContext = restoredContext

        return CollectionOpenRestorationPayload(
            context: restoredContext,
            compatibility: compatibility,
            navigation: makeNavigationPresentationPayload(
                context: restoredContext,
                compatibility: compatibility,
            ),
            shouldRestoreStaleNavigation: isStale,
            queryTrigger: makeOpenQueryTrigger(
                trimmedQuery: trimmedQuery,
                kind: kind,
                isStale: isStale,
            ),
            hydratedOpenPayload: makeHydratedOpenPayload(file: file, restoredContext: restoredContext),
            isEmptyDefinition: trimmedQuery.isEmpty
                && resolved.scopes.isEmpty
                && resolved.conditions.isEmpty,
            unsupportedFilterKeys: resolved.unknownKeys,
        )
    }

    private func restoredOpenContext(
        trimmedQuery: String,
        resolved: AppliedFiltersUtils.ResolutionResult,
        isStale: Bool,
        includeSubfolders: Bool,
    ) -> CollectionContext {
        let loadedContext = CollectionContext(
            query: trimmedQuery,
            scopes: resolved.scopes,
            includeSubfolders: includeSubfolders,
            conditions: resolved.conditions,
        )
        if isStale,
           let reopenContext = collectionSession.metadata.reopenContext
        {
            return reopenContext
        }
        return loadedContext
    }

    private mutating func refreshOpenedDocumentForRestoration(
        fileName: String,
        compatibility: CollectionFileCompatibilityMetadata,
    ) {
        guard let url = collectionSession.document?.url else {
            return
        }
        collectionSession.document = .init(
            url: url,
            name: fileName,
            compatibility: compatibility,
        )
    }

    private func makeHydratedOpenPayload(
        file: VoyagerCollectionFile,
        restoredContext: CollectionContext,
    ) -> CollectionHydratedOpenPayload? {
        guard let response = CollectionSnapshotHydration.syntheticSearchResponse(for: file),
              let items = response.items
        else {
            return nil
        }

        let snapshotPaths = items.compactMap { item -> String? in
            if case let .string(path) = item {
                return path
            }
            return nil
        }
        guard snapshotPaths.count == items.count else {
            return nil
        }

        return CollectionHydratedOpenPayload(
            lastFiltersResponse: response,
            lastSearchResponse: restoredContext.query.isEmpty ? nil : response,
            snapshotPaths: snapshotPaths,
        )
    }

    private func makeOpenQueryTrigger(
        trimmedQuery: String,
        kind: CollectionSessionPhase.OpenKind,
        isStale _: Bool,
    ) -> CollectionRefreshTriggerPayload? {
        guard kind == .definition else {
            return nil
        }
        return trimmedQuery.isEmpty ? .applyFilters : .submit
    }
}

struct CollectionSaveSnapshot: Equatable, Sendable {
    let query: String
    let scopes: [String]
    let includeSubfolders: Bool
    let conditions: [CollectionCondition]
    let snapshotItems: [VoyagerShared.JSONValue]?
    let definitionFingerprint: String
    let capturedAt: Date
    let relevanceRoots: [String]
}
