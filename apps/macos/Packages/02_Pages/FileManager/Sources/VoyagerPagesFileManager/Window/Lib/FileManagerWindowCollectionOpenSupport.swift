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
    state.content.entryViewLayout.collectionItems = []
    state.content.entryViewLayout.entries = []
    state.content.entryViewLayout.selectedIds = []
    state.content.entryViewLayout.lastSelectedId = nil
    state.content.entryViewLayout.rangeAnchorId = nil
    state.content.entryViewLayout.shouldScrollToSelection = false
    state.content.entryViewLayout.isCollectionMode = true
    state.content.entryViewLayout.isCollectionContentLoading = false
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

    if let activeTabID = state.contentTabs.activeTabID,
       let navigationPayload = payload.navigation
    {
        if payload.queryTrigger == nil {
            effects.append(contentsOf: makeNoTriggerCollectionNavigationEffects(
                navigationPayload: navigationPayload,
                activeTabID: activeTabID,
                state: state,
            ))
        } else if payload.shouldRestoreStaleNavigation {
            let navigation = makeWindowCollectionNavigation(navigationPayload, state: state)
            effects.append(contentsOf: [
                .send(.content(.internal(.requestNavigation(
                    .internal(.setNavigationState(.collection(navigation))),
                )))),
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

private func makeNoTriggerCollectionNavigationEffects(
    navigationPayload: CollectionNavigationPresentationPayload,
    activeTabID: ContentTabID,
    state: FileManagerWindowState,
) -> [Effect<FileManagerWindowAction>] {
    let navigation = makeWindowCollectionNavigation(navigationPayload, state: state)
    let collectionStatePayload = CollectionNavigationStatePayload(
        context: navigation.context,
        document: collectionURL(from: navigation).map {
            CollectionOpenedDocumentState(
                url: $0,
                name: navigationPayloadName(navigationPayload),
                compatibility: navigation.compatibility,
            )
        },
        baseline: CollectionBaseline(context: navigation.context),
        composerText: navigation.context.query,
        scopes: navigation.context.scopes,
        excludedScopes: navigation.context.excludedScopes,
        conditions: navigation.context.conditions,
    )
    return [
        .send(.tabContent(
            tabID: activeTabID,
            action: .internal(.requestNavigation(.internal(.setNavigationState(.collection(navigation))))),
        )),
        .send(.tabContent(tabID: activeTabID, action: .internal(.applyNavigationState(.collection(navigation))))),
        .send(.tabContent(
            tabID: activeTabID,
            action: .collection(.navigationStateApplied(collectionStatePayload)),
        )),
        .send(.tabContent(
            tabID: activeTabID,
            action: .composer(.applyCollectionNavigationComposer(collectionStatePayload)),
        )),
        .send(.tabContent(tabID: activeTabID, action: .entryViewLayout(.internal(.setCollectionMode(true))))),
        .send(.tabContent(tabID: activeTabID, action: .composer(.syncCollectionState(
            context: navigation.context,
            url: collectionURL(from: navigation),
            compatibility: navigation.compatibility,
            isCollectionMode: true,
        )))),
        .send(.tabContent(tabID: activeTabID, action: .entryViewLayout(.entryArrangements(.reapply)))),
    ]
}

private func collectionURL(from navigation: ContentPageCollectionNavigation) -> URL? {
    if case let .file(url, _) = navigation.kind {
        return url
    }
    return nil
}

private func navigationPayloadName(_ payload: CollectionNavigationPresentationPayload) -> String {
    switch payload.kind {
    case .temporary:
        ""
    case let .file(_, name):
        name
    }
}

enum CollectionOpenMetricResultStatus: String {
    case validEmpty = "valid_empty"
    case loadFailure = "load_failure"
}

func collectionOpenMetricEffect(
    metricsClient: MetricsClient,
    resultStatus: CollectionOpenMetricResultStatus,
    errorCategory: ContentPageNavigationErrorCategory? = nil,
) -> Effect<FileManagerWindowAction> {
    var tags = ["result_status": resultStatus.rawValue]
    if let errorCategory {
        tags["error_category"] = errorCategory.rawValue
    }
    let metricTags = tags
    return .run { _ in
        metricsClient.logMetric("collection.open", 1, metricTags)
    }
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
