import ComposableArchitecture
import Foundation
import VoyagerEntitiesCollection
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryArrangements

func prepareLoadedCollectionOpenState(
    restorationPayload: CollectionOpenRestorationPayload,
    registryClient: RegistryClient,
    state: inout FileManagerWindowState,
) {
    state.content.composer.applyCollectionOpenRestorationComposerPayload(
        restorationPayload,
        registryClient: registryClient,
    )
}

func makeWindowCollectionNavigation(
    _ payload: CollectionNavigationPresentationPayload,
    state: FileManagerWindowState,
) -> ContentPageCollectionNavigation {
    let kind: ContentPageCollectionKind = switch payload.kind {
    case .temporary:
        .temporary
    case let .file(url, name):
        .file(url: url, name: name)
    }

    return ContentPageCollectionNavigation(
        kind: kind,
        context: payload.context,
        sortKey: state.content.entryViewLayout.entryArrangements.sortKey,
        sortOrder: state.content.entryViewLayout.entryArrangements.sortOrder,
        viewLayout: contentPageNavigationViewLayout(from: state.content.entryViewLayout.mode),
        compatibility: payload.compatibility,
    )
}

func hydrateOpenedCollectionSnapshot(
    payload: CollectionHydratedOpenPayload,
    navigation: ContentPageCollectionNavigation,
    state: inout FileManagerWindowState,
) -> [Effect<FileManagerWindowAction>]? {
    state.content.composer.applyHydratedCollectionOpenComposerPayload(payload, navigation: navigation)

    let showHidden = state.content.entryViewLayout.showHiddenFiles

    return [
        .run { send in
            await send(.content(.internal(.requestNavigation(.internal(.setNavigationState(.collection(navigation)))))))
            await send(.content(.internal(.applyNavigationState(.collection(navigation)))))
            await send(.content(.entryViewLayout(.internal(.setCollectionMode(true)))))
            await send(.content(.entryViewLayout(.internal(.applyCollectionSearchPaths(
                paths: payload.snapshotPaths,
                showHidden: showHidden,
            )))))
            await send(.content(.internal(.syncComposerCollectionState)))
            await send(.content(.composer(.searchListApplied)))
        },
    ]
}

func makeHydratedCollectionOpenEffects(
    payload: CollectionOpenRestorationPayload,
    collectionAlertClient: CollectionAlertClient,
    state: inout FileManagerWindowState,
) -> [Effect<FileManagerWindowAction>]? {
    guard let navigationPayload = payload.navigation,
          let hydratedOpenPayload = payload.hydratedOpenPayload,
          let hydrationEffects = hydrateOpenedCollectionSnapshot(
              payload: hydratedOpenPayload,
              navigation: makeWindowCollectionNavigation(navigationPayload, state: state),
              state: &state,
          )
    else {
        return nil
    }

    var effects = hydrationEffects
    if !payload.unsupportedFilterKeys.isEmpty {
        effects.append(contentsOf: unsupportedFilterWarningEffects(
            unknownKeys: payload.unsupportedFilterKeys,
            collectionAlertClient: collectionAlertClient,
        ))
    }
    return effects
}

func makeCollectionOpenFollowupEffects(
    payload: CollectionOpenRestorationPayload,
    collectionAlertClient: CollectionAlertClient,
    state: FileManagerWindowState,
) -> [Effect<FileManagerWindowAction>] {
    var effects: [Effect<FileManagerWindowAction>] = []

    if payload.shouldRestoreStaleNavigation,
       let navigationPayload = payload.navigation
    {
        let navigation = makeWindowCollectionNavigation(navigationPayload, state: state)
        effects.append(contentsOf: [
            .send(.content(.internal(.requestNavigation(.internal(.setNavigationState(.collection(navigation))))))),
            .send(.content(.internal(.applyNavigationState(.collection(navigation))))),
            .send(.content(.entryViewLayout(.internal(.setCollectionMode(true))))),
        ])
    }

    if let trigger = payload.queryTrigger {
        let queryEffect: Effect<FileManagerWindowAction> = switch trigger {
        case .applyFilters:
            .send(.content(.composer(.applyFilters)))
        case .submit:
            .send(.content(.composer(.submit)))
        }
        effects.append(queryEffect)
    }

    if !payload.unsupportedFilterKeys.isEmpty {
        effects.append(contentsOf: unsupportedFilterWarningEffects(
            unknownKeys: payload.unsupportedFilterKeys,
            collectionAlertClient: collectionAlertClient,
        ))
    }

    return effects
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
