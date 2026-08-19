import ComposableArchitecture
import Foundation
import VoyagerEntitiesCollection
import VoyagerFeaturesComposer
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
    activeTabID: ContentTabID,
    state: inout FileManagerWindowState,
) -> [Effect<FileManagerWindowAction>]? {
    state.content.composer.applyHydratedCollectionOpenComposerPayload(
        payload,
        isNavigationQueryEmpty: navigation.context.query.isEmpty,
    )

    let showHidden = state.content.entryViewLayout.showHiddenFiles
    let priority = FileManagerContentEntryOpsCoordinator.rootMetadataPriority(
        for: state.content.entryViewLayout.entryArrangements,
    )
    let collectionURL: URL? = if case let .file(url, _) = navigation.kind { url } else { nil }

    return [
        .run { send in
            await send(.tabContent(
                tabID: activeTabID,
                action: .internal(.requestNavigation(.internal(.setNavigationState(.collection(navigation))))),
            ))
            await send(.tabContent(
                tabID: activeTabID,
                action: .internal(.applyNavigationState(.collection(navigation))),
            ))
            await send(.tabContent(
                tabID: activeTabID,
                action: .entryViewLayout(.internal(.setCollectionMode(true))),
            ))
            await send(.tabContent(tabID: activeTabID, action: .composer(.syncCollectionState(
                context: navigation.context,
                url: collectionURL,
                compatibility: navigation.compatibility,
                isCollectionMode: true,
            ))))
            await send(.tabContent(tabID: activeTabID, action: .entryViewLayout(
                .internal(.applyCollectionSearchPaths(
                    paths: payload.snapshotPaths,
                    showHidden: showHidden,
                    priority: priority,
                )),
            )))
            await send(.tabContent(tabID: activeTabID, action: .composer(.searchListApplied)))
        },
    ]
}

func makeHydratedCollectionOpenEffects(
    payload: CollectionOpenRestorationPayload,
    collectionAlertClient: CollectionAlertClient,
    state: inout FileManagerWindowState,
) -> [Effect<FileManagerWindowAction>]? {
    guard let activeTabID = state.contentTabs.activeTabID,
          let navigationPayload = payload.navigation,
          let hydratedOpenPayload = payload.hydratedOpenPayload,
          let hydrationEffects = hydrateOpenedCollectionSnapshot(
              payload: hydratedOpenPayload,
              navigation: makeWindowCollectionNavigation(navigationPayload, state: state),
              activeTabID: activeTabID,
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
       let activeTabID = state.contentTabs.activeTabID,
       let navigationPayload = payload.navigation
    {
        let navigation = makeWindowCollectionNavigation(navigationPayload, state: state)
        effects.append(contentsOf: [
            .send(.content(.internal(.requestNavigation(.internal(.setNavigationState(.collection(navigation))))))),
            .send(.tabContent(
                tabID: activeTabID,
                action: .internal(.applyNavigationState(.collection(navigation))),
            )),
            .send(.content(.entryViewLayout(.internal(.setCollectionMode(true))))),
            .send(.content(.composer(.syncCollectionState(
                context: navigation.context,
                url: collectionURL(from: navigation),
                compatibility: navigation.compatibility,
                isCollectionMode: true,
            )))),
        ])
    }

    if let trigger = payload.queryTrigger {
        let queryEffect: Effect<FileManagerWindowAction> = switch trigger {
        case .applyFilters:
            .send(.content(.composer(.applyFilters)))
        case .submit:
            .send(.content(.composer(.submit)))
        }
        effects.append(.send(.content(.internal(.setAutomaticRefreshFeedbackSuppressed(true)))))
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

private func collectionURL(from navigation: ContentPageCollectionNavigation) -> URL? {
    if case let .file(url, _) = navigation.kind {
        return url
    }
    return nil
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
