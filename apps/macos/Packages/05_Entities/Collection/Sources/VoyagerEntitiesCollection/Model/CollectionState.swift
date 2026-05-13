import ComposableArchitecture
import Foundation
import VoyagerShared

@ObservableState
public struct CollectionState: Equatable {
    public var pendingSave: CollectionSaveSnapshot?
    public var isSaving: Bool = false

    public var collectionSession: CollectionDocumentSessionState = .init()
    public var collectionContext: CollectionContext?

    public init(
        pendingSave: CollectionSaveSnapshot? = nil,
        isSaving: Bool = false,
        collectionSession: CollectionDocumentSessionState = .init(),
        collectionContext: CollectionContext? = nil
    ) {
        self.pendingSave = pendingSave
        self.isSaving = isSaving
        self.collectionSession = collectionSession
        self.collectionContext = collectionContext
    }
}

public extension CollectionState {
    var isDirty: Bool {
        guard let baseline = collectionSession.metadata.baseline,
              let context = collectionContext
        else { return false }
        return baseline.context != context
    }

    func canSave(isCollectionMode: Bool) -> Bool {
        guard isCollectionMode, collectionContext != nil else {
            return false
        }
        if collectionSession.metadata.baseline == nil {
            return true
        }
        return isDirty
    }

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
            conditions: []
        )
    }

    mutating func applyRefreshResponse(wasDirtyBeforeApplyingResponse: Bool) -> Bool {
        guard collectionSession.phase.isInflightRefresh else {
            return false
        }
        if !shouldWriteBackAfterRefresh(wasDirtyBeforeApplyingResponse: wasDirtyBeforeApplyingResponse) {
            collectionSession.finishRefreshWithoutWriteBack()
            return false
        }
        collectionSession.beginWriteBackAfterRefresh()
        return true
    }

    func shouldWriteBackAfterRefresh(wasDirtyBeforeApplyingResponse: Bool) -> Bool {
        guard collectionSession.phase.isInflightRefresh else {
            return false
        }
        let writeBackAllowed = collectionSession.document?.compatibility?.writeBackAllowed != false
        return !wasDirtyBeforeApplyingResponse && writeBackAllowed
    }

    func refreshBlockingReason(
        isCollectionMode: Bool,
        isDirty: Bool,
        isSearching: Bool
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
        if collectionSession.phase.isInflightRefresh {
            return .refreshInFlight
        }
        if collectionSession.phase.isInflightWriteBack {
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
        compatibility: CollectionFileCompatibilityMetadata? = nil
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
            compatibility: resolvedCompatibility
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
            compatibility: collectionSession.document?.compatibility
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
                compatibility: compatibility
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
            shouldAppendHistory: shouldAppendHistory
        )
    }

    mutating func makeOpenRestorationPayload(
        file: VoyagerCollectionFile,
        resolved: AppliedFiltersUtils.ResolutionResult,
        isStale: Bool,
        compatibility: CollectionFileCompatibilityMetadata
    ) -> CollectionOpenRestorationPayload {
        let trimmedQuery = file.query.trimmingCharacters(in: .whitespacesAndNewlines)
        let restoredContext = restoredOpenContext(
            trimmedQuery: trimmedQuery,
            resolved: resolved,
            isStale: isStale
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
                compatibility: compatibility
            ),
            shouldRestoreStaleNavigation: isStale,
            queryTrigger: makeOpenQueryTrigger(
                trimmedQuery: trimmedQuery,
                kind: kind,
                isStale: isStale
            ),
            hydratedOpenPayload: makeHydratedOpenPayload(file: file, restoredContext: restoredContext),
            isEmptyDefinition: trimmedQuery.isEmpty
                && resolved.scopes.isEmpty
                && resolved.conditions.isEmpty,
            unsupportedFilterKeys: resolved.unknownKeys
        )
    }

    private func restoredOpenContext(
        trimmedQuery: String,
        resolved: AppliedFiltersUtils.ResolutionResult,
        isStale: Bool
    ) -> CollectionContext {
        let loadedContext = CollectionContext(
            query: trimmedQuery,
            scopes: resolved.scopes,
            conditions: resolved.conditions
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
        compatibility: CollectionFileCompatibilityMetadata
    ) {
        guard let url = collectionSession.document?.url else {
            return
        }
        collectionSession.document = .init(
            url: url,
            name: fileName,
            compatibility: compatibility
        )
    }

    private func makeHydratedOpenPayload(
        file: VoyagerCollectionFile,
        restoredContext: CollectionContext
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
            snapshotPaths: snapshotPaths
        )
    }

    private func makeOpenQueryTrigger(
        trimmedQuery: String,
        kind: CollectionSessionPhase.OpenKind,
        isStale _: Bool
    ) -> CollectionRefreshTriggerPayload? {
        guard kind == .definition else {
            return nil
        }
        return trimmedQuery.isEmpty ? .applyFilters : .submit
    }
}

public struct CollectionSaveSnapshot: Equatable, Sendable {
    public let query: String
    public let scopes: [String]
    public let conditions: [CollectionCondition]
    public let snapshotItems: [VoyagerShared.JSONValue]?
    public let definitionFingerprint: String
    let capturedAt: Date
    let relevanceRoots: [String]
}
