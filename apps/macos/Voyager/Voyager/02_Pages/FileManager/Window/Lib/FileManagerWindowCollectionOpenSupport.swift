import ComposableArchitecture
import Foundation
import VoyagerShared

struct CollectionOpenContext {
    let trimmedQuery: String
    let navigation: ContentPageCollectionNavigation?
}

func isEmptyCollectionDefinition(
    file: VoyagerCollectionFile,
    resolved: AppliedFiltersUtils.ResolutionResult,
) -> Bool {
    file.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && resolved.scopes.isEmpty
        && resolved.conditions.isEmpty
}

func prepareLoadedCollectionOpenState(
    file: VoyagerCollectionFile,
    resolved: AppliedFiltersUtils.ResolutionResult,
    isStale: Bool,
    registryClient: RegistryClient,
    state: inout FileManagerWindowState,
) -> CollectionOpenContext {
    let trimmedQuery = file.query.trimmingCharacters(in: .whitespacesAndNewlines)
    state.content.composer.pendingSearchQuery = trimmedQuery.isEmpty ? nil : trimmedQuery
    state.content.composer.text = ""
    state.content.composer.scopes = resolved.scopes
    state.content.composer.conditions = resolved.conditions
    state.content.composer.propertyPicker = ConditionPropertyPickerFeature.State()
    state.content.composer.operatorPicker = OperatorPickerFeature.State()
    state.content.composer.valuePicker = ValuePickerFeature.State()
    state.content.composer.clearHistory()
    let filters = buildFilters(from: state.content.composer)
    applyAppliedFilters(
        .init(scopes: filters.scopes, conditions: filters.conditions),
        state: &state.content.composer,
        registryClient: registryClient,
    )
    state.content.collectionSession.baseline = CollectionBaseline(
        context: CollectionContext(
            query: trimmedQuery,
            scopes: resolved.scopes,
            conditions: resolved.conditions,
        ),
    )
    state.content.collectionSession.didHydrateSnapshotOnOpen = false
    state.content.collectionSession.staleReason = isStale ? .invalidatedLocally : nil
    state.content.composer.lastFiltersResponse = nil
    state.content.composer.lastSearchResponse = nil

    return .init(
        trimmedQuery: trimmedQuery,
        navigation: makeSnapshotNavigation(resolved: resolved, state: state),
    )
}

func makeSnapshotNavigation(
    resolved: AppliedFiltersUtils.ResolutionResult,
    state: FileManagerWindowState,
) -> ContentPageCollectionNavigation? {
    guard let openedURL = state.content.collectionSession.openedURL else { return nil }

    return ContentPageCollectionNavigation(
        kind: .file(
            url: openedURL,
            name: state.content.collectionSession.openedName ?? openedURL.deletingPathExtension().lastPathComponent,
        ),
        context: .init(
            query: state.content.composer.pendingSearchQuery ?? "",
            scopes: resolved.scopes,
            conditions: resolved.conditions,
        ),
        sortKey: state.content.entryViewLayout.entryArrangements.sortKey,
        sortOrder: state.content.entryViewLayout.entryArrangements.sortOrder,
        viewLayout: state.content.entryViewLayout.mode,
    )
}

func hydrateOpenedCollectionSnapshot(
    file: VoyagerCollectionFile,
    navigation: ContentPageCollectionNavigation,
    isStale: Bool,
    state: inout FileManagerWindowState,
) -> [Effect<FileManagerWindowAction>]? {
    guard let response = CollectionSnapshotHydration.syntheticSearchResponse(for: file),
          let paths = snapshotPaths(from: response)
    else {
        return nil
    }

    state.content.composer.lastFiltersResponse = response
    state.content.composer.lastSearchResponse = navigation.context.query.isEmpty ? nil : response
    state.content.collectionSession.didHydrateSnapshotOnOpen = true
    state.content.collectionSession.staleReason = isStale ? .snapshotHydratedOnOpen : nil

    return [
        .send(.content(.internal(.applyNavigationState(.collection(navigation))))),
        .send(.content(.entryViewLayout(.internal(.applyCollectionSearchPaths(
            paths: paths,
            showHidden: state.content.entryViewLayout.showHiddenFiles,
        ))))),
        .send(.content(.internal(.syncComposerCollectionState))),
        .send(.content(.composer(.searchListApplied))),
    ]
}

func makeHydratedCollectionOpenEffects(
    file: VoyagerCollectionFile,
    openContext: CollectionOpenContext,
    resolved: AppliedFiltersUtils.ResolutionResult,
    isStale: Bool,
    collectionAlertClient: CollectionAlertClient,
    state: inout FileManagerWindowState,
) -> [Effect<FileManagerWindowAction>]? {
    guard let navigation = openContext.navigation,
          let hydrationEffects = hydrateOpenedCollectionSnapshot(
              file: file,
              navigation: navigation,
              isStale: isStale,
              state: &state,
          )
    else {
        return nil
    }

    var effects = hydrationEffects
    if isStale, !state.content.isOpenedCollectionDirty {
        state.content.collectionSession.isRefreshingHydratedSnapshot = true
        effects.append(
            openContext.trimmedQuery.isEmpty
                ? .send(.content(.composer(.applyFilters)))
                : .send(.content(.composer(.submit))),
        )
    }
    if !resolved.unknownKeys.isEmpty {
        effects.append(contentsOf: unsupportedFilterWarningEffects(
            unknownKeys: resolved.unknownKeys,
            collectionAlertClient: collectionAlertClient,
        ))
    }
    return effects
}

func snapshotPaths(from response: VoyagerShared.SearchResponsePayload) -> [String]? {
    guard let items = response.items else { return nil }
    var paths: [String] = []
    for item in items {
        guard case let .string(path) = item else { return nil }
        paths.append(path)
    }
    return paths
}

func unsupportedFilterWarningEffects(
    unknownKeys: [String],
    collectionAlertClient: CollectionAlertClient,
) -> [Effect<FileManagerWindowAction>] {
    guard !unknownKeys.isEmpty else { return [] }
    let joinedKeys = unknownKeys.joined(separator: ", ")
    let warningMessage = [
        "Some filters in this collection are no longer supported and were disabled:",
        "\(joinedKeys).",
    ].joined(separator: " ")
    return [
        .run { _ in
            await collectionAlertClient.showCollectionOpenErrorAlert("Unsupported Filters", warningMessage)
        },
    ]
}
